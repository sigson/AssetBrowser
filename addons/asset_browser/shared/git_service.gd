tool
extends Reference
class_name ABGitService

# Статус рабочего дерева git для файлов проекта. Один экземпляр на плагин (ABShared.git).
# Запуск git блокирующий, поэтому результат кешируется и обновляется не чаще
# settings.git_refresh_min_ms; потребители дёргают ensure_fresh().

signal status_changed()

enum Status { UNMODIFIED = 0, MODIFIED = 1, NEW = 2 }

var available = false
var revision = 0           # растёт на каждый успешный refresh; входит в сигнатуру вью

var _settings = null
var _repo_root = ""
var _prefix = ""           # путь проекта относительно корня репозитория ("" либо "sub/dir/")
var _file_status = {}      # res-путь файла -> Status (только изменённые; остальные UNMODIFIED)
var _dir_dirty = {}        # res-путь директории -> true (любой предок изменённого файла)
var _last_ms = -100000.0
var _probed = false

func init(settings):
    _settings = settings
    _probe()

func _now_ms():
    return OS.get_ticks_msec()

# ---------- обнаружение репозитория ----------
func _probe():
    _probed = true
    available = false
    _repo_root = ""
    _prefix = ""

    var proj = ProjectSettings.globalize_path("res://").replace("\\", "/")
    if not proj.ends_with("/"):
        proj += "/"

    var out = []
    var code = OS.execute("git", ["-C", proj, "rev-parse", "--show-toplevel"], true, out)
    if code != 0:
        return

    var root = _out_text(out).strip_edges().replace("\\", "/")
    if root == "":
        return
    if not root.ends_with("/"):
        root += "/"
    if not proj.begins_with(root):
        return

    _repo_root = root
    _prefix = proj.substr(root.length())
    available = true

# Godot 3 складывает весь stdout одной строкой в output[0], но не полагаемся на это.
static func _out_text(out):
    var s = ""
    for x in out:
        s += str(x)
    return s

# ---------- обновление ----------
func ensure_fresh(force = false):
    if not _probed:
        _probe()
    if not available:
        return
    var min_ms = _settings.git_refresh_min_ms if _settings != null else 1500
    if not force and _now_ms() - _last_ms < min_ms:
        return
    refresh()

func refresh():
    if not _probed:
        _probe()
    if not available:
        return

    _last_ms = _now_ms()

    var out = []
    var args = ["-C", _repo_root, "status", "--porcelain", "--untracked-files=all"]
    if OS.execute("git", args, true, out) != 0:
        return

    var files = {}
    var dirs = {}
    for line in _out_text(out).split("\n"):
        if line.length() < 4:
            continue

        var xy = line.substr(0, 2)
        var rel = line.substr(3).strip_edges()

        # переименование: "R  old -> new" — интересует новый путь
        var arrow = rel.find(" -> ")
        if arrow >= 0:
            rel = rel.substr(arrow + 4)
        rel = _unquote(rel.strip_edges())
        if rel == "" or rel.ends_with("/"):
            continue

        var res_path = _to_res(rel)
        if res_path == null:
            continue

        files[res_path] = Status.NEW if (xy == "??" or xy.find("A") >= 0) else Status.MODIFIED

        var d = ABAssetDatabase.parent_dir(res_path)
        while true:
            dirs[d] = true
            if d == "res://":
                break
            d = ABAssetDatabase.parent_dir(d)

    _file_status = files
    _dir_dirty = dirs
    revision += 1
    # Отложенно: refresh() зовут из середины перестроения вью, а синхронный
    # сигнал приводил к реентерабельному populate() и дублированию списка узлов.
    call_deferred("emit_signal", "status_changed")

# Путь из porcelain (относительно корня репо) -> res://-путь, либо null (вне проекта).
func _to_res(rel):
    if _prefix != "":
        if not rel.begins_with(_prefix):
            return null
        rel = rel.substr(_prefix.length())
    return "res://" + rel

# git заключает в кавычки пути со спецсимволами.
static func _unquote(s):
    if s.length() < 2 or not s.begins_with("\"") or not s.ends_with("\""):
        return s
    s = s.substr(1, s.length() - 2)
    return s.replace("\\\"", "\"").replace("\\\\", "\\")

# ---------- запросы ----------
func status_of(path):
    return _file_status[path] if _file_status.has(path) else Status.UNMODIFIED

func is_dir_dirty(path):
    return _dir_dirty.has(ABAssetDatabase.normalize(path))

func changed_count():
    return _file_status.size()

# ---------- цвета ----------
func color_for(status):
    match status:
        Status.NEW:
            return _color("color_new", "5fd35f")
        Status.MODIFIED:
            return _color("color_modified", "f2c14e")
        _:
            return _color("color_unmodified", "9aa3b0")

func dir_color():
    return _color("color_dir", "6fb7f0")

func _color(key, def_hex):
    var hex = def_hex
    if _settings != null:
        hex = _settings.git_color(key, def_hex)
    return Color(hex)

static func status_name(status):
    match status:
        Status.NEW:
            return "new"
        Status.MODIFIED:
            return "modified"
        _:
            return "unmodified"
