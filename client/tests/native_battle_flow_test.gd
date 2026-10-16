extends Node
var checks := 0
var failures := 0
var capture := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	call_deferred("run")

func screenshot(suffix: String) -> void:
	if capture.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(capture + suffix + ".png") == OK, "Actual combat render: " + suffix)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-native-flow="): capture = argument.trim_prefix("--capture-native-flow=")
	var saved := Game.player.duplicate(true)
	var save_path := Game.save_path
	Game.save_path = "user://native_flow_%d.json" % OS.get_process_id()
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	for gender in 2:
		for job in 3:
			Game.new_player("原生动作检查", job, 0, gender)
			var opponent: Dictionary = ShushanWorld.ENEMIES[(job + gender) % 6].duplicate(true)
			opponent.hp = 999
			opponent.attack = 1
			app._enter_world()
			app._start_battle(opponent)
			app.battle.rng.seed = 42
			var home: Vector2 = app.battle_hero.position
			var enemy_home: Vector2 = app.battle_enemy.position
			var hp: int = app.battle.enemy_hp
			app._battle_turn("attack")
			await get_tree().create_timer(0.17).timeout
			var motion: BattleActionPlayback = app.battle_playback
			check(motion != null and motion.active and app.battle.enemy_hp == hp, "Approach starts without early damage for every character")
			if motion == null: continue
			check(app.battle_hero.position != home and not app.battle_hero_hp.visible and not app.battle_ring.visible, "Native approach moves actor and hides stale overhead health/ring")
			var round_number: int = app.battle.round_number
			app._battle_turn("attack")
			check(app.battle.round_number == round_number, "A moving attack owns its complete turn")
			motion.advance(motion.impact_time + 0.001)
			check(app.battle.enemy_hp < hp and app.battle_enemy.animation == "hurt", "Native hit step resolves damage and genuine hurt together")
			check(app.battle_hero.get_index() > app.battle_enemy.get_index(), "Native acting team draws the approaching hero in front")
			check(app.effects_layer.get_parent().get_index() > app.battle_hero.get_index(), "Damage effects and overhead HUD remain above both actors")
			check(absf(app.battle_hero.position.x - enemy_home.x) < 75, "Real battle attacker reaches weapon range")
			if job == 1 and gender == 1: await screenshot("-impact")
			motion.advance(motion.remaining())
			check(app.battle_hero.position == home and app.battle_playback != motion, "Full source sequence returns before enemy acts")
			var response: BattleActionPlayback = app.battle_playback
			check(response != null and response.actor == app.battle_enemy, "Enemy counterattack uses the same native playback")
			response.advance(response.impact_time + 0.001)
			check(app.battle_hero.animation == "hurt" and app.battle_enemy.get_index() > app.battle_hero.get_index(), "Native acting team draws the retaliating monster in front")
			app.battle_hero.set_frame_and_progress(2, 0.0)
			var hero_info := OriginalArt.actor_info(Game.actor_key())
			check(app.battle_hero.offset.x == float(hero_info.origin[0]) + float(hero_info.native_battle.pose_x.hurt[2]), "Actual battle restores native state-6 recoil")
			if job == 1 and gender == 1: await screenshot("-hero-hurt")
			response.advance(response.remaining())
			check(app.battle_enemy.position == enemy_home and app.battle_playback == null, "Enemy also returns before settlement")
			check(app.battle_enemy.get_index() > app.battle_hero.get_index(), "Native completion retains the last acting side until the next action")
			await get_tree().create_timer(0.38).timeout
			check(app.battle.phase == "select" and app.battle_stage == "select", "One complete round returns to command selection")
			if job == 1 and gender == 1: await screenshot("-returned")
	# Original skill IDs remain unknown; reviewed mage casting stays at home.
	Game.new_player("施法检查", 2, 0, 0)
	var opponent: Dictionary = ShushanWorld.ENEMIES[0].duplicate(true)
	opponent.hp = 999
	app._enter_world()
	app._start_battle(opponent)
	var hero_home: Vector2 = app.battle_hero.position
	app._battle_turn("skill")
	await get_tree().create_timer(0.17).timeout
	var casting: BattleActionPlayback = app.battle_playback
	check(casting.action == &"cast" and app.battle_hero.position == hero_home, "Reviewed staff casting does not inherit normal-attack target travel")
	# Leaving during approach releases the coroutine without damage or a stale counterattack.
	var previous_battle: ShushanBattle = app.battle
	var old_hp := previous_battle.enemy_hp
	app._home()
	await get_tree().process_frame
	check(casting.cancelled and previous_battle.enemy_hp == old_hp and app.battle_playback == null and app.mode == "home", "Scene change cancels presentation without resolving a pending hit")
	app._enter_world()
	app._start_battle(opponent)
	app._battle_turn("attack")
	await get_tree().create_timer(0.17).timeout
	var abandoned: BattleActionPlayback = app.battle_playback
	var abandoned_battle: ShushanBattle = app.battle
	app.queue_free()
	await get_tree().process_frame
	check(abandoned.cancelled and abandoned_battle.enemy_hp == int(opponent.hp), "Freeing the entire main scene releases a pending attack without stale damage")
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.save_path = save_path
	Game.player = saved
	print("NATIVE BATTLE FLOW: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
