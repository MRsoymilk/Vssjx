extends Node
## Owns DOM lifetime. Fields are weak references; no password/draft cache is kept here.
const SOURCE := "res://scripts/interface/adapters/web/browser_text_input.js"
var _bridge: JavaScriptObject
var _callback: JavaScriptObject
var _fields: Dictionary = {}

func _ready() -> void:
	if not OS.has_feature("web"): return
	var name := "__vssjx_input_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var key := JSON.stringify(name)
	JavaScriptBridge.eval("globalThis[" + key + "] = " + FileAccess.get_file_as_string(SOURCE), true)
	var factory := JavaScriptBridge.get_interface(name)
	_callback = JavaScriptBridge.create_callback(_receive)
	_bridge = factory.create(_callback)
	JavaScriptBridge.eval("delete globalThis[" + key + "]", true)
	# Focus must be resolved in the original touch gesture, not a later engine frame.
	Input.use_accumulated_input = false
	get_tree().node_added.connect(_added)
	get_tree().node_removed.connect(_removed)
	_scan(get_tree().root)

func _scan(node: Node) -> void:
	_added(node)
	for child in node.get_children(): _scan(child)

func _added(node: Node) -> void:
	if node is LineEdit: _track.call_deferred(weakref(node))

func _track(reference: WeakRef) -> void:
	var field: LineEdit = reference.get_ref()
	if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion(): return
	var id := str(field.get_instance_id())
	if _fields.has(id): return
	_fields[id] = reference
	field.virtual_keyboard_enabled = false
	var colors := {}
	for color in ["font_color", "font_uneditable_color", "font_selected_color", "caret_color"]:
		colors[color] = {"value": field.get_theme_color(color), "override": field.has_theme_color_override(color)}
	field.set_meta("_web_input_colors", colors)
	field.focus_entered.connect(_godot_focused.bind(reference))
	field.focus_exited.connect(_godot_blurred.bind(reference))
	field.editing_toggled.connect(func(editing: bool) -> void:
		if editing: _finish_focus.call_deferred(reference))
	_sync(field)

func _removed(node: Node) -> void:
	if not node is LineEdit: return
	var id := str(node.get_instance_id())
	_fields.erase(id)
	if _bridge != null: _bridge.remove(id)

func _process(_delta: float) -> void:
	if _bridge == null: return
	for id: String in _fields.keys():
		var field: LineEdit = _fields[id].get_ref()
		if not is_instance_valid(field) or field.is_queued_for_deletion():
			_bridge.remove(id)
			_fields.erase(id)
		elif not field.is_inside_tree() or not field.is_visible_in_tree(): _bridge.remove(id)
		else: _sync(field)

func _sync(field: LineEdit) -> void:
	if _bridge == null or field.get_viewport() != get_tree().root: return
	var rect := field.get_global_rect()
	var size := field.get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0: return
	var focused := field.has_focus() and field.editable
	var colors: Dictionary = field.get_meta("_web_input_colors")
	if bool(field.get_meta("_web_input_paint", false)) != focused:
		field.set_meta("_web_input_paint", focused)
		for color in colors:
			if focused: field.add_theme_color_override(color, Color.TRANSPARENT)
			elif colors[color].override: field.add_theme_color_override(color, colors[color].value)
			else: field.remove_theme_color_override(color)
	var labels := {"Password":"密码", "Username":"用户名", "ChatInput":"聊天消息", "Nickname":"昵称", "Signature":"签名", "ServerAddress":"服务地址"}
	var meta := {"id": str(field.get_instance_id()), "name": String(field.name),
		"label": labels.get(String(field.name), field.placeholder_text if not field.placeholder_text.is_empty() else String(field.name)),
		"x": rect.position.x / size.x, "y": rect.position.y / size.y,
		"w": rect.size.x / size.x, "h": rect.size.y / size.y,
		"font": float(field.get_theme_font_size("font_size")) / size.x,
		"secret": field.secret, "editable": field.editable and field.focus_mode != Control.FOCUS_NONE,
		"focused": focused, "color": colors.font_color.value.to_html(false),
		"placeholder": field.placeholder_text, "caret": field.caret_column,
		"start": field.get_selection_from_column() if field.has_selection() else field.caret_column,
		"end": field.get_selection_to_column() if field.has_selection() else field.caret_column}
	_bridge.update(JSON.stringify(meta), field.text)

func _godot_focused(reference: WeakRef) -> void:
	var field: LineEdit = reference.get_ref()
	# LineEdit activates the engine IME after emitting focus_entered.
	# Publish geometry now; finish focus after that notification has completed.
	if is_instance_valid(field):
		_sync(field)
		_finish_focus.call_deferred(reference)

func _finish_focus(reference: WeakRef) -> void:
	var field: LineEdit = reference.get_ref()
	if is_instance_valid(field) and field.has_focus(): focus_field(field)

func _godot_blurred(reference: WeakRef) -> void:
	var field: LineEdit = reference.get_ref()
	if is_instance_valid(field) and _bridge != null:
		_bridge.blur(str(field.get_instance_id()))
		if field.is_inside_tree(): _sync(field)

func focus_field(field: LineEdit, select_all: bool = false) -> void:
	if _bridge == null or not field.is_visible_in_tree(): return
	_track(weakref(field))
	_sync(field)
	# Native DOM owns editing; leave Godot focus for movement/modal guards. LineEdit's
	# draw notification would otherwise reactivate its invisible IME every redraw.
	field.unedit()
	DisplayServer.window_set_ime_active(false)
	_bridge.focus(str(field.get_instance_id()), select_all)

func blur_field(field: LineEdit) -> void:
	if _bridge != null: _bridge.blur(str(field.get_instance_id()))

func is_composing(field: LineEdit) -> bool:
	return _bridge != null and bool(_bridge.composing(str(field.get_instance_id())))

func _receive(arguments: Array) -> void:
	if arguments.size() < 2: return
	var kind := String(arguments[0])
	var id := String(arguments[1])
	if not _fields.has(id): return
	var field: LineEdit = _fields[id].get_ref()
	if not is_instance_valid(field) or not field.is_inside_tree() or not field.is_visible_in_tree() or field.is_queued_for_deletion(): return
	match kind:
		"focus":
			if not field.editable: return
			field.grab_focus()
			focus_field(field)
		"blur": field.release_focus()
		"input":
			if not field.editable or arguments.size() != 5: return
			var value := String(arguments[2])
			if field.max_length > 0: value = value.left(field.max_length)
			var changed := field.text != value
			field.text = value
			var start := clampi(int(arguments[3]), 0, value.length())
			var end := clampi(int(arguments[4]), 0, value.length())
			field.caret_column = end
			if start != end: field.select(start, end)
			else: field.deselect()
			if changed: field.text_changed.emit(value)
		"submit":
			if field.editable and not is_composing(field): field.text_submitted.emit(field.text)
			if is_instance_valid(field) and field.is_inside_tree() and not field.is_queued_for_deletion(): _sync(field)
		"escape":
			field.release_focus()
			_bridge.blur(id)

func _exit_tree() -> void:
	if _bridge != null: _bridge.dispose()
	_bridge = null
	_callback = null
	_fields.clear()
