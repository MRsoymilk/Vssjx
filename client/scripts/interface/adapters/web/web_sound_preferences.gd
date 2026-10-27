extends RefCounted
## A single non-secret flag. Never stores game saves, credentials or endpoints.
const READ_SCRIPT := "(() => { try { return localStorage.getItem('vssjx.sound.enabled.v1') ?? 'true'; } catch (_) { return null; } })()"
const ENABLE_SCRIPT := "(() => { try { localStorage.setItem('vssjx.sound.enabled.v1', 'true'); return localStorage.getItem('vssjx.sound.enabled.v1') === 'true'; } catch (_) { return false; } })()"
const DISABLE_SCRIPT := "(() => { try { localStorage.setItem('vssjx.sound.enabled.v1', 'false'); return localStorage.getItem('vssjx.sound.enabled.v1') === 'false'; } catch (_) { return false; } })()"

func load_enabled() -> PlatformResult:
	if not OS.has_feature("web"): return PlatformResult.unsupported()
	var value: Variant = JavaScriptBridge.eval(READ_SCRIPT, true)
	if value == "true": return PlatformResult.success(true)
	if value == "false": return PlatformResult.success(false)
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "AUDIO_SETTINGS_UNAVAILABLE", "无法读取浏览器声音设置，已使用默认值。")

func save_enabled(enabled: bool) -> PlatformResult:
	if not OS.has_feature("web"): return PlatformResult.unsupported()
	# Only fixed literals cross the bridge, never user input or arbitrary keys.
	var script := ENABLE_SCRIPT if enabled else DISABLE_SCRIPT
	if JavaScriptBridge.eval(script, true) == true: return PlatformResult.success()
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "AUDIO_SETTINGS_UNAVAILABLE", "浏览器未能保存声音设置。")
