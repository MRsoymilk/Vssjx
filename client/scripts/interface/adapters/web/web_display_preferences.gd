extends RefCounted
## A non-secret display flag, never a source of game state or network targets.
const READ_SCRIPT := "(() => { try { return localStorage.getItem('vssjx.players.display.v1') ?? 'normal'; } catch (_) { return null; } })()"
const NORMAL_SCRIPT := "(() => { try { localStorage.setItem('vssjx.players.display.v1', 'normal'); return localStorage.getItem('vssjx.players.display.v1') === 'normal'; } catch (_) { return false; } })()"
const FADED_SCRIPT := "(() => { try { localStorage.setItem('vssjx.players.display.v1', 'faded'); return localStorage.getItem('vssjx.players.display.v1') === 'faded'; } catch (_) { return false; } })()"
const HIDDEN_SCRIPT := "(() => { try { localStorage.setItem('vssjx.players.display.v1', 'hidden'); return localStorage.getItem('vssjx.players.display.v1') === 'hidden'; } catch (_) { return false; } })()"

func load_mode() -> PlatformResult:
	if not OS.has_feature("web"): return PlatformResult.unsupported()
	var value: Variant = JavaScriptBridge.eval(READ_SCRIPT, true)
	if value is String and value in ["normal", "faded", "hidden"]: return PlatformResult.success(value)
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "DISPLAY_SETTINGS_UNAVAILABLE", "无法读取浏览器人群显示设置。")

func save_mode(mode: String) -> PlatformResult:
	if not OS.has_feature("web"): return PlatformResult.unsupported()
	var scripts := {"normal": NORMAL_SCRIPT, "faded": FADED_SCRIPT, "hidden": HIDDEN_SCRIPT}
	if not scripts.has(mode): return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_DISPLAY_SETTINGS", "未知的人群显示方式。")
	if JavaScriptBridge.eval(scripts[mode], true) == true: return PlatformResult.success()
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "DISPLAY_SETTINGS_UNAVAILABLE", "浏览器未能保存人群显示设置。")
