class_name OnlineCreationFlow
extends Node
## Reuses the original creation scene, with all account state owned by the server.
signal enter_requested(character_id: String)
signal close_requested
var _loaded := false
var _entering := false
@onready var page: OriginalCharacterCreation = get_parent()
@onready var status: Label = $"../OnlineControls/Status"
@onready var school: OptionButton = $"../OnlineControls/School"

func _ready() -> void:
	set_process(false)
	page.ready.connect(_start)

func _start() -> void:
	if not page.online_mode: return
	$"../OnlineControls".show()
	$"../OnlineControls/Account".text = "账号：" + String(OnlineAccount.account.get("username", ""))
	$"../OnlineControls/Back".pressed.connect(func() -> void: close_requested.emit())
	page.create_requested.connect(_create)
	page.nickname.text_changed.connect(func(_text: String) -> void:
		if page.active and _loaded and OnlineAccount.pending_creation.is_empty(): status.text = "选择角色并创建，以后使用此账号登陆。"
	)
	OnlineAccount.completed.connect(_result)
	_restore_pending()
	set_process(true)
	_refresh()

func _restore_pending() -> void:
	var pending := OnlineAccount.pending_creation
	if pending.is_empty(): return
	page.active = true
	page.select_variant(int(pending.job) * 2 + int(pending.gender))
	page.nickname.text = pending.display_name
	school.select(int(pending.school))

func _process(_delta: float) -> void:
	_update_controls()

func _update_controls() -> void:
	var locked := OnlineAccount.busy or not OnlineAccount.is_logged_in() or _entering
	var pending := not OnlineAccount.pending_creation.is_empty()
	var full := _loaded and OnlineAccount.characters.size() >= OnlineAccount.MAX_CHARACTERS
	page.active = not locked and _loaded and not pending and not full
	for button in page.portrait_buttons: button.disabled = not page.active
	for path in ["Previous", "Next", "Edit", "Rename", "Random"]: page.get_node(path).disabled = not page.active
	school.disabled = not page.active
	$"../Create".disabled = locked or (full and not pending)
	$"../Create".text = "重试" if pending or not _loaded else "创建"

func _refresh() -> void:
	status.text = "正在读取该账号的角色……"
	_update_controls()
	if not OnlineAccount.busy: OnlineAccount.list_characters()
	_update_controls()

func _create() -> void:
	if $"../Create".disabled: return
	var input_result := Platform.context.text_input.check_submission([page.nickname])
	if not input_result.ok:
		status.text = input_result.message
		return
	if not _loaded:
		_refresh()
		return
	if OnlineAccount.pending_creation.is_empty() and not OnlineAccount.valid_nickname(page.nickname.text):
		status.text = "昵称须为2～12位汉字、英数字或下划线。"
		return
	status.text = "正在创建角色，请稍候……"
	OnlineAccount.create_character(page.nickname.text, floori(page.selected_variant / 2.0), page.selected_variant % 2, school.selected)
	_update_controls()

func _result(action: String, result: Dictionary) -> void:
	if _entering: return
	if action == "refresh" and result.ok:
		if not _loaded: call_deferred("_refresh")
		return
	if action not in ["characters", "character_create", "expired", "refresh"]: return
	if not result.ok:
		var errors := {"NAME_TAKEN": "昵称已被占用，请修改后创建。", "CHARACTER_LIMIT_REACHED": "角色已满（5/5），请返回选择已有角色。", "INVALID_NAME": "昵称不符合规则，请修改。", "UNAUTHORIZED": "登陆已失效，请返回重新登陆。", "RULES_UNSUPPORTED": "创建规则不兼容，请更新客户端。", "RATE_LIMITED": "请求过于频繁，请稍后重试。", "DATABASE_UNAVAILABLE": "数据库暂不可用，请稍后重试。"}
		status.text = String(errors.get(result.get("code", ""), "请求未确认，请重试。"))
		if result.get("code") == "CHARACTER_LIMIT_REACHED": _loaded = false
		if not OnlineAccount.pending_creation.is_empty():
			_restore_pending()
			status.text += "\n保留原创建请求，重试不会重复创建。"
	elif action == "characters":
		_loaded = true
		status.text = "选择角色并创建（%d/5）。" % OnlineAccount.characters.size()
		if OnlineAccount.characters.size() >= OnlineAccount.MAX_CHARACTERS: status.text = "角色已满（5/5），请返回选择已有角色。"
		if not OnlineAccount.pending_creation.is_empty(): status.text = "原创建尚未确认，请重试原请求。"
	else:
		_loaded = true
		_entering = true
		status.text = "正在打开角色选择面板……"
		enter_requested.emit(String(result.get("character_id", "")))
	_update_controls()

func _unhandled_key_input(event: InputEvent) -> void:
	if page.online_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if OnlineAccount.completed.is_connected(_result): OnlineAccount.completed.disconnect(_result)
