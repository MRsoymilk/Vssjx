class_name NpcFinder
extends RefCounted
## Same-map presentation and bounded path planning, without gameplay writes.

static func row(resident: Dictionary, origin: Vector2i, stage: int = -1, hint: String = "") -> Dictionary:
	var id: String = resident.id
	var service := String(resident.get("service_label", ""))
	if service.is_empty(): service = String(AIWorld.resident(id).get("service_label", "交谈／任务"))
	if id == "qingwei": service = "入派／任务／调息"
	if id == EndlessRules.rules.npc.id: service = "无尽试炼／排行榜"
	var cell := Vector2i(resident.cell[0], resident.cell[1])
	return {"kind":"npc_find", "id":id, "name":("! " if stage in [0, 2] else "") + String(resident.name),
		"detail":"%s · [%d,%d] · 约%d格%s" % [service, cell.x, cell.y, absi(origin.x-cell.x)+absi(origin.y-cell.y), " · "+hint if not hint.is_empty() else ""]}

static func route(grid: AStarGrid2D, origin: Vector2i, target: Vector2i, exits: Array) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	if not grid.region.has_point(origin) or not grid.region.has_point(target) or grid.is_point_solid(origin): return best
	# Do not route through auto-transfer cells. Restore the shared grid before returning.
	var previous := {}
	for gate in exits:
		for value in gate.get("cells", [gate.cell]):
			var point := Vector2i(value[0], value[1])
			if point == origin or not grid.region.has_point(point) or previous.has(point): continue
			previous[point] = grid.is_point_solid(point); grid.set_point_solid(point, true)
	for y in range(-2, 3):
		for x in range(-2, 3):
			if absi(x)+absi(y) > 2 or (x == 0 and y == 0): continue
			var goal := target + Vector2i(x, y)
			if not grid.region.has_point(goal) or grid.is_point_solid(goal): continue
			var path := grid.get_id_path(origin, goal)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()): best = path
	for point in previous: grid.set_point_solid(point, previous[point])
	return best

static func waypoint(path: Array[Vector2i]) -> Vector2i:
	# Movement packets carry destinations, not client paths. A straight segment has
	# a unique shortest route, so the server cannot shortcut across a portal cell.
	if path.size() < 2: return path[0] if not path.is_empty() else Vector2i(-1, -1)
	var direction := path[1] - path[0]
	var index := 1
	while index+1 < path.size() and path[index+1]-path[index] == direction: index += 1
	return path[index]
