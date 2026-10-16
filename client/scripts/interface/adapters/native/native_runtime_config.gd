extends PlatformRuntimeConfigInterface

const PATHS := {
	"save": {"environment": "SSJX_SAVE_PATH", "default": "user://shushan_save.json"},
	"connection": {"environment": "SSJX_CONNECTION_PATH", "default": "user://connection.cfg"},
}

func local_path(kind: String, explicit_path: String = "") -> PlatformResult:
	if not PATHS.has(kind):
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "UNKNOWN_SETTING", "未知的客户端配置项。")
	var path := explicit_path
	if path.is_empty(): path = OS.get_environment(PATHS[kind].environment)
	if path.is_empty(): path = PATHS[kind].default
	if OS.get_name() == "Windows": path = path.replace("\\", "/")
	return PlatformResult.success(path)
