extends Node
## Account tokens live only in memory and are bound to one server. No game state.
signal completed(action: String, result: Dictionary)
var account: Dictionary = {}
var server_address := ""
var login_session_id := ""
var busy := false
var _access_token := ""
var _refresh_token := ""
var _expires_at := 0.0
var _refresh_expires_at := 0.0
var _retry_at := 0.0
var _request: HTTPRequest
var _action := ""
var _target := ""

static func secure_credentials_target(address: String) -> bool:
	if address.begins_with("https://"): return true
	return RegEx.create_from_string("^http://(localhost|127(?:\\.[0-9]{1,3}){3}|\\[::1\\])(?::[0-9]+)?(?:/|$)").search(address) != null

func is_logged_in() -> bool:
	return not account.is_empty() and Time.get_unix_time_from_system() < _refresh_expires_at

func clear() -> void:
	account = {}
	server_address = ""
	login_session_id = ""
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0.0
	_refresh_expires_at = 0.0

func register_account(address: String, username: String, password: String) -> void:
	_send("register", address, {"username": username, "password": password})

func login(address: String, username: String, password: String) -> void:
	_send("login", address, {"username": username, "password": password})

func refresh() -> void:
	_send("refresh", server_address, {"refresh_token": _refresh_token})

func inspect_session() -> void:
	_send("me", server_address, {}, true)

func logout() -> void:
	if busy: return
	_send("logout", server_address, {}, true)
	# Even when the server cannot confirm revocation, forget local credentials.
	clear()

func _send(action: String, address: String, payload: Dictionary, bearer: bool = false) -> void:
	if busy: return
	var normalized := ServerConnectionSettings.normalize(address)
	if not normalized.ok:
		completed.emit(action, {"ok": false, "code": "INVALID_ADDRESS"})
		return
	if not secure_credentials_target(normalized.address):
		completed.emit(action, {"ok": false, "code": "HTTPS_REQUIRED"})
		return
	if is_logged_in() and action in ["login", "register"]:
		completed.emit(action, {"ok": false, "code": "LOGOUT_REQUIRED"})
		return
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if bearer: headers.append("Authorization: Bearer " + _access_token)
	_action = action
	_target = normalized.address
	busy = true
	_request = HTTPRequest.new()
	_request.timeout = 8.0
	_request.body_size_limit = 32768
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_on_response)
	var method := HTTPClient.METHOD_GET if action == "me" else HTTPClient.METHOD_POST
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var error := _request.request(_target + "/api/v1/auth/" + action, headers, method, body)
	if error != OK: _finish({"ok": false, "code": "NETWORK_ERROR"})

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish({"ok": false, "code": "NETWORK_ERROR"})
		return
	if code == 204 and _action == "logout":
		_finish({"ok": true})
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_finish({"ok": false, "code": "INVALID_RESPONSE"})
		return
	var data: Dictionary = parser.data
	if code not in [200, 201]:
		if code == 401 and _action in ["refresh", "me"]: clear()
		_finish({"ok": false, "code": data.get("code", "SERVER_ERROR")})
		return
	var identity: Variant = data.get("account")
	if not identity is Dictionary or not identity.get("id") is String or not identity.get("username") is String:
		_finish({"ok": false, "code": "INVALID_RESPONSE"})
		return
	var uuid_pattern := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	if uuid_pattern.search(identity.id) == null or RegEx.create_from_string("^[a-z0-9_]{3,32}$").search(identity.username) == null:
		_finish({"ok": false, "code": "INVALID_RESPONSE"})
		return
	if _action in ["login", "refresh"]:
		if not data.get("session_id") is String or uuid_pattern.search(data.session_id) == null:
			_finish({"ok": false, "code": "INVALID_RESPONSE"})
			return
		for key in ["access_token", "refresh_token"]:
			if not data.get(key) is String or RegEx.create_from_string("^[0-9a-f]{64}$").search(data[key]) == null:
				_finish({"ok": false, "code": "INVALID_RESPONSE"})
				return
		for key in ["expires_in", "refresh_expires_in"]:
			var value: Variant = data.get(key)
			var maximum := 86400 if key == "expires_in" else 2592000
			if not (value is int or value is float) or value < 1 or value > maximum or float(value) != floor(float(value)):
				_finish({"ok": false, "code": "INVALID_RESPONSE"})
				return
		server_address = _target
		login_session_id = data.session_id
		account = identity.duplicate()
		_access_token = data.access_token
		_refresh_token = data.refresh_token
		_expires_at = Time.get_unix_time_from_system() + float(data.expires_in)
		_refresh_expires_at = Time.get_unix_time_from_system() + float(data.refresh_expires_in)
	_finish({"ok": true, "account": identity.duplicate()})

func _finish(result: Dictionary) -> void:
	var action := _action
	busy = false
	_retry_at = Time.get_unix_time_from_system() + 30.0
	if _request != null:
		_request.queue_free()
		_request = null
	# Do not expose tokens to page callbacks, logs or local preference files.
	completed.emit(action, result)

func _process(_delta: float) -> void:
	if not account.is_empty() and not is_logged_in():
		clear()
		completed.emit("expired", {"ok": false, "code": "UNAUTHORIZED"})
	var now := Time.get_unix_time_from_system()
	if is_logged_in() and not busy and now >= _retry_at and now >= _expires_at - 60.0: refresh()
