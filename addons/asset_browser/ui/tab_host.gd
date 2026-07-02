tool
extends VBoxContainer
class_name ABTabHost

# Хост вкладок одного инстанса редактора (dock или bottom). Реализует контракт
# ILifecycleHost (утиная типизация): save_state/teardown/show_placeholder/rebuild_body.

var state_id = "dock"
var run_scan_timer = true
var loaded_suspended = false

var _s = null
var _tabs_row = null
var _content = null
var _placeholder = null

var _states = []
var _views = []
var _active = -1

var _scan_timer = null
var _thumb_timer = null

var _settings_connected = false

func _state_path():
    return "user://asset_browser/tabs_" + state_id + ".cfg"

func init(shared):
    _s = shared

func _enter_tree():
    if _s != null and _s.lifecycle != null:
        _s.lifecycle.register(self)

func _ready():
    if name != "Asset Browser":
        name = "Asset Browser"
    rect_min_size = Vector2(80, 200)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    rect_clip_content = true

    if _s.lifecycle.is_suspended:
        show_placeholder()
        return

    _build_body()

# ---------- построение/разрушение тела ----------
func _build_body():
    _tabs_row = HBoxContainer.new()
    _tabs_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(_tabs_row)

    _content = Control.new()
    _content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(_content)

    _configure_timers()
    _connect_settings()

    load_state()
    if _states.size() == 0:
        new_tab(null)
    _rebuild_tabs_row()
    set_active(0 if _active < 0 else _active)

func _configure_timers():
    var want_scan = run_scan_timer and _s.settings.scan_mode != ABSettings.ScanMode.EVENT_ONLY
    if want_scan:
        if _scan_timer == null or not is_instance_valid(_scan_timer):
            _scan_timer = Timer.new()
            _scan_timer.autostart = true
            _scan_timer.connect("timeout", self, "on_scan_tick")
            add_child(_scan_timer)
        _scan_timer.wait_time = max(1.0, _s.settings.frequency_sec)
        if _scan_timer.is_stopped():
            _scan_timer.start()
    elif _scan_timer != null and is_instance_valid(_scan_timer):
        _scan_timer.stop()
        _scan_timer.queue_free()
        _scan_timer = null

    var want_thumb = _s.settings.cache_mode == ABSettings.PreviewCacheMode.FULL_MEMORY
    if want_thumb:
        if _thumb_timer == null or not is_instance_valid(_thumb_timer):
            _thumb_timer = Timer.new()
            _thumb_timer.autostart = true
            _thumb_timer.connect("timeout", self, "on_thumb_tick")
            add_child(_thumb_timer)
        _thumb_timer.wait_time = max(1.0, _s.settings.cache_sweep_interval_sec)
        if _thumb_timer.is_stopped():
            _thumb_timer.start()
    elif _thumb_timer != null and is_instance_valid(_thumb_timer):
        _thumb_timer.stop()
        _thumb_timer.queue_free()
        _thumb_timer = null

func _connect_settings():
    if _settings_connected:
        return
    _s.settings.connect("changed", self, "on_settings_changed")
    _settings_connected = true

func _disconnect_settings():
    if not _settings_connected:
        return
    if _s != null and is_instance_valid(_s.settings) and _s.settings.is_connected("changed", self, "on_settings_changed"):
        _s.settings.disconnect("changed", self, "on_settings_changed")
    _settings_connected = false

func on_settings_changed():
    _configure_timers()

# ---------- тики ----------
func on_scan_tick():
    if _scan_timer != null and is_instance_valid(_scan_timer):
        _scan_timer.wait_time = max(1.0, _s.settings.frequency_sec)

    if _s.settings.poll_only_when_visible and not is_visible_in_tree():
        return

    _s.db.request_scan()

    if _s.settings.scan_mode == ABSettings.ScanMode.POLL_ONLY:
        _s.db.call_deferred("emit_tree_changed")

func on_thumb_tick():
    if _active >= 0 and _active < _views.size():
        _views[_active].touch_visible_thumbs()
    _s.thumbs.sweep_cache()

# ---------- tabs ----------
func new_tab(state):
    var st = state if state != null else ABBrowserTabState.new()
    var view = ABBrowserView.new()
    view.visible = false
    _content.add_child(view)
    view.build(_s, st)
    view.set_anchors_and_margins_preset(Control.PRESET_WIDE)

    _states.append(st)
    _views.append(view)
    _rebuild_tabs_row()
    set_active(_states.size() - 1)

func duplicate_tab(i):
    if i < 0 or i >= _states.size():
        return
    new_tab(_states[i].clone())

func close_tab(i):
    if _states.size() <= 1 or i < 0 or i >= _states.size():
        return
    _views[i].disconnect_shared()
    _views[i].queue_free()
    _views.remove(i)
    _states.remove(i)
    if _active >= _states.size():
        _active = _states.size() - 1
    _rebuild_tabs_row()
    set_active(_active)

func set_active(i):
    if i < 0 or i >= _views.size():
        return
    for k in range(_views.size()):
        _views[k].visible = (k == i)
    _active = i
    _rebuild_tabs_row()

func _rebuild_tabs_row():
    if _tabs_row == null or not is_instance_valid(_tabs_row):
        return
    for c in _tabs_row.get_children():
        c.queue_free()

    for i in range(_states.size()):
        var tab_box = HBoxContainer.new()
        var btn = Button.new()
        btn.text = _states[i].title
        btn.toggle_mode = true
        btn.pressed = (i == _active)
        btn.focus_mode = Control.FOCUS_NONE
        btn.connect("pressed", self, "on_tab_pressed", [i])
        tab_box.add_child(btn)

        if _states.size() > 1:
            var x = Button.new()
            x.text = "x"
            x.focus_mode = Control.FOCUS_NONE
            x.connect("pressed", self, "on_tab_close", [i])
            tab_box.add_child(x)
        _tabs_row.add_child(tab_box)

    var plus = Button.new()
    plus.text = "+"
    plus.focus_mode = Control.FOCUS_NONE
    plus.connect("pressed", self, "on_new_tab")
    _tabs_row.add_child(plus)

func on_tab_pressed(i):
    set_active(i)

func on_tab_close(i):
    close_tab(i)

func on_new_tab():
    new_tab(null)

# ---------- ILifecycleHost ----------
func teardown():
    _disconnect_settings()

    if _scan_timer != null and is_instance_valid(_scan_timer):
        _scan_timer.stop()
        _scan_timer.queue_free()
        _scan_timer = null
    if _thumb_timer != null and is_instance_valid(_thumb_timer):
        _thumb_timer.stop()
        _thumb_timer.queue_free()
        _thumb_timer = null

    for i in range(_views.size()):
        if _views[i] != null and is_instance_valid(_views[i]):
            _views[i].disconnect_shared()
            _views[i].queue_free()
    _views.clear()
    _states.clear()
    _active = -1

    if _tabs_row != null and is_instance_valid(_tabs_row):
        _tabs_row.queue_free()
        _tabs_row = null
    if _content != null and is_instance_valid(_content):
        _content.queue_free()
        _content = null

func show_placeholder():
    if _placeholder != null and is_instance_valid(_placeholder):
        return

    var center = CenterContainer.new()
    center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    center.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var box = VBoxContainer.new()
    var lbl = Label.new()
    lbl.text = "Asset Browser приостановлен"
    lbl.align = Label.ALIGN_CENTER
    box.add_child(lbl)

    var btn = Button.new()
    btn.text = "Resume"
    btn.connect("pressed", self, "on_resume_pressed")
    box.add_child(btn)

    center.add_child(box)
    _placeholder = center
    add_child(center)

func on_resume_pressed():
    _s.lifecycle.resume()

func rebuild_body():
    if _placeholder != null and is_instance_valid(_placeholder):
        _placeholder.queue_free()
        _placeholder = null
    _build_body()

# ---------- persistence ----------
func save_state():
    var d = Directory.new()
    if not d.dir_exists("user://asset_browser"):
        d.make_dir_recursive("user://asset_browser")
    var cfg = ConfigFile.new()
    cfg.set_value("host", "active", _active)
    cfg.set_value("host", "count", _states.size())
    cfg.set_value("host", "suspended", _s.lifecycle.is_suspended)
    for i in range(_states.size()):
        var s = _states[i]
        var sec = "tab_" + str(i)
        cfg.set_value(sec, "dir", s.current_dir)
        cfg.set_value(sec, "view", s.view)
        cfg.set_value(sec, "preview", s.preview_size)
        cfg.set_value(sec, "ratio", s.splitter_ratio)
        cfg.set_value(sec, "sort_col", s.sort_column)
        cfg.set_value(sec, "sort_asc", s.sort_asc)
        cfg.set_value(sec, "col_name", s.col_name)
        cfg.set_value(sec, "col_type", s.col_type)
        cfg.set_value(sec, "title", s.title)
        cfg.set_value(sec, "search", s.search.text)
    cfg.save(_state_path())

func load_state():
    var cfg = ConfigFile.new()
    if cfg.load(_state_path()) != OK:
        return
    loaded_suspended = bool(cfg.get_value("host", "suspended", false))
    var count = int(cfg.get_value("host", "count", 0))
    for i in range(count):
        var sec = "tab_" + str(i)
        var st = ABBrowserTabState.new()
        st.current_dir = str(cfg.get_value(sec, "dir", "res://"))
        st.view = int(cfg.get_value(sec, "view", ABBrowserTabState.ViewMode.GRID))
        st.preview_size = int(cfg.get_value(sec, "preview", 64))
        st.splitter_ratio = float(cfg.get_value(sec, "ratio", 0.3))
        st.sort_column = str(cfg.get_value(sec, "sort_col", "Name"))
        st.sort_asc = bool(cfg.get_value(sec, "sort_asc", true))
        st.col_name = int(cfg.get_value(sec, "col_name", 220))
        st.col_type = int(cfg.get_value(sec, "col_type", 90))
        st.title = str(cfg.get_value(sec, "title", "Assets"))
        st.search.text = str(cfg.get_value(sec, "search", ""))
        _new_tab_silent(st)
    _active = int(cfg.get_value("host", "active", 0))

func _new_tab_silent(st):
    var view = ABBrowserView.new()
    view.visible = false
    _content.add_child(view)
    view.build(_s, st)
    view.set_anchors_and_margins_preset(Control.PRESET_WIDE)
    _states.append(st)
    _views.append(view)
