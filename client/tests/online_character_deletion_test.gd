extends "res://tests/shared_interface_test.gd"

func until(predicate: Callable, description: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(predicate.call(), description)

func _run() -> void:
	var backend := OS.get_environment("SSJX_TEST_SERVER_URL")
	if backend.is_empty():
		push_error("Use tests/run_character_deletion.py with GODOT_BIN")
		get_tree().quit(1)
		return
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_connection := OS.get_environment("SSJX_CONNECTION_PATH")
	Game.save_path = "user://online_delete_%d.json" % OS.get_process_id()
	OS.set_environment("SSJX_CONNECTION_PATH", "user://online_delete_%d.cfg" % OS.get_process_id())
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-delete-sentinel")
	OnlineAccount.clear()
	OnlineAccount.register_account(backend, "delete_ui", "deletion-ui-password-1234")
	await until(func() -> bool: return not OnlineAccount.busy, "Registration finishes")
	OnlineAccount.login(backend, "delete_ui", "deletion-ui-password-1234")
	await until(func() -> bool: return not OnlineAccount.busy, "Login finishes")
	check(OnlineAccount.is_logged_in(), "Isolated UI account authenticated")
	for role in ["界面删除", "界面保留"]:
		OnlineAccount.create_character(role, 1, 0, 3)
		await until(func() -> bool: return not OnlineAccount.busy, "Create isolated UI role")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._online_characters()
	var page: OriginalCharacterSelection = app.character_selection
	var flow: OnlineSelectionFlow = page.get_node("Online")
	await until(func() -> bool: return flow._loaded and not OnlineAccount.busy, "Online list loads two characters")
	check(page.characters.size() == 2 and not page.get_node("Options/Delete").disabled, "Online menu exposes deletion")
	page._ask_delete()
	page._cancel_delete()
	check(page.characters.size() == 2 and OnlineAccount.pending_deletion.is_empty(), "Online cancel sends no deletion")
	page._ask_delete()
	page._confirm_delete()
	check(page._deleting and page.enter_button.disabled, "In-flight deletion locks entering and repeat confirmation")
	await until(func() -> bool: return not OnlineAccount.busy and not page._deleting, "Dropped response finishes without fabricating confirmation")
	check(not OnlineAccount.pending_deletion.is_empty() and page.characters.size() == 2, "Unknown result retains exact target and visible roster")
	var pending := OnlineAccount.pending_deletion.duplicate(true)
	page._ask_delete()
	page._confirm_delete()
	await until(func() -> bool: return not OnlineAccount.busy and flow._loaded and page.characters.size() == 1, "Retry reconciles server receipt and refreshes list")
	check(OnlineAccount.pending_deletion.is_empty() and page.characters[0].display_name == "界面保留", "Retry removes only originally confirmed role")
	page._ask_delete()
	page._confirm_delete()
	await until(func() -> bool: return not OnlineAccount.busy and flow._loaded and page.characters.is_empty(), "Last online role deletion refreshes empty list")
	check(page.enter_button.disabled and page.get_node("Options/Delete").disabled and not page.get_node("Options/Create").disabled, "Empty online list permits creation and prevents entering")
	check(FileAccess.get_file_as_string(Game.save_path) == "offline-delete-sentinel" and Game.player == old_player, "Online deletion never changes local save or player")
	check(pending.character_name == "界面删除", "Retry remains bound to the displayed confirmation")
	app.free()
	OnlineAccount.clear()
	DirAccess.remove_absolute(Game.save_path)
	DirAccess.remove_absolute(OS.get_environment("SSJX_CONNECTION_PATH"))
	Game.save_path = old_path
	OS.set_environment("SSJX_CONNECTION_PATH", old_connection)
	print("ONLINE CHARACTER DELETION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
