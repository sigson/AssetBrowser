tool
extends Container
class_name ABFlowContainer

# Контейнер с переносом по строкам (flow). Один ребёнок с флагом Expand тянется на
# остаток своей строки. MinWidthCap ограничивает минимальную ширину сверху — контейнер
# можно сильно сжать; длинные дети клипаются по ширине.

var sep = 2
var min_width_cap = 48.0
var _content_height = 22.0

func _ready():
    rect_clip_content = true

func _notification(what):
    if what == NOTIFICATION_SORT_CHILDREN:
        _layout_children()

func _get_minimum_size():
    var max_w = 0.0
    for c in get_children():
        if c is Control and c.visible and not c.is_set_as_toplevel():
            max_w = max(max_w, c.get_combined_minimum_size().x)
    return Vector2(min(max_w, min_width_cap), _content_height)

func _layout_children():
    var avail = rect_size.x
    if avail <= 0.0:
        avail = min_width_cap
    var x = 0.0
    var y = 0.0
    var row_h = 0.0

    var kids = []
    for c in get_children():
        if c is Control and c.visible and not c.is_set_as_toplevel():
            kids.append(c)

    for ctl in kids:
        var ms = ctl.get_combined_minimum_size()
        var expand = (ctl.size_flags_horizontal & Control.SIZE_EXPAND) != 0

        if x > 0.0 and x + ms.x > avail:
            x = 0.0
            y += row_h + sep
            row_h = 0.0

        var w = max(ms.x, avail - x) if expand else ms.x
        w = min(w, max(16.0, avail - x))

        var h = max(ms.y, 16.0)
        fit_child_in_rect(ctl, Rect2(x, y, w, h))
        x += w + sep
        row_h = max(row_h, h)

    var new_h = y + row_h
    if abs(new_h - _content_height) > 0.5:
        _content_height = new_h
        minimum_size_changed()
