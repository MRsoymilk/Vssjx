extends Node
## Deterministic movement checks; optional real-renderer captures for all avatars.
var checks := 0
var failures := 0
var world: ShushanWorld
var viewport: SubViewport
var output := ""
var records: Array[Dictionary] = []
const START := Vector2i(16, 17)

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func reset_position() -> void:
	world.cell = START
	world.stop_moving()
	world.camera.position = world.hero.position
	world.camera.force_update_scroll()

func capture(name_value: String) -> void:
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(not image.is_empty(), "Real renderer supplies an image")
	if not image.is_empty():
		check(image.save_png(output.path_join(name_value + ".png")) == OK, "Save motion capture")

func walk_key(code: Key, direction: Vector2i, label: String, variant: int) -> void:
	reset_position()
	var start := world.hero.position
	var seen := {}
	var old_facing := world.hero.scale.x
	key(code, true)
	check(Input.is_physical_key_pressed(code), "Synthetic physical key is held")
	for i in 60:
		var before := world.hero.position
		world._process(1.0 / 60.0)
		check(world.hero.animation == "walk", "Held key never inserts idle at grid boundaries")
		check(absf(world.hero.position.distance_to(before) - ShushanWorld.WALK_SPEED / 60.0) < 0.001, "Continuous speed across grid boundaries")
		var facing := (1.0 if direction.x < 0 else -1.0) if direction.x != 0 else old_facing
		check(world.hero.scale.x == facing, "Native left-facing art follows movement, vertical motion preserves facing")
		check(world.hero.get_child(0).scale.x * world.hero.scale.x == 1.0, "Name stays readable when mirrored")
		seen[world.hero.frame] = true
		records.append({"variant": variant, "direction": label, "tick": i,
			"x": world.hero.position.x, "y": world.hero.position.y,
			"frame": world.hero.frame, "phase": world.hero.frame_progress,
			"facing": world.hero.scale.x, "animation": world.hero.animation})
		if i == 18:
			world.enabled = false
			var position_before_pause := world.hero.position
			var pose := Vector2(world.hero.frame, world.hero.frame_progress)
			world._process(0.5)
			check(world.hero.position == position_before_pause, "Paused world does not move")
			check(Vector2(world.hero.frame, world.hero.frame_progress) == pose, "Paused gait does not advance")
			world.enabled = true
		if i % 4 == 0 and direction.x != 0:
			await capture("avatar_%d_%s_%02d" % [variant, label, i])
	key(code, false)
	check(seen.size() == 6, "Held key reaches all six gait frames")
	check(world.hero.position.distance_to(start + Vector2(direction) * ShushanWorld.WALK_SPEED) < 0.001, "One second travels exactly 72 pixels")
	world._process(1.0)
	check(world.hero.animation == "idle" and world.next_cell.x < 0, "Releasing key finishes current cell and idles")
	check(world.hero.position == world.cell_center(START + direction * 5), "Release does not queue extra cells")
	await capture("avatar_%d_%s_stopped" % [variant, label])

func _run() -> void:
	output = OS.get_environment("SSJX_MOTION_PATH")
	if not output.is_empty() and DisplayServer.get_name() == "headless":
		push_error("Captures require a real renderer; run through tests/run_offscreen.py")
		get_tree().quit(1)
		return
	# Never load or write the player's save.
	Game.save_path = "user://motion_regression_save.json"
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 240)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	for variant in 6:
		Game.new_player("行走验证", variant / 2, 0, variant % 2)
		Game.player.cell = [START.x, START.y]
		world = ShushanWorld.new()
		viewport.add_child(world)
		world.set_process(false)
		await get_tree().process_frame
		check(world.hero.animation == "idle", "All avatars enter the world standing")
		await walk_key(KEY_D, Vector2i.RIGHT, "right", variant)
		await walk_key(KEY_A, Vector2i.LEFT, "left", variant)
		await walk_key(KEY_W, Vector2i.UP, "up", variant)
		await walk_key(KEY_S, Vector2i.DOWN, "down", variant)
		reset_position()
		var destination := START + Vector2i(4, 0)
		world.click(world.cell_center(destination) - world.camera.get_screen_center_position() + Vector2(viewport.size) / 2.0)
		check(not world.path.is_empty() and world.path.back() == destination, "Map click creates a route")
		for i in 90: world._process(1.0 / 60.0)
		check(world.cell == destination and world.hero.animation == "idle", "Click route arrives and returns to idle")
		for fps in [15, 30, 60, 120]:
			reset_position()
			for x in range(17, 25): world.path.append(Vector2i(x, START.y))
			for i in fps: world._process(1.0 / fps)
			check(world.hero.position.distance_to(world.cell_center(START) + Vector2(72, 0)) < 0.002, "Same speed at %d FPS" % fps)
			check(absf(world.walk_distance - 8.0) < 0.002, "Same gait phase at %d FPS" % fps)
		reset_position()
		world.path.assign([START, START + Vector2i.RIGHT, START, START + Vector2i.UP])
		world._process(0.5)
		check(world.hero.position.distance_to(world.cell_center(START) + Vector2(0, -4)) < 0.001, "Duplicate route cells and turns preserve remaining movement")
		check(absf(world.walk_distance - 4.0) < 0.001 and world.hero.animation == "walk", "Turns do not restart gait")
		world.stop_moving()
		check(world.hero.animation == "idle" and world.walk_distance == 0.0, "Explicit stop resets gait")
		reset_position()
		world.astar.set_point_solid(START + Vector2i.RIGHT, true)
		key(KEY_RIGHT, true)
		world._process(1.0)
		key(KEY_RIGHT, false)
		check(world.hero.position == world.cell_center(START) and world.hero.animation == "idle", "Blocked movement does not slide or animate")
		world.queue_free()
		await get_tree().process_frame
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("motion_trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(records))
	viewport.queue_free()
	await get_tree().process_frame
	print("MOTION REGRESSION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
