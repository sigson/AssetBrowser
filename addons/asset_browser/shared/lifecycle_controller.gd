tool
extends Reference
class_name ABLifecycleController

# Координатор жизненного цикла плагина (ФТ-6, §8.2). Один на плагин, живёт в Shared.
# Глобальный killswitch: переводит ОБА хоста (dock + bottom) в Suspended синхронно.
#
# Хосты («ILifecycleHost») — утиная типизация: должны иметь методы
#   save_state(), teardown(), show_placeholder(), rebuild_body().
#
# Примечание к порту: в GDScript нет управляемого GC. Texture/Resource — refcounted,
# их нативная память освобождается детерминированно при обнулении ссылок (выгрузка
# плиток через queue_free + очистка кеша). Поэтому явные GC.Collect/Dispose из C#
# заменены авто-освобождением по refcount; функционально память возвращается так же.

signal suspended_changed(suspended)

var _s = null
var _hosts = []

var is_suspended = false

func init(shared):
    _s = shared

func register(host):
    if not _hosts.has(host):
        _hosts.append(host)

func unregister(host):
    _hosts.erase(host)

func toggle():
    if is_suspended:
        resume()
    else:
        suspend()

# §8.3
func suspend():
    if is_suspended:
        return   # идемпотентно

    for h in _hosts:
        h.save_state()
    for h in _hosts:
        h.teardown()

    _s.thumbs.shutdown()
    _s.db.shutdown()

    is_suspended = true
    for h in _hosts:
        h.show_placeholder()

    emit_signal("suspended_changed", true)

    # Освобождение нативной памяти происходит автоматически по refcount после того,
    # как SceneTree обработает отложенные queue_free тел/плиток (конец кадра).
    release_memory_now()

func release_memory_now():
    # В GDScript нет ручного GC — no-op. Оставлено для соответствия структуре C#.
    pass

# §8.4
func resume():
    if not is_suspended:
        return

    _s.db.init(_s.editor, _s.settings)
    _s.thumbs.init(_s.editor, _s.settings)
    _s.db.set_tag_store(_s.tags)

    is_suspended = false

    for h in _hosts:
        h.rebuild_body()

    _s.db.request_scan()

    emit_signal("suspended_changed", false)
