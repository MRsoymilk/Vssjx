class_name WorldMoveTarget
extends Node2D
## Local visual feedback only; never changes the route or the character state.

var destination := Vector2i(-1, -1)

func set_destination(cell: Vector2i) -> void:
	destination = cell
	position = Vector2(cell * 16) + Vector2(8, 8)
	show()

func clear() -> void:
	hide()
	destination = Vector2i(-1, -1)
