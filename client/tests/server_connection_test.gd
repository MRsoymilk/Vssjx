extends Node

var checks := 0
var failures := 0
var app: Control
const DOMAIN := "https://game.example.com/ssjx"

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + description)

func login_form() -> ServerLogin:
	app._cover_choice("登陆游戏")
	return app.modal.find_child("ServerLogin", true, false) as ServerLogin

func capture(name_value: String) -> void:
	var output := OS.get_environment("SSJX_LOGIN_CAPTURE_PATH")
	if output.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(output.path_join(name_value + ".png")) == OK, "Login screenshot saved")

func _run() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	var phase := OS.get_environment("SSJX_TEST_PERSISTENCE_PHASE")
	if not phase.is_empty():
		var form := login_form()
		if phase == "write":
			form.address_input.text = "  HTTPS://Game.Example.com/ssjx/  "
			form._return()
			var persisted := ServerConnectionSettings.new()
			var restored := persisted.load_address()
			check(restored == DOMAIN, "Draft persisted before process exit (save: %s; load: %s)" % [form.settings.last_error, persisted.last_error])
		else:
			check(form.address_input.text == DOMAIN, "Address restored after process restart")
			app._close_modal()
		_finish()
		return
	var previous_path := OS.get_environment("SSJX_CONNECTION_PATH")
	var isolated := "user://server_connection_test_%d_%d.cfg" % [OS.get_process_id(), Time.get_ticks_usec()]
	OS.set_environment("SSJX_CONNECTION_PATH", isolated)
	var valid := {
		"127.0.0.1:8080": "http://127.0.0.1:8080",
		"192.168.1.10:9000/ssjx/": "http://192.168.1.10:9000/ssjx",
		"localhost:8080": "http://localhost:8080",
		"[::1]:8080": "http://[::1]:8080",
		"game.example.com": "https://game.example.com",
		" HTTPS://Game.Example.com/ssjx/ ": DOMAIN,
		"http://game.example.com:8080/prefix": "http://game.example.com:8080/prefix",
	}
	for raw in valid:
		var result := ServerConnectionSettings.normalize(raw)
		check(result.ok and result.address == valid[raw], "Normalize server address: " + raw)
	for raw in ["", "ftp://example.com", "ws://example.com", "http://user:pass@example.com", "https://example.com?token=secret", "https://example.com/#fragment", "127.0.0.1:0", "127.0.0.1:65536", "999.999.999.999:80", "http://bad host", "http://bad\\host", "http://-bad.example", "http://example.com/../api", "http://example.com/%2e%2e/api", "http://example.com/%oops", "http://[invalid]:8080"]:
		check(not ServerConnectionSettings.normalize(raw).ok, "Reject invalid test address: " + raw)
	var settings := ServerConnectionSettings.new(isolated)
	check(settings.load_address().is_empty(), "First launch has no saved server")
	check(settings.save_address("127.0.0.1:8080"), "Valid address is written to disk")
	check(ServerConnectionSettings.new(isolated).load_address() == "http://127.0.0.1:8080", "New settings object restores address")
	check(settings.save_address(DOMAIN), "Domain replaces old IP")
	var saved := FileAccess.get_file_as_string(isolated)
	check(not settings.save_address("not a valid address"), "Invalid edit cannot be saved")
	check(FileAccess.get_file_as_string(isolated) == saved, "Invalid edit preserves last valid file")
	var invalid_config := ConfigFile.new()
	invalid_config.set_value("connection", "server_address", 123)
	invalid_config.save(isolated)
	check(settings.load_address().is_empty() and not settings.last_error.is_empty(), "Malformed preference value is handled")
	settings.save_address(DOMAIN)
	if OS.get_name() == "Windows":
		var native_path := ProjectSettings.globalize_path(isolated + ".native").replace("/", "\\")
		var native_settings := ServerConnectionSettings.new(native_path)
		check(native_settings.save_address(DOMAIN), "Native Windows path saves preferences")
		check(ServerConnectionSettings.new(native_path).load_address() == DOMAIN, "Native Windows path restores preferences")
		DirAccess.remove_absolute(native_settings.settings_path)
	var form := login_form()
	check(form.address_input.text == DOMAIN, "Login page fills persisted domain")
	check(not app.original_cover.active, "Login page pauses cover input")
	form.address_input.text = "192.168.1.10:9000"
	form._return()
	check(app.modal == null and app.original_cover.active, "Return closes login and restores cover")
	form = login_form()
	check(form.address_input.text == "http://192.168.1.10:9000", "Return remembers valid edited address")
	await capture("01_saved_server")
	form.address_input.text = "invalid address"
	form.connect_server()
	check(not form.connect_button.disabled and not form.status.text.is_empty(), "Invalid input reports error without connecting")
	check(settings.load_address() == "http://192.168.1.10:9000", "Invalid UI input preserves saved server")
	app._close_modal()
	var backend := OS.get_environment("SSJX_TEST_SERVER_URL")
	var fixture := OS.get_environment("SSJX_TEST_FIXTURE_URL")
	if not backend.is_empty():
		form = login_form()
		form.address_input.text = backend
		form.connect_server()
		await form.discovery.completed
		check(form.status.text.begins_with("已连接："), "Godot reaches actual Rust server")
		check(not OnlineAccount.is_logged_in() and app.mode == "home", "Discovery never pretends player authentication succeeded")
		check(settings.load_address() == backend, "Submitted address is saved independently of gameplay")
		await capture("02_connected_server")
		app._close_modal()
	if not fixture.is_empty():
		for prefix in ["prefix", "wrong", "protocol", "bad", "redirect", "unavailable", "oversized"]:
			form = login_form()
			form.address_input.text = fixture + "/" + prefix
			form.connect_server()
			await form.discovery.completed
			check(form.status.text.begins_with("已连接：") == (prefix == "prefix"), "Server identity, protocol, prefix and HTTP handling: " + prefix)
			check(settings.load_address() == fixture + "/" + prefix, "Valid address survives failed connection")
			app._close_modal()
		form = login_form()
		form.address_input.text = fixture + "/slow"
		form.discovery.timeout_seconds = 0.1
		form.connect_server()
		await form.discovery.completed
		check(form.status.text.contains("超时"), "Slow server times out without clearing address")
		app._close_modal()
		form = login_form()
		form.address_input.text = fixture + "/slow"
		form.connect_server()
		check(form.connect_button.disabled, "Repeated connect is locked during request")
		form._return()
		check(app.modal == null and app.original_cover.active, "Pending connection can be cancelled")
		await get_tree().create_timer(0.1).timeout
	app.queue_free()
	await get_tree().process_frame
	OS.set_environment("SSJX_CONNECTION_PATH", previous_path)
	DirAccess.remove_absolute(isolated)
	if FileAccess.file_exists(isolated + ".tmp"): DirAccess.remove_absolute(isolated + ".tmp")
	_finish()

func _finish() -> void:
	print("SERVER CONNECTION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
