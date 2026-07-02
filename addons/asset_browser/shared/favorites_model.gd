@tool
extends RefCounted
class_name ABFavoritesModel

const PATH = "user://asset_browser/favorites.cfg"

signal changed()

var _dirs = []

func dirs():
    return _dirs

func add(dir):
    dir = ABAssetDatabase.normalize(dir)
    if _dirs.has(dir):
        return
    _dirs.append(dir)
    save()
    emit_signal("changed")

func remove(dir):
    dir = ABAssetDatabase.normalize(dir)
    var idx = _dirs.find(dir)
    if idx >= 0:
        _dirs.remove_at(idx)
        save()
        emit_signal("changed")

func contains(dir):
    return _dirs.has(ABAssetDatabase.normalize(dir))

func load_data():
    var cfg = ConfigFile.new()
    if cfg.load(PATH) != OK:
        return
    _dirs.clear()
    var arr = cfg.get_value("favorites", "dirs", PackedStringArray())
    for s in arr:
        _dirs.append(s)

func save():
    _ensure_dir()
    var cfg = ConfigFile.new()
    cfg.set_value("favorites", "dirs", PackedStringArray(_dirs))
    cfg.save(PATH)

static func _ensure_dir():
    if not DirAccess.dir_exists_absolute("user://asset_browser"):
        DirAccess.make_dir_recursive_absolute("user://asset_browser")
