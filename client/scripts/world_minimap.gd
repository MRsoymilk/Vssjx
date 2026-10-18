class_name OriginalWorldMinimap
extends Control

signal toggle_requested
var world: ShushanWorld
var expanded := true
var shared_map: Dictionary = {}
var shared_entities: Dictionary = {}
var shared_population: Dictionary = {}
var shared_character_id := ""

func set_shared_world(data: Dictionary, entities: Dictionary, character_id: String) -> void:
	shared_map = data
	shared_entities = entities
	shared_character_id = character_id
	queue_redraw()

func set_shared_population(entities: Dictionary) -> void:
	shared_population = entities
	queue_redraw()

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
	var local := world != null and is_instance_valid(world)
	if not local and shared_map.is_empty(): return
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
			if (local and world.zone == 0) or (not local and shared_map.get("map_id") == "qingyun_trail"):
				var index := y * 32 + x
				var data: Dictionary = world.map_data if local else shared_map
				var tile := int(data.tiles[index])
				fill = Color("426969") if tile == 123 else (Color("919279") if tile == 138 or tile in [18, 20, 21, 22, 30, 32, 40, 41, 42] else Color("666e58"))
				if not local and data.blocked[index]: fill = fill.darkened(0.35)
			else: fill = Color("666374")
			if local and world.astar.is_point_solid(point): fill = fill.darkened(0.35)
			draw_rect(Rect2(origin + Vector2(point) * scale_value, Vector2.ONE * scale_value), fill)
	var map_id: String = world.map_id if local else String(shared_map.map_id)
	for gate in SharedWorldMap.exits(map_id):
		draw_rect(Rect2(origin+Vector2(gate.cell[0],gate.cell[1])*scale_value,Vector2(3,3)),Color("59e3d7"))
	if not local:
		for entry in shared_population.values():
			draw_rect(Rect2(origin + Vector2(entry.cell[0], entry.cell[1]) * scale_value, Vector2(2, 2)), Color("e2e29b") if entry.kind == "npc" else Color("d27950"))
		for id in shared_entities:
			var entry: Dictionary = shared_entities[id]
			var own: bool = id == shared_character_id
			draw_rect(Rect2(origin + Vector2(entry.cell[0], entry.cell[1]) * scale_value, Vector2(3, 3) if own else Vector2(2, 2)), Color("f7ed21") if own else Color("8de8f5"))
		return
	for enemy in world.available_enemies():
		var cell := Vector2(enemy.cell[0], enemy.cell[1])
		draw_rect(Rect2(origin + cell * scale_value, Vector2(2, 2)), Color("d27950"))
	if not AIWorld.map_data(map_id).is_empty():
		for resident in world.map_data.residents:
			if resident.kind=="npc":draw_rect(Rect2(origin+Vector2(resident.cell[0],resident.cell[1])*scale_value,Vector2(2,2)),Color("e2e29b"))
	elif world.zone == 0: draw_rect(Rect2(origin + Vector2(10, 13) * scale_value, Vector2(2, 2)), Color("e2e29b"))
	draw_rect(Rect2(origin + Vector2(world.cell) * scale_value, Vector2(3, 3)), Color("f7ed21"))
