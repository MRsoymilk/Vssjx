extends Node
## UI integration using validated world/chat protocol fixtures, without a DB.
const SELF := "10000000-0000-4000-8000-000000000001"
const PEER := "10000000-0000-4000-8000-000000000002"
const EPOCH := "20000000-0000-4000-8000-000000000001"
var checks := 0
var failures := 0
var sent: Array = []
var output := ""

func _ready() -> void: call_deferred("_run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func entity(id: String, net_id: int, display_name: String, job: int, gender: int, cell: Array) -> Dictionary:
	return {"id": id, "net_id": net_id, "display_name": display_name, "job": job, "gender": gender, "cell": cell, "next_cell": null, "segment_progress": 0, "entity_revision": "0", "last_input_seq": "0", "world_epoch": "1"}

func delta(seq: int, entered: Array = [], removed: Array = [], moves: Array = []) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data("VWD2".to_ascii_buffer())
	buffer.put_data(EPOCH.replace("-", "").hex_decode())
	buffer.put_u64(seq)
	var bytes := JSON.stringify(entered).to_utf8_buffer()
	buffer.put_u32(bytes.size())
	buffer.put_u16(removed.size())
	buffer.put_u16(moves.size())
	buffer.put_data(bytes)
	for net_id in removed: buffer.put_u32(net_id)
	for move in moves:
		buffer.put_u32(move[0])
		buffer.put_u16(move[1])
		buffer.put_u16(move[2])
		buffer.put_u16(move[3])
		buffer.put_u64(move[4])
		buffer.put_u64(move[5])
	bytes = buffer.data_array
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	bytes.append_array(digest.finish())
	return bytes

func capture(name_value: String) -> void:
	if output.is_empty(): return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_value + ".png")) == OK, "Save shared interface capture")

func _run() -> void:
	output = OS.get_environment("SSJX_INTERFACE_CAPTURE_PATH")
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://shared_interface_%d.json" % OS.get_process_id()
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-sentinel")
	Game.player = {"offline_sentinel": true}
	var offline := Game.player.duplicate(true)
	OnlineAccount.characters = [{"id": SELF, "display_name": "昆仑客", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45, "xp": 0, "gold": 30}]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.world_stream = EPOCH
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10, 16])}
	view.network._net_ids = {1: SELF}
	view.network.changed.emit(view.network.entities)
	check(view.network._receive_delta(delta(1, [entity(PEER, 2, "青衫客", 0, 1, [12, 16])])), "Validated world publication adds a peer")
	check(view.actors.size() == 2 and app.world == null and app.mode == "online_world", "Shared UI shows both players without starting an offline simulation")
	check(view.screen.scene_file_path == "res://scenes/ui/game_world_screen.tscn", "Online map uses the reusable game HUD scene")
	check(not view.screen.chrome.use_local_player and view.screen.chrome.identity.text == "LV.1", "Online HUD reads server character data without a local player")
	check(view.viewport.size == Vector2i(320, 375) and view.image.get_rect() == Rect2(0, 28, 320, 375), "Online field matches the original game viewport boundaries")
	check(view.screen.chrome.toolbar.visible and view.screen.hud.get_node("Minimap").shared_entities.size() == 2, "Original toolbar and minimap include online peers")
	check(view.chat_panel.visible and view.chat_panel.position.y == 403 and not view.has_node("ChatPanel"), "Chat is permanently embedded in the original bottom message area")
	check(view.screen.hud.get_node("MapCoordinates").text == "10  16" and view.count_label.text == "同图2人", "Coordinates and online population are displayed in the game HUD")
	var system_log := view.chat_log.get_parsed_text()
	check(view.network.chat.receive({"type": "chat.ready", "channel_epoch": EPOCH, "latest_seq": "40", "oldest_seq": "41", "history_limit": 1, "dedup_seconds": 300, "max_chars": 120, "max_bytes": 480}), "Chat channel handshake is accepted")
	check(view.network.chat.messages.is_empty() and view.chat_log.get_parsed_text() == system_log, "Entering a populated channel adds no pre-online history to the system log")
	view.network.chat.enabled = true
	view.network.chat.send_requested.connect(func(message: Dictionary) -> void: sent.append(message))
	view._process(0.01)
	view.chat_button.pressed.emit()
	await get_tree().process_frame
	check(view.chat_input.has_focus() and view.chat_panel.visible, "Toolbar social icon focuses the inline composer")
	var before_timer := view._key_timer
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	view._process(0.2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(view._key_timer == before_timer and not view._was_keyboard, "Typing WASD in inline chat never advances the movement input loop")
	view.chat_input.text = "[b]同屏聊天[/b]"
	view.chat_send.pressed.emit()
	check(sent.size() == 1 and sent[0].text == "[b]同屏聊天[/b]" and not view.network.chat.pending.is_empty(), "Inline send submits to the existing reliable public channel")
	var message_id := "30000000-0000-4000-8000-000000000001"
	check(view.network.chat.receive({"type": "chat.result", "result": {"client_message_id": sent[0].client_message_id, "status": "SENT", "message_id": message_id}}), "Confirmed send receipt is accepted")
	check(view.chat_input.text.is_empty(), "Composer clears only after confirmed delivery")
	check(view.network.chat.receive({"type": "chat.batch", "channel_epoch": EPOCH, "messages": [{"seq": "41", "message_id": message_id, "sender_character_id": PEER, "display_name": "青衫客", "server_time_ms": "1792036800000", "channel": "public", "text": "[b]同屏聊天[/b]"}]}), "Peer public message is validated")
	check(not view.chat_log.bbcode_enabled and view.chat_log.get_parsed_text().contains("[b]同屏聊天[/b]"), "Public messages render as literal text in the bottom area")
	check(view.network.chat.receive({"type": "chat.batch", "channel_epoch": EPOCH, "messages": [{"seq": "42", "message_id": "30000000-0000-4000-8000-000000000002", "sender_character_id": PEER, "display_name": "青衫客", "server_time_ms": "1792036800001", "channel": "public", "text": "大家好，一起游历青云山道！"}]}), "Recent public messages replace expired history in the same inline log")
	var peer_before: Vector2 = view.actors[PEER].root.position
	check(view.network._receive_delta(delta(2, [], [], [[2, 524, 525, 500, 1, 1]])), "Peer movement is validated while chatting")
	view._process(0.1)
	check(view.chat_input.has_focus() and view.actors[PEER].root.position != peer_before, "Remote actors continue moving while the composer has focus")
	await capture("01_online_chat")
	view.screen.chrome.toolbar.get_node("Menu").pressed.emit()
	check(view.menu.visible and not view.chat_input.has_focus(), "Original game menu opens without invoking offline menu actions")
	view.menu.get_node("Dismiss").pressed.emit()
	check(not view.menu.visible, "Outside click closes the in-world menu")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(180, 200)
	view.chat_input.grab_focus()
	view._map_input(click)
	check(not view.chat_input.has_focus() and view.chat_panel.visible, "Clicking the map returns focus to movement without closing chat")
	check(view.network._receive_delta(delta(3, [], [2])), "Peer departure is validated")
	check(view.actors.size() == 1 and view.count_label.text == "同图1人", "Peer departure updates actors and population together")
	check(Game.player == offline and FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Online HUD, chat and menus never mutate local player state or save")
	app._home()
	Game.new_player("本地青衫", 1, 2)
	app._enter_world()
	var local_screen: GameWorldScreen = app.ui.get_child(0)
	check(local_screen.scene_file_path == "res://scenes/ui/game_world_screen.tscn" and not local_screen.chat.visible, "Local game uses the identical HUD scene with its existing system log")
	check(app.chrome.log_label.visible and app.minimap.world == app.world, "Local quests, HUD and minimap keep their own state")
	await capture("02_local_world")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	Game.player = old_player
	Game.save_path = old_path
	OnlineAccount.characters = []
	print("SHARED INTERFACE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
