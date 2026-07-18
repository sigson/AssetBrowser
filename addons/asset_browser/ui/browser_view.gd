tool
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
var _import = null

func build(shared, state):
    _s = shared
    _state = state
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    rect_clip_content = true

    _toolbar = ABToolbar.new()
    _toolbar.build(_s, _state.search)
    _toolbar.connect("back_pressed", self, "on_back")
    _toolbar.connect("forward_pressed", self, "on_forward")
    _toolbar.connect("up_pressed", self, "on_up")
    _toolbar.connect("create_requested", self, "on_create")
    _toolbar.connect("settings_requested", self, "on_settings")
    _toolbar.connect("search_changed", self, "on_search")
    _toolbar.connect("segment_picked", self, "on_segment")
    _toolbar.connect("sort_requested", self, "on_sort_requested")
    _toolbar.connect("freeze_toggled", self, "on_freeze_toggled")
    _toolbar.connect("import_requested", self, "on_import_requested")
    add_child(_toolbar)

    _build_work_area()

    _status = ABStatusBar.new()
    _status.build(_state.preview_size, _s.settings.max_preview_size)
    _status.connect("zoom_changed", self, "on_zoom")
    add_child(_status)

    _settings_dlg = ABSettingsDialog.new()
    _settings_dlg.build(_s.settings)
    add_child(_settings_dlg)

    # Зеркалирование выделения в FileSystemDock — иначе окно Import видит
    # только то, что выделено там, а не группу, выбранную здесь.
    _import = ABImportBridge.new()
    add_child(_import)
    _import.build(_s)
    _import.connect("note", self, "on_import_note")

    _tree_debounce = Timer.new()
    _tree_debounce.one_shot = true
    _tree_debounce.connect("timeout", self, "apply_tree_changed")
    add_child(_tree_debounce)

    _s.db.connect("tree_changed", self, "on_tree_changed")
    _s.settings.connect("changed", self, "on_settings_changed")
    _s.git.connect("status_changed", self, "on_git_status_changed")
    _shared_connected = true

    _sync_all()

func disconnect_shared():
    if not _shared_connected:
        return
    if _s != null and is_instance_valid(_s.db) and _s.db.is_connected("tree_changed", self, "on_tree_changed"):
        _s.db.disconnect("tree_changed", self, "on_tree_changed")
    if _s != null and is_instance_valid(_s.settings) and _s.settings.is_connected("changed", self, "on_settings_changed"):
        _s.settings.disconnect("changed", self, "on_settings_changed")
    if _s != null and is_instance_valid(_s.git) and _s.git.is_connected("status_changed", self, "on_git_status_changed"):
        _s.git.disconnect("status_changed", self, "on_git_status_changed")
    _shared_connected = false

func _build_work_area():
    if _split_or_single != null:
        # remove_child немедленный, queue_free — нет: без этого старая и новая
        # рабочие области кадр делят высоту пополам (см. ABFileView._drop_view).
        if is_instance_valid(_split_or_single):
            if _split_or_single.get_parent() == self:
                remove_child(_split_or_single)
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

        if hier_first:
            split.add_child(_hier)
            split.add_child(_files)
        else:
            split.add_child(_files)
            split.add_child(_hier)

        split.split_offset = int(_state.splitter_ratio * 300)
        split.connect("dragged", self, "on_split_dragged")
        _split_or_single = split

        _hier.connect("dir_selected", self, "on_dir_selected")

    _files.connect("dir_entered", self, "on_dir_entered")
    _files.connect("reveal_requested", self, "on_reveal")
    _files.connect("edit_requested", self, "on_edit")
    _files.connect("status_update", self, "on_status")
    _files.connect("note_update", self, "on_note")
    _files.connect("hidden_update", self, "on_hidden")
    _files.connect("diag_update", self, "on_diag")
    _files.connect("selection_changed", self, "on_selection_changed")
    _files.connect("create_requested", self, "on_create")

    add_child_below_node(_toolbar, _split_or_single)

# ---------- nav ----------
func navigate(dir, record):
    _state.navigate_to(dir, record)
    _sync_all()

func _sync_all():
    _release_freeze()
    _toolbar.update_nav(_state.can_back(), _state.can_fwd(), _state.current_dir)
    _toolbar.set_sort(_state.sort_column, _state.sort_asc)
    if _hier != null:
        _hier.set_git_view(_state.search.git_view)
        _hier.select_dir(_state.current_dir)
    _files.populate()
    _state.title = "Assets" if _state.current_dir == "res://" else _state.current_dir.substr(_state.current_dir.find_last("/") + 1)

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
    if _hier != null:
        _hier.set_git_view(_state.search.git_view)
    _files.populate()

func on_status(count, sel_path):
    _status.set_info(count, sel_path)

func on_note(note):
    _status.set_note(note)

func on_hidden(count, summary):
    _status.set_hidden(count, summary)

func on_diag(text):
    _status.set_diag(text)

# Авто-синк отключён: выделение только запоминается, в док его отправляет
# кнопка на тулбаре — так видно, дошло оно до Import или нет.
func on_selection_changed(sel):
    _state.selection = Array(sel)

func on_import_requested():
    if _import == null:
        return
    if _state.selection.size() == 0:
        _status.set_note("import: ничего не выделено")
        return
    _import.push_now(_state.selection)

func on_import_note(text):
    if text != null and text != "":
        _status.set_note(text)

func on_git_status_changed():
    if _hier != null:
        _hier.refresh_git_colors()
    if _state.search.git_view:
        _files.populate()

func on_split_dragged(offset):
    _state.splitter_ratio = offset / 300.0

# ---------- edit/open ----------
func on_edit(path):
    var ext = path.substr(path.find_last(".") + 1).to_lower()
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
            ABFileOps.create_resource(dir + "/new_material.tres", SpatialMaterial.new())
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
    if _state.search.git_view:
        _s.git.ensure_fresh()

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
