extends "res://tests/shared_interface_test.gd"
## Menu routing in both real game UI instances, with isolated local state.
const LABELS := ["商城", "人物", "炼制", "社交", "任务", "队伍", "帮会", "交易", "系统"]

func check_rows(popup: OriginalGameMenu) -> void:
	check(popup.scene_file_path == "res://scenes/ui/game_menu.tscn" and popup.rows.size() == 9, "Both modes use the authored nine-row menu")
	for index in LABELS.size():
		check(popup.rows[index].text == LABELS[index], "Unnumbered menu row matches the requested order: " + LABELS[index])
	check(not popup.has_node("Panel/Rows/Recharge"), "Recharge entry is removed")

func _run() -> void:
	output = OS.get_environment("SSJX_MENU_CAPTURE_PATH")
	var old_save := Game.save_path
	var old_player := Game.player.duplicate(true)
	var old_prefs := OS.get_environment("SSJX_CONNECTION_PATH")
	Game.save_path = "user://menu_test_%d.json" % OS.get_process_id()
	var prefs := Game.save_path + ".cfg"
	OS.set_environment("SSJX_CONNECTION_PATH", prefs)
	ServerConnectionSettings.new().save_address("local")
	Game.new_player("本地修士", 1, 2)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_world()
	app.chrome.toolbar.get_node("Menu").pressed.emit()
	var popup: OriginalGameMenu = app.modal
	check_rows(popup)
	check(popup.visible and not app.world.enabled, "Local toolbar opens compact menu and pauses movement")
	await get_tree().process_frame
	check(popup.get_node("Panel").get_rect() == Rect2(2, 184, 64, 274), "Menu stays narrow at the bottom-left above the toolbar")
	check(popup.rows[0].button_pressed, "Opening menu highlights the first entry")
	await capture("01_local_menu")
	popup.rows[3].mouse_entered.emit()
	check(popup.selected_index == 3 and popup.rows[3].button_pressed and not popup.rows[0].button_pressed, "Hover moves the highlight without activating an action")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_UP
	popup._unhandled_key_input(key)
	check(popup.selected_index == 2, "Arrow keys navigate menu entries")
	key.keycode = KEY_1
	popup._unhandled_key_input(key)
	check(popup.visible and popup.selected_index == 2, "Removed numeric labels do not introduce numeric shortcuts")
	key.keycode = KEY_ESCAPE
	popup._unhandled_key_input(key)
	check(app.modal == null and app.world.enabled, "Escape dismisses the local menu and restores movement")
	app._menu()
	app.modal.get_node("Dismiss").pressed.emit()
	check(app.modal == null and app.world.enabled, "Outside click dismisses without selecting an item")
	app._menu()
	app._menu()
	check(app.modal == null, "Local menu action toggles an existing compact menu")
	app._menu()
	popup = app.modal
	popup.select_option(1)
	key.keycode = KEY_ENTER
	popup._unhandled_key_input(key)
	check(app.mode == "attributes" and app.attributes != null, "People entry opens the existing local character page")
	app._return_from_attributes()
	app._menu()
	app.modal.get_node("Panel/Rows/Quest").pressed.emit()
	check(app.modal.find_child("Title", true, false).text == "蜀山初行", "Task entry opens the real local quest")
	app._close_modal()
	var before := Game.player.duplicate(true)
	app._menu()
	app.modal.rows[0].pressed.emit()
	check(app.modal.get_child(1) is ShopPanel and Game.player == before,"Shop menu opens purchase page without mutating assets")
	app._close_modal()
	for index in [2, 5, 6, 7]:
		app._menu()
		popup = app.modal
		popup.rows[index].pressed.emit()
		check(app.modal.find_child("Title", true, false).text == LABELS[index] and Game.player == before, "Unavailable local entry reports its state without changing assets: " + LABELS[index])
		app._close_modal()
	app._menu()
	app.modal.get_node("Panel/Rows/System").pressed.emit()
	check(app.modal.scene_file_path == "res://scenes/ui/system_menu.tscn" and not app.world.enabled, "System entry opens an authored settings page")
	await capture("03_system_menu")
	app.modal.get_node("Panel/Save").pressed.emit()
	check(FileAccess.file_exists(Game.save_path) and app.modal.find_child("Title", true, false).text == "修行已保存", "Manual save remains available inside System")
	app._close_modal()
	app._menu()
	app.modal.get_node("Panel/Rows/System").pressed.emit()
	app.modal.get_node("Panel/Leave").pressed.emit()
	check(app.mode == "home" and app.modal.has_node("ServerLogin") and (await Game.load_game()).ok, "System saves progress and returns to login")
	check(Game.player.name == "本地修士", "Returning to login retains the local character save")
	var saved := FileAccess.get_file_as_string(Game.save_path)
	before = Game.player.duplicate(true)
	OnlineAccount.characters = [{"id": SELF, "display_name": "昆仑客", "job": 1, "gender": 0, "school": 2, "level": 1, "hp": 95, "mp": 45, "gold": 30}]
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.entities = {SELF: entity(SELF, 1, "昆仑客", 1, 0, [10, 16])}
	view.network.changed.emit(view.network.entities)
	view.screen.chrome.toolbar.get_node("Menu").pressed.emit()
	check_rows(view.menu)
	check(view.menu.visible and not view.details.visible and not view.chat_input.has_focus(), "Online toolbar opens the same compact menu")
	await capture("02_online_menu")
	var timer := view._key_timer
	view._process(0.2)
	check(view._key_timer == timer, "Open menu blocks keyboard movement input")
	view.menu.get_node("Panel/Rows/Properties").pressed.emit()
	check(not view.menu.visible and view.attributes.visible and view.attributes.snapshot.name == "昆仑客", "Online People entry uses the original attributes scene with server data")
	view.attributes.get_node("Back").pressed.emit()
	view._scene_action("menu")
	view.menu.get_node("Panel/Rows/Social").pressed.emit()
	await get_tree().process_frame
	check(view.chat_input.has_focus() and not view.menu.visible and not view.details.visible, "Online Social entry focuses the existing inline chat")
	for index in [0, 2, 4, 5, 6, 7]:
		view._scene_action("menu")
		view.menu.rows[index].pressed.emit()
		check(view.details.visible and view.details.get_node("Panel/Title").text == LABELS[index], "Online menu entry routes to its current feature state: " + LABELS[index])
		view.get_node("Menu/Panel/Continue").pressed.emit()
	view._scene_action("menu")
	view.menu.get_node("Panel/Rows/System").pressed.emit()
	check(view.details.visible and view.details.get_node("Panel/Title").text == "系统", "Online System retains return-to-login controls")
	key.keycode = KEY_ESCAPE
	view._unhandled_key_input(key)
	check(not view.menu.visible and not view.details.visible, "Escape dismisses online details without opening another menu")
	view._scene_action("menu")
	view._scene_action("menu")
	check(not view.menu.visible, "Online menu action toggles the compact menu")
	view._scene_action("menu")
	view.menu.get_node("Dismiss").pressed.emit()
	check(not view.menu.visible, "Online outside click dismisses the popup")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == saved, "All online menu actions preserve the local character and save")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	DirAccess.remove_absolute(prefs)
	OS.set_environment("SSJX_CONNECTION_PATH", old_prefs)
	Game.save_path = old_save
	Game.player = old_player
	OnlineAccount.characters = []
	print("GAME MENU: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
