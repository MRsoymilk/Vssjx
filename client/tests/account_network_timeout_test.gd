extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var address := OS.get_environment("SSJX_DELAYED_AUTH_FIXTURE")
	assert(address.begins_with("http://127.0.0.1:"), "Use the owned loopback fixture")
	OnlineAccount.clear()
	var started := Time.get_ticks_msec()
	OnlineAccount._send("login", address, {"username":"delayed_probe", "password":"owned-fixture-password"}, false)
	var result: Array = await OnlineAccount.completed
	var elapsed := Time.get_ticks_msec() - started
	assert(result[0] == "login" and result[1].code == "UNAUTHORIZED", "Slow valid JSON response must reach authentication handling, not generic network failure")
	assert(elapsed >= 9000 and elapsed < 30000, "Fixture exceeds the old eight-second timeout")
	assert(not OnlineAccount.busy and not OnlineAccount.is_logged_in(), "A rejected delayed login leaves no session")
	OnlineAccount.clear()
	print("ACCOUNT NETWORK TIMEOUT: 3 checks, 0 failures")
	get_tree().quit()
