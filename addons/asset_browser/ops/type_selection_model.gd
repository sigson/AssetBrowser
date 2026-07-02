tool
extends Reference
class_name ABTypeSelection

enum TriState { UNCHECKED = 0, PARTIAL = 1, CHECKED = 2 }

# Модель выбора типов с «инсталлерной» семантикой. Источник истины — множество
# «полностью включённых» типов _on (Dictionary как set). Матч файла по типу — O(1)
# проверка _on.has(res_type). Tri-state узлов — производное от _on (см. _recompute).

var _g = null
var _on = {}
var _in_count = {}

func _init(g):
    _g = g

# Инициализация из сохранённого фильтра: null => дефолт (выбрано всё).
func init_from_filter(filter):
    _on.clear()
    if filter == null:
        for t in _g.all_types.keys():
            _on[t] = true
    else:
        for t in filter.keys():
            if _g.all_types.has(t):
                _on[t] = true
    _recompute()

func contains(type):
    return _on.has(type)

func state(name):
    if not _g.has(name):
        return TriState.UNCHECKED
    var total = _g.subtree_of(name).size()
    var inc = _in_count[name] if _in_count.has(name) else 0
    if inc <= 0:
        return TriState.UNCHECKED
    return TriState.CHECKED if inc >= total else TriState.PARTIAL

# Клик: CHECKED -> выключить поддерево; иначе -> включить поддерево.
func toggle(name):
    if not _g.has(name):
        return
    var turn_off = state(name) == TriState.CHECKED
    for t in _g.subtree_of(name):
        if turn_off:
            _on.erase(t)
        else:
            _on[t] = true
    _recompute()

func select_all():
    _on.clear()
    for t in _g.all_types.keys():
        _on[t] = true
    _recompute()

func select_none():
    _on.clear()
    _recompute()

func is_default():
    return _on.size() == _g.all_types.size()

# Свернуть в фильтр для SearchState: дефолт => null.
func to_filter():
    if is_default():
        return null
    return _on.duplicate()

# Пересчёт in_count за один проход: дети раньше родителей (обратный pre-order).
func _recompute():
    _in_count.clear()
    var order = _g.pre_order
    for i in range(order.size() - 1, -1, -1):
        var n = order[i]
        var c = 1 if _on.has(n) else 0
        for ch in _g.children_of(n):
            if _in_count.has(ch):
                c += _in_count[ch]
        _in_count[n] = c
