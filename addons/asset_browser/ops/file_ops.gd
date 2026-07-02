tool
extends Reference
class_name ABFileOps

static func _root():
    var d = Directory.new()
    d.open("res://")
    return d

static func _is_dir(path):
    return Directory.new().dir_exists(path)

static func _file_exists(path):
    return Directory.new().file_exists(path)

static func make_folder(dir_path):
    var d = _root()
    return d.make_dir(dir_path)

static func create_text_file(path, content = ""):
    var f = File.new()
    var e = f.open(path, File.WRITE)
    if e != OK:
        return e
    f.store_string(content)
    f.close()
    return OK

static func create_resource(path, res):
    return ResourceSaver.save(path, res)

static func rename(from, to):
    var d = _root()
    var e = d.rename(from, to)
    if e != OK:
        return e
    _move_sidecar(d, from, to)
    return OK

static func move_into(from, dst_dir):
    var name = from.substr(from.find_last("/") + 1)
    var to = ABAssetDatabase.normalize(dst_dir) + "/" + name
    if ABAssetDatabase.normalize(from) == to:
        return OK
    return rename(from, to)

static func duplicate_path(src):
    var d = _root()
    var dst = _unique_name(src)
    var e
    if _is_dir(src):
        e = _copy_dir_recursive(src, dst)
    else:
        e = d.copy(src, dst)
    if e != OK:
        return e
    _copy_sidecar(d, src, dst)
    return OK

static func delete_path(path):
    var d = _root()
    var e
    if _is_dir(path):
        e = _remove_dir_recursive(path)
    else:
        e = d.remove(path)
    if e != OK:
        return e
    _remove_sidecar(d, path)
    return OK

static func copy(src, dst_dir):
    var d = _root()
    var name = src.substr(src.find_last("/") + 1)
    var dst = ABAssetDatabase.normalize(dst_dir) + "/" + name
    if _file_exists(dst) or _is_dir(dst):
        dst = _unique_name(dst)
    var e
    if _is_dir(src):
        e = _copy_dir_recursive(src, dst)
    else:
        e = d.copy(src, dst)
    if e != OK:
        return e
    _copy_sidecar(d, src, dst)
    return e

# --- helpers ---
static func _unique_name(path):
    var dir = path.substr(0, path.find_last("/"))
    var name = path.substr(path.find_last("/") + 1)
    var ext = ""
    var base_name = name
    var dot = name.find_last(".")
    if dot > 0 and not _is_dir(path):
        ext = name.substr(dot)
        base_name = name.substr(0, dot)
    var i = 1
    var candidate
    while true:
        candidate = "%s/%s_%d%s" % [dir, base_name, i, ext]
        i += 1
        if not (_file_exists(candidate) or _is_dir(candidate)):
            break
    return candidate

static func _move_sidecar(d, from, to):
    var s = from + ".import"
    if d.file_exists(s):
        d.rename(s, to + ".import")

static func _copy_sidecar(d, from, to):
    var s = from + ".import"
    if d.file_exists(s):
        d.copy(s, to + ".import")

static func _remove_sidecar(d, path):
    var s = path + ".import"
    if d.file_exists(s):
        d.remove(s)

static func _copy_dir_recursive(src, dst):
    var d = Directory.new()
    var e = d.make_dir_recursive(dst)
    if e != OK and e != ERR_ALREADY_EXISTS:
        return e
    var s = Directory.new()
    if s.open(src) != OK:
        return ERR_CANT_OPEN
    s.list_dir_begin(true, true)
    var name = s.get_next()
    while name != "":
        var child = src + "/" + name
        var target = dst + "/" + name
        if s.current_is_dir():
            _copy_dir_recursive(child, target)
        else:
            d.copy(child, target)
        name = s.get_next()
    s.list_dir_end()
    return OK

static func _remove_dir_recursive(path):
    var s = Directory.new()
    if s.open(path) != OK:
        return ERR_CANT_OPEN
    s.list_dir_begin(true, true)
    var name = s.get_next()
    while name != "":
        var child = path + "/" + name
        if s.current_is_dir():
            _remove_dir_recursive(child)
        else:
            s.remove(child)
        name = s.get_next()
    s.list_dir_end()
    return Directory.new().remove(path)
