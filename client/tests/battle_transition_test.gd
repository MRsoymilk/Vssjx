extends Node
var checks := 0
var failures := 0
var output := ""
var trace: Array[Dictionary] = []

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func sample(app: Control, zone: int, index: int) -> void:
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	var overlay: BattleEncounterTransition = app.battle_transition
	var path := "encounter_%d_%03d.png" % [zone, index]
	check(get_tree().root.get_texture().get_image().save_png(output.path_join(path)) == OK, "Encounter render saved")
	trace.append({"zone": zone, "sample": index, "mode": app.mode, "progress": overlay.progress if is_instance_valid(overlay) else 1.0, "path": path})

func _run() -> void:
	output = OS.get_environment("SSJX_ENCOUNTER_CAPTURE_PATH")
	var old_path := Game.save_path
	Game.save_path = "user://battle_transition_%d.json" % OS.get_process_id()
	var before := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	Game.new_player("遇敌演示", 2, 0, 1)
	app._enter_world()
	app._world_interaction("enemy", ShushanWorld.ENEMIES[0])
	check(app.mode == "world" and app.modal != null and app.battle_transition == null, "Quest requirement is checked before the encounter transition")
	app._close_modal()
	for zone in 2:
		Game.new_player("遇敌演示", 2, 0, 1 - zone)
		Game.player.zone = zone
		Game.player.cell = [10, 16] if zone == 0 else [5, 16]
		Game.player.quest = 1 if zone == 0 else 3
		app._enter_world()
		await get_tree().process_frame
		var enemy: Dictionary = ShushanWorld.ENEMIES[0 if zone == 0 else 5]
		var old_battle: ShushanBattle = app.battle
		var resources := {"hp": Game.player.hp, "mp": Game.player.mp, "potions": Game.player.potions, "gold": Game.player.gold, "xp": Game.player.xp}
		app._world_interaction("enemy", enemy)
		check(app.mode == "battle_loading" and app.battle == old_battle, "Encounter is visible before creating the battle")
		check(not app.world.enabled and app.world.path.is_empty() and app.world.hero.animation == "idle", "Loading stops world movement and local patrols")
		var overlay: BattleEncounterTransition = app.battle_transition
		check(overlay != null and overlay.mouse_filter == Control.MOUSE_FILTER_STOP and overlay.warning.text == "!", "Visible encounter warning blocks background clicks")
		check(overlay.caption.text.contains(enemy.name) and overlay.warning_anchor.y - 23 >= 28, "Encounter identifies the actual target without covering top HUD")
		check(BattleEncounterTransition.BAR_RECT.end.y <= 390, "Loading frame stays above the chat panel")
		app._world_interaction("enemy", enemy)
		app._world_interaction("npc", {})
		app._scene_action("menu")
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		app._unhandled_key_input(key)
		app._battle_turn("attack")
		check(app.battle_transition == overlay and app.modal == null and app.mode == "battle_loading", "Repeated encounters, menu, Escape and attack cannot bypass preparation")
		var hero_position: Vector2 = app.world.hero.position
		var monsters: Dictionary = {}
		for id in app.world.enemy_nodes: monsters[id] = app.world.enemy_nodes[id].position
		var previous := 0.0
		var ready_seen := false
		var index := 0
		var deadline := Time.get_ticks_msec() + 18000
		while app.mode == "battle_loading" and Time.get_ticks_msec() < deadline:
			check(overlay.progress >= previous and overlay.progress >= 0.0 and overlay.progress <= 1.0, "Resource progress is bounded and never regresses")
			previous = overlay.progress
			if overlay.progress == 1.0: ready_seen = true
			check(app.world.hero.position == hero_position, "Encounter overlay never permits extra player displacement")
			for id in monsters: check(app.world.enemy_nodes[id].position == monsters[id], "Personal monsters remain paused during preparation")
			await sample(app, zone, index)
			index += 1
			await get_tree().create_timer(1.0 / 30.0).timeout
		check(app.mode == "battle" and app.battle.enemy.id == enemy.id and app.battle.round_number == 0, "Prepared encounter enters exactly the intended battle at round zero")
		check(ready_seen and app.battle_transition == null and not app.action_menu.visible, "Completion removes loading UI without opening commands or auto-attacking")
		for field in resources: check(Game.player[field] == resources[field], "Encounter presentation never spends resources or awards loot")
		var required: Array[String]=[Game.appearance_key(),String(enemy.art),BattleDeathPlayback.ART_KEY]
		required.append_array(BattleEffects.preload_keys(int(Game.player.job),int(Game.player.school),int(Game.player.level)))
		required.append_array(BattleResultView.ART_KEYS)
		check(required.all(func(key:String)->bool:return OriginalArt.cached.has(key)), "Battle actors, mapped spells, death and outcome SpriteFrames are really prepared")
		await sample(app, zone, index)
		app._home()
		await get_tree().process_frame
	# Abandoning the world invalidates the old async preparation, even when it finishes later.
	Game.new_player("取消验证", 2, 0)
	Game.player.quest = 1
	app._enter_world()
	app._world_interaction("enemy", ShushanWorld.ENEMIES[0])
	app._home()
	await get_tree().create_timer(0.6).timeout
	check(app.mode == "home" and app.battle_transition == null and app.world == null, "Cancelled preparation cannot reopen a battle or touch the disposed world")
	app._enter_world()
	app._world_interaction("enemy", ShushanWorld.ENEMIES[0])
	var late_deadline := Time.get_ticks_msec() + 5000
	while app.mode == "battle_loading" and app.battle_transition.progress == 0.0 and Time.get_ticks_msec() < late_deadline: await get_tree().process_frame
	check(app.mode == "battle_loading" and app.battle_transition.progress > 0.0, "Cancellation fixture reaches actual cache preparation")
	var preparation: PlatformResourceRequest = app.battle_resource_request
	check(preparation != null and preparation.generation == app.battle_transition_epoch, "Encounter uses the platform resource request with its own generation")
	app._home()
	check(app.battle_resource_request == null, "Leaving the world releases its resource request handle")
	await get_tree().create_timer(0.4).timeout
	check(app.mode == "home" and app.battle_transition == null, "Cancellation during cache preparation rejects its late continuation")
	app._enter_world()
	app._world_interaction("enemy", ShushanWorld.ENEMIES[0])
	app._start_battle(ShushanWorld.ENEMIES[1])
	await get_tree().create_timer(0.5).timeout
	check(app.mode == "battle" and app.battle.enemy.id == ShushanWorld.ENEMIES[1].id and app.battle.round_number == 0, "Old preparation cannot replace a newer battle")
	# A missing local texture is a recoverable error, not a fake completed battle.
	Game.new_player("资源验证", 2, 0)
	Game.player.quest = 1
	app._enter_world()
	var art := String(ShushanWorld.ENEMIES[0].art)
	var old_texture: String = OriginalArt.catalog[art].texture
	OriginalArt.catalog[art].texture = "res://assets/actors/%s.png" % "missing-fixture-texture"
	app._world_interaction("enemy", ShushanWorld.ENEMIES[0])
	await get_tree().create_timer(0.4).timeout
	OriginalArt.catalog[art].texture = old_texture
	check(app.mode == "world" and app.modal != null and app.battle_transition == null, "Missing assets show a recoverable message, not fake loading success")
	app._close_modal()
	check(app.world.enabled and int(Game.player.gold) == 30 and int(Game.player.potions) == 6, "Closing preparation error restores play without deductions")
	# Progress itself clamps malformed/backwards values without timer-driven fake percentages.
	var progress: BattleEncounterTransition = load("res://scenes/ui/battle_encounter_transition.tscn").instantiate()
	app.ui.add_child(progress)
	progress.configure("测试", Vector2(-100, -100))
	progress.set_progress(0.7, "准备动作")
	progress.set_progress(0.1, "准备动作")
	check(is_equal_approx(progress.progress, 0.7), "Late progress observations cannot move the bar backwards")
	progress.set_progress(2.0, "准备就绪")
	check(progress.progress == 1.0 and progress.warning_anchor.x >= 25 and progress.warning_anchor.y >= 60, "Progress and encounter marker stay within viewport bounds")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("encounter_trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(trace, "\t"))
		file.close()
	app.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = before
	print("BATTLE TRANSITION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
