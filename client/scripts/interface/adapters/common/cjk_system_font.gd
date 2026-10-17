extends SystemFont
## Desktop fonts keep priority; shipped native builds also need CJK
## when the operating system has no usable Chinese system font installed.
func _init() -> void:
	if OS.has_feature("web") or OS.has_feature("android") or OS.has_feature("windows") or OS.has_feature("bundled_cjk"):
		fallbacks = [load("res://assets/fonts/cjk_fallback.tres")]
