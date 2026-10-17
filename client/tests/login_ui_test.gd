extends Node
var checks := 0
var failures := 0
var output := ""

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func capture(name_value: String) -> void:
	if output.is_empty(): return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output.path_join(name_value + ".png")) == OK, "Save login capture")

func _run() -> void:
	var old_path := OS.get_environment("SSJX_CONNECTION_PATH")
	var isolated := "user://login_ui_%d.cfg" % OS.get_process_id()
	OS.set_environment("SSJX_CONNECTION_PATH", isolated)
	output = OS.get_environment("SSJX_LOGIN_UI_CAPTURE_PATH")
	OnlineAccount.clear()
	var settings := ServerConnectionSettings.new()
	settings.save_address("https://game.example.com/ssjx")
	var offline := Game.player.duplicate(true)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	var cover: OriginalCover = app.original_cover
	check(cover.rows.size() == 2 and cover.rows[0].text == "登陆游戏" and cover.rows[1].text == "退出游戏", "Title has exactly the two requested entry actions")
	for removed in ["Confirm", "Exit", "Rows2", "Rows3", "UpArrow", "DownArrow"]:
		check(not cover.has_node(removed), "Title removes obsolete control: " + removed)
	cover.select_option(2)
	check(cover.selected_index == 0, "Keyboard selection wraps across only the two entries")
	await capture("01_title")
	cover.rows[0].pressed.emit()
	var login := app.modal.get_node("ServerLogin") as ServerLogin
	check(login != null and not cover.active, "Title login opens the scene and pauses title input")
	check(login.auth_button.text == "登陆" and login.switch_button.text == "注册" and login.get_node("Back").text == "返回", "Login page uses the requested action labels")
	check(login.auth_button.position.y < login.switch_button.position.y and login.switch_button.position.y < login.get_node("Back").position.y, "Login, register and return follow the requested vertical order")
	check(login.address_input.editable and not login.has_node("ConnectButton"), "Server address can be edited immediately without a Modify button")
	check(login.address_input.text == "https://game.example.com/ssjx" and login.password_input.secret, "Saved address is shown and password stays masked")
	check(not login.remember_me.button_pressed and not FileAccess.file_exists(login.remembered.path), "Remembering credentials is opt-in")
	for node_name in ["ServerAddress", "Username", "Password", "AuthButton", "SwitchButton", "RememberMe", "Status", "Back"]:
		var control: Control = login.get_node(node_name)
		check(Rect2(0, 0, 320, 480).encloses(control.get_rect()), "Control remains inside the game area: " + node_name)
	await capture("02_login")
	check(login.address_input.get_rect().end.x == login.password_input.get_rect().end.x, "Address field uses the freed button space and aligns with credentials")
	login.address_input.text = "invalid address"
	login.address_input.text_submitted.emit(login.address_input.text)
	check(login.address_input.editable and not login.status.text.is_empty(), "Enter validates an edited address while keeping invalid input editable")
	check(settings.load_address() == "https://game.example.com/ssjx" and login.discovery.request == null, "Invalid edits preserve the saved address without sending a request")
	login.address_input.text = "https://game.example.com/ssjx"
	login.auth_button.pressed.emit()
	check(not login.register_mode and login.status.text.contains("请输入"), "Login button directly validates a login request")
	login.switch_button.pressed.emit()
	check(login.register_mode and login.status.text.contains("请输入"), "Register button directly validates a registration request")
	# Reject these test credentials locally: no external auth requests are sent.
	login.address_input.text = "http://203.0.113.1:8080"
	login.username_input.text = "ui_player"
	login.password_input.text = "ui-password-1234"
	login.switch_button.pressed.emit()
	check(login.register_mode and login.password_input.text.is_empty() and login.status.text.contains("HTTPS") and not OnlineAccount.busy, "Registration uses its own action, clears the password and keeps preflight validation")
	login.password_input.text = "ui-password-1234"
	login.auth_button.pressed.emit()
	check(not login.register_mode and login.password_input.text.is_empty() and login.status.text.contains("HTTPS"), "Login remains a distinct action after registration")
	var transport_results: Array = []
	OnlineAccount.completed.connect(func(_action: String, result: Dictionary) -> void: transport_results.append(result), CONNECT_ONE_SHOT)
	OnlineAccount._action = "login"
	OnlineAccount._on_response(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, PackedStringArray(), PackedByteArray(), OnlineAccount._generation)
	check(transport_results.size() == 1 and transport_results[0].code == "NETWORK_ERROR" and transport_results[0].transport_error == "TLS_HANDSHAKE_ERROR", "TLS failures retain the retry contract and expose only a transport category")
	check(login.status.text.contains("HTTPS握手失败") and login.status.text.contains("端口") and not login.status.text.contains("网络请求未确认"), "Account page distinguishes TLS protocol/certificate failures from unknown request outcomes")
	OnlineAccount.completed.connect(func(_action: String, result: Dictionary) -> void: transport_results.append(result), CONNECT_ONE_SHOT)
	OnlineAccount._action = "login"
	OnlineAccount._on_response(HTTPRequest.RESULT_CANT_RESOLVE, 0, PackedStringArray(), PackedByteArray(), OnlineAccount._generation)
	check(transport_results.size() == 2 and transport_results[1].code == "NETWORK_ERROR" and transport_results[1].transport_error == "DNS_ERROR", "DNS failures retain the retry contract with a specific safe transport category")
	check(login.status.text.contains("域名解析失败") and login.status.text.contains("DNS") and not login.status.text.contains("网络请求未确认"), "Unresolved tunnel hostname identifies the missing DNS route instead of a generic credential error")
	login.address_input.text = "https://game.example.com/ssjx"
	login.get_node("Back").pressed.emit()
	check(app.modal == null and cover.active, "Return restores title input")
	check(Game.player == offline, "Account UI leaves offline character state unchanged")
	var store := RememberedLogin.new()
	check(not FileAccess.file_exists(store.path), "Unchecked and unsuccessful authentication never writes credentials")
	check(store.remember("https://game.example.com/ssjx/", "test01", "remember-password-1234"), "Encrypted credentials can be saved for a normalized server")
	var encrypted := FileAccess.get_file_as_bytes(store.path)
	check(not encrypted.is_empty() and not encrypted.get_string_from_ascii().contains("remember-password-1234") and not encrypted.get_string_from_ascii().contains("test01"), "Username and password are not written as plaintext")
	check(store.load_saved("https://other.example.com").is_empty() and store.load_saved("local").is_empty(), "Other servers and local mode never receive saved credentials")
	check(not store.remember("http://203.0.113.1:8080", "test01", "remember-password-1234"), "Insecure remote targets cannot replace the remembered identity")
	cover.rows[0].pressed.emit()
	login = app.modal.get_node("ServerLogin")
	check(login.username_input.text == "test01" and login.password_input.text == "remember-password-1234" and login.remember_me.button_pressed, "Reopening the scene restores username, password and selection")
	check(login.password_input.secret and not OnlineAccount.busy, "Restored password stays masked and does not automatically log in")
	check(login.remember_me.position.y > login.password_input.get_rect().end.y and login.remember_me.get_rect().end.y < login.auth_button.position.y, "Remember control has its own aligned row between password and login")
	login._account_result("logout", {"ok": true})
	await capture("03_remembered_login")
	var hover := InputEventMouseMotion.new()
	hover.position = login.remember_me.get_global_rect().get_center()
	get_viewport().push_input(hover, true)
	await get_tree().process_frame
	check(login.remember_me.get_draw_mode() == BaseButton.DRAW_HOVER_PRESSED, "Checked Remember Me actually enters hovered-pressed state")
	var hovered_color := login.remember_me.get_theme_color("font_hover_pressed_color")
	check(hovered_color.srgb_to_linear().get_luminance() < 0.25 and login.remember_me.get_theme_color("font_focus_color").srgb_to_linear().get_luminance() < 0.25, "Checked hover and keyboard focus retain readable dark text")
	await capture("04_remembered_hover")
	login.address_input.text = "https://other.example.com"
	login.address_input.text_changed.emit(login.address_input.text)
	check(login.password_input.text.is_empty() and not login.remember_me.button_pressed, "Editing the server clears the autofilled password")
	login.address_input.text = "https://game.example.com/ssjx"
	login._restore_credentials()
	login.remember_me.button_pressed = false
	check(not FileAccess.file_exists(store.path) and not FileAccess.file_exists(store.path + ".key"), "Unchecking immediately deletes saved credentials and key")
	login.get_node("Back").pressed.emit()
	cover.rows[0].pressed.emit()
	login = app.modal.get_node("ServerLogin")
	check(login.username_input.text.is_empty() and login.password_input.text.is_empty() and not login.remember_me.button_pressed, "Next scene stays empty after remembering is disabled")
	login.address_input.text = "local"
	login._update_controls()
	check(login.remember_me.disabled, "Local game does not offer password persistence")
	login.address_input.text = "https://game.example.com/ssjx"
	login.get_node("Back").pressed.emit()
	check(store.remember("https://game.example.com/ssjx", "test01", "remember-password-1234"), "Credential store can be recreated after clearing")
	DirAccess.remove_absolute(store.path + ".key")
	check(store.load_saved("https://game.example.com/ssjx").is_empty() and not store.last_error.is_empty(), "Missing local key falls back to manual entry")
	check(store.forget(), "Unreadable remembered credentials can still be cleared")
	cover.rows[1].pressed.emit()
	check(app.modal != null and not cover.active, "Exit menu opens its confirmation")
	app._close_modal()
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(isolated)
	OS.set_environment("SSJX_CONNECTION_PATH", old_path)
	print("LOGIN UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
