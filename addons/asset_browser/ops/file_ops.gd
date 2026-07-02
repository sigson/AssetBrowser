@tool
extends RefCounted
class_name ABFileOps

static func _is_dir(path):
    return DirAccess.dir_exists_absolute(path)

static func _file_exists(path):
    return FileAccess.file_exists(path)

static func make_folder(dir_path):
    return DirAccess.make_dir_absolute(dir_path)

static func create_text_file(path, content = ""):
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(content)
    f.close()
    return OK

static func create_resource(path, res):
    return ResourceSaver.save(res, path)

static func rename(from, to):
    var e = DirAccess.rename_absolute(from, to)
    if e != OK:
        return e
    _move_sidecar(from, to)
    return OK

static func move_into(from, dst_dir):
    var name = from.substr(from.rfind("/") + 1)
    var to = ABAssetDatabase.normalize(dst_dir) + "/" + name
    if ABAssetDatabase.normalize(from) == to:
        return OK
    return rename(from, to)

static func duplicate_path(src):
    var dst = _unique_name(src)
    var e
    if _is_dir(src):
        e = _copy_dir_recursive(src, dst)
    else:
        e = DirAccess.copy_absolute(src, dst)
    if e != OK:
        return e
    _copy_sidecar(src, dst)
    return OK

static func delete_path(path):
    var e
    if _is_dir(path):
        e = _remove_dir_recursive(path)
    else:
        e = DirAccess.remove_absolute(path)
    if e != OK:
        return e
    _remove_sidecar(path)
    return OK

static func copy(src, dst_dir):
    var name = src.substr(src.rfind("/") + 1)
    var dst = ABAssetDatabase.normalize(dst_dir) + "/" + name
    if _file_exists(dst) or _is_dir(dst):
        dst = _unique_name(dst)
    var e
    if _is_dir(src):
        e = _copy_dir_recursive(src, dst)
    else:
        e = DirAccess.copy_absolute(src, dst)
    if e != OK:
        return e
    _copy_sidecar(src, dst)
    return e

# --- helpers ---
static func _unique_name(path):
    var dir = path.substr(0, path.rfind("/"))
    var name = path.substr(path.rfind("/") + 1)
    var ext = ""
    var base_name = name
    var dot = name.rfind(".")
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

static func _move_sidecar(from, to):
    var s = from + ".import"
    if FileAccess.file_exists(s):
        DirAccess.rename_absolute(s, to + ".import")

static func _copy_sidecar(from, to):
    var s = from + ".import"
    if FileAccess.file_exists(s):
        DirAccess.copy_absolute(s, to + ".import")

static func _remove_sidecar(path):
    var s = path + ".import"
    if FileAccess.file_exists(s):
        DirAccess.remove_absolute(s)

static func _copy_dir_recursive(src, dst):
    var e = DirAccess.make_dir_recursive_absolute(dst)
    if e != OK and e != ERR_ALREADY_EXISTS:
        return e
    var s = DirAccess.open(src)
    if s == null:
        return ERR_CANT_OPEN
    s.list_dir_begin()
    var name = s.get_next()
    while name != "":
        var child = src + "/" + name
        var target = dst + "/" + name
        if s.current_is_dir():
            _copy_dir_recursive(child, target)
        else:
            DirAccess.copy_absolute(child, target)
        name = s.get_next()
    s.list_dir_end()
    return OK

static func _remove_dir_recursive(path):
    var s = DirAccess.open(path)
    if s == null:
        return ERR_CANT_OPEN
    s.list_dir_begin()
    var name = s.get_next()
    while name != "":
        var child = path + "/" + name
        if s.current_is_dir():
            _remove_dir_recursive(child)
        else:
            DirAccess.remove_absolute(child)
        name = s.get_next()
    s.list_dir_end()
    return DirAccess.remove_absolute(path)
