tool
extends EditorPlugin

const CONFIG_PATH = "res://addons/asset_browser/config.tres"

var _shared = null
var _dock_host = null
var _bottom_host = null

func _enter_tree():
    _build_plugin()

func _build_plugin():
    _shared = ABShared.new()
    _shared.init(get_editor_interface(), get_undo_redo())
    _shared.restart_hook = funcref(self, "request_restart")

    var cfg = _load_or_create_config()
    var primary_assigned = false

    if cfg.open_in_dock:
        _dock_host = _make_host("dock", not primary_assigned)
        primary_assigned = true
        add_control_to_dock(cfg.dock_slot, _dock_host)

    if cfg.open_in_bottom_panel:
        _bottom_host = _make_host("bottom", not primary_assigned)
        primary_assigned = true
        var title = "Asset Browser" if cfg.bottom_panel_title == "" else cfg.bottom_panel_title
        add_control_to_bottom_panel(_bottom_host, title)

    if _dock_host == null and _bottom_host == null:
        _dock_host = _make_host("dock", true)
        add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UL, _dock_host)

    _shared.db.request_scan()

    call_deferred("apply_persisted_suspend")

func request_restart():
    call_deferred("restart_plugin")

func restart_plugin():
    _teardown_plugin()
    _build_plugin()

func apply_persisted_suspend():
    if _shared == null or not _shared.settings.persist_suspended:
        return
    var was_suspended = (_dock_host != null and _dock_host.loaded_suspended) \
        or (_bottom_host != null and _bottom_host.loaded_suspended)
    if was_suspended and not _shared.lifecycle.is_suspended:
        _shared.lifecycle.suspend()

func _make_host(state_id, primary):
    var h = ABTabHost.new()
    h.name = "Asset Browser"
    h.state_id = state_id
    h.run_scan_timer = primary
    h.init(_shared)
    return h

func _load_or_create_config():
    if ResourceLoader.exists(CONFIG_PATH):
        var loaded = ResourceLoader.load(CONFIG_PATH)
        return loaded if loaded != null else ABAssetBrowserConfig.new()

    var cfg = ABAssetBrowserConfig.new()
    ResourceSaver.save(CONFIG_PATH, cfg)
    return cfg

func _exit_tree():
    _teardown_plugin()

func _teardown_plugin():
    if _shared != null:
        _shared.restart_hook = null

    if _dock_host != null:
        _dock_host.save_state()
        remove_control_from_docks(_dock_host)
        _dock_host.free()
        _dock_host = null
    if _bottom_host != null:
        _bottom_host.save_state()
        remove_control_from_bottom_panel(_bottom_host)
        _bottom_host.free()
        _bottom_host = null
    if _shared != null:
        _shared.dispose2()
    _shared = null

func get_window_layout(layout):
    if _dock_host != null:
        _dock_host.save_state()
    if _bottom_host != null:
        _bottom_host.save_state()

func set_window_layout(layout):
    pass
