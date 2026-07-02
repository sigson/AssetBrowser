tool
extends Reference
class_name ABIThumbnailProvider

# GDScript не имеет интерфейсов — контракт выражен «утиной типизацией».
# Провайдер превью должен предоставлять:
#   provider_id() -> String
#   version()     -> int
#   handles(res_type: String) -> bool
#   generate(res_path: String, size: int, on_ready: FuncRef) -> void
# Этот файл оставлен как документация контракта; ThumbnailService принимает любой
# объект с указанными методами.
