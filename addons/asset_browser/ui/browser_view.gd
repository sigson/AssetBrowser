@tool
extends VBoxContainer
class_name ABBrowserView

var _s = null
var _state = null

var _toolbar = null
var _hier = null
var _files = null
var _status = null
var _split_or_single = null
var _settings_dlg = null
var _tree_debounce = null
var _shared_connected = false
var _frozen = false

func build(shared, state):
    _s = shared
    _state = state
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    clip_contents = true

    _toolbar = ABToolbar.new()
    _toolbar.build(_s, _state.search)
    _toolbar.connect("back_pressed", Callable(self, "on_back"))
    _toolbar.connect("forward_pressed", Callable(self, "on_forward"))
    _toolbar.connect("up_pressed", Callable(self, "on_up"))
    _toolbar.connect("create_requested", Callable(self, "on_create"))
    _toolbar.connect("settings_requested", Callable(self, "on_settings"))
    _toolbar.connect("search_changed", Callable(self, "on_search"))
    _toolbar.connect("segment_picked", Callable(self, "on_segment"))
    _toolbar.connect("sort_requested", Callable(self, "on_sort_requested"))
    _toolbar.connect("freeze_toggled", Callable(self, "on_freeze_toggled"))
    add_child(_toolbar)

    _build_work_area()

    _status = ABStatusBar.new()
    _status.build(_state.preview_size, _s.settings.max_preview_size)
    _status.connect("zoom_changed", Callable(self, "on_zoom"))
    add_child(_status)

    _settings_dlg = ABSettingsDialog.new()
    _settings_dlg.build(_s.settings)
    add_child(_settings_dlg)

    _tree_debounce = Timer.new()
    _tree_debounce.one_shot = true
    _tree_debounce.connect("timeout", Callable(self, "apply_tree_changed"))
    add_child(_tree_debounce)

    _s.db.connect("tree_changed", Callable(self, "on_tree_changed"))
    _s.settings.connect("changed", Callable(self, "on_settings_changed"))
    _shared_connected = true

    _sync_all()

func disconnect_shared():
    if not _shared_connected:
        return
    if _s != null and is_instance_valid(_s.db) and _s.db.is_connected("tree_changed", Callable(self, "on_tree_changed")):
        _s.db.disconnect("tree_changed", Callable(self, "on_tree_changed"))
    if _s != null and is_instance_valid(_s.settings) and _s.settings.is_connected("changed", Callable(self, "on_settings_changed")):
        _s.settings.disconnect("changed", Callable(self, "on_settings_changed"))
    _shared_connected = false

func _build_work_area():
    if _split_or_single != null:
        _split_or_single.queue_free()
        _split_or_single = null

    _hier = null
    _files = ABFileView.new()

    var mode = _s.settings.layout_mode
    if mode == "combined":
        _files.build(_s, _state)
        _files.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _split_or_single = VBoxContainer.new()
        _split_or_single.size_flags_vertical = Control.SIZE_EXPAND_FILL
        _split_or_single.add_child(_files)
    else:
        var horizontal = mode.begins_with("left_")
        var hier_first = mode == "left_hier_right_files" or mode == "top_hier_bottom_files"

        _hier = ABHierarchyPane.new()
        _hier.build(_s)
        _files.build(_s, _state)

        var split = HSplitContainer.new() if horizontal else VSplitContainer.new()
        split.size_flags_vertical = Control.SIZE_EXPAND_FILL
        split.size_flags_horizontal = Control.SIZE_EXPAND_FILL

        # Явный, но тематический разделитель: обе области — в панелях с рамкой из
        # цвета темы редактора, стыкующая сторона рисуется толще.
        var first = _hier if hier_first else _files
        var second = _files if hier_first else _hier
        var first_edge = "right" if horizontal else "bottom"
        var second_edge = "left" if horizontal else "top"
        split.add_child(_wrap_pane(first, first_edge))
        split.add_child(_wrap_pane(second, second_edge))

        split.split_offset = int(_state.splitter_ratio * 300)
        split.connect("dragged", Callable(self, "on_split_dragged"))
        _split_or_single = split

        _hier.connect("dir_selected", Callable(self, "on_dir_selected"))

    _files.connect("dir_entered", Callable(self, "on_dir_entered"))
    _files.connect("reveal_requested", Callable(self, "on_reveal"))
    _files.connect("edit_requested", Callable(self, "on_edit"))
    _files.connect("status_update", Callable(self, "on_status"))
    _files.connect("note_update", Callable(self, "on_note"))
    _files.connect("create_requested", Callable(self, "on_create"))

    _toolbar.add_sibling(_split_or_single)

# ---------- тематическое разделение областей ----------
func _wrap_pane(ctrl, accent_edge):
    var panel = PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", _pane_style(accent_edge))
    ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    ctrl.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(ctrl)
    return panel

func _editor_base():
    if _s != null and _s.editor != null:
        return _s.editor.get_base_control()
    return null

func _theme_color(cname, fallback):
    var bc = _editor_base()
    if bc != null and bc.has_theme_color(cname, "Editor"):
        return bc.get_theme_color(cname, "Editor")
    return fallback

func _pane_style(accent_edge):
    # Всё берём из темы редактора, чтобы разделение жило и в тёмной, и в светлой теме.
    var base = _theme_color("base_color", Color(0.16, 0.16, 0.18, 1.0))
    var fg = _theme_color("font_color", Color(1, 1, 1, 1))
    var line = Color(fg.r, fg.g, fg.b, 0.28)

    var sb = StyleBoxFlat.new()
    # Оттенок панели чуть смещён от фона редактора, чтобы область читалась как отдельная.
    sb.bg_color = base.lightened(0.05) if base.get_luminance() < 0.5 else base.darkened(0.05)
    sb.set_border_width_all(1)
    sb.border_color = line
    # Стыкующая сторона — заметная линия-разделитель (толще).
    match accent_edge:
        "left":
            sb.border_width_left = 3
        "right":
            sb.border_width_right = 3
        "top":
            sb.border_width_top = 3
        "bottom":
            sb.border_width_bottom = 3
    sb.content_margin_left = 3
    sb.content_margin_top = 3
    sb.content_margin_right = 3
    sb.content_margin_bottom = 3
    return sb

# ---------- nav ----------
func navigate(dir, record):
    _state.navigate_to(dir, record)
    _sync_all()

func _sync_all():
    _release_freeze()
    _toolbar.update_nav(_state.can_back(), _state.can_fwd(), _state.current_dir)
    _toolbar.set_sort(_state.sort_column, _state.sort_asc)
    if _hier != null:
        _hier.select_dir(_state.current_dir)
    _files.populate()
    _state.title = "Assets" if _state.current_dir == "res://" else _state.current_dir.substr(_state.current_dir.rfind("/") + 1)

func on_back():
    _state.back()
    _sync_all()

func on_forward():
    _state.forward()
    _sync_all()

func on_up():
    navigate(ABAssetDatabase.parent_dir(_state.current_dir), true)

func on_segment(dir):
    navigate(dir, true)

func on_dir_selected(dir):
    navigate(dir, true)

func on_dir_entered(dir):
    navigate(dir, true)

func on_reveal(dir):
    _state.search.text = ""
    _toolbar.sync_search_input()
    navigate(dir, true)

func on_sort_requested(column, asc):
    _release_freeze()
    _state.sort_column = column
    _state.sort_asc = asc
    _files.populate()

func on_search():
    _release_freeze()
    _files.populate()

func on_status(count, sel_path):
    _status.set_info(count, sel_path)

func on_note(note):
    _status.set_note(note)

func on_split_dragged(offset):
    _state.splitter_ratio = offset / 300.0

# ---------- edit/open ----------
func on_edit(path):
    var ext = path.substr(path.rfind(".") + 1).to_lower()
    if ext == "tscn" or ext == "scn":
        _s.editor.open_scene_from_path(path)
        return
    var res = ResourceLoader.load(path)
    if res != null:
        _s.editor.edit_resource(res)
    else:
        OS.shell_open(ProjectSettings.globalize_path(path))

# ---------- create ----------
func on_create(kind):
    var dir = _state.current_dir
    match kind:
        ABToolbar.CreateKind.FOLDER:
            ABFileOps.make_folder(dir + "/New Folder")
        ABToolbar.CreateKind.TEXT_FILE:
            ABFileOps.create_text_file(dir + "/new_file.txt", "")
        ABToolbar.CreateKind.MATERIAL:
            ABFileOps.create_resource(dir + "/new_material.tres", StandardMaterial3D.new())
        ABToolbar.CreateKind.SCENE:
            var root_node = Node.new()
            root_node.name = "Node"
            var ps = PackedScene.new()
            ps.pack(root_node)
            ABFileOps.create_resource(dir + "/new_scene.tscn", ps)
            root_node.free()
        ABToolbar.CreateKind.RESOURCE:
            ABFileOps.create_resource(dir + "/new_resource.tres", Resource.new())
    _s.db.request_scan()

# ---------- zoom ----------
func on_zoom(value):
    _state.preview_size = value
    var new_mode = ABBrowserTabState.ViewMode.LIST if value <= 24 else ABBrowserTabState.ViewMode.GRID
    if new_mode != _state.view:
        _state.view = new_mode
        _files.populate()
    elif _state.view == ABBrowserTabState.ViewMode.GRID:
        _files.populate()

func on_settings():
    _settings_dlg.popup_centered()

func on_tree_changed():
    var wait = max(0.01, _s.settings.coalesce_ms / 1000.0)
    _tree_debounce.start(wait)

func apply_tree_changed():
    var dir_changed = false
    if not _s.db.has_dir(_state.current_dir):
        var fallback = _s.db.nearest_existing_dir(_state.current_dir)
        _state.navigate_to(fallback, false)
        dir_changed = true

    if _hier != null:
        _hier.refresh()
        _hier.select_dir(_state.current_dir)
    _toolbar.update_nav(_state.can_back(), _state.can_fwd(), _state.current_dir)

    if _frozen and not dir_changed:
        return

    if dir_changed:
        _release_freeze()
    _files.populate()

func on_freeze_toggled(on):
    _frozen = on
    if _files != null:
        _files.set_frozen(on)

func _release_freeze():
    if not _frozen:
        return
    _frozen = false
    if _files != null:
        _files.set_frozen(false)
    _toolbar.set_freeze_visual(false)

func touch_visible_thumbs():
    _files.touch_visible_thumbs()

func on_settings_changed():
    _status.update_max(_s.settings.max_preview_size)
    _build_work_area()
    _sync_all()

func get_state():
    return _state
