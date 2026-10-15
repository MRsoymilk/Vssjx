extends Node
var checks := 0
var failures := 0
var folder := ""
var role := ""
var view: OnlineWorldView
var seen_remote_motion := false
var seen_remote_leave := false
var previous_remote := Vector2.ZERO
var other_id := ""
var trace: Array = []

func _ready() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)
func mark(stage: String) -> void:
	var file := FileAccess.open(folder.path_join(role + "_" + stage), FileAccess.WRITE)
	file.store_string("ok")
	file.close()
func wait_until(predicate: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()
func capture(stage: String) -> void:
	if OS.get_environment("SSJX_WORLD_RENDER") != "1": return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(folder.path_join(role + "_" + stage + ".png")) == OK, "World screenshot saved")
func _process(_delta: float) -> void:
	if view == null or not is_instance_valid(view) or view.network == null or not view.network.world_ready: return
	if view.network.entities.has(other_id):
		var entity: Dictionary = view.network.entities[other_id]
		var point := Vector2(entity.cell[0], entity.cell[1])
		if previous_remote != Vector2.ZERO and point != previous_remote: seen_remote_motion = true
		previous_remote = point
	elif previous_remote != Vector2.ZERO: seen_remote_leave = true

func _run() -> void:
	folder = OS.get_environment("SSJX_WORLD_SYNC")
	role = OS.get_environment("SSJX_WORLD_ROLE")
	other_id = OS.get_environment("SSJX_WORLD_OTHER")
	if folder.is_empty() or role.is_empty(): get_tree().quit(1); return
	var old_path := Game.save_path
	Game.save_path = folder.path_join(role + "_offline.json")
	var sentinel := FileAccess.open(Game.save_path, FileAccess.WRITE)
	sentinel.store_string("offline-sentinel")
	sentinel.close()
	var before := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_TEST_SERVER_URL"), "world_ui_" + role, "world-test-password-1234")
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "Real account authenticated")
	OnlineAccount.list_characters()
	await OnlineAccount.completed
	check(OnlineAccount.characters.size() == 1, "Character loaded from database")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	app._online_characters()
	await OnlineAccount.completed
	var lobby := app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	check(not lobby.enter_button.disabled, "Lobby enables explicit online entry")
	lobby.enter_button.pressed.emit()
	view = app.ui.get_node("OnlineWorld") as OnlineWorldView
	check(await wait_until(func() -> bool: return view.network.world_ready and view.actors.size() == 2), "Both independent clients share the map")
	if not view.network.world_ready: get_tree().quit(1); return
	check(app.mode == "online_world" and app.world == null, "Online entry never runs the offline world simulation")
	check(view.network.entities.has(other_id), "Peer appears with server identity")
	var own_id := OnlineAccount.characters[0].id as String
	var game := view.network.game_session
	var epoch := view.network.connection_epoch
	await capture("together")
	mark("seen")
	check(await wait_until(func() -> bool: return FileAccess.file_exists(folder.path_join("go"))), "Coordinator starts movement only after mutual visibility")
	check(await wait_until(func() -> bool: return view.network.chat.connected and view.network.chat.enabled), "Authenticated public channel starts independently of map snapshots")
	view.chat_button.pressed.emit()
	await get_tree().create_timer(0.15).timeout
	check(view.chat_panel.visible and view.chat_input.has_focus(), "Public chat panel accepts keyboard focus")
	var literal := "[b]%s WASD[/b] 大家好" % role
	view.chat_input.text = literal
	view.chat_input.text_submitted.emit(literal)
	check(await wait_until(func() -> bool: return view.network.chat.messages.size() == 2 and view.network.chat.pending.is_empty()), "Both independent clients send and receive public chat")
	check(not view.chat_log.bbcode_enabled and view.chat_log.get_parsed_text().contains("[b]") and view.chat_input.text.is_empty(), "Markup is literal plain text and confirmed input clears")
	var before_input := view.network._input_seq
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(0.25).timeout
	key.pressed = false
	Input.parse_input_event(key)
	check(view.network._input_seq == before_input, "Typing WASD in chat never issues movement commands")
	await capture("chat")
	var destination := Vector2i(13, 16) if role == "alice" else Vector2i(15, 16)
	view.network.move_to(destination)
	check(await wait_until(func() -> bool:
		if not view.network.entities.has(own_id): return false
		var own: Dictionary = view.network.entities[own_id]
		return Vector2i(own.cell[0], own.cell[1]) == destination and own.next_cell == null and seen_remote_motion
	), "Authoritative movement reaches target and remote movement is observed")
	print("MOVEMENT ", role, " ", view.network.entities, " remote_motion=", seen_remote_motion, " status=", view.status.text)
	await capture("moved")
	check(view.chat_panel.visible and seen_remote_motion, "Remote actors keep updating while public chat stays open")
	mark("moved")
	if role == "bob":
		check(await wait_until(func() -> bool: return FileAccess.file_exists(folder.path_join("reconnect"))), "Coordinator triggers network loss")
		# Freeze only this connection's receive loop, not the peer or server. The
		# peer observes acceptance before we deliberately lose the sender's result.
		view.network.set_process(false)
		view.chat_input.text = "重连原消息"
		view.chat_send.pressed.emit()
		view.network.socket.poll()
		check(not view.network.chat.pending.is_empty(), "Lost-response fixture retains the original client message ID")
		check(await wait_until(func() -> bool: return FileAccess.file_exists(folder.path_join("alice_chat_seen"))), "Peer saw message before sender received confirmation")
		view.network.socket.close()
		view.network.set_process(true)
		check(await wait_until(func() -> bool: return view.network.world_ready and view.network.connection_epoch != epoch), "Network loss automatically obtains a fresh ticket and reconnects")
		check(view.network.game_session == game and int(view.network.connection_epoch) > int(epoch), "Same login resumes original game session with a new epoch")
		var restored: Array = view.network.entities[own_id].cell
		check(Vector2i(restored[0], restored[1]) == destination, "Reconnect preserves authoritative location")
		check(await wait_until(func() -> bool: return view.network.chat.connected and view.network.chat.pending.is_empty() and view.network.chat.messages.size() == 3), "Reconnect retries original chat ID and recovers bounded history")
		check(view.chat_log.get_parsed_text().count("重连原消息") == 1, "Lost response does not duplicate the public message")
		mark("reconnected")
	else:
		check(await wait_until(func() -> bool: return view.chat_log.get_parsed_text().contains("重连原消息")), "Peer receives message while sender stops polling")
		mark("chat_seen")
		check(await wait_until(func() -> bool: return FileAccess.file_exists(folder.path_join("bob_reconnected"))), "Other client reconnect completed")
		check(await wait_until(func() -> bool: return view.network.entities.has(other_id)), "Peer returns without duplicate entity")
		check(seen_remote_leave and view.actors.size() == 2, "Disconnect removed peer and reconnect restored exactly one actor")
		check(view.chat_log.get_parsed_text().count("重连原消息") == 1, "Reconnect retry is not rebroadcast to other players")
	await capture("reconnected")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Shared-world play never mutates offline assets")
	mark("done")
	check(await wait_until(func() -> bool: return FileAccess.file_exists(folder.path_join("finish"))), "Coordinator finishes both clients")
	view.network.leave()
	await get_tree().create_timer(0.3).timeout
	app.queue_free()
	await get_tree().process_frame
	Game.save_path = old_path
	print("SHARED WORLD %s: %d checks, %d failures" % [role, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
