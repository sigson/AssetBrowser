tool
extends Reference
class_name ABResourceTypeGraph

# Иерархия типов Resource. В C# собиралась РЕФЛЕКСИЕЙ по сборке GodotSharp; в GDScript
# эквивалент — ClassDB.get_inheriters_from_class("Resource") (движковые классы напрямую),
# что даёт ту же иерархию корректнее (имена совпадают с EditorFileSystem.get_file_type).
# Плюс синтетический корневой ребёнок Resource — "CustomResource" для пользовательских
# (скриптовых) ресурсов.
#
# Граф иммутабелен и строится один раз. В GDScript нет статических переменных, поэтому
# синглтон кешируется в Shared.type_graph (см. Shared.init).

const ROOT = "Resource"
const CUSTOM = "CustomResource"   # синтетический ребёнок Resource

# Родитель типа (ROOT -> null). Ребёнок CUSTOM -> ROOT.
var parent = {}
# Дети типа, отсортированные по имени.
var children = {}
# Полное поддерево {сам тип} ∪ все потомки.
var subtree = {}
# Глубина от корня (0 у Resource).
var depth = {}

# Имена ТОЛЬКО движковых типов (без синтетического CustomResource).
var _engine_types = {}
# Все узлы графа, включая CustomResource.
var all_types = {}
# Pre-order обход от корня.
var pre_order = []

func is_known_engine_type(name):
    return name != null and _engine_types.has(name)

func has(name):
    return name != null and parent.has(name)

func children_of(name):
    return children[name] if children.has(name) else []

func subtree_of(name):
    return subtree[name] if subtree.has(name) else []

static func build():
    var g = load("res://addons/asset_browser/ops/resource_type_graph.gd").new()

    # 1) Собираем движковые классы, наследующие Resource.
    var found = {}
    for name in ClassDB.get_inheriters_from_class("Resource"):
        found[name] = true
    found[ROOT] = true

    # 2) Родитель = ближайший предок по цепочке ClassDB, попавший в набор.
    for name in found.keys():
        g._engine_types[name] = true
        g.all_types[name] = true

        if name == ROOT:
            g.parent[name] = null
            continue

        var par = ROOT
        var b = ClassDB.get_parent_class(name)
        while b != null and b != "":
            if found.has(b) and b != name:
                par = b
                break
            b = ClassDB.get_parent_class(b)
        g.parent[name] = par

    # 3) Синтетический CustomResource — ребёнок Resource.
    g.parent[CUSTOM] = ROOT
    g.all_types[CUSTOM] = true

    # 4) Списки детей (по алфавиту).
    for node in g.parent.keys():
        var par = g.parent[node]
        if not g.children.has(node):
            g.children[node] = []
        if par != null:
            if not g.children.has(par):
                g.children[par] = []
            g.children[par].append(node)
    for node in g.children.keys():
        g.children[node].sort()

    # 5) Глубины (BFS от корня) и поддеревья (итеративно).
    g._compute_depths()
    g._compute_subtrees(ROOT)

    return g

func _compute_depths():
    var q = [ROOT]
    depth[ROOT] = 0
    while q.size() > 0:
        var n = q.pop_front()
        for c in children_of(n):
            if depth.has(c):
                continue
            depth[c] = depth[n] + 1
            q.append(c)

func _compute_subtrees(root):
    var order = pre_order
    var stack = [root]
    while stack.size() > 0:
        var n = stack.pop_back()
        order.append(n)
        for c in children_of(n):
            stack.push_back(c)
    # order — pre-order; проходим в обратном порядке => дети раньше родителей.
    for i in range(order.size() - 1, -1, -1):
        var n = order[i]
        var sub = [n]
        for c in children_of(n):
            if subtree.has(c):
                for x in subtree[c]:
                    sub.append(x)
        subtree[n] = sub
