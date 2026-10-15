class_name ServerLogin
extends Control

signal close_requested
var settings := ServerConnectionSettings.new()
var address_input: LineEdit
var status: Label
var connect_button: Button
var discovery: ServerDiscovery
var register_mode := false
var username_input: LineEdit
var password_input: LineEdit
var auth_button: Button
var switch_button: Button
var _probing := false

func _ready() -> void:
	size = Vector2(284, 368)
	_label("目标服务器地址", Rect2(18, 0, 248, 20))
	address_input = LineEdit.new()
	address_input.name = "ServerAddress"
	address_input.position = Vector2(18, 20)
	address_input.size = Vector2(248, 28)
	address_input.max_length = 1024
	address_input.placeholder_text = "IP:端口 / 域名"
	address_input.text = settings.load_address()
	add_child(address_input)
	_label("地址自动保存；公网账号须用HTTPS。", Rect2(18, 52, 248, 26))
	_label("登录账号（3～32位英数字/下划线）", Rect2(18, 82, 248, 18))
	username_input = _make_input("Username", Rect2(18, 100, 248, 28), 32)
	_label("密码（12～128个字符，不保存）", Rect2(18, 132, 248, 18))
	password_input = _make_input("Password", Rect2(18, 150, 248, 28), 128)
	password_input.secret = true
	status = _label("服务器地址下次登录自动显示。", Rect2(18, 184, 248, 68))
	if not settings.last_error.is_empty(): status.text = settings.last_error
	auth_button = _button("", Rect2(18, 260, 116, 30), _submit_account)
	switch_button = _button("", Rect2(150, 260, 116, 30), _switch_mode)
	connect_button = _button("保存并连接", Rect2(18, 298, 150, 30), connect_server)
	_button("返回", Rect2(178, 298, 88, 30), _return)
	_label("账号与离线角色隔离；不记住密码。", Rect2(18, 334, 248, 22))
	discovery = ServerDiscovery.new()
	add_child(discovery)
	discovery.completed.connect(_connection_result)
	OnlineAccount.completed.connect(_account_result)
	address_input.text_changed.connect(func(_value: String) -> void:
		status.text = "地址已修改，保存并连接后查看服务状态。"
	)
	address_input.text_submitted.connect(func(_value: String) -> void: connect_server())
	address_input.focus_exited.connect(func() -> void: save_draft(false))
	password_input.text_submitted.connect(func(_value: String) -> void: _submit_account())
	_update_controls()
	if OnlineAccount.is_logged_in(): _show_account()
	address_input.grab_focus()

func _make_input(node_name: String, rect: Rect2, limit: int) -> LineEdit:
	var input := LineEdit.new()
	input.name = node_name
	input.position = rect.position
	input.size = rect.size
	input.max_length = limit
	add_child(input)
	return input

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
	_probing = true
	address_input.editable = false
	_update_controls()
	discovery.check_server(address_input.text)

func _connection_result(result: Dictionary) -> void:
	_probing = false
	address_input.editable = true
	_update_controls()
	if not result.ok:
		status.text = result.error + "\n已保存的有效地址不会被清除。"
		return
	var display_name := String(result.server_name).left(24)
	if String(result.server_name).length() > 24: display_name += "…"
	if "account_auth" in result.get("capabilities", []):
		status.text = "已连接：%s\n账号服务可用，请注册或登录。\n角色与多人世界尚未开放。" % display_name
	else:
		status.text = "已连接：%s\n当前仅开放服务连接检查。\n账号登录和多人世界尚未开放。" % display_name

func _update_controls() -> void:
	var locked := OnlineAccount.busy or _probing
	connect_button.disabled = locked
	auth_button.disabled = locked
	switch_button.disabled = locked or OnlineAccount.is_logged_in()
	username_input.editable = not locked and not OnlineAccount.is_logged_in()
	password_input.editable = not locked and not OnlineAccount.is_logged_in()
	address_input.editable = not locked
	auth_button.text = "退出账号" if OnlineAccount.is_logged_in() else ("注册账号" if register_mode else "登录账号")
	switch_button.text = "已有账号" if register_mode else "注册账号"

func _switch_mode() -> void:
	register_mode = not register_mode
	password_input.clear()
	status.text = "注册登录账号，不占用角色昵称。" if register_mode else "请输入账号和密码。"
	_update_controls()

func _submit_account() -> void:
	if auth_button.disabled: return
	if OnlineAccount.is_logged_in():
		status.text = "正在退出账号……"
		OnlineAccount.logout()
		_update_controls()
		return
	if not save_draft(): return
	address_input.text = ServerConnectionSettings.normalize(address_input.text).address
	if username_input.text.strip_edges().is_empty() or password_input.text.is_empty():
		status.text = "请输入账号和密码。"
		return
	status.text = "正在注册账号……" if register_mode else "正在登录……"
	var secret := password_input.text
	password_input.clear()
	if register_mode: OnlineAccount.register_account(address_input.text, username_input.text, secret)
	else: OnlineAccount.login(address_input.text, username_input.text, secret)
	_update_controls()

func _show_account() -> void:
	username_input.text = String(OnlineAccount.account.get("username", ""))
	status.text = "已登录：%s\n账号认证成功。\n线上角色与多人世界尚未开放。" % username_input.text
	if address_input.text != OnlineAccount.server_address:
		status.text = "已登录其他服务器：%s\n请先退出原账号，再更换服务器登录。" % username_input.text
	_update_controls()

func _account_result(action: String, result: Dictionary) -> void:
	password_input.clear()
	_update_controls()
	if not result.ok:
		var errors := {
			"INVALID_USERNAME": "账号须为3～32位英数字或下划线。", "WEAK_PASSWORD": "密码须为12～128个字符，不能全为空白。",
			"ACCOUNT_EXISTS": "账号已存在，请改用其他账号或登录。", "UNAUTHORIZED": "账号或密码错误，或会话已失效。",
			"HTTPS_REQUIRED": "公网账号必须使用HTTPS；HTTP仅允许本机回环地址。", "AUTH_UNAVAILABLE": "该服务器尚未启用账号数据库。",
			"DATABASE_UNAVAILABLE": "数据库暂不可用，请稍后再试。", "RATE_LIMITED": "操作过于频繁，请稍后再试。",
			"SERVER_BUSY": "服务器繁忙，请稍后再试。", "SESSION_LIMIT_REACHED": "有效登录会话过多，请退出旧会话或稍后重试。",
			"LOGOUT_REQUIRED": "请先退出原服务器账号，再登录其他账号。", "NETWORK_ERROR": "网络请求未确认；注册可尝试登录，刷新失败请重新登录。",
		}
		status.text = String(errors.get(result.get("code", ""), "账号请求失败，请检查服务器与客户端版本。"))
		if action == "logout": status.text = "本地已退出，服务器注销未确认。"
		return
	if action == "register":
		register_mode = false
		username_input.text = String(result.account.username)
		status.text = "注册成功，请重新输入密码登录。"
		_update_controls()
	elif action == "logout": status.text = "账号已退出，服务器地址仍会保留。"
	else: _show_account()

func _return() -> void:
	if ServerConnectionSettings.normalize(address_input.text).ok and not save_draft(): return
	discovery.cancel()
	close_requested.emit()

func _exit_tree() -> void:
	# Escape/window close also remembers a valid draft, without touching saves.
	if address_input != null and is_instance_valid(address_input): save_draft(false)
	if discovery != null and is_instance_valid(discovery): discovery.cancel()
	if password_input != null and is_instance_valid(password_input): password_input.clear()
