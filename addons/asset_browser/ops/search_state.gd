@tool
extends RefCounted
class_name ABSearchState

var text = ""
var regex = false
var content = false
var split = false
var scope_global = false
# ФТ-4: разовое подтверждение глобального контент-поиска (per-tab, не персистится).
var global_content_confirmed = false

# Структурный фильтр по типу ресурса (селектор типов). null => дефолт (не применяется).
# Иначе — множество имён типов как Dictionary {name: true}.
var types = null

func type_filter_active():
    return types != null

# Пустой поиск = нет текста И нет активного тип-фильтра.
func is_empty():
    return text.strip_edges() == "" and types == null

func clone():
    var s = get_script().new()
    s.text = text
    s.regex = regex
    s.content = content
    s.split = split
    s.scope_global = scope_global
    s.global_content_confirmed = global_content_confirmed
    s.types = null if types == null else types.duplicate()
    return s
