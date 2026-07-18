tool
extends Reference
class_name ABSettings

# Режимы опроса ФС (ФТ-1).
enum ScanMode { EVENT_ONLY, EVENT_PLUS_POLL, POLL_ONLY }
# Режимы перестройки дерева иерархии (ФТ-2).
enum TreeRebuildMode { FULL, INCREMENTAL }
# Режимы кеширования превью (ФТ-5).
enum PreviewCacheMode { ENGINE_LAZY, FULL_MEMORY }
# Профили (§9).
enum Profile { LOW_CPU_LOW_RAM, BALANCED, RESPONSIVE }

const PATH = "res://addons/asset_browser/settings.cfg"

signal changed()

var _cfg = ConfigFile.new()

# ---------- [scan] (ФТ-1) ----------
var frequency_sec = 5.0
var scan_mode_raw = "event_only"
var scan_mode = ScanMode.EVENT_ONLY
var coalesce_ms = 250
var poll_only_when_visible = true

# ---------- [tree] (ФТ-2) ----------
var lazy_subdirs = true
var rebuild_mode_raw = "incremental"
var rebuild_mode = TreeRebuildMode.INCREMENTAL
var tree_refresh_min_ms = 500

# ---------- [files] (ФТ-3) ----------
var tiles_per_frame = 32
var tiles_frame_budget_ms = 6
var virtualize_grid = true
var repopulate_min_ms = 250
var defer_size_column = true

# ---------- [search] (ФТ-4) ----------
var search_async = true
var search_nodes_per_frame = 256
var search_frame_budget_ms = 6
var content_max_files = 500
var content_requires_global_optin = true
var search_debounce_ms = 300
var search_max_results = 1000

# ---------- [preview] (ФТ-5) ----------
var cache_mode_raw = "engine_lazy"
var cache_mode = PreviewCacheMode.ENGINE_LAZY
var preview_only_visible = true
var max_preview_size = 128
var cache_ttl_sec = 180.0
var heavy_per_frame = 4
var heavy_frame_budget_ms = 8
var cache_sweep_interval_sec = 10

# ---------- [lifecycle] (ФТ-6) ----------
var persist_suspended = false

# ---------- [git] ----------
var git_refresh_min_ms = 1500

# ---------- [layout]/[nav]/[spacing] ----------
var layout_mode = "left_hier_right_files"
var show_parent_folder = false
var grid_tile_gap = 8
var list_row_gap = 2
var font_size = 13

func load_data():
    if _cfg.load(PATH) != OK:
        _defaults()
    else:
        _migrate_dead_keys()
    _reload()

# Пересчитать кеш-поля из ConfigFile.
func _reload():
    frequency_sec = float(_read("scan", "frequency_sec", 5.0))
    scan_mode_raw = str(_read("scan", "scan_mode", "event_only"))
    scan_mode = parse_scan_mode(scan_mode_raw)
    coalesce_ms = int(_read("scan", "coalesce_ms", 250))
    poll_only_when_visible = bool(_read("scan", "poll_only_when_visible", true))

    lazy_subdirs = bool(_read("tree", "lazy_subdirs", true))
    rebuild_mode_raw = str(_read("tree", "rebuild_mode", "incremental"))
    rebuild_mode = parse_rebuild_mode(rebuild_mode_raw)
    tree_refresh_min_ms = int(_read("tree", "refresh_min_interval_ms", 500))

    tiles_per_frame = int(_read("files", "tiles_per_frame", 32))
    tiles_frame_budget_ms = int(_read("files", "tiles_frame_budget_ms", 6))
    virtualize_grid = bool(_read("files", "virtualize_grid", true))
    repopulate_min_ms = int(_read("files", "repopulate_min_interval_ms", 250))
    defer_size_column = bool(_read("files", "defer_size_column", true))

    search_async = bool(_read("search", "async", true))
    search_nodes_per_frame = int(_read("search", "nodes_per_frame", 256))
    search_frame_budget_ms = int(_read("search", "frame_budget_ms", 6))
    content_max_files = int(_read("search", "content_max_files", 500))
    content_requires_global_optin = bool(_read("search", "content_requires_global_optin", true))
    search_debounce_ms = int(_read("search", "debounce_ms", 300))
    search_max_results = int(_read("search", "max_results", 1000))

    cache_mode_raw = str(_read("preview", "cache_mode", "engine_lazy"))
    cache_mode = parse_cache_mode(cache_mode_raw)
    preview_only_visible = bool(_read("preview", "only_visible", true))
    max_preview_size = int(_read("preview", "max_preview_size_px", 128))
    cache_ttl_sec = float(_read("preview", "cache_ttl_sec", 180.0))
    heavy_per_frame = int(_read("preview", "heavy_previews_per_frame", 4))
    heavy_frame_budget_ms = int(_read("preview", "heavy_frame_budget_ms", 8))
    cache_sweep_interval_sec = int(_read("preview", "cache_sweep_interval_sec", 10))

    persist_suspended = bool(_read("lifecycle", "persist_suspended", false))

    git_refresh_min_ms = int(_read("git", "refresh_min_interval_ms", 1500))

    layout_mode = str(_read("layout", "mode", "left_hier_right_files"))
    show_parent_folder = bool(_read("nav", "show_parent_folder", false))
    grid_tile_gap = int(_read("spacing", "grid_tile_gap_px", 8))
    list_row_gap = int(_read("spacing", "list_row_gap_px", 2))
    font_size = int(_read("spacing", "font_size_px", 13))

func _defaults():
    _cfg.set_value("scan", "frequency_sec", 5.0)
    _cfg.set_value("scan", "scan_mode", "event_only")
    _cfg.set_value("scan", "coalesce_ms", 250)
    _cfg.set_value("scan", "poll_only_when_visible", true)
    _cfg.set_value("tree", "lazy_subdirs", true)
    _cfg.set_value("tree", "rebuild_mode", "incremental")
    _cfg.set_value("tree", "refresh_min_interval_ms", 500)
    _cfg.set_value("files", "tiles_per_frame", 32)
    _cfg.set_value("files", "tiles_frame_budget_ms", 6)
    _cfg.set_value("files", "virtualize_grid", true)
    _cfg.set_value("files", "repopulate_min_interval_ms", 250)
    _cfg.set_value("files", "defer_size_column", true)
    _cfg.set_value("search", "async", true)
    _cfg.set_value("search", "nodes_per_frame", 256)
    _cfg.set_value("search", "frame_budget_ms", 6)
    _cfg.set_value("search", "content_max_files", 500)
    _cfg.set_value("search", "content_requires_global_optin", true)
    _cfg.set_value("search", "debounce_ms", 300)
    _cfg.set_value("search", "max_results", 1000)
    _cfg.set_value("preview", "cache_mode", "engine_lazy")
    _cfg.set_value("preview", "only_visible", true)
    _cfg.set_value("preview", "max_preview_size_px", 128)
    _cfg.set_value("preview", "cache_ttl_sec", 180.0)
    _cfg.set_value("preview", "heavy_previews_per_frame", 4)
    _cfg.set_value("preview", "heavy_frame_budget_ms", 8)
    _cfg.set_value("preview", "cache_sweep_interval_sec", 10)
    _cfg.set_value("lifecycle", "persist_suspended", false)
    _cfg.set_value("git", "refresh_min_interval_ms", 1500)
    _cfg.set_value("git", "color_new", "5fd35f")
    _cfg.set_value("git", "color_modified", "f2c14e")
    _cfg.set_value("git", "color_unmodified", "9aa3b0")
    _cfg.set_value("git", "color_dir", "6fb7f0")
    _cfg.set_value("layout", "mode", "left_hier_right_files")
    _cfg.set_value("nav", "show_parent_folder", false)
    _cfg.set_value("spacing", "grid_tile_gap_px", 8)
    _cfg.set_value("spacing", "list_row_gap_px", 2)
    _cfg.set_value("spacing", "font_size_px", 13)
    save()

# §10: вычистить мёртвые ключи из ранее сохранённого конфига.
func _migrate_dead_keys():
    var dirty = false
    if _cfg.has_section_key("scan", "max_dirs_per_chunk"):
        _cfg.erase_section_key("scan", "max_dirs_per_chunk"); dirty = true
    if _cfg.has_section_key("scan", "use_editor_fs_cache"):
        _cfg.erase_section_key("scan", "use_editor_fs_cache"); dirty = true
    if dirty:
        save()

func _read(section, key, def):
    return _cfg.get_value(section, key, def)

# Цвета git-состояний живут в конфиге как hex-строки (без "#").
func git_color(key, def_hex):
    return str(_read("git", key, def_hex))

func set_value(section, key, value):
    _cfg.set_value(section, key, value)
    save()
    _reload()
    emit_signal("changed")

# Применить пачку изменений и эмитнуть changed РОВНО один раз.
# entries — Array из [section, key, value].
func set_batch(entries):
    for e in entries:
        _cfg.set_value(e[0], e[1], e[2])
    save()
    _reload()
    emit_signal("changed")

func save():
    _cfg.save(PATH)

# ---------- профили (§9) ----------
func profile_entries(p):
    var e = []
    match p:
        Profile.LOW_CPU_LOW_RAM:
            e.append(["preview", "cache_mode", "engine_lazy"])
            e.append(["preview", "only_visible", true])
            e.append(["files", "virtualize_grid", true])
            e.append(["files", "tiles_per_frame", 16])
            e.append(["files", "tiles_frame_budget_ms", 4])
            e.append(["scan", "scan_mode", "event_only"])
            e.append(["search", "async", true])
            e.append(["search", "nodes_per_frame", 128])
            e.append(["preview", "heavy_previews_per_frame", 2])
        Profile.BALANCED:
            e.append(["preview", "cache_mode", "engine_lazy"])
            e.append(["preview", "only_visible", true])
            e.append(["files", "virtualize_grid", true])
            e.append(["files", "tiles_per_frame", 32])
            e.append(["files", "tiles_frame_budget_ms", 6])
            e.append(["scan", "scan_mode", "event_only"])
            e.append(["search", "async", true])
            e.append(["search", "nodes_per_frame", 256])
            e.append(["preview", "heavy_previews_per_frame", 4])
        Profile.RESPONSIVE:
            e.append(["preview", "cache_mode", "full_memory"])
            e.append(["preview", "only_visible", false])
            e.append(["files", "virtualize_grid", false])
            e.append(["files", "tiles_per_frame", 128])
            e.append(["files", "tiles_frame_budget_ms", 12])
            e.append(["scan", "scan_mode", "event_only"])
            e.append(["search", "async", true])
            e.append(["search", "nodes_per_frame", 1024])
            e.append(["preview", "heavy_previews_per_frame", 8])
    return e

func apply_profile(p):
    set_batch(profile_entries(p))

# ---------- разбор enum-строк ----------
static func parse_scan_mode(s):
    match s:
        "event_plus_poll": return ScanMode.EVENT_PLUS_POLL
        "poll_only": return ScanMode.POLL_ONLY
        _: return ScanMode.EVENT_ONLY

static func parse_rebuild_mode(s):
    return TreeRebuildMode.FULL if s == "full" else TreeRebuildMode.INCREMENTAL

static func parse_cache_mode(s):
    return PreviewCacheMode.FULL_MEMORY if s == "full_memory" else PreviewCacheMode.ENGINE_LAZY
