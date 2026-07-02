tool
extends Reference
class_name ABBrowserTabState

enum ViewMode { LIST, GRID }

var current_dir = "res://"
var back_stack = []
var fwd_stack = []
var selection = []
var view = ViewMode.GRID
var preview_size = 64          # клампится max_preview_size
var splitter_ratio = 0.3
var sort_column = "Name"
var sort_asc = true
var col_name = 220
var col_type = 90
var search = null
var scroll_offset = Vector2.ZERO
var title = "Assets"

func _init():
    search = ABSearchState.new()

func navigate_to(dir, record = true):
    dir = ABAssetDatabase.normalize(dir)
    if dir == current_dir:
        return
    if record:
        back_stack.append(current_dir)
        fwd_stack.clear()
    current_dir = dir

func can_back():
    return back_stack.size() > 0

func can_fwd():
    return fwd_stack.size() > 0

func back():
    if not can_back():
        return
    fwd_stack.append(current_dir)
    current_dir = back_stack[back_stack.size() - 1]
    back_stack.remove(back_stack.size() - 1)

func forward():
    if not can_fwd():
        return
    back_stack.append(current_dir)
    current_dir = fwd_stack[fwd_stack.size() - 1]
    fwd_stack.remove(fwd_stack.size() - 1)

func clone():
    var s = get_script().new()
    s.current_dir = current_dir
    s.back_stack = back_stack.duplicate()
    s.fwd_stack = fwd_stack.duplicate()
    s.selection = selection.duplicate()
    s.view = view
    s.preview_size = preview_size
    s.splitter_ratio = splitter_ratio
    s.sort_column = sort_column
    s.sort_asc = sort_asc
    s.col_name = col_name
    s.col_type = col_type
    s.search = search.clone()
    s.scroll_offset = scroll_offset
    s.title = title
    return s
