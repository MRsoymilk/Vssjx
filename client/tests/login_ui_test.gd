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
	check(not login.address_input.editable and login.connect_button.text == "修改", "Server address is read-only until Modify is selected")
	check(login.address_input.text == "https://game.example.com/ssjx" and login.password_input.secret, "Saved address is shown and password stays masked")
	for node_name in ["ServerAddress", "ConnectButton", "Username", "Password", "AuthButton", "SwitchButton", "Status", "Back"]:
		var control: Control = login.get_node(node_name)
		check(Rect2(0, 0, 320, 480).encloses(control.get_rect()), "Control remains inside the game area: " + node_name)
	await capture("02_login")
	login.connect_button.pressed.emit()
	check(login.address_input.editable and login.connect_button.text == "保存", "Modify enables editing and changes the action to Save")
	login.address_input.text = "invalid address"
	login.connect_button.pressed.emit()
	check(login.address_input.editable and not login.connect_button.disabled and not login.status.text.is_empty(), "Invalid address stays editable and reports an error")
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
	login.address_input.text = "https://game.example.com/ssjx"
	login.get_node("Back").pressed.emit()
	check(app.modal == null and cover.active, "Return restores title input")
	check(Game.player == offline, "Account UI leaves offline character state unchanged")
	cover.rows[1].pressed.emit()
	check(app.modal != null and not cover.active, "Exit menu opens its confirmation")
	app._close_modal()
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(isolated)
	OS.set_environment("SSJX_CONNECTION_PATH", old_path)
	print("LOGIN UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
