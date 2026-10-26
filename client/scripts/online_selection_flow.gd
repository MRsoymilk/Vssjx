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
	page.delete_requested.connect(_delete)
	set_process(true)
	_refresh()

func _process(_delta: float) -> void: _update_controls()

func _update_controls() -> void:
	var locked := OnlineAccount.busy or not OnlineAccount.is_logged_in() or _entering
	page.set_controls(locked or not _loaded, _loaded and (OnlineAccount.characters.size() < OnlineAccount.MAX_CHARACTERS or not OnlineAccount.pending_creation.is_empty()))
	page.get_node("Options/Refresh").disabled = locked or page._deleting or not page._delete_target.is_empty()
	page.get_node("Options/Create").text = "继续创建" if not OnlineAccount.pending_creation.is_empty() else "创建角色"
	if not OnlineAccount.pending_creation.is_empty(): page.get_node("Options/Delete").disabled = true
	if not OnlineAccount.pending_deletion.is_empty():
		page.get_node("Options/Create").disabled = true
		if not page.characters.is_empty() and page.characters[page.selected_index].id != OnlineAccount.pending_deletion.character_id: page.get_node("Options/Delete").disabled = true

func _delete(id: String, character_name: String) -> void:
	if not _loaded or OnlineAccount.busy or not OnlineAccount.is_logged_in():
		page.finish_delete()
		return
	page.status.text = "正在删除角色……"
	OnlineAccount.delete_character(id, character_name)
	_update_controls()

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
	if action == "character_delete":
		page.finish_delete()
		if result.ok:
			page.display_characters(OnlineAccount.characters)
			_refresh()
		else:
			page.status.text = {
				"CHARACTER_BUSY": "角色仍在游戏中，请退出并稍后重试",
				"CHARACTER_IN_GUILD": "请先退出公会，或转让会长并退出",
				"CHARACTER_IN_TEAM": "请先退出队伍后再删除角色",
				"CHARACTER_HAS_ESCROW": "请先结束拍卖／交易，并领取全部装备、货款及退款",
				"CHARACTER_NOT_FOUND": "角色已更新，请从菜单刷新",
				"CHARACTER_CHANGED": "角色已更新，请从菜单刷新",
				"DELETE_RETRY_REQUIRED": "请先重试上次删除，或刷新角色列表",
				"NOT_FOUND": "服务器尚不支持删除角色，请更新服务端",
			}.get(result.get("code", ""), "删除未确认，请刷新或选择原角色重试")
			if not OnlineAccount.is_logged_in():
				_loaded = false
				page.display_characters([])
				page.status.text = "登陆已失效，请返回重新登陆。"
		_update_controls()
		return
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
