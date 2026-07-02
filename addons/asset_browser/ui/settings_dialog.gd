tool
extends WindowDialog
class_name ABSettingsDialog

var _s = null

var _layout = null
var _scan_mode = null
var _rebuild_mode = null
var _cache_mode = null
var _show_parent = null
var _poll_when_visible = null
var _lazy_subdirs = null
var _virtualize = null
var _defer_size = null
var _search_async = null
var _content_opt_in = null
var _preview_only_visible = null
var _persist_suspended = null
var _max_prev = null
var _grid_gap = null
var _row_gap = null
var _font = null
var _freq = null
var _coalesce = null
var _tree_refresh = null
var _ttl = null
var _sweep = null
var _heavy_n = null
var _heavy_ms = null
var _tiles_n = null
var _tiles_ms = null
var _repop_ms = null
var _search_nodes_n = null
var _search_ms = null
var _content_max = null
var _search_debounce = null
var _search_max = null

const LAYOUT_MODES = [
    "left_hier_right_files", "left_files_right_hier",
    "top_hier_bottom_files", "bottom_hier_top_files", "combined"
]
const SCAN_MODES = ["event_only", "event_plus_poll", "poll_only"]
const REBUILD_MODES = ["full", "incremental"]
const CACHE_MODES = ["engine_lazy", "full_memory"]

func build(settings):
    _s = settings
    window_title = "Asset Browser Settings"
    rect_min_size = Vector2(460, 620)

    var scroll = ScrollContainer.new()
    scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_KEEP_SIZE, 10)
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(scroll)

    var vb = VBoxContainer.new()
    vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(vb)

    _header(vb, "Profiles")
    var prof_row = HBoxContainer.new()
    _add_profile_btn(prof_row, "Low CPU / Low RAM", ABSettings.Profile.LOW_CPU_LOW_RAM)
    _add_profile_btn(prof_row, "Balanced", ABSettings.Profile.BALANCED)
    _add_profile_btn(prof_row, "Responsive", ABSettings.Profile.RESPONSIVE)
    vb.add_child(prof_row)

    _header(vb, "Filesystem scan")
    _scan_mode = _enum(vb, "Scan mode", SCAN_MODES, _s.scan_mode_raw)
    _freq = _spin(vb, "Poll frequency sec", 1, 120, 1, int(_s.frequency_sec))
    _coalesce = _spin(vb, "Coalesce window ms", 0, 2000, 50, _s.coalesce_ms)
    _poll_when_visible = _check(vb, "Poll only when visible", _s.poll_only_when_visible)

    _header(vb, "Hierarchy tree")
    _lazy_subdirs = _check(vb, "Lazy subdirectories", _s.lazy_subdirs)
    _rebuild_mode = _enum(vb, "Rebuild mode", REBUILD_MODES, _s.rebuild_mode_raw)
    _tree_refresh = _spin(vb, "Refresh min interval ms", 0, 5000, 50, _s.tree_refresh_min_ms)

    _header(vb, "Files / grid")
    _tiles_n = _spin(vb, "Tiles per frame", 1, 256, 1, _s.tiles_per_frame)
    _tiles_ms = _spin(vb, "Tiles frame budget ms", 1, 100, 1, _s.tiles_frame_budget_ms)
    _virtualize = _check(vb, "Virtualize grid", _s.virtualize_grid)
    _repop_ms = _spin(vb, "Repopulate min interval ms", 0, 2000, 50, _s.repopulate_min_ms)
    _defer_size = _check(vb, "Defer size column", _s.defer_size_column)

    _header(vb, "Search")
    _search_async = _check(vb, "Async / chunked search", _s.search_async)
    _search_nodes_n = _spin(vb, "Nodes per frame", 16, 4096, 16, _s.search_nodes_per_frame)
    _search_ms = _spin(vb, "Search frame budget ms", 1, 100, 1, _s.search_frame_budget_ms)
    _content_max = _spin(vb, "Content max files", 0, 50000, 50, _s.content_max_files)
    _content_opt_in = _check(vb, "Global content requires opt-in", _s.content_requires_global_optin)
    _search_debounce = _spin(vb, "Search debounce ms", 0, 2000, 50, _s.search_debounce_ms)
    _search_max = _spin(vb, "Search max results", 50, 50000, 50, _s.search_max_results)

    _header(vb, "Preview")
    _cache_mode = _enum(vb, "Cache mode", CACHE_MODES, _s.cache_mode_raw)
    _preview_only_visible = _check(vb, "Queue previews only for visible", _s.preview_only_visible)
    _heavy_n = _spin(vb, "Heavy previews / frame", 1, 64, 1, _s.heavy_per_frame)
    _heavy_ms = _spin(vb, "Heavy frame budget ms", 1, 100, 1, _s.heavy_frame_budget_ms)
    _ttl = _spin(vb, "Cache TTL sec (full_memory)", 5, 3600, 5, int(_s.cache_ttl_sec))
    _sweep = _spin(vb, "Cache sweep interval sec", 1, 600, 1, _s.cache_sweep_interval_sec)
    _max_prev = _spin(vb, "Max grid cell px", 16, 2048, 8, _s.max_preview_size)

    _header(vb, "Lifecycle")
    _persist_suspended = _check(vb, "Persist suspended across sessions", _s.persist_suspended)

    _header(vb, "Appearance")
    _layout = _enum(vb, "Layout mode", LAYOUT_MODES, _s.layout_mode)
    _show_parent = _check(vb, "Show \"..\" parent entry", _s.show_parent_folder)
    _grid_gap = _spin(vb, "Grid tile gap px", 0, 64, 1, _s.grid_tile_gap)
    _row_gap = _spin(vb, "List row gap px", 0, 32, 1, _s.list_row_gap)
    _font = _spin(vb, "Font size px", 8, 32, 1, _s.font_size)

    var apply = Button.new()
    apply.text = "Apply"
    apply.connect("pressed", self, "on_apply")
    vb.add_child(apply)

func _header(parent, text):
    var l = Label.new()
    l.text = text
    l.add_color_override("font_color", Color(0.55, 0.7, 1))
    parent.add_child(HSeparator.new())
    parent.add_child(l)

func _add_profile_btn(row, text, p):
    var b = Button.new()
    b.text = text
    b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    b.connect("pressed", self, "on_profile", [p])
    row.add_child(b)

func _row(parent, label, c):
    var h = HBoxContainer.new()
    var l = Label.new()
    l.text = label
    l.rect_min_size = Vector2(200, 0)
    h.add_child(l)
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    h.add_child(c)
    parent.add_child(h)

func _spin(parent, label, mn, mx, step, val):
    var s = SpinBox.new()
    s.min_value = mn
    s.max_value = mx
    s.step = step
    s.value = val
    _row(parent, label, s)
    return s

func _check(parent, label, val):
    var c = CheckBox.new()
    c.pressed = val
    _row(parent, label, c)
    return c

func _enum(parent, label, options, current):
    var o = OptionButton.new()
    for i in range(options.size()):
        o.add_item(options[i], i)
    var idx = options.find(current)
    o.selected = 0 if idx < 0 else idx
    _row(parent, label, o)
    return o

func on_profile(profile):
    _s.apply_profile(profile)
    hide()

func on_apply():
    var e = [
        ["scan", "scan_mode", SCAN_MODES[_scan_mode.selected]],
        ["scan", "frequency_sec", float(_freq.value)],
        ["scan", "coalesce_ms", int(_coalesce.value)],
        ["scan", "poll_only_when_visible", _poll_when_visible.pressed],
        ["tree", "lazy_subdirs", _lazy_subdirs.pressed],
        ["tree", "rebuild_mode", REBUILD_MODES[_rebuild_mode.selected]],
        ["tree", "refresh_min_interval_ms", int(_tree_refresh.value)],
        ["files", "tiles_per_frame", int(_tiles_n.value)],
        ["files", "tiles_frame_budget_ms", int(_tiles_ms.value)],
        ["files", "virtualize_grid", _virtualize.pressed],
        ["files", "repopulate_min_interval_ms", int(_repop_ms.value)],
        ["files", "defer_size_column", _defer_size.pressed],
        ["search", "async", _search_async.pressed],
        ["search", "nodes_per_frame", int(_search_nodes_n.value)],
        ["search", "frame_budget_ms", int(_search_ms.value)],
        ["search", "content_max_files", int(_content_max.value)],
        ["search", "content_requires_global_optin", _content_opt_in.pressed],
        ["search", "debounce_ms", int(_search_debounce.value)],
        ["search", "max_results", int(_search_max.value)],
        ["preview", "cache_mode", CACHE_MODES[_cache_mode.selected]],
        ["preview", "only_visible", _preview_only_visible.pressed],
        ["preview", "heavy_previews_per_frame", int(_heavy_n.value)],
        ["preview", "heavy_frame_budget_ms", int(_heavy_ms.value)],
        ["preview", "cache_ttl_sec", float(_ttl.value)],
        ["preview", "cache_sweep_interval_sec", int(_sweep.value)],
        ["preview", "max_preview_size_px", int(_max_prev.value)],
        ["lifecycle", "persist_suspended", _persist_suspended.pressed],
        ["layout", "mode", LAYOUT_MODES[_layout.selected]],
        ["nav", "show_parent_folder", _show_parent.pressed],
        ["spacing", "grid_tile_gap_px", int(_grid_gap.value)],
        ["spacing", "list_row_gap_px", int(_row_gap.value)],
        ["spacing", "font_size_px", int(_font.value)],
    ]
    _s.set_batch(e)
    hide()
