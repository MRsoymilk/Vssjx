extends Node

var app: Control
var output := ""

func _ready() -> void:
	call_deferred("_capture")

func save_frame(name_value: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	image.save_png(output.path_join(name_value + ".png"))

func _capture() -> void:
	output = OS.get_environment("SSJX_CAPTURE_PATH")
	if output.is_empty():
		push_error("Set SSJX_CAPTURE_PATH to an existing screenshot directory")
		get_tree().quit(1)
		return
	Game.save_path = "user://visual_test_save.json"
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	await save_frame("01_title")
	app._create()
	app.nickname.text = "我是你们永远超越不了的传说"
	await save_frame("02_character")
	app._select_job(0)
	await save_frame("10_warrior")
	app._select_job(2)
	await save_frame("11_mage")
	app.creation.select_variant(1)
	await save_frame("16_female_warrior")
	app.creation.select_variant(3)
	await save_frame("17_female_knight")
	app.creation.select_variant(5)
	await save_frame("18_female_mage")
	app.creation.select_variant(2)
	app._select_job(1)
	app._begin_new("青衫客")
	app.character_selection.enter_button.pressed.emit()
	app._close_modal()
	await save_frame("03_world")
	app._npc()
	await save_frame("04_quest")
	app._close_modal()
	Game.player.quest = 1
	app._start_battle(ShushanWorld.ENEMIES[0])
	await save_frame("05_battle")
	await app._battle_turn("skill")
	await save_frame("06_battle_turn")
	Game.player.zone = 1
	Game.player.cell = [15, 16]
	app._enter_world()
	await save_frame("07_ruins")
	app._bag()
	await save_frame("08_bag")
	app._close_modal()
	Game.player.zone = 0
	Game.player.cell = [25, 16]
	app._enter_world()
	await save_frame("09_portal")
	Game.player.job = 2
	Game.restore()
	Game.player.cell = [10, 16]
	app._enter_world()
	await save_frame("12_mage_idle_world")
	var motion_path := OS.get_environment("SSJX_MOTION_PATH")
	if not motion_path.is_empty():
		for index in 32:
			await get_tree().create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			get_tree().root.get_texture().get_image().save_png(motion_path.path_join("frame_%03d.png" % index))
	else:
		await get_tree().create_timer(3.2).timeout
	await save_frame("13_wolf_patrol")
	app.world.path.append(Vector2i(11, 16))
	await get_tree().create_timer(0.08).timeout
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(output.path_join("14_mage_walk.png"))
	await save_frame("15_mage_stopped")
	Game.new_player("玖幽↑殇王子", 0, 1)
	Game.player.signature = "蜀山修行，剑心长存"
	app._enter_world()
	app._menu()
	await save_frame("19_properties_menu")
	app._attributes()
	await save_frame("20_character_attributes")
	app.attributes.select_tab(1)
	await save_frame("21_attributes_extended")
	app.attributes.select_tab(2)
	await save_frame("22_attributes_skills")
	app.attributes.select_tab(3)
	await save_frame("23_attributes_inner")
	app._return_from_attributes()
	Game.new_player("七月的风", 0, 1)
	app._enter_world()
	app._start_battle(ShushanWorld.ENEMIES[3])
	await save_frame("24_courtyard_battle")
	app._battle_inspect()
	await save_frame("25_battle_character_info")
	app._close_modal()
	app._battle_turn("skill")
	await get_tree().create_timer(0.14).timeout
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(output.path_join("26_battle_original_effect.png"))
	await get_tree().create_timer(0.9).timeout
	var snow_enemy: Dictionary = ShushanWorld.ENEMIES[4].duplicate(true)
	snow_enemy.terrain = "snow"
	Game.restore()
	app._start_battle(snow_enemy)
	await save_frame("27_snow_battle")
	Game.player.zone = 1
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[5])
	await save_frame("28_ruins_battle")
	Game.player.job = 2
	Game.restore()
	app._start_battle(ShushanWorld.ENEMIES[5])
	app._battle_turn("skill")
	await get_tree().create_timer(0.24).timeout
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(output.path_join("29_battle_flame.png"))
	await get_tree().create_timer(0.9).timeout
	Game.new_player("花涧青衫", 0, 1)
	Game.player.potions = 201
	app._enter_world()
	app._bag()
	app.backpack.select_item(0, true)
	await save_frame("30_green_backpack")
	app.backpack.select_item(3)
	app.backpack.open_menu()
	app.backpack.equip_item()
	app.backpack.select_item(0, true)
	await save_frame("31_equipped_backpack")
	app._close_modal()
	for school in 3:
		Game.player.school = school
		app._world_ui()
		await save_frame("%d_school_world" % (32 + school))
		app._bag()
		await save_frame("%d_school_backpack" % (35 + school))
		app._close_modal()
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	print("VISUAL SMOKE: 37 screenshots saved")
	get_tree().quit()
