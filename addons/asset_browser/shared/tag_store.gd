tool
extends Reference
class_name ABTagStore

const PATH = "user://asset_browser/tags.cfg"

signal changed()

# path -> множество тегов (Dictionary {tag: true})
var _map = {}

func get_tags(path):
    path = ABAssetDatabase.normalize(path)
    if _map.has(path):
        return _map[path].duplicate()
    return {}

func add_tag(path, tag):
    path = ABAssetDatabase.normalize(path)
    tag = tag.strip_edges().to_lower()
    if tag.length() == 0:
        return
    if not _map.has(path):
        _map[path] = {}
    if not _map[path].has(tag):
        _map[path][tag] = true
        save()
        emit_signal("changed")

func remove_tag(path, tag):
    path = ABAssetDatabase.normalize(path)
    tag = tag.strip_edges().to_lower()
    if _map.has(path) and _map[path].has(tag):
        _map[path].erase(tag)
        if _map[path].empty():
            _map.erase(path)
        save()
        emit_signal("changed")

func has_tag(path, tag):
    path = ABAssetDatabase.normalize(path)
    return _map.has(path) and _map[path].has(tag.to_lower())

func all_tags():
    var result = {}
    for k in _map:
        for tag in _map[k]:
            result[tag] = true
    return result.keys()

func load_data():
    var cfg = ConfigFile.new()
    if cfg.load(PATH) != OK:
        return
    _map.clear()
    if not cfg.has_section("tags"):
        return
    for key in cfg.get_section_keys("tags"):
        var v = cfg.get_value("tags", key, PoolStringArray())
        var s = {}
        for tag in v:
            s[tag] = true
        _map[key] = s

func save():
    var d = Directory.new()
    if not d.dir_exists("user://asset_browser"):
        d.make_dir_recursive("user://asset_browser")
    var cfg = ConfigFile.new()
    for path in _map:
        cfg.set_value("tags", path, PoolStringArray(_map[path].keys()))
    cfg.save(PATH)
