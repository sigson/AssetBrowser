@tool
extends EditorResourcePreviewGenerator
class_name ABTileSetPreviewGenerator

# Порт на Godot 4: TileSet больше не хранит плитки как плоский список id, а разбит
# на источники (TileSetAtlasSource / TileSetScenesCollectionSource). Здесь берём
# до 9 тайл-регионов из атласных источников и собираем из них квадратный коллаж.

func _handles(type):
    return type == "TileSet"

func _generate_small_preview_automatically():
    return true

func _can_generate_small_preview():
    return true

func _generate(from, size, metadata):
    var ts = from as TileSet
    if ts == null:
        return null

    # 1) собрать до 9 миниатюр отдельных тайлов из атласных источников
    var cells = []
    for si in range(ts.get_source_count()):
        if cells.size() >= 9:
            break
        var sid = ts.get_source_id(si)
        var atlas = ts.get_source(sid) as TileSetAtlasSource
        if atlas == null:
            continue
        var tex = atlas.texture
        if tex == null:
            continue
        var img = tex.get_image()
        if img == null:
            continue
        var bounds = Rect2i(0, 0, img.get_width(), img.get_height())
        for ti in range(atlas.get_tiles_count()):
            if cells.size() >= 9:
                break
            var coords = atlas.get_tile_id(ti)
            var reg = Rect2i(atlas.get_tile_texture_region(coords, 0))
            reg = reg.intersection(bounds)
            if reg.size.x <= 0 or reg.size.y <= 0:
                continue
            cells.append(img.get_region(reg))

    var n = cells.size()
    if n == 0:
        return null

    # 2) наименьший квадрат: dim=ceil(sqrt(n)), кламп 1..3
    var dim = int(ceil(sqrt(n)))
    if dim < 1:
        dim = 1
    if dim > 3:
        dim = 3

    var side = int(max(size.x, 1))
    var cell = int(max(1, side / dim))

    var canvas = Image.create(side, side, false, Image.FORMAT_RGBA8)
    canvas.fill(Color(0, 0, 0, 0))   # прозрачный фон

    for i in range(n):
        var row = i / dim
        var col = i % dim
        var c = cells[i]
        if c.get_format() != Image.FORMAT_RGBA8:
            c.convert(Image.FORMAT_RGBA8)
        c.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
        canvas.blit_rect(c, Rect2i(0, 0, cell, cell), Vector2i(col * cell, row * cell))

    return ImageTexture.create_from_image(canvas)
