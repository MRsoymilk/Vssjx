extends Node
var checks := 0
var failures := 0
var app: Control

func _ready() -> void: call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func enter_local() -> ServerLogin:
	app.original_cover.rows[0].pressed.emit()
	var form: ServerLogin = app.modal.get_node("ServerLogin")
	form.address_input.text = "  LOCAL  "
	form.connect_server()
	check(form.address_input.text == "local" and form.discovery.request == null and not OnlineAccount.busy, "Local address never probes a server")
	check(not form.username_input.editable and not form.password_input.editable and form.switch_button.disabled, "Local play requires no account or registration")
	form.auth_button.pressed.emit()
	return form

func _run() -> void:
	var old_path := Game.save_path
	var old_connection := OS.get_environment("SSJX_CONNECTION_PATH")
	var old_player := Game.player.duplicate(true)
	var account_before := OnlineAccount.account.duplicate(true)
	var phase := OS.get_environment("SSJX_LOCAL_TEST_PHASE")
	var path := OS.get_environment("SSJX_LOCAL_TEST_PATH")
	if path.is_empty(): path = "user://local_mode_test_%d.json" % OS.get_process_id()
	Game.save_path = path
	OS.set_environment("SSJX_CONNECTION_PATH", path + ".cfg")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	if phase != "read":
		enter_local()
		check(app.mode == "create" and app.creation != null, "First local entry creates a local character")
		app.creation.select_variant(5)
		app.selected_school = 1
		app.nickname.text = "本地青衫"
		app.creation.create_requested.emit()
		app._close_modal()
		check(app.mode == "world" and app.world != null and FileAccess.file_exists(path), "Local character enters the normal game world and is saved")
		Game.player.hp = 51
		Game.player.mp = 23
		Game.player.gold = 73
		Game.player.potions = 4
		Game.player.quest = 2
		Game.player.equipped = true
		Game.player.signature = "本地保存"
		app.world.cell = Vector2i(17, 17)
		app.world.stop_moving()
		app._process(10.1)
		check(FileAccess.get_file_as_string(path).contains("本地保存"), "Normal autosave writes local progress")
		app._home()
		Game.player = {}
	if phase != "write":
		app.original_cover.rows[0].pressed.emit()
		var form: ServerLogin = app.modal.get_node("ServerLogin")
		check(form.address_input.text == "local", "Local service preference survives reopening or a process restart")
		form.auth_button.pressed.emit()
		check(app.mode == "world" and app.creation == null, "An existing local save resumes without recreating the character")
		var expected := {"name": "本地青衫", "job": 2, "gender": 1, "school": 1, "hp": 51, "mp": 23, "gold": 73, "potions": 4, "quest": 2, "equipped": true, "signature": "本地保存", "cell": [17, 17]}
		for key in expected:
			var actual: Variant = Game.player.get(key)
			if key == "cell": check(Vector2i(actual[0], actual[1]) == Vector2i(17, 17), "Local save restores cell")
			else: check(actual == expected[key], "Local save restores " + key)
		check(app.world.cell == Vector2i(17, 17), "World starts at the saved position")
		app._home()
		FileAccess.open(path, FileAccess.WRITE).store_string("{invalid-save")
		enter_local()
		check(app.mode == "home" and app.modal != null and FileAccess.get_file_as_string(path) == "{invalid-save", "A corrupt local save is reported and never replaced with a new character")
	check(OnlineAccount.account == account_before and OnlineAccount._request == null, "Local mode neither authenticates nor changes the online account")
	app.queue_free()
	await get_tree().process_frame
	if phase != "write":
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".cfg")
	Game.player = old_player
	Game.save_path = old_path
	OS.set_environment("SSJX_CONNECTION_PATH", old_connection)
	print("LOCAL MODE %s: %d checks, %d failures" % [phase, checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
