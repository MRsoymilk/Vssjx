extends Node

var checks := 0
var failures := 0
var world: ShushanWorld
var viewport: SubViewport
var interactions := 0
const START := Vector2i(16, 17)

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func reset_position() -> void:
	world.cell = START
	world.stop_moving()
	world.camera.position = world.hero.position
	world.camera.force_update_scroll()

func click_cell(target: Vector2i) -> void:
	world.click(world.cell_center(target) - world.camera.get_screen_center_position() + Vector2(viewport.size) / 2.0)

func route_is_connected() -> bool:
	var origin := world.next_cell if world.next_cell.x >= 0 else world.cell
	if world.next_cell.x >= 0 and absi(origin.x - world.cell.x) + absi(origin.y - world.cell.y) != 1: return false
	for point in world.path:
		if absi(point.x - origin.x) + absi(point.y - origin.y) != 1 or world.astar.is_point_solid(point): return false
		origin = point
	return true

func repeated_clicks(direction: Vector2i, offset: Vector2, fps: int, interval: int) -> void:
	reset_position()
	var screen_point := Vector2(viewport.size) / 2.0 + offset * Vector2(direction)
	var reversed := false
	var connected := true
	var speed_ok := true
	for tick in int(fps * 1.25):
		if tick % interval == 0: world.click(screen_point)
		connected = connected and route_is_connected()
		var before := world.hero.position
		world._process(1.0 / fps)
		world.camera.force_update_scroll()
		var travel := world.hero.position - before
		if travel.x * direction.x < -0.001 or travel.y * direction.y < -0.001: reversed = true
		if travel.length() > ShushanWorld.WALK_SPEED / fps + 0.001: speed_ok = false
	var sample := "%s %s %d FPS / every %d frames" % [direction, offset, fps, interval]
	check(not reversed, "Repeated screen clicks never walk backward: " + sample)
	check(connected, "Replanning preserves adjacent passable grid steps: " + sample)
	check(speed_ok, "Repeated clicks never teleport the character: " + sample)

func _run() -> void:
	Game.save_path = "user://click_motion_regression_save.json"
	Game.new_player("连续点击验证", 0, 0)
	Game.player.cell = [START.x, START.y]
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 375)
	add_child(viewport)
	world = ShushanWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	world.interaction.connect(func(_kind: String, _data: Dictionary) -> void: interactions += 1)
	await get_tree().process_frame
	# No NPC, portal or patrol should turn a movement test into an interaction.
	Game.player.defeated = ["wolf_a", "wolf_b", "wolf_c", "spirit", "guardian", "boss"]
	world.zone = 1
	for direction in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		for offset in [Vector2(24, 40), Vector2(40, 24), Vector2(64, 64), Vector2(96, 48)]:
			for fps in [15, 30, 60, 120]:
				for interval in [1, 2, 4, 8]: repeated_clicks(direction, offset, fps, interval)
	# Retargeting preserves the current segment and applies the new route after it.
	reset_position()
	click_cell(START + Vector2i(4, 0))
	world._process(0.1)
	var active_cell := world.next_cell
	var before := world.hero.position
	var destination := START + Vector2i(-2, -2)
	click_cell(destination)
	check(world.next_cell == active_cell and world.hero.position == before, "Changing direction mid-step preserves position and active destination")
	check(route_is_connected(), "A deliberate reverse command starts its route at the active step's endpoint")
	for tick in 120: world._process(1.0 / 60.0)
	check(world.cell == destination and world.hero.animation == "idle", "A changed click destination is still honored")
	# Clicking the active step's endpoint must stop there, without a stale route.
	reset_position()
	click_cell(START + Vector2i(4, 0))
	world._process(0.1)
	active_cell = world.next_cell
	for tick in 30:
		click_cell(active_cell)
		world._process(1.0 / 60.0)
	check(world.cell == active_cell and world.next_cell.x < 0 and world.path.is_empty(), "Repeated clicks on the active endpoint stop without backtracking")
	# Repeatedly requesting a blocked destination finishes the active segment.
	reset_position()
	click_cell(START + Vector2i(4, 0))
	world._process(0.1)
	active_cell = world.next_cell
	click_cell(Vector2i(0, 0))
	world._process(1.0)
	check(world.cell == active_cell and world.hero.animation == "idle", "An unreachable click does not reverse or teleport an active step")
	# A legitimate obstacle detour remains connected while clicks replace it.
	reset_position()
	world.astar.set_point_solid(START + Vector2i.RIGHT, true)
	destination = START + Vector2i(4, 0)
	var connected := true
	for tick in 180:
		click_cell(destination)
		connected = connected and route_is_connected()
		world._process(1.0 / 60.0)
	check(connected and world.cell == destination, "Repeated clicks preserve obstacle detours and reach the destination")
	world.astar.set_point_solid(START + Vector2i.RIGHT, false)
	# NPC/enemy/portal approaches use the same endpoint as ordinary map clicks.
	reset_position()
	click_cell(START + Vector2i(4, 0))
	world._process(0.1)
	active_cell = world.next_cell
	before = world.hero.position
	var target := {"kind": "npc", "cell": START + Vector2i(4, 2), "data": {}}
	world._walk_to(target)
	check(world.next_cell == active_cell and world.hero.position == before and route_is_connected(), "Interaction retargeting also preserves the current step")
	connected = true
	for tick in 180:
		if interactions > 0: break
		world._walk_to(target)
		connected = connected and route_is_connected()
		world._process(1.0 / 60.0)
	check(connected and interactions == 1 and world.pending.is_empty() and world.path.is_empty(), "Repeated interaction requests arrive and emit exactly one interaction")
	viewport.queue_free()
	await get_tree().process_frame
	print("CLICK MOTION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
