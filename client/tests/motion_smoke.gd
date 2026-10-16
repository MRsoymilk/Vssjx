extends Node
## Actual-engine capture of stand, right walk, left walk and return to stand.
var app: Control
var output := ""
var index := 0

func _ready() -> void:
	call_deferred("_capture")

func frames(count: int) -> void:
	for i in count:
		await get_tree().create_timer(1.0 / 15.0).timeout
		await RenderingServer.frame_post_draw
		var frame: Image = app.viewport.get_texture().get_image()
		frame.get_region(Rect2i(115, 108, 90, 96)).save_png(output.path_join("motion_%03d.png" % index))
		index += 1

func _capture() -> void:
	output = OS.get_environment("SSJX_MOTION_PATH")
	if output.is_empty():
		get_tree().quit(1)
		return
	Game.save_path = "user://motion_test_save.json"
	var variant := clampi(int(OS.get_environment("SSJX_MOTION_VARIANT")), 0, 5) if OS.has_environment("SSJX_MOTION_VARIANT") else 2
	Game.new_player("行走验证", variant / 2, 0, variant % 2)
	Game.player.cell = [14, 17]
	await Game.save_game()
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	app._enter_world()
	await frames(9)
	for x in range(15, 21): app.world.path.append(Vector2i(x, 17))
	await frames(27)
	for x in range(19, 13, -1): app.world.path.append(Vector2i(x, 17))
	await frames(27)
	await frames(9)
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	print("MOTION SMOKE: %d actual-engine frames saved" % index)
	get_tree().quit()
