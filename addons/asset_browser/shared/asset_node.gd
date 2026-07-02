tool
extends Reference
class_name ABAssetNode

var path = ""
var name = ""
var is_dir = false
var res_type = ""      # "Texture","GDScript","TileSet",... (из EditorFileSystem), не расширение
var size = -1          # лениво
var mod_time = -1      # лениво
var tags = {}          # множество тегов как Dictionary {tag: true}

func ext():
    var i = name.find_last(".")
    return "" if i < 0 else name.substr(i + 1).to_lower()
