class_name PlatformDisplayInterface
extends Node
## Native coordinates: window pixels versus Godot logical coordinates, not CSS.
signal changed(snapshot: Dictionary)

func snapshot() -> Dictionary:
	return {}

func window_to_logical(position: Vector2) -> Vector2:
	return position

func logical_to_window(position: Vector2) -> Vector2:
	return position
