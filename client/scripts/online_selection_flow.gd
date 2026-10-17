class_name OnlineSelectionFlow
extends Node
signal enter_requested(character_id: String)
signal create_requested
var _loaded := false
var _entering := false
@onready var page: OriginalCharacterSelection = get_parent()

func _ready() -> void:
	set_process(false)
	page.ready.connect(_start)

func _start() -> void:
	if not page.online_mode: return
	OnlineAccount.completed.connect(_result)
	page.enter_requested.connect(_enter)
	page.create_requested.connect(_create)
	page.refresh_requested.connect(_refresh)
	set_process(true)
	_refresh()

func _process(_delta: float) -> void: _update_controls()

func _update_controls() -> void:
	var locked := OnlineAccount.busy or not OnlineAccount.is_logged_in() or _entering
	page.set_controls(locked or not _loaded, _loaded and (OnlineAccount.characters.size() < OnlineAccount.MAX_CHARACTERS or not OnlineAccount.pending_creation.is_empty()))
	page.get_node("Options/Refresh").disabled = locked
	page.get_node("Options/Create").text = "继续创建" if not OnlineAccount.pending_creation.is_empty() else "创建角色"

func _refresh() -> void:
	if OnlineAccount.busy: return
	_loaded = false
	page.status.text = "正在读取角色……"
	_update_controls()
	OnlineAccount.list_characters()

func _create() -> void:
	if not _loaded or OnlineAccount.busy or not OnlineAccount.is_logged_in(): return
	if OnlineAccount.characters.size() >= OnlineAccount.MAX_CHARACTERS and OnlineAccount.pending_creation.is_empty(): return
	create_requested.emit()

func _enter(id: String) -> void:
	if not _loaded or _entering or OnlineAccount.busy or not OnlineAccount.is_logged_in():
		page._entering = false
		_update_controls()
		return
	for character in OnlineAccount.characters:
		if character.id == id:
			_entering = true
			page.status.text = "正在进入游戏……"
			_update_controls()
			enter_requested.emit(id)
			return
	page._entering = false
	page.status.text = "角色已更新，请刷新后重试。"
	_update_controls()

func _result(action: String, result: Dictionary) -> void:
	if action == "refresh" and result.ok:
		if not _loaded: call_deferred("_refresh")
		return
	if action not in ["characters", "expired", "refresh", "logout"]: return
	if result.ok and action == "characters":
		_loaded = true
		page.display_characters(OnlineAccount.characters)
		page.status.text = "请选择角色后进入游戏" if not OnlineAccount.characters.is_empty() else "尚无角色，请从菜单创建角色"
	else:
		_loaded = false
		if not OnlineAccount.is_logged_in():
			page.display_characters([])
			page.status.text = "登陆已失效，请返回重新登陆。"
		else: page.status.text = "角色读取失败，请从菜单刷新重试。"
	_update_controls()

func _exit_tree() -> void:
	if OnlineAccount.completed.is_connected(_result): OnlineAccount.completed.disconnect(_result)
