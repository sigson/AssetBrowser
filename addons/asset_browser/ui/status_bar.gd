tool
extends HBoxContainer
class_name ABStatusBar

signal zoom_changed(value)

var _count = null
var _note = null
var _path = null
var _zoom = null
var _max = 0

func build(preview_size, max_preview_size):
    _max = max_preview_size
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rect_clip_content = true
    add_constant_override("separation", 2)

    _count = Label.new()
    _count.text = "0 items"
    add_child(_count)

    _note = Label.new()
    _note.text = ""
    _note.add_color_override("font_color", Color(0.95, 0.75, 0.2))   # приглушённо-янтарный
    add_child(_note)

    add_child(VSeparator.new())

    _path = Label.new()
    _path.text = ""
    _path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _path.clip_text = true
    add_child(_path)

    var l1 = Label.new()
    l1.text = "list"
    add_child(l1)

    _zoom = HSlider.new()
    _zoom.min_value = 16
    _zoom.max_value = max_preview_size
    _zoom.step = 8
    _zoom.value = preview_size
    _zoom.rect_min_size = Vector2(70, 0)
    _zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _zoom.connect("value_changed", self, "on_zoom")
    add_child(_zoom)

    var l2 = Label.new()
    l2.text = "grid"
    add_child(l2)

func set_info(count, selected_path):
    _count.text = "%d items" % count
    _path.text = selected_path if selected_path != null else ""

# ФТ-4: уведомление об усечении выдачи / заблокированном контент-поиске.
func set_note(note):
    if _note != null:
        _note.text = "" if (note == null or note == "") else "— " + note

func set_zoom(v):
    if _zoom != null:
        _zoom.value = clamp(v, int(_zoom.min_value), _max)

func update_max(max_preview_size):
    _max = max_preview_size
    if _zoom != null:
        _zoom.max_value = max_preview_size

func on_zoom(v):
    emit_signal("zoom_changed", int(v))
