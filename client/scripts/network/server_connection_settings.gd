class_name ServerConnectionSettings
extends RefCounted
## Connection preferences are independent of player saves and contain no secrets.

var settings_path := ""
var last_error := ""

func _init(path: String = "") -> void:
	if not Platform.is_available():
		last_error = "平台尚未就绪，无法读取连接配置。"
		return
	var result := Platform.context.runtime_config.local_path("connection", path)
	if result.ok: settings_path = result.value
	else: last_error = result.message

static func normalize(raw: String) -> Dictionary:
	var value := raw.strip_edges()
	if value.to_lower() == "local": return {"ok": true, "address": "local", "error": ""}
	if value.is_empty(): return _invalid("请输入服务器地址。")
	if value.length() > 1024: return _invalid("服务器地址过长。")
	var whitespace := RegEx.create_from_string("[\\s\\x00-\\x1f\\x7f\\\\]")
	if whitespace.search(value) != null: return _invalid("地址不能包含空格、控制字符或反斜杠。")
	var separator := value.find("://")
	if separator < 0:
		var authority := value.get_slice("/", 0)
		var candidate := authority.get_slice(":", 0).to_lower()
		if authority.begins_with("["): candidate = authority.get_slice("]", 0).trim_prefix("[")
		value = ("http://" if candidate == "localhost" or candidate.is_valid_ip_address() else "https://") + value
	else:
		value = value.left(separator).to_lower() + value.substr(separator)
	var pattern := RegEx.create_from_string("^(https?)://(\\[[^\\]]+\\]|[^/:?#@]+)(?::([0-9]+))?(/[^?#]*)?$")
	var parsed := pattern.search(value)
	if parsed == null: return _invalid("请填写IP:端口或HTTP/HTTPS地址，不要附带账号、查询参数或片段。")
	var scheme := parsed.get_string(1)
	var host := parsed.get_string(2).to_lower()
	if host.begins_with("["):
		var ip := host.trim_prefix("[").trim_suffix("]")
		if not ip.contains(":") or not ip.is_valid_ip_address(): return _invalid("IPv6地址格式不正确。")
	elif not host.is_valid_ip_address():
		if host.length() > 253 or host.replace(".", "").is_valid_int(): return _invalid("IP或域名格式不正确。")
		var label_pattern := RegEx.create_from_string("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
		for label in host.split("."):
			if label_pattern.search(label) == null: return _invalid("域名格式不正确；国际化域名请使用Punycode。")
	var port := parsed.get_string(3)
	if not port.is_empty():
		if port.length() > 5 or int(port) < 1 or int(port) > 65535: return _invalid("端口必须在1～65535之间。")
		port = ":%d" % int(port)
	var prefix := parsed.get_string(4)
	var path_pattern := RegEx.create_from_string("^[/a-zA-Z0-9._~!$&'()*+,;=:@%+-]*$")
	if path_pattern.search(prefix) == null or RegEx.create_from_string("%(?![0-9a-fA-F]{2})").search(prefix) != null:
		return _invalid("路径前缀格式不正确。")
	# Godot's URI decoder expects uppercase hexadecimal escapes.
	for segment in prefix.to_upper().uri_decode().split("/"):
		if segment in [".", ".."]: return _invalid("路径前缀不能包含相对目录。")
	while prefix.ends_with("/"): prefix = prefix.trim_suffix("/")
	return {"ok": true, "address": scheme + "://" + host + port + prefix, "error": ""}

static func is_local(raw: String) -> bool:
	return raw.strip_edges().to_lower() == "local"

static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "address": "", "error": message}

func load_address() -> String:
	last_error = ""
	if not _storage_ready(): return ""
	var read := Platform.context.storage.read_text(settings_path, 65536)
	if not read.ok:
		if read.code != "NOT_FOUND": last_error = "无法读取已保存的服务器地址，请重新填写。"
		return ""
	var config := ConfigFile.new()
	if config.parse(read.value) != OK:
		last_error = "无法读取已保存的服务器地址，请重新填写。"
		return ""
	var value: Variant = config.get_value("connection", "server_address", "")
	if not value is String:
		last_error = "已保存的服务器地址格式不正确，请重新填写。"
		return ""
	var result := normalize(value)
	if not result.ok:
		last_error = "已保存的服务器地址无效，请重新填写。"
		return ""
	return result.address

func save_address(raw: String) -> bool:
	last_error = ""
	if not _storage_ready(): return false
	var result := normalize(raw)
	if not result.ok:
		last_error = result.error
		return false
	var config := ConfigFile.new()
	config.set_value("connection", "server_address", result.address)
	var write := Platform.context.storage.write_text_atomic(settings_path, config.encode_to_text())
	if not write.ok:
		last_error = "服务器地址保存失败，请检查本地目录权限。"
		return false
	return true

func _storage_ready() -> bool:
	if Platform.is_available() and not settings_path.is_empty(): return true
	last_error = "平台尚未就绪，无法读写连接配置。"
	return false
