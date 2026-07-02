tool
extends EditorResourcePreviewGenerator
class_name ABTileSetPreviewGenerator

func handles(type):
    return type == "TileSet"

func generate_small_preview_automatically():
    return true

func can_generate_small_preview():
    return true

func generate(from, size):
    var ts = from as TileSet
    if ts == null:
        return null

    # 1) собрать различные исходные текстуры (дедуп по resource_path)
    var seen = {}
    var cells = []
    var ids = ts.get_tiles_ids()
    for id_obj in ids:
        var id = int(id_obj)
        var tex = ts.tile_get_texture(id)
        if tex == null:
            continue
        var key = tex.resource_path
        if key == null or key == "":
            key = str(tex.get_instance_id())
        if seen.has(key):
            continue
        seen[key] = true

        var img = tex.get_data()
        if img == null:
            continue

        # SINGLE_TILE: пытаемся вырезать регион; для atlas/autotile регион = весь атлас -> вся текстура
        var reg = ts.tile_get_region(id)
        if reg.size.x > 0 and reg.size.y > 0 \
                and reg.size.x <= img.get_width() and reg.size.y <= img.get_height() \
                and (reg.size.x < img.get_width() or reg.size.y < img.get_height()):
            var sub = Image.new()
            sub.create(int(reg.size.x), int(reg.size.y), false, img.get_format())
            sub.blit_rect(img, reg, Vector2.ZERO)
            cells.append(sub)
        else:
            cells.append(img)

        if cells.size() >= 9:
            break

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

    var canvas = Image.new()
    canvas.create(side, side, false, Image.FORMAT_RGBA8)
    canvas.fill(Color(0, 0, 0, 0))   # прозрачный фон

    for i in range(n):
        var row = i / dim
        var col = i % dim
        var c = cells[i]
        if c.get_format() != Image.FORMAT_RGBA8:
            c.convert(Image.FORMAT_RGBA8)
        c.resize(cell, cell, Image.INTERPOLATE_BILINEAR)
        canvas.blit_rect(c, Rect2(0, 0, cell, cell), Vector2(col * cell, row * cell))

    var out_tex = ImageTexture.new()
    out_tex.create_from_image(canvas)
    return out_tex
