tool
extends Reference
class_name ABClipboardModel

enum ClipboardMode { NONE, COPY, CUT }

var paths = []
var mode = ClipboardMode.NONE

func has_content():
    return mode != ClipboardMode.NONE and paths.size() > 0

func set_data(new_paths, new_mode):
    paths = new_paths if new_paths != null else []
    mode = new_mode

func clear():
    paths = []
    mode = ClipboardMode.NONE
