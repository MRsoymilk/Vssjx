class_name OnlineCharacters
extends Control
## Lobby only: never installs an online snapshot in Game.player.
signal close_requested
var nickname: LineEdit
var job: OptionButton
var gender: OptionButton
var school: OptionButton
var status: Label
var create_button: Button
var refresh_button: Button
var _loaded := false

func _ready() -> void:
	size = Vector2(284, 368)
	_label("线上角色 · 每账号限一个", Rect2(18, 0, 248, 22))
	_label("2～12位汉字、英数字或下划线\n全服唯一；英文大小写不区分", Rect2(18, 26, 248, 40))
	nickname = LineEdit.new()
	nickname.name = "OnlineNickname"
	nickname.position = Vector2(18, 70)
	nickname.size = Vector2(248, 28)
	nickname.max_length = 32
	nickname.placeholder_text = "请输入线上昵称"
	add_child(nickname)
	job = _choice("Job", ["力士", "侠客", "隐者"], Vector2(18, 108), 92)
	gender = _choice("Gender", ["男", "女"], Vector2(116, 108), 62)
	school = _choice("School", ["峨眉", "花涧", "昆仑"], Vector2(184, 108), 82)
	status = _label("正在读取线上角色……", Rect2(18, 148, 248, 118))
	create_button = _button("创建角色", Rect2(18, 274, 156, 30), _create)
	refresh_button = _button("刷新", Rect2(182, 274, 84, 30), _refresh)
	_button("返回账号", Rect2(18, 326, 248, 30), func() -> void: close_requested.emit())
	OnlineAccount.completed.connect(_result)
	_restore_pending()
	_update_controls()
	_refresh()

func _process(_delta: float) -> void:
	_update_controls()

func _label(text_value: String, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)
	return label

func _button(text_value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(callback)
	add_child(button)
	return button

func _choice(node_name: String, choices: Array, position_value: Vector2, width: float) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = node_name
	choice.position = position_value
	choice.size = Vector2(width, 28)
	for text_value in choices: choice.add_item(text_value)
	add_child(choice)
	return choice

func _restore_pending() -> void:
	var pending: Dictionary = OnlineAccount.pending_creation
	if pending.is_empty(): return
	nickname.text = pending.display_name
	job.select(int(pending.job))
	gender.select(int(pending.gender))
	school.select(int(pending.school))

func _update_controls() -> void:
	var locked := OnlineAccount.busy or not OnlineAccount.is_logged_in()
	var exists := not OnlineAccount.characters.is_empty()
	var pending := not OnlineAccount.pending_creation.is_empty()
	nickname.editable = not locked and not exists and not pending
	for choice in [job, gender, school]: choice.disabled = locked or exists or pending
	create_button.disabled = locked or exists or not _loaded
	create_button.text = "重试原创建请求" if pending else "创建角色"
	refresh_button.disabled = locked

func _refresh() -> void:
	if OnlineAccount.busy: return
	status.text = "正在读取线上角色……"
	OnlineAccount.list_characters()
	_update_controls()

func _create() -> void:
	if create_button.disabled: return
	if OnlineAccount.pending_creation.is_empty() and not OnlineAccount.valid_nickname(nickname.text):
		status.text = "昵称须为2～12位汉字、英数字或下划线。\n请勿使用内部空格、全角字母或控制符。"
		return
	status.text = "正在提交；请勿重复创建……"
	OnlineAccount.create_character(nickname.text, job.selected, gender.selected, school.selected)
	_update_controls()

func _result(action: String, result: Dictionary) -> void:
	if action == "refresh" and result.ok:
		# Opening this page during an unrelated automatic refresh must still load it.
		if not _loaded: call_deferred("_refresh")
		return
	if action not in ["characters", "character_create", "expired", "refresh"]: return
	if not result.ok:
		var errors := {"NAME_TAKEN": "昵称已被占用，请修改昵称后重新创建。", "CHARACTER_LIMIT_REACHED": "账号已有角色，请刷新查看。", "INVALID_NAME": "昵称不符合规则，请修改。", "UNAUTHORIZED": "登录已失效，请返回账号重新登录。", "RULES_UNSUPPORTED": "创建规则不兼容，请更新客户端。", "RATE_LIMITED": "请求过于频繁，请稍后重试。", "DATABASE_UNAVAILABLE": "数据库暂不可用，请稍后重试。"}
		status.text = String(errors.get(result.get("code", ""), "请求未确认，请稍后重试。"))
		if not OnlineAccount.pending_creation.is_empty(): status.text += "\n结果未知，保留原操作；重试不会重复发放资产。"
	else:
		_loaded = true
		if OnlineAccount.characters.is_empty():
			status.text = "尚无线上角色。\n线上角色不会导入或覆盖本地存档。"
			if not OnlineAccount.pending_creation.is_empty(): status.text += "\n原创建尚未确认，请重试原请求。"
		else:
			var character: Dictionary = OnlineAccount.characters[0]
			nickname.text = character.display_name
			job.select(int(character.job))
			gender.select(int(character.gender))
			school.select(int(character.school))
			status.text = "线上角色：%s\n等级%d · 金币%d\n角色已存入服务器，可重新登录查看。\n共享地图尚未开放；不会进入离线世界。" % [character.display_name, character.level, character.gold]
	_update_controls()
