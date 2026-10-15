extends "res://tests/population_test.gd"

func pve_state(revision: int = 1, stage: int = 0) -> Dictionary:
	return {"rules_version":"qingyun-pve-v1", "character":{"id":SELF,"display_name":"昆仑客","name_rules_version":"nickname-v1","rules_version":"creation-v1","state_revision":str(revision),"job":1,"gender":0,"school":2,"level":1,"gold":30,"hp":95,"mp":45,"xp":0,"quest_stage":stage,"map_id":"qingyun_trail","cell_x":10,"cell_y":16},"potions":6,"stats":{"hp":95,"mp":45,"attack":28,"defense":4},"progress":{"kills":0,"defeated":[]},"battle":null}

func _run() -> void:
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
	check(view.encounter.visible and view.encounter.scene_file_path.ends_with("online_encounter.tscn"), "NPC opens authored interaction scene")
	view.encounter.get_node("Panel/Primary").pressed.emit()
	check(not view._approach.is_empty() and view.encounter.approaching, "NPC action approaches before issuing quest command")
	view.network._pending_motion = {}
	view.network.entities[SELF].cell = [10,14]
	view._advance_approach()
	check(model.pending() and sent.size() == 1 and sent[0].command.action == "accept", "Stationary character sends one authoritative quest operation")
	var operation: String = sent[0].command.operation_id
	check(not model.submit("accept", "qingwei"), "Pending command blocks double-clicks")
	model.disconnect_channel()
	check(model.pending() and not model.ready, "Unknown result survives channel loss")
	check(model.receive({"type":"pve.state","state":pve_state(2,1)}) and sent.size() == 2 and sent[1] == sent[0], "Reconnect retries exact original operation and payload")
	var result := {"type":"pve.result","operation_id":operation,"ok":true,"replayed":true,"lines":["已领受山林试炼"],"state":pve_state(2,1)}
	check(model.receive(result) and not model.pending() and not view.encounter.visible, "Receipt clears pending action and updates UI")
	view._scene_action("quest")
	check(view.get_node("Menu/Panel/Body").text.contains("0 / 3"), "Quest menu shows live server progress")
	view.details.hide()
	var state := pve_state(3,1)
	state.character.hp = 85
	state.character.mp = 36
	state.battle = {"id":PEER,"enemy":population.entities[1].duplicate(true),"hp":85,"mp":36,"potions":6,"enemy_hp":43,"round":1,"revision":"1","outcome":"active"}
	check(model.receive({"type":"pve.state","state":state}), "Server battle snapshot accepted")
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
	model.submit("restore", "qingwei")
	check(not view.battle_view.visible, "New NPC command cannot reopen a previously dismissed battle result")
	OnlineAccount.pending_pve = {}
	model.disconnect_channel()
	check(Game.player == old, "Online quest and battle never mutate local progress")
	OnlineAccount.pending_pve = {}
	app.queue_free()
	await get_tree().process_frame
	print("ONLINE PVE UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
