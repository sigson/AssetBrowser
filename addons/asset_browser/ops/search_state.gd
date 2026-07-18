tool
extends Reference
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

# Direct filter: не уходить в режим результатов поиска, а прятать несовпавшие
# файлы прямо в директории, куда заходит пользователь.
var direct = false

# Git view: подсветка состояний и доступность git-фильтра.
var git_view = false
# Набор состояний ABGitService.Status как Dictionary {Status: true}; null => all (по умолчанию).
var git_states = null

func type_filter_active():
    return types != null

# Текстовый/структурный запрос (то, что умеет разобрать ABSearchEngine).
func has_text_query():
    return text.strip_edges() != "" or types != null

# Любой активный критерий отбора, включая git-состояния: git-фильтр —
# такой же полноправный запрос, как текст или тип-фильтр.
func has_query():
    return has_text_query() or git_filter_active()

# Пустой поиск = нет ни одного активного критерия.
func is_empty():
    return not has_query()

# Режим результатов: критерий есть и direct filter выключен => рекурсивная
# выдача вглубь от текущей папки. С direct filter тот же критерий прячет
# несовпавшие файлы на месте.
func results_mode():
    return has_query() and not direct

func git_filter_active():
    return git_view and git_states != null

# Фильтруем ли содержимое текущей директории на месте.
func direct_filter_active():
    return direct and has_query()

func clone():
    var s = get_script().new()
    s.text = text
    s.regex = regex
    s.content = content
    s.split = split
    s.scope_global = scope_global
    s.global_content_confirmed = global_content_confirmed
    s.types = null if types == null else types.duplicate()
    s.direct = direct
    s.git_view = git_view
    s.git_states = null if git_states == null else git_states.duplicate()
    return s

# Компактная подпись для сигнатуры вью (пересборка при смене фильтров).
func filter_sig():
    var g = "all"
    if git_states != null:
        var keys = git_states.keys()
        keys.sort()
        g = str(keys)
    return "%s|%s|%s" % [str(direct), str(git_view), g]
