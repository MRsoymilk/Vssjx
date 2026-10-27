class_name ShushanWorld
extends Node2D

signal interaction(kind: String, data: Dictionary)
signal moved
const CELL := 16
const MAP_SIZE := 32
const WALK_SPEED := 72.0
const WALK_CYCLE_DISTANCE := 32.0 # One full left/right stride, in map pixels.
enum Ground { GRASS, DIRT, WATER, BRIDGE }
static var ENEMIES: Array = _enemy_definitions()

static func _enemy_definitions() -> Array:
	var enemies := SharedWorldMap.population().filter(func(value: Dictionary) -> bool: return value.kind != "npc")
	enemies.append_array(SharedWorldMap.population("ancient_ruins"))
	return enemies

var map_data: Dictionary
var zone := 0
var map_id := "qingyun_trail"
var ai_npcs: Dictionary = {}
var ai_markers: Dictionary = {}
var ai_station: Node2D
var enabled := true:
	set(value):
		enabled = value
		if not value and move_target != null: move_target.clear()
		if value and actors != null: _sync_enemies()
		if value: refresh_quest_marker()
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
var move_target: WorldMoveTarget
var quest_marker: NpcQuestMarker
var soul_markers: SoulMarkers
var day_night: WorldDayNight
var gathering_nodes:Dictionary={}
var npc_search := false

func _ready() -> void:
	zone = int(Game.player.zone)
	map_id = AIWorld.local_map_id()
	cell = Vector2i(Game.player.cell[0], Game.player.cell[1])
	_build_map()
	day_night = WorldDayNight.new()
	day_night.name = "DayNight"
	day_night.set_map(map_data)
	add_child(day_night)
	move_target = preload("res://scenes/world_move_target.tscn").instantiate()
	add_child(move_target)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	_add_scenery()
	portal_marker = Node2D.new()
	portal_marker.set_script(preload("res://scripts/portal.gd"))
	var gate: Dictionary = SharedWorldMap.exits(map_id)[0]
	portal_marker.set("gate",gate)
	portal_marker.position = cell_center(Vector2i(gate.cell[0], gate.cell[1]))
	actors.add_child(portal_marker)
	_name_tag(portal_marker, SharedWorldMap.exit_label(gate), Color("c2f7f4"))
	portal_marker.get_child(0).position.y = -24
	if not AIWorld.map_data(map_id).is_empty():
		for exit in SharedWorldMap.exits(map_id).slice(1):
			var node := Node2D.new()
			node.set_script(preload("res://scripts/portal.gd"))
			node.set("gate",exit)
			node.position=cell_center(Vector2i(exit.cell[0],exit.cell[1]))
			actors.add_child(node)
			_name_tag(node,SharedWorldMap.exit_label(exit),Color("c2f7f4"));node.get_child(0).position.y=-24
	var art: String = Game.appearance_key()
	hero = OriginalArt.actor(art)
	hero.position = cell_center(cell)
	actors.add_child(hero)
	_name_tag(hero, String(Game.player.name), Color("fff4c9"))
	hero.add_child(preload("res://scenes/actors/player_ring.tscn").instantiate())
	soul_markers=preload("res://scenes/actors/soul_markers.tscn").instantiate()
	actors.add_child(soul_markers)
	refresh_soul()
	if not AIWorld.map_data(map_id).is_empty():
		for definition in SharedWorldMap.population(map_id):
			if definition.kind != "npc": continue
			var npc := OriginalArt.actor(definition.art)
			npc.z_index = 10
			npc.position = cell_center(Vector2i(definition.cell[0], definition.cell[1]))
			actors.add_child(npc)
			_name_tag(npc, definition.name + " · AI", Color("ffe095"))
			if not String(definition.get("service_label","")).is_empty():
				_name_tag(npc,String(definition.service_label),Color("c2f7f4"))
				npc.get_child(1).position.y=-92
			ai_npcs[definition.id] = npc
			var marker := preload("res://scenes/actors/npc_quest_marker.tscn").instantiate()
			marker.position.y-=22
			npc.add_child(marker);ai_markers[definition.id]=marker
			if String(definition.id).ends_with("_guide"):quest_marker=marker
	else:
		ai_station = Node2D.new()
		ai_station.set_script(preload("res://scripts/portal.gd"))
		ai_station.position = cell_center(AIWorld.station(map_id))
		actors.add_child(ai_station)
		_name_tag(ai_station, "灵空台 · AI生成", Color("c2f7f4"));ai_station.get_child(0).position.y=-24
	if zone == 0 and AIWorld.map_data(map_id).is_empty():
		var definition: Dictionary = SharedWorldMap.population()[0]
		var npc := OriginalArt.actor(definition.art)
		npc.z_index = 10
		npc.position = cell_center(Vector2i(definition.cell[0], definition.cell[1]))
		actors.add_child(npc)
		_name_tag(npc, String(definition.name), Color("ffe095"))
		quest_marker = preload("res://scenes/actors/npc_quest_marker.tscn").instantiate()
		npc.add_child(quest_marker)
		refresh_quest_marker()
	_sync_enemies()
	for data in GatheringRules.nodes_for(map_id):
		var resource:=GatheringNode.new();resource.local_mode=true;actors.add_child(resource);resource.display(data,int(Time.get_unix_time_from_system()*1000));gathering_nodes[data.id]=resource
	camera = Camera2D.new()
	camera.position = hero.position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 512
	camera.limit_bottom = 512
	add_child(camera)
	if astar.is_point_solid(cell):
		cell = Vector2i(map_data.spawn[0],map_data.spawn[1])
		hero.position = cell_center(cell)
		_save_position()
	queue_redraw()

func refresh_appearance() -> void:
	if not is_instance_valid(hero): return
	OriginalArt.apply_appearance(hero,Game.appearance_key())
	refresh_soul()

func refresh_soul() -> void:
	if is_instance_valid(hero):hero.modulate=Color(0.8,0.9,1.0,0.5) if Game.is_soul() else Color.WHITE
	if is_instance_valid(soul_markers):soul_markers.display(map_id,Game.player.corpse if Game.is_soul() else {})

func refresh_quest_marker() -> void:
	if not AIWorld.map_data(map_id).is_empty():
		for id in ai_markers:
			var value := AIWorld.npc_marker(id,AIWorld.progress(),int(Game.player.level))
			ai_markers[id].set_stage(value.stage);ai_markers[id].tooltip_text=value.hint
		return
	if is_instance_valid(quest_marker):
		var unjoined:bool=int(Game.player.get("school",SchoolRules.UNJOINED))==SchoolRules.UNJOINED
		quest_marker.set_stage(0 if unjoined else int(Game.player.get("quest",-1)))
		if unjoined:quest_marker.tooltip_text="与清微道人交谈，选择门派。"

func cell_center(value: Vector2i) -> Vector2:
	return Vector2(value * CELL) + Vector2(8, 8)

func _build_map() -> void:
	terrain = TileMapLayer.new()
	add_child(terrain)
	map_data = SharedWorldMap.load_data(map_id)
	SharedWorldMap.build(terrain, astar, map_data)

func _ruins_data() -> Dictionary:
	return SharedWorldMap.load_data("ancient_ruins")

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
	SharedWorldMap.add_scenery(actors, map_data)

func _name_tag(sprite: Node2D, value: String, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position.y=-74
	preload("res://scripts/world_nameplate.gd").apply(label,color)
	sprite.add_child(label)

func _sync_enemies() -> void:
	var now := Time.get_unix_time_from_system()
	for enemy in _map_enemies():
		var enemy_zone := zone if not AIWorld.map_data(map_id).is_empty() else (1 if enemy.id in ["guardian", "boss"] else 0)
		if enemy_zone != zone or not Game.enemy_available(String(enemy.id), now):
			if not enemy_nodes.has(enemy.id): continue
			var removed: AnimatedSprite2D = enemy_nodes[enemy.id]
			actors.remove_child(removed)
			removed.queue_free()
			enemy_nodes.erase(enemy.id)
			patrols.erase(enemy.id)
			if pending.get("kind") == "enemy" and pending.data.id == enemy.id:
				pending = {}
				path.clear()
				move_target.clear()
			continue
		if enemy_nodes.has(enemy.id): continue
		var sprite := OriginalArt.actor(String(enemy.art))
		var home := Vector2i(enemy.cell[0], enemy.cell[1])
		sprite.position = cell_center(home)
		actors.add_child(sprite)
		enemy_nodes[enemy.id] = sprite
		_name_tag(sprite, "%d级 %s" % [int(enemy.level), String(enemy.name)], Color("ff3030"))
		if not enabled: sprite.pause()
		if enemy.kind == "wolf":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			patrols[enemy.id] = {"home": home, "cell": home, "next": Vector2i(-1, -1),
				"path": [], "rng": rng, "wait": rng.randf_range(0.2, 2.5)}

func available_enemies() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var now := Time.get_unix_time_from_system()
	for enemy in _map_enemies():
		var enemy_zone := zone if not AIWorld.map_data(map_id).is_empty() else (1 if enemy.id in ["guardian", "boss"] else 0)
		if enemy_zone == zone and enemy_nodes.has(enemy.id) and Game.enemy_available(String(enemy.id), now):
			var current: Dictionary = enemy.duplicate(true)
			var spot := _enemy_cell(enemy_nodes[enemy.id])
			current.cell = [spot.x, spot.y]
			result.append(current)
	return result

func _map_enemies() -> Array:
	return SharedWorldMap.population(map_id).filter(func(r: Dictionary) -> bool: return r.kind != "npc") if not AIWorld.map_data(map_id).is_empty() else ENEMIES

func _ai_targets() -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for id in ai_npcs:
		var r := AIWorld.resident(id)
		values.append({"kind": "ai_npc", "cell": Vector2i(r.cell[0], r.cell[1]), "data": r})
	for gate in SharedWorldMap.exits(map_id):
		if gate.get("legacy",false): continue
		values.append({"kind":"map_exit","cell":Vector2i(gate.cell[0],gate.cell[1]),"data":gate})
	return values

func travel(destination: String) -> void:
	_walk_to({"kind": "ai_travel", "cell": AIWorld.station(map_id), "data": {"target": destination}})

func approach_ai_target(id: String) -> void:
	var r := AIWorld.resident(id)
	if not r.is_empty(): _walk_to({"kind": "ai_npc" if r.kind == "npc" else "enemy", "cell": Vector2i(r.cell[0], r.cell[1]), "data": r})

func npc_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for id in ai_npcs:
		if not is_instance_valid(ai_npcs[id]) or not ai_npcs[id].visible: continue
		var resident := AIWorld.resident(id).duplicate(true)
		if resident.is_empty(): continue
		var point := Vector2i(floori(ai_npcs[id].position.x/CELL), floori(ai_npcs[id].position.y/CELL))
		resident.cell = [point.x, point.y]
		targets.append({"kind":"ai_npc", "cell":point, "data":resident})
	if map_id == "qingyun_trail" and is_instance_valid(quest_marker):
		var resident: Dictionary = SharedWorldMap.population(map_id)[0].duplicate(true)
		targets.append({"kind":"npc", "cell":Vector2i(resident.cell[0], resident.cell[1]), "data":resident})
	return targets

func find_npc(id: String) -> bool:
	if not enabled or Game.is_soul(): return false
	for target in npc_targets():
		if target.data.id != id: continue
		var origin := next_cell if next_cell.x >= 0 else cell
		var route := NpcFinder.route(astar, origin, target.cell, SharedWorldMap.exits(map_id))
		if route.is_empty(): return false
		pending = target; npc_search = true
		path = route; path.pop_front()
		if next_cell.x < 0 and absi(cell.x-target.cell.x)+absi(cell.y-target.cell.y) <= 2:
			_interact_pending()
		elif not path.is_empty(): move_target.set_destination(path[-1])
		return true
	return false

func click(local: Vector2) -> void:
	if not enabled: return
	npc_search = false
	var world_point := camera.get_screen_center_position() + local - get_viewport_rect().size / 2.0
	var target := Vector2i(floor(world_point.x / CELL), floor(world_point.y / CELL))
	if not astar.region.has_point(target): return
	var found := target_at_pixel(world_point)
	if found.is_empty():
		pending = {}
		path = _route_to(target)
		if not path.is_empty() or target == next_cell:
			move_target.set_destination(target)
		else: move_target.clear()
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
	if Game.is_soul():return soul_markers.target() if soul_markers.hit(point) else {}
	for target in _ai_targets():
		if target.kind=="map_exit":
			if Rect2(cell_center(target.cell)-Vector2(8,8),Vector2(16,16)).has_point(point):return target
			continue
		if WorldSpriteHit.hit(ai_npcs.get(target.data.id), to_global(point)): return target
	if zone == 0 and AIWorld.map_data(map_id).is_empty():
		var npc_cell := Vector2i(10, 13)
		if WorldSpriteHit.hit(quest_marker.get_parent() as AnimatedSprite2D, to_global(point)):
			return {"kind": "npc", "cell": npc_cell, "data": {}}
	for enemy in available_enemies():
		var sprite: AnimatedSprite2D = enemy_nodes.get(enemy.id)
		if WorldSpriteHit.hit(sprite, to_global(point)):
			return {"kind": "enemy", "cell": _enemy_cell(sprite), "data": enemy}
	for resource in gathering_nodes.values():
		if resource.hit(point):return {"kind":"gather","cell":Vector2i(resource.data.cell[0],resource.data.cell[1]),"data":resource.data}
	return {}

func target_at(target: Vector2i) -> Dictionary:
	if Game.is_soul():
		var corpse_target:=soul_markers.target()
		return corpse_target if not corpse_target.is_empty() and corpse_target.cell==target else {}
	for value in _ai_targets():
		if value.kind=="map_exit":
			if target==value.cell:return value
			continue
		if target == value.cell: return value
	if zone == 0 and AIWorld.map_data(map_id).is_empty() and target == Vector2i(10, 13):
		return {"kind": "npc", "cell": Vector2i(10, 13), "data": {}}
	var portal := Vector2i(28, 16) if zone == 0 else Vector2i(3, 16)
	if AIWorld.map_data(map_id).is_empty() and target == portal:
		return {"kind": "portal", "cell": portal, "data": {}}
	for enemy in available_enemies():
		var spot := _enemy_cell(enemy_nodes[enemy.id]) if enemy_nodes.has(enemy.id) else Vector2i(enemy.cell[0], enemy.cell[1])
		if target == spot:
			return {"kind": "enemy", "cell": spot, "data": enemy}
	for resource in gathering_nodes.values():
		if target==Vector2i(resource.data.cell[0],resource.data.cell[1]):return {"kind":"gather","cell":target,"data":resource.data}
	return {}

func _walk_to(target: Dictionary) -> void:
	npc_search = false
	if Game.is_soul() and target.get("kind")!="corpse":return
	if target.kind == "enemy" and enemy_nodes.has(target.data.id):
		target = target.duplicate()
		target.cell = _enemy_cell(enemy_nodes[target.data.id])
	if target.kind=="map_exit":
		pending={};path=_route_to(target.cell)
		if not path.is_empty():move_target.set_destination(target.cell)
		elif cell==target.cell:_enter_exit(target.data)
		return
	pending = target
	if target.kind == "enemy" and enemy_nodes.has(target.data.id):
		enemy_nodes[target.data.id].play("idle")
	if cell.distance_to(target.cell) <= (1.0 if target.kind=="gather" else 2.0) and next_cell.x < 0:
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
	if not path.is_empty(): move_target.set_destination(path[-1])
	else: move_target.clear()

func interact_nearest() -> void:
	if not enabled: return
	if Game.is_soul():
		var target:=soul_markers.target()
		if not target.is_empty() and cell.distance_to(target.cell)<3.5:_walk_to(target)
		else:interaction.emit("hint",{"text":SoulRules.hint(Game.player.corpse)})
		return
	var nearest: Dictionary = {}
	var distance := 3.5
	var targets: Array[Dictionary] = []
	targets.append_array(_ai_targets())
	if zone == 0 and AIWorld.map_data(map_id).is_empty(): targets.append({"kind": "npc", "cell": Vector2i(10, 13), "data": {}})
	if AIWorld.map_data(map_id).is_empty(): targets.append({"kind": "portal", "cell": Vector2i(28, 16) if zone == 0 else Vector2i(3, 16), "data": {}})
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
	npc_search = false
	move_target.clear()
	var target := pending
	pending = {}
	path.clear()
	if not target.is_empty(): interaction.emit(target.kind, target.data)

func _enter_exit(gate: Dictionary) -> void:
	path.clear();pending={};enabled=false
	interaction.emit("map_exit",gate)

func _process(delta: float) -> void:
	refresh_quest_marker()
	if not enabled or hero == null: return
	if OS.has_feature("web") and (not Platform.context.lifecycle.focused or Platform.context.lifecycle.suspended): return
	_sync_enemies()
	if _keyboard_direction() != Vector2i.ZERO:
		npc_search = false
		move_target.clear()
		path.clear()
		pending = {}
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
			var exit := SharedWorldMap.exit_at(map_id,cell)
			if not exit.is_empty() and not Game.is_soul() and not npc_search:
				_idle_hero();_enter_exit(exit);return
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
	if get_tree().root.gui_get_focus_owner() is LineEdit: return Vector2i.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): return Vector2i.LEFT
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): return Vector2i.RIGHT
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): return Vector2i.UP
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): return Vector2i.DOWN
	return Vector2i.ZERO

func _begin_step() -> bool:
	var direction := _keyboard_direction()
	if direction != Vector2i.ZERO:
		# A held direction takes over a click route at the next cell boundary.
		path.clear()
		pending = {}
		var destination := cell + direction
		if astar.region.has_point(destination) and not astar.is_point_solid(destination):
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
	move_target.clear()
	walk_distance = 0.0
	if hero.animation != "idle" or not hero.is_playing(): hero.play("idle")

func _face_actor(sprite: AnimatedSprite2D, left: bool) -> void:
	sprite.scale.x = 1.0 if left else -1.0
	if sprite.get_child_count() > 0:
		var tag: Label = sprite.get_child(0)
		tag.scale.x = sprite.scale.x
		tag.position.x = -tag.size.x*0.5*sprite.scale.x

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
			var targets: Array[Vector2i] = []
			for y in range(-2, 3):
				for x in range(-2, 3): targets.append(state.home + Vector2i(x, y))
			# Shuffle with this monster's stream; global RNG calls cannot synchronize patrols.
			for i in range(targets.size() - 1, 0, -1):
				var other: int = state.rng.randi_range(0, i)
				var swap := targets[i]
				targets[i] = targets[other]
				targets[other] = swap
			for destination in targets:
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
			state.wait = state.rng.randf_range(0.5, 2.0)
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
				state.wait = state.rng.randf_range(0.5, 2.0)
				sprite.play("idle")

func _save_position() -> void:
	Game.player.cell = [cell.x, cell.y]
	moved.emit()

func stop_moving() -> void:
	pause_moving()
	next_cell = Vector2i(-1, -1)
	hero.position = cell_center(cell)

func pause_moving() -> void:
	npc_search = false
	# UI pauses keep the rendered position and unfinished segment. Resuming may
	# finish that one segment, but must not restore an old click/interaction path.
	path.clear()
	move_target.clear()
	pending = {}
	_idle_hero()
	_save_position()
