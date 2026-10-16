extends "res://tests/shared_interface_test.gd"

func verify_ring(ring: Node2D, actor: Node2D, message: String) -> void:
	ring._process(0.0)
	check(ring.scene_file_path == "res://scenes/actors/player_ring.tscn" and ring.show_behind_parent, "Original ring draws below its actor: " + message)
	var visual: AnimatedSprite2D = ring._visual_actor
	var expected := actor.global_position
	if visual != null:
		var poses: Dictionary = visual.get_meta("ground_pose_x", {})
		var steps: Array = poses.get(String(visual.animation), poses.get("idle", []))
		var offset := 0.0 if visual.get_meta("native_ground_anchor", false) or steps.is_empty() else -float(steps[mini(visual.frame, steps.size() - 1)])
		expected = visual.to_global(Vector2(offset, 0))
	check(ring.global_position.is_equal_approx(expected), "Ring follows the compensated foot anchor: " + message)
	check(ring.global_transform.x.is_equal_approx(Vector2.RIGHT) and ring.global_transform.y.is_equal_approx(Vector2.DOWN), "Facing and actor scaling preserve ring pixels: " + message)
	var animation: AnimatedSprite2D = ring.get_node("Animation")
	check(animation.sprite_frames.get_frame_count("idle") == 4 and animation.sprite_frames.get_animation_loop("idle") and animation.is_playing(), "Four original animation steps loop: " + message)
	var texture: AtlasTexture = animation.sprite_frames.get_frame_texture("idle", 0)
	check(texture.region == Rect2(90, 0, 30, 16) and animation.offset == Vector2(-15, -10), "Native ring origin and first frame are preserved: " + message)

func _run() -> void:
	await Game.when_ready()
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_characters := OnlineAccount.characters.duplicate(true)
	Game.save_path = "user://player_ring_%d.json" % OS.get_process_id()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-rings=") and DisplayServer.get_name() != "headless": output = argument.trim_prefix("--capture-rings=")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.set_process(false)
	for variant in 6:
		Game.new_player("脚环验证", variant / 2, 0, variant % 2)
		app._enter_world()
		app.world.set_process(false)
		var hero: AnimatedSprite2D = app.world.hero
		var ring: Node2D = hero.get_node("PlayerRing")
		verify_ring(ring, hero, "world avatar " + str(variant))
		# Source head centers are pinned independently of the runtime metadata.
		var centers := {"idle": [5, 4, 0, 4, 2, 4][variant], "walk": [3, 1, -2, 2, 1, 2][variant]}
		for side in [1.0, -1.0]:
			hero.scale.x = side
			for animation in ["idle", "walk"]:
				hero.animation = animation
				hero.pause()
				for frame in hero.sprite_frames.get_frame_count(animation):
					hero.frame = frame
					ring._process(0.0)
					check(ring.global_position.is_equal_approx(hero.to_global(Vector2(-centers[animation], 0))), "Native ground origin stays centered for variant %d, %s, frame %d, side %d" % [variant, animation, frame, side])
		hero.play("idle")
		app.world._face_actor(hero, true)
		ring._process(0.0)
		var former_position := ring.global_position
		hero.position += Vector2(16, 0)
		app.world._face_actor(hero, false)
		verify_ring(ring, hero, "moving and facing right " + str(variant))
		check(is_equal_approx(ring.global_position.x, hero.global_position.x + float(centers.idle)), "Mirrored feet carry the ring to the correct side of the moving actor")
		check(ring.global_position != former_position, "World ring never stays at a previous cell")
		check(hero.get_child(0) is Label, "Adding a ring preserves the actor name tag facing logic")
		if variant == 3: await capture("world-player-ring")
		var enemy: Dictionary = ShushanWorld.ENEMIES[0].duplicate(true)
		enemy.hp = 999
		enemy.attack = 1
		app._start_battle(enemy)
		verify_ring(app.battle_ring, app.battle_hero, "battle avatar " + str(variant))
		check(app.battle_ring.global_position == app.battle_hero.global_position, "Native battle actors do not receive world compensation twice")
		check(app.battle_ring.visible and not app.battle_enemy.has_node("PlayerRing"), "Ready battle marks only the local character")
		app._battle_turn("attack")
		await get_tree().create_timer(0.17).timeout
		check(not app.battle_ring.visible, "Native normal attack hides the ring instead of leaving it at home")
		app.battle_playback.advance(app.battle_playback.remaining())
		check(app.battle_ring.visible, "Player return restores the ring before enemy retaliation")
		app.battle_playback.advance(app.battle_playback.remaining())
		await get_tree().create_timer(0.4).timeout
		verify_ring(app.battle_ring, app.battle_hero, "returned battle avatar " + str(variant))
		if variant == 3: await capture("battle-player-ring")
	app._home()
	var offline := Game.player.duplicate(true)
	OnlineAccount.characters = [{"id":SELF,"display_name":"脚环验证","job":1,"gender":1,"school":0,"level":1,"hp":95,"mp":45,"xp":0,"gold":30}]
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.set_process(false)
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.entities = {SELF:entity(SELF,1,"自己",1,1,[10,16]), PEER:entity(PEER,2,"其他玩家",0,0,[12,16])}
	view.network.changed.emit(view.network.entities)
	var own: Node2D = view.actors[SELF].root
	verify_ring(own.get_node("PlayerRing"), own, "online world")
	var online_sprite: AnimatedSprite2D = view.actors[SELF].sprite
	for side in [1.0, -1.0]:
		online_sprite.scale.x = side
		var online_marker: Node2D = own.get_node("PlayerRing")
		online_marker._process(0.0)
		check(online_marker.global_position == online_sprite.to_global(Vector2(-4, 0)), "Online sibling ring follows visual facing rather than its unmirrored container")
	check(not view.actors[PEER].root.has_node("PlayerRing"), "Online peers do not receive the local-player marker")
	own.position += Vector2(8, 12)
	verify_ring(own.get_node("PlayerRing"), own, "online interpolated position")
	view.camera.position = own.position
	view.camera.force_update_scroll()
	await capture("online-world-player-ring")
	var model := OnlinePve.new()
	model.ready = true
	model.state = {"character":{"job":1,"gender":1,"level":1,"hp":95,"mp":45,"display_name":"自己"},"stats":{"hp":95,"mp":45},"potions":6,
		"battle":{"id":"ring-battle","revision":"1","outcome":"active","enemy_hp":62,"hp":95,"mp":45,"enemy":{"art":"monster/langw","name":"山狼","level":1,"hp":62,"attack":13,"defense":3}}}
	var battle_view := view.battle_view
	battle_view.set_process(false)
	battle_view.present(model)
	var online_ring: Node2D = battle_view.get_node("Hero/Ring")
	verify_ring(online_ring, battle_view.get_node("Hero"), "online battle")
	model.last_action = "attack"
	model.state.battle.revision = "2"
	model.state.battle.enemy_hp = 50
	battle_view.present(model)
	check(not online_ring.visible, "Online normal attack follows the same native ring visibility rule")
	battle_view._process(battle_view._hero_motion.remaining() + 0.001)
	check(online_ring.visible, "Online player return restores the ring")
	battle_view._process(battle_view._enemy_motion.remaining() + 0.001)
	check(Game.player == offline, "Player markers never change offline progress during online play")
	app.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.player = old_player
	Game.save_path = old_path
	OnlineAccount.characters = old_characters
	print("PLAYER RING: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
