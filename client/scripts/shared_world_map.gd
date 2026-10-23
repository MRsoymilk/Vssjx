class_name SharedWorldMap
extends RefCounted
## Mode-independent terrain, collision and scenery. The server validates MAP_PATH's bytes.
const MAP_PATH := "res://assets/data/qingyun-v1.json"
const POPULATION_PATH := "res://assets/data/qingyun-population-v1.json"
const MAPS := {"qingyun_trail": MAP_PATH, "ancient_ruins": "res://assets/data/ancient-ruins-v1.json"}
const POPULATIONS := {"qingyun_trail": POPULATION_PATH, "ancient_ruins": "res://assets/data/ruins-population-v1.json"}

static func load_data(map_id: String = "qingyun_trail") -> Dictionary:
	if not AIWorld.map_data(map_id).is_empty(): return AIWorld.map_data(map_id)
	return JSON.parse_string(FileAccess.get_file_as_string(MAPS[map_id]))

static func population(map_id: String = "qingyun_trail") -> Array:
	if not AIWorld.map_data(map_id).is_empty(): return AIWorld.map_data(map_id).residents
	return JSON.parse_string(FileAccess.get_file_as_string(POPULATIONS[map_id]))

static func portal(map_id: String) -> Dictionary:
	if not AIWorld.map_data(map_id).is_empty(): return AIWorld.map_data(map_id).portal
	return {"id": "ruins_gate", "cell": [28, 16], "name": "古剑遗迹 · 灵门"} if map_id == "qingyun_trail" else {"id": "trail_gate", "cell": [3, 16], "name": "返回山道"}

static func exits(map_id: String) -> Array:
	var generated := AIWorld.map_data(map_id)
	if not generated.is_empty(): return generated.exits
	var gate := portal(map_id)
	var station := AIWorld.station(map_id)
	return [{"cell":gate.cell,"target_map":"ancient_ruins" if map_id=="qingyun_trail" else "qingyun_trail","name":gate.name,"legacy":true},{"cell":[station.x,station.y],"target_map":"ai_001","name":"灵空台 · AI生成"}]

static func exit_at(map_id: String, cell: Vector2i) -> Dictionary:
	for gate in exits(map_id):
		for point in gate.get("cells",[gate.cell]):
			if cell==Vector2i(point[0],point[1]): return gate
	return {}

static func title(map_id: String) -> String:
	if not AIWorld.map_data(map_id).is_empty(): return AIWorld.map_data(map_id).name + " · AI生成"
	return "青云山道" if map_id == "qingyun_trail" else "古剑遗迹"

static func level_range(map_id:String)->Vector2i:
	var data:=AIWorld.map_data(map_id)
	if not data.is_empty():return Vector2i(int(data.level_min),int(data.level_max))
	var levels:Array=population(map_id).filter(func(r:Dictionary)->bool:return r.kind!="npc").map(func(r:Dictionary)->int:return int(r.level))
	return Vector2i(int(levels.min()),int(levels.max()))

static func level_text(map_id:String)->String:
	var levels:=level_range(map_id)
	return "%d级"%levels.x if levels.x==levels.y else "%d～%d级"%[levels.x,levels.y]

static func exit_label(gate:Dictionary)->String:
	return "%s · %s"%[gate.name,level_text(gate.target_map)]

static func exists(map_id: Variant) -> bool:
	return map_id is String and (MAPS.has(map_id) or not AIWorld.map_data(map_id).is_empty())

static func map_hash(map_id: String) -> String:
	if not AIWorld.map_data(map_id).is_empty(): return AIWorld.catalog_hash
	return FileAccess.get_sha256(MAPS[map_id])

static func build(terrain: TileMapLayer, grid: AStarGrid2D, data: Dictionary) -> void:
	var width := int(data.width)
	var cell_size := int(data.cell_size)
	grid.region = Rect2i(0, 0, width, int(data.height))
	grid.cell_size = Vector2(cell_size, cell_size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	NativeWorldMaps.build(terrain,data)
	for index in data.blocked.size():
		var point := Vector2i(index % width, index / width)
		grid.set_point_solid(point, data.blocked[index])

static func add_scenery(parent: Node2D, data: Dictionary) -> void:
	NativeWorldMaps.add_scenery(parent,String(data.map_id))
