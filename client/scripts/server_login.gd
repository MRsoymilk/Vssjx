class_name ServerLogin
extends Control

signal close_requested
signal characters_requested
signal local_requested
var settings := ServerConnectionSettings.new()
var remembered := RememberedLogin.new()
@onready var address_input: LineEdit = $ServerAddress
@onready var status: Label = $Status
@onready var connect_button: Button = $ConnectButton
@onready var discovery: ServerDiscovery = $Discovery
var register_mode := false
@onready var username_input: LineEdit = $Username
@onready var password_input: LineEdit = $Password
@onready var auth_button: Button = $AuthButton
@onready var switch_button: Button = $SwitchButton
@onready var remember_me: CheckBox = $RememberMe
var _probing := false
var _editing_address := false
var _registration_secret := ""
var _registered_login := false
var _pending_credentials: Dictionary = {}
var _restored_password := false
var _credentials_address := ""

func _ready() -> void:
	address_input.text = settings.load_address()
	if not settings.last_error.is_empty(): status.text = settings.last_error
	_restore_credentials()
	remember_me.toggled.connect(_remember_toggled)
	auth_button.pressed.connect(_login)
	switch_button.pressed.connect(_register)
	connect_button.pressed.connect(_edit_address)
	$Back.pressed.connect(_return)
	discovery.completed.connect(_connection_result)
	OnlineAccount.completed.connect(_account_result)
	address_input.text_changed.connect(func(_value: String) -> void:
		if _restored_password: password_input.clear()
		_restored_password = false
		remember_me.set_pressed_no_signal(false)
		status.text = "地址已修改，点击保存后生效。"
		_update_controls()
	)
	address_input.text_submitted.connect(func(_value: String) -> void: connect_server())
	address_input.focus_exited.connect(func() -> void: save_draft(false))
	password_input.text_submitted.connect(func(_value: String) -> void: _login())
	_update_controls()
	if ServerConnectionSettings.is_local(address_input.text): status.text = "本地单人模式，进度保存在此设备。"
	elif OnlineAccount.is_logged_in(): _show_account()
	username_input.grab_focus()

func _restore_credentials() -> void:
	if _restored_password: password_input.clear()
	_credentials_address = address_input.text
	var saved := remembered.load_saved(address_input.text)
	remember_me.set_pressed_no_signal(not saved.is_empty())
	_restored_password = not saved.is_empty()
	if not saved.is_empty():
		username_input.text = saved.username
		password_input.text = saved.password
	if not remembered.last_error.is_empty(): status.text = remembered.last_error

func _remember_toggled(enabled: bool) -> void:
	if enabled: return
	_pending_credentials = {}
	if not remembered.forget(): status.text = remembered.last_error

func _edit_address() -> void:
	if connect_button.disabled: return
	if _editing_address:
		connect_server()
		return
	_editing_address = true
	_update_controls()
	address_input.grab_focus()
	address_input.select_all()

func _login() -> void:
	if auth_button.disabled: return
	if ServerConnectionSettings.is_local(address_input.text):
		if not save_draft(): return
		password_input.clear()
		local_requested.emit()
		return
	OnlineAccount.set_process(true)
	if OnlineAccount.is_logged_in():
		if not save_draft(): return
		if ServerConnectionSettings.normalize(address_input.text).address != OnlineAccount.server_address:
			status.text = "请先退出原服务器账号，再登陆其他服务器。"
			return
		characters_requested.emit()
		return
	register_mode = false
	_submit_account()

func _register() -> void:
	if switch_button.disabled: return
	OnlineAccount.set_process(true)
	register_mode = true
	_submit_account()

func save_draft(show_error: bool = true) -> bool:
	if not settings.save_address(address_input.text):
		if show_error: status.text = settings.last_error
		return false
	return true

func connect_server() -> void:
	if connect_button.disabled: return
	if not save_draft(): return
	address_input.text = ServerConnectionSettings.normalize(address_input.text).address
	if _credentials_address != address_input.text: _restore_credentials()
	if ServerConnectionSettings.is_local(address_input.text):
		discovery.cancel()
		_probing = false
		_editing_address = false
		password_input.clear()
		status.text = "本地单人模式，进度保存在此设备。"
		_update_controls()
		return
	status.text = "地址已保存，正在连接服务器……"
	_probing = true
	_editing_address = false
	_update_controls()
	discovery.check_server(address_input.text)

func _connection_result(result: Dictionary) -> void:
	_probing = false
	_update_controls()
	if not result.ok:
		status.text = result.error + "\n已保存的有效地址不会被清除。"
		return
	var display_name := String(result.server_name).left(24)
	if String(result.server_name).length() > 24: display_name += "…"
	if "account_auth" in result.get("capabilities", []):
		status.text = "已连接：%s\n请登陆或注册账号。" % display_name
	else:
		status.text = "已连接：%s\n账号服务尚未开放。" % display_name

func _update_controls() -> void:
	var local := ServerConnectionSettings.is_local(address_input.text)
	var locked := _probing or (OnlineAccount.busy and not local)
	connect_button.disabled = locked
	auth_button.disabled = locked
	switch_button.disabled = locked or local
	remember_me.disabled = locked or local
	username_input.editable = not locked and not local and not OnlineAccount.is_logged_in()
	password_input.editable = not locked and not local and not OnlineAccount.is_logged_in()
	username_input.placeholder_text = "本地模式，无需账号" if local else ""
	address_input.editable = not locked and _editing_address
	connect_button.text = "保存" if _editing_address else "修改"
	auth_button.text = "进入游戏" if local or OnlineAccount.is_logged_in() else "登陆"
	switch_button.text = "退出账号" if not local and OnlineAccount.is_logged_in() else "注册"

func _submit_account() -> void:
	if auth_button.disabled: return
	if OnlineAccount.is_logged_in():
		status.text = "正在退出账号……"
		OnlineAccount.logout()
		_update_controls()
		return
	if not save_draft(): return
	address_input.text = ServerConnectionSettings.normalize(address_input.text).address
	if _restored_password and _credentials_address != address_input.text:
		password_input.clear()
		_restore_credentials()
	if username_input.text.strip_edges().is_empty() or password_input.text.is_empty():
		status.text = "请输入账号和密码。"
		return
	_editing_address = false
	status.text = "正在注册账号……" if register_mode else "正在登录……"
	var secret := password_input.text
	_pending_credentials = {"server": address_input.text, "username": username_input.text.strip_edges().to_lower(), "password": secret} if remember_me.button_pressed else {}
	_restored_password = false
	password_input.clear()
	if register_mode:
		_registration_secret = secret
		OnlineAccount.register_account(address_input.text, username_input.text, secret)
	else: OnlineAccount.login(address_input.text, username_input.text, secret)
	_update_controls()

func _show_account() -> void:
	username_input.text = String(OnlineAccount.account.get("username", ""))
	status.text = "已登录：%s\n点击进入游戏，查看线上角色。" % username_input.text
	if address_input.text != OnlineAccount.server_address:
		status.text = "已登录其他服务器：%s\n请先退出原账号，再更换服务器登录。" % username_input.text
	_update_controls()

func _account_result(action: String, result: Dictionary) -> void:
	if ServerConnectionSettings.is_local(address_input.text): return
	password_input.clear()
	_update_controls()
	if not result.ok:
		_pending_credentials = {}
		_registration_secret = ""
		var errors := {
			"INVALID_USERNAME": "账号须为3～32位英数字或下划线。", "WEAK_PASSWORD": "密码须为12～128个字符，不能全为空白。",
			"ACCOUNT_EXISTS": "账号已存在，请改用其他账号或登录。", "UNAUTHORIZED": "账号或密码错误，或会话已失效。",
			"HTTPS_REQUIRED": "公网账号必须使用HTTPS；HTTP仅允许本机回环地址。", "AUTH_UNAVAILABLE": "该服务器尚未启用账号数据库。",
			"DATABASE_UNAVAILABLE": "数据库暂不可用，请稍后再试。", "RATE_LIMITED": "操作过于频繁，请稍后再试。",
			"SERVER_BUSY": "服务器繁忙，请稍后再试。", "SESSION_LIMIT_REACHED": "有效登录会话过多，请退出旧会话或稍后重试。",
			"LOGOUT_REQUIRED": "请先退出原服务器账号，再登录其他账号。", "NETWORK_ERROR": "网络请求未确认；注册可尝试登录，刷新失败请重新登录。",
		}
		status.text = String(errors.get(result.get("code", ""), "账号请求失败，请检查服务器与客户端版本。"))
		if _registered_login: status.text = "注册成功，请使用刚才的账号密码登陆。\n" + status.text
		_registered_login = false
		if action == "logout": status.text = "本地已退出，服务器注销未确认。"
		return
	if action == "register":
		register_mode = false
		username_input.text = String(result.account.username)
		if _registration_secret.is_empty():
			status.text = "注册成功，请使用此账号登陆。"
			return
		status.text = "注册成功，正在登陆并读取角色……"
		var secret := _registration_secret
		_registration_secret = ""
		_registered_login = true
		OnlineAccount.login(address_input.text, username_input.text, secret)
		_update_controls()
	elif action == "logout":
		_restore_credentials()
		status.text = "账号已退出，服务器地址仍会保留。"
	else:
		if action == "login" and not _pending_credentials.is_empty():
			var saved := remembered.remember(_pending_credentials.server, _pending_credentials.username, _pending_credentials.password)
			_pending_credentials = {}
			if not saved:
				_show_account()
				status.text += "\n" + remembered.last_error
				return
		_show_account()
		if action == "login":
			_registered_login = false
			characters_requested.emit()

func _return() -> void:
	if ServerConnectionSettings.normalize(address_input.text).ok and not save_draft(): return
	discovery.cancel()
	close_requested.emit()

func _exit_tree() -> void:
	_pending_credentials = {}
	_registration_secret = ""
	if OnlineAccount.completed.is_connected(_account_result): OnlineAccount.completed.disconnect(_account_result)
	# Escape/window close also remembers a valid draft, without touching saves.
	if address_input != null and is_instance_valid(address_input): save_draft(false)
	if discovery != null and is_instance_valid(discovery): discovery.cancel()
	if password_input != null and is_instance_valid(password_input): password_input.clear()
