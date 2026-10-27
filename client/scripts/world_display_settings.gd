class_name WorldDisplaySettings
extends RefCounted
## Device-only presentation. All authoritative entities continue to synchronize.
const MODES := ["normal", "faded", "hidden"]
const LABELS := ["正常", "半透明", "隐藏"]
static var mode := "normal"
static var initialized := false
static var last_error := ""

static func initialize() -> void:
	if initialized or not Platform.is_available(): return
	initialized = true
	var result := Platform.context.runtime_config.load_player_display()
	mode = result.value if result.ok and result.value is String and result.value in MODES else "normal"
	last_error = "" if result.ok else result.message

static func set_mode(value: String) -> PlatformResult:
	initialize()
	if value not in MODES: return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_DISPLAY_SETTINGS", "未知的人群显示方式。")
	mode = value
	var result := Platform.context.runtime_config.save_player_display(value) if Platform.is_available() else PlatformResult.unsupported()
	last_error = "" if result.ok else result.message
	return result
