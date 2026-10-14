extends Node
## Records the actual battle HUD and both action stages with an isolated save.

var app: Control
var output: String
var seen: Dictionary = {}

func _ready() -> void:
	call_deferred("_capture")

func _capture() -> void:
	output = OS.get_environment("SSJX_TURN_PATH")
	if output.is_empty():
		push_error("Set SSJX_TURN_PATH to an existing screenshot directory")
		get_tree().quit(1)
		return
	Game.save_path = "user://turn_visual_save.json"
	Game.new_player("回合验证", 1, 0)
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	app._enter_world()
	app._start_battle(ShushanWorld.ENEMIES[0])
	app.battle.rng.seed = 42
	app._battle_menu()
	for i in 105:
		if i == 12: app._battle_turn("attack")
		if i > 12 and app.battle.phase == "select" and app.battle.round_number == 1:
			if not app.action_menu.visible: app._battle_menu()
			if i >= 72: app._battle_turn("guard")
		await get_tree().create_timer(1.0 / 15.0).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = get_tree().root.get_texture().get_image()
		frame.save_png(output.path_join("turn_%03d.png" % i))
		var stage: String = app.battle_stage
		# Capture player/enemy after the damage stage has resolved.
		var resolved: bool = stage == "select" or stage == "settlement" or app.battle.phase != stage
		if resolved and not seen.has(stage):
			seen[stage] = true
			frame.save_png(output.path_join("stage_" + stage + ".png"))
		if i > 12 and stage == "select" and app.battle.round_number == 1:
			frame.save_png(output.path_join("stage_next_select.png"))
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	print("TURN SMOKE: 105 actual engine frames; stages: ", seen.keys())
	get_tree().quit()
