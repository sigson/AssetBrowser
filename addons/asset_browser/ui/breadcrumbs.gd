@tool
extends ABFlowContainer
class_name ABBreadcrumbs

# Хлебные крошки с переносом строк (flow).

signal segment_picked(dir)

var _s = null
var _edit_mode = false
var _current_dir = "res://"
var _edit = null

func set_shared(s):
    _s = s

func build(current_dir):
    _current_dir = ABAssetDatabase.normalize(current_dir)
    for c in get_children():
        c.queue_free()
    _edit = null

    var toggle = Button.new()
    toggle.flat = true
    toggle.focus_mode = Control.FOCUS_NONE
    toggle.tooltip_text = "Switch to breadcrumbs" if _edit_mode else "Edit path as text"
    _glyph(toggle, "Folder" if _edit_mode else "Edit", "/" if _edit_mode else "...")
    toggle.connect("pressed", Callable(self, "on_toggle"))
    add_child(toggle)

    if _edit_mode:
        _build_text_field()
    else:
        _build_segments()

    queue_sort()

# ---------- segments ----------
func _build_segments():
    _add_seg("res://", "res://")
    if _current_dir != "res://":
        var rel = _current_dir.substr(6).strip_edges()
        var acc = "res://"
        for seg in rel.split("/"):
            if seg.length() == 0:
                continue
            _add_label(">")
            acc = "res://" + seg if acc == "res://" else acc + "/" + seg
            _add_seg(seg, acc)

func _add_seg(text, dir):
    var b = Button.new()
    b.text = text
    b.flat = true
    b.focus_mode = Control.FOCUS_NONE
    b.connect("pressed", Callable(self, "on_seg").bindv([dir]))
    add_child(b)

func _add_label(t):
    var l = Label.new()
    l.text = t
    add_child(l)

# ---------- text field ----------
func _build_text_field():
    _edit = LineEdit.new()
    _edit.text = _current_dir
    _edit.tooltip_text = "Type or paste a res:// path and press Enter"
    _edit.custom_minimum_size = Vector2(40, 0)
    _edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _edit.connect("text_submitted", Callable(self, "on_path_entered"))
    _edit.connect("text_changed", Callable(self, "on_path_changed"))
    add_child(_edit)

func _glyph(b, icon, fallback):
    var tex = _s.thumbs.editor_icon(icon) if _s != null else null
    if tex != null:
        b.icon = tex
        b.text = ""
    else:
        b.text = fallback

# ---------- handlers ----------
func on_toggle():
    _edit_mode = not _edit_mode
    build(_current_dir)
    if _edit_mode and _edit != null:
        _edit.grab_focus()
        _edit.select_all()

func on_seg(dir):
    emit_signal("segment_picked", dir)

func on_path_entered(text):
    _try_navigate(text, true)

func on_path_changed(text):
    _try_navigate(text, false)

func _try_navigate(text, revert_on_fail):
    var norm = ABAssetDatabase.normalize(text)
    if norm == _current_dir:
        return
    if DirAccess.dir_exists_absolute(norm):
        emit_signal("segment_picked", norm)
    elif revert_on_fail and _edit != null:
        _edit.text = _current_dir
