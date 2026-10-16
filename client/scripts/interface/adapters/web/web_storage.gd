extends PlatformStorageInterface
## Dedicated, same-origin IndexedDB slot. Never calls FileAccess for player data.
const SLOT := "offline://save-v1"
const SOURCE := "res://scripts/interface/adapters/web/indexeddb_storage.js"
const MAXIMUM_BYTES := 1048576
static var _factory: JavaScriptObject
var _bridge: JavaScriptObject
var _callback: JavaScriptObject
var _pending: Dictionary = {}
var _next_id := 0
var _closed := false

func initialize() -> PlatformStorageRequest:
	if not OS.has_feature("web"):
		return PlatformStorageRequest.resolved(PlatformResult.unsupported())
	if _closed: return _rejected("STORAGE_CLOSED")
	if _bridge == null:
		if _factory == null:
			var source := FileAccess.get_file_as_string(SOURCE)
			if source.is_empty(): return _rejected("STORAGE_UNSUPPORTED")
			# A temporary random name transfers the trusted factory to the bridge.
			# No save data, URL parameters or credentials are interpolated into JS.
			var name := "__vssjx_idb_" + Crypto.new().generate_random_bytes(16).hex_encode()
			var key := JSON.stringify(name)
			JavaScriptBridge.eval("globalThis[" + key + "] = " + source, true)
			_factory = JavaScriptBridge.get_interface(name)
			JavaScriptBridge.eval("delete globalThis[" + key + "]", true)
		if _factory == null: return _rejected("STORAGE_UNSUPPORTED")
		_bridge = _factory.create()
		if _bridge == null: return _rejected("STORAGE_UNSUPPORTED")
		_callback = JavaScriptBridge.create_callback(_dispatch.bind(weakref(self)))
	return _submit("initialize", "", "", MAXIMUM_BYTES)

func probe(path: String) -> PlatformStorageRequest:
	return _submit("probe", path, "", MAXIMUM_BYTES)

func read(path: String, maximum_bytes: int = MAXIMUM_BYTES) -> PlatformStorageRequest:
	return _submit("read", path, "", maximum_bytes)

func write(path: String, text: String) -> PlatformStorageRequest:
	if text.length() > MAXIMUM_BYTES or text.to_utf8_buffer().size() > MAXIMUM_BYTES: return _rejected("TOO_LARGE")
	return _submit("write", path, text, MAXIMUM_BYTES)

func status() -> Dictionary:
	if _bridge == null: return {"state": "closed" if _closed else "uninitialized", "retention": "unknown", "busy": false}
	var value: Variant = JSON.parse_string(_bridge.status_json())
	return value if value is Dictionary else {"state": "failed", "retention": "unknown", "busy": not _pending.is_empty()}

func close() -> void:
	if _closed: return
	_closed = true
	if _bridge != null: _bridge.dispose()
	_bridge = null
	_callback = null
	var requests := _pending.values()
	_pending.clear()
	for request in requests:
		request.finish(PlatformResult.new(PlatformResult.Status.CANCELLED, "STORAGE_CLOSED", "浏览器存档操作已关闭，写入结果可能尚未确认。"))

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE: return
	# RefCounted is already at zero here: do not call a method on self or
	# resurrect it via a bound callback while handling PREDELETE.
	if _bridge != null: _bridge.dispose()
	var requests := _pending.values()
	_pending.clear()
	for request in requests:
		request.finish(PlatformResult.new(PlatformResult.Status.CANCELLED, "STORAGE_CLOSED", "浏览器存档连接已释放，写入结果可能尚未确认。"))

func _submit(kind: String, path: String, text: String, maximum_bytes: int) -> PlatformStorageRequest:
	if _closed: return _rejected("STORAGE_CLOSED")
	if _bridge == null: return _rejected("STORAGE_NOT_READY")
	if not _pending.is_empty(): return _rejected("STORAGE_BUSY")
	if kind != "initialize" and path != SLOT: return _rejected("INVALID_PATH")
	if maximum_bytes < 1 or maximum_bytes > MAXIMUM_BYTES: return _rejected("INVALID_LIMIT")
	_next_id += 1
	var request := PlatformStorageRequest.new()
	_pending[_next_id] = request
	_bridge.submit(_next_id, kind, path, text, maximum_bytes, _callback)
	return request

static func _dispatch(arguments: Array, owner: WeakRef) -> void:
	var port: RefCounted = owner.get_ref()
	if port != null: port._receive(arguments)

func _receive(arguments: Array) -> void:
	if arguments.size() != 1 or not arguments[0] is String:
		_invalid_callback()
		return
	var parser := JSON.new()
	if parser.parse(arguments[0]) != OK:
		_invalid_callback()
		return
	var data: Variant = parser.data
	if not data is Dictionary or not (data.get("id") is float or data.get("id") is int):
		_invalid_callback()
		return
	if not is_finite(float(data.id)) or float(data.id) != floor(float(data.id)):
		_invalid_callback()
		return
	var id := int(data.id)
	if not _pending.has(id): return
	var request: PlatformStorageRequest = _pending[id]
	_pending.erase(id)
	if data.get("ok") == true:
		request.finish(PlatformResult.success(data.get("value")))
	else:
		var error := _error(String(data.get("code", "SYNC_FAILED")))
		if data.get("uncertain") == true: error.value = {"uncertain": true}
		request.finish(error)

func _invalid_callback() -> void:
	var requests := _pending.values()
	_pending.clear()
	for request in requests: request.finish(_error("SYNC_FAILED"))

func _rejected(code: String) -> PlatformStorageRequest:
	return PlatformStorageRequest.resolved(_error(code))

func _error(code: String) -> PlatformResult:
	var messages := {
		"STORAGE_NOT_READY": "浏览器存档尚未初始化，请重试。", "STORAGE_BUSY": "浏览器存档操作尚未完成，请稍候。",
		"STORAGE_UNSUPPORTED": "当前环境无法使用浏览器本地存储。", "STORAGE_DENIED": "浏览器拒绝了本地存储访问，请检查站点设置。",
		"STORAGE_BLOCKED": "浏览器存储被其他页面占用，请关闭旧页面后重试。", "STORAGE_OPEN_FAILED": "无法打开浏览器存档，请重试。",
		"STORAGE_TIMEOUT": "浏览器存档操作超时，写入结果未确认；请重新初始化并检查存档。",
		"QUOTA_EXCEEDED": "浏览器存储空间不足，存档未确认，请释放空间后重试。",
		"NOT_FOUND": "没有浏览器本地存档。", "TOO_LARGE": "存档超过大小限制，原记录未被替换。",
		"INVALID_STORED_DATA": "浏览器存档记录格式不正确，原记录已保留。", "READ_FAILED": "浏览器存档读取失败，请重试。",
		"INVALID_PATH": "仅允许访问本游戏的离线存档槽。", "INVALID_LIMIT": "浏览器存档读取大小限制无效。",
		"STORAGE_CLOSED": "浏览器存档连接已关闭。", "SYNC_FAILED": "浏览器存档事务未确认，当前进度仍在内存中。",
	}
	var safe_code := code if messages.has(code) else "SYNC_FAILED"
	var status_code := PlatformResult.Status.INVALID_DATA if safe_code in ["INVALID_PATH", "INVALID_LIMIT", "TOO_LARGE", "INVALID_STORED_DATA"] else PlatformResult.Status.TEMPORARY_FAILURE
	if safe_code in ["STORAGE_DENIED", "QUOTA_EXCEEDED"]: status_code = PlatformResult.Status.DENIED
	if safe_code == "STORAGE_UNSUPPORTED": status_code = PlatformResult.Status.UNSUPPORTED
	return PlatformResult.new(status_code, safe_code, messages[safe_code])
