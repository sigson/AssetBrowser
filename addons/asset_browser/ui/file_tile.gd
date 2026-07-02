tool
extends Control
class_name ABFileTile

# Плитка — Control (не Container), чтобы фон выделения занимал всю ячейку.

var _view = null
var _node = null
var _s = null
var _icon = null
var _label = null
var _bg = null
var _cell = 0
var _is_parent = false

func build(view, node, cell, shared):
    _view = view
    _node = node
    _s = shared
    _cell = cell
    _is_parent = node.path == _view.PARENT_MARKER

    rect_min_size = Vector2(cell + 8, cell + 26)
    mouse_filter = Control.MOUSE_FILTER_STOP
    hint_tooltip = node.name

    _bg = ColorRect.new()
    _bg.color = Color(0, 0, 0, 0)
    _bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_bg)
    _bg.set_anchors_and_margins_preset(Control.PRESET_WIDE)

    var box = VBoxContainer.new()
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_constant_override("separation", 2)
    add_child(box)
    box.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_KEEP_SIZE, 4)

    _icon = TextureRect.new()
    _icon.expand = true
    _icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _icon.texture = _s.thumbs.get_type_icon(node)
    _icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _icon.rect_min_size = Vector2(cell, cell)
    box.add_child(_icon)

    _label = Label.new()
    _label.text = node.name
    _label.align = Label.ALIGN_LEFT
    _label.clip_text = true
    _label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _label.rect_min_size = Vector2(0, 18)
    box.add_child(_label)

func set_thumb(tex):
    if _icon != null:
        _icon.texture = tex

# Сбросить превью обратно на типовую иконку (engine_lazy: полноразмерный кеш не держим).
func release_thumb():
    if _icon != null:
        _icon.texture = _s.thumbs.get_type_icon(_node)

func set_selected(on):
    if _is_parent:
        return
    if _bg != null:
        _bg.color = Color(0.26, 0.52, 0.96, 0.35) if on else Color(0, 0, 0, 0)

func _gui_input(ev):
    if not (ev is InputEventMouseButton):
        return
    var mb = ev

    if _is_parent:
        if mb.button_index == BUTTON_LEFT and mb.pressed and mb.doubleclick:
            _view.activate(_node.path)
        if mb.button_index == BUTTON_LEFT:
            accept_event()
        return

    if mb.button_index == BUTTON_LEFT:
        if mb.pressed:
            if mb.doubleclick:
                _view.activate(_node.path)
            else:
                _view.tile_pressed(_node.path, mb.control, mb.shift)
        else:
            _view.tile_released(_node.path)
        accept_event()
    elif mb.button_index == BUTTON_RIGHT and mb.pressed:
        _view.tile_right_pressed(_node.path)
        _view.popup_context()
        accept_event()

func get_drag_data(position):
    if _is_parent:
        return null
    var data = _view.tile_drag_start(_node.path)

    var preview = TextureRect.new()
    preview.texture = _icon.texture
    preview.expand = true
    preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    preview.rect_min_size = Vector2(48, 48)
    set_drag_preview(preview)
    return data

func can_drop_data(position, data):
    return not _is_parent and _node.is_dir and _view.is_files_data(data)

func drop_data(position, data):
    if _node.is_dir:
        _view.do_drop(data, _node.path)
