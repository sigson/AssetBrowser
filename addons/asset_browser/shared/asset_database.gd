@tool
extends RefCounted
class_name ABAssetDatabase

signal tree_changed()
signal preview_invalidated(path)

var _editor = null
var _fs = null
var _prev = null
var _settings = null
var _tags = null
var _connected = false

# ФТ-1: Init идемпотентен и учитывает scan_mode.
func init(editor, settings):
    _editor = editor
    _settings = settings
    _fs = editor.get_resource_filesystem()   # singleton, НЕ инстанцировать новый
    _prev = editor.get_resource_previewer()

    shutdown()   # снять прежние подписки (идемпотентность)

    var event_driven = _settings == null or _settings.scan_mode != ABSettings.ScanMode.POLL_ONLY
    if event_driven:
        _fs.connect("filesystem_changed", Callable(self, "on_fs_changed"))
        _fs.connect("resources_reimported", Callable(self, "on_reimported"))
        _fs.connect("sources_changed", Callable(self, "on_sources_changed"))
    _prev.connect("preview_invalidated", Callable(self, "on_preview_invalidated"))
    _connected = true

func set_tag_store(tags):
    _tags = tags

func shutdown():
    if not _connected:
        return
    if _fs != null:
        if _fs.is_connected("filesystem_changed", Callable(self, "on_fs_changed")):
            _fs.disconnect("filesystem_changed", Callable(self, "on_fs_changed"))
        if _fs.is_connected("resources_reimported", Callable(self, "on_reimported")):
            _fs.disconnect("resources_reimported", Callable(self, "on_reimported"))
        if _fs.is_connected("sources_changed", Callable(self, "on_sources_changed")):
            _fs.disconnect("sources_changed", Callable(self, "on_sources_changed"))
    if _prev != null and _prev.is_connected("preview_invalidated", Callable(self, "on_preview_invalidated")):
        _prev.disconnect("preview_invalidated", Callable(self, "on_preview_invalidated"))
    _connected = false

func emit_tree_changed():
    emit_signal("tree_changed")

# --- scan ---
func is_scanning():
    return _fs.is_scanning()

func scan_progress():
    return _fs.get_scanning_progress()

func request_scan():
    if not _fs.is_scanning():
        _fs.scan()

# --- signals ---
func on_fs_changed():
    emit_signal("tree_changed")

func on_reimported(_resources):
    emit_signal("tree_changed")

func on_sources_changed(_exist):
    emit_signal("tree_changed")

func on_preview_invalidated(path):
    emit_signal("preview_invalidated", path)

# --- queries ---
func file_type(path):
    var t = _fs.get_file_type(path)
    return "Resource" if (t == null or t == "") else t

func find_dir(dir_path):
    dir_path = normalize(dir_path)
    var root = _fs.get_filesystem()
    if dir_path == "res://" or dir_path == "res:/":
        return root

    var rel = _strip_res(dir_path).strip_edges()
    if rel.length() == 0:
        return root

    var cur = root
    for seg in rel.split("/"):
        if seg == "":
            continue
        var idx = cur.find_dir_index(seg)
        if idx < 0:
            return null
        cur = cur.get_subdir(idx)
    return cur

func get_children(dir_path):
    var dir = find_dir(dir_path)
    var result = []
    if dir == null:
        return result

    for i in range(dir.get_subdir_count()):
        var sub = dir.get_subdir(i)
        var n = ABAssetNode.new()
        n.path = normalize(sub.get_path())
        n.name = sub.get_name()
        n.is_dir = true
        n.res_type = "Folder"
        n.tags = _tags_for(normalize(sub.get_path()))
        result.append(n)
    for i in range(dir.get_file_count()):
        var p = dir.get_file_path(i)
        var n2 = ABAssetNode.new()
        n2.path = p
        n2.name = dir.get_file(i)
        n2.is_dir = false
        n2.res_type = dir.get_file_type(i)
        n2.tags = _tags_for(p)
        result.append(n2)
    return result

# Дёшево: есть ли у директории поддиректории (по зеркалу EditorFileSystem, без диска).
func has_subdirs(dir_path):
    var dir = find_dir(dir_path)
    return dir != null and dir.get_subdir_count() > 0

# Только поддиректории (для дерева иерархии).
func get_subdirs(dir_path):
    var dir = find_dir(dir_path)
    var result = []
    if dir == null:
        return result
    for i in range(dir.get_subdir_count()):
        var sub = dir.get_subdir(i)
        var n = ABAssetNode.new()
        n.path = normalize(sub.get_path())
        n.name = sub.get_name()
        n.is_dir = true
        n.res_type = "Folder"
        n.tags = _tags_for(normalize(sub.get_path()))
        result.append(n)
    return result

func has_dir(dir_path):
    return find_dir(dir_path) != null

# Родительская директория ("res://addons/ui" -> "res://addons"; "res://x" -> "res://").
static func parent_dir(path):
    path = normalize(path)
    if path == "res://":
        return "res://"
    var idx = path.rfind("/")
    return "res://" if idx <= 5 else path.substr(0, idx)

# Ближайший существующий предок (для отката, когда текущая папка исчезла).
func nearest_existing_dir(dir_path):
    dir_path = normalize(dir_path)
    while dir_path != "res://" and find_dir(dir_path) == null:
        dir_path = parent_dir(dir_path)
    return dir_path if find_dir(dir_path) != null else "res://"

func get_node_at(path):
    path = normalize(path)
    if _dir_exists(path):
        var d = find_dir(path)
        if d == null:
            return null
        var n = ABAssetNode.new()
        n.path = path
        n.name = d.get_name()
        n.is_dir = true
        n.res_type = "Folder"
        n.tags = _tags_for(path)
        return n
    var parent = path.substr(0, path.rfind("/"))
    var use = "res://" if parent.length() < 6 else parent
    for node in get_children(use):
        if node.path == path:
            return node
    return null

func all_dirs(root_dir):
    var result = []
    var stack = [normalize(root_dir)]
    while stack.size() > 0:
        var d = stack.pop_back()
        result.append(d)
        var dir = find_dir(d)
        if dir == null:
            continue
        for i in range(dir.get_subdir_count()):
            stack.push_back(normalize(dir.get_subdir(i).get_path()))
    return result

func tags_for(path):
    return _tags_for(path)

func _tags_for(path):
    if _tags != null:
        return _tags.get_tags(path)
    return {}

static func _dir_exists(path):
    return DirAccess.dir_exists_absolute(path)

static func _strip_res(p):
    return p.substr(6) if p.begins_with("res://") else p

static func normalize(p):
    if p == null or p == "":
        return "res://"
    p = p.replace("\\", "/")
    if not p.begins_with("res://"):
        p = "res://" + p.lstrip("/")
    if p.length() > 6:
        p = p.rstrip("/")
    return p
