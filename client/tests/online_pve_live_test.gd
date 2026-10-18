extends Node
var checks := 0
var failures := 0
var view: OnlineWorldView
var own_id := ""

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
func _run() -> void:
	var old := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_PVE_BASE"), OS.get_environment("SSJX_PVE_USER"), OS.get_environment("SSJX_PVE_PASSWORD"))
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "Owned test account authenticated")
	OnlineAccount.list_characters()
	await OnlineAccount.completed
	if OnlineAccount.characters.is_empty(): get_tree().quit(1); return
	own_id = OnlineAccount.characters[0].id
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._online_characters()
	check(await wait_until(func() -> bool: return app.mode == "online_select" and app.character_selection != null and app.character_selection.get_node("Online")._loaded), "Real authenticated account stops at character selection")
	check(not app.ui.has_node("OnlineWorld") and app.world == null and app.character_selection.characters[0].id == own_id, "Character selection does not start online or offline world automatically")
	app.character_selection.enter_button.pressed.emit()
	check(await wait_until(func() -> bool: return app.mode == "online_world"), "Explicit Enter starts selected server character")
	view = app.ui.get_node("OnlineWorld")
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready and view.residents.size() == 5), "Real server negotiates population and private quest state")
	if not view.network.pve.ready: get_tree().quit(1); return
	view.screen.chrome.get_node("Properties").pressed.emit()
	check(view.attributes.visible and view.attributes.snapshot.name == view.network.pve.state.character.display_name, "Real online header opens original attributes with server identity")
	check(view.attributes.numbers.hp.value == "%d/%d" % [int(view.network.pve.state.character.hp), int(view.network.pve.state.stats.hp)], "Real attributes use authoritative health maximum")
	view.attributes.get_node("Back").pressed.emit()
	var map_revision: String = view.network.pve.state.character.state_revision
	view.screen.chrome.toolbar.get_node("Map").pressed.emit()
	check(view.world_map.visible and view.world_map.locations.size() == 79 and not view.details.visible, "Real online toolbar opens recovered world map scene")
	view.world_map.get_node("MainCity").pressed.emit()
	view.world_map.get_node("Footer/Back").pressed.emit()
	check(not view.world_map.visible and view.network.world_ready and view.network.pve.state.character.state_revision == map_revision, "World map browsing returns to same authoritative session without teleporting")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(14 * 16 + 8, 16 * 16 + 8) - view.camera.get_screen_center_position() + Vector2(view.viewport.size) / 2.0
	view._map_input(click)
	check(view.move_target.visible and view.move_target.destination == Vector2i(14,16), "Real online map click displays original destination marker")
	check(await wait_until(func() -> bool: return int(view.network.entities[own_id].cell[0]) == 14 and int(view.network.entities[own_id].cell[1]) == 16 and not view.move_target.visible), "Real movement clears marker only after character arrives")
	view.resident_selected.emit("qingwei")
	check(await wait_until(func() -> bool: return view.npc_dialog.visible), "Real approach opens the original-style NPC option list")
	check(int(view.network.pve.state.character.quest_stage) == 0 and not view.network.pve.pending() and not view.encounter.visible, "Opening conversation does not accept a task or trigger battle loading")
	view.npc_dialog.quest_button.pressed.emit()
	check(await wait_until(func() -> bool: return int(view.network.pve.state.character.quest_stage) == 1), "NPC task option accepts the quest on the real server")
	check(not view.encounter.visible and not view.npc_dialog.visible and not view.network.pve.pending(), "Confirmed task receipt closes dialogue without an encounter effect")
	view.resident_selected.emit("wolf_a")
	check(await wait_until(func() -> bool: return view.network.pve.active(), 30.0), "Moving monster can be approached and challenged through UI")
	check(await wait_until(func() -> bool: return view.battle_view.visible), "Real encounter prepares resources and enters battle without confirmation")
	check(view.encounter.progress == 1.0 and not view.encounter.visible and view.chat_panel.visible, "Completed resource progress disappears while original bottom chat stays usable")
	view.chat_input.text = "战斗中聊天[微笑]"
	view.chat_send.pressed.emit()
	check(await wait_until(func() -> bool: return view.network.chat.messages.size() == 1 and view.chat_input.text.is_empty()), "Chat and emotes remain usable during combat")
	view.chat_input.release_focus()
	var hp := int(view.network.pve.state.battle.enemy_hp)
	view.battle_view.get_node("Hud/ActionMenu/BattleButtons0").pressed.emit()
	check(await wait_until(func() -> bool: return not view.network.pve.pending() and int(view.network.pve.state.battle.enemy_hp) < hp), "Battle button applies authoritative damage")
	var battle_id: String = view.network.pve.state.battle.id
	var connection := view.network.connection_epoch
	var ownership := view.network.world_epoch
	# Lose a guard response after sending. Retry must retain operation UUID and version.
	view.network.pve.submit("guard")
	var pending := OnlineAccount.pending_pve.duplicate(true)
	view.network.socket.close()
	check(await wait_until(func() -> bool: return view.network.pve.ready and (view.network.connection_epoch != connection or view.network.world_epoch != ownership) and not view.network.pve.pending(), 20.0), "Unknown action result recovers automatically after reconnect")
	check(view.network.pve.state.battle.id == battle_id and int(view.network.pve.state.battle.revision) == int(pending.command.expected_revision) + 1, "Reconnect replays exact action once in the same battle")
	await get_tree().create_timer(0.85).timeout
	while view.network.pve.active():
		var battle: Dictionary = view.network.pve.state.battle
		var action := "skill" if int(battle.mp) >= 9 else "attack"
		view.battle_view.choose(action)
		if action == "skill": view.battle_view.skill_picker.activate(view.battle_view.skill_picker.selected_id)
		if not await wait_until(func() -> bool: return not view.network.pve.pending()): break
		await get_tree().create_timer(0.85).timeout
	check(view.network.pve.state.battle.outcome == "victory" and int(view.network.pve.state.progress.kills) == 1, "UI battle awards first wolf progress")
	check(not view.residents.has("wolf_a") and view.network.population.entities.has("wolf_a"), "Defeat filtering is personal while shared population persists")
	if OS.get_environment("SSJX_TEST_PVE_RESPAWN") == "1":
		var completed_id: String = view.network.pve.state.battle.id
		check(await wait_until(func() -> bool: return not view.battle_view.visible, 8.0), "Final action, death and result animation automatically return to the map")
		check(await wait_until(func() -> bool: return view.residents.has("wolf_a"), 35.0), "Real Godot client automatically respawns the wolf after the production 30-second cooldown")
		check(view.screen.hud.get_node("Minimap").shared_population.has("wolf_a") and int(view.network.pve.state.progress.kills) == 1, "Real respawn restores the minimap without resetting quest credit")
		view.resident_selected.emit("wolf_a")
		check(await wait_until(func() -> bool: return view.network.pve.active() and view.battle_view.visible and view.network.pve.state.battle.id != completed_id), "Clicking the returned wolf enters a fresh authoritative battle")
		check(view.network.pve.state.battle.enemy_hp == view.network.pve.state.battle.enemy.hp, "Rematch starts with a full-health monster")
	check(Game.player == old, "Real online gameplay leaves offline progress untouched")
	app.queue_free()
	await get_tree().process_frame
	OnlineAccount.clear()
	print("ONLINE PVE LIVE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
