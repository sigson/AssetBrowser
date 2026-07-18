tool
extends Reference
class_name ABShared

# Один экземпляр на плагин. Прокидывается во все View.

var editor = null
var undo = null

var settings = null
var db = null
var thumbs = null
var favorites = null
var clipboard = null
var tags = null
var lifecycle = null       # ФТ-6: глобальный killswitch
var type_graph = null      # граф типов ресурсов (в C# — синглтон ResourceTypeGraph.Instance)
var git = null             # статус рабочего дерева git (ABGitService)

# Хук полного рестарта плагина (выставляет AssetBrowserPlugin). FuncRef или null.
var restart_hook = null

func init(p_editor, p_undo):
	editor = p_editor
	undo = p_undo

	settings = ABSettings.new()
	settings.load_data()

	db = ABAssetDatabase.new()
	db.init(editor, settings)

	thumbs = ABThumbnailService.new()
	thumbs.init(editor, settings)

	favorites = ABFavoritesModel.new()
	favorites.load_data()

	tags = ABTagStore.new()
	tags.load_data()
	db.set_tag_store(tags)

	clipboard = ABClipboardModel.new()

	type_graph = ABResourceTypeGraph.build()

	git = ABGitService.new()
	git.init(settings)

	lifecycle = ABLifecycleController.new()
	lifecycle.init(self)

func dispose2():
	if thumbs != null:
		thumbs.shutdown()
	if db != null:
		db.shutdown()
	if settings != null:
		settings.save()
	if favorites != null:
		favorites.save()
	if tags != null:
		tags.save()

func call_restart_hook():
	if restart_hook != null:
		restart_hook.call_func()
