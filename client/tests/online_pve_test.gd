extends "res://tests/population_test.gd"

func pve_state(revision: int = 1, stage: int = 0) -> Dictionary:
	return {"rules_version":"qingyun-pve-v1", "character":{"id":SELF,"display_name":"昆仑客","name_rules_version":"nickname-v1","rules_version":"creation-v1","state_revision":str(revision),"job":1,"gender":0,"school":2,"level":1,"gold":30,"hp":95,"mp":45,"xp":0,"quest_stage":stage,"map_id":"qingyun_trail","cell_x":10,"cell_y":16},"potions":6,"stats":{"hp":95,"mp":45,"attack":28,"defense":4},"progress":{"kills":0,"defeated":[]},"battle":null}

func wait_until(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()

func _run() -> void:
	output = OS.get_environment("SSJX_PVE_CAPTURE_PATH")
	var old := Game.player.duplicate(true)
	OnlineAccount.pending_pve = {}
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.stream = EPOCH
	view.network.world_ready = true
	view.network._pve_version = 1
	view.network.pve.bind_character(SELF, "http://127.0.0.1:9999")
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10,16])}
	view.network.changed.emit(view.network.entities)
	var population := residents_packet()
	view.network.population.receive(population)
	var model := view.network.pve
	check(model.receive({"type":"pve.state","state":pve_state()}), "Validated private state accepted")
	model.send_requested.connect(func(packet: Dictionary) -> void: sent.append(packet))
	view.resident_selected.emit("qingwei")
	check(not view.encounter.visible and not view.encounter.has_node("Panel"), "Selecting NPC never opens a confirmation dialog")
	check(not view._approach.is_empty() and sent.is_empty(), "NPC click approaches directly without submitting from afar")
	view._scene_action("menu")
	check(view._approach.is_empty() and sent.is_empty(), "Opening menu cancels an unsubmitted interaction")
	view.menu.hide()
	view.resident_selected.emit("wolf_a")
	view.resident_selected.emit("qingwei")
	check(view._approach.target == "qingwei", "Selecting another target replaces the old approach")
	view.network._pending_motion = {}
	view.network.entities[SELF].cell = [10,14]
	view._advance_approach()
	check(model.pending() and sent.size() == 1 and sent[0].command.action == "accept", "Stationary character sends one authoritative quest operation")
	check(view.encounter.visible and view.encounter.waiting and view.encounter.progress == 0.0, "Server wait uses the local visual with indeterminate progress")
	check(view.encounter is BattleEncounterTransition and view.encounter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Indicator reuses local transition and does not block chat")
	view.resident_selected.emit("qingwei")
	view._advance_approach()
	check(sent.size() == 1 and view._approach.is_empty(), "Repeated resident clicks cannot submit another pending operation")
	var operation: String = sent[0].command.operation_id
	check(not model.submit("accept", "qingwei"), "Pending command blocks double-clicks")
	model.disconnect_channel()
	check(model.pending() and not model.ready and view.encounter.waiting and view.encounter.detail.text.contains("连接中断"), "Unknown result survives channel loss with reconnect indicator")
	check(model.receive({"type":"pve.state","state":pve_state(2,1)}) and sent.size() == 2 and sent[1] == sent[0], "Reconnect retries exact original operation and payload")
	var result := {"type":"pve.result","operation_id":operation,"ok":true,"replayed":true,"lines":["已领受山林试炼"],"state":pve_state(2,1)}
	check(model.receive(result) and not model.pending() and not view.encounter.visible, "Receipt clears pending action and updates UI")
	view._scene_action("quest")
	check(view.get_node("Menu/Panel/Body").text.contains("0 / 3"), "Quest menu shows live server progress")
	view.details.hide()
	var no_request := sent.size()
	view.resident_selected.emit("qingwei")
	view.network._pending_motion = {}
	view._advance_approach()
	check(sent.size() == no_request and not view.encounter.visible and view._system_text.contains("0 / 3"), "Full-health NPC interaction shows quest progress without an unnecessary restore")
	var state := pve_state(3,1)
	state.character.hp = 85
	state.character.mp = 36
	state.battle = {"id":PEER,"enemy":population.entities[1].duplicate(true),"hp":85,"mp":36,"potions":6,"enemy_hp":43,"round":1,"revision":"1","outcome":"active"}
	check(model.receive({"type":"pve.state","state":state}), "Server battle snapshot accepted")
	check(view.encounter.visible and not view.encounter.waiting and view.encounter.progress == 0.0 and not view.battle_view.visible, "Authoritative battle first displays encounter icon and resource preparation bar")
	await capture("online_encounter")
	var last_progress := 0.0
	var monotonic := true
	var preparation_deadline := Time.get_ticks_msec() + 5000
	var captured_progress := false
	var commands_before := sent.size()
	while not view.battle_view.visible and Time.get_ticks_msec() < preparation_deadline:
		monotonic = monotonic and view.encounter.progress >= last_progress and view.encounter.progress <= 1.0
		last_progress = view.encounter.progress
		if not captured_progress and last_progress > 0.0:
			captured_progress = true
			await capture("online_preparation")
		await get_tree().process_frame
	check(view.battle_view.visible, "Prepared assets automatically enter battle without another click")
	check(monotonic and captured_progress and sent.size() == commands_before, "Resource progress advances monotonically without submitting a battle action")
	check(view.encounter.progress == 1.0 and not view.encounter.visible, "Real preparation completes before hiding the indicator")
	check(view.battle_view.visible and view.battle_view.hero is AnimatedSprite2D and view.battle_view.enemy is AnimatedSprite2D, "Authored battle scene uses native animated character and monster")
	check(view.battle_view.hero.get_parent().position.x > view.battle_view.enemy.get_parent().position.x and view.battle_view.get_node("Hud/ActionMenu").visible, "Reference places hero right, enemy left and a vertical action menu in the center")
	check(view.chat_panel.visible and view.chat_panel.position.y == 424 and view.battle_view.get_rect() == Rect2(0,28,320,396), "Battle retains the same bottom chat area")
	view._scene_action("system")
	check(view.details.visible and view.battle_view.visible, "System menu remains accessible to leave and resume an active encounter")
	view.details.hide()
	var labels := PackedStringArray()
	for button in view.battle_view.buttons: labels.append(button.text)
	check(labels == PackedStringArray(["1 攻击", "2 技能", "3 待机", "4 道具", "5 查看", "6 逃跑"]), "Reference menu preserves all six names and ordering")
	view.battle_view.selected_enemy = true
	view.battle_view.choose("inspect")
	check(view.battle_view.get_node("Inspect").visible and view.battle_view.get_node("Inspect/NameValue").text == "山狼", "Inspect shows selected monster's server attributes")
	view.battle_view.get_node("Inspect/Close").pressed.emit()
	view.battle_view.choose("potion")
	check(view.battle_view.get_node("Choice/Use").text == "回春散 ×6", "Items menu uses the server's potion inventory")
	view.battle_view.get_node("Choice/Cancel").pressed.emit()
	view.battle_view.toggle_auto()
	check(view.battle_view.automatic and not view.battle_view.get_node("Hud/ActionMenu").visible, "Reference automatic combat toggle hides manual menu")
	view.battle_view.toggle_auto()
	check(not view.battle_view.has_node("Speed") and not view.battle_view.has_node("Settings"), "Battle omits the removed acceleration and wrench controls")
	var invalid := state.duplicate(true)
	invalid.battle.enemy.art = "res://scripts/main.gd"
	check(not model.receive({"type":"pve.state","state":invalid}) and model.state == state, "Invalid battle resource cannot replace current state")
	check(model.receive(result) and model.active() and model.state.character.state_revision == "3", "Old replay receipt cannot roll current state backwards")
	output = OS.get_environment("SSJX_PVE_CAPTURE_PATH")
	await capture("online_battle")
	view.battle_view.get_node("Hud/ActionMenu/BattleButtons1").pressed.emit()
	check(view.battle_view.get_node("Choice").visible, "Reference skill menu opens a skill choice")
	view.battle_view.get_node("Choice/Use").pressed.emit()
	check(sent[-1].command.action == "skill" and sent[-1].command.battle_id == PEER and sent[-1].command.expected_revision == "1", "Battle action includes server battle identity and revision")
	check(view.battle_view.get_node("Result/Return").disabled, "Active encounter cannot be dismissed into movement")
	output = OS.get_environment("SSJX_PVE_CAPTURE_PATH")
	var finished := state.duplicate(true)
	finished.character.state_revision = "4"
	finished.character.gold = 42
	finished.progress = {"kills":1,"defeated":["wolf_a"]}
	finished.battle.outcome = "victory"
	finished.battle.revision = "2"
	finished.battle.enemy_hp = 0
	var receipt := {"type":"pve.result","operation_id":sent[-1].command.operation_id,"ok":true,"replayed":false,"lines":["山狼被击败！","获得12铜钱、16修为。"],"state":finished}
	check(model.receive(receipt) and view.residents.size() == 4 and not view.residents.has("wolf_a"), "Victory hides only this character's defeated monster")
	check(view.screen.hud.get_node("Minimap").shared_population.size() == 4, "Personal quest completion updates minimap without changing shared population")
	await capture("online_victory")
	view.battle_view.animation_time = 0
	view.battle_view.refresh()
	view.battle_view.get_node("Result/Return").pressed.emit()
	view.resident_selected.emit("qingwei")
	await capture("online_npc")
	view.network._pending_motion = {}
	view._advance_approach()
	check(model.pending() and sent[-1].command.action == "restore" and not view.battle_view.visible, "Injured NPC interaction restores directly without reopening the dismissed battle")
	var restored := finished.duplicate(true)
	restored.character.state_revision = "5"
	restored.character.hp = 95
	restored.character.mp = 45
	check(model.receive({"type":"pve.result", "operation_id":sent[-1].command.operation_id, "ok":true,"replayed":false,"lines":["元气已恢复"],"state":restored}), "Restore receipt applies normally")
	var claim := restored.duplicate(true)
	claim.character.state_revision = "6"
	claim.character.quest_stage = 2
	claim.progress = {"kills":3,"defeated":["wolf_a","wolf_b","wolf_c"]}
	model.receive({"type":"pve.state","state":claim})
	view.resident_selected.emit("qingwei")
	view.network._pending_motion = {}
	view._advance_approach()
	check(sent[-1].command.action == "claim", "Completed quest directly claims its reward when NPC is reached")
	OnlineAccount.pending_pve = {}
	# Failed preparation remains a recoverable server battle, never a fake success.
	var next_battle := state.duplicate(true)
	next_battle.character.state_revision = "7"
	next_battle.battle.id = EPOCH
	var art := String(next_battle.battle.enemy.art)
	var texture: String = OriginalArt.catalog[art].texture
	OriginalArt.catalog[art].texture = "res://assets/actors/missing-online-test.png"
	var count_before_load := sent.size()
	model.receive({"type":"pve.state","state":next_battle})
	check(await wait_until(func() -> bool: return view._battle_load_failed), "Missing resources produce a recoverable load failure")
	OriginalArt.catalog[art].texture = texture
	check(model.active() and sent.size() == count_before_load and view.battle_view.battle_id != EPOCH, "Resource failure neither resubmits challenge nor simulates a battle result")
	var retry_click := InputEventMouseButton.new()
	retry_click.button_index = MOUSE_BUTTON_LEFT
	retry_click.pressed = true
	view._map_input(retry_click)
	check(await wait_until(func() -> bool: return view.battle_view.battle_id == EPOCH), "Clicking map retries resource preparation in the same authoritative battle")
	check(sent.size() == count_before_load, "Resource retry sends no extra game command")
	# Disconnect during the warning invalidates the old preparation generation.
	next_battle.character.state_revision = "8"
	next_battle.battle.id = SELF
	model.receive({"type":"pve.state","state":next_battle})
	check(not view.battle_view.visible, "Old battle controls are hidden while the next encounter prepares")
	model.disconnect_channel()
	await get_tree().create_timer(0.4).timeout
	check(view._loading_battle.is_empty() and view.battle_view.battle_id == EPOCH, "Disconnected preparation cannot enter a stale battle")
	model.receive({"type":"pve.state","state":next_battle})
	check(await wait_until(func() -> bool: return view.battle_view.battle_id == SELF), "Reconnection prepares and restores the authoritative active battle")
	next_battle.character.state_revision = "9"
	next_battle.battle.id = PEER
	model.receive({"type":"pve.state","state":next_battle})
	check(await wait_until(func() -> bool: return view._battle_resource_request != null and view.encounter.progress > 0.0), "Cancellation fixture reaches real resource/cache work")
	var preparing_epoch: int = view._battle_load_epoch
	next_battle.character.state_revision = "10"
	next_battle.battle.revision = "2"
	next_battle.battle.round = 2
	model.receive({"type":"pve.state","state":next_battle})
	check(view._battle_load_epoch == preparing_epoch, "New revision of the same battle does not restart asset preparation")
	model.disconnect_channel()
	await get_tree().create_timer(0.4).timeout
	check(view._battle_resource_request == null and view.battle_view.battle_id == SELF, "Disconnect during cache work releases the request and rejects its late continuation")
	model.receive({"type":"pve.state","state":next_battle})
	check(await wait_until(func() -> bool: return view.battle_view.battle_id == PEER) and view.battle_view.revision == "2", "Prepared scene restores the latest server revision")
	# A scene being discarded cannot receive a late prepared battle.
	next_battle.character.state_revision = "11"
	next_battle.battle.id = EPOCH
	model.receive({"type":"pve.state","state":next_battle})
	var weak_view: WeakRef = weakref(view)
	app._home()
	await get_tree().create_timer(0.5).timeout
	check(weak_view.get_ref() == null and app.mode == "home", "Leaving during preparation discards the old view without a late battle")
	OnlineAccount.pending_pve = {}
	model.disconnect_channel()
	check(Game.player == old, "Online quest and battle never mutate local progress")
	OnlineAccount.pending_pve = {}
	app.queue_free()
	await get_tree().process_frame
	print("ONLINE PVE UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
