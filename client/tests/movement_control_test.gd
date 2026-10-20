extends "res://tests/shared_interface_test.gd"
## Regressions for concrete route, control, pause and online rendering failures.
const START := Vector2i(16, 17)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func turns(route: Array[Vector2i], origin: Vector2i) -> int:
	var count := 0
	var previous := Vector2i.ZERO
	for cell in route:
		var direction := cell - origin
		if previous != Vector2i.ZERO and previous != direction: count += 1
		previous = direction
		origin = cell
	return count

func sample(cell: Vector2i, next: Variant, progress: int) -> Dictionary:
	var value := entity(SELF, 1, "昆仑客", 1, 0, [cell.x, cell.y])
	value.next_cell = null if next == null else [next.x, next.y]
	value.segment_progress = progress
	return value

func publish(view: OnlineWorldView, value: Dictionary) -> void:
	view.network.entities = {SELF: value}
	view.network.changed.emit(view.network.entities)

func packet(socket: WebSocketPeer, remote: WebSocketPeer) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		socket.poll()
		remote.poll()
		if remote.get_available_packet_count() > 0: return JSON.parse_string(remote.get_packet().get_string_from_utf8())
		await get_tree().process_frame
	return {}

func socket_intents() -> void:
	var listener := TCPServer.new()
	check(listener.listen(0, "127.0.0.1") == OK, "Create isolated loopback movement socket")
	var socket := WebSocketPeer.new()
	check(socket.connect_to_url("ws://127.0.0.1:%d" % listener.get_local_port()) == OK, "Connect real WebSocket movement peer")
	var deadline := Time.get_ticks_msec() + 2000
	while not listener.is_connection_available() and Time.get_ticks_msec() < deadline:
		socket.poll()
		await get_tree().process_frame
	if not listener.is_connection_available(): check(false, "Loopback accepts connection"); listener.stop(); return
	var remote := WebSocketPeer.new()
	check(remote.accept_stream(listener.take_connection()) == OK, "Accept real movement WebSocket")
	while socket.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < deadline:
		socket.poll()
		remote.poll()
		await get_tree().process_frame
	check(socket.get_ready_state() == WebSocketPeer.STATE_OPEN, "Movement fixture completes WebSocket upgrade")
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN: listener.stop(); return
	var client := OnlineWorldClient.new()
	add_child(client)
	client.set_process(false)
	client.socket = socket
	client.world_ready = true
	client.character_id=SELF
	client.entities={SELF:{"last_input_seq":"0"}}
	client.move_to(Vector2i(18, 17))
	var first := await packet(socket, remote)
	check(first.get("type") == "world.move_to" and first.get("target") == [18.0, 17.0], "First target is sent through the actual socket")
	client.move_to(Vector2i(19, 17))
	client.move_to(Vector2i(20, 17))
	check(client._pending_motion.get("target") == [20, 17], "Rapid retarget keeps only the newest unsent click")
	await get_tree().create_timer(0.12).timeout
	client._flush_motion()
	check(client._input_seq==1 and client._pending_motion.get("target")==[20,17],"Delayed authority coalesces targets without adding in-flight movement packets")
	client.entities[SELF].last_input_seq="1"
	client._flush_motion()
	var last := await packet(socket, remote)
	check(last.get("target") == [20.0, 17.0] and last.get("input_seq") == "2", "Newest target is transmitted after the rate window instead of discarded")
	client.stop_moving()
	check(client._pending_motion.get("type") == "world.stop", "A quick release retains its stop command")
	await get_tree().create_timer(0.12).timeout
	client.entities[SELF].last_input_seq="2"
	client._flush_motion()
	var stop := await packet(socket, remote)
	check(stop.get("type") == "world.stop" and stop.get("input_seq") == "3", "Stop is delivered once when the rate window opens")
	client._pending_motion={"type":"world.move_to","target":[21,17]}
	client._receive({"type":"error","code":"BATTLE_ACTIVE"},PackedByteArray())
	check(client._pending_motion.is_empty() and client._motion_waiting==0,"Battle fencing discards queued movement and releases only its local acknowledgement gate")
	client._receive({"type":"error","code":"RATE_LIMITED"},PackedByteArray())
	check(client._motion_retry_at>Time.get_ticks_msec(),"Rate rejection imposes a monotonic backoff instead of immediate resubmission")
	client.move_to(Vector2i(21, 17))
	client._failed("DISCONNECTED")
	check(client._pending_motion.is_empty(), "Disconnect discards old movement intent instead of replaying after reconnect")
	remote.close(-1)
	socket.close(-1)
	listener.stop()
	client.queue_free()
	await get_tree().process_frame

func _run() -> void:
	output = OS.get_environment("SSJX_CONTROL_CAPTURE_PATH")
	var old_player := Game.player.duplicate(true)
	var old_save := Game.save_path
	Game.save_path = "user://movement_control_%d.json" % OS.get_process_id()
	Game.new_player("行走修正", 1, 0)
	Game.player.cell = [START.x, START.y]
	var viewport: SubViewport = load("res://scenes/ui/world_viewport.tscn").instantiate()
	add_child(viewport)
	var world := ShushanWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	for direction in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var goal: Vector2i = START + direction * 3
		var route := world._route_to(goal)
		check(route.size() == 6 and turns(route, START) <= 1, "Open-ground shortest route has one turn instead of a zigzag: " + str(direction))
	world.path = world._route_to(START + Vector2i(7, 0))
	world._process(0.1)
	key(KEY_A, true)
	world._process(0.1)
	world._process(0.1)
	world._process(0.1)
	world._process(0.1)
	key(KEY_A, false)
	check(world.hero.position.x < world.cell_center(START).x and world.pending.is_empty(), "Left key takes over a rightward click route")
	world.cell = START
	world.stop_moving()
	world.path = world._route_to(START + Vector2i(7, 0))
	world._process(0.1)
	var held_position := world.hero.position
	var held_next := world.next_cell
	world.pause_moving()
	world.enabled = false
	world._process(1.0)
	check(world.hero.position == held_position and world.next_cell == held_next and world.path.is_empty(), "UI pause preserves sub-cell position without a backward snap")
	world.enabled = true
	for frame in 60: world._process(1.0 / 60.0)
	check(world.cell == held_next and world.hero.animation == "idle", "Resume finishes just the current segment and does not restore the old route")
	viewport.queue_free()
	await get_tree().process_frame
	OnlineAccount.characters = [{"id": SELF, "display_name": "昆仑客", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45}]
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = SELF
	add_child(view)
	view.network.set_process(false)
	view.set_process(false)
	view.network.world_ready = true
	publish(view, sample(START, null, 0))
	publish(view, sample(START, START + Vector2i.RIGHT, 900))
	view._process(0.05)
	publish(view, sample(START + Vector2i.RIGHT, START + Vector2i(1, 1), 400))
	view._process(0.05)
	check(is_equal_approx(view.actors[SELF].root.position.y, world_center(START).y), "Online rendering finishes the horizontal segment before turning vertically")
	for frame in 30: view._process(1.0 / 60.0)
	check(view.actors[SELF].root.position.is_equal_approx(world_center(START + Vector2i.RIGHT).lerp(world_center(START + Vector2i(1, 1)), 0.4)), "Online corner interpolation reaches the received authoritative sample")
	for fps in [15, 30, 60, 120]:
		view.actors[SELF].root.queue_free()
		view.actors.clear()
		publish(view, sample(START, null, 0))
		var idle_ticks := 0
		var fast_frames := 0
		for frame in fps * 2:
			var time: float = float(frame) / fps
			var sample_time := floorf(time * 10.0 + 0.000001) / 10.0
			var cells := sample_time * 72.0 / 16.0
			var origin := START + Vector2i(floori(cells), 0)
			publish(view, sample(origin, origin + Vector2i.RIGHT, roundi(fposmod(cells, 1.0) * 1000.0)))
			var previous: Vector2 = view.actors[SELF].root.position
			view._process(1.0 / fps)
			if view.actors[SELF].sprite.animation == "idle": idle_ticks += 1
			if view.actors[SELF].root.position.distance_to(previous) > 72.0 / fps + 0.02: fast_frames += 1
		check(idle_ticks == 0, "100ms online publications do not insert idle frames during a continuous walk at %d FPS" % fps)
		check(fast_frames == 0, "Normal online samples render at the authoritative speed at %d FPS" % fps)
		publish(view, sample(START + Vector2i(9, 0), null, 0))
		for frame in fps: view._process(1.0 / fps)
		check(view.actors[SELF].sprite.animation == "idle" and view.actors[SELF].sprite.is_playing(), "Authoritative stop eventually resumes animated idle at %d FPS" % fps)
	# A missing publication must recover around terrain instead of cutting it.
	view.actors[SELF].root.queue_free()
	view.actors.clear()
	publish(view, sample(Vector2i(12, 7), null, 0))
	publish(view, sample(Vector2i(15, 7), null, 0))
	var passable := true
	for frame in 180:
		view._process(1.0 / 60.0)
		var point: Vector2 = view.actors[SELF].root.position
		passable = passable and not view._motion_grid.is_point_solid(Vector2i(floori(point.x / 16.0), floori(point.y / 16.0)))
	check(passable and view.actors[SELF].root.position.is_equal_approx(world_center(Vector2i(15, 7))), "Publication-gap recovery follows passable grid cells around trees")
	view.camera.force_update_scroll()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = world_center(Vector2i(16, 7)) - view.camera.get_screen_center_position() + Vector2(view.viewport.size) / 2.0
	view._was_keyboard = true
	view._map_input(click)
	view._process(0.016)
	check(not view._was_keyboard and view.network._pending_motion.get("type") == "world.move_to", "A click after keyboard movement is not overwritten by a stale key-release stop")
	click = click.duplicate()
	click.position = world_center(Vector2i(13, 7)) - view.camera.get_screen_center_position() + Vector2(view.viewport.size) / 2.0
	view._map_input(click)
	check(view.network._pending_motion.get("type") == "world.stop", "Clicking blocked terrain cancels the previous online route")
	await capture("01_online_movement")
	view.queue_free()
	await get_tree().process_frame
	await socket_intents()
	check(not FileAccess.file_exists(Game.save_path), "Movement fixtures never write a player save")
	Game.save_path = old_save
	Game.player = old_player
	OnlineAccount.characters = []
	print("MOVEMENT CONTROL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func world_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * 16) + Vector2(8, 8)
