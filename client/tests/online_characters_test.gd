extends Node
var checks := 0
var failures := 0
var app: Control

func _ready() -> void: call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)

func until(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(predicate.call(), message)

func selecting() -> bool:
	return app.mode == "online_select" and app.character_selection != null and app.character_selection.get_node("Online")._loaded and not OnlineAccount.busy

func open_creation() -> void:
	await until(selecting, "Character selection finishes account lookup")
	app.character_selection.get_node("Options/Create").pressed.emit()
	await until(func() -> bool: return app.mode == "online_create" and app.creation != null and app.creation.get_node("Online")._loaded, "Selection opens original creation scene")

func capture(stem: String) -> void:
	var folder := OS.get_environment("SSJX_CHARACTER_CAPTURE_PATH")
	if folder.is_empty(): return
	await RenderingServer.frame_post_draw
	check(get_tree().root.get_texture().get_image().save_png(folder.path_join(stem + ".png")) == OK, "Screenshot saved")

func idle_account() -> void:
	await until(func() -> bool: return not OnlineAccount.busy, "Account request finishes")

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
	ServerConnectionSettings.new().save_address(backend)
	var old_save_path := Game.save_path
	Game.save_path = "user://online_character_%d_save.json" % OS.get_process_id()
	FileAccess.open(Game.save_path, FileAccess.WRITE).store_string("offline-save-sentinel")
	var before := Game.player.duplicate(true)
	OnlineAccount.clear()
	OnlineAccount.register_account(backend, "character_ui", "character-ui-password-1234")
	await idle_account()
	OnlineAccount.login(backend, "character_ui", "character-ui-password-1234")
	await idle_account()
	check(OnlineAccount.is_logged_in(), "Online account authenticated")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._server_login()
	var login: ServerLogin = app.modal.get_node("ServerLogin")
	check(login.auth_button.text == "选择角色", "Authenticated account can continue")
	login.auth_button.pressed.emit()
	await open_creation()
	var page: OriginalCharacterCreation = app.creation
	var flow: OnlineCreationFlow = page.get_node("Online")
	check(page.scene_file_path == "res://scenes/ui/character_creation.tscn" and not page.get_node("Create").disabled, "Original scene offers server-backed creation")
	page.nickname.text = "ＡＢ"
	flow._create()
	check(not OnlineAccount.busy and flow.status.text.contains("昵称须"), "Invalid nickname rejected before request")
	page.nickname.text = "青衫ab_1"
	flow._create()
	check(page.get_node("Create").disabled and not page.nickname.editable, "Duplicate submit and edits locked in flight")
	await idle_account()
	check(flow.status.text.contains("占用") and page.nickname.text == "青衫ab_1" and OnlineAccount.pending_creation.is_empty(), "Name refusal preserves input and ends operation")
	await capture("01_name_taken")
	page.nickname.text = "界面青衫"
	page.select_variant(5)
	check(flow.school.disabled and flow.school.get_item_text(0)=="闲云野鹤","Creation starts without a school and directs admission to an NPC")
	flow._create()
	await idle_account()
	check(not OnlineAccount.pending_creation.is_empty() and page.get_node("Create").text == "重试", "Lost committed response preserves operation")
	check(not page.nickname.editable and flow.school.disabled and flow.status.text.contains("保留原"), "Unknown result prevents changed business intent")
	var original := OnlineAccount.pending_creation.duplicate(true)
	await capture("02_unknown_result")
	page.get_node("Create").pressed.emit()
	await until(selecting, "Retry resolves receipt and opens selection")
	check(not app.ui.has_node("OnlineWorld"), "Creation retry does not automatically enter world")
	app.character_selection.enter_button.pressed.emit()
	await until(func() -> bool: return app.mode == "online_world", "Explicit Enter starts shared world")
	check(OnlineAccount.pending_creation.is_empty() and OnlineAccount.characters.size() == 1, "Retry resolves original receipt")
	var character: Dictionary = OnlineAccount.characters[0]
	check(character.display_name == "界面青衫" and int(character.job) == 2 and int(character.gender) == 1 and int(character.school) == SchoolRules.UNJOINED, "Server confirms portrait and unjoined identity")
	for field in ["id", "state_revision"]:
		var malformed := character.duplicate(true)
		malformed[field] += "\n"
		check(not OnlineAccount._valid_character(malformed), "Strict response identities reject trailing newline")
	var overflowing := character.duplicate(true)
	overflowing.state_revision = "9223372036854775808"
	check(not OnlineAccount._valid_character(overflowing), "Revision overflow rejected without float conversion")
	check(app.ui.get_node("OnlineWorld").character_id == character.id and app.world == null, "Created character enters online simulation only")
	check(original.operation_id.length() == 36, "Creation uses random UUID operation identity")
	await capture("03_character_created")
	app._home()
	await idle_account()
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "offline-save-sentinel", "Online creation preserves offline state")
	var saved := FileAccess.get_file_as_string(isolated)
	check(not saved.contains("界面青衫") and not saved.contains("character_ui") and not saved.contains(OnlineAccount._access_token), "Preferences contain no online state or credentials")
	OnlineAccount.logout()
	await idle_account()
	OnlineAccount.login(backend, "character_ui", "character-ui-password-1234")
	await idle_account()
	OnlineAccount._expires_at = Time.get_unix_time_from_system() - 1.0
	app._online_characters()
	await until(selecting, "Relogin with automatic refresh stops on existing character selection")
	check(OnlineAccount.characters.size() == 1 and OnlineAccount.characters[0].id == character.id and app.creation == null, "Recovered character is reused without creating again")
	check(not app.character_selection.get_node("Options/Create").disabled, "An account with an existing character can create another")
	for extra in 4:
		await open_creation()
		page = app.creation
		flow = page.get_node("Online")
		check(page.active and not page.get_node("Create").disabled, "Existing roster no longer redirects creation back to selection")
		page.nickname.text = "界面次角%d" % extra
		page.select_variant(extra)
		flow._create()
		await idle_account()
		if not OnlineAccount.pending_creation.is_empty():
			page.get_node("Create").pressed.emit()
		await until(selecting, "Additional creation returns to selection with the complete roster")
		check(OnlineAccount.characters.size() == extra + 2 and app.character_selection.get_node("Details/Name").text == "界面次角%d" % extra, "New character is selected without losing previous characters")
	check(app.character_selection.get_node("Options/Create").disabled and app.character_selection.characters.size() == 5, "Five characters fill the carousel and disable additional creation")
	await capture("04_five_characters")
	app.character_selection.step(1)
	check(app.character_selection.characters[app.character_selection.selected_index].id == character.id, "Carousel wraps from the fifth character back to the original")
	app.character_selection.enter_button.pressed.emit()
	await until(func() -> bool: return app.mode == "online_world", "Original character remains playable after four more creations")
	check(app.ui.get_node("OnlineWorld").character_id == character.id and Game.player == before, "Entering a selected character uses its own ID and never overwrites offline state")
	app._home()
	await idle_account()
	OnlineAccount.logout()
	await idle_account()
	OnlineAccount.register_account(backend, "character_ui_pending", "character-ui-password-1234")
	await idle_account()
	OnlineAccount.login(backend, "character_ui_pending", "character-ui-password-1234")
	await idle_account()
	OnlineAccount.refresh()
	app._online_characters()
	await open_creation()
	page = app.creation
	flow = page.get_node("Online")
	page.nickname.text = "未决修士"
	flow._create()
	await idle_account()
	var unconfirmed := OnlineAccount.pending_creation.duplicate(true)
	app._home()
	app._online_characters()
	await open_creation()
	page = app.creation
	flow = page.get_node("Online")
	check(OnlineAccount.characters.is_empty() and OnlineAccount.pending_creation == unconfirmed and not unconfirmed.is_empty(), "Empty list preserves unresolved operation")
	check(page.nickname.text == "未决修士" and not page.nickname.editable and not page.get_node("Create").disabled, "Reopened scene offers original-request retry")
	page.get_node("Create").pressed.emit()
	await until(selecting, "Uncommitted retry returns to role selection")
	check(OnlineAccount.characters.size() == 1 and OnlineAccount.characters[0].display_name == "未决修士", "Retried creation belongs to the current account")
	app._home()
	await idle_account()
	# Session expiry must fence selection and discard a late character list.
	app._online_characters()
	var selection: OriginalCharacterSelection = app.character_selection
	OnlineAccount._refresh_expires_at = Time.get_unix_time_from_system() - 1.0
	OnlineAccount._process(0.0)
	check(selection.enter_button.disabled and selection.status.text.contains("失效"), "Expired session disables selection entry")
	await idle_account()
	check(OnlineAccount.characters.is_empty() and not OnlineAccount.is_logged_in(), "Late response cannot restore data after session expiry")
	check(Game.player == before and FileAccess.get_file_as_string(Game.save_path) == "offline-save-sentinel", "All account transitions preserve local save")
	app.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_save_path
	OS.set_environment("SSJX_CONNECTION_PATH", old_connection)
	DirAccess.remove_absolute(isolated)
	print("ONLINE CHARACTER UI: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
