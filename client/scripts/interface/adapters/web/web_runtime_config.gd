extends PlatformRuntimeConfigInterface
## Same-origin network configuration controlled by the exported build.
## Page path, query, fragment, JS config globals and saved preferences are ignored.
var _profile: Resource = preload("res://scripts/interface/profiles/web_runtime.tres")

func local_path(kind: String, explicit_path: String = "") -> PlatformResult:
	if kind == "save" and explicit_path.is_empty(): return PlatformResult.success("offline://save-v1")
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "UNKNOWN_SETTING", "网页不接受本地路径或环境变量覆盖。")

func _page_origin() -> String:
	if not OS.has_feature("web"): return ""
	var value: Variant = JavaScriptBridge.eval("window.location.origin", true)
	return value if value is String else ""

func connection_options() -> PlatformResult:
	var origin := _page_origin()
	var parsed := RegEx.create_from_string("^(https?)://(\\[[0-9a-f:.]+\\]|[a-z0-9.-]+)(?::([0-9]{1,5}))?\\z").search(origin)
	if parsed == null or origin.length() > 1024: return _invalid()
	var host := parsed.get_string(2)
	if host.begins_with("["):
		if not host.contains(":") or not host.trim_prefix("[").trim_suffix("]").is_valid_ip_address(): return _invalid()
	elif not host.is_valid_ip_address():
		var label_pattern := RegEx.create_from_string("^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\z")
		if host.length() > 253: return _invalid()
		for label in host.split("."):
			if label_pattern.search(label) == null: return _invalid()
		# Reject URL numeric-host aliases, even in a malformed test/embedding origin.
		var last := host.get_slice(".", host.get_slice_count(".") - 1)
		if last.is_valid_int() or last.begins_with("0x"): return _invalid()
	var port := parsed.get_string(3)
	if not port.is_empty() and (int(port) < 1 or int(port) > 65535): return _invalid()
	if parsed.get_string(1) != "https":
		var loopback := host == "localhost" or host == "[::1]" or (host.is_valid_ip_address() and host.begins_with("127."))
		if not _profile.allow_loopback_http or not loopback: return _invalid()
	var prefix: String = _profile.api_prefix
	# Deliberately narrower than native URLs: build prefix consists of path segments.
	if prefix.length() > 256 or (not prefix.is_empty() and RegEx.create_from_string("^(/[a-zA-Z0-9_-]+)+\\z").search(prefix) == null): return _invalid()
	return PlatformResult.success({"editable": false, "server_address": origin + prefix})

func check_network_target(address: String) -> PlatformResult:
	var options := connection_options()
	if not options.ok: return options
	if address != options.value.server_address:
		return PlatformResult.new(PlatformResult.Status.DENIED, "TARGET_NOT_ALLOWED", "网页仅可连接本站配置的游戏服务。")
	return PlatformResult.success(address)

func _invalid() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "WEB_CONFIG_INVALID", "网页服务配置不可用，请通过受信任的HTTPS游戏入口打开。")
