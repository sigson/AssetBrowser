tool
extends Node
class_name ABImportBridge

# Окно Import в Godot 3 обновляет FileSystemDock._update_import_dock(), и источник
# выделения там зависит от режима отображения дока:
#   DISPLAY_MODE_TREE_ONLY -> читает выделение из Tree
#   split-режим            -> читает выделение из списка файлов (ItemList)
# Режим наружу не экспонирован (get_display_mode() в ClassDB нет), поэтому
# выделение проставляется в ОБА виджета — какой бы док ни прочитал, он прочитает верный.
#
# Флаг обновления взводится вызовом _file_multi_selected/_tree_multi_selected:
# по данным ClassDB это забинденные методы, они сами делают call_deferred на
# _update_import_dock(). Если их вдруг нет — откатываемся на эмит штатных сигналов.
#
# Синк только для групп (2+ файла) — одиночный клик док не трогает.

signal note(text)

const MIN_GROUP = 2

var _s = null
var _pending = []
var _debounce = null
var _settle = null
var _dock = null
var _want = []
var _verbose = false

func build(shared):
    _s = shared

    _debounce = Timer.new()
    _debounce.one_shot = true
    _debounce.wait_time = 0.15
    _debounce.connect("timeout", self, "_flush")
    add_child(_debounce)

    # navigate_to_path перестраивает дерево и список отложенно —
    # выделение накладываем через кадр.
    _settle = Timer.new()
    _settle.one_shot = true
    _settle.wait_time = 0.05
    _settle.connect("timeout", self, "_apply_selection")
    add_child(_settle)

func push_selection(paths):
    _verbose = false
    _pending = []
    for p in paths:
        _pending.append(p)
    _debounce.stop()
    _debounce.start()

# Явная отправка по кнопке: без дебаунса, без порога группы и с подробным
# отчётом на каждом шаге — чтобы было видно, где именно обрывается цепочка.
func push_now(paths):
    _pending = []
    for p in paths:
        _pending.append(p)
    _verbose = true
    _debounce.stop()
    _flush()

# ---------- основной поток ----------
func _flush():
    var files = _files_only(_pending)
    if files.size() == 0:
        _set_note("import: нечего отправлять (выделены только папки?)")
        return
    if not _verbose and files.size() < MIN_GROUP:
        _set_note("")
        return

    var dock = _fs_dock()
    if dock == null:
        _set_note("import: FileSystemDock не найден")
        return
    if not dock.has_method("navigate_to_path"):
        _set_note("import: FileSystemDock без navigate_to_path")
        return

    _dock = dock
    _want = files

    # Ведём док в папку самой большой однопапочной группы: список файлов держит
    # только одну директорию, дерево же может добрать остальные.
    dock.navigate_to_path(_anchor_file(files))
    _settle.stop()
    _settle.start()

func _anchor_file(files):
    var by_dir = {}
    for p in files:
        var d = ABAssetDatabase.parent_dir(p)
        if not by_dir.has(d):
            by_dir[d] = []
        by_dir[d].append(p)

    var best = []
    for d in by_dir.keys():
        if by_dir[d].size() > best.size():
            best = by_dir[d]
    return best[0]

func _files_only(paths):
    var d = Directory.new()
    var out = []
    for p in paths:
        if typeof(p) != TYPE_STRING:
            continue
        if d.dir_exists(p):
            continue
        if d.file_exists(p):
            out.append(p)
    return out

# ---------- проставление выделения ----------
func _apply_selection():
    if _dock == null or not is_instance_valid(_dock) or _want.size() == 0:
        return

    var want = {}
    for p in _want:
        want[p] = true

    var in_list = _select_in_list(_dock, want)
    var in_tree = _select_in_tree(_dock, want)

    if _verbose:
        # Полная картина в Output: видно, нашлись ли виджеты, сколько элементов
        # выделено в каждом и есть ли методы, взводящие флаг обновления Import.
        print("[AssetBrowser] import: запрошено=", _want.size(),
            " список=", ("нет виджета" if in_list < 0 else str(in_list)),
            " дерево=", ("нет виджета" if in_tree < 0 else str(in_tree)),
            " | _file_multi_selected=", _dock.has_method("_file_multi_selected"),
            " _tree_multi_selected=", _dock.has_method("_tree_multi_selected"),
            " _update_import_dock=", _dock.has_method("_update_import_dock"),
            " | док виден=", _dock.is_visible_in_tree())

    if in_list < 0 and in_tree < 0:
        _set_note("import: виджеты FileSystemDock не найдены")
        return
    if in_list <= 0 and in_tree <= 0:
        _set_note("import: 0 из %d — док не показывает эти файлы" % _want.size())
        return

    var best = max(in_list, in_tree)
    if best < _want.size():
        _set_note("import: %d из %d (док показывает не все)" % [best, _want.size()])
    elif _verbose:
        _set_note("import: отправлено %d (список %d / дерево %d)" % [best, max(0, in_list), max(0, in_tree)])
    else:
        _set_note("")

# Возвращает число выделенных элементов, либо -1 если виджета нет.
func _select_in_list(dock, want):
    var list = _find_widget(dock, "ItemList")
    if list == null:
        return -1

    list.unselect_all()   # снять то, что док выделил сам при navigate_to_path

    var last = -1
    var hit = 0
    for i in range(list.get_item_count()):
        var md = list.get_item_metadata(i)
        if typeof(md) != TYPE_STRING or not want.has(md):
            continue
        list.select(i, false)   # false => копить, а не заменять
        last = i
        hit += 1

    if last < 0:
        return 0

    # Программный select() сигналов не шлёт — взводим флаг обновления вручную.
    if dock.has_method("_file_multi_selected"):
        dock.call("_file_multi_selected", last, true)
    else:
        list.emit_signal("multi_selected", last, true)
    return hit

func _select_in_tree(dock, want):
    var tree = _find_widget(dock, "Tree")
    if tree == null:
        return -1

    var found = []
    _walk_tree(tree.get_root(), want, found)

    # В Godot 3 у Tree нет deselect_all() — снимаем поэлементно, иначе прежний
    # выбор дока подмешается в окно Import.
    _deselect_tree(tree.get_root(), tree.columns)
    if found.size() == 0:
        return 0

    for it in found:
        it.select(0)

    if dock.has_method("_tree_multi_selected"):
        dock.call("_tree_multi_selected", found[found.size() - 1], 0, true)
    else:
        tree.emit_signal("multi_selected", found[found.size() - 1], 0, true)
    return found.size()

# ---------- обход ----------
# TreeItem.get_children() в Godot 3 возвращает ПЕРВОГО потомка, не массив.
func _walk_tree(item, want, found):
    while item != null:
        var md = item.get_metadata(0)
        if typeof(md) == TYPE_STRING and want.has(md):
            found.append(item)
        _walk_tree(item.get_children(), want, found)
        item = item.get_next()

func _deselect_tree(item, columns):
    while item != null:
        for c in range(max(1, columns)):
            item.deselect(c)
        _deselect_tree(item.get_children(), columns)
        item = item.get_next()

# ---------- поиск виджетов дока ----------
func _fs_dock():
    if _s == null or _s.editor == null:
        return null
    if not _s.editor.has_method("get_file_system_dock"):
        return null
    var dock = _s.editor.get_file_system_dock()
    return dock if (dock != null and is_instance_valid(dock)) else null

# Обход в ширину; поддеревья попапов пропускаем — внутри диалогов дока
# есть собственные Tree/ItemList, которые нам не нужны.
func _find_widget(root, cls):
    var queue = [root]
    while queue.size() > 0:
        var n = queue.pop_front()
        for c in n.get_children():
            if c is Popup:
                continue
            if c.is_class(cls):
                return c
            queue.append(c)
    return null

func _set_note(text):
    emit_signal("note", text)
