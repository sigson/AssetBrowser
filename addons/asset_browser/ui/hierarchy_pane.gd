tool
extends VBoxContainer
class_name ABHierarchyPane

# ФТ-2: ленивое и инкрементальное построение иерархии директорий.

signal dir_selected(dir)

const DUMMY_META = "::lazy_dummy::"

var _s = null
var _tree = null
var _ctx_menu = null
var _del_dlg = null
var _ctx_dir = null
var _pending_delete = null

var _suppress_select = false
var _mutating = false
var _expanded = {"res://": true}

var _items = {}          # path -> TreeItem
var _materialized = {}   # path -> true

var _root_dir_item = null
var _fav_items = []
var _selected_dir = "res://"

var _refresh_timer = null
var _last_refresh_ms = -100000.0
var _force_full = false

func build(shared):
    _s = shared
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL

    _tree = Tree.new()
    _tree.hide_root = true
    _tree.allow_rmb_select = true
    _tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tree.connect("item_selected", self, "on_selected")
    _tree.connect("item_rmb_selected", self, "on_rmb")
    _tree.connect("item_collapsed", self, "on_item_collapsed")
    add_child(_tree)

    _ctx_menu = PopupMenu.new()
    _ctx_menu.connect("id_pressed", self, "on_ctx_menu")
    add_child(_ctx_menu)

    _del_dlg = ConfirmationDialog.new()
    _del_dlg.window_title = "Delete folder"
    _del_dlg.connect("confirmed", self, "on_delete_confirmed")
    add_child(_del_dlg)

    _refresh_timer = Timer.new()
    _refresh_timer.one_shot = true
    _refresh_timer.connect("timeout", self, "on_refresh_timer")
    add_child(_refresh_timer)

    _s.favorites.connect("changed", self, "on_favorites_changed")

    _force_full = true
    _do_refresh()

func _now_ms():
    return OS.get_ticks_msec()

func _dir_icon():
    var n = ABAssetNode.new()
    n.is_dir = true
    return _s.thumbs.get_type_icon(n)

func on_favorites_changed():
    _force_full = true
    _do_refresh()

# ---------- коалесцирование ----------
func refresh():
    var min_ms = _s.settings.tree_refresh_min_ms
    if min_ms <= 0:
        _do_refresh()
        return

    var now = _now_ms()
    if now - _last_refresh_ms >= min_ms and _refresh_timer.is_stopped():
        _do_refresh()
        return
    if _refresh_timer.is_stopped():
        var wait = max(0.01, (min_ms - (now - _last_refresh_ms)) / 1000.0)
        _refresh_timer.start(wait)

func on_refresh_timer():
    _do_refresh()

func _do_refresh():
    _last_refresh_ms = _now_ms()
    var full = _force_full \
        or _s.settings.rebuild_mode == ABSettings.TreeRebuildMode.FULL \
        or _root_dir_item == null \
        or not is_instance_valid(_root_dir_item)
    _force_full = false

    var prev_mut = _mutating
    _mutating = true
    if full:
        _full_rebuild()
    else:
        _incremental_rebuild()

    if _selected_dir != null and _selected_dir != "":
        select_dir(_selected_dir)

    _mutating = prev_mut
    _suppress_select = false

# ---------- полный ребилд (lazy) ----------
func _full_rebuild():
    _suppress_select = true
    _tree.clear()
    _items.clear()
    _materialized.clear()
    _fav_items.clear()
    _root_dir_item = null

    var root = _tree.create_item()

    var fav_dirs = _s.favorites.dirs()
    if fav_dirs.size() > 0:
        var fav_header = _tree.create_item(root)
        fav_header.set_text(0, "FAVORITES")
        fav_header.set_selectable(0, false)
        fav_header.set_custom_color(0, Color(0.6, 0.6, 0.6))
        _fav_items.append(fav_header)
        for f in fav_dirs:
            var it = _tree.create_item(root)
            it.set_text(0, f.substr(f.find_last("/") + 1) + "/")
            it.set_metadata(0, "fav:" + f)
            it.set_icon(0, _dir_icon())
            _fav_items.append(it)
        var sep = _tree.create_item(root)
        sep.set_text(0, "----------")
        sep.set_selectable(0, false)
        _fav_items.append(sep)

    _root_dir_item = _tree.create_item(root)
    _root_dir_item.set_text(0, "res://")
    _root_dir_item.set_metadata(0, "res://")
    _root_dir_item.set_icon(0, _dir_icon())
    _items["res://"] = _root_dir_item
    _root_dir_item.collapsed = false
    _materialize_children(_root_dir_item, "res://")

    _suppress_select = false

func _materialize_children(item, path):
    if _materialized.has(path):
        return
    _remove_dummy(item)
    for n in _s.db.get_subdirs(path):
        _build_dir_node(item, n)
    _materialized[path] = true
    _expanded[path] = true

func _build_dir_node(parent, n):
    var it = _tree.create_item(parent)
    it.set_text(0, n.name)
    it.set_metadata(0, n.path)
    it.set_icon(0, _s.thumbs.get_type_icon(n))
    _items[n.path] = it

    var want_expanded = _expanded.has(n.path) and _s.settings.lazy_subdirs == true
    var lazy = _s.settings.lazy_subdirs

    if _s.db.has_subdirs(n.path):
        if not lazy or want_expanded:
            it.collapsed = not _expanded.has(n.path)
            _materialize_children(it, n.path)
        else:
            _add_dummy(it)
            it.collapsed = true
    return it

func _add_dummy(parent):
    var d = _tree.create_item(parent)
    d.set_text(0, "")
    d.set_metadata(0, DUMMY_META)
    d.set_selectable(0, false)

func _remove_dummy(item):
    var c = item.get_children()
    while c != null:
        var next = c.get_next()
        var s = c.get_metadata(0)
        if typeof(s) == TYPE_STRING and s == DUMMY_META:
            c.free()
        c = next

# ---------- инкрементальный ребилд ----------
func _incremental_rebuild():
    _suppress_select = true
    _sync_children(_root_dir_item, "res://")
    _suppress_select = false

func _sync_children(item, path):
    if item == null or not is_instance_valid(item):
        return
    if not _materialized.has(path):
        _update_leaf_state(item, path)
        return

    var desired = {}
    for n in _s.db.get_subdirs(path):
        desired[n.path] = n

    var existing = {}
    var c = item.get_children()
    while c != null:
        var next = c.get_next()
        var s = c.get_metadata(0)
        if typeof(s) == TYPE_STRING and s != DUMMY_META and not s.begins_with("fav:"):
            if desired.has(s):
                existing[s] = c
            else:
                _forget_subtree(c)
                c.free()
        c = next

    for key in desired.keys():
        if not existing.has(key):
            _build_dir_node(item, desired[key])

    for key in existing.keys():
        _update_leaf_state(existing[key], key)
        if _materialized.has(key):
            _sync_children(existing[key], key)

func _update_leaf_state(item, path):
    if _materialized.has(path):
        return
    var has = _s.db.has_subdirs(path)
    var has_dummy = _has_dummy(item)
    if has and not has_dummy and _s.settings.lazy_subdirs:
        _add_dummy(item)
    elif not has and has_dummy:
        _remove_dummy(item)

func _has_dummy(item):
    var c = item.get_children()
    while c != null:
        var s = c.get_metadata(0)
        if typeof(s) == TYPE_STRING and s == DUMMY_META:
            return true
        c = c.get_next()
    return false

func _forget_subtree(item):
    var s = item.get_metadata(0)
    if typeof(s) == TYPE_STRING and s != DUMMY_META and not s.begins_with("fav:"):
        _items.erase(s)
        _materialized.erase(s)
        _expanded.erase(s)
    var c = item.get_children()
    while c != null:
        _forget_subtree(c)
        c = c.get_next()

# ---------- разворачивание ----------
func on_item_collapsed(item_obj):
    if _mutating:
        return
    var item = item_obj as TreeItem
    if item == null:
        return
    var path = item.get_metadata(0)
    if typeof(path) != TYPE_STRING or path == DUMMY_META or path.begins_with("fav:"):
        return

    if not item.collapsed:
        _expanded[path] = true
        if not _materialized.has(path):
            call_deferred("materialize_path_deferred", path)
    else:
        _expanded.erase(path)

func materialize_path_deferred(path):
    if not _items.has(path):
        return
    var item = _items[path]
    if not is_instance_valid(item):
        return
    if _materialized.has(path):
        return
    var prev_mut = _mutating
    _mutating = true
    _materialize_children(item, path)
    _mutating = prev_mut

# ---------- выбор директории ----------
func select_dir(dir):
    dir = ABAssetDatabase.normalize(dir)
    _selected_dir = dir

    var prev_mut = _mutating
    _mutating = true
    _ensure_path_materialized(dir)

    var it = _items[dir] if _items.has(dir) else _find_item(_tree.get_root(), dir)
    if it == null or not is_instance_valid(it):
        _mutating = prev_mut
        _suppress_select = false
        return

    var p = it.get_parent()
    while p != null:
        p.collapsed = false
        var s = p.get_metadata(0)
        if typeof(s) == TYPE_STRING and s != DUMMY_META:
            _expanded[s] = true
        p = p.get_parent()

    _suppress_select = true
    it.select(0)

    _mutating = prev_mut
    _suppress_select = false

func _ensure_path_materialized(dir):
    if _root_dir_item == null or not is_instance_valid(_root_dir_item):
        return
    _materialize_children(_root_dir_item, "res://")
    if dir == "res://":
        return

    var rel = _trim_slashes(dir.substr(6))
    if rel.length() == 0:
        return

    var acc = "res://"
    var cur = _root_dir_item
    for seg in rel.split("/"):
        if seg.length() == 0:
            continue
        acc = "res://" + seg if acc == "res://" else acc + "/" + seg
        if not _items.has(acc):
            return
        cur = _items[acc]
        if not is_instance_valid(cur):
            return
        _materialize_children(cur, acc)

func _trim_slashes(s):
    while s.begins_with("/"):
        s = s.substr(1)
    while s.ends_with("/"):
        s = s.substr(0, s.length() - 1)
    return s

func _find_item(from, dir):
    if from == null:
        return null
    var child = from.get_children()
    while child != null:
        var md = child.get_metadata(0)
        if typeof(md) == TYPE_STRING and md == dir:
            return child
        var deep = _find_item(child, dir)
        if deep != null:
            return deep
        child = child.get_next()
    return null

func on_selected():
    if _suppress_select:
        return
    var it = _tree.get_selected()
    if it == null:
        return
    var md = it.get_metadata(0)
    if typeof(md) == TYPE_STRING and md != DUMMY_META:
        _selected_dir = _strip_fav(md)
        call_deferred("emit_dir_selected", _selected_dir)

func emit_dir_selected(dir):
    emit_signal("dir_selected", dir)

func _strip_fav(md):
    return md.substr(4) if md.begins_with("fav:") else md

func on_rmb(_pos):
    var it = _tree.get_selected()
    if it == null:
        return
    var md = it.get_metadata(0)
    if typeof(md) != TYPE_STRING or md == DUMMY_META:
        return

    var is_fav = md.begins_with("fav:")
    var dir = _strip_fav(md)
    _ctx_dir = dir

    var is_root = ABAssetDatabase.normalize(dir) == "res://"
    var is_fav_dir = _s.favorites.contains(dir)

    _ctx_menu.clear()
    _ctx_menu.add_item("Open", 5)
    _ctx_menu.add_item("New Folder", 1)
    if not is_root:
        _ctx_menu.add_item("Delete Folder", 2)
    _ctx_menu.add_separator()
    if is_fav or is_fav_dir:
        _ctx_menu.add_item("Remove from Favorites", 4)
    else:
        _ctx_menu.add_item("Add to Favorites", 3)

    _ctx_menu.set_global_position(get_global_mouse_position())
    _ctx_menu.popup()

func on_ctx_menu(id):
    if _ctx_dir == null:
        return
    match id:
        5:
            emit_signal("dir_selected", _ctx_dir)
        1:
            ABFileOps.make_folder(_ctx_dir + "/New Folder")
            _s.db.request_scan()
        2:
            _pending_delete = _ctx_dir
            _del_dlg.dialog_text = "Delete folder \"%s\" and all its contents? This cannot be undone." % _ctx_dir
            _del_dlg.popup_centered()
        3:
            _s.favorites.add(_ctx_dir)
        4:
            _s.favorites.remove(_ctx_dir)

func on_delete_confirmed():
    if _pending_delete == null:
        return
    if _s.favorites.contains(_pending_delete):
        _s.favorites.remove(_pending_delete)
    ABFileOps.delete_path(_pending_delete)
    _pending_delete = null
    _s.db.request_scan()
