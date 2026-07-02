tool
extends Reference
class_name ABThumbnailService

# ФТ-5: двухрежимное кеширование превью (engine_lazy / full_memory).
# Примечание к порту: в GDScript Texture/Resource — refcounted (Reference), память
# освобождается детерминированно при обнулении ссылок, поэтому C#-микроменеджмент
# GC/Dispose здесь не нужен (обёрток managed-слоя нет). Функционально: при выгрузке
# плиток и очистке кеша нативные текстуры освобождаются автоматически.

var _editor = null
var _prev = null
var _base = null
var _tile_gen = null
var _settings = null

var _providers = []

# Кеш превью в памяти с TTL. Используется ТОЛЬКО в режиме full_memory.
# path -> {tex, touched, full_res}
var _cache = {}

const DIRECT_TEX_TYPES = {
    "Texture": true, "StreamTexture": true, "ImageTexture": true,
    "AtlasTexture": true, "LargeTexture": true, "CubeMap": true
}

func full_memory():
    return _settings != null and _settings.cache_mode == ABSettings.PreviewCacheMode.FULL_MEMORY

# engine_lazy: плагин не удерживает превью в собственном кеше.
func engine_lazy():
    return not full_memory()

func init(editor, settings):
    _editor = editor
    _settings = settings
    _prev = editor.get_resource_previewer()
    _base = editor.get_base_control()

    if _tile_gen != null and _prev != null:
        _prev.remove_preview_generator(_tile_gen)

    _tile_gen = ABTileSetPreviewGenerator.new()
    _prev.add_preview_generator(_tile_gen)

func shutdown():
    if _prev != null and _tile_gen != null:
        _prev.remove_preview_generator(_tile_gen)
    _tile_gen = null
    _cache.clear()

func register(p):
    if not _providers.has(p):
        _providers.append(p)

func unregister(id):
    var kept = []
    for p in _providers:
        if p.provider_id() != id:
            kept.append(p)
    _providers = kept

# ---------- запрос превью для отрисовки ----------
func get_thumb(n, allow_full_res, receiver, func_name, userdata):
    var key = n.path
    var now = _now_sec()
    var need_full = allow_full_res and is_direct_texture(n.res_type)

    if full_memory() and _cache.has(key):
        var e = _cache[key]
        if not need_full or e.full_res:
            e.touched = now
            return e.tex

    if n.is_dir:
        return _maybe_put(key, get_type_icon(n), now, true)

    if need_full:
        var full = load_full_texture(n.path)
        if full != null:
            return _maybe_put(key, full, now, true)

    if previewable(n.res_type):
        _prev.queue_resource_preview(n.path, receiver, func_name, userdata)
        return get_type_icon(n)

    return _maybe_put(key, get_type_icon(n), now, true)

# Вернуть кешированное превью, если есть (только full_memory). Иначе null.
func peek_cached(path, want_full):
    if not full_memory():
        return null
    if _cache.has(path):
        var e = _cache[path]
        if not want_full or e.full_res:
            e.touched = _now_sec()
            return e.tex
    return null

func load_heavy(path):
    if not full_memory():
        return load_full_texture(path)
    var now = _now_sec()
    if _cache.has(path) and _cache[path].full_res:
        _cache[path].touched = now
        return _cache[path].tex
    return _maybe_put(path, load_full_texture(path), now, true)

# Совместимость со старым именем.
func load_heavy_cached(path):
    return load_heavy(path)

func queue_generated(path, receiver, func_name, userdata):
    _prev.queue_resource_preview(path, receiver, func_name, userdata)

func editor_icon(name):
    return _icon_or(name)

func store_preview(path, tex):
    if not full_memory():
        return
    if tex != null:
        _cache[path] = {"tex": tex, "touched": _now_sec(), "full_res": false}

func touch(path):
    if not full_memory():
        return
    if _cache.has(path):
        _cache[path].touched = _now_sec()

func sweep_cache():
    if not full_memory():
        return
    var now = _now_sec()
    var ttl = _ttl()
    var dead = []
    for k in _cache:
        if now - _cache[k].touched > ttl:
            dead.append(k)
    for k in dead:
        _cache.erase(k)

func clear_cache():
    _cache.clear()

func _maybe_put(key, tex, now, full_res):
    if full_memory() and tex != null:
        _cache[key] = {"tex": tex, "touched": now, "full_res": full_res}
    return tex

func _ttl():
    return max(5.0, _settings.cache_ttl_sec if _settings != null else 180.0)

static func _now_sec():
    return OS.get_ticks_msec() / 1000.0

func is_direct_texture(res_type):
    return res_type != null and res_type != "" and DIRECT_TEX_TYPES.has(res_type)

# Полноразмерная текстура для превью грузится в обход глобального ResourceCache (no_cache=true).
func load_full_texture(path):
    return ResourceLoader.load(path, "", true) as Texture

func get_type_icon(n):
    if n.is_dir:
        return _icon_or("Folder")
    var t = "File" if (n.res_type == null or n.res_type == "") else n.res_type
    if _base != null and _base.has_icon(t, "EditorIcons"):
        return _base.get_icon(t, "EditorIcons")
    return _icon_or("File")

func _icon_or(name):
    if _base != null and _base.has_icon(name, "EditorIcons"):
        return _base.get_icon(name, "EditorIcons")
    return null

func previewable(res_type):
    match res_type:
        "Texture", "StreamTexture", "ImageTexture", "AtlasTexture", "TileSet", \
        "Mesh", "ArrayMesh", "PackedScene", "SpatialMaterial", "ShaderMaterial":
            return true
        _:
            return false

func invalidate(path):
    _cache.erase(path)
    _prev.check_for_invalidation(path)
