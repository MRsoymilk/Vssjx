class_name ServerLogin
extends Control

signal close_requested
var settings := ServerConnectionSettings.new()
var address_input: LineEdit
var status: Label
var connect_button: Button
var discovery: ServerDiscovery

func _ready() -> void:
	size = Vector2(284, 260)
	_label("目标服务器地址", Rect2(18, 0, 248, 20))
	address_input = LineEdit.new()
	address_input.name = "ServerAddress"
	address_input.position = Vector2(18, 24)
	address_input.size = Vector2(248, 30)
	address_input.max_length = 1024
	address_input.placeholder_text = "IP:端口 / 域名"
	address_input.text = settings.load_address()
	add_child(address_input)
	_label("IP默认HTTP，域名默认HTTPS。\n也可填写完整地址及反向代理前缀。", Rect2(18, 60, 248, 42))
	status = _label("填写后保存，下次登录自动显示。", Rect2(18, 108, 248, 78))
	if not settings.last_error.is_empty(): status.text = settings.last_error
	connect_button = _button("保存并连接", Rect2(18, 196, 150, 34), connect_server)
	_button("返回", Rect2(178, 196, 88, 34), _return)
	_label("仅记住地址，不保存密码。", Rect2(18, 236, 248, 20))
	discovery = ServerDiscovery.new()
	add_child(discovery)
	discovery.completed.connect(_connection_result)
	address_input.text_changed.connect(func(_value: String) -> void:
		status.text = "地址已修改，保存并连接后查看服务状态。"
	)
	address_input.text_submitted.connect(func(_value: String) -> void: connect_server())
	address_input.focus_exited.connect(func() -> void: save_draft(false))
	address_input.grab_focus()

func _label(value: String, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _button(value: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.position = rect.position
	button.size = rect.size
	for state in ["normal", "hover", "pressed"]:
		var skin := StyleBoxFlat.new()
		skin.bg_color = Color("1e3c41") if state == "normal" else Color("315858")
		skin.border_color = Color("b69252")
		skin.set_border_width_all(1)
		button.add_theme_stylebox_override(state, skin)
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(action)
	add_child(button)
	return button

func save_draft(show_error: bool = true) -> bool:
	if not settings.save_address(address_input.text):
		if show_error: status.text = settings.last_error
		return false
	return true

func connect_server() -> void:
	if connect_button.disabled: return
	if not save_draft(): return
	address_input.text = ServerConnectionSettings.normalize(address_input.text).address
	status.text = "地址已保存，正在连接服务器……"
	connect_button.disabled = true
	address_input.editable = false
	discovery.check_server(address_input.text)

func _connection_result(result: Dictionary) -> void:
	connect_button.disabled = false
	address_input.editable = true
	if not result.ok:
		status.text = result.error + "\n已保存的有效地址不会被清除。"
		return
	var display_name := String(result.server_name).left(24)
	if String(result.server_name).length() > 24: display_name += "…"
	status.text = "已连接：%s\n当前仅开放服务连接检查。\n账号登录和多人世界尚未开放。" % display_name

func _return() -> void:
	if ServerConnectionSettings.normalize(address_input.text).ok and not save_draft(): return
	discovery.cancel()
	close_requested.emit()

func _exit_tree() -> void:
	# Escape/window close also remembers a valid draft, without touching saves.
	if address_input != null and is_instance_valid(address_input): save_draft(false)
	if discovery != null and is_instance_valid(discovery): discovery.cancel()
