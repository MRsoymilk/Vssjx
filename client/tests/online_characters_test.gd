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

func capture(stem: String) -> void:
	var folder := OS.get_environment("SSJX_CHARACTER_CAPTURE_PATH")
	if folder.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(folder.path_join(stem + ".png")) == OK, "Screenshot saved")

func _run() -> void:
	var backend := OS.get_environment("SSJX_TEST_SERVER_URL")
	if backend.is_empty():
		push_error("Use tests/run_characters.py with its disposable database")
		get_tree().quit(1)
		return
	var vectors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SSJX_NICKNAME_VECTORS")))
	for sample in vectors.valid:
		check(OnlineAccount.canonical_nickname(sample.raw) == {"display_name": sample.display_name, "name_key": sample.name_key}, "Client normalizes contract nickname")
	for value in vectors.invalid: check(not OnlineAccount.valid_nickname(value), "Client rejects contract nickname")
	var old_connection := OS.get_environment("SSJX_CONNECTION_PATH")
	var isolated := "user://online_character_%d.cfg" % OS.get_process_id()
	OS.set_environment("SSJX_CONNECTION_PATH", isolated)
	var old_save_path := Game.save_path
	Game.save_path = "user://online_character_%d_save.json" % OS.get_process_id()
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string("offline-save-sentinel")
	file.close()
	var before := Game.player.duplicate(true)
	OnlineAccount.clear()
	OnlineAccount.register_account(backend, "character_ui", "character-ui-password-1234")
	await OnlineAccount.completed
	OnlineAccount.login(backend, "character_ui", "character-ui-password-1234")
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(), "Online account authenticated")
	var app: Control = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(app)
	app._server_login()
	var login := app.modal.find_child("ServerLogin", true, false) as ServerLogin
	check(login.switch_button.text == "线上角色", "Authenticated account exposes online lobby")
	login._switch_mode()
	var lobby := app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	await OnlineAccount.completed
	check(lobby != null and not lobby.create_button.disabled and OnlineAccount.characters.is_empty(), "Empty online account can create")
	lobby.nickname.text = "ＡＢ"
	lobby._create()
	check(not OnlineAccount.busy and lobby.status.text.contains("昵称须"), "Invalid nickname rejected before request")
	lobby.nickname.text = "青衫ab_1"
	lobby._create()
	check(lobby.create_button.disabled and not lobby.nickname.editable, "Duplicate submit and edits locked in flight")
	await OnlineAccount.completed
	check(lobby.status.text.contains("占用") and lobby.nickname.text == "青衫ab_1" and OnlineAccount.pending_creation.is_empty(), "Name refusal preserves input and ends operation")
	await capture("01_name_taken")
	lobby.nickname.text = "界面青衫"
	lobby.job.select(2)
	lobby.gender.select(1)
	lobby.school.select(1)
	lobby._create()
	await OnlineAccount.completed
	check(not OnlineAccount.pending_creation.is_empty() and lobby.create_button.text == "重试原创建请求", "Lost committed response preserves operation")
	check(not lobby.nickname.editable and lobby.job.disabled and lobby.status.text.contains("结果未知"), "Unknown result prevents changed business intent")
	var original := OnlineAccount.pending_creation.duplicate(true)
	await capture("02_unknown_result")
	lobby._create()
	await OnlineAccount.completed
	check(OnlineAccount.pending_creation.is_empty() and OnlineAccount.characters.size() == 1, "Retry resolves original receipt")
	var character: Dictionary = OnlineAccount.characters[0]
	check(character.display_name == "界面青衫" and int(character.job) == 2 and int(character.gender) == 1 and int(character.school) == 1, "Server confirms typed character selection")
	for field in ["id", "state_revision"]:
		var malformed := character.duplicate(true)
		malformed[field] += "\n"
		check(not OnlineAccount._valid_character(malformed), "Strict response identities reject trailing newline")
	var overflowing := character.duplicate(true)
	overflowing.state_revision = "9223372036854775808"
	check(not OnlineAccount._valid_character(overflowing), "Revision overflow rejected without float conversion")
	check(lobby.create_button.disabled and not lobby.enter_button.disabled and lobby.status.text.contains("同图移动"), "Existing character offers explicit shared-world entry")
	check(original.operation_id.length() == 36, "Creation uses random UUID operation identity")
	await capture("03_character_created")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "offline-save-sentinel", "Online creation never changes offline player or save")
	check(app.mode == "home" and app.world == null, "Online lobby never starts offline simulation")
	var saved := FileAccess.get_file_as_string(isolated)
	check(not saved.contains("界面青衫") and not saved.contains("character_ui") and not saved.contains(OnlineAccount._access_token), "Preferences persist no online character or credentials")
	app._close_modal()
	OnlineAccount.logout()
	await OnlineAccount.completed
	OnlineAccount.login(backend, "character_ui", "character-ui-password-1234")
	await OnlineAccount.completed
	OnlineAccount._expires_at = Time.get_unix_time_from_system() - 1.0
	app._online_characters()
	var event: Array = await OnlineAccount.completed
	if event[0] == "refresh": await OnlineAccount.completed
	lobby = app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	check(OnlineAccount.characters.size() == 1 and OnlineAccount.characters[0].id == character.id, "Relogin + automatic refresh recovers server character")
	check(lobby.create_button.disabled, "Recovered character cannot be recreated")
	app._close_modal()
	OnlineAccount.refresh()
	app._online_characters()
	await OnlineAccount.completed
	lobby = app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	var deadline := Time.get_ticks_msec() + 10000
	while not lobby._loaded and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(lobby._loaded and not lobby.refresh_button.disabled, "Page opened during background refresh eventually loads")
	OnlineAccount._refresh_expires_at = Time.get_unix_time_from_system() - 1.0
	OnlineAccount._process(0.0)
	check(not lobby.nickname.editable and lobby.status.text.contains("失效"), "Expired session disables character operations")
	app._close_modal()
	OnlineAccount.register_account(backend, "character_ui_pending", "character-ui-password-1234")
	await OnlineAccount.completed
	OnlineAccount.login(backend, "character_ui_pending", "character-ui-password-1234")
	await OnlineAccount.completed
	app._online_characters()
	await OnlineAccount.completed
	lobby = app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	lobby.nickname.text = "未决修士"
	lobby._create()
	await OnlineAccount.completed
	var unconfirmed := OnlineAccount.pending_creation.duplicate(true)
	app._close_modal()
	app._online_characters()
	await OnlineAccount.completed
	lobby = app.modal.find_child("OnlineCharacters", true, false) as OnlineCharacters
	check(OnlineAccount.characters.is_empty() and OnlineAccount.pending_creation == unconfirmed and not unconfirmed.is_empty(), "An empty list after reopening does not discard unresolved creation")
	check(lobby.nickname.text == "未决修士" and not lobby.nickname.editable and not lobby.create_button.disabled, "Reopened page offers only original-request retry")
	lobby._create()
	await OnlineAccount.completed
	check(OnlineAccount.characters.size() == 1 and OnlineAccount.characters[0].display_name == "未决修士", "Uncommitted unknown request can be retried after reopening")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "offline-save-sentinel", "Reopened creation also preserves offline save")
	OnlineAccount.list_characters()
	OnlineAccount.clear()
	await OnlineAccount.completed
	check(OnlineAccount.characters.is_empty() and not OnlineAccount.is_logged_in(), "Late response cannot restore data after session clear")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_save_path
	OS.set_environment("SSJX_CONNECTION_PATH", old_connection)
	if FileAccess.file_exists(isolated): DirAccess.remove_absolute(isolated)
	print("ONLINE CHARACTER UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
