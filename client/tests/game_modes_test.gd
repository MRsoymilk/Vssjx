extends "res://tests/shared_interface_test.gd"

func _run() -> void:
	await Game.when_ready()
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_characters := OnlineAccount.characters.duplicate(true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-modes=") and DisplayServer.get_name() != "headless": output = argument.trim_prefix("--capture-modes=")
	Game.save_path = "user://game_modes_%d.json" % OS.get_process_id()
	Game.new_player("本地修士", 0, 0)
	await Game.save_game()
	var saved := FileAccess.get_file_as_string(Game.save_path)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	app._enter_local_game()
	check(app.mode == "local_select" and app.character_selection.get_node("GameMode").text == "本地模式", "Existing local slot identifies local mode on selection")
	await capture("00_local_selection")
	app.character_selection.enter_button.pressed.emit()
	var local: ShushanWorld = app.world
	local.set_process(false)
	var terrain: TileMapLayer = local.terrain
	var grid := local.astar
	var canonical := SharedWorldMap.load_data()
	check(local.map_data == canonical, "Local map reads the exact online map data instead of regenerating terrain")
	var screen: GameWorldScreen = app.ui.get_child(0)
	check(screen.get_node("GameMode").text == "本地模式", "Local HUD identifies mode")
	var chat: LocalWorldChat = screen.local_chat
	screen.chrome.toolbar.get_node("Social").pressed.emit()
	await get_tree().process_frame
	check(chat.panel.visible and chat.input.has_focus(), "Local social button opens the same authored composer")
	local.path.append(Vector2i(11, 16))
	chat.release_input()
	chat._focus()
	check(local.path.is_empty(), "Focusing local chat cancels click movement")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var before := local.hero.position
	local._process(0.2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(local.hero.position == before, "Typing WASD in local chat cannot move the actor in its SubViewport")
	chat.input.text = "仅我可见[b]原样[/b][微笑]"
	screen.get_node("Chat/ChatSend").pressed.emit()
	check(chat.messages.size() == 1 and chat.input.text.is_empty() and chat.log.get_parsed_text().contains("[本地] 本地修士：仅我可见[b]原样[/b]"), "Local echo immediately renders literal text with no server receipt")
	check(chat.expanded.entries.size() == 1 and chat.expanded.public_caption == "本地", "Expanded local history uses the same private cache and local label")
	chat.input.text = " "
	chat.send()
	chat.input.text = "\u200b"
	chat.send()
	check(chat.messages.size() == 1, "Invalid local drafts are rejected")
	for index in 102:
		chat.input.text = "本地消息%d" % index
		chat.send()
	check(chat.messages.size() == 100 and chat.expanded.entries.size() == 100, "Local history stays bounded")
	var generation := OnlineAccount._generation
	var identity := {}
	for field in ["account", "server_address", "_expires_at", "_refresh_expires_at"]: identity[field] = OnlineAccount.get(field)
	OnlineAccount.account = {"id": SELF, "username": "mode_fixture"}
	OnlineAccount.server_address = "http://127.0.0.1:9"
	OnlineAccount._expires_at = Time.get_unix_time_from_system() + 3600
	OnlineAccount._refresh_expires_at = OnlineAccount._expires_at + 3600
	OnlineAccount.list_characters()
	OnlineAccount.request_world_ticket(SELF, "ignored")
	OnlineAccount.refresh()
	check(OnlineAccount.network_suspended and not OnlineAccount.is_processing() and OnlineAccount._generation == generation and OnlineAccount._request == null and not OnlineAccount.busy, "Local mode blocks background and explicit account/world reports")
	for field in identity: OnlineAccount.set(field, identity[field])
	check(FileAccess.get_file_as_string(Game.save_path) == saved, "Local chat never writes character data or message history to the save")
	chat.release_input()
	local.hero.position = local.cell_center(Vector2i(12, 16))
	chat.input.text = "本地消息仅我可见[微笑]"
	chat.send()
	await capture("01_local_chat")
	var cells := terrain.get_used_cells()
	var atlas: Dictionary = {}
	var solids: Dictionary = {}
	for point in cells:
		atlas[point] = terrain.get_cell_atlas_coords(point)
		solids[point] = grid.is_point_solid(point)
	var definitions := ShushanWorld.ENEMIES.slice(0, 4).duplicate(true)
	app._world_ui()
	check(app.ui.get_child(0).local_chat.messages.size() == 100, "Rebuilding local HUD retains this session's private history")
	app._home()
	OnlineAccount.resume_network()
	OnlineAccount.characters = [{"id": SELF, "display_name": "联机修士", "job": 0, "gender": 0, "school": 0, "level": 1, "hp": 120, "mp": 32, "xp": 0, "gold": 30}]
	app._enter_online_world(SELF)
	var online: OnlineWorldView = app.ui.get_node("OnlineWorld")
	online.network.set_process(false)
	online.network.world_ready = true
	online.network.world_stream = EPOCH
	online.network.entities = {SELF: entity(SELF, 1, "联机修士", 0, 0, [12, 16])}
	online.network.changed.emit(online.network.entities)
	check(online.map_data == canonical and online.screen.get_node("GameMode").text == "联机模式", "Online map uses the same canonical data and identifies online mode")
	for point in cells:
		check(online.get_node("Viewport/Scene/Terrain").get_cell_atlas_coords(point) == atlas[point] and online._motion_grid.is_point_solid(point) == solids[point], "Both modes have identical terrain and collision at %s" % point)
	var population := SharedWorldMap.population()
	for definition in definitions:
		check(population.filter(func(value: Dictionary) -> bool: return value.id == definition.id) == [definition], "Local resident definition matches server source: " + String(definition.id))
	check(online.screen.local_chat == null and online.network.chat.messages.is_empty(), "Online chat starts without any local message history")
	check(online.network.chat.receive({"type": "chat.ready", "channel_epoch": EPOCH, "latest_seq": "0", "oldest_seq": "1", "history_limit": 50, "dedup_seconds": 300, "max_chars": 120, "max_bytes": 480}), "Online public channel accepts handshake")
	online.network.chat.enabled = true
	online.network.chat.send_requested.connect(func(message: Dictionary) -> void: sent.append(message))
	online.chat_input.text = "大家都能看到"
	online.chat_send.pressed.emit()
	check(sent.size() == 1 and sent[0].channel == "public" and not online.chat_input.text.is_empty(), "Online chat submits to the public channel and waits for confirmation")
	check(online.network.chat.receive({"type": "chat.batch", "channel_epoch": EPOCH, "messages": [{"seq": "1", "message_id": "30000000-0000-4000-8000-000000000001", "sender_character_id": PEER, "display_name": "同图修士", "server_time_ms": "1792036800000", "channel": "public", "text": "来自另一名玩家"}]}), "Online channel receives another player's message")
	check(online.chat_log.get_parsed_text().contains("同图修士：来自另一名玩家"), "Online messages from peers appear in shared UI")
	check(Game.player.name == "本地修士" and FileAccess.get_file_as_string(Game.save_path) == saved, "Online simulation and public chat never change offline character or storage")
	await capture("02_online_chat")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = old_player
	OnlineAccount.characters = old_characters
	print("GAME MODES: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
