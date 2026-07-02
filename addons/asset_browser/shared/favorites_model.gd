tool
extends Reference
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
        _dirs.remove(idx)
        save()
        emit_signal("changed")

func contains(dir):
    return _dirs.has(ABAssetDatabase.normalize(dir))

func load_data():
    var cfg = ConfigFile.new()
    if cfg.load(PATH) != OK:
        return
    _dirs.clear()
    var arr = cfg.get_value("favorites", "dirs", PoolStringArray())
    for s in arr:
        _dirs.append(s)

func save():
    _ensure_dir()
    var cfg = ConfigFile.new()
    cfg.set_value("favorites", "dirs", PoolStringArray(_dirs))
    cfg.save(PATH)

static func _ensure_dir():
    var d = Directory.new()
    if not d.dir_exists("user://asset_browser"):
        d.make_dir_recursive("user://asset_browser")
