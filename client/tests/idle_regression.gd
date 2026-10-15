extends Node
## Exercise the real AnimatedSprite2D clock, not just its animation name.
var checks := 0
var failures := 0
var worlds: Array[ShushanWorld] = []
var previews: Array[AnimatedSprite2D] = []
var positions: Array[Vector2] = []
var output := ""

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func check_idle(sprite: AnimatedSprite2D, description: String) -> void:
	check(sprite.animation == "idle" and sprite.is_playing(), description + " is playing idle")
	check(sprite.sprite_frames.get_animation_loop("idle") and sprite.sprite_frames.get_frame_count("idle") == 2, description + " has a real two-frame loop")
	check(sprite.sprite_frames.get_frame_texture("idle", 0) != sprite.sprite_frames.get_frame_texture("idle", 1), description + " uses different poses")

func capture(name_value: String) -> void:
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_value + ".png")) == OK, "Save idle capture")

func _run() -> void:
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://idle_regression_save.json"
	output = OS.get_environment("SSJX_IDLE_CAPTURE_PATH")
	if not output.is_empty() and DisplayServer.get_name() == "headless":
		push_error("Idle captures require a real renderer")
		get_tree().quit(1)
		return
	var stems := ["mzs", "wzs", "mck", "wck", "mfs", "wfs"]
	for variant in stems.size():
		Game.new_player("待机验证", variant / 2, 0, variant % 2)
		Game.player.cell = [16, 17]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(320, 375)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var world := ShushanWorld.new()
		viewport.add_child(world)
		world.set_process(false)
		worlds.append(world)
		positions.append(world.hero.position)
		check_idle(world.hero, stems[variant] + " world actor")
		var preview := OriginalArt.actor("creation/" + stems[variant])
		preview.position = Vector2(55 + variant % 3 * 105, 215 + variant / 3 * 160)
		preview.scale = Vector2(2, 2)
		add_child(preview)
		previews.append(preview)
		check_idle(preview, stems[variant] + " creation preview")
	# Sample both original standing poses deterministically for optional visual QA.
	for pose in 2:
		for preview in previews:
			preview.pause()
			preview.set_frame_and_progress(pose, 0.0)
		await capture("idle_pose_%d" % pose)
	for preview in previews:
		preview.set_frame_and_progress(0, 0.0)
		preview.play("idle")
	for world in worlds:
		world.hero.set_frame_and_progress(0, 0.0)
	# Repeated idle updates must not restart the breathing cycle every frame.
	var until := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < until:
		for world in worlds: world._process(1.0 / 60.0)
		await get_tree().process_frame
	for variant in stems.size():
		var world := worlds[variant]
		check(world.hero.frame == 1 and previews[variant].frame == 1, stems[variant] + " actual idle clock advances to the second pose")
		check(world.hero.position == positions[variant] and world.hero.scale.x == 1.0, stems[variant] + " idle does not move or turn the actor")
		world.hero.pause()
		world._idle_hero()
		check(world.hero.is_playing(), stems[variant] + " paused idle resumes")
		world.path.append(world.cell + Vector2i.RIGHT)
		world._process(16.0 / ShushanWorld.WALK_SPEED)
		check(world.hero.animation == "idle" and world.hero.is_playing() and world.next_cell.x < 0, stems[variant] + " walking finishes in a playing idle state")
		positions[variant] = world.hero.position
		world.hero.set_frame_and_progress(0, 0.0)
	until = Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < until:
		for world in worlds: world._process(1.0 / 60.0)
		await get_tree().process_frame
	for variant in stems.size():
		check(worlds[variant].hero.frame == 1 and worlds[variant].hero.position == positions[variant], stems[variant] + " post-walk idle animates in place")
	Game.player = old_player
	Game.save_path = old_path
	print("IDLE REGRESSION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
