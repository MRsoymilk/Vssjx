class_name ShushanWorld
extends Node2D

signal interaction(kind: String, data: Dictionary)
signal moved
const CELL := 16
const MAP_SIZE := 32
const WALK_SPEED := 72.0
const WALK_CYCLE_DISTANCE := 32.0 # One full left/right stride, in map pixels.
enum Ground { GRASS, DIRT, WATER, BRIDGE }
const PATROL_OFFSETS := [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 1), Vector2i(-2, 1), Vector2i(-2, 0), Vector2i.ZERO]
const ENEMIES := [
	{"id": "wolf_a", "name": "山狼", "kind": "wolf", "art": "monster/langw", "cell": [18, 10], "hp": 62, "attack": 13, "defense": 3, "gold": 12, "xp": 16},
	{"id": "wolf_b", "name": "山狼", "kind": "wolf", "art": "monster/langw", "cell": [24, 20], "hp": 72, "attack": 15, "defense": 4, "gold": 14, "xp": 18},
	{"id": "wolf_c", "name": "山狼", "kind": "wolf", "art": "monster/langw", "cell": [15, 24], "hp": 82, "attack": 17, "defense": 4, "gold": 16, "xp": 20},
	{"id": "spirit", "name": "山灵", "kind": "spirit", "art": "monster/hs1", "cell": [22, 8], "hp": 70, "attack": 14, "defense": 2, "gold": 20, "xp": 22},
	{"id": "guardian", "name": "遗迹守卫", "kind": "spirit", "art": "monster/xt1", "cell": [17, 19], "hp": 100, "attack": 19, "defense": 6, "gold": 24, "xp": 30},
	{"id": "boss", "name": "赤焰妖王", "kind": "boss", "art": "monster/nt1", "cell": [24, 12], "hp": 190, "attack": 23, "defense": 7, "gold": 120, "xp": 90}
]
var zone := 0
var enabled := true:
	set(value):
		enabled = value
		for sprite in enemy_nodes.values():
			if not value: sprite.pause()
			else: sprite.play()
var terrain: TileMapLayer
var actors: Node2D
var hero: AnimatedSprite2D
var camera: Camera2D
var astar := AStarGrid2D.new()
var cell := Vector2i(10, 16)
var path: Array[Vector2i] = []
var next_cell := Vector2i(-1, -1)
var pending: Dictionary = {}
var enemy_nodes: Dictionary = {}
var patrols: Dictionary = {}
var facing_left := true # Native stand and walk composites face left.
var walk_distance := 0.0
var portal_marker: Node2D

func _ready() -> void:
	zone = int(Game.player.zone)
	cell = Vector2i(Game.player.cell[0], Game.player.cell[1])
	_build_map()
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	_add_scenery()
	portal_marker = Node2D.new()
	portal_marker.set_script(preload("res://scripts/portal.gd"))
	portal_marker.position = cell_center(Vector2i(28, 16) if zone == 0 else Vector2i(3, 16))
	actors.add_child(portal_marker)
	_name_tag(portal_marker, "古剑遗迹 · 灵门" if zone == 0 else "返回山道", Color("c2f7f4"))
	portal_marker.get_child(0).position.y = -50
	var art: String = Game.actor_key()
	hero = OriginalArt.actor(art)
	hero.position = cell_center(cell)
	actors.add_child(hero)
	_name_tag(hero, String(Game.player.name), Color("fff4c9"))
	if zone == 0:
		var npc := OriginalArt.actor("hero/mfs")
		npc.position = cell_center(Vector2i(10, 13))
		actors.add_child(npc)
		_name_tag(npc, "清微道人 · 任务", Color("ffe095"))
	for enemy in available_enemies():
		var sprite := OriginalArt.actor(String(enemy.art))
		sprite.position = cell_center(Vector2i(enemy.cell[0], enemy.cell[1]))
		actors.add_child(sprite)
		enemy_nodes[enemy.id] = sprite
		_name_tag(sprite, String(enemy.name), Color("ffb29a"))
		if enemy.kind == "wolf":
			var home := Vector2i(enemy.cell[0], enemy.cell[1])
			patrols[enemy.id] = {"home": home, "cell": home, "next": Vector2i(-1, -1),
				"path": [], "waypoint": 0, "wait": 0.7 + patrols.size() * 0.25}
	camera = Camera2D.new()
	camera.position = hero.position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 512
	camera.limit_bottom = 512
	add_child(camera)
	if astar.is_point_solid(cell):
		cell = Vector2i(10, 16)
		hero.position = cell_center(cell)
		_save_position()
	queue_redraw()

func cell_center(value: Vector2i) -> Vector2:
	return Vector2(value * CELL) + Vector2(8, 8)

func _build_map() -> void:
	terrain = TileMapLayer.new()
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(CELL, CELL)
	var source := TileSetAtlasSource.new()
	source.texture = load("res://assets/tiles/original_tiles.png")
	source.texture_region_size = Vector2i(CELL, CELL)
	for i in 756:
		source.create_tile(Vector2i(i % 32, i / 32))
	tileset.add_source(source, 0)
	terrain.tile_set = tileset
	add_child(terrain)
	astar.region = Rect2i(0, 0, MAP_SIZE, MAP_SIZE)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	var random := RandomNumberGenerator.new()
	random.seed = 403084 + zone
	for y in MAP_SIZE:
		for x in MAP_SIZE:
			var point := Vector2i(x, y)
			var tile: int = 14 if zone == 0 else (258 if random.randf() > 0.025 else 222)
			var solid := x == 0 or y == 0 or x == 31 or y == 31
			if zone == 0:
				match ground_at(point):
					Ground.GRASS:
						tile = 13 if random.randf() < 0.3 else 14
						if x > 7 and random.randf() < 0.025: tile = random.randi_range(0, 12)
					Ground.DIRT: tile = road_tile(point)
					Ground.WATER:
						tile = 123
						solid = true
					Ground.BRIDGE: tile = 138
			else:
				if y == 16 or y == 17:
					tile = 158 if y == 16 else 168
			if x == 0 or y == 0 or x == 31 or y == 31:
				if zone == 1: tile = 219
			terrain.set_cell(point, 0, Vector2i(tile % 32, tile / 32))
			astar.set_point_solid(point, solid)

func ground_at(point: Vector2i) -> int:
	var road := point.y == 16 or point.y == 17
	var river := point.x >= 4 and point.x <= 6
	if river: return Ground.BRIDGE if road else Ground.WATER
	if road or (point.x >= 8 and point.x <= 12 and point.y >= 11 and point.y <= 15): return Ground.DIRT
	return Ground.GRASS

func road_tile(point: Vector2i) -> int:
	var mask := 0
	var directions := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for i in directions.size():
		if ground_at(point + directions[i]) not in [Ground.DIRT, Ground.BRIDGE]: mask |= 1 << i
	return {0: 18, 1: 21, 2: 32, 4: 41, 8: 30, 9: 20, 3: 22, 12: 40, 6: 42}.get(mask, 18)

func _add_scenery() -> void:
	var places := [Vector2i(3, 8), Vector2i(8, 8), Vector2i(13, 7), Vector2i(27, 8), Vector2i(29, 24), Vector2i(8, 26), Vector2i(19, 28), Vector2i(2, 24)]
	for i in places.size():
		var tree := OriginalArt.actor("map/m%d" % (2 if zone == 0 else 9))
		tree.position = cell_center(places[i])
		actors.add_child(tree)
		astar.set_point_solid(places[i], true)
		if zone == 0:
			astar.set_point_solid(places[i] + Vector2i(1, 0), true)

func _name_tag(sprite: Node2D, value: String, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = Vector2(-65, -68)
	label.size = Vector2(130, 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimHei", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	label.add_theme_font_override("font", font)
	label.add_theme_color_override("font_outline_color", Color("182821"))
	label.add_theme_constant_override("outline_size", 1)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	sprite.add_child(label)

func available_enemies() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for enemy in ENEMIES:
		var enemy_zone := 1 if enemy.id in ["guardian", "boss"] else 0
		if enemy_zone == zone and not Game.player.defeated.has(enemy.id):
			var current: Dictionary = enemy.duplicate(true)
			if enemy_nodes.has(enemy.id):
				var spot := _enemy_cell(enemy_nodes[enemy.id])
				current.cell = [spot.x, spot.y]
			result.append(current)
	return result

func click(local: Vector2) -> void:
	if not enabled: return
	var world_point := camera.get_screen_center_position() + local - get_viewport_rect().size / 2.0
	var target := Vector2i(floor(world_point.x / CELL), floor(world_point.y / CELL))
	if not astar.region.has_point(target): return
	var found := target_at_pixel(world_point)
	if found.is_empty(): found = target_at(target)
	if found.is_empty():
		pending = {}
		path = _route_to(target)
	else:
		_walk_to(found)

func _route_to(target: Vector2i) -> Array[Vector2i]:
	# Finish the active segment before following a replacement route. Planning
	# from the previous cell can send us back or skip diagonally across cells.
	var origin := next_cell if next_cell.x >= 0 else cell
	var route: Array[Vector2i] = astar.get_id_path(origin, target)
	if not route.is_empty() and route[0] == origin: route.pop_front()
	return route

func target_at_pixel(point: Vector2) -> Dictionary:
	if zone == 0:
		var npc_cell := Vector2i(10, 13)
		if Rect2(cell_center(npc_cell) - Vector2(28, 72), Vector2(56, 80)).has_point(point):
			return {"kind": "npc", "cell": npc_cell, "data": {}}
	for enemy in available_enemies():
		var spot := Vector2i(enemy.cell[0], enemy.cell[1])
		var position_now: Vector2 = enemy_nodes[enemy.id].position if enemy_nodes.has(enemy.id) else cell_center(spot)
		if Rect2(position_now - Vector2(32, 72), Vector2(64, 80)).has_point(point):
			return {"kind": "enemy", "cell": spot, "data": enemy}
	return {}

func target_at(target: Vector2i) -> Dictionary:
	if zone == 0 and target.distance_to(Vector2i(10, 13)) <= 2.0:
		return {"kind": "npc", "cell": Vector2i(10, 13), "data": {}}
	var portal := Vector2i(28, 16) if zone == 0 else Vector2i(3, 16)
	if target.distance_to(portal) <= 1.5:
		return {"kind": "portal", "cell": portal, "data": {}}
	for enemy in available_enemies():
		var spot := Vector2i(enemy.cell[0], enemy.cell[1])
		if target.distance_to(spot) <= 2.0:
			return {"kind": "enemy", "cell": spot, "data": enemy}
	return {}

func _walk_to(target: Dictionary) -> void:
	pending = target
	if target.kind == "enemy" and enemy_nodes.has(target.data.id):
		enemy_nodes[target.data.id].play("idle")
	if cell.distance_to(target.cell) <= 2.0 and next_cell.x < 0:
		_interact_pending()
		return
	var origin := next_cell if next_cell.x >= 0 else cell
	var best: Array[Vector2i] = []
	for offset in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var spot: Vector2i = target.cell + offset
		if astar.is_point_solid(spot): continue
		var candidate := _route_to(spot)
		if spot == origin:
			best = candidate
			break
		if not candidate.is_empty() and (best.is_empty() or candidate.size() < best.size()):
			best = candidate
	path = best

func interact_nearest() -> void:
	if not enabled: return
	var nearest: Dictionary = {}
	var distance := 3.5
	var targets: Array[Dictionary] = []
	if zone == 0: targets.append({"kind": "npc", "cell": Vector2i(10, 13), "data": {}})
	targets.append({"kind": "portal", "cell": Vector2i(28, 16) if zone == 0 else Vector2i(3, 16), "data": {}})
	for enemy in available_enemies():
		targets.append({"kind": "enemy", "cell": Vector2i(enemy.cell[0], enemy.cell[1]), "data": enemy})
	for target in targets:
		var candidate := cell.distance_to(target.cell)
		if candidate < distance:
			distance = candidate
			nearest = target
	if not nearest.is_empty():
		_walk_to(nearest)
	else:
		interaction.emit("hint", {"text": "靠近人物、怪物或灵门，再按交互。"})

func _interact_pending() -> void:
	var target := pending
	pending = {}
	path.clear()
	if not target.is_empty(): interaction.emit(target.kind, target.data)

func _process(delta: float) -> void:
	if not enabled or hero == null: return
	_update_patrols(delta)
	var remaining := WALK_SPEED * delta
	while remaining > 0.0:
		if next_cell.x < 0 and not _begin_step():
			_idle_hero()
			break
		var target := cell_center(next_cell)
		var distance := hero.position.distance_to(target)
		var travel := minf(remaining, distance)
		hero.position = hero.position.move_toward(target, travel)
		_advance_walk(travel)
		remaining -= travel
		if travel >= distance:
			cell = next_cell
			next_cell = Vector2i(-1, -1)
			_save_position()
			if path.is_empty() and not pending.is_empty():
				_idle_hero()
				_interact_pending()
				break
			# Continue held keys without inserting idle at every grid boundary.
			# Spend leftover distance too, so speed does not depend on frame rate.
			if not _begin_step():
				_idle_hero()
				break
	camera.position = hero.position

func _keyboard_direction() -> Vector2i:
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): return Vector2i.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): return Vector2i.RIGHT
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): return Vector2i.UP
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): return Vector2i.DOWN
	return Vector2i.ZERO

func _begin_step() -> bool:
	if path.is_empty():
		var direction := _keyboard_direction()
		var destination := cell + direction
		if direction != Vector2i.ZERO and astar.region.has_point(destination) and not astar.is_point_solid(destination):
			pending = {}
			path.append(destination)
	while not path.is_empty():
		var destination: Vector2i = path.pop_front()
		if destination == cell: continue
		next_cell = destination
		if next_cell.x != cell.x:
			facing_left = next_cell.x < cell.x
		_face_actor(hero, facing_left)
		return true
	return false

func _advance_walk(distance: float) -> void:
	# The world owns locomotion, including its animation clock. Pauses, turns
	# and cell transitions must not restart the gait or animate sliding feet.
	walk_distance = fposmod(walk_distance + distance, WALK_CYCLE_DISTANCE)
	hero.animation = "walk"
	hero.pause()
	var phase := walk_distance / WALK_CYCLE_DISTANCE * hero.sprite_frames.get_frame_count("walk")
	hero.set_frame_and_progress(int(phase), fposmod(phase, 1.0))

func _idle_hero() -> void:
	walk_distance = 0.0
	if hero.animation != "idle": hero.play("idle")

func _face_actor(sprite: AnimatedSprite2D, left: bool) -> void:
	sprite.scale.x = 1.0 if left else -1.0
	if sprite.get_child_count() > 0:
		var tag: Label = sprite.get_child(0)
		tag.scale.x = sprite.scale.x
		tag.position.x = -65 * sprite.scale.x

func _enemy_cell(sprite: AnimatedSprite2D) -> Vector2i:
	return Vector2i(roundi((sprite.position.x - 8) / CELL), roundi((sprite.position.y - 8) / CELL))

func _update_patrols(delta: float) -> void:
	if not enabled: return
	for id in patrols:
		var state: Dictionary = patrols[id]
		var sprite: AnimatedSprite2D = enemy_nodes[id]
		if not pending.is_empty() and pending.kind == "enemy" and pending.data.id == id:
			sprite.play("idle")
			continue
		if state.wait > 0.0:
			state.wait -= delta
			sprite.play("idle")
			continue
		if state.next.x < 0 and state.path.is_empty():
			for attempt in PATROL_OFFSETS.size():
				var destination: Vector2i = state.home + PATROL_OFFSETS[int(state.waypoint)]
				state.waypoint = (int(state.waypoint) + 1) % PATROL_OFFSETS.size()
				if not astar.region.has_point(destination) or astar.is_point_solid(destination): continue
				var route: Array[Vector2i] = astar.get_id_path(state.cell, destination)
				var local_route := true
				for point in route:
					if maxi(absi(point.x - state.home.x), absi(point.y - state.home.y)) > 2: local_route = false
				if not local_route or route.size() <= 1: continue
				route.pop_front()
				state.path = route
				break
		if state.next.x < 0 and not state.path.is_empty(): state.next = state.path.pop_front()
		if state.next.x < 0:
			state.wait = 0.5
			continue
		var destination := cell_center(state.next)
		if destination.distance_to(hero.position) < 24.0:
			sprite.play("idle")
			continue
		if absf(destination.x - sprite.position.x) > 0.1: _face_actor(sprite, destination.x < sprite.position.x)
		sprite.play("walk")
		sprite.position = sprite.position.move_toward(destination, 28.0 * delta)
		if sprite.position.distance_to(destination) < 0.1:
			state.cell = state.next
			state.next = Vector2i(-1, -1)
			if state.path.is_empty():
				state.wait = 0.6
				sprite.play("idle")

func _save_position() -> void:
	Game.player.cell = [cell.x, cell.y]
	moved.emit()

func stop_moving() -> void:
	path.clear()
	pending = {}
	next_cell = Vector2i(-1, -1)
	hero.position = cell_center(cell)
	_idle_hero()
	_save_position()
