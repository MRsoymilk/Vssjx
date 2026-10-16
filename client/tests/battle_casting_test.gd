extends Node
## Actual battle UI, rendered actor frames and independent test save only.
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

func _run() -> void:
	output = OS.get_environment("SSJX_BATTLE_CAPTURE_PATH")
	var old_path := Game.save_path
	Game.save_path = "user://battle_casting_%d.json" % OS.get_process_id()
	var before := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	for gender in 2:
		Game.new_player("法杖演示", 2, 0, gender)
		Game.player.hp = 50
		app._enter_world()
		var enemy: Dictionary = ShushanWorld.ENEMIES[0].duplicate(true)
		enemy.hp = 300
		enemy.attack = 1
		app._start_battle(enemy)
		app.battle.rng.seed = 42
		check(app.battle_hero.animation == "idle" and not app.battle_move_callout.visible, "Idle mage has no looping attack or stale move name")
		check(not app.battle_hero.sprite_frames.get_animation_loop("cast"), "Staff flourish plays once")
		check(is_equal_approx(app._battle_action_duration(app.battle_hero, &"cast"), 0.75), "Battle timing uses cast sequence duration")
		app.battle.mp = 0
		app._battle_turn("skill")
		check(app.battle.round_number == 0 and not app.battle_move_callout.visible, "Rejected skill shows no misleading announcement")
		app.battle.mp = int(Game.stats().mp)
		for command in ["skill", "attack"]:
			var round_before: int = app.battle.round_number
			var mp_before: int = app.battle.mp
			app._battle_turn(command)
			check(app.battle_move_callout.visible and app.battle_move_callout.caption.text == ShushanBattle.action_name(command, 2), "Move name matches the action and combat log")
			check(app.battle_move_callout.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Move bubble cannot consume battle input")
			var rect: Rect2 = app.battle_move_callout.get_rect()
			check(rect.position.y >= 28 and rect.end.x <= 320 and rect.end.y < app.battle_hero.position.y - 60, "Bubble fits scene above the hero and health bars")
			var seen_frames: Dictionary = {}
			for index in 30:
				await get_tree().create_timer(1.0 / 30.0).timeout
				var expected := "cast" if command == "skill" else "attack"
				if app.battle_hero.animation == expected: seen_frames[app.battle_hero.frame] = true
				if index == 6:
					check(app.battle_hero.animation == expected, "Mage uses the correct non-looping staff animation")
					check(app.battle.round_number == round_before + 1 and app.battle_stage == "player", "One accepted action owns the player stage")
					app._battle_turn(command)
					check(app.battle.round_number == round_before + 1, "Repeated submission cannot overlap the animation")
				if not output.is_empty():
					await RenderingServer.frame_post_draw
					var path := "%d_%s_%02d.png" % [gender, command, index]
					check(get_tree().root.get_texture().get_image().save_png(output.path_join(path)) == OK, "Rendered frame saved")
					trace.append({"gender": gender, "command": command, "sample": index, "animation": String(app.battle_hero.animation), "frame": app.battle_hero.frame, "stage": app.battle_stage, "bubble": app.battle_move_callout.visible, "path": path})
			var deadline := Time.get_ticks_msec() + 5000
			while app.battle.phase != "select" and Time.get_ticks_msec() < deadline: await get_tree().process_frame
			check(app.battle.phase == "select" and app.battle_hero.animation == "idle", "Completed action returns to a stable ready pose")
			check(seen_frames.size() >= 4, "Actual engine advances through distinct staff poses")
			check(not app.battle_move_callout.visible and app.battle.mp == mp_before - (9 if command == "skill" else 0), "Bubble clears without extra resource consumption")
			check(app.battle_log.text.contains("摄灵诀") if command == "skill" else app.battle_log.text.contains("挥杖"), "Mage combat text describes the actual move")
		app._home()
		await get_tree().process_frame
	# Other jobs use the same authoritative move names, not the reference's unimplemented skill.
	for job in 3: check(ShushanBattle.action_name("skill", job) == ShushanBattle.SKILL_NAMES[job], "Skill callouts share names with battle resolution")
	var bubble: BattleMoveCallout = load("res://scenes/ui/battle_move_callout.tscn").instantiate()
	app.ui.add_child(bubble)
	bubble.present("摄灵诀", Vector2(3, 100), 1.0)
	check(bubble.position.x >= 0 and bubble.position.x + bubble.size.x <= 320, "Edge-anchored bubble is clamped inside the viewport")
	bubble.clear()
	check(not bubble.visible, "Clearing the announcement immediately hides it")
	var station := Node2D.new()
	station.position = Vector2(30, 20)
	station.scale = Vector2(1.5, 1.5)
	app.ui.add_child(station)
	var subject := Node2D.new()
	subject.position = Vector2(140, 160)
	station.add_child(subject)
	bubble.present_for("剑击", subject, 1.0)
	check(is_equal_approx(bubble.position.x + bubble.tail_x, 240.0), "Attached bubble converts a scaled station into UI coordinates")
	var before_move := bubble.position
	subject.position.x = 100
	bubble._process(0.1)
	check(bubble.position.x < before_move.x and is_equal_approx(bubble.position.x + bubble.tail_x, 180.0), "Normal bubble processing follows the moving actor")
	check(is_equal_approx(bubble.remaining, 0.9), "Reanchoring does not restart the announcement lifetime")
	subject.scale.x = -1.0
	bubble._process(0.0)
	check(bubble.scale == Vector2.ONE and bubble.caption.scale == Vector2.ONE and is_equal_approx(bubble.position.x + bubble.tail_x, 180.0), "Actor facing never mirrors the move name")
	for edge in [3.0, 317.0]:
		subject.global_position.x = edge
		bubble._process(0.0)
		check(bubble.position.x >= 4 and bubble.get_rect().end.x <= 316 and bubble.tail_x >= 10 and bubble.tail_x <= bubble.size.x - 10, "Following at a screen edge keeps the bubble and pointer in bounds")
	subject.free()
	bubble._process(0.0)
	check(not bubble.visible and bubble.remaining == 0.0, "Freed actor clears the attached announcement without stale access")
	station.free()
	bubble.present("摄灵诀", Vector2(160, 100), 0.2)
	bubble._process(0.3)
	check(not bubble.visible, "A reused static announcement still expires normally")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("casting_trace.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(trace, "\t"))
		file.close()
	app.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = before
	print("BATTLE CASTING: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
