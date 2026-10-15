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
	app._enter_online_world(own_id)
	view = app.ui.get_node("OnlineWorld")
	check(await wait_until(func() -> bool: return view.network.world_ready and view.network.pve.ready and view.residents.size() == 5), "Real server negotiates population and private quest state")
	if not view.network.pve.ready: get_tree().quit(1); return
	view.screen.chrome.get_node("Properties").pressed.emit()
	check(view.attributes.visible and view.attributes.snapshot.name == view.network.pve.state.character.display_name, "Real online header opens original attributes with server identity")
	check(view.attributes.numbers.hp.value == "%d/%d" % [int(view.network.pve.state.character.hp), int(view.network.pve.state.stats.hp)], "Real attributes use authoritative health maximum")
	view.attributes.get_node("Back").pressed.emit()
	view.resident_selected.emit("qingwei")
	view.encounter.get_node("Panel/Primary").pressed.emit()
	check(await wait_until(func() -> bool: return int(view.network.pve.state.character.quest_stage) == 1), "NPC UI automatically approaches and accepts quest on server")
	check(not view.encounter.visible and not view.network.pve.pending(), "Confirmed receipt closes NPC panel")
	view.resident_selected.emit("wolf_a")
	view.encounter.get_node("Panel/Primary").pressed.emit()
	check(await wait_until(func() -> bool: return view.network.pve.active(), 30.0), "Moving monster can be approached and challenged through UI")
	check(view.battle_view.visible and view.chat_panel.visible, "Real encounter shares original bottom chat")
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
		if action == "skill": view.battle_view.get_node("Choice/Use").pressed.emit()
		if not await wait_until(func() -> bool: return not view.network.pve.pending()): break
		await get_tree().create_timer(0.85).timeout
	check(view.network.pve.state.battle.outcome == "victory" and int(view.network.pve.state.progress.kills) == 1, "UI battle awards first wolf progress")
	check(not view.residents.has("wolf_a") and view.network.population.entities.has("wolf_a"), "Defeat filtering is personal while shared population persists")
	check(Game.player == old, "Real online gameplay leaves offline progress untouched")
	app.queue_free()
	await get_tree().process_frame
	OnlineAccount.clear()
	print("ONLINE PVE LIVE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
