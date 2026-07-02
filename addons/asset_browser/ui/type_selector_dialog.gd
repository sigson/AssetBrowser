@tool
extends ConfirmationDialog
class_name ABTypeSelectorDialog

# Модальный селектор типов ресурсов: поле поиска + дерево с tri-state чекбоксами и
# инсталлерной логикой (см. ABTypeSelection). Граф читается из shared.type_graph.

signal applied()

var result_filter = null   # итоговый фильтр после OK: null => дефолт

var _s = null
var _g = null
var _model = null

var _search = null
var _tree = null
var _summary = null

var _item_type = {}   # TreeItem -> type string
var _query = ""

var _ico_checked = null
var _ico_unchecked = null
var _ico_partial = null

func build(shared):
    _s = shared
    _g = _s.type_graph if _s != null else ABResourceTypeGraph.build()
    _model = ABTypeSelection.new(_g)

    title = "Filter by resource type"
    unresizable = false
    min_size = Vector2i(440, 560)
    get_ok_button().text = "Apply"

    _build_tristate_icons()

    var vb = VBoxContainer.new()
    vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vb.custom_minimum_size = Vector2(420, 500)
    add_child(vb)

    _search = LineEdit.new()
    _search.placeholder_text = "search type... (e.g. ani, texture)"
    _search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _search.connect("text_changed", Callable(self, "on_search_text"))
    vb.add_child(_search)

    _tree = Tree.new()
    _tree.hide_root = false
    _tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _tree.columns = 1
    _tree.set_column_expand(0, true)
    _tree.connect("button_clicked", Callable(self, "on_button_pressed"))
    _tree.connect("item_activated", Callable(self, "on_item_activated"))
    vb.add_child(_tree)

    _summary = Label.new()
    _summary.modulate = Color(1, 1, 1, 0.7)
    vb.add_child(_summary)

    add_button("All", true, "all")
    add_button("None", true, "none")

    connect("confirmed", Callable(self, "on_confirmed"))
    connect("custom_action", Callable(self, "on_custom_action"))

func open(current_filter):
    _model.init_from_filter(current_filter)
    _search.text = ""
    _query = ""
    _rebuild()
    popup_centered(Vector2i(460, 580))
    _search.grab_focus()

# ---------- построение дерева ----------
func _rebuild():
    _tree.clear()
    _item_type.clear()

    var visible = _compute_visible(_query)
    var filtering = _query.length() > 0

    var root_item = _tree.create_item()
    _bind_item(root_item, ABResourceTypeGraph.ROOT, filtering)

    var stack = [[root_item, ABResourceTypeGraph.ROOT]]
    while stack.size() > 0:
        var kv = stack.pop_back()
        var parent_item = kv[0]
        var parent_type = kv[1]
        for child in _g.children_of(parent_type):
            if not visible.has(child):
                continue
            var it = _tree.create_item(parent_item)
            _bind_item(it, child, filtering)
            stack.push_back([it, child])

    _refresh_states()
    _update_summary()

func _bind_item(it, type, filtering):
    _item_type[it] = type

    it.set_text(0, type)
    var ico = _type_icon(type)
    if ico != null:
        it.set_icon(0, ico)
    it.set_selectable(0, true)
    it.add_button(0, _ico_unchecked, 0)

    var depth = _g.depth[type] if _g.depth.has(type) else 0
    if not filtering and depth >= 1:
        it.collapsed = true

func _type_icon(type):
    if _s == null:
        return null
    if type == ABResourceTypeGraph.CUSTOM:
        var c = _s.thumbs.editor_icon("ResourcePreloader")
        return c if c != null else _s.thumbs.editor_icon("Object")
    var t = _s.thumbs.editor_icon(type)
    return t if t != null else _s.thumbs.editor_icon("Object")

func _compute_visible(query):
    var vis = {}
    if query.length() == 0:
        for t in _g.all_types.keys():
            vis[t] = true
        return vis
    vis[ABResourceTypeGraph.ROOT] = true
    var q = query.to_lower()
    for t in _g.all_types.keys():
        if t.to_lower().find(q) < 0:
            continue
        var cur = t
        while cur != null:
            if vis.has(cur):
                break
            vis[cur] = true
            cur = _g.parent[cur] if _g.parent.has(cur) else null
    return vis

# ---------- состояние чекбоксов ----------
func _refresh_states():
    for item in _item_type.keys():
        var type = _item_type[item]
        var st = _model.state(type)
        var ic = _ico_unchecked
        if st == ABTypeSelection.TriState.CHECKED:
            ic = _ico_checked
        elif st == ABTypeSelection.TriState.PARTIAL:
            ic = _ico_partial
        item.set_button(0, 0, ic)

        if st == ABTypeSelection.TriState.CHECKED:
            item.set_custom_color(0, _accent_color())
        elif st == ABTypeSelection.TriState.PARTIAL:
            item.set_custom_color(0, _accent_color(0.65))
        else:
            item.clear_custom_color(0)

func _update_summary():
    if _model.is_default():
        _summary.text = "All resource types (filter off)"
        return
    var f = _model.to_filter()
    var n = f.size() if f != null else 0
    _summary.text = "No types selected (matches nothing)" if n == 0 else "%d type(s) selected" % n

# ---------- сигналы ----------
func on_search_text(t):
    _query = (t if t != null else "").strip_edges()
    _rebuild()

func on_button_pressed(item_obj, column, _id, _mb = 0):
    if column != 0:
        return
    var item = item_obj as TreeItem
    if item == null or not _item_type.has(item):
        return
    _model.toggle(_item_type[item])
    _refresh_states()
    _update_summary()

func on_item_activated():
    var it = _tree.get_selected()
    if it != null and _item_type.has(it):
        _model.toggle(_item_type[it])
        _refresh_states()
        _update_summary()

func on_custom_action(action):
    if action == "all":
        _model.select_all()
    elif action == "none":
        _model.select_none()
    _refresh_states()
    _update_summary()

func on_confirmed():
    result_filter = _model.to_filter()
    emit_signal("applied")

# ---------- иконки tri-state (генерируются) ----------
func _build_tristate_icons():
    var border = Color(0.72, 0.74, 0.78)
    var fill = _accent_color()
    var glyph = Color(1, 1, 1)

    _ico_unchecked = _make_icon(border, null, glyph, false, false)
    _ico_checked = _make_icon(border, fill, glyph, true, false)
    _ico_partial = _make_icon(border, fill, glyph, false, true)

func _accent_color(a = 1.0):
    return Color(0.26, 0.59, 0.98, a)

func _make_icon(border, fill, glyph, check, minus):
    var n = 16
    var img = Image.create(n, n, false, Image.FORMAT_RGBA8)
    for y in range(n):
        for x in range(n):
            img.set_pixel(x, y, Color(0, 0, 0, 0))

    var a = 2
    var b = n - 3
    if fill != null:
        for y in range(a, b + 1):
            for x in range(a, b + 1):
                img.set_pixel(x, y, fill)

    for i in range(a, b + 1):
        img.set_pixel(i, a, border)
        img.set_pixel(i, b, border)
        img.set_pixel(a, i, border)
        img.set_pixel(b, i, border)

    if check:
        _stroke(img, 4, 8, 7, 11, glyph)
        _stroke(img, 7, 11, 12, 4, glyph)
    if minus:
        for x in range(4, 12):
            img.set_pixel(x, 7, glyph)
            img.set_pixel(x, 8, glyph)

    var tex = ImageTexture.create_from_image(img)
    return tex

func _stroke(img, x0, y0, x1, y1, c):
    var dx = abs(x1 - x0)
    var dy = -abs(y1 - y0)
    var sx = 1 if x0 < x1 else -1
    var sy = 1 if y0 < y1 else -1
    var err = dx + dy
    while true:
        _plot(img, x0, y0, c)
        _plot(img, x0 + 1, y0, c)
        _plot(img, x0, y0 + 1, c)
        if x0 == x1 and y0 == y1:
            break
        var e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy

func _plot(img, x, y, c):
    if x >= 0 and y >= 0 and x < 16 and y < 16:
        img.set_pixel(x, y, c)
