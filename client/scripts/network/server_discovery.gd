class_name ServerDiscovery
extends Node
## Discovery is not authentication and never installs a player snapshot.
signal completed(result: Dictionary)

const PROTOCOL_VERSION := 1
var request: HTTPRequest
var generation := 0
var timeout_seconds := 8.0

func cancel() -> void:
	generation += 1
	if request != null and is_instance_valid(request):
		request.cancel_request()
		request.queue_free()
	request = null

func check_server(address: String) -> void:
	cancel()
	if not Platform.is_available():
		completed.emit({"ok": false, "error": "平台尚未就绪，无法连接服务器。"})
		return
	var allowed := Platform.context.runtime_config.check_network_target(address)
	if not allowed.ok:
		completed.emit({"ok": false, "error": allowed.message})
		return
	request = HTTPRequest.new()
	request.timeout = timeout_seconds
	request.body_size_limit = 32768
	request.max_redirects = 0 # Never silently switch the user's chosen server.
	add_child(request)
	request.request_completed.connect(_on_response.bind(generation))
	var error := request.request(address + "/api/v1/server-info", PackedStringArray(["Accept: application/json"]))
	if error != OK:
		completed.emit({"ok": false, "error": "无法发起连接（%d）。" % error})

func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, expected_generation: int) -> void:
	if expected_generation != generation: return
	if result != HTTPRequest.RESULT_SUCCESS:
		var message := "无法连接服务器，请检查地址、网络与服务是否启动。"
		if result == HTTPRequest.RESULT_TIMEOUT: message = "连接超时，地址已保存，可稍后重试。"
		elif result == HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: message = "HTTPS证书或TLS连接失败，请检查域名与证书。"
		completed.emit({"ok": false, "error": message})
		return
	if code != 200:
		completed.emit({"ok": false, "error": "服务器返回HTTP %d，请检查地址及反向代理路径。" % code})
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		completed.emit({"ok": false, "error": "服务器响应不是有效的服务信息。"})
		return
	var info: Dictionary = parser.data
	var protocol: Variant = info.get("protocol_version")
	if info.get("service") != "vssjx" or not (protocol is int or protocol is float):
		completed.emit({"ok": false, "error": "目标不是兼容的蜀山剑侠服务器。"})
		return
	if float(protocol) != PROTOCOL_VERSION:
		completed.emit({"ok": false, "error": "服务器协议版本不兼容，请更新客户端或更换服务器。"})
		return
	var name_value: Variant = info.get("server_name")
	if not name_value is String or name_value.is_empty() or name_value.length() > 64:
		completed.emit({"ok": false, "error": "服务器名称字段无效。"})
		return
	var capabilities: Variant = info.get("capabilities", [])
	if not capabilities is Array: capabilities = []
	completed.emit({"ok": true, "server_name": name_value, "stage": info.get("stage", "unknown"), "capabilities": capabilities})
