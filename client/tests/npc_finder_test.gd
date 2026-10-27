extends "res://tests/ground_click_test.gd"

func _run() -> void:
	await Platform.when_ready(); await Game.when_ready()
	OnlineAccount.suspend_network()
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_pending := OnlineAccount.pending_pve.duplicate(true)
	OnlineAccount.pending_pve = {}
	Game.save_path = "user://npc_finder_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-sentinel")
	output = OS.get_environment("SSJX_NPC_FINDER_CAPTURE") if DisplayServer.get_name() != "headless" else ""
	_test_routes()
	await _test_local()
	await _test_online()
	check(FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Finding and talking never writes character assets or saves")
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path; Game.player = old_player
	OnlineAccount.pending_pve = old_pending
	OnlineAccount.resume_network()
	await get_tree().create_timer(0.25).timeout
	print("NPC FINDER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_routes() -> void:
	var grid := AStarGrid2D.new(); grid.region = Rect2i(0,0,9,7)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER; grid.update()
	var exits := [{"cell":[4,3], "cells":[[4,3],[4,4]]}]
	var path := NpcFinder.route(grid, Vector2i(1,3), Vector2i(8,3), exits)
	check(not path.is_empty() and Vector2i(4,3) not in path and Vector2i(4,4) not in path, "Same-map route avoids every auto-transfer cell")
	check(not grid.is_point_solid(Vector2i(4,3)) and not grid.is_point_solid(Vector2i(4,4)), "Shared grid is restored after route planning")
	var next := NpcFinder.waypoint(path)
	check(next.x == path[0].x or next.y == path[0].y, "Online waypoint packets form straight segments, not unsafe server shortcuts")
	check(absi(path[-1].x-8)+absi(path[-1].y-3) <= 2, "Destination is inside valid NPC interaction range")
	for y in 7: grid.set_point_solid(Vector2i(5,y),true)
	check(NpcFinder.route(grid, Vector2i(1,3), Vector2i(8,3), exits).is_empty(), "Unreachable NPC cannot become a teleport or a false arrival")
	check(NpcFinder.route(grid, Vector2i(-1,3), Vector2i(8,3), exits).is_empty(), "Invalid origins are rejected safely")

func _test_local() -> void:
	Game.new_player("寻找NPC",1,0)
	var app: Control = load("res://scenes/main.tscn").instantiate(); add_child(app); app.set_process(false)
	app._enter_world(); app.world.set_process(false)
	app._menu()
	check(app.modal.has_node("Panel/Rows/Find") and app.modal.rows.size() == 11, "Actual shared menu includes Finding without removing Help or System")
	app.modal.get_node("Panel/Rows/Find").pressed.emit()
	check(app.modal is WorldTargetList and app.modal.entries.size() == 1 and app.modal.entries[0].id == "qingwei", "Local finder lists only current-map NPCs, not monsters")
	check(app.modal.entries[0].name.begins_with("!") and app.modal.entries[0].detail.contains("入派"), "Rows include real task marker, services and coordinates")
	await capture("local-list")
	var before := [Game.player.quest,Game.player.gold,Game.player.hp,Game.player.mp]
	app.modal.rows.get_child(0).pressed.emit()
	check(app.modal == null and app.world.npc_search, "Choosing NPC starts walking and closes the list")
	for i in 240:
		if app.modal is OriginalNpcDialog: break
		app.world._process(1.0/60.0)
	check(app.modal is OriginalNpcDialog and app.modal.target == "qingwei" and app.world.next_cell.x < 0, "Local arrival automatically opens dialogue after stopping")
	check([Game.player.quest,Game.player.gold,Game.player.hp,Game.player.mp] == before, "Arrival never accepts a quest, heals, spends or challenges")
	await capture("local-arrived")
	app._close_modal()
	app.world.stop_moving(); app.world.cell = Vector2i(16,17); app.world.hero.position = app.world.cell_center(app.world.cell)
	check(app.world.find_npc("qingwei"), "A distant NPC can be selected by stable ID")
	local_click(app.world, app.world.cell_center(Vector2i(18,17)))
	check(not app.world.npc_search and app.world.pending.is_empty(), "Manual map movement cancels pending NPC dialogue")
	Game.player.ai_map = "ai_001"; Game.player.cell = AIWorld.map_data("ai_001").spawn.duplicate()
	app._enter_world(); app.world.set_process(false)
	app._scene_action("find")
	check(app.modal is WorldTargetList and app.modal.entries.any(func(entry:Dictionary)->bool:return entry.id == EndlessRules.rules.npc.id), "AI map includes its real service and endless NPCs")
	app.modal.search.text = "无尽"; app.modal._refresh()
	check(app.modal.rows.get_child_count() == 1, "Search can find NPCs by service, not only name")
	await capture("local-services")
	app._close_modal(); Game.player.corpse = {"id":SELF}
	check(not app.world.find_npc("ai_001_guide"), "Soul state cannot start NPC interaction")
	Game.player.erase("corpse")
	app.queue_free(); await get_tree().process_frame

func _ack_motion(view: OnlineWorldView) -> void:
	var command: Dictionary = view.network._pending_motion
	if command.get("type") == "world.move_to": view.network.entities[SELF].cell = command.target.duplicate()
	view.network.entities[SELF].next_cell = null
	view.network.entities[SELF].last_input_seq = str(view.network._input_seq)
	view.network._pending_motion.clear()
	view._snapshot(view.network.entities)
	for i in 300:
		if not view.actors[SELF].motion.has_motion(): break
		view.actors[SELF].motion.advance(1.0/60.0)
	view.actors[SELF].root.position = view.actors[SELF].motion.position

func _test_online() -> void:
	var before := Game.player.duplicate(true)
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = SELF; add_child(view); view.set_process(false); view.network.set_process(false)
	view.network.world_ready = true; view.network.stream = EPOCH
	view.network.entities = {SELF:entity(SELF,1,"寻找NPC",1,0,[10,16])}
	view._snapshot(view.network.entities)
	var packet := residents_packet(); packet.entities[0].cell = [12,13]
	view.network._receive(packet,JSON.stringify(packet).to_utf8_buffer())
	view.network.pve.ready = true
	view.network.pve.state = {"character":{"school":0,"quest_stage":0,"hp":95,"mp":45,"level":1},"stats":Game.stats(),"progress":{"kills":0},"battle":null}
	var writes: Array = []; view.network.pve.send_requested.connect(func(value:Dictionary)->void:writes.append(value))
	view._scene_action("menu"); view.menu.get_node("Panel/Rows/Find").pressed.emit()
	check(is_instance_valid(view.target_list) and view.target_list.entries.size() == 1 and view.target_list.entries[0].detail.contains("[12,13]"), "Online finder uses current authoritative coordinates, not original static placement")
	check(writes.is_empty(), "Opening finder sends no gameplay writes")
	var moved := residents_packet(2); moved.entities[0].cell = [13,13]
	view.network._receive(moved,JSON.stringify(moved).to_utf8_buffer())
	check(view.target_list.entries[0].detail.contains("[13,13]"), "Open finder refreshes coordinates from a new population revision")
	await capture("online-list")
	view.target_list.rows.get_child(0).pressed.emit()
	check(view.target_list == null and view._approach.get("npc_find", false), "Online row invokes the existing approach state machine")
	for i in 128:
		_ack_motion(view); view._advance_approach()
		if view.npc_dialog.visible or view._approach.is_empty(): break
	check(view.npc_dialog.visible and view.npc_dialog.target == "qingwei" and view._approach.is_empty(), "Confirmed arrival opens the same NPC dialogue exactly once")
	check(writes.is_empty() and OnlineAccount.pending_pve.is_empty(), "Arrival does not auto-submit accept, claim or challenge commands")
	await capture("online-arrived")
	view.npc_dialog.hide(); view.network.team_following = true
	view._scene_action("find")
	check(view.target_list == null and view.chat_status.text.contains("暂离"), "Following members are told to go away before independent pathfinding")
	view.network.team_following = false
	view._start_npc_find("qingwei"); _ack_motion(view)
	view.actors[SELF].motion.waypoints.append(view.actors[SELF].root.position+Vector2(1,0))
	view._advance_approach()
	check(not view.npc_dialog.visible and not view._approach.is_empty(), "Arrival waits for rendered movement to settle, not just a server position")
	view.actors[SELF].motion.advance(0.1); view._advance_approach()
	check(view.npc_dialog.visible, "Dialogue opens when both authority and visual movement have stopped")
	view.npc_dialog.hide()
	view.network.pve.state.battle = {"outcome":"active"}
	view._scene_action("find")
	check(view.target_list == null and view._approach.is_empty(), "Battle state cannot start finder navigation")
	view.network.pve.state.battle = null
	view.network.pve.state.character.corpse = {"id":SELF}
	view._scene_action("find")
	check(view.target_list == null and view.chat_status.text.contains("灵魂"), "Online soul cannot use NPC finder")
	view.network.pve.state.character.erase("corpse")
	view.network.map_rules.map_id = "qingyun_trail"
	view.network.map_rules.rules = {"residents":[{"id":"qingwei","enabled":false}]}
	view._scene_action("find")
	check(view.target_list.entries.is_empty() and view.target_list.empty.visible, "Disabled NPC is omitted even while an older population frame remains")
	view.network.map_rules.rules.residents[0].enabled = true; view._refresh_npc_finder()
	check(view.target_list.entries.size() == 1, "Open list refreshes when current-map NPC is enabled again")
	view._close_target_list(); view.network.map_rules.clear()
	view._start_npc_find("qingwei")
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_ESCAPE
	view._unhandled_key_input(key)
	check(view._approach.is_empty(), "Escape cancels automatic NPC approach")
	view._start_npc_find("qingwei"); _ack_motion(view)
	key.keycode = KEY_W; key.physical_keycode = KEY_W
	Input.parse_input_event(key); Input.flush_buffered_events(); view._advance_approach()
	key = key.duplicate(); key.pressed = false; Input.parse_input_event(key); Input.flush_buffered_events()
	check(view._approach.is_empty() and not view.npc_dialog.visible, "Manual keyboard input cancels before a pending arrival can open dialogue")
	view._start_npc_find("qingwei"); view.network.world_ready = false; view._status_changed("断线")
	check(view._approach.is_empty(), "Disconnect cancels the approach before reconnect")
	view.network.world_ready = true
	view._start_npc_find("qingwei"); view.network.population.entities.erase("qingwei"); view._advance_approach()
	check(view._approach.is_empty(), "NPC removed during approach cannot trigger a stale dialogue")
	view.network.population.entities["qingwei"] = packet.entities[0].duplicate(true)
	view.network.entities[SELF].cell = [10,16]
	view._start_npc_find("qingwei"); _ack_motion(view)
	var changed := {}
	for offset in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var point: Vector2i = Vector2i(10,16)+offset
		changed[point] = view._motion_grid.is_point_solid(point); view._motion_grid.set_point_solid(point,true)
	view._advance_approach()
	check(view._approach.is_empty() and view.chat_status.text.contains("不可达"), "Unreachable online NPC reports failure without any interaction")
	for point in changed: view._motion_grid.set_point_solid(point,changed[point])
	view._scene_action("find")
	var stale: WorldTargetList = view.target_list
	view._map_changed("ancient_ruins"); stale.chosen.emit("npc_find","qingwei")
	check(view.target_list == null and view._approach.is_empty() and not view.npc_dialog.visible, "Map changes discard finder and reject late old-map selection")
	check(Game.player == before, "Online finder never installs or changes the offline character")
	view.queue_free(); await get_tree().process_frame
