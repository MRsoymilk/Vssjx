extends Node
## Native execution of Web policy + real business consumers, not Web acceptance.
class TestWebConfig extends "res://scripts/interface/adapters/web/web_runtime_config.gd":
	var origin := "https://game.example.com"
	func _page_origin() -> String:
		return origin

class NoStorage extends PlatformStorageInterface:
	var accesses := 0
	func exists(_path: String) -> bool:
		accesses += 1
		return false
	func read_text(_path: String, _maximum_bytes: int = 1048576) -> PlatformResult:
		accesses += 1
		return PlatformResult.unsupported()
	func write_text_atomic(_path: String, _text: String) -> PlatformResult:
		accesses += 1
		return PlatformResult.unsupported()

var checks := 0
var failures := 0
var original: PlatformContext
var config := TestWebConfig.new()
var no_storage := NoStorage.new()
var directory := ""

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WEB SECURITY FAIL: " + description)

func _install() -> void:
	Platform.context = PlatformContext.new("web-policy-test", no_storage, config, original.display,
		original.lifecycle, original.resource_loader, original.text_input, original.system_actions)

func _run() -> void:
	await Platform.when_ready()
	original = Platform.context
	config._profile = config._profile.duplicate()
	OnlineAccount.suspend_network()
	OnlineAccount.clear()
	directory = "user://web_security_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_absolute(directory) == OK, "Owned test directory")
	_test_config()
	await _test_credentials_and_ui()
	OnlineAccount.resume_network() # Test online target policy after the credential-only suspension.
	await _test_network_denials()
	Platform.context = original
	OnlineAccount.clear()
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	check(preload("res://scripts/interface/platform_factory.gd").create("web") == null, "Web factory remains explicitly unsupported")
	print("PLATFORM WEB SECURITY: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_config() -> void:
	check(not PlatformRuntimeConfigInterface.new().allows_remembered_login(), "Base denies credential storage")
	check(not PlatformRuntimeConfigInterface.new().check_network_target("https://game.example.com").ok, "Base denies network targets")
	check(original.runtime_config.allows_remembered_login() and original.runtime_config.connection_options().value.editable, "Native policy remains editable and opt-in remembering remains supported")
	check(not preload("res://scripts/interface/adapters/web/web_runtime_config.gd").new().connection_options().ok, "Production adapter cannot get a page origin on native")
	check(config.connection_options().value == {"editable": false, "server_address": config.origin}, "Web default is API origin root, never the game static directory")
	for origin in ["https://game.example.com", "https://game.example.com:8443", "https://[2001:db8::1]", "https://xn--fiqs8s.example"]:
		config.origin = origin
		check(config.check_network_target(origin).ok, "Explicit origin accepted")
	for origin in ["", "null", "file://", "data:text/html,hello", "http://game.example.com", "http://127.0.0.1:8060", "https://user:secret@game.example.com", "https://game.example.com/game/", "https://game.example.com?server=evil", "https://game.example.com#evil", "https://game.example.com\n", "https://*.example.com", "https://[127.0.0.1]", "https://127.1", "https://0x7f000001", "https://game.example.com:65536"]:
		config.origin = origin
		var result := config.connection_options()
		check(not result.ok and result.code == "WEB_CONFIG_INVALID" and not result.message.contains("secret"), "Malformed/unsafe origins fail closed without echo")
	config._profile.allow_loopback_http = true
	for origin in ["http://localhost:8060", "http://127.0.0.1:8060", "http://127.0.0.2:8061", "http://[::1]:8060"]:
		config.origin = origin
		check(config.check_network_target(origin).ok, "Build-only loopback development override")
	for origin in ["http://localhost.evil:8060", "http://0.0.0.0:8060", "http://192.168.1.2:8060", "http://[::]:8060"]:
		config.origin = origin
		check(not config.connection_options().ok, "Development override cannot enable non-loopback HTTP")
	config._profile.allow_loopback_http = false
	config.origin = "https://game.example.com"
	for prefix in ["", "/ssjx", "/games/shushan-v1"]:
		config._profile.api_prefix = prefix
		check(config.connection_options().value.server_address == config.origin + prefix, "Build-controlled API prefix")
	for prefix in ["/", "//evil.example", "https://evil.example", "/../api", "/game/..", "/%2e%2e", "/%2f%2fevil", "/x?server=evil", "/x#evil", "/x\\y", "/x/", "/x\n"]:
		config._profile.api_prefix = prefix
		check(not config.connection_options().ok, "Invalid build prefix cannot redirect credentials")
	config._profile.api_prefix = "/ssjx"
	for address in ["https://evil.example/ssjx", "http://game.example.com/ssjx", "https://sub.game.example.com/ssjx", "https://game.example.com:8443/ssjx", "https://game.example.com", "https://game.example.com/game", "https://game.example.com/ssjx/other", "https://game.example.com/ssjx?server=evil", "https://game.example.com/ssjx#evil"]:
		check(config.check_network_target(address).code == "TARGET_NOT_ALLOWED", "Exact target including prefix, scheme, host and port")
	_install()
	var settings := ServerConnectionSettings.new(directory.path_join("poisoned.cfg"))
	check(settings.load_address() == "local" and settings.settings_path.is_empty(), "Web defaults to local and ignores explicit/native settings paths")
	check(settings.save_address("https://game.example.com/ssjx") and settings.save_address("local"), "Fixed service and offline selection need no synchronous writes")
	check(not settings.save_address("https://evil.example") and settings.load_address() == "local", "Address tampering cannot replace the default or fixed Web service")
	check(no_storage.accesses == 0, "Web connection settings never touch native/synchronous storage")

func _test_credentials_and_ui() -> void:
	Platform.context = original
	var path := directory.path_join("native.login")
	var native_store := RememberedLogin.new(path)
	check(native_store.remember("https://game.example.com/ssjx", "native_user", "native-password-1234"), "Seed existing native encrypted credentials")
	var before := [FileAccess.get_sha256(path), FileAccess.get_sha256(path + ".key")]
	_install()
	check(not native_store.is_supported() and native_store.load_saved("https://game.example.com/ssjx").is_empty(), "Existing native object cannot read credentials under Web policy")
	check(not native_store.remember("https://game.example.com/ssjx", "new_user", "not-persisted-1234") and not native_store.forget(), "Web policy cannot overwrite or delete native credentials")
	check(before == [FileAccess.get_sha256(path), FileAccess.get_sha256(path + ".key")], "Native credential files and key preserved byte-for-byte")
	var web_store := RememberedLogin.new(path)
	check(web_store.path.is_empty() and web_store.load_saved(config.origin).is_empty(), "Web constructor ignores even an explicit credential path")
	web_store.path = path # A later field mutation still cannot bypass operation guards.
	check(not web_store.remember(config.origin, "test", "not-persisted-1234") and not web_store.forget(), "Every operation rechecks policy")
	var form := load("res://scenes/ui/server_login.tscn").instantiate() as ServerLogin
	add_child(form)
	check(form.address_input.text == "local" and form.address_input.editable and not form.has_node("ConnectButton"), "Web UI defaults to local while allowing the configured online service")
	check(form.auth_button.text=="进入游戏" and not form.username_input.editable,"Web local entry requires no account")
	form.address_input.text="https://game.example.com/ssjx";form._update_controls()
	check(form.save_draft() and form.username_input.editable,"Web can switch from local to the configured same-origin service")
	form.address_input.text="https://evil.example"
	check(not form.save_draft(),"Editable Web address still rejects an external target before networking")
	form.address_input.text="local";form._update_controls()
	check(not form.remember_me.visible and form.remember_me.disabled and not form.remember_me.button_pressed and form.password_input.text.is_empty(), "Web UI offers no remembering or credential restoration")
	form.remembered.path = path
	form.remember_me.button_pressed = true
	check(not form.remember_me.button_pressed and form._pending_credentials.is_empty(), "Forged remember toggle is reset without file deletion")
	form._pending_credentials = {"server": config.origin, "username": "test", "password": "not-persisted-1234"}
	form._account_result("login", {"ok": true})
	check(form._pending_credentials.is_empty() and before == [FileAccess.get_sha256(path), FileAccess.get_sha256(path + ".key")], "Late login completion cannot persist a queued native password")
	form._restore_credentials()
	check(form.password_input.text.is_empty() and not form.remember_me.button_pressed, "Logout/reopen path cannot restore native credentials")
	form.queue_free()
	await get_tree().process_frame
	check(no_storage.accesses == 0, "Opening and closing Web login UI never invokes synchronous storage")
	var state := Platform.state
	Platform.state = Platform.State.FAILED
	check(not native_store.remember(config.origin, "test", "not-persisted-1234") and not native_store.forget() and native_store.load_saved(config.origin).is_empty(), "Unavailable platform blocks all credential IO")
	Platform.state = state
	Platform.context = original
	check(native_store.load_saved("https://game.example.com/ssjx").password == "native-password-1234", "Returning to native preserves legacy behavior")
	check(native_store.forget(), "Clean up only owned native credential fixture")
	_install()

func _test_network_denials() -> void:
	var replies: Array[Dictionary] = []
	var callback := func(action: String, result: Dictionary) -> void: replies.append({"action": action, "result": result})
	var tickets: Array[Dictionary] = []
	var ticket_callback := func(result: Dictionary) -> void: tickets.append(result)
	OnlineAccount.completed.connect(callback)
	OnlineAccount.world_ticket_received.connect(ticket_callback)
	for target in ["https://evil.example", "https://game.example.com", "https://game.example.com:8443/ssjx", "https://game.example.com/game", "http://127.0.0.1:9999"]:
		for action in ["login", "register", "refresh", "me", "characters", "character_create", "logout", "world_ticket"]:
			OnlineAccount._send(action, target, {"password": "not-sent-1234"}, action in ["me", "characters", "character_create", "logout", "world_ticket"])
			var reply: Dictionary = tickets.back() if action == "world_ticket" else replies.back().result
			check(reply.get("code") == "TARGET_NOT_ALLOWED" and not OnlineAccount.busy and OnlineAccount._request == null, "Account target rejected before credential/bearer/refresh HTTP request")
	check(OnlineAccount._after_refresh.is_empty(), "Rejected targets cannot queue automatic refresh")
	var discovery := ServerDiscovery.new()
	add_child(discovery)
	var discovery_replies: Array[Dictionary] = []
	discovery.completed.connect(func(result: Dictionary) -> void: discovery_replies.append(result))
	discovery.check_server("https://evil.example")
	check(discovery.request == null and discovery_replies.size() == 1 and not discovery_replies[0].ok, "Discovery cannot reach another Web target")
	discovery.queue_free()
	var world := OnlineWorldClient.new()
	add_child(world)
	world.server = "https://evil.example"
	world._state = "ticket"
	world._on_ticket({"ok": true, "ticket": "not-sent"})
	check(world.socket == null and world._ticket.is_empty() and world._state == "failed", "World target rechecked before creating socket or retaining ticket")
	world.queue_free()
	OnlineAccount.completed.disconnect(callback)
	OnlineAccount.world_ticket_received.disconnect(ticket_callback)
	await get_tree().process_frame
