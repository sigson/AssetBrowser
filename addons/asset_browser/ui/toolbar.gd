tool
extends VBoxContainer
class_name ABToolbar

enum CreateKind { FOLDER = 0, TEXT_FILE = 1, MATERIAL = 2, SCENE = 3, RESOURCE = 4 }

signal back_pressed()
signal forward_pressed()
signal up_pressed()
signal create_requested(kind)
signal settings_requested()
signal search_changed()
signal segment_picked(dir)
signal sort_requested(column, asc)
signal freeze_toggled(on)

var _s = null
var _back = null
var _fwd = null
var _up = null
var _kill = null
var _freeze = null
var _restart = null
var _create = null
var _sort = null
var _sort_col = "Name"
var _sort_asc = true
var crumbs = null
var search = null

func build(shared, state):
    _s = shared
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rect_clip_content = true

    var row = ABFlowContainer.new()
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(row)

    _back = _nav_button("Back", "<", "Back")
    _back.connect("pressed", self, "on_back")
    row.add_child(_back)

    _fwd = _nav_button("Forward", ">", "Forward")
    _fwd.connect("pressed", self, "on_fwd")
    row.add_child(_fwd)

    _up = _nav_button("ArrowUp", "^", "Parent folder")
    _up.connect("pressed", self, "on_up")
    row.add_child(_up)

    _create = MenuButton.new()
    _create.hint_tooltip = "Create"
    _create.focus_mode = Control.FOCUS_NONE
    var add_ic = _s.thumbs.editor_icon("Add") if _s != null else null
    if add_ic != null:
        _create.icon = add_ic
    else:
        _create.text = "+"
    var pm = _create.get_popup()
    pm.add_item("Folder", CreateKind.FOLDER)
    pm.add_item("Text File", CreateKind.TEXT_FILE)
    pm.add_item("Material", CreateKind.MATERIAL)
    pm.add_item("Scene", CreateKind.SCENE)
    pm.add_item("Resource", CreateKind.RESOURCE)
    pm.connect("id_pressed", self, "on_create")
    row.add_child(_create)

    _sort = MenuButton.new()
    _sort.hint_tooltip = "Sort"
    _sort.focus_mode = Control.FOCUS_NONE
    var sort_ic = _s.thumbs.editor_icon("Sort") if _s != null else null
    if sort_ic != null:
        _sort.icon = sort_ic
    else:
        _sort.text = "sort"
    var sp = _sort.get_popup()
    sp.add_radio_check_item("Name", 0)
    sp.add_radio_check_item("Type", 1)
    sp.add_radio_check_item("Size", 2)
    sp.add_separator()
    sp.add_check_item("Ascending", 10)
    sp.connect("id_pressed", self, "on_sort_pick")
    sp.connect("about_to_show", self, "refresh_sort_checks")
    row.add_child(_sort)

    var gear = Button.new()
    gear.hint_tooltip = "View settings"
    gear.focus_mode = Control.FOCUS_NONE
    var gear_ic = _s.thumbs.editor_icon("Tools") if _s != null else null
    if gear_ic != null:
        gear.icon = gear_ic
    else:
        gear.text = "cfg"
    gear.connect("pressed", self, "on_settings")
    row.add_child(gear)

    _freeze = Button.new()
    _freeze.toggle_mode = true
    _freeze.hint_tooltip = "Freeze current items"
    _freeze.focus_mode = Control.FOCUS_NONE
    var frz_ic = null
    if _s != null:
        frz_ic = _s.thumbs.editor_icon("Pin")
        if frz_ic == null:
            frz_ic = _s.thumbs.editor_icon("Lock")
    if frz_ic != null:
        _freeze.icon = frz_ic
    else:
        _freeze.text = "hold"
    _freeze.connect("pressed", self, "on_freeze")
    row.add_child(_freeze)

    _kill = Button.new()
    _kill.toggle_mode = true
    _kill.hint_tooltip = "Suspend / resume Asset Browser"
    _kill.focus_mode = Control.FOCUS_NONE
    var kill_ic = null
    if _s != null:
        kill_ic = _s.thumbs.editor_icon("Stop")
        if kill_ic == null:
            kill_ic = _s.thumbs.editor_icon("Power")
    if kill_ic != null:
        _kill.icon = kill_ic
    else:
        _kill.text = "off"
    _kill.pressed = _s != null and _s.lifecycle != null and _s.lifecycle.is_suspended
    _kill.connect("pressed", self, "on_killswitch")
    row.add_child(_kill)

    _restart = Button.new()
    _restart.hint_tooltip = "Restart Asset Browser plugin (rebuild after recompile)"
    _restart.focus_mode = Control.FOCUS_NONE
    var rs_ic = null
    if _s != null:
        rs_ic = _s.thumbs.editor_icon("Reload")
        if rs_ic == null:
            rs_ic = _s.thumbs.editor_icon("RotateRight")
    if rs_ic != null:
        _restart.icon = rs_ic
    else:
        _restart.text = "restart"
    _restart.connect("pressed", self, "on_restart")
    row.add_child(_restart)

    if _s != null and _s.lifecycle != null:
        _s.lifecycle.connect("suspended_changed", self, "on_suspended_changed")

    crumbs = ABBreadcrumbs.new()
    crumbs.set_shared(_s)
    crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    crumbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    crumbs.connect("segment_picked", self, "on_segment")
    row.add_child(crumbs)

    search = ABSearchBar.new()
    search.build(_s, state)
    search.connect("search_changed", self, "on_search")
    add_child(search)

func _nav_button(icon, fallback, tip):
    var b = Button.new()
    b.hint_tooltip = tip
    b.focus_mode = Control.FOCUS_NONE
    var ic = _s.thumbs.editor_icon(icon) if _s != null else null
    if ic != null:
        b.icon = ic
    else:
        b.text = fallback
    return b

func update_nav(can_back, can_fwd, current_dir):
    _back.disabled = not can_back
    _fwd.disabled = not can_fwd
    _up.disabled = ABAssetDatabase.normalize(current_dir) == "res://"
    crumbs.build(current_dir)

func set_sort(column, asc):
    _sort_col = column
    _sort_asc = asc

func sync_search_input():
    if search != null:
        search.sync_from_state()

func on_back():
    emit_signal("back_pressed")

func on_fwd():
    emit_signal("forward_pressed")

func on_up():
    emit_signal("up_pressed")

func on_create(id):
    emit_signal("create_requested", id)

func on_settings():
    emit_signal("settings_requested")

func on_search():
    emit_signal("search_changed")

func on_segment(dir):
    emit_signal("segment_picked", dir)

func on_sort_pick(id):
    if id == 0:
        _sort_col = "Name"
    elif id == 1:
        _sort_col = "Type"
    elif id == 2:
        _sort_col = "Size"
    elif id == 10:
        _sort_asc = not _sort_asc
    emit_signal("sort_requested", _sort_col, _sort_asc)

func on_killswitch():
    if _s != null and _s.lifecycle != null:
        _s.lifecycle.toggle()

func on_restart():
    if _s != null and _s.restart_hook != null:
        _s.call_restart_hook()

func on_freeze():
    emit_signal("freeze_toggled", _freeze.pressed)

func set_freeze_visual(on):
    if _freeze != null:
        _freeze.pressed = on

func on_suspended_changed(suspended):
    if _kill != null:
        _kill.pressed = suspended

func refresh_sort_checks():
    var p = _sort.get_popup()
    p.set_item_checked(0, _sort_col == "Name")
    p.set_item_checked(1, _sort_col == "Type")
    p.set_item_checked(2, _sort_col == "Size")
    p.set_item_checked(4, _sort_asc)
