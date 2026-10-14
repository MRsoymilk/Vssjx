class_name OriginalWorldMinimap
extends Control

signal toggle_requested
var world: ShushanWorld
var expanded := true

func _ready() -> void:
	size = Vector2(80, 82)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			expanded = not expanded
			size = Vector2(80, 82) if expanded else Vector2(26, 17)
			queue_redraw()
			accept_event()
	)

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if world == null or not is_instance_valid(world): return
	if not expanded:
		draw_rect(Rect2(0, 0, 26, 17), Color("152424"))
		draw_rect(Rect2(0, 0, 26, 17), Color("e6efc8"), false)
		for y in 3:
			for x in 4: draw_rect(Rect2(5 + x * 4, 4 + y * 3, 2, 2), Color("c1d3b7"))
		return
	draw_rect(Rect2(0, 0, 80, 82), Color(0.03, 0.05, 0.04, 0.83))
	draw_rect(Rect2(0, 0, 80, 82), Color("eef3d3"), false)
	var origin := Vector2(13, 14)
	var scale_value := 1.65
	for y in 32:
		for x in 32:
			var point := Vector2i(x, y)
			var fill := Color("626653")
			if world.zone == 0:
				match world.ground_at(point):
					ShushanWorld.Ground.GRASS: fill = Color("666e58")
					ShushanWorld.Ground.DIRT, ShushanWorld.Ground.BRIDGE: fill = Color("919279")
					ShushanWorld.Ground.WATER: fill = Color("426969")
			else: fill = Color("666374")
			if world.astar.is_point_solid(point): fill = fill.darkened(0.35)
			draw_rect(Rect2(origin + Vector2(point) * scale_value, Vector2.ONE * scale_value), fill)
	for enemy in world.available_enemies():
		var cell := Vector2(enemy.cell[0], enemy.cell[1])
		draw_rect(Rect2(origin + cell * scale_value, Vector2(2, 2)), Color("d27950"))
	if world.zone == 0: draw_rect(Rect2(origin + Vector2(10, 13) * scale_value, Vector2(2, 2)), Color("e2e29b"))
	draw_rect(Rect2(origin + Vector2(world.cell) * scale_value, Vector2(3, 3)), Color("f7ed21"))
