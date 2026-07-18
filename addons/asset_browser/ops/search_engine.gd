tool
extends Reference
class_name ABSearchEngine

# ФТ-4: обход ленивый — потребитель (FileView) продвигает курсор порциями по кадрам.
# В C# это был IEnumerable + yield; в GDScript эквивалент — курсор SearchCursor с next().

const TEXT_EXTS = {
    "gd": true, "cs": true, "tres": true, "tscn": true, "txt": true, "json": true,
    "shader": true, "gdshader": true, "cfg": true, "import": true, "md": true,
    "xml": true, "csv": true
}
const RES_EXTS = { "tres": true, "res": true }
const MAX_CONTENT_BYTES = 2 * 1024 * 1024

var _db = null
var _tags = null
var _settings = null
var _graph = null
var _res_cache = {}

# Диагностика для статус-бара (читать ПОСЛЕ завершения/паузы обхода).
var files_read = 0
var content_truncated = false
var global_content_blocked = false

func _init(db, tags, settings, graph):
    _db = db
    _tags = tags
    _settings = settings
    _graph = graph

# Возвращает курсор (SearchCursor) с методом next() -> AssetNode|null.
# traversal=false => курсор используется только как предикат (direct filter),
# обхода не будет, поэтому «глобальные» ограничения к нему неприменимы.
func query(s, current_dir, traversal = true):
    var parsed = _parse_tokens(s.text)
    var type_filter = parsed.type_filter
    var label_filters = parsed.labels
    var rest = parsed.rest

    var root = "res://" if s.scope_global else ABAssetDatabase.normalize(current_dir)

    # ФТ-4: opt-in на глобальный контент-поиск. Гасит поиск по содержимому только
    # когда обход действительно глобальный: при фильтрации на месте читается одна
    # директория, и блокировать её из-за тоггла области нечестно.
    var require_optin = _settings == null or _settings.content_requires_global_optin
    var content_allowed = s.content
    if s.content and s.scope_global and traversal and require_optin and not s.global_content_confirmed:
        content_allowed = false
        global_content_blocked = true

    var content_cap = max(0, _settings.content_max_files) if _settings != null else 500

    var cur = SearchCursor.new(self)
    cur.setup(root, rest, s, type_filter, label_filters, content_allowed, content_cap)
    return cur

# Direct filter: тот же предикат, но без обхода — вызывающий сам подаёт узлы
# текущей директории в matches().
func make_matcher(s, current_dir):
    return query(s, current_dir, false)

# ---------- структурный тип-фильтр ----------
func match_type_filter(n, sel):
    if n.is_dir:
        return false
    var rt = "Resource" if (n.res_type == null or n.res_type == "") else n.res_type

    if sel.has(rt):
        return true

    if not RES_EXTS.has(n.ext()):
        return false

    var want_custom = sel.has(ABResourceTypeGraph.CUSTOM)

    if not _graph.is_known_engine_type(rt):
        var info = _read_res_info(n.path)
        if info.base != null and sel.has(info.base):
            return true
        if want_custom:
            return true
        return false

    if want_custom and _read_res_info(n.path).scripted:
        return true
    return false

func _read_res_info(path):
    if _res_cache.has(path):
        return _res_cache[path]

    var info = {"base": null, "scripted": false}
    var f = File.new()
    if f.open(path, File.READ) == OK:
        var guard = 0
        while not f.eof_reached() and guard < 300:
            guard += 1
            var line = f.get_line()
            var t = line.strip_edges(true, false)   # trim leading only

            if info.base == null and t.begins_with("[gd_resource"):
                info.base = _extract_quoted(line, "type=\"")
            if line.find("script_class=\"") >= 0:
                info.scripted = true
            if t.begins_with("script = ExtResource") or t.begins_with("script = SubResource"):
                info.scripted = true

            if info.base != null and info.scripted:
                break
        f.close()
    _res_cache[path] = info
    return info

static func _extract_quoted(line, key):
    var i = line.find(key)
    if i < 0:
        return null
    i += key.length()
    var j = line.find("\"", i)
    return line.substr(i, j - i) if j > i else null

func _parse_tokens(text):
    var type_filter = null
    var labels = []
    var rest = []
    var src = "" if text == null else text
    for tok in src.split(" "):
        if tok.length() == 0:
            continue
        if tok.begins_with("t:") and tok.length() > 2:
            type_filter = tok.substr(2).to_lower()
        elif tok.begins_with("l:") and tok.length() > 2:
            labels.append(tok.substr(2).to_lower())
        else:
            rest.append(tok)
    return {"type_filter": type_filter, "labels": labels, "rest": PoolStringArray(rest).join(" ")}

func match_type(n, t):
    if n.is_dir:
        return false
    return n.res_type.to_lower().find(t) >= 0 or n.ext() == t

# Читает текст файла либо null; уважает потолок content_max_files.
func read_text(n, cap):
    if n.is_dir or not TEXT_EXTS.has(n.ext()):
        return null
    if cap > 0 and files_read >= cap:
        content_truncated = true
        return null

    var f = File.new()
    if f.open(n.path, File.READ) != OK:
        return null
    files_read += 1
    if f.get_len() > MAX_CONTENT_BYTES:
        f.close()
        return null
    var txt = f.get_as_text()
    f.close()
    return txt

static func unescape(s):
    return s.replace("\\n", "\n").replace("\\t", "\t").replace("\\r", "\r").replace("\\\\", "\\")


# ==================== ленивый курсор обхода ====================
class SearchCursor:
    extends Reference

    var _e = null            # ABSearchEngine
    var _root = "res://"
    var _rest = ""
    var _s = null            # SearchState
    var _type_filter = null
    var _labels = []
    var _content_allowed = false
    var _content_cap = 500

    # обход
    var _stack = []
    var _pending = []
    var _idx = 0

    # предикаты
    var _re = null           # RegEx для имени/контента (regex-режим)
    var _split_keys = []
    var _needle = ""
    var _has_rest = false
    var _content_active = false

    func _init(engine):
        _e = engine

    func setup(root, rest, s, tok_type, labels, content_allowed, content_cap):
        _root = root
        _rest = rest
        _s = s
        _tok_type = tok_type          # t:-токен (подстрока), может быть null
        _type_filter = s.types        # структурный фильтр по дереву типов (Dictionary|null)
        _labels = labels
        _content_allowed = content_allowed
        _content_cap = content_cap
        _has_rest = rest.strip_edges() != ""

        if _has_rest:
            if s.regex:
                var re = RegEx.new()
                if re.compile(rest) == OK:
                    _re = re
                else:
                    _re = null   # невалидное — ничего не матчит
            elif s.split:
                _split_keys = []
                for k in rest.split(" "):
                    if k.length() > 0:
                        _split_keys.append(k)
            else:
                _needle = _e.unescape(rest)
        _content_active = _content_allowed and _has_rest

        _stack = [ABAssetDatabase.normalize(root)]
        _pending = []
        _idx = 0

    # Следующий совпавший узел или null (обход исчерпан).
    func next():
        while true:
            if _idx < _pending.size():
                var n = _pending[_idx]
                _idx += 1
                if n.is_dir:
                    _stack.push_back(n.path)
                if _match(n):
                    return n
            else:
                if _stack.size() == 0:
                    return null
                var d = _stack.pop_back()
                _pending = _e._db.get_children(d)
                _idx = 0

    # Публичная проверка одного узла (direct filter).
    func matches(n):
        return _match(n)

    func _match(n):
        # структурный тип (дёшево, s.types) идёт первым
        if _type_filter != null and not _e.match_type_filter(n, _type_filter):
            return false
        # t:-токен (подстрока по типу/расширению)
        if _tok_type != null and not _e.match_type(n, _tok_type):
            return false
        if _labels.size() > 0:
            for l in _labels:
                if not _e._tags.has_tag(n.path, l):
                    return false
        if not _has_rest:
            return true
        var ok = _name_test(n)
        if not ok and _content_active and not n.is_dir:
            ok = _content_test(n)
        return ok

    # t:-токен (в C# — второй фильтр после структурного)
    var _tok_type = null

    func _name_test(n):
        if not _has_rest:
            return true
        if _s.regex:
            return _re != null and _re.search(n.name) != null
        if _s.split:
            for k in _split_keys:
                if n.name.to_lower().find(k.to_lower()) < 0:
                    return false
            return true
        return n.name.to_lower().find(_needle.to_lower()) >= 0

    func _content_test(n):
        var c = _e.read_text(n, _content_cap)
        if c == null:
            return false
        if _s.regex:
            return _re != null and _re.search(c) != null
        if _s.split:
            for k in _split_keys:
                if c.to_lower().find(k.to_lower()) < 0:
                    return false
            return true
        return c.to_lower().find(_needle.to_lower()) >= 0
