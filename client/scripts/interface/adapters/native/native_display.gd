extends PlatformDisplayInterface

var _window: Window

func _ready() -> void:
	_window = get_tree().root
	_window.size_changed.connect(_on_size_changed)

func snapshot() -> Dictionary:
	if not is_instance_valid(_window): return {}
	var available := Rect2i(Vector2i.ZERO, _window.size)
	var safe := available
	if DisplayServer.get_name() != "headless":
		available = DisplayServer.screen_get_usable_rect(_window.current_screen)
		safe = DisplayServer.get_display_safe_area()
	return {"window_pixels": _window.size, "logical_rect": _window.get_visible_rect(),
		"usable_screen_pixels": available, "safe_screen_pixels": safe}

func window_to_logical(position: Vector2) -> Vector2:
	return _window.get_final_transform().affine_inverse() * position

func logical_to_window(position: Vector2) -> Vector2:
	return _window.get_final_transform() * position

func _on_size_changed() -> void:
	changed.emit(snapshot())
