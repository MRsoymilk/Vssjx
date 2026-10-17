extends Node
var checks := 0
var failures := 0
var capture_prefix := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("DEATH FAIL: " + message)

func _ready() -> void:
	_run.call_deferred()

func capture(suffix: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(capture_prefix + suffix + ".png") == OK, "Rendered death: " + suffix)

func wait_for_enemy(app: Control) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while app.battle_playback == null and Time.get_ticks_msec() < deadline: await get_tree().process_frame

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-death="): capture_prefix = argument.trim_prefix("--capture-death=")
	var saved := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://battle_death_%d.json" % OS.get_process_id()
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	Game.new_player("死亡检查", 1, 0, 1)
	Game.player.hp = 1
	var opponent: Dictionary = ShushanWorld.ENEMIES[0].duplicate(true)
	opponent.attack = 999
	app._enter_world()
	app._start_battle(opponent)
	app._battle_turn("guard")
	await wait_for_enemy(app)
	var motion: BattleActionPlayback = app.battle_playback
	check(motion != null and motion.actor == app.battle_enemy, "Offline lethal round starts with the actual enemy action")
	if motion == null: get_tree().quit(1); return
	motion.advance(motion.impact_time + 0.001)
	check(app.battle.hp == 0 and app.battle_hero.visible and app.battle_death == null, "Lethal impact still shows hurt before death")
	motion.advance(motion.remaining())
	var death: BattleDeathPlayback = app.battle_death
	check(death != null and death.active and not app.battle_hero.visible, "Enemy return replaces the hero with original death ANI")
	check(death.sprite.transform == app.battle_hero.transform and death.sprite.get_parent() == app.battle_hero.get_parent(), "Death preserves the actor station, scale and facing")
	check(not app.battle_ring.visible and not app.battle_hero_hp.visible and not app.battle_hero_mp.visible and not app.battle_hero_status.visible, "Dead hero hides ring, health, mana and ready label")
	check(app.modal == null and not app.battle_committed and int(Game.player.hp) == 1, "Death playback neither settles nor restores the player early")
	var info := OriginalArt.actor_info(BattleDeathPlayback.ART_KEY)
	check(info.count == 10 and death.sprite.sprite_frames.get_frame_count("source_0") == 10 and is_equal_approx(death.duration, 1.0), "All ten original steps retain source durations")
	var first: AtlasTexture = death.sprite.sprite_frames.get_frame_texture("source_0", 0)
	var last: AtlasTexture = death.sprite.sprite_frames.get_frame_texture("source_0", 9)
	check(first.region.position == Vector2(info.width, info.height) and last.region.position == Vector2.ZERO, "Native reversed frame table plays smoke into the tombstone, not backwards")
	death.advance(0.45)
	await capture("-offline-smoke")
	check(app.modal == null and death.sprite.frame == 4, "Mid-animation remains visible before settlement")
	death.advance(death.remaining())
	check(not death.active and death.sprite.frame == 9 and not app.battle_hero.visible, "Completion holds the final tombstone instead of restoring idle")
	await get_tree().create_timer(0.4).timeout
	check(app.modal != null and app.battle_committed and int(Game.player.hp) == int(Game.stats().hp), "Existing defeat restoration/save follows complete death playback")
	await capture("-offline-result")
	app._enter_world()
	check(death.cancelled and death.sprite == null and app.battle_death == null, "Returning to the map removes the death presentation")
	# Leaving mid-death releases the waiting turn without committing an abandoned result.
	Game.player.hp = 1
	app._start_battle(opponent)
	app._battle_turn("guard")
	await wait_for_enemy(app)
	motion = app.battle_playback
	motion.advance(motion.duration)
	death = app.battle_death
	var abandoned: ShushanBattle = app.battle
	app._home()
	await get_tree().create_timer(0.4).timeout
	check(death.cancelled and not abandoned.committed and app.mode == "home", "Scene changes cancel death without stale settlement")
	app.free()
	var model := OnlinePve.new()
	model.ready = true
	model.state = {"character":{"job":1,"gender":1,"level":1,"hp":100,"mp":40,"display_name":"死亡检查"},
		"stats":{"hp":100,"mp":40},"potions":6,
		"battle":{"id":"death-test","revision":"1","outcome":"active","enemy_hp":62,"hp":100,"mp":40,
		"enemy":{"art":"monster/langw","name":"山狼","level":1,"hp":62,"attack":13,"defense":3}}}
	var view: OnlineBattleView = load("res://scenes/ui/online_battle_view.tscn").instantiate()
	add_child(view)
	view.set_process(false)
	view.present(model)
	model.last_action = "guard"
	model.state.battle.revision = "2"
	model.state.battle.hp = 0
	model.state.battle.outcome = "defeat"
	var authoritative := model.state.duplicate(true)
	view.present(model)
	view._process(view._enemy_motion.remaining())
	death = view._hero_death
	check(death != null and death.active and not view.hero.visible and not view.get_node("Result").visible, "Online lethal counter waits for the same original death sequence")
	check(not view.get_node("Hero/Ring").visible and not view.get_node("Hud/BattleHeroHp").visible, "Online death also removes stale character indicators")
	view.return_to_map()
	check(view.visible and view.get_node("Result/Return").disabled, "Direct return or Escape cannot skip the death sequence")
	view._process(0.45)
	await capture("-online-smoke")
	var elapsed := death.elapsed
	view.present(model)
	check(view._hero_death == death and death.elapsed == elapsed, "Repeated authoritative snapshots never restart death")
	view._process(death.remaining())
	check(view.get_node("Result").visible and not view.get_node("Result/Return").disabled and not view.hero.visible, "Online settlement appears after the tombstone is reached")
	check(model.state == authoritative, "Presentation does not alter authoritative HP, rewards or restoration")
	view.return_to_map()
	check(not view.visible and death.cancelled and death.sprite == null, "Online dismissal cleans the held tombstone")
	# A restored connection may initially contain an already-completed defeat.
	view.present(model)
	check(view._hero_death != null and view._hero_death.active and not view.get_node("Result").visible, "An initial defeat snapshot also receives death presentation")
	model.ready = false
	view._process(0.1)
	check(view._hero_death == null and view.hero.visible, "Disconnect cancels pending death safely")
	model.ready = true
	view.present(model)
	check(view._hero_death != null and view._hero_death.active, "Reconnect rebuilds death from the same server snapshot")
	view.free()
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = saved
	print("BATTLE DEATH: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
