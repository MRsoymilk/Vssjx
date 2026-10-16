extends Node2D

const VIEW := preload("res://scenes/ui/online_battle_view.tscn")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func state() -> Dictionary:
	return {"character": {"job":1,"gender":0,"level":1,"hp":100,"mp":40,"display_name":"Test"},
		"stats":{"hp":100,"mp":40},"potions":6,
		"battle":{"id":"first","revision":"1","outcome":"active","enemy_hp":62,"hp":100,"mp":40,
		"enemy":{"art":"monster/langw","name":"Wolf","level":1,"hp":62,"attack":13,"defense":3}}}

func _ready() -> void:
	var player_before := Game.player.duplicate(true)
	var model := OnlinePve.new()
	model.state = state()
	model.ready = true
	var view := VIEW.instantiate()
	add_child(view)
	view.set_process(false)
	view.present(model)
	check(view.enemy.animation == "idle", "Entering battle does not fake a hit")
	model.last_action = "attack"
	model.state.battle.revision = "2"
	model.state.battle.enemy_hp = 50
	view.present(model)
	check(view.enemy.animation == "hurt" and view.hero.animation == "attack", "Player strike triggers wolf hurt, not wolf attack")
	check(view._enemy_attack_delay > 0 and not view.get_node("Hud/ActionMenu").visible, "Counterattack is queued while impact plays")
	view._process(0.1)
	check(view.enemy.animation == "hurt", "Early turn time cannot overwrite hurt with attack")
	view._process(view._enemy_attack_delay + 0.01)
	check(view.enemy.animation == "attack" and view.animation_time > 0, "Counterattack follows player action and hurt")
	model.state.battle.revision = "3"
	model.state.battle.enemy_hp = 38
	view.present(model)
	model.ready = false
	view._process(10)
	check(view._enemy_attack_delay == 0 and view.enemy.animation != "attack", "Disconnection cancels queued retaliation")
	model.ready = true
	model.state = state()
	model.state.battle.id = "second"
	view.present(model)
	check(view._enemy_attack_delay == 0 and view.animation_time == 0 and view.enemy.animation == "idle", "A new battle clears old reaction state")
	model.state.battle.revision = "2"
	view.present(model)
	check(view.enemy.animation == "attack", "No damage does not trigger a hurt reaction")
	model.state.battle.revision = "3"
	model.state.battle.enemy_hp = 0
	model.state.battle.outcome = "victory"
	view.present(model)
	check(view.enemy.animation == "hurt" and view._enemy_attack_delay == 0, "Defeated wolf cannot retaliate")
	view.queue_free()
	await get_tree().process_frame
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(900, 400)
	RenderingServer.set_default_clear_color(Color("17242e"))
	for row in 2:
		for column in 3:
			var mode: String = ["attack", "hurt", "idle"][column]
			var label := Label.new()
			label.text = mode.to_upper() + (" / LEFT" if row == 0 else " / RIGHT")
			label.position = Vector2(column * 300 + 70, row * 190 + 15)
			add_child(label)
			var actor := OriginalArt.actor("monster/langw")
			add_child(actor)
			actor.position = Vector2(column * 300 + 155, row * 190 + 175)
			actor.scale = Vector2(3 if row == 0 else -3, 3)
			actor.play(mode)
			actor.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Rendered attack/hurt separation")
	check(Game.player == player_before, "Reaction presentation leaves player rules unchanged")
	print("Wolf reactions: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
