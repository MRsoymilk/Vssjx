extends Node
## Real native HTTPRequest consumers under injected Web policy; no browser claims.
class TestWebConfig extends "res://scripts/interface/adapters/web/web_runtime_config.gd":
	var origin := ""
	func _page_origin() -> String:
		return origin

var checks := 0
var failures := 0
var responses: Array[Dictionary] = []
var tickets: Array[Dictionary] = []

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WEB NETWORK FAIL: " + description)

func wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while OnlineAccount.busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(not OnlineAccount.busy, "Owned HTTP fixture completes within deadline")

func _run() -> void:
	await Platform.when_ready()
	var original := Platform.context
	var config := TestWebConfig.new()
	config.origin = OS.get_environment("SSJX_TEST_SERVER_URL")
	config._profile = config._profile.duplicate()
	config._profile.allow_loopback_http = true
	config._profile.api_prefix = "/ssjx"
	check(config.connection_options().ok, "Explicit loopback HTTP is test-build-only")
	Platform.context = PlatformContext.new("web-policy-test", original.storage, config, original.display,
		original.lifecycle, original.resource_loader, original.text_input, original.system_actions)
	OnlineAccount.clear()
	OnlineAccount.completed.connect(func(action: String, result: Dictionary) -> void: responses.append({"action": action, "result": result}))
	OnlineAccount.world_ticket_received.connect(func(result: Dictionary) -> void: tickets.append(result))
	var form := load("res://scenes/ui/server_login.tscn").instantiate() as ServerLogin
	add_child(form)
	var service := config.origin + "/ssjx"
	var outsider := OS.get_environment("SSJX_TEST_OUTSIDER_URL")
	check(form.address_input.text == service and form.settings.settings_path.is_empty(), "UI derives API base from origin plus build prefix")
	check(not form.remember_me.visible and not form.address_input.editable, "Web UI has no credential storage or editable destination")
	form.remember_me.set_pressed_no_signal(true) # A forged checkbox still cannot create a pending password.
	form.username_input.text = "web_policy_user"
	form.password_input.text = "web-policy-password-1234"
	form._register()
	await wait_idle()
	check(OnlineAccount.is_logged_in() and OnlineAccount.server_address == service, "Same-origin registration and memory-only auto-login use real HTTP")
	check(form.password_input.text.is_empty() and form._pending_credentials.is_empty() and form._registration_secret.is_empty(), "Successful registration/login clears UI secrets without a remember queue")
	check(form.remembered.path.is_empty(), "No credential filename is selected")
	form.address_input.text = outsider
	form.password_input.text = "not-sent-password-1234"
	form._login()
	check(not OnlineAccount.busy and form.status.text.contains("本站"), "Tampered UI target rejected before entering account actions")
	form.address_input.text = service
	OnlineAccount.list_characters()
	await wait_idle()
	check(responses.back().action == "characters" and responses.back().result.ok and OnlineAccount.characters.is_empty(), "Bearer character query uses controlled prefix")
	OnlineAccount.request_world_ticket("00000000-0000-4000-8000-000000000001", "0".repeat(64))
	await wait_idle()
	check(tickets.size() == 1 and tickets[0].ok, "Same-origin world ticket remains on the existing HTTP route")
	OnlineAccount.refresh()
	await wait_idle()
	check(responses.back().action == "refresh" and responses.back().result.ok and OnlineAccount.is_logged_in(), "Memory-only token rotation still works")
	# This fixture redirects /me to the outsider. Existing max_redirects=0 must hold.
	OnlineAccount.inspect_session()
	await wait_idle()
	check(not responses.back().result.ok, "Credential-bearing HTTP redirect is not followed")
	for action in ["login", "register", "refresh", "me", "characters", "character_create", "world_ticket"]:
		var count := tickets.size() if action == "world_ticket" else responses.size()
		OnlineAccount._send(action, outsider, {"password": "not-sent-password-1234"}, action in ["me", "characters", "character_create", "world_ticket"])
		var result: Dictionary = tickets.back() if action == "world_ticket" else responses.back().result
		check((tickets.size() if action == "world_ticket" else responses.size()) == count + 1 and result.code == "TARGET_NOT_ALLOWED" and not OnlineAccount.busy, "Direct account API cannot escape target policy")
	var session_server := OnlineAccount.server_address
	OnlineAccount.server_address = outsider
	OnlineAccount._expires_at = 0
	OnlineAccount.list_characters()
	check(responses.back().result.code == "TARGET_NOT_ALLOWED" and OnlineAccount._after_refresh.is_empty(), "Tampered expired session cannot trigger a refresh to the wrong service")
	OnlineAccount.server_address = session_server
	# Refresh the trusted session, then exercise logout with bearer authentication.
	OnlineAccount.refresh()
	await wait_idle()
	OnlineAccount.logout()
	await wait_idle()
	check(not OnlineAccount.is_logged_in() and OnlineAccount._access_token.is_empty() and OnlineAccount._refresh_token.is_empty(), "Logout clears memory tokens")
	check(form.password_input.text.is_empty() and not form.remember_me.button_pressed, "Logout does not restore a browser password")
	form.queue_free()
	await get_tree().process_frame
	Platform.context = original
	OnlineAccount.clear()
	print("PLATFORM WEB NETWORK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
