extends PlatformDisplayInterface
## Canvas/window pixels use Godot transforms; CSS safe-area belongs to the shell.
var _window: Window

func _ready() -> void:
	_window = get_tree().root
	_window.size_changed.connect(_changed)
	ThemeDB.fallback_font = load("res://assets/fonts/cjk_fallback.tres")

func snapshot() -> Dictionary:
	if not is_instance_valid(_window): return {}
	return {"window_pixels": _window.size, "logical_rect": _window.get_visible_rect(),
		"usable_screen_pixels": Rect2i(Vector2i.ZERO, _window.size),
		"safe_screen_pixels": Rect2i(Vector2i.ZERO, _window.size), "safe_area_handled_by_shell": true}

func window_to_logical(position: Vector2) -> Vector2:
	return _window.get_final_transform().affine_inverse() * position

func logical_to_window(position: Vector2) -> Vector2:
	return _window.get_final_transform() * position

func _changed() -> void:
	changed.emit(snapshot())
