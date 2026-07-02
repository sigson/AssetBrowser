tool
extends VBoxContainer
class_name ABFileView

const PARENT_MARKER = "::parent::"
const _BIG = 2147483647

signal dir_entered(dir)
signal edit_requested(path)
signal reveal_requested(dir)
signal selection_changed(sel)
signal status_update(count, sel_path)
signal create_requested(kind)
signal note_update(note)

var _s = null
var _state = null

var _list = null
var _scroll = null
var _grid = null
var _canvas = null

var _nodes = []
var _tiles = {}
var _rows = {}
var _selection = []
var _anchor = null

var _pending_path = null
var _pending_ctrl = false
var _drag_started = false

var _heavy = []
var _last_dir = null
var _pending_scroll = 0
var _scroll_tries = 0
var _resize_col = -1

var _virtual = false
var _cols = 1
var _cell_px = 64
var _gap_px = 8
var _col_stride = 1
var _row_stride = 1
var _win_first = -1
var _win_last = -1
var _build_queue = []
var _preview_requested = {}
var _index = {}

var _last_build_ms = -100000.0
var _repop_timer = null

var _search_cursor = null
var _search_engine = null
var _search_running = false
var _search_cap = 1
var _search_count = 0
var _frozen = false

var _size_needed = false

var _ctx = null
var _create_menu = null
var _view_sig = 0
var _del_dlg = null
var _ren_dlg = null
var _ren_input = null
var _ren_target = null

func set_frozen(on):
    _frozen = on
    if on:
        _search_running = false
        _search_cursor = null

func build(shared, state):
    _s = shared
    _state = state
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL

    _build_context_menu()
    _build_create_menu()
    _build_dialogs()

    _repop_timer = Timer.new()
    _repop_timer.one_shot = true
    _repop_timer.connect("timeout", self, "populate")
    add_child(_repop_timer)

    populate()

func _now_ms():
    return OS.get_ticks_msec()

func _visible_count():
    if _nodes.size() > 0 and _nodes[0].path == PARENT_MARKER:
        return _nodes.size() - 1
    return _nodes.size()

func _sel_last():
    return _selection[_selection.size() - 1] if _selection.size() > 0 else _state.current_dir

# ---------- create menu ----------
func _build_create_menu():
    _create_menu = PopupMenu.new()
    _create_menu.add_item("New Folder", ABToolbar.CreateKind.FOLDER)
    _create_menu.add_item("New Text File", ABToolbar.CreateKind.TEXT_FILE)
    _create_menu.add_item("New Material", ABToolbar.CreateKind.MATERIAL)
    _create_menu.add_item("New Scene", ABToolbar.CreateKind.SCENE)
    _create_menu.add_item("New Resource", ABToolbar.CreateKind.RESOURCE)
    _create_menu.connect("id_pressed", self, "on_create_picked")
    add_child(_create_menu)

func on_create_picked(kind):
    emit_signal("create_requested", kind)

# ---------- population ----------
func populate():
    if _frozen:
        _render_frozen()
        return

    var prev_scroll = _scroll.scroll_vertical if _scroll != null else 0
    var same_dir = _last_dir == _state.current_dir

    var min_ms = _s.settings.repopulate_min_ms
    if same_dir and min_ms > 0:
        var since = _now_ms() - _last_build_ms
        if since < min_ms:
            if _repop_timer.is_stopped():
                _repop_timer.start(max(0.01, (min_ms - since) / 1000.0))
            return

    _last_dir = _state.current_dir

    _collect_nodes()

    var sig = _compute_sig()
    var widget_ready = (_list != null) if _state.view == ABBrowserTabState.ViewMode.LIST else (_scroll != null)
    if not _search_running and sig == _view_sig and widget_ready:
        emit_signal("status_update", _visible_count(), _sel_last())
        return
    _view_sig = sig
    _last_build_ms = _now_ms()

    _clear_views()
    if _state.view == ABBrowserTabState.ViewMode.LIST:
        _build_list()
    else:
        _build_grid()

    _pending_scroll = prev_scroll if same_dir else 0
    _scroll_tries = 4 if (same_dir and _scroll != null and _pending_scroll > 0) else 0

    emit_signal("status_update", _visible_count(), _sel_last())
    _emit_search_note()

func _render_frozen():
    var prev_scroll = _scroll.scroll_vertical if _scroll != null else 0
    var sig = _compute_sig()
    var widget_ready = (_list != null) if _state.view == ABBrowserTabState.ViewMode.LIST else (_scroll != null)
    if sig == _view_sig and widget_ready:
        emit_signal("status_update", _visible_count(), _sel_last())
        return
    _view_sig = sig
    _last_build_ms = _now_ms()

    _clear_views()
    if _state.view == ABBrowserTabState.ViewMode.LIST:
        _build_list()
    else:
        _build_grid()

    _pending_scroll = prev_scroll
    _scroll_tries = 4 if (_scroll != null and _pending_scroll > 0) else 0

    emit_signal("status_update", _visible_count(), _sel_last())

func _emit_search_note():
    if _search_engine == null or _state.search.is_empty():
        emit_signal("note_update", "")
        return
    if _search_engine.global_content_blocked:
        emit_signal("note_update", "Поиск по содержимому в глобальной области требует подтверждения")
    elif _search_engine.content_truncated:
        emit_signal("note_update", "Поиск по содержимому ограничен %d файлами" % _s.settings.content_max_files)
    else:
        emit_signal("note_update", "")

func _collect_nodes():
    _nodes.clear()
    _search_running = false
    _search_cursor = null
    _search_engine = null

    if not _state.search.is_empty():
        _search_engine = ABSearchEngine.new(_s.db, _s.tags, _s.settings, _s.type_graph)
        _search_cap = max(1, _s.settings.search_max_results)
        var cursor = _search_engine.query(_state.search, _state.current_dir)

        if _s.settings.search_async and _state.view != ABBrowserTabState.ViewMode.LIST:
            _search_cursor = cursor
            _search_count = 0
            _search_running = true
            return

        var got = []
        var node = cursor.next()
        while node != null and got.size() < _search_cap:
            got.append(node)
            node = cursor.next()
        _sort_into(got)
        return

    _sort_into(_s.db.get_children(_state.current_dir))

    if _s.settings.show_parent_folder and _state.search.is_empty() \
        and ABAssetDatabase.normalize(_state.current_dir) != "res://":
        var up = ABAssetNode.new()
        up.path = PARENT_MARKER
        up.name = ".."
        up.is_dir = true
        up.res_type = "Folder"
        _nodes.insert(0, up)

func _sort_into(list):
    _size_needed = _state.sort_column == "Size" \
        and (not _s.settings.defer_size_column or _state.view == ABBrowserTabState.ViewMode.LIST)
    list.sort_custom(self, "_cmp_nodes")
    for n in list:
        _nodes.append(n)

func _cmp_nodes(a, b):
    if a.is_dir != b.is_dir:
        return a.is_dir
    if a.is_dir and b.is_dir:
        return a.name.nocasecmp_to(b.name) < 0
    var c = 0
    match _state.sort_column:
        "Type":
            c = _type_key(a).nocasecmp_to(_type_key(b))
            if c == 0:
                c = a.name.nocasecmp_to(b.name)
        "Size":
            c = _sign(_size_of(a) - _size_of(b)) if _size_needed else 0
            if c == 0:
                c = a.name.nocasecmp_to(b.name)
        _:
            c = a.name.nocasecmp_to(b.name)
    if not _state.sort_asc:
        c = -c
    return c < 0

func _sign(x):
    if x < 0:
        return -1
    if x > 0:
        return 1
    return 0

func _compute_sig():
    var cell = int(clamp(_state.preview_size, 32, _s.settings.max_preview_size))
    var parts = str(_state.view) + "|" + str(cell) + "|" + str(_state.sort_column) \
        + "|" + str(_state.sort_asc) + "|" + str(_nodes.size())
    for n in _nodes:
        parts += "|" + n.path
    return hash(parts)

func _clear_views():
    _tiles.clear()
    _rows.clear()
    _heavy.clear()
    _build_queue.clear()
    _preview_requested.clear()
    _index.clear()
    _win_first = -1
    _win_last = -1
    if _list != null:
        _list.queue_free()
        _list = null
    if _scroll != null:
        _scroll.queue_free()
        _scroll = null
        _grid = null
        _canvas = null

# ---------- LIST ----------
func _build_list():
    _list = Tree.new()
    _list.hide_root = true
    _list.select_mode = Tree.SELECT_MULTI
    _list.mouse_filter = Control.MOUSE_FILTER_STOP
    _list.allow_rmb_select = true
    _list.columns = 3
    _list.set_column_titles_visible(true)
    _list.set_column_title(0, "Name")
    _list.set_column_title(1, "Type")
    _list.set_column_title(2, "Size")
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.connect("item_activated", self, "on_list_activate")
    _list.connect("multi_selected", self, "on_list_multi")
    _list.connect("item_rmb_selected", self, "on_list_rmb")
    _list.connect("empty_rmb", self, "on_list_empty_rmb")
    _list.connect("empty_tree_rmb_selected", self, "on_list_empty_rmb")
    _list.connect("nothing_selected", self, "on_list_nothing_selected")
    _list.connect("column_title_pressed", self, "on_sort_column")
    _list.connect("gui_input", self, "on_list_gui")
    _list.set_drag_forwarding(self)
    _list.set_column_expand(0, false)
    _list.set_column_min_width(0, max(50, _state.col_name))
    _list.set_column_expand(1, false)
    _list.set_column_min_width(1, max(30, _state.col_type))
    _list.set_column_expand(2, true)
    add_child(_list)

    var root = _list.create_item()
    for n in _nodes:
        var it = _list.create_item(root)
        it.set_text(0, n.name)
        it.set_text(1, "Folder" if n.is_dir else n.res_type)
        it.set_text(2, "" if n.is_dir else _size_str(n))
        it.set_text_align(1, TreeItem.ALIGN_CENTER)
        it.set_text_align(2, TreeItem.ALIGN_CENTER)
        it.set_icon(0, _s.thumbs.get_type_icon(n))
        it.set_icon_max_width(0, 16)
        it.set_metadata(0, n.path)
        if _selection.has(n.path):
            it.select(0)
        _rows[n.path] = it
        if not n.is_dir:
            _s.thumbs.get_thumb(n, false, self, "on_preview_ready", n.path)

# ---------- GRID ----------
func _build_grid():
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _scroll.mouse_filter = Control.MOUSE_FILTER_PASS
    add_child(_scroll)

    _cell_px = int(clamp(_state.preview_size, 32, _s.settings.max_preview_size))
    _gap_px = _s.settings.grid_tile_gap
    _cols = _compute_columns(_cell_px, _gap_px)
    _col_stride = (_cell_px + 8) + _gap_px
    _row_stride = (_cell_px + 26) + _gap_px

    _build_index()

    _virtual = _s.settings.virtualize_grid and not _search_running

    if _virtual:
        _scroll.scroll_horizontal_enabled = false
        _canvas = Control.new()
        _canvas.mouse_filter = Control.MOUSE_FILTER_PASS
        _canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _scroll.add_child(_canvas)
        _update_canvas_size()
        _win_first = -1
        _win_last = -1
        _update_virtual_window()
    else:
        _scroll.scroll_horizontal_enabled = true
        _grid = GridContainer.new()
        _grid.mouse_filter = Control.MOUSE_FILTER_PASS
        _grid.add_constant_override("hseparation", _gap_px)
        _grid.add_constant_override("vseparation", _gap_px)
        _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        _grid.columns = _cols
        _scroll.add_child(_grid)

        _build_queue.clear()
        for i in range(_nodes.size()):
            _build_queue.append(i)
        _build_slice_chunk()

    _apply_selection_visual()

func _build_index():
    _index.clear()
    for i in range(_nodes.size()):
        _index[_nodes[i].path] = i

func _update_canvas_size():
    if _canvas == null:
        return
    var rows = (_nodes.size() + _cols - 1) / max(1, _cols)
    _canvas.rect_min_size = Vector2(0, rows * _row_stride)

func _compute_columns(cell, gap):
    var w = rect_size.x
    if w <= 1:
        w = rect_min_size.x if rect_min_size.x > 1 else 200
    w -= 16.0
    return max(1, int(w / (cell + gap + 8)))

func _visible_row_range():
    var first = 0
    var last = -1
    if _scroll == null or _row_stride <= 0:
        return [first, last]
    var y = _scroll.scroll_vertical
    var h = _scroll.rect_size.y
    if h <= 0:
        h = 200.0
    first = max(0, int(y / _row_stride))
    last = int((y + h) / _row_stride)
    return [first, last]

func _make_tile(i):
    var n = _nodes[i]
    var tile = ABFileTile.new()
    tile.build(self, n, _cell_px, _s)
    if _virtual and _canvas != null:
        var row = i / max(1, _cols)
        var col = i % max(1, _cols)
        tile.rect_position = Vector2(col * _col_stride, row * _row_stride)
        tile.rect_size = Vector2(_cell_px + 8, _cell_px + 26)
        _canvas.add_child(tile)
    else:
        _grid.add_child(tile)
    _tiles[n.path] = tile
    tile.set_selected(_selection.has(n.path))

    if not n.is_dir:
        var cached = _s.thumbs.peek_cached(n.path, true)
        if cached != null:
            tile.set_thumb(cached)
            _preview_requested[n.path] = true
    return tile

func _request_preview(n):
    if n.is_dir or _preview_requested.has(n.path):
        return
    _preview_requested[n.path] = true
    if _s.thumbs.is_direct_texture(n.res_type):
        _heavy.append(n.path)
    elif _s.thumbs.previewable(n.res_type):
        _s.thumbs.queue_generated(n.path, self, "on_preview_ready", n.path)

func _request_visible_previews():
    if _tiles.size() == 0:
        return
    var only_vis = _s.settings.preview_only_visible
    var vf = 0
    var vl = _BIG
    if only_vis:
        var rng = _visible_row_range()
        vf = rng[0]
        vl = rng[1]

    for key in _tiles.keys():
        if _preview_requested.has(key):
            continue
        if not _index.has(key):
            continue
        var i = _index[key]
        if only_vis:
            var row = i / max(1, _cols)
            if row < vf or row > vl:
                continue
        _request_preview(_nodes[i])

    if only_vis and not _virtual and _canvas == null:
        for key in _tiles.keys():
            if not _preview_requested.has(key):
                continue
            if not _index.has(key):
                continue
            var i = _index[key]
            var row = i / max(1, _cols)
            if row < vf or row > vl:
                var t = _tiles[key]
                if is_instance_valid(t):
                    t.release_thumb()
                _preview_requested.erase(key)

func _update_virtual_window():
    if _canvas == null or _row_stride <= 0:
        return
    var buffer = 2
    var rng = _visible_row_range()
    var vf = rng[0]
    var vl = rng[1]
    var first = max(0, vf - buffer)
    var total_rows = (_nodes.size() + _cols - 1) / max(1, _cols)
    var last = min(total_rows - 1, vl + buffer)
    if first == _win_first and last == _win_last:
        return

    var drop = []
    for key in _tiles.keys():
        if not _index.has(key):
            drop.append(key)
            continue
        var i = _index[key]
        var row = i / max(1, _cols)
        if row < first or row > last:
            drop.append(key)
    for p in drop:
        if _tiles.has(p):
            var t = _tiles[p]
            if is_instance_valid(t):
                t.queue_free()
        _tiles.erase(p)
        _preview_requested.erase(p)

    for row in range(first, last + 1):
        for col in range(_cols):
            var i = row * _cols + col
            if i >= _nodes.size():
                break
            if not _tiles.has(_nodes[i].path):
                _make_tile(i)
    _win_first = first
    _win_last = last

func _build_slice_chunk():
    if _build_queue.size() == 0 or _grid == null:
        return
    var max_n = max(1, _s.settings.tiles_per_frame)
    var budget = max(1, _s.settings.tiles_frame_budget_ms)
    var start = _now_ms()
    var done = 0
    while _build_queue.size() > 0 and done < max_n and _now_ms() - start < budget:
        _make_tile(_build_queue.pop_front())
        done += 1

func _pump_search():
    if _search_cursor == null or _grid == null:
        _search_running = false
        return
    var max_n = max(1, _s.settings.search_nodes_per_frame)
    var budget = max(1, _s.settings.search_frame_budget_ms)
    var start = _now_ms()
    var done = 0
    var finished = false
    while done < max_n and _now_ms() - start < budget:
        if _search_count >= _search_cap:
            finished = true
            break
        var n = _search_cursor.next()
        if n == null:
            finished = true
            break
        var i = _nodes.size()
        _nodes.append(n)
        _index[n.path] = i
        _search_count += 1
        _make_tile(i)
        done += 1
    emit_signal("status_update", _visible_count(), _sel_last())
    if finished:
        _finish_search()

func _finish_search():
    _search_running = false
    _search_cursor = null

    var captured = _nodes.duplicate()
    _nodes.clear()
    _sort_into(captured)

    _clear_views()
    _build_index()
    _build_grid()

    _view_sig = _compute_sig()
    emit_signal("status_update", _visible_count(), _sel_last())
    _emit_search_note()

func _process(_delta):
    if _scroll_tries > 0 and _scroll != null:
        _scroll.scroll_vertical = _pending_scroll
        _scroll_tries -= 1

    if _search_running:
        _pump_search()
    elif _build_queue.size() > 0:
        _build_slice_chunk()

    if _virtual and _canvas != null and not _search_running:
        _update_virtual_window()

    if _grid != null or _canvas != null:
        _request_visible_previews()

    _pump_heavy()

func _pump_heavy():
    if _heavy.size() == 0 or not is_visible_in_tree():
        return
    var max_n = max(1, _s.settings.heavy_per_frame)
    var budget = max(1, _s.settings.heavy_frame_budget_ms)
    var only_vis = _s.settings.preview_only_visible
    var vf = 0
    var vl = _BIG
    if only_vis:
        var rng = _visible_row_range()
        vf = rng[0]
        vl = rng[1]

    var start = _now_ms()
    var done = 0
    while _heavy.size() > 0 and done < max_n and _now_ms() - start < budget:
        var path = _heavy.pop_front()
        if not _tiles.has(path):
            continue
        var tile = _tiles[path]
        if not is_instance_valid(tile):
            continue

        if only_vis and _index.has(path):
            var row = _index[path] / max(1, _cols)
            if row < vf or row > vl:
                _preview_requested.erase(path)
                continue

        var tex = _s.thumbs.load_heavy_cached(path)
        if tex != null:
            tile.set_thumb(tex)
            # engine_lazy: нативную ссылку держит TextureRect плитки; refcount падает при
            # queue_free/release_thumb детерминированно (в GDScript ручной Dispose не нужен).
        done += 1

func _notification(what):
    if what != NOTIFICATION_RESIZED or _scroll == null:
        return

    _cols = _compute_columns(_cell_px, _gap_px)
    if _virtual and _canvas != null:
        _update_canvas_size()
        for key in _tiles.keys():
            if not _index.has(key):
                continue
            var t = _tiles[key]
            if not is_instance_valid(t):
                continue
            var i = _index[key]
            var row = i / max(1, _cols)
            var col = i % max(1, _cols)
            t.rect_position = Vector2(col * _col_stride, row * _row_stride)
        _win_first = -1
        _win_last = -1
    elif _grid != null and _grid.columns != _cols:
        _grid.columns = _cols

# ---------- preview callback ----------
func on_preview_ready(path, preview, thumbnail, userdata):
    if not is_instance_valid(self):
        return
    var big = preview if preview != null else thumbnail
    var small = thumbnail if thumbnail != null else preview
    if big == null:
        return
    var p = userdata if typeof(userdata) == TYPE_STRING else path
    _s.thumbs.store_preview(p, big)
    if _tiles.has(p):
        var tile = _tiles[p]
        if is_instance_valid(tile):
            tile.set_thumb(big)
    if _rows.has(p):
        var row = _rows[p]
        if is_instance_valid(row):
            row.set_icon(0, small)

func touch_visible_thumbs():
    for n in _nodes:
        _s.thumbs.touch(n.path)

# ---------- selection ----------
func tile_pressed(path, ctrl, shift):
    _drag_started = false
    _pending_path = null

    if shift and _anchor != null:
        _select_range(_anchor, path)
        _emit_selection(path)
        return
    if ctrl:
        _pending_path = path
        _pending_ctrl = true
        return
    if _selection.has(path):
        _pending_path = path
        _pending_ctrl = false
    else:
        _select_single(path)
        _emit_selection(path)

func tile_released(path):
    if _drag_started or _pending_path == null or _pending_path != path:
        _pending_path = null
        return
    if _pending_ctrl:
        _toggle_one(path)
    else:
        _select_single(path)
    _emit_selection(path)
    _pending_path = null

func tile_right_pressed(path):
    _pending_path = null
    if not _selection.has(path):
        _select_single(path)
        _emit_selection(path)

func tile_drag_start(path):
    _drag_started = true
    _pending_path = null
    if not _selection.has(path):
        _select_single(path)
        _emit_selection(path)
    return _make_drag_data()

func _select_single(p):
    _selection.clear()
    _selection.append(p)
    _anchor = p
    _apply_selection_visual()

func _toggle_one(p):
    if _selection.has(p):
        _selection.erase(p)
    else:
        _selection.append(p)
    _anchor = p
    _apply_selection_visual()

func _select_range(a, b):
    var ia = _index_of_path(a)
    var ib = _index_of_path(b)
    if ia < 0 or ib < 0:
        _select_single(b)
        return
    _selection.clear()
    var lo = min(ia, ib)
    var hi = max(ia, ib)
    for i in range(lo, hi + 1):
        if _nodes[i].path != PARENT_MARKER:
            _selection.append(_nodes[i].path)
    _apply_selection_visual()

func _index_of_path(p):
    for i in range(_nodes.size()):
        if _nodes[i].path == p:
            return i
    return -1

func _emit_selection(last):
    emit_signal("selection_changed", PoolStringArray(_selection))
    emit_signal("status_update", _visible_count(), last if last != null else _state.current_dir)

func _apply_selection_visual():
    for key in _tiles.keys():
        _tiles[key].set_selected(_selection.has(key))

func _clear_selection():
    _selection.clear()
    _anchor = null
    _apply_selection_visual()
    if _list != null:
        for key in _rows.keys():
            for c in range(3):
                _rows[key].deselect(c)
    emit_signal("selection_changed", PoolStringArray())
    emit_signal("status_update", _visible_count(), _state.current_dir)

func is_selected(path):
    return _selection.has(path)

func get_selection():
    return PoolStringArray(_selection)

# ---------- activation ----------
func activate(path):
    if path == PARENT_MARKER:
        emit_signal("dir_entered", ABAssetDatabase.parent_dir(_state.current_dir))
        return
    var n = _node_by_path(path)
    if n == null:
        return
    if n.is_dir:
        emit_signal("dir_entered", n.path)
    else:
        emit_signal("edit_requested", n.path)

func _node_by_path(path):
    for x in _nodes:
        if x.path == path:
            return x
    return null

func on_list_activate():
    var it = _list.get_selected()
    if it != null:
        var p = it.get_metadata(0)
        if typeof(p) == TYPE_STRING:
            activate(p)

func on_list_multi(_item, _col, _selected):
    _sync_list_selection()

func _sync_list_selection():
    _selection.clear()
    for key in _rows.keys():
        if key == PARENT_MARKER:
            continue
        var row = _rows[key]
        var sel = false
        for c in range(3):
            if row.is_selected(c):
                sel = true
                break
        if sel:
            _selection.append(key)
    _anchor = _selection[_selection.size() - 1] if _selection.size() > 0 else null
    var last = _selection[_selection.size() - 1] if _selection.size() > 0 else _state.current_dir
    emit_signal("selection_changed", PoolStringArray(_selection))
    emit_signal("status_update", _visible_count(), last)

func on_list_rmb(_pos):
    _sync_list_selection()
    popup_context()

func on_list_empty_rmb(_pos):
    if not _state.search.is_empty():
        return
    _create_menu.set_global_position(get_global_mouse_position())
    _create_menu.popup()

func on_list_nothing_selected():
    _clear_selection()

func on_sort_column(col):
    var c = "Type" if col == 1 else ("Size" if col == 2 else "Name")
    if _state.sort_column == c:
        _state.sort_asc = not _state.sort_asc
    else:
        _state.sort_column = c
        _state.sort_asc = true
    populate()

func on_list_gui(ev):
    if _list == null:
        return

    if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
        if ev.pressed:
            var x = ev.position.x
            var b1 = _list.get_column_width(0)
            var b2 = b1 + _list.get_column_width(1)
            if abs(x - b1) <= 6.0:
                _resize_col = 0
                _list.accept_event()
            elif abs(x - b2) <= 6.0:
                _resize_col = 1
                _list.accept_event()
        elif _resize_col != -1:
            _resize_col = -1
            _list.accept_event()
    elif ev is InputEventMouseMotion:
        var x = ev.position.x
        var w = _list.rect_size.x
        if _resize_col != -1:
            if _resize_col == 0:
                _state.col_name = int(clamp(x, 60.0, max(80.0, w - _state.col_type - 80.0)))
            else:
                _state.col_type = int(clamp(x - _state.col_name, 40.0, max(60.0, w - _state.col_name - 60.0)))
            _list.set_column_min_width(0, max(50, _state.col_name))
            _list.set_column_min_width(1, max(30, _state.col_type))
            _list.accept_event()
        else:
            var b1 = _list.get_column_width(0)
            var b2 = b1 + _list.get_column_width(1)
            var on_border = abs(x - b1) <= 6.0 or abs(x - b2) <= 6.0
            _list.mouse_default_cursor_shape = Control.CURSOR_HSIZE if on_border else Control.CURSOR_ARROW

# ---------- context menu ----------
func _build_context_menu():
    _ctx = PopupMenu.new()
    _ctx.add_item("Edit", 0)
    _ctx.add_item("Open in External Editor", 11)
    _ctx.add_item("Open Containing Folder", 10)
    _ctx.add_item("Rename", 1)
    _ctx.add_item("Duplicate", 2)
    _ctx.add_item("Delete", 3)
    _ctx.add_separator()
    _ctx.add_item("Copy", 4)
    _ctx.add_item("Cut", 5)
    _ctx.add_item("Paste", 6)
    _ctx.add_separator()
    _ctx.add_item("Copy Path", 7)
    _ctx.add_item("Show in Explorer", 8)
    _ctx.add_item("Add to Favorites", 9)
    _ctx.connect("id_pressed", self, "on_context")
    add_child(_ctx)

func popup_context():
    _ctx.set_global_position(get_global_mouse_position())
    _ctx.popup()

func on_context(id):
    var target = _selection[_selection.size() - 1] if _selection.size() > 0 else null
    match id:
        0:
            if target != null:
                activate(target)
        1:
            if target != null:
                begin_rename(target)
        2:
            for p in _selection:
                ABFileOps.duplicate_path(p)
            _rescan()
        3:
            if _selection.size() > 0:
                _confirm_delete()
        4:
            _s.clipboard.set_data(_selection.duplicate(), ABClipboardModel.ClipboardMode.COPY)
        5:
            _s.clipboard.set_data(_selection.duplicate(), ABClipboardModel.ClipboardMode.CUT)
        6:
            paste()
        7:
            if target != null:
                OS.set_clipboard(target)
        8:
            if target != null:
                OS.shell_open(ProjectSettings.globalize_path(_dir_of(target)))
        9:
            if target != null and Directory.new().dir_exists(target):
                _s.favorites.add(target)
        10:
            if target != null:
                emit_signal("reveal_requested", ABAssetDatabase.parent_dir(target))
        11:
            if target != null:
                OS.shell_open(ProjectSettings.globalize_path(target))

func _dir_of(path):
    if Directory.new().dir_exists(path):
        return path
    return path.substr(0, path.find_last("/"))

func paste():
    if not _s.clipboard.has_content():
        return
    for p in _s.clipboard.paths:
        if _s.clipboard.mode == ABClipboardModel.ClipboardMode.CUT:
            ABFileOps.move_into(p, _state.current_dir)
        else:
            ABFileOps.copy(p, _state.current_dir)
    if _s.clipboard.mode == ABClipboardModel.ClipboardMode.CUT:
        _s.clipboard.clear()
    _rescan()

func _rescan():
    _s.db.request_scan()

# ---------- dialogs ----------
func _build_dialogs():
    _del_dlg = ConfirmationDialog.new()
    _del_dlg.window_title = "Delete"
    _del_dlg.connect("confirmed", self, "on_delete_confirmed")
    add_child(_del_dlg)

    _ren_dlg = WindowDialog.new()
    _ren_dlg.window_title = "Rename"
    _ren_dlg.rect_min_size = Vector2(280, 90)
    var vb = VBoxContainer.new()
    vb.set_anchors_and_margins_preset(Control.PRESET_WIDE, Control.PRESET_MODE_KEEP_SIZE, 8)
    _ren_input = LineEdit.new()
    _ren_input.connect("text_entered", self, "on_rename_entered")
    var ok = Button.new()
    ok.text = "OK"
    ok.connect("pressed", self, "on_rename_ok")
    vb.add_child(_ren_input)
    vb.add_child(ok)
    _ren_dlg.add_child(vb)
    add_child(_ren_dlg)

func _confirm_delete():
    _del_dlg.dialog_text = "Delete %d item(s)? This cannot be undone and does not fix references." % _selection.size()
    _del_dlg.popup_centered()

func on_delete_confirmed():
    for p in _selection.duplicate():
        ABFileOps.delete_path(p)
    _selection.clear()
    _rescan()

func begin_rename(path):
    _ren_target = path
    _ren_input.text = path.substr(path.find_last("/") + 1)
    _ren_dlg.popup_centered()
    _ren_input.grab_focus()
    _ren_input.select_all()

func on_rename_entered(_t):
    on_rename_ok()

func on_rename_ok():
    if _ren_target == null:
        return
    var new_name = _ren_input.text.strip_edges()
    if new_name.length() == 0:
        _ren_dlg.hide()
        return
    var dir = _ren_target.substr(0, _ren_target.find_last("/"))
    ABFileOps.rename(_ren_target, dir + "/" + new_name)
    _ren_target = null
    _ren_dlg.hide()
    _rescan()

# ---------- keyboard ----------
func _gui_input(ev):
    if ev is InputEventMouseButton and ev.pressed:
        if ev.button_index == BUTTON_RIGHT:
            if _state.search.is_empty():
                _create_menu.set_global_position(get_global_mouse_position())
                _create_menu.popup()
                accept_event()
            return
        if ev.button_index == BUTTON_LEFT:
            _clear_selection()
            accept_event()
            return

    if ev is InputEventKey and ev.pressed:
        if ev.scancode == KEY_F2 and _selection.size() == 1:
            begin_rename(_selection[0])
            accept_event()
        elif ev.scancode == KEY_DELETE and _selection.size() > 0:
            _confirm_delete()
            accept_event()
        elif ev.control and ev.scancode == KEY_C:
            _s.clipboard.set_data(_selection.duplicate(), ABClipboardModel.ClipboardMode.COPY)
            accept_event()
        elif ev.control and ev.scancode == KEY_X:
            _s.clipboard.set_data(_selection.duplicate(), ABClipboardModel.ClipboardMode.CUT)
            accept_event()
        elif ev.control and ev.scancode == KEY_V:
            paste()
            accept_event()
        elif ev.control and ev.scancode == KEY_D:
            for p in _selection:
                ABFileOps.duplicate_path(p)
            _rescan()
            accept_event()

# ---------- drag & drop ----------
func get_drag_data_fw(_pos, _from):
    return _make_drag_data()

func can_drop_data_fw(_pos, data, _from):
    return is_files_data(data)

func drop_data_fw(_pos, data, _from):
    do_drop(data, _state.current_dir)

func can_drop_data(_pos, data):
    return is_files_data(data)

func drop_data(_pos, data):
    do_drop(data, _state.current_dir)

func _make_drag_data():
    var paths = PoolStringArray(_selection) if _selection.size() > 0 else PoolStringArray()
    return {"type": "files", "files": paths, "from": self}

static func is_files_data(data):
    return typeof(data) == TYPE_DICTIONARY and data.has("type") and data["type"] == "files"

func do_drop(data, dst_dir):
    if typeof(data) != TYPE_DICTIONARY:
        return
    var copy = Input.is_key_pressed(KEY_CONTROL)
    for f in data["files"]:
        if copy:
            ABFileOps.copy(f, dst_dir)
        else:
            ABFileOps.move_into(f, dst_dir)
    _rescan()

func _size_str(n):
    var length = _size_of(n)
    if length < 0:
        return ""
    if length < 1024:
        return str(length) + " B"
    if length < 1024 * 1024:
        return str(length / 1024) + " KB"
    return str(length / (1024 * 1024)) + " MB"

func _size_of(n):
    if n.is_dir:
        return -1
    if n.size >= 0:
        return n.size
    var f = File.new()
    if f.open(n.path, File.READ) != OK:
        n.size = 0
        return 0
    n.size = int(f.get_len())
    f.close()
    return n.size

func _type_key(n):
    return n.ext() if n.res_type == "" else n.res_type
