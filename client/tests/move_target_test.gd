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
	output = OS.get_environment("SSJX_MOVE_TARGET_CAPTURE_PATH") if DisplayServer.get_name() != "headless" else ""
	await capture("local_move_target")
	image.queue_free()
	viewport.queue_free()
	await get_tree().process_frame
	await online_marker()
	Game.player = old_player
	Game.save_path = old_path
	print("MOVE TARGET: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func online_click(view: OnlineWorldView, cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = Vector2(cell * 16) + Vector2(8,8) - view.camera.get_screen_center_position() + Vector2(view.viewport.size)/2.0
	view._map_input(event)

func online_marker() -> void:
	OnlineAccount.pending_pve = {}
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.set_process(false)
	view.network.world_ready = true
	view.network.entities = {SELF:entity(SELF,1,"落点提示",1,0,[16,17])}
	view.network.changed.emit(view.network.entities)
	view.camera.position = view.actors[SELF].root.position
	view.camera.force_update_scroll()
	var marker := view.move_target
	check(not marker.visible and marker.scene_file_path == "res://scenes/world_move_target.tscn", "Online view instances the same original marker scene")
	online_click(view, Vector2i(20,17))
	check(marker.visible and marker.destination == Vector2i(20,17) and view.network._pending_motion.get("target") == [20,17], "Online map click displays destination without changing move command")
	online_click(view, Vector2i(22,17))
	check(marker.destination == Vector2i(22,17) and view.network._pending_motion.get("target") == [22,17], "Rapid online retarget replaces the same marker with newest click")
	online_click(view, Vector2i(20,17))
	view._update_move_target(2.0)
	check(marker.visible, "Unsent rate-limited click is not erased by previous idle snapshot")
	view.network._pending_motion = {}
	view.network._input_seq = 2
	view._update_move_target(2.0)
	check(marker.visible, "Old unacknowledged snapshot cannot erase latest click marker")
	view.network.entities[SELF].last_input_seq = "2"
	view._update_move_target(.05)
	check(marker.visible, "Movement acknowledgement may precede first moving tick")
	view.network.entities[SELF].next_cell = [17,17]
	view.network.entities[SELF].segment_progress = 400
	view.network.changed.emit(view.network.entities)
	view._process(.05)
	check(marker.visible and marker.position == Vector2(328,280), "Online marker stays fixed while rendered character moves")
	view.network.entities[SELF].cell = [20,17]
	view.network.entities[SELF].next_cell = null
	view.network.entities[SELF].segment_progress = 0
	view.network.changed.emit(view.network.entities)
	view._update_move_target(.05)
	check(marker.visible, "Final server snapshot waits for buffered character animation to arrive")
	for i in 20: view._process(.1)
	check(not marker.visible and view.actors[SELF].root.position == Vector2(328,280), "Rendered online arrival clears marker")
	view._mark_destination(Vector2i(22,17))
	view.network.stop_moving()
	check(not marker.visible, "All online stop paths immediately clear marker")
	view._mark_destination(Vector2i(22,17))
	view._scene_action("menu")
	check(not marker.visible, "Opening online menu cancels destination hint")
	view.menu.hide()
	view._mark_destination(Vector2i(22,17))
	view.network.pve.state = {"battle":{"outcome":"active"}}
	view._update_move_target(.1)
	check(not marker.visible, "Online battle cannot retain world destination hint")
	view.network.pve.state = {}
	view._mark_destination(Vector2i(22,17))
	view.network.world_ready = false
	view.network.status_changed.emit("连接已断开")
	check(not marker.visible, "Disconnected world clears old destination before reconnect")
	view.network.world_ready = true
	view._mark_destination(Vector2i(22,17))
	view.network._pending_motion = {}
	view.network.entities[SELF].last_input_seq = str(view.network._input_seq)
	view._update_move_target(1.1)
	check(not marker.visible, "Acknowledged rejected or cancelled movement cannot leave a stale pin")
	view._mark_destination(Vector2i(22,17))
	var key := InputEventKey.new(); key.physical_keycode = KEY_A; key.pressed = true
	Input.parse_input_event(key); Input.flush_buffered_events()
	view._process(.01)
	check(not marker.visible, "Online keyboard takeover clears click destination")
	key = InputEventKey.new(); key.physical_keycode = KEY_A; key.pressed = false
	Input.parse_input_event(key); Input.flush_buffered_events()
	view.network.entities[PEER] = entity(PEER,2,"同图玩家",0,1,[22,19])
	view.network.changed.emit(view.network.entities)
	check(not marker.visible, "Other players do not create local destination markers")
	view._mark_destination(Vector2i(22,17))
	view.camera.position = view.actors[SELF].root.position
	await capture("online_move_target")
	app.queue_free()
	await get_tree().process_frame
