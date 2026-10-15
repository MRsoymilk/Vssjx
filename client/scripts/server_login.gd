class_name ServerLogin
extends Control

signal close_requested
signal characters_requested
var settings := ServerConnectionSettings.new()
@onready var address_input: LineEdit = $ServerAddress
@onready var status: Label = $Status
@onready var connect_button: Button = $ConnectButton
@onready var discovery: ServerDiscovery = $Discovery
var register_mode := false
@onready var username_input: LineEdit = $Username
@onready var password_input: LineEdit = $Password
@onready var auth_button: Button = $AuthButton
@onready var switch_button: Button = $SwitchButton
var _probing := false

func _ready() -> void:
	address_input.text = settings.load_address()
	if not settings.last_error.is_empty(): status.text = settings.last_error
	auth_button.pressed.connect(_submit_account)
	switch_button.pressed.connect(_switch_mode)
	connect_button.pressed.connect(connect_server)
	$Back.pressed.connect(_return)
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
		status.text = "已连接：%s\n账号服务可用，请注册或登录。\n共享地图尚未开放。" % display_name
	else:
		status.text = "已连接：%s\n当前仅开放服务连接检查。\n账号登录和多人世界尚未开放。" % display_name

func _update_controls() -> void:
	var locked := OnlineAccount.busy or _probing
	connect_button.disabled = locked
	auth_button.disabled = locked
	switch_button.disabled = locked
	username_input.editable = not locked and not OnlineAccount.is_logged_in()
	password_input.editable = not locked and not OnlineAccount.is_logged_in()
	address_input.editable = not locked
	auth_button.text = "退出账号" if OnlineAccount.is_logged_in() else ("注册账号" if register_mode else "登录账号")
	switch_button.text = "线上角色" if OnlineAccount.is_logged_in() else ("已有账号" if register_mode else "注册账号")

func _switch_mode() -> void:
	if OnlineAccount.is_logged_in():
		characters_requested.emit()
		return
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
	status.text = "已登录：%s\n可点击“线上角色”创建或查看角色。\n共享地图尚未开放。" % username_input.text
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
