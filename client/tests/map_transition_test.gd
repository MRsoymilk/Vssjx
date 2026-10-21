extends Node
const DELAYED := preload("res://tests/fixtures/delayed_storage.gd")
var checks := 0
var failures := 0

func _ready() -> void: _run.call_deferred()

func check(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("MAP TRANSITION FAIL: " + text)

func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()

func _run() -> void:
	await Platform.when_ready()
	await Game.when_ready()
	var before := Game.player.duplicate(true)
	var path := Game.save_path
	var original := Platform.context
	var pending := OnlineAccount.pending_pve.duplicate(true)
	var storage := DELAYED.new()
	Platform.context = PlatformContext.new("map-transition-test", storage, original.runtime_config, original.display, original.lifecycle, original.resource_loader, original.text_input, original.system_actions)
	Game.save_path = "user://map_transition_test_%d.json" % OS.get_process_id()
	Game.new_player("切图测试", 1, 0)
	Game.player.quest = 3
	Game.player.cell = [28, 16]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	app._enter_world()
	check(app.map_transition == null, "Initial entry does not play a map transfer")
	app._world_interaction("portal", {})
	check(app.map_transition.blocking and not app.world.enabled, "Portal immediately covers the old map and freezes local input")
	check(await wait_until(func() -> bool: return not storage.operations.is_empty()), "Transfer awaits its storage operation")
	check(app.world.map_id == "qingyun_trail" and Game.storage_busy and app.map_transition.progress < 1.0, "Delayed persistence keeps the old world behind the loading page")
	app._world_interaction("portal", {})
	app._scene_action("bag")
	check(storage.operations.size() == 1 and app.modal == null, "Repeated portal/menu input cannot queue another transfer")
	var payload: Dictionary = JSON.parse_string(storage.operations[0].text)
	check(int(payload.cell[0]) == 5 and int(payload.cell[1]) == 16, "Pausing the old world cannot overwrite the new spawn before saving")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "SYNC_FAILED", "测试保存失败"))
	check(Game.player.zone == 0 and Game.player.cell == [28, 16] and app.world.map_id == "qingyun_trail", "Failed persistence rolls back map and spawn together")
	check(not app.map_transition.blocking and app.modal != null, "Failed save removes the cover and shows its error")
	app._close_modal()
	check(app.world.enabled, "Closing the error restores movement")
	app._world_interaction("portal", {})
	check(await wait_until(func() -> bool: return not storage.operations.is_empty()), "A failed transfer can be retried")
	storage.complete(PlatformResult.success({"written": true, "durability": "native_file"}))
	check(await wait_until(func() -> bool: return app.world.map_id == "ancient_ruins"), "Saved portal transfer builds the actual new world")
	check(await wait_until(func() -> bool: return not app.map_transition.blocking), "Loaded map completes the animation")
	check(app.world.enabled and Game.player.cell == [5, 16] and app.map_name.text == "古剑遗迹", "Map, HUD, spawn and movement agree after reveal")
	app._enter_world()
	check(not app.map_transition.blocking, "Rebuilding the same map after a battle does not replay loading")
	Game.player.zone = 0
	Game.player.cell = [3, 16]
	app._enter_world()
	app._world_interaction("ai_travel", {"target": "ai_001"})
	check(await wait_until(func() -> bool: return not storage.operations.is_empty()), "AI station uses the same storage barrier")
	storage.complete(PlatformResult.success({"written": true, "durability": "native_file"}))
	check(await wait_until(func() -> bool: return not app.map_transition.blocking), "AI station uses the same completed loading page")
	check(app.world.map_id == "ai_001" and app.world.enabled, "AI station reveals its destination and restores movement")
	app.free()
	Platform.context = original
	Game.player = before
	Game.save_path = path

	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	add_child(view)
	view.set_process(false)
	view.network.set_process(false)
	view.map_transition.set_process(false)
	view.character_id = "owned-transition-test"
	view._character = {"job": 0, "gender": 1, "appearance": [2, 1]}
	check(not view.map_transition.blocking, "Initial online join has no false map animation")
	view._map_command_sent({"command":{"action":"school_join"}})
	check(view.map_transition.blocking,"School admission starts the same protected map transition")
	view.network.pve.last_action="school_join";view.network.pve.last_code="STALE_SCHOOL"
	view.network.pve.message.emit("角色状态已变化")
	check(not view.map_transition.blocking,"Refused admission cancels loading and leaves the original map usable")
	view.network.pve.last_action="";view.network.pve.last_code=""
	view._map_command_sent({"command": {"action": "ai_travel"}})
	var runner := view.map_transition.runner
	check(view.map_transition.blocking and runner.get_meta("art_key") == ShopRules.actor_key(0, 1, [2, 1]), "Online transfer animates the current gender and equipment")
	check(runner.animation == "walk" and runner.is_playing() and runner.scale.x < 0 and runner.position.x == 32.0, "Original walking frames face toward the end of the loading strip")
	view.map_transition._process(0.02)
	check(view.map_transition._display_progress > 0 and view.map_transition._display_progress < view.map_transition.progress, "Visible progress moves smoothly toward a confirmed stage")
	view.map_transition._process(10.0)
	check(view.map_transition.blocking and view.map_transition.progress < 1.0, "A long network wait cannot invent completed progress")
	view._map_command_sent({"command": {"action": "ai_travel"}})
	check(view.map_transition.runner == runner, "Retried command keeps the same animation instead of restarting")
	view._scene_action("menu")
	check(not view.menu.visible, "Online menus are blocked while transferring")
	view.network.map_id = "ancient_ruins"
	view.map_data = SharedWorldMap.load_data("ancient_ruins")
	view._advance_map_transition()
	check(view.map_transition.progress == 0.5, "Handshake alone does not reveal an empty map")
	view.network.world_ready = true
	view.actors[view.character_id] = {}
	view._advance_map_transition()
	check(view.map_transition.progress == 0.7, "Snapshot waits for character progress")
	view.network.pve.ready = true
	view.network.pve.state = {"character": {"map_id": "ancient_ruins"}}
	view._advance_map_transition()
	check(view.map_transition.progress == 0.85, "Character progress waits for the population baseline")
	view.network.population.revision = 0
	OnlineAccount.pending_pve = {"command": {"action": "ai_travel"}}
	view._advance_map_transition()
	check(view.map_transition.progress < 1.0, "Unconfirmed transfer receipt still blocks reveal")
	OnlineAccount.pending_pve = {}
	view._advance_map_transition()
	check(view.map_transition.progress == 1.0 and view.map_transition.blocking, "All authoritative channels complete the bar before reveal")
	view.map_transition._process(1.0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var capture := OS.get_environment("SSJX_TRANSITION_CAPTURE")
		if not capture.is_empty(): check(get_viewport().get_texture().get_image().save_png(capture) == OK, "Capture original-style map loading")
	view.map_transition._process(0.11)
	check(not view.map_transition.blocking, "Final rendered hold releases online input")
	view._begin_map_transition()
	view.network.pve.state = {}
	view.actors.clear()
	view.network._failed("TIMEOUT")
	check(not view.map_transition.blocking and "TIMEOUT" in view._system_text, "Real connection errors remove the cover and retain the diagnosis")
	view._begin_map_transition()
	view.network.pve.last_action = "transfer"
	view.network.pve.last_code = "QUEST_REQUIRED"
	view.network.pve.message.emit("任务尚未完成")
	check(not view.map_transition.blocking and "任务尚未完成" in view._system_text, "Rejected transfers end animation and expose the server message")
	view.free()
	OnlineAccount.pending_pve = pending
	print("MAP TRANSITION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
