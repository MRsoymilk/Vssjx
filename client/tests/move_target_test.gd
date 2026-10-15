extends "res://tests/shared_interface_test.gd"

func click_cell(world: ShushanWorld, target: Vector2i) -> void:
	world.click(world.cell_center(target) - world.camera.get_screen_center_position() + Vector2(world.get_viewport().size) / 2.0)

func _run() -> void:
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://move_target_%d.json" % OS.get_process_id()
	Game.new_player("落点提示", 1, 0)
	Game.player.cell = [16,17]
	Game.player.defeated = ["wolf_a", "wolf_b", "wolf_c", "spirit", "guardian", "boss"]
	var viewport: SubViewport = load("res://scenes/ui/world_viewport.tscn").instantiate()
	add_child(viewport)
	var world := ShushanWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	world.camera.force_update_scroll()
	var marker := world.move_target
	check(not marker.visible and marker.scene_file_path == "res://scenes/world_move_target.tscn", "Movement marker is a hidden authored scene")
	check(marker.get_node("Pin").texture.resource_path.ends_with("scene_target.png") and marker.get_node("Top").texture.resource_path.ends_with("select_0.png"), "Reference pin and ring use original game resources")
	click_cell(world, Vector2i(20,17))
	check(marker.visible and marker.destination == Vector2i(20,17) and marker.position == world.cell_center(Vector2i(20,17)), "Click marks actual destination in world coordinates")
	world._process(.1)
	check(marker.visible and marker.destination == Vector2i(20,17), "Marker stays on destination while character walks")
	click_cell(world, Vector2i(18,17))
	check(marker.destination == Vector2i(18,17), "Retarget replaces previous marker without leaving a duplicate")
	world.camera.force_update_scroll()
	for i in 60: world._process(1.0/60.0)
	check(world.cell == Vector2i(18,17) and not marker.visible, "Arrival clears movement marker")
	click_cell(world, Vector2i(20,17))
	world.pause_moving()
	check(not marker.visible and world.path.is_empty(), "Opening UI or pausing movement clears marker")
	click_cell(world, Vector2i(20,17))
	world.enabled = false
	check(not marker.visible, "Battle or disabled world cannot retain marker")
	world.enabled = true
	click_cell(world, Vector2i(20,17))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_A
	key.pressed = true
	Input.parse_input_event(key); Input.flush_buffered_events()
	world._process(.01)
	check(not marker.visible, "Keyboard takeover clears click destination")
	key = InputEventKey.new(); key.physical_keycode = KEY_A; key.pressed = false
	Input.parse_input_event(key); Input.flush_buffered_events()
	world.stop_moving()
	world.camera.force_update_scroll()
	click_cell(world, world.cell)
	check(not marker.visible, "Clicking current standing cell leaves no stale marker")
	click_cell(world, Vector2i(20,17))
	var blocked := Vector2i(-1,-1)
	for y in 32:
		for x in 32:
			if world.astar.is_point_solid(Vector2i(x,y)):
				blocked = Vector2i(x,y)
				break
		if blocked.x >= 0: break
	click_cell(world, blocked)
	check(not marker.visible, "Blocked destination cannot leave previous marker")
	click_cell(world, Vector2i(20,17))
	var image := TextureRect.new()
	image.position = Vector2(0,28)
	image.size = Vector2(320,375)
	image.texture = viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(image)
	output = OS.get_environment("SSJX_MOVE_TARGET_CAPTURE_PATH")
	await capture("local_move_target")
	image.queue_free()
	viewport.queue_free()
	await get_tree().process_frame
	Game.player = old_player
	Game.save_path = old_path
	print("MOVE TARGET: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)
