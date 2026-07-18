tool
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

var _direct = null
var _git = null
var _git_menu = null
var _git_sync = false

func build(shared, state):
    _s = shared
    _state = state
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _regex = _toggle(null, ".*", "regex", state.regex)
    _content = _toggle(null, "in", "content", state.content)
    _split = _toggle(null, "kw", "split keywords", state.split)

    _type = Button.new()
    _type.toggle_mode = true
    _type.hint_tooltip = "filter by resource type"
    _type.focus_mode = Control.FOCUS_NONE
    _glyph(_type, "Object", "type")
    _type.connect("toggled", self, "on_type_toggled")
    add_child(_type)

    _scope = _toggle("Filesystem", "all", "global scope", state.scope_global)

    # Direct filter: фильтровать видимость файлов прямо в директориях вместо
    # переключения в режим результатов поиска.
    _direct = Button.new()
    _direct.toggle_mode = true
    _direct.pressed = state.direct
    _direct.hint_tooltip = "direct filter: hide non-matching files in place"
    _direct.focus_mode = Control.FOCUS_NONE
    _glyph(_direct, "Filter", "direct")
    _direct.connect("toggled", self, "on_direct_toggled")
    add_child(_direct)

    _build_git_controls(state)
    _refresh_scope_enabled()

    _clear = Button.new()
    _clear.focus_mode = Control.FOCUS_NONE
    _clear.hint_tooltip = "clear"
    _glyph(_clear, "Close", "x")
    _clear.connect("pressed", self, "on_clear")
    add_child(_clear)

    var mag = TextureRect.new()
    mag.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
    mag.texture = _s.thumbs.editor_icon("Search") if _s != null else null
    mag.rect_min_size = Vector2(16, 16)
    add_child(mag)

    _input = LineEdit.new()
    _input.placeholder_text = "search... (t:texture l:ui)"
    _input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _input.rect_min_size = Vector2(40, 0)
    _input.text = state.text
    _input.connect("text_changed", self, "on_text")
    add_child(_input)

    _debounce = Timer.new()
    _debounce.one_shot = true
    _debounce.connect("timeout", self, "_emit")
    add_child(_debounce)

    _opt_in_dlg = ConfirmationDialog.new()
    _opt_in_dlg.window_title = "Global content search"
    _opt_in_dlg.dialog_text = "Run content search across the whole project?\nThis opens and scans many files and may be slow."
    _opt_in_dlg.connect("confirmed", self, "on_opt_in_confirmed")
    _opt_in_dlg.connect("popup_hide", self, "on_opt_in_dismissed")
    add_child(_opt_in_dlg)
    _opt_in_dlg.set_as_toplevel(true)

    _type_dlg = ABTypeSelectorDialog.new()
    _type_dlg.build(_s)
    _type_dlg.connect("applied", self, "on_type_applied")
    add_child(_type_dlg)
    _type_dlg.set_as_toplevel(true)

    _refresh_type_toggle()

# ---------- git ----------
func _build_git_controls(state):
    var have_git = _s != null and _s.git != null and _s.git.available

    _git = Button.new()
    _git.toggle_mode = true
    _git.pressed = state.git_view and have_git
    _git.disabled = not have_git
    _git.hint_tooltip = "git view: colour by state" if have_git \
        else "git view: project is not in a git working tree"
    _git.focus_mode = Control.FOCUS_NONE
    _glyph(_git, "VcsBranches", "git")
    _git.connect("toggled", self, "on_git_toggled")
    add_child(_git)

    if not state.git_view or not have_git:
        state.git_view = false
        state.git_states = null

    _git_menu = MenuButton.new()
    _git_menu.hint_tooltip = "git state filter"
    _git_menu.focus_mode = Control.FOCUS_NONE
    _glyph(_git_menu, "VcsChanges", "state")
    var p = _git_menu.get_popup()
    p.add_check_item("New", ABGitService.Status.NEW)
    p.add_check_item("Modified", ABGitService.Status.MODIFIED)
    p.add_check_item("Unmodified", ABGitService.Status.UNMODIFIED)
    p.add_separator()
    p.add_item("All (default)", 10)
    p.add_item("Refresh git status", 11)
    p.connect("id_pressed", self, "on_git_state_picked")
    p.connect("about_to_show", self, "refresh_git_checks")
    add_child(_git_menu)

    _refresh_git_enabled()

func on_git_toggled(pressed):
    if _git_sync:
        return
    _state.git_view = pressed
    if not pressed:
        _state.git_states = null
    else:
        _s.git.ensure_fresh(true)
    _refresh_git_enabled()
    _debounce.stop()
    _emit()

func on_git_state_picked(id):
    if id == 11:
        _s.git.ensure_fresh(true)
        _debounce.stop()
        _emit()
        return

    if id == 10:
        _state.git_states = null
    else:
        var cur = {} if _state.git_states == null else _state.git_states.duplicate()
        if cur.has(id):
            cur.erase(id)
        else:
            cur[id] = true
        # пустой набор и полный набор эквивалентны дефолту
        _state.git_states = null if (cur.size() == 0 or cur.size() >= 3) else cur

    _debounce.stop()
    _emit()

func refresh_git_checks():
    var p = _git_menu.get_popup()
    var sel = _state.git_states
    for st in [ABGitService.Status.NEW, ABGitService.Status.MODIFIED, ABGitService.Status.UNMODIFIED]:
        var idx = p.get_item_index(st)
        if idx >= 0:
            p.set_item_checked(idx, sel != null and sel.has(st))

func _refresh_git_enabled():
    if _git_menu != null:
        _git_menu.disabled = not _state.git_view

func on_direct_toggled(pressed):
    _state.direct = pressed
    _refresh_scope_enabled()
    _debounce.stop()
    _emit()

# Область поиска применима только к обходу. Direct filter обхода не делает —
# фильтруется всегда текущая директория, поэтому тоггл гасим, чтобы он не врал.
func _refresh_scope_enabled():
    if _scope == null:
        return
    _scope.disabled = _state.direct
    _scope.hint_tooltip = "global scope — недоступно при direct filter (фильтруется текущая папка)" \
        if _state.direct else "global scope"

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
    _type.pressed = _state.types != null
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
            _scope.pressed = false

func sync_from_state():
    if _input != null:
        _input.text = _state.text
    _refresh_type_toggle()
    if _direct != null:
        _direct.pressed = _state.direct
    _refresh_scope_enabled()
    if _git != null:
        _git_sync = true
        _git.pressed = _state.git_view
        _git_sync = false
    _refresh_git_enabled()

func _toggle(icon, fallback, tip, pressed):
    var b = Button.new()
    b.toggle_mode = true
    b.pressed = pressed
    b.hint_tooltip = tip
    b.focus_mode = Control.FOCUS_NONE
    _glyph(b, icon, fallback)
    b.connect("toggled", self, "on_toggle")
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
    _state.regex = _regex.pressed
    _state.content = _content.pressed
    _state.split = _split.pressed
    _state.scope_global = _scope.pressed

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
    # git-состояния — такой же критерий запроса, как текст и тип: «очистить»
    # обязано снять и его, иначе вью останется в режиме результатов.
    # Сам git view при этом не выключаем — это режим подсветки, а не запрос.
    _state.git_states = null
    _refresh_type_toggle()
    _debounce.stop()
    _emit()

func _emit():
    emit_signal("search_changed")
