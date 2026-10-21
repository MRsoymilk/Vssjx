extends Node
var checks := 0
var failures := 0
var view: OnlineWorldView
var connection_statuses: Array[String] = []

func _ready() -> void: call_deferred("_run")
func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + text)
func wait_until(predicate: Callable, seconds: float = 20.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()
func click_gate() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = view.portal_marker.position - view.camera.get_screen_center_position() + Vector2(view.viewport.size) / 2.0
	view._map_input(event)
func _run() -> void:
	var old := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_MAP_TEST_BASE"), "map_ui", OS.get_environment("SSJX_MAP_TEST_PASSWORD"))
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "Owned map test account logs in")
	OnlineAccount.list_characters()
	await OnlineAccount.completed
	if OnlineAccount.characters.is_empty(): get_tree().quit(1); return
	view = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = OnlineAccount.characters[0].id
	add_child(view)
	view.network.status_changed.connect(func(text: String) -> void: connection_statuses.append(text))
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready and view.residents.size() == 5), "First map and NPCs synchronized")
	click_gate()
	check(view.network._input_seq > 0 or not view.network._pending_motion.is_empty(), "Real portal click requests authoritative movement to its tile")
	check(await wait_until(func() -> bool: return view.map_transition.blocking), "Walking onto a real online portal opens the native loading page")
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id == "ancient_ruins" and view.residents.has("boss"), 30.0), "Portal approaches, commits and reconnects automatically")
	if view.network.map_id != "ancient_ruins":
		print("Enter diagnostics: ", view._approach, " input=", view.network._input_seq, " pending=", view.network._pending_motion, " own=", view.network.entities.get(view.character_id, {}), " status=", view._system_text, " pve=", view.network.pve.last_code)
		get_tree().quit(1); return
	check(view.map_data == SharedWorldMap.load_data("ancient_ruins"), "Online ruins use exact same map bytes as local mode")
	check(view.screen.hud.get_node("MapName").text == "古剑遗迹", "HUD switches map name")
	check(view.residents.size() == 2 and not view.residents.has("qingwei"), "Ruins contain guardian and boss without old NPCs")
	check(view.screen.hud.get_node("Minimap").shared_map.map_id == "ancient_ruins", "Minimap switches terrain")
	check(view.portal_marker.get_child(0).text == "返回山道", "Return portal is visible")
	check(view.network.entities.has(view.character_id), "New baseline includes own character")
	check(await wait_until(func() -> bool: return not view.map_transition.blocking), "New baseline, character receipt and population release the loading page")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var path := OS.get_environment("SSJX_MAP_CAPTURE")
		if not path.is_empty(): get_viewport().get_texture().get_image().save_png(path)
	view.resident_selected.emit("guardian")
	check(await wait_until(func() -> bool: return view.network.pve.active() and (view.battle_view.visible or view.solo_battle.visible), 30.0), "Ruins guardian loads original battle art and authoritative encounter")
	check(view.network.pve.state.battle.enemy.art == "monster/xt1", "Guardian uses its own original animation")
	check(view.network.pve.submit("flee"), "Ruins encounter accepts authoritative retreat")
	check(await wait_until(func() -> bool: return not view.network.pve.active() and not view.network.pve.pending() and view.battle_view.animation_time <= 0), "Retreat completes before returning to map")
	check(await wait_until(func() -> bool: return not view.battle_view.visible and not view.solo_battle.visible), "Retreat returns to the map without a result confirmation")
	check(not view.battle_view.visible and not view.solo_battle.visible, "Battle returns to the ruins map")
	# Return using the rendered portal and the same authoritative movement workflow.
	click_gate()
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id == "qingyun_trail" and view.residents.has("qingwei")), "Return portal restores the first map")
	if view.network.map_id != "qingyun_trail":
		print("Return diagnostics: ", view._approach, " input=", view.network._input_seq, " own=", view.network.entities.get(view.character_id, {}), " status=", view._system_text)
	check(view.residents.size() == 5 and not view.residents.has("boss"), "No ruins actors remain in first map")
	check(view.screen.hud.get_node("MapName").text == "青云山道", "First map HUD is restored")
	check(await wait_until(func() -> bool: return not view.map_transition.blocking), "Return journey finishes loading before input resumes")
	check(Game.player == old, "Online map changes never touch local saves")
	check(not connection_statuses.any(func(text: String) -> bool: return text.begins_with("连接中断")), "Normal map transfers never report a disconnected failure")
	view.network.move_to(Vector2i(11,16))
	check(await wait_until(func() -> bool: return view.network.entities.has(view.character_id) and view.network.entities[view.character_id].cell==[11,16] and view.network.entities[view.character_id].next_cell==null), "Movement remains usable after round-trip transfer")
	view.network.leave()
	view.queue_free()
	await get_tree().process_frame
	print("ONLINE MAP UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
