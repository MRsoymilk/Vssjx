extends PlatformRuntimeConfigInterface

var audio_settings_path := "user://audio.cfg"
var display_settings_path := "user://display.cfg"
const PREFERENCE_STORAGE := preload("res://scripts/interface/adapters/native/native_storage.gd")

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

func connection_options() -> PlatformResult:
	return PlatformResult.success({"editable": true, "server_address": ""})

func check_network_target(address: String) -> PlatformResult:
	# Existing native callers retain their own normalization and HTTPS checks.
	return PlatformResult.success(address)

func allows_remembered_login() -> bool:
	return true

func load_sound_enabled() -> PlatformResult:
	var read := PREFERENCE_STORAGE.new().read_text(audio_settings_path, 4096)
	if read.code == "NOT_FOUND": return PlatformResult.success(true)
	if not read.ok: return read
	var config := ConfigFile.new()
	if config.parse(read.value) != OK or not config.has_section_key("audio", "enabled"):
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_AUDIO_SETTINGS", "声音设置格式不正确，已使用默认值。")
	var enabled: Variant = config.get_value("audio", "enabled", true)
	if not enabled is bool:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_AUDIO_SETTINGS", "声音设置格式不正确，已使用默认值。")
	return PlatformResult.success(enabled)

func save_sound_enabled(enabled: bool) -> PlatformResult:
	var config := ConfigFile.new()
	config.set_value("audio", "enabled", enabled)
	return PREFERENCE_STORAGE.new().write_text_atomic(audio_settings_path, config.encode_to_text())

func load_player_display() -> PlatformResult:
	var read := PREFERENCE_STORAGE.new().read_text(display_settings_path, 4096)
	if read.code == "NOT_FOUND": return PlatformResult.success("normal")
	if not read.ok: return read
	var config := ConfigFile.new()
	if config.parse(read.value) == OK and config.has_section_key("display", "players"):
		var mode: Variant = config.get_value("display", "players", "normal")
		if mode is String and mode in ["normal", "faded", "hidden"]: return PlatformResult.success(mode)
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_DISPLAY_SETTINGS", "人群显示设置无效，已使用正常显示。")

func save_player_display(mode: String) -> PlatformResult:
	if mode not in ["normal", "faded", "hidden"]:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_DISPLAY_SETTINGS", "未知的人群显示方式。")
	var config := ConfigFile.new()
	config.set_value("display", "players", mode)
	return PREFERENCE_STORAGE.new().write_text_atomic(display_settings_path, config.encode_to_text())
