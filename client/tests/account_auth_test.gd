extends Node
var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func form(app: Control) -> ServerLogin:
	app._server_login()
	var page := app.modal.find_child("ServerLogin", true, false) as ServerLogin
	# Isolate auth/session checks here; registration_flow_test covers navigation.
	page.characters_requested.disconnect(Callable(app, "_online_characters"))
	page.registration_requested.disconnect(Callable(app, "_online_creation"))
	return page

func capture(name_value: String) -> void:
	var output := OS.get_environment("SSJX_AUTH_CAPTURE_PATH")
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(output.path_join(name_value + ".png")) == OK, "Auth screenshot saved")

func _run() -> void:
	var backend := OS.get_environment("SSJX_TEST_SERVER_URL")
	if backend.is_empty():
		push_error("Run account_auth_test through tests/run_account_auth.py with its isolated PostgreSQL")
		get_tree().quit(1)
		return
	var previous := OS.get_environment("SSJX_CONNECTION_PATH")
	var isolated := "user://account_auth_%d.cfg" % OS.get_process_id()
	OS.set_environment("SSJX_CONNECTION_PATH", isolated)
	OnlineAccount.clear()
	var player_before := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	var login := form(app)
	check(login.auth_button.text == "登陆" and login.switch_button.text == "注册" and login.password_input.secret, "Login page exposes separate actions and a masked password field")
	check(OnlineAccount.secure_credentials_target("https://game.example.com"), "HTTPS accepts remote credentials")
	check(not OnlineAccount.secure_credentials_target("http://203.0.113.1:8080"), "Remote HTTP credentials are refused")
	login.address_input.text = "http://203.0.113.1:8080"
	login.username_input.text = "ui_player"
	login.password_input.text = "ui-password-1234"
	login.switch_button.pressed.emit()
	check(not OnlineAccount.busy and login.status.text.contains("HTTPS"), "Unsafe target refused before sending credentials")
	login.address_input.text = backend
	login.address_input.text_changed.emit(backend)
	login.password_input.text = "ui-password-1234"
	await capture("01_registration")
	login.switch_button.pressed.emit()
	check(login.password_input.text.is_empty() and login.auth_button.disabled, "Password cleared and duplicate submit locked")
	await OnlineAccount.completed
	while OnlineAccount.busy: await get_tree().process_frame
	check(OnlineAccount.is_logged_in() and not login.register_mode and login._registration_secret.is_empty(), "Registration performs a real login and forgets its temporary password")
	login.switch_button.pressed.emit()
	await OnlineAccount.completed
	login.password_input.text = "incorrect-password"
	login.auth_button.pressed.emit()
	await OnlineAccount.completed
	check(not OnlineAccount.is_logged_in() and login.status.text.contains("错误"), "Wrong password fails")
	login.password_input.text = "ui-password-1234"
	login.auth_button.pressed.emit()
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in() and OnlineAccount.account.username == "ui_player", "Real account login succeeds")
	check(login.password_input.text.is_empty(), "No password remains in the form")
	check(not FileAccess.file_exists(RememberedLogin.new().path), "Successful login without remember selected never persists credentials")
	check(app.mode == "home" and Game.player == player_before, "Account authentication does not import local character assets")
	var saved := FileAccess.get_file_as_string(isolated)
	check(not saved.contains("ui_player") and not saved.contains("ui-password") and not saved.contains(OnlineAccount._access_token), "Only server address is persisted")
	await capture("02_authenticated")
	app._close_modal()
	check(OnlineAccount.is_logged_in(), "Closing a page does not destroy the authenticated session")
	login = form(app)
	check(login.address_input.text == backend and login.auth_button.text == "选择角色" and login.switch_button.text == "退出账号", "Reopened page restores address and memory-only account status")
	OnlineAccount.inspect_session()
	var me: Array = await OnlineAccount.completed
	check(me[1].ok and me[1].account.username == "ui_player", "Account identity is fetched from the server")
	var old_token := OnlineAccount._access_token
	OnlineAccount.refresh()
	var refreshed: Array = await OnlineAccount.completed
	check(refreshed[1].ok and OnlineAccount._access_token != old_token, "Refresh rotates in-memory credentials")
	OnlineAccount._refresh_expires_at = Time.get_unix_time_from_system() - 1.0
	OnlineAccount._process(0.0)
	check(not OnlineAccount.is_logged_in() and login.password_input.editable, "Local expiry clears session and unlocks login fields")
	login.password_input.text = "ui-password-1234"
	login.auth_button.pressed.emit()
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "User can log in again after local expiry")
	login.switch_button.pressed.emit()
	await OnlineAccount.completed
	check(not OnlineAccount.is_logged_in() and login.status.text.contains("已退出"), "Logout clears memory and confirms revocation")
	await capture("03_logged_out")
	app.queue_free()
	await get_tree().process_frame
	OS.set_environment("SSJX_CONNECTION_PATH", previous)
	if FileAccess.file_exists(isolated): DirAccess.remove_absolute(isolated)
	print("ACCOUNT AUTH UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
