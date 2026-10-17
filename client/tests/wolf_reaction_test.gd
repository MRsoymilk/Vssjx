extends Node2D

const VIEW := preload("res://scenes/ui/online_battle_view.tscn")
var checks := 0
var failures := 0
var capture_prefix := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func capture(suffix: String) -> void:
	if capture_prefix.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	RenderingServer.force_draw()
	check(get_viewport().get_texture().get_image().save_png(capture_prefix + suffix + ".png") == OK, "Rendered overlapping battle actors: " + suffix)

func state(art_key: String) -> Dictionary:
	return {"character": {"job":1,"gender":0,"level":1,"hp":100,"mp":40,"display_name":"Test"},
		"stats":{"hp":100,"mp":40},"potions":6,
		"battle":{"id":"first","revision":"1","outcome":"active","enemy_hp":62,"hp":100,"mp":40,
		"enemy":{"art":art_key,"name":"Wolf","level":1,"hp":62,"attack":13,"defense":3}}}

func level_offsets(view: OnlineBattleView) -> Array[Vector2]:
	return [view.get_node("Hud/Level").get_global_transform_with_canvas().origin - view.hero.get_global_transform_with_canvas().origin,
		view.get_node("EnemyLevel").get_global_transform_with_canvas().origin - view.enemy.get_global_transform_with_canvas().origin]

func check_levels(view: OnlineBattleView, offsets: Array[Vector2], stage: String) -> void:
	var current := level_offsets(view)
	check(current[0].distance_to(offsets[0]) < 0.01, "Player level follows actor: " + stage)
	check(current[1].distance_to(offsets[1]) < 0.01, "Monster level follows actor: " + stage)
	check(view.get_node("EnemyLevel").scale == Vector2.ONE and view.get_node("Hud/Level").scale == Vector2.ONE,
		"Level text keeps its size and does not inherit the mirrored monster transform: " + stage)

func check_reactions(art_key: String) -> void:
	var model := OnlinePve.new()
	model.state = state(art_key)
	model.state.character.gender = 1
	model.ready = true
	var view := VIEW.instantiate()
	add_child(view)
	if art_key != "monster/langw":
		view.position += Vector2(11, 7)
		view.scale = Vector2(1.15, 0.9)
	view.set_process(false)
	view.present(model)
	var offsets := level_offsets(view)
	check(view.enemy.animation == "idle", "Entering battle does not fake a hit")
	model.last_action = "attack"
	model.state.battle.revision = "2"
	model.state.battle.enemy_hp = 50
	model.state.battle.hp = 96
	view.present(model)
	check(view.enemy.animation == "idle" and view.hero.animation == "attack" and view.hero.position != Vector2.ZERO, "Approach begins before native impact; target is not hit early")
	check_levels(view, offsets, "player approach / " + art_key)
	check(view._enemy_attack_delay > 0 and not view.get_node("Hud/ActionMenu").visible, "Counterattack is queued while impact plays")
	view._process(view._hero_motion.impact_time - 0.01)
	check(view.enemy.animation == "idle", "Target stays idle until native hit step")
	view._process(0.02)
	check_levels(view, offsets, "player impact / " + art_key)
	check(view.enemy.animation == "hurt", "Native hit step triggers the independent hurt sequence")
	check(view.get_node("Hero").get_index() > view.get_node("Enemy").get_index(), "Native acting team puts the player attack in front")
	if art_key == "monster/langw": await capture("-online-monster-hurt")
	view._process(view._enemy_attack_delay + 0.01)
	check_levels(view, offsets, "monster approach / " + art_key)
	check(view.enemy.animation == "attack" and view.animation_time > 0 and view.hero.position == Vector2.ZERO, "Counterattack follows complete player return")
	view._process(view._enemy_motion.impact_time + 0.001)
	check_levels(view, offsets, "monster impact / " + art_key)
	check(view.get_node("Enemy").get_index() > view.get_node("Hero").get_index(), "Native acting team puts the monster retaliation in front")
	check(view.hero.animation == "hurt", "Defender displays the genuine hurt sequence")
	view.hero.set_frame_and_progress(2, 0.0)
	check(view.hero.offset.x == float(OriginalArt.actor_info("hero/wck").origin[0]) + 7.0, "Female knight preserves native recoil at hurt frame two")
	check(view.get_node("Hud").get_index() > view.get_node("Enemy").get_index(), "HUD and impact effects remain above the online actors")
	if art_key == "monster/langw": await capture("-online-hero-hurt")
	view._process(view._enemy_motion.remaining() + 0.01)
	check(view.enemy.position == Vector2.ZERO and view.enemy.animation == "idle", "Counterattack also returns to its original station")
	check_levels(view, offsets, "return to stations / " + art_key)
	check(view.get_node("Hero").get_index() < view.get_node("Enemy").get_index(), "Online counterattack restores the original station order")
	model.state.battle.revision = "3"
	model.state.battle.enemy_hp = 38
	view.present(model)
	model.ready = false
	view._process(10)
	check_levels(view, offsets, "disconnect cancels player approach / " + art_key)
	check(view._enemy_attack_delay == 0 and view.enemy.animation != "attack", "Disconnection cancels queued retaliation")
	check(view.get_node("Hero").get_index() < view.get_node("Enemy").get_index(), "Disconnection restores drawing order")
	model.ready = true
	model.state = state(art_key)
	model.state.battle.id = "second"
	view.present(model)
	check(view._enemy_attack_delay == 0 and view.animation_time == 0 and view.enemy.animation == "idle", "A new battle clears old reaction state")
	model.state.battle.revision = "2"
	view.present(model)
	check(view.enemy.animation == "idle", "No damage does not trigger a fake hurt reaction")
	view._process(view._hero_motion.remaining() + 0.001)
	check(view.enemy.animation == "attack", "A miss still waits for the player return before retaliation")
	model.state.battle.revision = "3"
	model.state.battle.enemy_hp = 0
	model.state.battle.outcome = "victory"
	view.present(model)
	view._process(view._hero_motion.impact_time + 0.01)
	check(view.enemy.animation == "hurt" and view._enemy_attack_delay == 0, "Defeated monster cannot retaliate")
	view._process(view._hero_motion.remaining() + 0.01)
	check(view.hero.position == Vector2.ZERO and not view.get_node("Result").visible and view._enemy_death != null, "Attacker returns before monster death starts")
	view._process(view._enemy_death.remaining())
	check(view.get_node("Result").visible and not view.enemy.visible, "Victory waits for the monster tombstone")
	model.state = state(art_key)
	model.state.battle.id = "lethal_counter"
	view.present(model)
	model.state.battle.revision = "2"
	model.state.battle.enemy_hp = 50
	model.state.battle.hp = 0
	model.state.battle.outcome = "defeat"
	view.present(model)
	view._process(view._hero_motion.remaining() + 0.001)
	check(view.enemy.animation == "attack" and not view.get_node("Result").visible, "A lethal counterattack still plays before defeat is shown")
	view._process(view._enemy_motion.remaining() + 0.001)
	check(view.enemy.position == Vector2.ZERO and not view.get_node("Result").visible and view._hero_death != null and view.get_node("Hud/BattleHeroHp").value == 0, "Lethal counterattack returns before original death animation")
	view._process(view._hero_death.remaining() + 0.001)
	check(view.get_node("Result").visible and not view.hero.visible, "Defeat settlement waits for death animation and retains its tombstone")
	model.state = state(art_key)
	model.state.battle.id = "guard_reflection"
	view.present(model)
	model.last_action = "guard"
	model.state.battle.revision = "2"
	model.state.battle.enemy_hp = 0
	model.state.battle.outcome = "victory"
	view.present(model)
	check(view.enemy.animation == "attack" and not view.get_node("Result").visible, "Guard reflection victory includes the original enemy strike")
	view._process(view._enemy_motion.remaining() + 0.001)
	check(view.enemy.position == Vector2.ZERO and not view.get_node("Result").visible and view._enemy_death != null, "Reflected monster returns before death starts")
	view._process(view._enemy_death.remaining())
	check(view.get_node("Result").visible and not view.enemy.visible, "Reflected victory settles after the monster tombstone")
	# Sample a whole native attack, including each approach/strike/return frame.
	model.state = state(art_key)
	model.state.battle.id = "level_tracking"
	view.present(model)
	check_levels(view, offsets, "replacement battle / " + art_key)
	model.state.battle.revision = "2"
	view.present(model)
	while view.animation_time > 0:
		view._process(0.025)
		check_levels(view, offsets, "native step / " + art_key)
	model.state.battle.revision = "3"
	view.present(model)
	model.ready = false
	view._process(0.01)
	check_levels(view, offsets, "disconnect cancels monster approach / " + art_key)
	view.queue_free()
	await get_tree().process_frame

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-battle-layers="): capture_prefix = argument.trim_prefix("--capture-battle-layers=")
	var player_before := Game.player.duplicate(true)
	var count := 0
	OriginalArt.has_actor("monster/langw")
	for key in OriginalArt._index:
		if String(key).begins_with("monster/"):
			await check_reactions(key)
			count += 1
	check(count == 4, "Every registered runtime monster was tested")
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(900, 920)
	RenderingServer.set_default_clear_color(Color("17242e"))
	var names := ["langw", "xt1", "hs1", "nt1"]
	for row in 8:
		for column in 3:
			var mode: String = ["attack", "hurt", "idle"][column]
			var label := Label.new()
			label.text = names[row % 4] + " " + mode.to_upper() + (" / L" if row < 4 else " / R")
			label.position = Vector2(column * 300 + 35, row * 112 + 10)
			add_child(label)
			var actor := OriginalArt.actor("monster/" + names[row % 4])
			add_child(actor)
			actor.position = Vector2(column * 300 + 155, row * 112 + 107)
			actor.scale = Vector2(1.5 if row < 4 else -1.5, 1.5)
			actor.play(mode)
			actor.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Rendered attack/hurt separation")
	check(Game.player == player_before, "Reaction presentation leaves player rules unchanged")
	print("Monster reactions: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
