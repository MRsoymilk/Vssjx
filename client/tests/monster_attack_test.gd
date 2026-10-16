extends Node2D

const MONSTERS := ["langw", "xt1", "hs1", "nt1"]
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func label_at(value: String, point: Vector2, font_size: int = 15) -> void:
	var label := Label.new()
	label.text = value
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)

func _ready() -> void:
	var player_before := Game.player.duplicate(true)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(1080, 810)
	RenderingServer.set_default_clear_color(Color("17242e"))
	var playing: Array[AnimatedSprite2D] = []
	for name in MONSTERS:
		for facing in [1.0, -1.0]:
			var actor := OriginalArt.actor("monster/" + name)
			add_child(actor)
			actor.position = Vector2(100, 100)
			actor.scale = Vector2(facing, 1)
			var info := OriginalArt.actor_info("monster/" + name)
			check(not actor.sprite_frames.get_animation_loop("attack"), name + " attack is one-shot")
			check(actor.sprite_frames.get_animation_loop("idle") and actor.sprite_frames.get_frame_count("idle") > 1, name + " returns to animated idle")
			check(actor.sprite_frames.get_frame_count("attack") == info.playback.attack.size(), name + " keeps original attack timings")
			for index in info.playback.attack.size():
				var texture: AtlasTexture = actor.sprite_frames.get_frame_texture("attack", index)
				var frame := int(info.playback.attack[index][0])
				check(texture.region.position == Vector2((frame % int(info.columns)) * int(info.width), (frame / int(info.columns)) * int(info.height)), name + " loads corrected attack region")
			actor.play("attack")
			playing.append(actor)
			if name == "langw":
				var hurt := OriginalArt.actor("monster/" + name)
				add_child(hurt)
				hurt.position = Vector2(100, 100)
				hurt.scale = Vector2(facing, 1)
				check(hurt.sprite_frames.has_animation("hurt") and not hurt.sprite_frames.get_animation_loop("hurt"), "Wolf has an independent one-shot hurt state")
				hurt.play("hurt")
				playing.append(hurt)
	await get_tree().create_timer(2.1).timeout
	for actor in playing:
		check(actor.animation == "idle", "Attack finishes and returns to idle")
		check(actor.position == Vector2(100, 100) and absf(actor.scale.x) == 1 and not actor.flip_h, "Attack does not move actor or change facing")
		actor.queue_free()
	await get_tree().process_frame
	for column in 4:
		label_at(["IDLE", "ATTACK START", "ATTACK MID", "ATTACK END"][column], Vector2(column * 270 + 62, 12), 18)
	for row in 8:
		var name: String = MONSTERS[row % 4]
		var facing := 1.0 if row < 4 else -1.0
		label_at(name + (" / LEFT" if facing > 0 else " / RIGHT"), Vector2(10, 41 + row * 94))
		for column in 4:
			var actor := OriginalArt.actor("monster/" + name)
			add_child(actor)
			actor.position = Vector2(145 + column * 270, 124 + row * 94)
			actor.scale = Vector2(1.4 * facing, 1.4)
			actor.play("idle" if column == 0 else "attack")
			var count := actor.sprite_frames.get_frame_count("attack")
			if column > 0:
				actor.set_frame_and_progress(0 if column == 1 else (count / 2 if column == 2 else count - 1), 0)
			actor.pause()
	await get_tree().process_frame
	await get_tree().process_frame
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and DisplayServer.get_name() != "headless":
			RenderingServer.force_draw()
			check(get_viewport().get_texture().get_image().save_png(argument.trim_prefix("--capture=")) == OK, "Rendered all monster attacks in both facings")
	check(Game.player == player_before, "Preview leaves player state unchanged")
	print("Monster attacks: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
