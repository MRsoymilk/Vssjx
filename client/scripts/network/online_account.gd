extends Node
const MAX_CHARACTERS := 5
const REQUEST_TIMEOUT := 30.0
## Online identity stays separate from Game.player and offline saves.
signal completed(action: String, result: Dictionary)
signal world_ticket_received(result: Dictionary)
var account: Dictionary = {}
var server_address := ""
var login_session_id := ""
var busy := false
var network_suspended := false
var _access_token := ""
var _refresh_token := ""
var _expires_at := 0.0
var _refresh_expires_at := 0.0
var _retry_at := 0.0
var _request: HTTPRequest
var _action := ""
var _target := ""
var characters: Array = []
var pending_creation: Dictionary = {}
var pending_pve: Dictionary = {}
var _after_refresh: Dictionary = {}
var _generation := 0

static func secure_credentials_target(address: String) -> bool:
	if address.begins_with("https://"): return true
	return RegEx.create_from_string("^http://(localhost|127(?:\\.[0-9]{1,3}){3}|\\[::1\\])(?::[0-9]+)?(?:/|$)").search(address) != null

func is_logged_in() -> bool:
	return not account.is_empty() and Time.get_unix_time_from_system() < _refresh_expires_at

func suspend_network() -> void:
	# Keep the memory-only account separate, but do no background network work
	# while the player has explicitly selected the local service.
	network_suspended = true
	_generation += 1
	if _request != null and is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	busy = false
	_action = ""
	_target = ""
	_after_refresh = {}
	set_process(false)

func resume_network() -> void:
	network_suspended = false
	set_process(true)

func clear() -> void:
	_generation += 1
	account = {}
	server_address = ""
	login_session_id = ""
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0.0
	_refresh_expires_at = 0.0
	characters = []
	pending_creation = {}
	pending_pve = {}
	_after_refresh = {}

func list_characters() -> void:
	_send("characters", server_address, {}, true)

func request_world_ticket(character_id: String, config_hash: String) -> void:
	_send("world_ticket", server_address, {"character_id": character_id, "protocol_version": 1, "config_hash": config_hash}, true)

func create_character(display_name: String, job: int, gender: int, school: int) -> void:
	if busy: return
	if not is_logged_in():
		completed.emit("character_create", {"ok": false, "code": "UNAUTHORIZED"})
		return
	if pending_creation.is_empty():
		var bytes := Crypto.new().generate_random_bytes(16)
		if bytes.size() != 16:
			completed.emit("character_create", {"ok": false, "code": "SERVER_BUSY"})
			return
		bytes[6] = (bytes[6] & 15) | 64
		bytes[8] = (bytes[8] & 63) | 128
		var hex := bytes.hex_encode()
		var operation_id := "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
		pending_creation = {"operation_id": operation_id, "display_name": display_name, "job": job, "gender": gender, "school": school, "rules_version": "creation-v1"}
	# An unknown result always retries the ORIGINAL payload, not edited fields.
	_send("character_create", server_address, pending_creation, true)

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
	if network_suspended: return
	if busy: return
	if not Platform.is_available():
		var result := {"ok": false, "code": "PLATFORM_NOT_READY"}
		if action == "world_ticket": world_ticket_received.emit(result)
		else: completed.emit(action, result)
		return
	var normalized := ServerConnectionSettings.normalize(address)
	if not normalized.ok:
		completed.emit(action, {"ok": false, "code": "INVALID_ADDRESS"})
		return
	var target_result := Platform.context.runtime_config.check_network_target(normalized.address)
	if not target_result.ok:
		var result := {"ok": false, "code": target_result.code}
		if action == "world_ticket": world_ticket_received.emit(result)
		else: completed.emit(action, result)
		return
	if not secure_credentials_target(normalized.address):
		completed.emit(action, {"ok": false, "code": "HTTPS_REQUIRED"})
		return
	if bearer and action != "logout":
		if not is_logged_in():
			completed.emit(action, {"ok": false, "code": "UNAUTHORIZED"})
			return
		if Time.get_unix_time_from_system() >= _expires_at - 5.0:
			_after_refresh = {"action": action, "payload": payload.duplicate(true)}
			refresh()
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
	_request.timeout = REQUEST_TIMEOUT
	_request.body_size_limit = 32768
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_on_response.bind(_generation))
	var method := HTTPClient.METHOD_GET if action in ["me", "characters"] else HTTPClient.METHOD_POST
	var body := "" if payload.is_empty() else JSON.stringify(payload)
	var route := "/api/v1/auth/" + action
	if action in ["characters", "character_create"]: route = "/api/v1/characters"
	if action == "world_ticket": route = "/api/v1/world/ticket"
	var error := _request.request(_target + route, headers, method, body)
	if error != OK: _finish({"ok": false, "code": "NETWORK_ERROR", "request_error": int(error)})

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, expected_generation: int) -> void:
	if expected_generation != _generation and _action != "logout":
		_finish({"ok": false, "code": "UNAUTHORIZED"})
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		var failure := {"ok": false, "code": "NETWORK_ERROR", "transport_result": result}
		var categories := {
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS_HANDSHAKE_ERROR",
			HTTPRequest.RESULT_CANT_RESOLVE: "DNS_ERROR",
			HTTPRequest.RESULT_TIMEOUT: "TIMEOUT",
			HTTPRequest.RESULT_CANT_CONNECT: "CANT_CONNECT",
			HTTPRequest.RESULT_CONNECTION_ERROR: "CONNECTION_ERROR",
			HTTPRequest.RESULT_NO_RESPONSE: "NO_RESPONSE",
			HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "RESPONSE_TOO_LARGE",
		}
		failure["transport_error"] = categories.get(result, "TRANSPORT_ERROR")
		if code >= 400 and code <= 599: failure["http_status"] = code
		_finish(failure)
		return
	if code == 204 and _action == "logout":
		_finish({"ok": true})
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		var failure := {"ok": false, "code": "INVALID_RESPONSE"}
		if code >= 400 and code <= 599: failure["http_status"] = code
		_finish(failure)
		return
	var data: Dictionary = parser.data
	if _action == "world_ticket" and code == 200:
		if not data.get("ticket") is String or RegEx.create_from_string("^[0-9a-f]{64}\\z").search(data.ticket) == null:
			_finish({"ok": false, "code": "INVALID_RESPONSE"})
		else:
			_finish({"ok": true, "ticket": data.ticket, "announcement_version": 1 if data.get("announcement_version") == 1 else 0, "population_version": 1 if data.get("population_version") == 1 else 0, "pve_version": 1 if data.get("pve_version") == 1 else 0, "maps_version": 1 if data.get("maps_version") == 1 else 0, "shop_version": int(data.shop_version) if data.get("shop_version")==1 or data.get("shop_version")==2 else 0})
		return
	if code not in [200, 201]:
		if _action == "character_create" and code in [409, 422] and data.get("operation_id") == pending_creation.get("operation_id"): pending_creation = {}
		if code == 401 and _action in ["refresh", "me", "characters", "character_create"]: clear()
		_finish({"ok": false, "code": data.get("code", "SERVER_ERROR")})
		return
	if _action in ["characters", "character_create"]:
		if _action == "characters" and (data.get("rules_version") != "creation-v1" or data.get("name_rules_version") != "nickname-v1"):
			_finish({"ok": false, "code": "RULES_UNSUPPORTED"})
			return
		if _action == "character_create" and (data.get("operation_id") != pending_creation.get("operation_id") or not data.get("replayed") is bool):
			_finish({"ok": false, "code": "INVALID_RESPONSE"})
			return
		var values: Variant = data.get("characters") if _action == "characters" else [data.get("character")]
		if not values is Array or values.size() > MAX_CHARACTERS:
			_finish({"ok": false, "code": "INVALID_RESPONSE"})
			return
		var identities := {}
		for value in values:
			if not _valid_character(value):
				_finish({"ok": false, "code": "INVALID_RESPONSE"})
				return
			if identities.has(value.id):
				_finish({"ok": false, "code": "INVALID_RESPONSE"})
				return
			identities[value.id] = true
		if _action == "character_create":
			# Creation receipts contain a single historical snapshot, not the roster.
			var found := false
			for index in characters.size():
				if characters[index].id == values[0].id: found = true
			if not found:
				if characters.size() >= MAX_CHARACTERS:
					_finish({"ok": false, "code": "INVALID_RESPONSE"})
					return
				characters.append(values[0].duplicate(true))
			pending_creation = {}
		else: characters = values.duplicate(true)
		_finish({"ok": true, "characters": characters.duplicate(true), "character_id": values[0].id if _action == "character_create" else ""})
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
	var next := _after_refresh.duplicate(true) if action == "refresh" else {}
	if action == "refresh": _after_refresh = {}
	busy = false
	_retry_at = Time.get_unix_time_from_system() + 30.0
	if _request != null:
		_request.queue_free()
		_request = null
	# Do not expose tokens to page callbacks, logs or local preference files.
	if action == "world_ticket": world_ticket_received.emit(result)
	else: completed.emit(action, result)
	if not next.is_empty():
		if result.ok: _send(next.action, server_address, next.payload, true)
		elif next.action == "world_ticket": world_ticket_received.emit(result)
		else: completed.emit(next.action, result)

static func valid_nickname(raw: String) -> bool:
	return not canonical_nickname(raw).is_empty()

static func canonical_nickname(raw: String) -> Dictionary:
	var value := raw
	while value.begins_with(" "): value = value.substr(1)
	while value.ends_with(" "): value = value.left(-1)
	if value.length() < 2 or value.length() > 12: return {}
	for index in value.length():
		var point := value.unicode_at(index)
		if not (point >= 65 and point <= 90 or point >= 97 and point <= 122 or point >= 48 and point <= 57 or point == 95 or point >= 0x4e00 and point <= 0x9fff): return {}
	return {"display_name": value, "name_key": value.to_lower()}

static func _valid_character(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not value.get("id") is String or RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z").search(value.id) == null: return false
	if not value.get("display_name") is String or canonical_nickname(value.display_name).get("display_name") != value.display_name: return false
	if value.get("name_rules_version") != "nickname-v1" or value.get("rules_version") != "creation-v1": return false
	if not value.get("state_revision") is String or RegEx.create_from_string("^[1-9][0-9]{0,18}\\z").search(value.state_revision) == null: return false
	if value.state_revision.length() == 19 and value.state_revision > "9223372036854775807": return false
	for key in ["job", "gender", "school", "level", "gold", "hp", "mp", "xp", "quest_stage", "cell_x", "cell_y"]:
		var number: Variant = value.get(key)
		var maximum := 1 if key == "gender" else (2 if key in ["job", "school"] else (31 if key in ["cell_x", "cell_y"] else (60 if key == "level" else 2147483647)))
		if not (number is int or number is float) or not is_finite(float(number)) or number < 0 or number > maximum or float(number) != floor(float(number)): return false
	if value.has("appearance_v2"):
		var look_v2: Variant = value.appearance_v2
		if not look_v2 is Array or look_v2.size()!=3: return false
		for i in 3:
			if not OnlinePve.integer(look_v2[i],0,[27,11,9][i]): return false
	if value.has("appearance"):
		var look: Variant = value.appearance
		if not look is Array or look.size() != 2: return false
		for i in 2:
			if not (look[i] is int or look[i] is float) or not is_finite(float(look[i])) or float(look[i]) != floor(float(look[i])) or look[i] < 0 or look[i] > (3 if i == 0 else 2): return false
	if value.level < 1 or value.hp < 1 or not SharedWorldMap.MAPS.has(value.get("map_id")): return false
	return true

func _process(_delta: float) -> void:
	if not account.is_empty() and not is_logged_in():
		clear()
		completed.emit("expired", {"ok": false, "code": "UNAUTHORIZED"})
	var now := Time.get_unix_time_from_system()
	if is_logged_in() and not busy and now >= _retry_at and now >= _expires_at - 60.0: refresh()
