extends SystemFont
## Keep native system-font metrics/priority unchanged; Web has no system fonts.
func _init() -> void:
	if OS.has_feature("web"):
		fallbacks = [load("res://assets/fonts/cjk_fallback.tres")]
