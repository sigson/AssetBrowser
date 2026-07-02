tool
extends Resource
class_name ABAssetBrowserConfig

# Конфиг плагина в виде .tres-ресурса. Редактируется в инспекторе: галочки решают,
# где открыть браузер — в доке и/или в нижней панели. Можно включить оба сразу
# (получится два независимых редактора, разделяющих общий слой данных).
# Изменения вступают в силу при следующем включении плагина / перезапуске редактора.

export var open_in_dock = true
export var open_in_bottom_panel = false

# Слот дока: 0=LeftUL 1=LeftBL 2=LeftUR 3=LeftBR 4=RightUL 5=RightBL 6=RightUR 7=RightBR
export(int, "LeftUL,LeftBL,LeftUR,LeftBR,RightUL,RightBL,RightUR,RightBR") var dock_slot = 0

export var bottom_panel_title = "Asset Browser"
