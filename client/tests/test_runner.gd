extends Node

var failures := 0
var checks := 0
var app: Control

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func _find_button(parent: Node, text_value: String) -> Button:
	for child in parent.get_children():
		if child is Button and child.text == text_value: return child
		var result := _find_button(child, text_value)
		if result != null: return result
	return null

func press(text_value: String) -> void:
	var button := _find_button(app.ui, text_value)
	check(button != null, "Button exists: " + text_value)
	if button != null:
		check(not button.disabled, "Button enabled: " + text_value)
		button.pressed.emit()

func _run() -> void:
	Game.save_path = "user://test_save.json"
	Game.new_player("验证侠客", 1, 0)
	check(Game.save_game(), "Initial save succeeds")
	check(Game.save_game(), "Atomic replacement of existing save succeeds")
	Game.player.gold = 0
	check(Game.load_game() and int(Game.player.gold) == 30, "Save reload restores state")
	Game.new_player("我是你们永远超越不了的传说", 2, 0, 1)
	check(Game.player.name == "我是你们永远超越不了的传说", "Reference-length nickname is preserved")
	check(Game.save_game() and Game.load_game() and int(Game.player.gender) == 1 and Game.actor_key() == "hero/wfs", "Female avatar persists across save and reload")
	var legacy := Game.player.duplicate(true)
	legacy.erase("gender")
	check(Game.valid_save(legacy), "Old saves without gender remain valid")
	var invalid_gender := Game.player.duplicate(true)
	invalid_gender.gender = 3
	check(not Game.valid_save(invalid_gender), "Invalid gender is rejected")
	Game.new_player("验证侠客", 1, 0)
	Game.save_game()
	var malformed := Game.player.duplicate(true)
	malformed.cell = [0, 100]
	check(not Game.valid_save(malformed), "Reject invalid coordinates")
	malformed = Game.player.duplicate(true)
	malformed.hp = "bad"
	check(not Game.valid_save(malformed), "Reject wrong stat type")
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string("{broken json")
	file.close()
	var previous := Game.player.duplicate(true)
	check(not Game.load_game() and Game.player == previous, "Corrupt save does not change current player")
	Game.save_game()
	for job in 3:
		var limit_enemy: Dictionary = ShushanWorld.ENEMIES[0].duplicate(true)
		limit_enemy.hp = 9999
		limit_enemy.attack = 1
		var limited := ShushanBattle.new(limit_enemy)
		check(limited.round_number == 0 and limited.phase == "select", "Battle starts at round zero awaiting a command")
		for i in ShushanBattle.MAX_ROUNDS:
			limited.action("guard")
			check(limited.round_number == i + 1, "Each complete action advances exactly one round")
		check(limited.finished and limited.escaped and not limited.victory, "Thirty-turn limit ends without victory reward")
		check(limited.round_number == 30 and not limited.action("attack").ok, "Round limit never displays round 31")
		Game.new_player("职业验证", job, job)
		var model := ShushanBattle.new(ShushanWorld.ENEMIES[0])
		model.rng.seed = 100 + job
		model.mp = 0
		var turn := model.round_number
		check(not model.action("skill").ok and model.round_number == turn, "Insufficient MP does not consume turn, job %d" % job)
		model.potions = 0
		check(not model.action("potion").ok and model.round_number == turn, "Empty bag does not consume turn")
		model.action("guard")
		check(model.mp == 5, "Guard regenerates spirit")
		model.action("flee")
		model.commit()
		check(model.escaped and Game.player.defeated.is_empty(), "Escape does not reward or defeat enemy")
		Game.new_player("职业验证", job, job)
		Game.player.quest = 1
		Game.player.equipped = true
		for enemy in ShushanWorld.ENEMIES.slice(0, 3):
			Game.restore()
			var duel := ShushanBattle.new(enemy)
			duel.rng.seed = job + 100
			var safety := 0
			while not duel.finished and safety < 100:
				duel.action("skill" if duel.mp >= 9 else "attack")
				safety += 1
			check(duel.victory, "Job %d wins wolf encounter" % job)
			duel.commit()
			var gold_after := int(Game.player.gold)
			duel.commit()
			check(int(Game.player.gold) == gold_after, "Battle reward committed only once")
		check(int(Game.player.quest) == 2 and int(Game.player.kills) == 3, "Three wolves advance quest")
		Game.player.quest = 3
		Game.add_rewards(60, 35)
		Game.restore()
		var boss := ShushanBattle.new(ShushanWorld.ENEMIES[5])
		boss.rng.seed = 40
		var steps := 0
		while not boss.finished and steps < 100:
			var command := "skill" if boss.mp >= 9 else "attack"
			if boss.hp < int(Game.stats().hp) / 2 and boss.potions > 0: command = "potion"
			boss.action(command)
			steps += 1
		check(boss.victory, "Job %d can finish boss encounter" % job)
		boss.commit()
		check(int(Game.player.quest) == 4, "Boss advances final quest")
		check(Game.load_game() and int(Game.player.quest) == 4, "Final quest persists")
	Game.new_player("失败验证", 1, 0)
	Game.player.quest = 1
	Game.player.hp = 1
	Game.player.zone = 1
	var loss := ShushanBattle.new(ShushanWorld.ENEMIES[5])
	loss.action("attack")
	check(loss.finished and not loss.victory, "Defeat outcome")
	loss.commit()
	check(int(Game.player.zone) == 0 and int(Game.player.hp) == int(Game.stats().hp), "Defeat restores hero at mountain gate")
	Game.new_player("回合验证", 1, 0)
	var staged := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	staged.rng.seed = 15
	var initial_hp := staged.hp
	var initial_enemy_hp := staged.enemy_hp
	check(not staged.begin_action("potion").ok and staged.round_number == 0, "Full-health potion does not consume a round")
	check(staged.begin_action("attack").ok and staged.phase == "player" and staged.round_number == 1, "Submitting one command enters first player stage")
	check(staged.hp == initial_hp and staged.enemy_hp == initial_enemy_hp, "Queued command applies no damage before player stage resolves")
	check(not staged.begin_action("guard").ok and not staged.action("attack").ok and staged.round_number == 1, "Repeated commands cannot consume another turn during resolution")
	check(not staged.resolve_enemy().ok and not staged.finish_round().ok, "Enemy and settlement cannot execute ahead of player")
	staged.resolve_player()
	check(staged.enemy_hp < initial_enemy_hp and staged.hp == initial_hp and staged.phase == "enemy", "Player action damages only enemy before enemy response")
	var after_player_hp := staged.enemy_hp
	check(not staged.resolve_player().ok and staged.enemy_hp == after_player_hp, "Player damage cannot apply twice")
	staged.resolve_enemy()
	check(staged.hp < initial_hp and staged.phase == "settlement", "Enemy response damages hero in its own stage")
	var after_enemy_hp := staged.hp
	check(not staged.resolve_enemy().ok and staged.hp == after_enemy_hp, "Enemy damage cannot apply twice")
	staged.finish_round()
	check(staged.phase == "select" and staged.round_number == 1, "Settlement returns to selection without advancing round twice")
	var lethal := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	lethal.enemy_hp = 1
	lethal.begin_action("attack")
	lethal.resolve_player()
	check(lethal.finished and lethal.victory and lethal.phase == "settlement" and not lethal.resolve_enemy().ok, "Dead enemy never takes a turn")
	check(not lethal.commit() and not lethal.committed, "Rewards cannot commit before final settlement")
	lethal.finish_round()
	lethal.commit()
	check(lethal.committed and lethal.phase == "finished", "Rewards commit after final settlement")
	var retreat := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	retreat.begin_action("flee")
	retreat.resolve_player()
	check(retreat.escaped and retreat.hp == int(Game.player.hp) and not retreat.resolve_enemy().ok, "Successful retreat skips enemy action")
	retreat.finish_round()
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame
	check(app.mode == "home", "Title scene loads")
	check(app.original_cover != null and app.original_cover.original_text.menu.slice(0, 4) == ["游戏试玩", "快速登录", "登录游戏", "注册账号"], "Cover uses original menu strings")
	var cover_art: TextureRect = app.original_cover.get_node("Original320x480Artwork")
	check(cover_art.texture.get_size() == Vector2(320, 480), "Cover uses full original portrait artwork")
	press("注册账号")
	check(app.mode == "home" and app.modal != null and not app.original_cover.active, "Unconnected account action pauses cover input")
	app._close_modal()
	check(app.original_cover.active, "Closing cover dialog restores menu input")
	app.original_cover.select_option(4)
	check(app.original_cover.rows[3].text == "游戏帮助", "Original menu scroll reaches help")
	press("游戏帮助")
	check(app.modal != null, "Cover help opens")
	app._close_modal()
	app.original_cover.select_option(0)
	press("游戏试玩")
	await get_tree().process_frame
	check(app.preview != null and app.nickname != null, "Character creation loads art and input")
	check(app.nickname.size == Vector2(214, 24), "Nickname row matches reference height")
	check(_find_button(app.ui, "创建").get_rect().end.y <= 480 and _find_button(app.ui, "随机").get_rect().end.x <= 320, "Bottom buttons remain inside game area")
	check(app.creation.portrait_buttons.size() == 6 and app.selected_job == 0 and app.selected_gender == 0, "Reference layout starts on male warrior with six portraits")
	var sample_name := "我是你们永远超越不了的传说"
	app.nickname.text = sample_name
	for variant in 6:
		app.creation.portrait_buttons[variant].pressed.emit()
		check(app.selected_job == variant / 2 and app.selected_gender == variant % 2 and app.preview != null, "Portrait switches model, job and gender: %d" % variant)
		check(app.nickname.text == sample_name, "Switching portrait preserves nickname")
		check(app.create_description.text == String(app.creation.data.descriptions[variant / 2]).replace("\r", "").replace("\n\n", "\n"), "Portrait uses original biography")
	app.creation.select_variant(0)
	press("随机")
	check(not app.nickname.text.is_empty() and app.nickname.text != sample_name, "Random button fills nickname")
	press("改名")
	check(app.nickname.has_focus(), "Rename button focuses editable nickname")
	app.nickname.text = ""
	var player_before_create := Game.player.duplicate(true)
	press("创建")
	check(app.modal != null and Game.player == player_before_create, "Empty name cannot create or overwrite character")
	app._close_modal()
	app.nickname.release_focus()
	app.creation.select_variant(5)
	app._begin_new(sample_name)
	app._close_modal()
	check(int(Game.player.gender) == 1 and int(Game.player.job) == 2 and Game.player.name == sample_name, "Creation selection reaches persisted player state")
	check(app.world.hero.sprite_frames == OriginalArt.cached["hero/wfs"], "Created female avatar is used in the game world")
	app._home()
	app._create()
	app.creation.select_variant(0)
	app._begin_new("界面验证")
	app._close_modal()
	await get_tree().process_frame
	check(app.mode == "world" and app.world.available_enemies().size() == 4, "World scene and original enemies load")
	var image_frame: AtlasTexture = app.world.hero.sprite_frames.get_frame_texture("idle", 0)
	check(int(image_frame.region.position.y) % int(OriginalArt.catalog[Game.actor_key()].height) == 0, "Atlas frames align with complete sprite rows")
	check(app.world.astar.is_point_solid(Vector2i(5, 12)), "River blocks movement")
	check(not app.world.astar.is_point_solid(Vector2i(5, 16)), "Bridge permits movement")
	check(app.world.portal_marker != null and app.world.portal_marker.get_parent() == app.world.actors, "Portal is drawn above terrain")
	for enemy in app.world.available_enemies():
		check(not app.world.astar.get_id_path(app.world.cell, Vector2i(enemy.cell[0], enemy.cell[1])).is_empty(), "Enemy reachable: " + String(enemy.id))
	var wolf_spot: Vector2 = app.world.cell_center(Vector2i(18, 10))
	check(app.world.target_at_pixel(wolf_spot + Vector2(0, -52)).get("kind") == "enemy", "Click on sprite head selects actor at its feet")
	check(app.world.hero.animation == "idle", "Entering world starts hero in idle")
	var idle_position: Vector2 = app.world.hero.position
	var initial_facing: float = app.world.hero.scale.x
	app.world.path.append(Vector2i(10, 15))
	app.world._process(0.05)
	check(app.world.hero.scale.x == initial_facing, "Initial vertical movement preserves standing facing")
	app.world._process(0.3)
	app.world.path.append(Vector2i(10, 16))
	app.world._process(0.3)
	for i in 20: app.world._process(0.1)
	check(app.world.hero.position == idle_position and app.world.hero.animation == "idle", "Standing hero does not attack or move")
	var wolf: AnimatedSprite2D = app.world.enemy_nodes.wolf_a
	var before_patrol: Vector2 = wolf.position
	for i in 45: app.world._update_patrols(0.1)
	check(wolf.position.distance_to(before_patrol) >= 8.0, "Wolf patrol changes world position")
	check(wolf.sprite_frames.get_frame_count("idle") > 0 and wolf.sprite_frames.get_frame_count("walk") > 1, "Wolf has valid stand and locomotion frames")
	var live_enemy: Dictionary = app.world.available_enemies()[0]
	check(Vector2i(live_enemy.cell[0], live_enemy.cell[1]) == app.world._enemy_cell(wolf), "Interaction tracks moving wolf instead of spawn point")
	var click_position: Vector2 = wolf.position + Vector2(0, -30) - app.world.camera.get_screen_center_position() + app.world.get_viewport_rect().size / 2.0
	app.world.click(click_position)
	check(not app.world.pending.is_empty() and app.world.pending.get("data", {}).get("id") == "wolf_a", "Clicking patrol sprite selects correct target")
	var held_position: Vector2 = wolf.position
	for i in 20: app.world._update_patrols(0.1)
	check(wolf.position == held_position, "Selected wolf holds still while hero approaches")
	app.world.stop_moving()
	app.world.enabled = false
	for i in 20: app.world._update_patrols(0.1)
	check(wolf.position == held_position, "Dialog pauses patrol movement")
	app.world.enabled = true
	for i in 50: app.world._update_patrols(0.1)
	check(wolf.position != held_position, "Patrol resumes after selection or dialog ends")
	var patrol_valid := true
	for id in app.world.patrols:
		var state: Dictionary = app.world.patrols[id]
		var spot: Vector2i = app.world._enemy_cell(app.world.enemy_nodes[id])
		if app.world.astar.is_point_solid(spot) or maxi(absi(spot.x - state.home.x), absi(spot.y - state.home.y)) > 2:
			patrol_valid = false
	check(patrol_valid, "Patrol respects collision and stays near its spawn")
	var grass_valid := true
	for point in app.world.terrain.get_used_cells():
		if app.world.ground_at(point) != ShushanWorld.Ground.GRASS: continue
		var uv: Vector2i = app.world.terrain.get_cell_atlas_coords(point)
		if uv.y * 32 + uv.x > 14: grass_valid = false
	check(grass_valid, "Grass excludes dirt-edge and dark patch tiles")
	check(app.world.road_tile(Vector2i(15, 16)) == 21 and app.world.road_tile(Vector2i(15, 17)) == 41, "Road edges face adjacent grass")
	app.world.path.append(Vector2i(11, 16))
	app.world._process(0.05)
	check(app.world.hero.animation == "walk", "Moving switches to walk animation")
	for i in 10: app.world._process(0.1)
	check(app.world.hero.animation == "idle" and app.world.cell == Vector2i(11, 16), "Arriving switches back to idle")
	app.world.enabled = false
	var actors_to_check: Array[AnimatedSprite2D] = []
	for key in ["hero/mzs", "hero/mck", "hero/mfs"]:
		var actor := OriginalArt.actor(key)
		app.ui.add_child(actor)
		check(actor.sprite_frames.get_frame_count("idle") == 1 and actor.sprite_frames.get_frame_count("walk") > 1, "Distinct stand and walk for " + key)
		actor.play("attack")
		actors_to_check.append(actor)
	await get_tree().create_timer(0.8).timeout
	for actor in actors_to_check:
		check(actor.animation == "idle", "Single attack returns to idle")
		actor.queue_free()
	app.world.enabled = true
	app.world.interact_nearest()
	for i in 30: app.world._process(0.1)
	check(app.modal != null, "Nearest interaction walks to NPC and opens dialog")
	press("领受试炼")
	check(int(Game.player.quest) == 1, "NPC accepts quest through UI")
	app._bag()
	check(app.backpack.cells.size() == 24 and app.backpack.items.size() == 2 and app.backpack.header.text == "背包(2/60)", "Backpack uses six columns, four rows and real occupied slots")
	app.backpack.select_item(1)
	app.backpack.open_menu()
	press("装备")
	check(Game.player.equipped, "Equipment button changes combat stat")
	check(app.backpack.equipment_icon.visible and app.backpack.items.size() == 1, "Equipping moves sword out of the inventory grid")
	app.backpack.open_menu()
	press("购药 · 8 铜钱")
	check(int(Game.player.potions) == 7 and int(Game.player.gold) == 22, "Shop deducts money and adds potion")
	app._close_modal()
	check(app.viewport.size == Vector2i(320, 375) and app.world_view.position.y == 28, "Field fills reference HUD and message boundaries")
	check(app.chrome.toolbar != null and app.chrome.message_panel.position.y == 403, "World uses original icon toolbar and blue message area")
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[0])
	check(app.battle_round.text == "回合：0/30" and app.battle_status.text == "请选择本回合指令", "Battle HUD exposes round counter and manual selection")
	check(app.battle_hero.position.x > app.battle_enemy.position.x and app.battle_buttons.size() == 6, "Battle uses right player, left enemy and six vertical commands")
	check(app.battle_buttons[2].text == "3 待机" and app.battle_buttons[3].text == "4 道具", "Command order matches original reference")
	var inspect_round: int = app.battle.round_number
	app._battle_menu()
	press("5 查看")
	check(app.modal != null and app.battle.round_number == inspect_round and not app.action_menu.visible, "Inspect opens cream card without consuming a turn")
	app._close_modal()
	app._battle_menu()
	var hp_before_turn: int = app.battle.hp
	press("1 攻击")
	check(app.battle.round_number == 1 and app.battle_stage == "player" and app.battle_buttons[0].disabled, "Submitting command advances visible round and locks input")
	await get_tree().create_timer(0.2).timeout
	check(app.battle.enemy_hp < int(app.battle.enemy.hp) and not app.action_menu.visible and app.battle_enemy_hp.value == app.battle.enemy_hp, "Attack closes menu and updates enemy bar")
	check(app.battle.hp == hp_before_turn and app.battle_stage == "player", "Enemy damage is delayed until player animation completes")
	app._battle_turn("attack")
	app._battle_menu()
	app._battle_inspect()
	check(app.battle.round_number == 1 and not app.action_menu.visible and app.modal == null, "Keys, actor menu and inspect cannot interrupt a resolving round")
	app._toggle_auto()
	app._process(1.0)
	check(app.battle.round_number == 1, "Auto combat cannot overlap a resolving round")
	app._toggle_auto()
	while app.battle.phase != "select": await get_tree().process_frame
	check(app.battle.hp < hp_before_turn and app.battle.round_number == 1 and not app.battle_buttons[0].disabled, "Completed enemy response unlocks next command in same counted round")
	app.battle.mp = 0
	var wait_key := InputEventKey.new()
	wait_key.keycode = KEY_3
	wait_key.pressed = true
	app._unhandled_key_input(wait_key)
	while app.battle.phase != "select": await get_tree().process_frame
	check(app.battle.mp == 5 and app.battle.round_number == inspect_round + 2, "Key three performs wait instead of using a potion")
	app._toggle_auto()
	check(app.battle_auto and app.auto_button.text == "0键手动战斗", "Auto prompt switches to manual command without hiding stage")
	app._process(1.0)
	check(app.battle.round_number == inspect_round + 3 and app.battle_stage == "player", "Auto starts one new staged round after selection delay")
	app._toggle_auto()
	while app.battle.phase != "select": await get_tree().process_frame
	app._process(2.0)
	check(app.battle.round_number == inspect_round + 3 and app.battle.phase == "select", "Stopping auto completes current round and waits for manual selection")
	app.battle_selected_enemy = true
	app._battle_inspect()
	check(app.modal != null and not app.world.enabled, "Enemy inspect keeps exploration paused")
	app._close_modal()
	await app._battle_turn("flee")
	press("返回山道")
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[0])
	app._battle_turn("attack")
	app._start_battle(ShushanWorld.ENEMIES[1])
	await get_tree().create_timer(0.2).timeout
	check(app.battle.round_number == 0 and app.battle.enemy_hp == int(app.battle.enemy.hp), "Abandoned turn cannot mutate a replacement battle")
	await app._battle_turn("flee")
	press("返回山道")
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[0])
	app.battle.enemy_hp = 1
	app._battle_turn("attack")
	await get_tree().create_timer(0.2).timeout
	var escape_key := InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	app._unhandled_key_input(escape_key)
	check(app.mode == "battle" and app.battle.phase == "settlement" and app.modal == null, "Escape cannot bypass victory animation and reward settlement")
	while app.battle.phase != "finished": await get_tree().process_frame
	check(app.battle.committed and app.modal != null, "Victory animation finishes before reward popup and save")
	# Reset quest data so the subsequent complete quest flow starts with all wolves.
	Game.player.defeated = []
	Game.player.kills = 0
	Game.player.quest = 1
	press("返回山道")
	for enemy in ShushanWorld.ENEMIES.slice(0, 3):
		Game.restore()
		app._start_battle(enemy)
		var steps := 0
		while not app.battle.finished and steps < 100:
			await app._battle_turn("skill" if app.battle.mp >= 9 else "attack")
			steps += 1
		check(app.battle.victory and app.modal != null, "Battle UI displays victory")
		press("返回山道")
		await get_tree().process_frame
	check(int(Game.player.quest) == 2 and app.world.available_enemies().size() == 1, "Defeated wolves removed from world")
	app._npc()
	press("领取奖励")
	check(int(Game.player.quest) == 3, "NPC reward unlocks ruins")
	app._world_interaction("portal", {})
	await get_tree().process_frame
	check(int(Game.player.zone) == 1 and app.world.available_enemies().size() == 2, "Portal enters ruins")
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[5])
	var steps := 0
	while not app.battle.finished and steps < 100:
		var command := "skill" if app.battle.mp >= 9 else "attack"
		if app.battle.hp < int(Game.stats().hp) / 2 and app.battle.potions > 0: command = "potion"
		await app._battle_turn(command)
		steps += 1
	check(app.battle.victory and int(Game.player.quest) == 4, "Full UI quest flow finishes boss")
	press("返回山道")
	await get_tree().process_frame
	app._save_feedback()
	check(app.modal != null, "Manual save shows success dialog")
	app._close_modal()
	app._home()
	app._continue()
	await get_tree().process_frame
	check(app.mode == "world" and int(Game.player.quest) == 4, "Continue reloads completed character")
	app._menu()
	press("人物属性")
	check(app.mode == "attributes" and not app.world.enabled and not app.world_view.visible, "Properties screen pauses the world")
	check(app.attributes.snapshot.name == Game.player.name and app.attributes.preview.sprite_frames == OriginalArt.cached[Game.actor_key()], "Properties show saved name and current avatar")
	check(app.attributes.bars.hp.value == int(Game.player.hp) and app.attributes.bars.mp.max_value == int(Game.stats().mp), "Properties bind current and maximum combat stats")
	check(app.attributes.numbers.xp.value == "%d/%d" % [int(Game.player.xp), int(Game.player.level) * 40], "Experience uses actual level threshold")
	check(app.attributes.numbers.gold.value == str(int(Game.player.gold)), "Copper matches saved wallet")
	app.attributes.signature.text = "蜀山修行，剑心长存"
	app.attributes.signature.text_changed.emit(app.attributes.signature.text)
	for i in range(1, 4):
		press(OriginalCharacterAttributes.TABS[i])
		check(app.attributes.selected_tab == i, "Properties tab switches")
	check(Game.player.signature == "蜀山修行，剑心长存", "Tab changes preserve edited signature")
	press("返回")
	check(app.mode == "world" and app.world.enabled, "Return resumes the same world")
	check(Game.load_game() and Game.player.signature == "蜀山修行，剑心长存", "Signature persists across reload")
	var old_properties := Game.player.duplicate(true)
	for key in ["signature", "title", "ingots", "guild_contribution", "essence"]: old_properties.erase(key)
	check(Game.valid_save(old_properties), "Legacy saves without properties fields remain valid")
	var old_file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	old_file.store_string(JSON.stringify(old_properties))
	old_file.close()
	check(Game.load_game() and Game.player.signature == "" and Game.player.ingots == 0, "Load migrates legacy properties fields")
	Game.player.potions = 201
	Game.player.equipped = false
	Game.player.weapon_owned = true
	Game.player.bag_order = ["potion", "sword"]
	check(Game.bag_items().size() == 4 and Game.bag_items()[0].count == 99 and Game.bag_items()[2].count == 3, "Potion stacks split at 99 without changing total quantity")
	app._bag()
	check(not app.world.enabled and app.minimap != null, "Inventory pauses world and keeps minimap beneath overlay")
	app.backpack.scrollbar.value = 36
	check(app.backpack.offset == 36 and app.backpack.cells.size() == 24, "Backpack scrollbar reaches last four rows")
	app.backpack.sort_items()
	check(Game.player.bag_order == ["sword", "potion"] and int(Game.player.potions) == 201 and app.backpack.items[0].id == "sword", "Sorting reorders slots without losing items")
	Game.player.hp = int(Game.stats().hp) - 45
	app.backpack.select_item(1)
	app.backpack.open_menu()
	press("使用")
	check(int(Game.player.potions) == 200 and int(Game.player.hp) == int(Game.stats().hp), "Inventory use consumes one potion and heals")
	app.backpack.select_item(1)
	app.backpack.open_menu()
	press("丢弃")
	press("取消")
	check(int(Game.player.potions) == 200, "Discard cancel preserves inventory")
	app.backpack.open_menu()
	press("丢弃")
	press("确定")
	check(int(Game.player.potions) == 101, "Discard removes only the selected stack")
	app.backpack.select_item(0)
	app.backpack.open_menu()
	press("装备")
	app.backpack._select_equipment(0)
	press("卸下")
	check(not Game.player.equipped and app.backpack.items[0].id == "sword", "Unequip returns weapon to inventory")
	check(Game.load_game() and not Game.player.equipped and int(Game.player.potions) == 101 and Game.player.bag_order == ["sword", "potion"], "Inventory operations persist across save and reload")
	app._close_modal()
	for school in 3:
		app._menu()
		press("门派")
		press(Game.SCHOOLS[school] + "派")
		check(Game.load_game() and int(Game.player.school) == school and app.mode == "world", "Menu school choice persists identity and returns to world")
		var colors := OriginalUITheme.palette("scene")
		check(app.chrome.palette.main == colors.main and app.chrome.toolbar.get_theme_stylebox("panel").bg_color == colors.main, "Scene remains blue independently of school")
		app._bag()
		check(app.backpack.palette.main == OriginalUITheme.palette("bag").main, "Backpack remains green independently of school")
		app._close_modal()
	var legacy_bag := Game.player.duplicate(true)
	legacy_bag.erase("weapon_owned")
	legacy_bag.erase("bag_order")
	check(Game.valid_save(legacy_bag), "Inventory migration remains compatible with legacy saves")
	var bad_order := Game.player.duplicate(true)
	bad_order.bag_order = ["sword", "sword"]
	check(not Game.valid_save(bad_order), "Inventory rejects duplicate ordering keys")
	var missing_weapon := Game.player.duplicate(true)
	missing_weapon.weapon_owned = false
	missing_weapon.equipped = true
	check(not Game.valid_save(missing_weapon), "Save rejects equipped weapon that is no longer owned")
	var before_money := int(Game.player.gold)
	Game.player.potions = 59 * 99
	check(not Game.bag_buy_potion() and int(Game.player.gold) == before_money, "Full backpack purchase leaves money and inventory unchanged")
	var bad_properties := Game.player.duplicate(true)
	bad_properties.signature = "字".repeat(41)
	check(not Game.valid_save(bad_properties), "Overlong signature rejected")
	bad_properties = Game.player.duplicate(true)
	bad_properties.ingots = -1
	check(not Game.valid_save(bad_properties), "Negative additional currency rejected")
	bad_properties.ingots = 1.5
	check(not Game.valid_save(bad_properties), "Fractional additional currency rejected")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	print("TEST RESULT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
