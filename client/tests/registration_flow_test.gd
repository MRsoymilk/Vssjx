extends Node
var checks := 0
var failures := 0
var app: Control
var backend := ""

func _ready() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func until(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	var passed: bool = predicate.call()
	check(passed, message)
	return passed

func login_form() -> ServerLogin:
	app._home()
	app._server_login()
	var form: ServerLogin = app.modal.get_node("ServerLogin")
	form.address_input.text = backend
	form.address_input.text_changed.emit(backend)
	return form

func selecting() -> bool:
	return app.mode == "online_select" and app.character_selection != null and app.character_selection.get_node("Online")._loaded and not OnlineAccount.busy

func creating() -> bool:
	return app.mode == "online_create" and app.creation != null and app.creation.get_node("Online")._loaded and not OnlineAccount.busy

func capture() -> void:
	var path := OS.get_environment("SSJX_REGISTRATION_CAPTURE_PATH")
	if path.is_empty(): return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path) == OK, "Capture actual registration scene")

func capture_selection(stem: String) -> void:
	var folder := OS.get_environment("SSJX_SELECTION_CAPTURE_PATH")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(stem + ".png")) == OK, "Capture authenticated character selection")

func _run() -> void:
	backend = OS.get_environment("SSJX_TEST_SERVER_URL")
	if backend.is_empty():
		push_error("Run tests/run_registration_flow.py (loopback protocol fixture)")
		get_tree().quit(1)
		return
	var old_connection := OS.get_environment("SSJX_CONNECTION_PATH")
	var prefs := "user://registration_%d.cfg" % OS.get_process_id()
	OS.set_environment("SSJX_CONNECTION_PATH", prefs)
	var old_save := Game.save_path
	Game.save_path = "user://registration_%d.json" % OS.get_process_id()
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-sentinel")
	var offline := Game.player.duplicate(true)
	OnlineAccount.clear()
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	var form := login_form()
	form.username_input.text = "registration_ui"
	form.password_input.text = "short"
	form.remember_me.button_pressed = true
	form.switch_button.pressed.emit()
	await until(func() -> bool: return not OnlineAccount.busy, "Invalid registration completes")
	check(not OnlineAccount.is_logged_in() and form.status.text.contains("密码") and form._registration_secret.is_empty(), "Refused registration clears temporary secret and stays on login")
	check(not FileAccess.file_exists(RememberedLogin.new().path), "Refused registration does not remember its password")
	form.password_input.text = "registration-password-1234"
	form.switch_button.pressed.emit()
	check(form.password_input.text.is_empty() and form.auth_button.disabled, "Registration clears visible password and locks duplicate requests")
	if not await until(creating, "Registration authenticates and opens character creation"): get_tree().quit(1); return
	check(OnlineAccount.is_logged_in() and OnlineAccount.account.username == "registration_ui", "Registered account is the authenticated owner")
	var remembered := RememberedLogin.new()
	check(remembered.load_saved(backend) == {"username": "registration_ui", "password": "registration-password-1234"}, "Successful registration and auto-login remember the account when selected")
	var page: OriginalCharacterCreation = app.creation
	var flow: OnlineCreationFlow = page.get_node("Online")
	check(page.scene_file_path == "res://scenes/ui/character_creation.tscn" and page.online_mode, "Registration uses the exact requested PackedScene")
	check(page.get_node("OnlineControls").visible and page.get_node("OnlineControls/Account").text.contains("registration_ui"), "Creation identifies its account")
	check(page.preview is AnimatedSprite2D and page.preview.is_playing(), "Original animated character preview is retained")
	page.get_node("OnlineControls/Back").pressed.emit()
	await until(func() -> bool: return app.mode == "home" and app.modal != null, "Creation Back returns to login")
	form = app.modal.get_node("ServerLogin")
	check(OnlineAccount.is_logged_in() and form.username_input.text == "registration_ui", "Cancelling creation keeps the registered account")
	form.auth_button.pressed.emit()
	await until(selecting, "Same account opens empty character selection")
	await capture_selection("character_selection_empty")
	check(app.world == null and not app.ui.has_node("OnlineWorld"), "Login never enters game before explicit Enter")
	app.character_selection.get_node("Options/Create").pressed.emit()
	await until(creating, "Empty selection can resume original creation scene")
	page = app.creation
	flow = page.get_node("Online")
	for index in 6:
		page.select_variant(index)
		check(page.selected_variant == index and page.preview is AnimatedSprite2D, "Original portrait selection works: %d" % index)
	page.nickname.text = "ＡＢ"
	page.get_node("Create").pressed.emit()
	check(not OnlineAccount.busy and flow.status.text.contains("昵称须"), "Invalid nickname rejected locally")
	page.nickname.text = "已占昵称"
	page.get_node("Create").pressed.emit()
	check(not page.active and page.get_node("Create").disabled and flow.school.disabled, "Creation locks selection and duplicate submit in flight")
	await until(func() -> bool: return not OnlineAccount.busy, "Name conflict completes")
	check(flow.status.text.contains("占用") and page.active and OnlineAccount.pending_creation.is_empty(), "Name conflict preserves editable selection")
	page.nickname.text = "注册青衫"
	flow.school.select(1)
	await capture()
	page.get_node("Create").pressed.emit()
	await until(func() -> bool: return not OnlineAccount.busy, "Lost creation response completes")
	var original := OnlineAccount.pending_creation.duplicate(true)
	check(not original.is_empty() and not page.active and not page.get_node("Create").disabled, "Unknown result keeps the original operation and allows retry")
	check(page.get_node("Create").text == "重试" and flow.status.text.contains("保留原"), "Retry action is visible in original creation scene")
	page.select_variant(0)
	check(page.selected_variant == 5 and not page.nickname.editable, "Unknown request prevents changing the original selection")
	page.get_node("Create").pressed.emit()
	await until(selecting, "Original creation retry returns to character selection")
	check(app.character_selection.get_node("Details/Name").text == "注册青衫" and not app.ui.has_node("OnlineWorld"), "Created role waits for explicit entry")
	app.character_selection.enter_button.pressed.emit()
	await until(func() -> bool: return app.mode == "online_world", "Explicit Enter opens the shared world")
	var character: Dictionary = OnlineAccount.characters[0]
	check(character.display_name == "注册青衫" and character.job == 2 and character.gender == 1 and character.school == 1, "Server character matches selected variant and school")
	check(app.ui.get_node("OnlineWorld").character_id == character.id and app.world == null, "Created character enters shared world without offline simulation")
	check(OnlineAccount.pending_creation.is_empty(), "Original operation receipt is resolved after retry")
	form = login_form()
	await until(func() -> bool: return not OnlineAccount.busy and not form.switch_button.disabled, "Returned login unlocks after any in-flight world ticket")
	form.switch_button.pressed.emit()
	await until(func() -> bool: return not OnlineAccount.busy, "Account logout completes")
	check(not OnlineAccount.is_logged_in(), "Logout forgets current session")
	check(form.remember_me.button_pressed and form.password_input.text == "registration-password-1234", "Logout restores remembered credentials without restoring a session")
	# Recreate the page to ensure its ephemeral state is not needed for later login.
	form = login_form()
	form._restore_credentials()
	check(form.username_input.text == "registration_ui" and form.password_input.text == "registration-password-1234", "New login page autofills the previously registered account")
	form.username_input.text = "registration_ui"
	form.password_input.text = "wrong-password"
	form.auth_button.pressed.emit()
	await until(func() -> bool: return not OnlineAccount.busy, "Wrong password completes")
	check(not OnlineAccount.is_logged_in() and form.status.text.contains("错误"), "The same account still requires its registered password")
	check(remembered.load_saved(backend).password == "registration-password-1234", "Failed login cannot overwrite the saved valid password")
	form.password_input.text = "registration-password-1234"
	form.auth_button.pressed.emit()
	await until(selecting, "Later login stops on existing character selection")
	await capture_selection("character_selection_login")
	check(app.world == null and not app.ui.has_node("OnlineWorld"), "Existing character does not auto-enter after login")
	app.character_selection.enter_button.pressed.emit()
	await until(func() -> bool: return app.mode == "online_world", "Later login enters only after confirmation")
	check(OnlineAccount.characters.size() == 1 and OnlineAccount.characters[0].id == character.id, "Later login recovers the same server character")
	check(Game.player == offline and FileAccess.get_file_as_string(Game.save_path) == "offline-sentinel", "Registration and later login preserve offline player and save")
	var saved := FileAccess.get_file_as_string(prefs)
	check(not saved.contains("registration_ui") and not saved.contains("password") and not saved.contains(OnlineAccount._access_token), "No account credentials or online snapshots are persisted in preferences")
	form = login_form()
	form._restore_credentials()
	form.remember_me.button_pressed = false
	check(not FileAccess.file_exists(remembered.path), "Disabling remember after authentication clears stored credentials")
	app._home()
	OnlineAccount.suspend_network()
	OnlineAccount.clear()
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	DirAccess.remove_absolute(prefs)
	Game.save_path = old_save
	OS.set_environment("SSJX_CONNECTION_PATH", old_connection)
	print("REGISTRATION FLOW: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
