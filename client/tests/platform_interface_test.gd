extends Node

const ENTRY := preload("res://scripts/interface/platform.gd")
var checks := 0
var failures := 0
var directory := ""

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PLATFORM FAIL: " + description)

func _run() -> void:
	var ready_result := await Platform.when_ready()
	check(ready_result.ok and Platform.is_available(), "Explicit readiness succeeds on native")
	check(Platform.context.target == "native", "Factory selects the native runtime")
	var capabilities := Platform.context.capabilities()
	capabilities.native_file_storage = false
	check(Platform.context.capabilities().native_file_storage, "Capability snapshot cannot be mutated by its caller")
	check(not Platform.context.capabilities().web_runtime, "Native does not claim Web support")
	var original_context := Platform.context
	Platform.initialize("web")
	check(Platform.context == original_context, "Initialization is idempotent, not a runtime platform switch")
	var unsupported := ENTRY.new()
	unsupported.initialize("web")
	add_child(unsupported)
	var failed := await unsupported.when_ready()
	check(not failed.ok and failed.code == "PLATFORM_UNSUPPORTED" and not failed.message.is_empty(), "Unimplemented Web fails explicitly, never falls back to native")
	check(unsupported.state == unsupported.State.FAILED and unsupported.context == null, "Failure is terminal and has no partial interfaces")
	unsupported.queue_free()
	check(PlatformStorageInterface.new().read_text("unused").status == PlatformResult.Status.UNSUPPORTED, "Base contract does not report unsupported reads as success")
	check(not PlatformRuntimeConfigInterface.new().local_path("save").ok, "Base config is not a fake success")
	directory = "user://platform_test_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Create isolated test directory")
	_test_config()
	_test_storage()
	await _test_save_compatibility()
	await _test_display()
	_test_lifecycle()
	await _test_initialization_failure(failed)
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory.path_join("existing_directory"))
	DirAccess.remove_absolute(directory)
	await get_tree().process_frame
	print("PLATFORM INTERFACE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_config() -> void:
	var config := Platform.context.runtime_config
	for kind in ["save", "connection"]:
		var key := "SSJX_SAVE_PATH" if kind == "save" else "SSJX_CONNECTION_PATH"
		var previous := OS.get_environment(key)
		OS.set_environment(key, "")
		check(config.local_path(kind).value == ("user://shushan_save.json" if kind == "save" else "user://connection.cfg"), "Keep default path for " + kind)
		OS.set_environment(key, directory.path_join(kind))
		check(config.local_path(kind).value == directory.path_join(kind), "Native environment override for " + kind)
		check(config.local_path(kind, directory.path_join("explicit")).value.ends_with("explicit"), "Explicit path wins for " + kind)
		OS.set_environment(key, previous)
	check(config.local_path("SSJX_DATABASE_URL").code == "UNKNOWN_SETTING", "No generic environment or server-secret accessor")

func _test_storage() -> void:
	var storage := Platform.context.storage
	var path := directory.path_join("storage.txt")
	check(storage.read_text(path).code == "NOT_FOUND" and not storage.exists(path), "Missing is a stable result, not empty-file success")
	var write := storage.write_text_atomic(path, "离线内容\n")
	check(write.ok and write.value.durability == "native_file" and write.value.written, "Write returns an explicit native-file receipt")
	check(write.value.bytes == "离线内容\n".to_utf8_buffer().size(), "Receipt counts actual UTF-8 bytes")
	check(storage.exists(path) and storage.read_text(path).value == "离线内容\n", "Read back exact Unicode and newline content")
	check(storage.write_text_atomic(path, "replacement").ok and storage.read_text(path).value == "replacement", "Atomic replacement preserves existing behavior")
	check(not storage.exists(path + ".tmp"), "Successful replacement leaves no temporary file")
	check(storage.read_text(path, 3).code == "TOO_LARGE", "Oversized read is rejected before loading content")
	check(storage.read_text(path, 0).code == "INVALID_LIMIT", "Invalid read limit is distinct from IO failure")
	check(storage.read_text(path).value == "replacement", "Rejected read does not modify original")
	var missing := directory.path_join("missing_parent/file")
	check(storage.write_text_atomic(missing, "x").code == "WRITE_FAILED", "Missing/unwritable directory is a visible write failure")
	var existing := directory.path_join("existing_directory")
	DirAccess.make_dir_absolute(existing)
	check(storage.write_text_atomic(existing, "cannot replace directory").code == "REPLACE_FAILED", "Rename failure is not reported as written")
	check(DirAccess.dir_exists_absolute(existing) and not storage.exists(existing + ".tmp"), "Failed replacement preserves target and removes only its own temporary file")
	var settings := ServerConnectionSettings.new(directory.path_join("connection.cfg"))
	check(settings.save_address(" HTTPS://Game.Example.com/ssjx/ "), "Connection config still saves normalized addresses")
	check(ServerConnectionSettings.new(settings.settings_path).load_address() == "https://game.example.com/ssjx", "Legacy ConfigFile format still round-trips")
	var content := storage.read_text(settings.settings_path).value as String
	check(not settings.save_address("bad address") and storage.read_text(settings.settings_path).value == content, "Invalid address cannot overwrite a valid configuration")
	check(not content.contains("password") and not content.contains("token"), "Address-only config contains no credentials")

func _test_save_compatibility() -> void:
	var previous_path := Game.save_path
	var previous_player := Game.player.duplicate(true)
	Game.save_path = directory.path_join("legacy.json")
	Game.new_player("旧版存档", 2, 1, 1)
	var legacy := Game.player.duplicate(true)
	for key in ["gender", "signature", "title", "ingots", "guild_contribution", "essence", "weapon_owned", "bag_order"]: legacy.erase(key)
	var file := FileAccess.open(Game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy))
	file.close()
	check((await Game.probe_save()).value and (await Game.load_game()).ok, "Read pre-interface v1 save from its existing path")
	check(Game.player.gender == 0 and Game.player.signature == "" and Game.player.weapon_owned, "Old optional defaults remain business-owned")
	check((await Game.save_game()).ok, "Awaitable native save returns its confirmed receipt")
	var stored := Platform.context.storage.read_text(Game.save_path)
	check(JSON.parse_string(stored.value) == JSON.parse_string(JSON.stringify(Game.player)) and int(Game.player.version) == 1, "No new wrapper, platform fields or save-version migration")
	var player := Game.player.duplicate(true)
	Platform.context.storage.write_text_atomic(Game.save_path, "{broken")
	check(not (await Game.load_game()).ok and Game.player == player and not Game.last_save_error.is_empty(), "Malformed file does not change current player")
	check(Platform.context.storage.read_text(Game.save_path).value == "{broken", "Malformed original remains untouched")
	Game.save_path = directory.path_join("missing_parent/save.json")
	check(not (await Game.save_game()).ok and not Game.last_save_error.is_empty(), "Failed native save remains a failure with readable explanation")
	Game.save_path = directory.path_join("absent.json")
	check(not (await Game.load_game()).ok and Game.last_save_error.is_empty(), "Missing slot clears stale errors")
	Game.save_path = previous_path
	Game.player = previous_player

func _test_display() -> void:
	var display := Platform.context.display
	var window := get_tree().root
	var previous := window.size
	var events: Array[Dictionary] = []
	var listener := func(value: Dictionary) -> void: events.append(value)
	display.changed.connect(listener)
	for dimensions in [Vector2i(640, 960), Vector2i(960, 540)]:
		window.size = dimensions
		await get_tree().process_frame
		check(display.snapshot().window_pixels == dimensions, "Display reports native window pixels " + str(dimensions))
		check(display.snapshot().logical_rect.size.is_equal_approx(Vector2(320, 480)), "Display does not rewrite game portrait coordinates")
		var logical := Vector2(112, 237)
		check(display.window_to_logical(display.logical_to_window(logical)).is_equal_approx(logical), "Physical/logical coordinate conversion round-trip")
	check(not events.is_empty(), "Window size updates are observable, not only a startup snapshot")
	display.changed.disconnect(listener)
	window.size = previous

func _test_lifecycle() -> void:
	var port := Platform.context.lifecycle
	var before := port.snapshot()
	var identity := OnlineAccount.account.duplicate(true)
	var player := Game.player.duplicate(true)
	port.focused = true
	port.suspended = false
	var events: Array[String] = []
	var listener := func(event: String) -> void: events.append(event)
	port.changed.connect(listener)
	for event in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_OUT,
		Node.NOTIFICATION_APPLICATION_FOCUS_IN, Node.NOTIFICATION_APPLICATION_PAUSED,
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]: port.notification(event)
	check(events == ["focus_lost", "focus_gained", "suspended", "resumed"], "Native lifecycle maps and deduplicates state transitions")
	check(port.snapshot() == {"focused": true, "suspended": false}, "Dynamic lifecycle state is distinct from capabilities")
	check(Game.player == player and OnlineAccount.account == identity, "Lifecycle adapter does not mutate game/account state")
	port.changed.disconnect(listener)
	port.focused = before.focused
	port.suspended = before.suspended

func _test_initialization_failure(failed: PlatformResult) -> void:
	var state := Platform.state
	var result := Platform.last_result
	var player := Game.player.duplicate(true)
	Game.new_player("就绪校验", 1, 0)
	Platform.state = Platform.State.FAILED
	Platform.last_result = failed
	check(not (await Game.save_game()).ok and not Game.last_save_error.is_empty(), "Game refuses storage while platform is unavailable")
	var settings := ServerConnectionSettings.new()
	check(not settings.save_address("local") and not settings.last_error.is_empty(), "Config refuses writes before readiness")
	var responses: Array[Dictionary] = []
	var listener := func(_action: String, value: Dictionary) -> void: responses.append(value)
	OnlineAccount.completed.connect(listener)
	OnlineAccount.login("https://game.example.com", "test", "not-sent")
	check(responses.size() == 1 and responses[0].code == "PLATFORM_NOT_READY" and not OnlineAccount.busy, "Account fails before any credential request when platform is unavailable")
	OnlineAccount.completed.disconnect(listener)
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	check(app.original_cover == null and not app.is_processing(), "Initialization failure presents explanation instead of entering the game")
	check(app.get_node("UI").get_child_count() > 0, "Failure has visible UI, not a silent black screen")
	app.queue_free()
	await get_tree().process_frame
	Platform.state = state
	Platform.last_result = result
	Game.player = player
