extends PlatformLifecycleInterface
var _document: JavaScriptObject
var _window: JavaScriptObject
var _callback: JavaScriptObject

func _ready() -> void:
	if not OS.has_feature("web"): return
	_document = JavaScriptBridge.get_interface("document")
	_window = JavaScriptBridge.get_interface("window")
	_callback = JavaScriptBridge.create_callback(_refresh)
	_document.addEventListener("visibilitychange", _callback)
	for event in ["blur", "focus", "pagehide", "pageshow"]: _window.addEventListener(event, _callback)
	_refresh([])

func _refresh(_arguments: Array) -> void:
	if _document == null: return
	_set_suspended(bool(_document.hidden))
	_set_focused(bool(_document.hasFocus()))

func _set_focused(value: bool) -> void:
	if focused == value: return
	focused = value
	if not value:
		for key in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			var release := InputEventKey.new()
			release.physical_keycode = key
			release.keycode = key
			release.pressed = false
			Input.parse_input_event(release)
	changed.emit("focus_gained" if value else "focus_lost")

func _set_suspended(value: bool) -> void:
	if suspended == value: return
	suspended = value
	changed.emit("suspended" if value else "resumed")

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: _set_focused(true)

func _exit_tree() -> void:
	if _callback != null:
		_document.removeEventListener("visibilitychange", _callback)
		for event in ["blur", "focus", "pagehide", "pageshow"]: _window.removeEventListener(event, _callback)
	_callback = null
	_document = null
	_window = null
