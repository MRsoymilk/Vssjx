extends Node

var checks := 0
var failures := 0
var viewport: SubViewport
var world: ShushanWorld

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("RESPAWN FAIL: " + message)

func enter_zone(zone: int) -> void:
	if world != null:
		viewport.remove_child(world)
		world.queue_free()
	Game.player.zone = zone
	Game.player.cell = [10, 16]
	world = ShushanWorld.new()
	viewport.add_child(world)
	world.set_process(false)

func write_save(data: Dictionary) -> void:
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _run() -> void:
	await Game.when_ready()
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://offline_respawn_%d.json" % OS.get_process_id()
	Game.new_player("刷新验证", 1, 0)
	viewport = preload("res://scenes/ui/world_viewport.tscn").instantiate()
	add_child(viewport)
	check(Game.player.enemy_respawns.is_empty(), "New characters start without cooldowns")
	check(Game.enemy_available("wolf_a"), "A living monster is available")
	# Completed legacy saves must recover a populated world, without losing progress.
	Game.player.defeated = ["wolf_a", "wolf_b", "wolf_c", "spirit", "guardian", "boss"]
	Game.player.quest = 4
	Game.player.kills = 3
	var legacy := Game.player.duplicate(true)
	legacy.erase("enemy_respawns")
	check(Game.valid_save(legacy), "Legacy saves without cooldowns remain valid")
	write_save(legacy)
	check((await Game.load_game()).ok and Game.player.enemy_respawns.is_empty(), "Legacy load adds an empty cooldown table")
	enter_zone(0)
	check(world.enemy_nodes.size() == 4 and world.available_enemies().size() == 4, "Old defeated history no longer leaves the trail empty")
	enter_zone(1)
	check(world.enemy_nodes.size() == 2 and world.available_enemies().size() == 2, "Old completed saves restore guardians and bosses too")
	check(Game.player.quest == 4 and Game.player.kills == 3 and Game.player.defeated.size() == 6, "Migration preserves all quest and defeat history")

	# Every configured enemy, including the boss, disappears only until its own deadline.
	for enemy in ShushanWorld.ENEMIES:
		enter_zone(1 if enemy.id in ["guardian", "boss"] else 0)
		var original_count := world.enemy_nodes.size()
		var original_children := world.actors.get_child_count()
		var former: AnimatedSprite2D = world.enemy_nodes[enemy.id]
		var before := Time.get_unix_time_from_system()
		Game.finish_enemy(enemy)
		var deadline: float = Game.player.enemy_respawns[enemy.id]
		check(deadline >= before + 30.0 and deadline <= Time.get_unix_time_from_system() + 30.0, "Victory schedules a 30-second cooldown: " + enemy.id)
		check(not Game.enemy_available(enemy.id, deadline - 0.001) and Game.enemy_available(enemy.id, deadline), "Respawn occurs exactly at the deadline: " + enemy.id)
		world._process(0.0)
		check(not world.enemy_nodes.has(enemy.id) and not world.patrols.has(enemy.id), "Victory removes the sprite and its patrol: " + enemy.id)
		check(world.available_enemies().size() == original_count - 1 and former.get_parent() == null, "Interaction and minimap population exclude defeated enemy: " + enemy.id)
		# Expiry is checked by the normal process loop, without reloading the map.
		Game.player.enemy_respawns[enemy.id] = Time.get_unix_time_from_system() - 0.1
		world._process(0.0)
		check(world.enemy_nodes.has(enemy.id) and world.available_enemies().size() == original_count, "World process respawns the enemy in place: " + enemy.id)
		var sprite: AnimatedSprite2D = world.enemy_nodes[enemy.id]
		var home := world.cell_center(Vector2i(enemy.cell[0], enemy.cell[1]))
		check(sprite != former and sprite.position == home and sprite.animation == "idle", "New sprite starts at its home in idle: " + enemy.id)
		check(world.target_at_pixel(home + Vector2(0, -20)).get("data", {}).get("id") == enemy.id, "Respawned enemy can be targeted: " + enemy.id)
		for tick in 5: world._process(0.0)
		check(world.enemy_nodes[enemy.id] == sprite and world.actors.get_child_count() == original_children, "Expiry creates no duplicate sprites or name tags: " + enemy.id)
		if enemy.kind == "wolf":
			check(world.patrols.has(enemy.id) and world.patrols[enemy.id].cell == Vector2i(enemy.cell[0], enemy.cell[1]), "Wolf respawn resets patrol to home: " + enemy.id)
			for tick in 40: world._update_patrols(0.1)
			check(sprite.position != home and sprite.animation in ["walk", "idle"], "Respawned wolf resumes patrolling: " + enemy.id)
	check(Game.player.quest == 4 and Game.player.kills == 3 and Game.player.defeated.size() == 6, "Repeated kills do not regress or duplicate quest history")

	# Let a short fixture deadline elapse through the actual SceneTree process.
	enter_zone(0)
	Game.finish_enemy(ShushanWorld.ENEMIES[0])
	Game.player.enemy_respawns.wolf_a = Time.get_unix_time_from_system() + 0.15
	var refresh_at: float = Game.player.enemy_respawns.wolf_a
	world._process(0.0)
	world.set_process(true)
	while Time.get_unix_time_from_system() < refresh_at + 0.1:
		await get_tree().process_frame
	world.set_process(false)
	check(world.enemy_nodes.has("wolf_a"), "Elapsed wall time refreshes an idle world automatically")
	Game.finish_enemy(ShushanWorld.ENEMIES[0])
	world._process(0.0)
	world.enabled = false
	Game.player.enemy_respawns.wolf_a = Time.get_unix_time_from_system() - 1.0
	world._process(100.0)
	check(not world.enemy_nodes.has("wolf_a"), "Paused battle or menu does not mutate world sprites")
	world.enabled = true
	check(world.enemy_nodes.has("wolf_a"), "Returning from a paused screen immediately catches up elapsed cooldowns")
	Game.finish_enemy(ShushanWorld.ENEMIES[0])
	var renewed: float = Game.player.enemy_respawns.wolf_a
	check(not Game.enemy_available("wolf_a") and Game.player.defeated.size() == 6, "Defeating a respawned monster starts a new cooldown")
	check((await Game.save_game()).ok, "Cooldown save succeeds")
	Game.player.enemy_respawns = {}
	check((await Game.load_game()).ok and Game.player.enemy_respawns.wolf_a == renewed, "Reload preserves the original deadline rather than restarting the timer")
	enter_zone(1)
	enter_zone(0)
	check(not world.enemy_nodes.has("wolf_a") and world.enemy_nodes.has("wolf_b"), "Changing maps preserves independent enemy cooldowns")
	Game.player.enemy_respawns.wolf_a = Time.get_unix_time_from_system() - 10.0
	await Game.save_game()
	Game.player.enemy_respawns.wolf_a = Time.get_unix_time_from_system() + 999.0
	check((await Game.load_game()).ok, "Expired deadline reload succeeds")
	enter_zone(0)
	check(world.enemy_nodes.has("wolf_a"), "Time elapsed outside the game restores the monster on load")

	# Real battle outcomes only schedule on victory, and settlement is idempotent.
	Game.new_player("结算验证", 1, 0)
	Game.player.quest = 1
	var escape := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	escape.action("flee")
	await escape.commit()
	check(Game.player.enemy_respawns.is_empty(), "Fleeing never schedules a respawn")
	Game.player.hp = 1
	var loss := ShushanBattle.new(ShushanWorld.ENEMIES[5])
	loss.action("attack")
	await loss.commit()
	check(loss.finished and not loss.victory and Game.player.enemy_respawns.is_empty(), "Losing never schedules a respawn")
	var win := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	win.enemy_hp = 1
	win.action("attack")
	await win.commit()
	var settled := Game.player.duplicate(true)
	await win.commit()
	check(win.victory and settled == Game.player and not Game.enemy_available("wolf_a"), "Repeated victory settlement neither rewards nor schedules twice")
	check(Game.player.quest == 1 and Game.player.kills == 1, "Victory still advances the wolf trial")
	if "--realtime" in OS.get_cmdline_user_args():
		enter_zone(0)
		check(not world.enemy_nodes.has("wolf_a"), "Real victory initially leaves its spawn empty")
		var real_deadline: float = Game.player.enemy_respawns.wolf_a
		world.set_process(true)
		print("OFFLINE RESPAWN: waiting for the actual 30-second victory deadline")
		while Time.get_unix_time_from_system() < real_deadline - 0.05:
			await get_tree().process_frame
		check(not world.enemy_nodes.has("wolf_a"), "Actual 30-second cooldown does not respawn early")
		while Time.get_unix_time_from_system() < real_deadline + 0.2:
			await get_tree().process_frame
		world.set_process(false)
		check(world.enemy_nodes.has("wolf_a") and world.available_enemies().size() == 4, "Actual 30-second deadline restores the monster without changing scenes")
		var refreshed: Dictionary = world.target_at(Vector2i(18, 10)).get("data", {})
		check(refreshed.get("id") == "wolf_a" and ShushanBattle.new(refreshed).enemy_hp == 62, "Refreshed wolf can enter another battle at full health")

	for bad in [null, [], {"wolf_a": "soon"}, {"wolf_a": -1}, {"wolf_a": INF}, {"wolf_a": NAN}, {"wolf_a": true}, {"wolf_a": 253402300800.0}, {"": 1.0}, {42: 1.0}]:
		var malformed := Game.player.duplicate(true)
		malformed.enemy_respawns = bad
		check(not Game.valid_save(malformed), "Malformed cooldown tables are rejected: " + str(bad))
	var oversized := Game.player.duplicate(true)
	oversized.enemy_respawns = {}
	for i in 21: oversized.enemy_respawns[str(i)] = 1.0
	check(not Game.valid_save(oversized), "Oversized cooldown table is rejected")
	var invalid_file := Game.player.duplicate(true)
	invalid_file.enemy_respawns = {"wolf_a": "bad"}
	write_save(invalid_file)
	var prior := Game.player.duplicate(true)
	check(not (await Game.load_game()).ok and Game.player == prior, "Invalid cooldown save cannot overwrite the current character")

	viewport.queue_free()
	await get_tree().process_frame
	if FileAccess.file_exists(Game.save_path): DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = old_player
	print("OFFLINE RESPAWN: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
