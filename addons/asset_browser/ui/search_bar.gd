@tool
extends ABFlowContainer
class_name ABSearchBar

signal search_changed()

var _s = null
var _input = null
var _regex = null
var _content = null
var _split = null
var _scope = null
var _clear = null
var _type = null
var _type_dlg = null
var _type_sync = false
var _state = null
var _debounce = null
var _opt_in_dlg = null

func build(shared, state):
    _s = shared
    _state = state
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _regex = _toggle(null, ".*", "regex", state.regex)
    _content = _toggle(null, "in", "content", state.content)
    _split = _toggle(null, "kw", "split keywords", state.split)

    _type = Button.new()
    _type.toggle_mode = true
    _type.tooltip_text = "filter by resource type"
    _type.focus_mode = Control.FOCUS_NONE
    _glyph(_type, "Object", "type")
    _type.connect("toggled", Callable(self, "on_type_toggled"))
    add_child(_type)

    _scope = _toggle("Filesystem", "all", "global scope", state.scope_global)

    _clear = Button.new()
    _clear.focus_mode = Control.FOCUS_NONE
    _clear.tooltip_text = "clear"
    _glyph(_clear, "Close", "x")
    _clear.connect("pressed", Callable(self, "on_clear"))
    add_child(_clear)

    var mag = TextureRect.new()
    mag.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    mag.texture = _s.thumbs.editor_icon("Search") if _s != null else null
    mag.custom_minimum_size = Vector2(16, 16)
    add_child(mag)

    _input = LineEdit.new()
    _input.placeholder_text = "search... (t:texture l:ui)"
    _input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _input.custom_minimum_size = Vector2(40, 0)
    _input.text = state.text
    _input.connect("text_changed", Callable(self, "on_text"))
    add_child(_input)

    _debounce = Timer.new()
    _debounce.one_shot = true
    _debounce.connect("timeout", Callable(self, "_emit"))
    add_child(_debounce)

    _opt_in_dlg = ConfirmationDialog.new()
    _opt_in_dlg.title = "Global content search"
    _opt_in_dlg.dialog_text = "Run content search across the whole project?\nThis opens and scans many files and may be slow."
    _opt_in_dlg.connect("confirmed", Callable(self, "on_opt_in_confirmed"))
    _opt_in_dlg.connect("canceled", Callable(self, "on_opt_in_dismissed"))
    add_child(_opt_in_dlg)

    _type_dlg = ABTypeSelectorDialog.new()
    _type_dlg.build(_s)
    _type_dlg.connect("applied", Callable(self, "on_type_applied"))
    add_child(_type_dlg)

    _refresh_type_toggle()

func on_type_toggled(_pressed):
    if _type_sync:
        return
    _type_dlg.open(_state.types)
    _refresh_type_toggle()

func on_type_applied():
    _state.types = _type_dlg.result_filter   # null => дефолт
    _refresh_type_toggle()
    _debounce.stop()
    _emit()

func _refresh_type_toggle():
    if _type == null:
        return
    _type_sync = true
    _type.button_pressed = _state.types != null
    _type_sync = false

func _needs_global_content_opt_in():
    var require = _s == null or _s.settings.content_requires_global_optin
    return require and _state.content and _state.scope_global and not _state.global_content_confirmed

func on_opt_in_confirmed():
    _state.global_content_confirmed = true
    _debounce.stop()
    _emit()

func on_opt_in_dismissed():
    if _state.global_content_confirmed:
        return
    if _state.content and _state.scope_global and not _state.global_content_confirmed:
        _state.scope_global = false
        if _scope != null:
            _scope.button_pressed = false

func sync_from_state():
    if _input != null:
        _input.text = _state.text
    _refresh_type_toggle()

func _toggle(icon, fallback, tip, pressed):
    var b = Button.new()
    b.toggle_mode = true
    b.button_pressed = pressed
    b.tooltip_text = tip
    b.focus_mode = Control.FOCUS_NONE
    _glyph(b, icon, fallback)
    b.connect("toggled", Callable(self, "on_toggle"))
    add_child(b)
    return b

func _glyph(b, icon, fallback):
    var tex = null
    if icon != null and _s != null:
        tex = _s.thumbs.editor_icon(icon)
    if tex != null:
        b.icon = tex
        b.text = ""
    else:
        b.text = fallback

func on_text(t):
    _state.text = t
    var wait = max(0.05, (_s.settings.search_debounce_ms if _s != null else 300) / 1000.0)
    _debounce.wait_time = wait
    _debounce.start()

func on_toggle(_pressed):
    _state.regex = _regex.button_pressed
    _state.content = _content.button_pressed
    _state.split = _split.button_pressed
    _state.scope_global = _scope.button_pressed

    if not _state.scope_global or not _state.content:
        _state.global_content_confirmed = false

    if _needs_global_content_opt_in():
        _debounce.stop()
        _opt_in_dlg.popup_centered()
        return

    _debounce.stop()
    _emit()

func on_clear():
    _input.text = ""
    _state.text = ""
    _state.types = null
    _refresh_type_toggle()
    _debounce.stop()
    _emit()

func _emit():
    emit_signal("search_changed")
