extends Control
## 320×480 offline reconstruction, with mouse/touch and keyboard controls.

const INK := Color("102027")
const PAPER := Color("eee6cc")
const GOLD := Color("e9c67c")
const TEAL := Color("7cc7bd")
var mode := "home"
@onready var ui: Control = $UI
@onready var announcement_banner: AnnouncementBanner = $Announcements/Banner
var world_view: TextureRect
var viewport: SubViewport
var world: ShushanWorld
var hud_name: Label
var hud_stats: Label
var quest_label: Label
var modal: Control
var battle: ShushanBattle
var battle_hero: AnimatedSprite2D
var battle_enemy: AnimatedSprite2D
var battle_log: Label
var battle_status: Label
var battle_enemy_status: Label
var battle_hero_status: Label
var battle_stage := "select"
var battle_round: Label
var battle_buttons: Array[Button] = []
var battle_auto := false
var auto_timer := 0.0
var battle_committed := false
var selected_job := 0
var selected_gender := 0
var selected_school := 0
var nickname: LineEdit
var preview: AnimatedSprite2D
var create_description: Label
var autosave_timer := 0.0
var original_cover: OriginalCover
var creation: OriginalCharacterCreation
var attributes: OriginalCharacterAttributes
var chrome: OriginalSceneChrome
var action_menu: Panel
var battle_hero_hp: ProgressBar
var battle_hero_mp: ProgressBar
var battle_enemy_hp: ProgressBar
var auto_button: Button
var battle_selected_enemy := false
var battle_field: OriginalBattleField
var field_kind := "courtyard"
var battle_move_callout: BattleMoveCallout
var battle_transition: BattleEncounterTransition
var battle_transition_epoch := 0
var battle_resource_request: PlatformResourceRequest
var battle_playback: BattleActionPlayback
var battle_ring: Node2D
var clock_timer := 0.0
var effects_layer: Control
var world_identity: Label
var backpack: OriginalInventory
var minimap: OriginalWorldMinimap
var map_name: Label
var map_coordinates: Label
var character_selection: OriginalCharacterSelection
var _ui_epoch := 0
var _storage_notice: Label
var _ui_process_mode: ProcessMode
var _closing := false

func _exit_tree() -> void:
	_ui_epoch += 1
	if battle_playback != null: battle_playback.cancel()
	battle_playback = null
	Game.invalidate_load()

func _ready() -> void:
	get_tree().auto_accept_quit = false
	var platform_result := await Platform.when_ready()
	if platform_result.ok: platform_result = await Game.when_ready()
	if not platform_result.ok:
		_label(ui, platform_result.message, Rect2(16, 80, 288, 180), 16)
		set_process(false)
		set_process_unhandled_key_input(false)
		return
	Game.storage_changed.connect(_storage_changed)
	if OS.has_feature("web"): Platform.context.lifecycle.changed.connect(_web_lifecycle)
	_home()
	if Game.storage_busy: _storage_changed(true)

func _storage_changed(active: bool) -> void:
	if active:
		_ui_process_mode = ui.process_mode
		ui.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(world):
			world.enabled = false
		_storage_notice = _label(self, "正在处理本地存档，请稍候……", Rect2(12, 4, 296, 42), 13, GOLD, true)
		_storage_notice.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		ui.process_mode = _ui_process_mode
		if is_instance_valid(_storage_notice): _storage_notice.queue_free()
		_storage_notice = null
		if mode == "world" and modal == null and is_instance_valid(world): world.enabled = true

func _save_current() -> PlatformResult:
	var epoch := _ui_epoch
	var result := await Game.save_game()
	if not is_inside_tree() or epoch != _ui_epoch:
		return PlatformResult.new(PlatformResult.Status.CANCELLED, "STALE_PAGE", "页面已变化。")
	return result

func _save_local_change() -> void:
	var result := await _save_current()
	if result.status == PlatformResult.Status.CANCELLED or _closing: return
	_close_modal()
	_refresh_hud()
	if not result.ok: _message("保存失败", result.message + "\n当前变更仅在内存中，请重试保存。")

func _autosave() -> void:
	if Game.storage_busy or _closing: return
	var result := await _save_current()
	if not _closing and not result.ok and result.status != PlatformResult.Status.CANCELLED:
		_message("自动保存失败", result.message + "\n当前进度仍在内存中。")

func _process(delta: float) -> void:
	if Game.storage_busy or _closing: return
	if OS.has_feature("web") and (not Platform.context.lifecycle.focused or Platform.context.lifecycle.suspended): return
	if battle_playback != null: battle_playback.advance(delta)
	clock_timer += delta
	if clock_timer >= 1.0 and chrome != null and is_instance_valid(chrome):
		clock_timer = 0.0
		if mode == "world": chrome.update_header(int(Game.player.hp), int(Game.player.mp), 0)
		elif mode == "battle": chrome.update_header(battle.hp, battle.mp, battle.round_number)
	if mode == "battle" and battle_auto and battle.phase == "select" and modal == null:
		auto_timer += delta
		if auto_timer >= 0.9:
			auto_timer = 0.0
			var command := "attack"
			if battle.hp < int(Game.stats().hp) / 3 and battle.potions > 0:
				command = "potion"
			elif battle.mp >= 9:
				command = "skill"
			_battle_turn(command)
	if mode == "world":
		autosave_timer += delta
		if autosave_timer >= 10.0:
			autosave_timer = 0.0
			_autosave()

func _unhandled_key_input(event: InputEvent) -> void:
	if Game.storage_busy or _closing: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if mode == "battle_loading":
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if mode == "battle" and battle.phase == "finished":
			_enter_world()
		elif modal != null:
			_close_modal()
		elif mode == "attributes":
			_return_from_attributes()
		elif mode == "world":
			_menu()
		elif mode == "create":
			_home()
	elif mode == "world" and modal == null and event.keycode == KEY_C:
		_attributes()
	elif mode == "world" and modal == null and event.keycode == KEY_3:
		_open_world_map()
	elif mode == "world" and modal == null and event.keycode in [KEY_E, KEY_ENTER]:
		world.interact_nearest()
	elif mode == "battle" and modal == null:
		match event.keycode:
			KEY_1: _battle_turn("attack")
			KEY_2: _battle_turn("skill")
			KEY_3: _battle_turn("guard")
			KEY_4: _battle_turn("potion")
			KEY_5: _battle_inspect()
			KEY_6: _battle_turn("flee")
			KEY_0: _toggle_auto()
			KEY_ENTER: _battle_menu()

func _box(parent: Node, rect: Rect2, color: Color = INK, border: Color = Color("3e6060")) -> Panel:
	var panel: Panel = preload("res://scenes/ui/dynamic_panel.tscn").instantiate()
	panel.position = rect.position
	panel.size = rect.size
	_style_panel(panel, color, border)
	parent.add_child(panel)
	return panel

func _style_panel(panel: Panel, color: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff7b8") if mode in ["world", "battle"] and color == INK else color
	style.border_color = OriginalUITheme.palette("scene").main if mode in ["world", "battle"] else border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0 if mode in ["world", "battle"] else 4)
	panel.add_theme_stylebox_override("panel", style)

func _label(parent: Node, text_value: String, rect: Rect2, size_value: int = 12, color: Color = PAPER, centered: bool = false) -> Label:
	var label: Label = preload("res://scenes/ui/dynamic_label.tscn").instantiate()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", Color("654518") if mode == "create" or (mode in ["world", "battle"] and color in [PAPER, GOLD, TEAL]) else color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, rect: Rect2, callback: Callable, primary: bool = false) -> Button:
	var button: Button = preload("res://scenes/ui/dynamic_button.tscn").instantiate()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("b69252") if primary else Color("1e3c41")
	style.border_color = GOLD if primary else Color("52766d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color("ceb478") if primary else Color("315858")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate()
	pressed.bg_color = Color("78643e") if primary else Color("102f32")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := style.duplicate()
	disabled.bg_color = Color("15282c")
	disabled.border_color = Color("2a4041")
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", INK if primary else PAPER)
	button.add_theme_color_override("font_hover_color", INK if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_font_size_override("font_size", 12)
	if mode in ["create", "world", "battle"]:
		style.bg_color = Color("b77927")
		style.border_color = Color("75410e")
		style.set_corner_radius_all(0)
		hover.bg_color = Color("d0953f")
		hover.border_color = Color("75410e")
		hover.set_corner_radius_all(0)
		pressed.bg_color = Color("935c20")
		pressed.border_color = Color("75410e")
		pressed.set_corner_radius_all(0)
		button.add_theme_color_override("font_color", Color("fffbd2"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _clear_ui() -> void:
	_ui_epoch += 1
	if is_instance_valid(battle_move_callout): battle_move_callout.clear()
	battle_move_callout = null
	if battle_playback != null: battle_playback.cancel()
	battle_playback = null
	battle_ring = null
	Game.invalidate_load()
	character_selection = null
	announcement_banner.present({})
	battle_transition_epoch += 1
	if battle_resource_request != null: battle_resource_request.cancel()
	battle_resource_request = null
	battle_transition = null
	modal = null
	original_cover = null
	creation = null
	attributes = null
	chrome = null
	action_menu = null
	backpack = null
	minimap = null
	nickname = null
	preview = null
	create_description = null
	ui.theme = null
	for child in ui.get_children():
		ui.remove_child(child)
		child.queue_free()
	if world != null and is_instance_valid(world):
		world.enabled = false
	if world_view != null: world_view.hide()
	queue_redraw()

func _dispose_world() -> void:
	if viewport != null:
		remove_child(viewport)
		viewport.queue_free()
		viewport = null
		world = null
	if world_view != null:
		remove_child(world_view)
		world_view.queue_free()
		world_view = null

func _home() -> void:
	mode = "home"
	_clear_ui()
	_dispose_world()
	original_cover = load("res://scenes/ui/original_cover.tscn").instantiate()
	ui.add_child(original_cover)
	original_cover.chosen.connect(_cover_choice)
	original_cover.exit_requested.connect(_cover_exit)

func _cover_choice(option: String) -> void:
	match option:
		"登陆游戏", "登录游戏":
			if OS.has_feature("web"): _web_entry()
			else: _server_login()
		"退出游戏": _cover_exit()

func _web_entry() -> void:
	var panel := _modal_panel("选择游戏模式")
	_label(panel, "离线存档仅保存在本站浏览器，不会导入线上角色。清除站点数据会删除进度。", Rect2(18, 48, 248, 68), 13)
	_button(panel, "离线单人", Rect2(18, 124, 248, 30), _enter_local_game, true)
	_button(panel, "本站联机", Rect2(18, 160, 248, 30), _server_login)
	_button(panel, "返回", Rect2(18, 196, 248, 30), _close_modal)

func _web_lifecycle(event: String) -> void:
	if event not in ["focus_lost", "suspended"]: return
	if is_instance_valid(world): world.pause_moving()
	# Unload/visibility is not a reliable asynchronous save boundary.
	# No auto-settlement, reward replay or claimed save success here.

func _server_login() -> void:
	_close_modal()
	if original_cover != null: original_cover.active = false
	modal = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	ui.add_child(modal)
	var login: ServerLogin = load("res://scenes/ui/server_login.tscn").instantiate()
	login.name = "ServerLogin"
	modal.add_child(login)
	login.close_requested.connect(_close_modal)
	login.characters_requested.connect(_online_characters, CONNECT_DEFERRED)
	login.registration_requested.connect(_online_creation, CONNECT_DEFERRED)
	login.local_requested.connect(_enter_local_game)

func _enter_local_game() -> void:
	if Game.storage_busy or _closing: return
	OnlineAccount.suspend_network()
	var epoch := _ui_epoch
	var probe := await Game.probe_save()
	if epoch != _ui_epoch or probe.status == PlatformResult.Status.CANCELLED or _closing: return
	if not probe.ok:
		_message("无法确认存档", probe.message)
	elif probe.value:
		var result := await Game.load_game()
		if epoch != _ui_epoch or result.status == PlatformResult.Status.CANCELLED or _closing: return
		if result.ok: _local_character_selection()
		else: _message("无法读取", result.message)
	else: _create()

func _online_characters(_character_id: String = "") -> void:
	mode = "online_select"
	_clear_ui()
	_dispose_world()
	character_selection = preload("res://scenes/ui/character_selection.tscn").instantiate()
	character_selection.online_mode = true
	var flow: OnlineSelectionFlow = character_selection.get_node("Online")
	flow.enter_requested.connect(_enter_selected_online, CONNECT_DEFERRED)
	flow.create_requested.connect(_online_creation, CONNECT_DEFERRED)
	character_selection.back_requested.connect(_return_to_server_login, CONNECT_DEFERRED)
	ui.add_child(character_selection)

func _enter_selected_online(character_id: String) -> void:
	if mode != "online_select" or not OnlineAccount.is_logged_in(): return
	for character in OnlineAccount.characters:
		if character.id == character_id:
			_enter_online_world(character_id)
			return

func _local_character_selection() -> void:
	mode = "local_select"
	_clear_ui()
	_dispose_world()
	character_selection = preload("res://scenes/ui/character_selection.tscn").instantiate()
	ui.add_child(character_selection)
	character_selection.display_characters([Game.player])
	character_selection.set_controls(false, false)
	character_selection.status.text = "请选择角色后进入游戏"
	character_selection.enter_requested.connect(func(_id: String) -> void: _continue())
	character_selection.back_requested.connect(_return_to_server_login)

func _online_creation() -> void:
	mode = "online_create"
	_clear_ui()
	_dispose_world()
	creation = load("res://scenes/ui/character_creation.tscn").instantiate()
	creation.online_mode = true
	var flow: OnlineCreationFlow = creation.get_node("Online")
	flow.enter_requested.connect(_online_characters, CONNECT_DEFERRED)
	flow.close_requested.connect(_return_to_server_login, CONNECT_DEFERRED)
	ui.add_child(creation)
	ui.theme = creation.theme

func _return_to_server_login() -> void:
	_home()
	_server_login()

func _cover_exit() -> void:
	var panel := _modal_panel("退出游戏")
	_label(panel, String(original_cover.original_text.quit), Rect2(18, 56, 248, 90), 14)
	_button(panel, "确定", Rect2(18, 186, 148, 32), _request_exit, true)
	_button(panel, "取消", Rect2(176, 186, 88, 32), _close_modal)

func _enter_online_world(character_id: String) -> void:
	mode = "online_world"
	_clear_ui()
	_dispose_world()
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.name = "OnlineWorld"
	view.character_id = character_id
	ui.add_child(view)
	view.network.announcements.changed.connect(announcement_banner.present)
	view.close_requested.connect(_return_to_server_login)

func _create() -> void:
	mode = "create"
	_clear_ui()
	creation = load("res://scenes/ui/character_creation.tscn").instantiate()
	creation.selected_variant = selected_job * 2 + selected_gender
	creation.selection_changed.connect(_creation_selection)
	creation.create_requested.connect(_start_new)
	ui.add_child(creation)
	ui.theme = creation.theme
	nickname = creation.nickname
	preview = creation.preview
	create_description = creation.description

func _creation_selection(job: int, gender: int) -> void:
	selected_job = job
	selected_gender = gender
	preview = creation.preview
	create_description = creation.description

func _select_job(index: int) -> void:
	if creation != null: creation.select_variant(clampi(index, 0, 2) * 2 + selected_gender)

func _start_new() -> void:
	if Game.storage_busy or _closing: return
	if not Platform.context.text_input.check_submission([nickname]).ok: return
	var name_value := nickname.text.strip_edges()
	if name_value.is_empty():
		_message("请输入昵称", "请先输入昵称。")
		return
	var epoch := _ui_epoch
	var probe := await Game.probe_save()
	if epoch != _ui_epoch or probe.status == PlatformResult.Status.CANCELLED or _closing: return
	if not probe.ok:
		_message("无法确认存档", probe.message)
		return
	if probe.value:
		var panel := _modal_panel("开启新的修行")
		_label(panel, "当前只有一个本地存档槽。\n入山后将覆盖已有角色存档。", Rect2(18, 56, 248, 70), 13)
		_button(panel, "确认入山", Rect2(18, 180, 148, 32), _begin_new.bind(name_value), true)
		_button(panel, "返回", Rect2(176, 180, 88, 32), _close_modal)
	else:
		await _begin_new(name_value)

func _begin_new(name_value: String) -> void:
	if Game.storage_busy or _closing: return
	Game.new_player(name_value, selected_job, selected_school, selected_gender)
	var result := await _save_current()
	if result.status == PlatformResult.Status.CANCELLED or _closing: return
	if not result.ok:
		_message("创建存档失败", result.message + "\n尚未进入地图，请重试。")
		return
	_enter_world()
	_message("山门初见", "蜀山山道妖气渐浓。\n先去石桥旁找清微道人，接取试炼。\n\n点击人物或怪物，会自动走近并交互。\nWASD / 方向键移动，E 键交互。")

func _continue() -> void:
	if Game.storage_busy or _closing: return
	var epoch := _ui_epoch
	var result := await Game.load_game()
	if epoch != _ui_epoch or result.status == PlatformResult.Status.CANCELLED or _closing: return
	if result.ok:
		if int(Game.player.hp) == 0: Game.restore()
		_enter_world()
	else:
		_message("无法读取", result.message if result.code != "NOT_FOUND" else "尚无本地存档。")

func _enter_world() -> void:
	mode = "world"
	_clear_ui()
	_dispose_world()
	viewport = preload("res://scenes/ui/world_viewport.tscn").instantiate()
	add_child(viewport)
	world = ShushanWorld.new()
	viewport.add_child(world)
	world.interaction.connect(_world_interaction)
	world.moved.connect(_refresh_hud)
	world_view = preload("res://scenes/ui/world_image.tscn").instantiate()
	world_view.texture = viewport.get_texture()
	world_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	world_view.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			world.click(event.position)
		elif event is InputEventScreenTouch and event.pressed:
			world.click(event.position)
	)
	add_child(world_view)
	move_child(ui, get_child_count() - 1)
	_world_ui()

func _world_ui() -> void:
	mode = "world"
	_clear_ui()
	world_view.show()
	world.enabled = true
	var screen: GameWorldScreen = preload("res://scenes/ui/game_world_screen.tscn").instantiate()
	ui.add_child(screen)
	chrome = screen.chrome
	screen.action_requested.connect(_scene_action)
	ui.theme = chrome.theme
	var hud: Control = screen.hud
	minimap = hud.get_node("Minimap")
	minimap.world = world
	map_name = hud.get_node("MapName")
	map_name.text = "青云山道" if int(Game.player.zone) == 0 else "古剑遗迹"
	map_coordinates = hud.get_node("MapCoordinates")
	hud_name = hud.get_node("HudName")
	world_identity = hud.get_node("WorldIdentity")
	hud_stats = chrome.hint
	quest_label = chrome.log_label
	_refresh_hud()

func _scene_action(action: String) -> void:
	if Game.storage_busy or _closing: return
	if mode == "battle_loading": return
	match action:
		"menu": _menu()
		"properties":
			if mode == "world": _attributes()
			else: _battle_inspect()
		"quest": _quest()
		"bag": _bag()
		"rest": _rest()
		"map": _open_world_map()
		"mail": _message("邮件", "暂无邮件。")
		"social": _message("社交", "尚未结交好友。")
		"system": _system_menu()
		"shop", "craft", "team", "guild", "trade":
			var titles := {"shop": "商城", "craft": "炼制", "team": "队伍", "guild": "帮会", "trade": "交易"}
			_message(titles[action], titles[action] + "暂未开放。")
		"reward":
			var panel := _modal_panel("奖励", 246, "reward")
			_label(panel, Game.quest_text() + "\n\n完成山林试炼后，向清微道人领取奖励。", Rect2(18, 54, 248, 128), 12)
			_button(panel, "返回", Rect2(18, 192, 248, 32), _close_modal, true)

func _refresh_hud() -> void:
	if mode != "world" or hud_name == null or not is_instance_valid(hud_name): return
	hud_name.text = "%s  Lv.%d  ·  %s%s" % [Game.player.name, int(Game.player.level), Game.SCHOOLS[int(Game.player.school)], Game.JOBS[int(Game.player.job)]]
	var values := Game.stats()
	hud_stats.text = ""
	world_identity.text = "等级 %d\n%s派" % [int(Game.player.level), Game.SCHOOLS[int(Game.player.school)]]
	map_coordinates.text = "%d  %d" % [world.cell.x, world.cell.y]
	quest_label.text = "[系统] " + Game.quest_text() + "\n[系统] 气血 %d/%d  灵力 %d/%d" % [int(Game.player.hp), int(values.hp), int(Game.player.mp), int(values.mp)]
	chrome.update_header(int(Game.player.hp), int(Game.player.mp), 0)

func _world_interaction(kind: String, data: Dictionary) -> void:
	if Game.storage_busy or _closing: return
	if mode == "battle_loading": return
	match kind:
		"npc": _npc()
		"enemy":
			if int(Game.player.quest) == 0:
				_message("尚未领受试炼", "先找清微道人领受试炼，再挑战山中的妖物。")
			else: _encounter_battle(data)
		"portal":
			if int(Game.player.zone) == 0 and int(Game.player.quest) < 3:
				_message("灵门未开", "完成山狼试炼，并向清微道人复命后，方可前往古剑遗迹。")
			else:
				Game.player.zone = 1 - int(Game.player.zone)
				Game.player.cell = [10, 16] if int(Game.player.zone) == 0 else [5, 16]
				var result := await _save_current()
				if result.status == PlatformResult.Status.CANCELLED or _closing: return
				_enter_world()
				if not result.ok: _message("保存失败", result.message + "\n当前位置仍在内存中，请重试保存。")
		"hint": _message("交互", String(data.text))

func _npc() -> void:
	var panel := _modal_panel("清微道人")
	var stage := int(Game.player.quest)
	var text_value := ""
	match stage:
		0: text_value = "小友，山中妖物惊扰行人。\n请击败三只山狼，再回来见我。\n\n试炼奖励：60 铜钱 / 35 修为\n道人可为你免费恢复生命与灵力。"
		1: text_value = "山狼试炼进度：%d / 3\n\n山狼出没于东北、东南与南方山林。\n点击怪物即可自动走近挑战。" % int(Game.player.kills)
		2: text_value = "小友果然身手不凡！\n收下这份谢礼。东侧灵门已经为你开启。\n\n遗迹中赤焰妖王盘踞，请再走一遭。"
		3: text_value = "穿过东侧的蓝色灵门，进入古剑遗迹。\n击败赤焰妖王，便可消除山中妖气。\n\n出发前，先让我为你恢复元气。"
		_: text_value = "妖气已散，山门安宁。\n多谢小友！蜀山初行至此完成。\n\n你可以继续探索，或创建其他职业体验。"
	_label(panel, text_value, Rect2(18, 52, 248, 126), 12)
	if stage == 0:
		_button(panel, "领受试炼", Rect2(18, 186, 148, 32), func() -> void:
			if Game.storage_busy or _closing or int(Game.player.quest) != stage: return
			Game.player.quest = 1
			Game.restore()
			await _save_local_change()
		, true)
	elif stage == 2:
		_button(panel, "领取奖励", Rect2(18, 186, 148, 32), func() -> void:
			if Game.storage_busy or _closing or int(Game.player.quest) != stage: return
			Game.player.quest = 3
			Game.add_rewards(60, 35)
			Game.restore()
			await _save_local_change()
		, true)
	else:
		_button(panel, "恢复元气", Rect2(18, 186, 148, 32), func() -> void:
			if Game.storage_busy or _closing: return
			Game.restore()
			await _save_local_change()
		, true)
	_button(panel, "告辞", Rect2(176, 186, 88, 32), _close_modal)

func _modal_panel(title: String, height: int = 246, page: String = "scene") -> Panel:
	_close_modal()
	if original_cover != null: original_cover.active = false
	if creation != null: creation.active = false
	if world != null and is_instance_valid(world):
		world.pause_moving()
		world.enabled = false
	modal = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	ui.add_child(modal)
	var shade: ColorRect = modal.get_node("Shade")
	shade.color = Color(0.92, 0.88, 0.71, 0.28) if mode in ["world", "battle"] else Color(0.01, 0.02, 0.03, 0.75)
	var panel: Panel = preload("res://scenes/ui/dialog_frame.tscn").instantiate()
	panel.position.y = (480 - height) / 2.0
	panel.size.y = height
	_style_panel(panel, INK, GOLD)
	modal.add_child(panel)
	if page == "reward":
		var colors := OriginalUITheme.palette(page)
		var skin: StyleBoxFlat = panel.get_theme_stylebox("panel")
		skin.border_color = colors.main
		OriginalSceneChrome.panel(panel, Rect2(1, 1, 282, 40), colors.main, colors.edge)
	if mode == "create":
		var skin: StyleBoxFlat = panel.get_theme_stylebox("panel")
		skin.bg_color = Color("fff8b8")
		skin.border_color = Color("81501b")
		skin.set_corner_radius_all(0)
	var title_label: Label = panel.get_node("Title")
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color("fff8c5") if page == "reward" else (Color("654518") if mode in ["create", "world", "battle"] else GOLD))
	panel.move_child(title_label, panel.get_child_count() - 1)
	return panel

func _close_modal() -> void:
	if Game.storage_busy or _closing: return
	if modal != null and is_instance_valid(modal):
		ui.remove_child(modal)
		modal.queue_free()
	modal = null
	backpack = null
	if original_cover != null: original_cover.active = true
	if creation != null: creation.active = true
	if mode == "world" and world != null and is_instance_valid(world): world.enabled = true

func _message(title: String, value: String) -> void:
	var panel := _modal_panel(title)
	_label(panel, value, Rect2(18, 54, 248, 128), 12)
	_button(panel, "知道了", Rect2(18, 192, 248, 32), _close_modal, true)

func _save_feedback() -> void:
	if Game.storage_busy or _closing: return
	world.pause_moving()
	var result := await _save_current()
	if result.status == PlatformResult.Status.CANCELLED or _closing: return
	if result.ok:
		var explanation := "下次将服务地址设为local，进入游戏即可继续。\n\n存档会记录角色、任务、背包及所在位置。"
		if result.value.durability == "browser_sync": explanation = "已同步到浏览器本地存储。\n清理站点数据或浏览器回收存储仍可能导致丢档，不保证永久保存。"
		_message("修行已保存", explanation)
	else:
		_message("保存失败", result.message)

func _rest() -> void:
	var panel := _modal_panel("凝神调息")
	_label(panel, "花费 5 铜钱，恢复全部生命与灵力。\n\n清微道人也可免费为你恢复元气。", Rect2(18, 58, 248, 110), 12)
	var button := _button(panel, "调息 · 5 铜钱", Rect2(18, 184, 148, 32), func() -> void:
		if Game.storage_busy or _closing: return
		Game.player.gold = int(Game.player.gold) - 5
		Game.restore()
		await _save_local_change()
	, true)
	button.disabled = int(Game.player.gold) < 5
	_button(panel, "返回", Rect2(176, 184, 88, 32), _close_modal)

func _bag() -> void:
	_close_modal()
	world.pause_moving()
	world.enabled = false
	modal = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	ui.add_child(modal)
	var shade: ColorRect = modal.get_node("Shade")
	shade.color = Color(0.03, 0.04, 0.02, 0.42)
	backpack = load("res://scenes/ui/inventory.tscn").instantiate()
	modal.add_child(backpack)
	backpack.back_requested.connect(_close_modal)
	backpack.changed.connect(_refresh_hud)

func _open_world_map() -> void:
	if modal is OriginalWorldMap:
		_close_modal()
		return
	if mode != "world": return
	_close_modal()
	world.pause_moving()
	world.enabled = false
	var page: OriginalWorldMap = preload("res://scenes/ui/world_map.tscn").instantiate()
	modal = page
	ui.add_child(page)
	page.back_requested.connect(_close_modal)
	page.present()

func _quest() -> void:
	_message("蜀山初行", Game.quest_text() + "\n\n路线：道人领受试炼 → 三只山狼 →\n道人领取奖励 → 东侧灵门 → 遗迹妖王\n\n点击目标可自动寻路。战斗失败会回山门，\n保留任务进度、铜钱和装备。")

func _menu() -> void:
	if modal is OriginalGameMenu:
		_close_modal()
		return
	_close_modal()
	if is_instance_valid(world):
		world.pause_moving()
		world.enabled = false
	var popup: OriginalGameMenu = load("res://scenes/ui/game_menu.tscn").instantiate()
	modal = popup
	ui.add_child(popup)
	popup.dismissed.connect(_close_modal)
	popup.chosen.connect(func(action: String) -> void:
		_close_modal()
		_scene_action(action)
	)
	popup.open()

func _system_menu() -> void:
	_close_modal()
	if is_instance_valid(world):
		world.pause_moving()
		world.enabled = false
	modal = load("res://scenes/ui/system_menu.tscn").instantiate()
	ui.add_child(modal)
	modal.get_node("Panel/Continue").pressed.connect(_close_modal)
	modal.get_node("Panel/Save").pressed.connect(_save_feedback)
	modal.get_node("Panel/School").pressed.connect(_school)
	modal.get_node("Panel/Rest").pressed.connect(_rest)
	modal.get_node("Panel/Leave").pressed.connect(func() -> void:
		if Game.storage_busy or _closing: return
		var result := await _save_current()
		if result.status == PlatformResult.Status.CANCELLED or _closing: return
		if result.ok: _return_to_server_login()
		else: _message("保存失败", result.message)
	)

func _school() -> void:
	var panel := _modal_panel("角色门派", 226)
	_label(panel, "选择角色门派。\n当前：" + Game.SCHOOLS[int(Game.player.school)] + "派", Rect2(18, 53, 248, 57), 12)
	for i in 3:
		var button := _button(panel, Game.SCHOOLS[i] + "派", Rect2(18 + i * 84, 118, 78, 34), func() -> void:
			if Game.storage_busy or _closing: return
			var previous_school := int(Game.player.school)
			Game.player.school = i
			var result := await _save_current()
			if result.status == PlatformResult.Status.CANCELLED or _closing: return
			if result.ok: _world_ui()
			else:
				Game.player.school = previous_school
				_message("保存失败", result.message)
		)
		var colors := OriginalUITheme.palette("scene")
		for state in ["normal", "hover", "pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = colors.main
			style.border_color = colors.edge
			style.set_border_width_all(1)
			button.add_theme_stylebox_override(state, style)
	_button(panel, "返回", Rect2(18, 172, 248, 30), _close_modal)

func _attributes() -> void:
	world.pause_moving()
	mode = "attributes"
	_clear_ui()
	attributes = load("res://scenes/ui/character_attributes.tscn").instantiate()
	ui.add_child(attributes)
	attributes.back_requested.connect(_return_from_attributes)

func _return_from_attributes() -> void:
	if Game.storage_busy or _closing: return
	if not Platform.context.text_input.check_submission([attributes.signature]).ok: return
	Game.player.signature = attributes.signature.text
	var result := await _save_current()
	if result.status == PlatformResult.Status.CANCELLED or _closing: return
	if not result.ok:
		_message("保存失败", result.message)
		return
	_world_ui()

func _about() -> void:
	var panel := _modal_panel("关于本次重建", 344)
	_label(panel, "原包：《蜀山剑侠Online》320×480版\n原始开发者：博荣无限\n\n美术来自 analysis 中解包恢复的原始图像。\n图块、人物部件、动画组合由静态解析转换。\n\n本版采用 Godot 4.7，支持完全离线游玩。\n地图布局、任务、数值、战斗与存档重新编写。\n原服务端、账号和地图逻辑未恢复。\n\n战斗：1攻击 / 2技能 / 3待机 / 4道具\n5查看 / 6逃跑 / 0自动战斗。", Rect2(18, 54, 248, 236), 11)
	_button(panel, "返回", Rect2(18, 296, 248, 31), _close_modal, true)

func _encounter_current(epoch: int, world_id: int) -> bool:
	return epoch == battle_transition_epoch and mode == "battle_loading" and is_instance_valid(world) and world.get_instance_id() == world_id and is_instance_valid(battle_transition)

func _encounter_failed(explanation: String = "本地战斗资源未能准备完成，请检查游戏文件后重试。") -> void:
	battle_transition_epoch += 1
	if battle_resource_request != null: battle_resource_request.cancel()
	battle_resource_request = null
	if is_instance_valid(battle_transition):
		ui.remove_child(battle_transition)
		battle_transition.queue_free()
	battle_transition = null
	mode = "world"
	chrome.hint.show()
	_message("无法进入战斗", explanation + "\n当前角色资源没有扣除。")

func _encounter_battle(enemy: Dictionary) -> void:
	if mode != "world" or modal != null or not is_instance_valid(world): return
	world.pause_moving()
	world.enabled = false
	mode = "battle_loading"
	chrome.hint.hide()
	battle_transition_epoch += 1
	var epoch := battle_transition_epoch
	var world_id := world.get_instance_id()
	world.camera.force_update_scroll()
	var point: Vector2 = world.hero.get_global_transform_with_canvas().origin + world_view.position
	battle_transition = load("res://scenes/ui/battle_encounter_transition.tscn").instantiate()
	ui.add_child(battle_transition)
	battle_transition.configure(String(enemy.get("name", "妖物")), point)
	# A short readable warning, followed by actual texture/cache work.
	await get_tree().create_timer(0.20).timeout
	if not _encounter_current(epoch, world_id): return
	var keys: Array[String] = [Game.actor_key(), String(enemy.get("art", "")), "effect/flash", ["effect/t71", "effect/t36", "effect/t47"][int(Game.player.job)]]
	var paths: Array[String] = ["res://assets/tiles/original_tiles.png"]
	for key in keys:
		var info := OriginalArt.actor_info(key)
		if info.is_empty():
			_encounter_failed()
			return
		var path := String(info.texture)
		if not paths.has(path): paths.append(path)
	var request := Platform.context.resource_loader.prepare(PackedStringArray(paths), battle_transition, epoch)
	battle_resource_request = request
	while not request.is_finished():
		battle_transition.set_progress(0.75 * request.progress, "准备战斗图像与场景")
		await get_tree().process_frame
		if not _encounter_current(epoch, world_id):
			request.cancel()
			return
	if not _encounter_current(epoch, world_id) or request.generation != epoch: return
	if not request.result.ok:
		_encounter_failed(request.result.message)
		return
	for index in keys.size():
		# SpriteFrames preparation is bounded to these four battle actors/effects.
		var prepared := OriginalArt.actor(keys[index])
		prepared.free()
		battle_transition.set_progress(0.75 + 0.20 * float(index + 1) / keys.size(), "准备角色动作与招式")
		await get_tree().process_frame
		if not _encounter_current(epoch, world_id): return
	battle_transition.set_progress(1.0, "准备就绪")
	await get_tree().create_timer(0.16).timeout
	if not _encounter_current(epoch, world_id): return
	_start_battle(enemy)

func _start_battle(enemy: Dictionary) -> void:
	world.pause_moving()
	mode = "battle"
	_clear_ui()
	battle = ShushanBattle.new(enemy)
	battle_stage = "select"
	battle_committed = false
	battle_auto = false
	auto_timer = 0.0
	battle_buttons.clear()
	battle_selected_enemy = false
	field_kind = String(enemy.get("terrain", "ruins" if int(Game.player.zone) == 1 else ("wilderness" if enemy.kind == "wolf" else "courtyard")))
	_battle_scenery()
	battle_enemy = OriginalArt.battle_actor(String(enemy.art))
	battle_enemy.position = Vector2(58, 282)
	battle_enemy.scale = Vector2(-1.1, 1.1)
	ui.add_child(battle_enemy)
	battle_hero = OriginalArt.battle_actor(Game.actor_key())
	battle_hero.position = Vector2(256, 282)
	battle_hero.scale = Vector2(1.2, 1.2)
	ui.add_child(battle_hero)
	battle_ring = preload("res://scenes/actors/player_ring.tscn").instantiate()
	battle_hero.add_child(battle_ring)
	chrome = load("res://scenes/ui/battle_chrome.tscn").instantiate()
	ui.add_child(chrome)
	chrome.action_requested.connect(_scene_action)
	ui.theme = chrome.theme
	battle_log = chrome.log_label
	battle_round = chrome.round_label
	battle_status = chrome.hint
	battle_log.text = "[系统] %s进入战斗。\n[系统] 点击人物展开战斗指令。" % enemy.name
	var hud: Control = preload("res://scenes/ui/battle_hud.tscn").instantiate()
	ui.add_child(hud)
	battle_hero_hp = hud.get_node("BattleHeroHp")
	battle_hero_mp = hud.get_node("BattleHeroMp")
	battle_enemy_hp = hud.get_node("BattleEnemyHp")
	battle_enemy_status = hud.get_node("BattleEnemyStatus")
	battle_hero_status = hud.get_node("BattleHeroStatus")
	hud.get_node("Level").text = str(int(Game.player.level))
	hud.get_node("HeroHit").pressed.connect(func() -> void: battle_selected_enemy = false; _battle_menu())
	hud.get_node("EnemyHit").pressed.connect(func() -> void: battle_selected_enemy = true; _battle_menu())
	auto_button = hud.get_node("AutoButton")
	auto_button.pressed.connect(_toggle_auto)
	effects_layer = hud.get_node("EffectsLayer")
	action_menu = hud.get_node("ActionMenu")
	var commands := ["attack", "skill", "guard", "potion", "inspect", "flee"]
	for i in commands.size():
		var button: Button = action_menu.get_node("BattleButtons%d" % i)
		if commands[i] == "inspect": button.pressed.connect(_battle_inspect)
		else: button.pressed.connect(_battle_turn.bind(commands[i]))
		battle_buttons.append(button)
	battle_move_callout = load("res://scenes/ui/battle_move_callout.tscn").instantiate()
	ui.add_child(battle_move_callout)
	_battle_menu()
	action_menu.hide()
	_refresh_battle()

func _battle_scenery() -> void:
	battle_field = OriginalBattleField.new()
	battle_field.kind = field_kind
	battle_field.position = Vector2(0, 28)
	ui.add_child(battle_field)

func _battle_menu() -> void:
	if battle.phase != "select" or modal != null: return
	if action_menu != null and is_instance_valid(action_menu):
		action_menu.visible = not action_menu.visible
		_refresh_battle()

func _battle_inspect() -> void:
	if battle.phase != "select": return
	if action_menu != null: action_menu.hide()
	_close_modal()
	modal = preload("res://scenes/ui/modal_overlay.tscn").instantiate()
	modal.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed: _close_modal()
	)
	ui.add_child(modal)
	modal.get_node("Shade").hide()
	var panel: Panel = preload("res://scenes/ui/battle_inspect.tscn").instantiate()
	modal.add_child(panel)
	var enemy := battle_selected_enemy
	panel.get_node("NameValue").text = String(battle.enemy.name) if enemy else String(Game.player.name)
	var values := Game.stats()
	var hp := battle.enemy_hp if enemy else battle.hp
	var max_hp := int(battle.enemy.hp) if enemy else int(values.hp)
	panel.get_node("Hp").text = "气血：%d/%d" % [hp, max_hp]
	panel.get_node("Secondary").text = "攻击：%d" % int(battle.enemy.attack) if enemy else "灵力：%d/%d" % [battle.mp, int(values.mp)]
	panel.get_node("Tertiary").text = "防御：%d" % int(battle.enemy.defense) if enemy else "门派：" + Game.SCHOOLS[int(Game.player.school)] + "派"

func _battle_turn(command: String) -> void:
	if mode != "battle" or battle.phase != "select" or modal != null: return
	var active_battle := battle
	var epoch := _ui_epoch
	var start := battle.begin_action(command)
	_battle_lines(start.lines)
	if not start.ok:
		_refresh_battle()
		return
	if action_menu != null: action_menu.hide()
	battle_stage = "player"
	var animation: StringName = &"cast" if command == "skill" and battle_hero.sprite_frames.has_animation("cast") else &"attack"
	battle_move_callout.present_for(ShushanBattle.action_name(command, int(Game.player.job)), battle_hero, _battle_action_duration(battle_hero, animation) + 0.15 if command in ["attack", "skill"] else 0.75)
	_refresh_battle()
	await get_tree().create_timer(0.15).timeout
	if epoch != _ui_epoch or mode != "battle" or battle != active_battle: return
	var player_motion: BattleActionPlayback
	if command in ["attack", "skill"]:
		player_motion = BattleActionPlayback.new()
		battle_playback = player_motion
		player_motion.start(battle_hero, OriginalArt.actor_info(Game.actor_key()), battle_enemy.global_position, animation, battle_enemy)
		_refresh_battle()
		await player_motion.impact
		if epoch != _ui_epoch or player_motion.cancelled or mode != "battle" or battle != active_battle: return
	var result := battle.resolve_player()
	_battle_lines(result.lines)
	if command in ["attack", "skill"]:
		if int(result.damage) > 0 and battle_enemy.sprite_frames.has_animation("hurt"):
			battle_enemy.play("hurt")
		var effect_key: String = "effect/flash" if command == "attack" else ["effect/t71", "effect/t36", "effect/t47"][int(Game.player.job)]
		var effect := OriginalArt.effect(effect_key)
		effect.position = battle_enemy.position - effects_layer.position
		effects_layer.add_child(effect)
		_damage_number(int(result.damage), battle_enemy.position + Vector2(-3, -53))
	_refresh_battle()
	if player_motion != null:
		await player_motion.completed
		if player_motion.cancelled: return
	else:
		await get_tree().create_timer(0.6).timeout
	if epoch != _ui_epoch or mode != "battle" or battle != active_battle: return
	battle_playback = null
	battle_move_callout.clear()
	if battle.phase == "enemy":
		battle_stage = "enemy"
		var enemy_motion := BattleActionPlayback.new()
		battle_playback = enemy_motion
		enemy_motion.start(battle_enemy, OriginalArt.actor_info(battle.enemy.art), battle_hero.global_position, &"attack", battle_hero)
		_refresh_battle()
		await enemy_motion.impact
		if epoch != _ui_epoch or enemy_motion.cancelled or mode != "battle" or battle != active_battle: return
		var response := battle.resolve_enemy()
		_battle_lines(response.lines)
		if int(response.incoming) > 0 and battle_hero.sprite_frames.has_animation("hurt"): battle_hero.play("hurt")
		_damage_number(int(response.incoming), battle_hero.position + Vector2(-10, -53))
		if int(response.reflected) > 0:
			_damage_number(int(response.reflected), battle_enemy.position + Vector2(-3, -53))
		_refresh_battle()
		await enemy_motion.completed
		if epoch != _ui_epoch or enemy_motion.cancelled or mode != "battle" or battle != active_battle: return
		battle_playback = null
	battle_stage = "settlement"
	_refresh_battle()
	await get_tree().create_timer(0.35).timeout
	if epoch != _ui_epoch or mode != "battle" or battle != active_battle: return
	_battle_lines(battle.finish_round().lines)
	battle_stage = battle.phase
	auto_timer = 0.0
	_refresh_battle()
	if battle.finished: _battle_result()

func _battle_action_duration(actor: AnimatedSprite2D, animation: StringName = &"attack") -> float:
	var frames := actor.sprite_frames
	var duration := 0.0
	for i in frames.get_frame_count(animation):
		duration += frames.get_frame_duration(animation, i) / frames.get_animation_speed(animation)
	return maxf(0.6, duration)

func _battle_lines(lines: Array) -> void:
	var all_lines := battle_log.text.split("\n")
	for line in lines: all_lines.append("[系统] " + String(line))
	while all_lines.size() > 3: all_lines.remove_at(0)
	battle_log.text = "\n".join(all_lines)

func _damage_number(damage: int, point: Vector2) -> void:
	var label := _label(ui, "-%d" % damage, Rect2(point, Vector2(74, 23)), 16, Color("e42712"))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color("39180b"))
	var tween := create_tween()
	tween.tween_property(label, "position:y", point.y - 17, 0.55)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.55)
	tween.tween_callback(label.queue_free)

func _toggle_auto() -> void:
	if battle.finished or modal != null: return
	battle_auto = not battle_auto
	auto_timer = 0.0
	if action_menu != null: action_menu.hide()
	_refresh_battle()

func _refresh_battle() -> void:
	if is_instance_valid(battle_move_callout): battle_move_callout.update_anchor()
	var values := Game.stats()
	chrome.update_header(battle.hp, battle.mp, battle.round_number)
	var stages := {"select": "请选择本回合指令", "player": "我方行动", "enemy": "敌方行动", "settlement": "回合结算", "finished": "战斗结束"}
	battle_status.text = String(stages[battle_stage]) if battle_stage == "select" else "第 %d 回合 · %s" % [battle.round_number, stages[battle_stage]]
	auto_button.text = "0键手动战斗" if battle_auto else "0键自动战斗"
	battle_hero_status.text = "行动" if battle_stage == "player" else ("就绪" if battle_stage == "select" else "等待")
	battle_enemy_status.text = "行动" if battle_stage == "enemy" else ("就绪" if battle_stage == "select" else "等待")
	battle_hero_hp.max_value = values.hp
	battle_hero_hp.value = battle.hp
	battle_hero_mp.max_value = values.mp
	battle_hero_mp.value = battle.mp
	battle_enemy_hp.max_value = int(battle.enemy.hp)
	battle_enemy_hp.value = battle.enemy_hp
	var moving_hero := battle_playback != null and battle_playback.active and battle_playback.actor == battle_hero and battle_playback.action == &"attack"
	var moving_enemy := battle_playback != null and battle_playback.active and battle_playback.actor == battle_enemy
	battle_hero_hp.visible = not moving_hero
	battle_hero_mp.visible = not moving_hero
	battle_hero_status.visible = not moving_hero
	if is_instance_valid(battle_ring): battle_ring.visible = not moving_hero
	battle_enemy_hp.visible = not moving_enemy
	battle_enemy_status.visible = not moving_enemy
	if battle_buttons.size() == 6:
		for button in battle_buttons: button.disabled = battle.phase != "select"
		battle_buttons[1].disabled = battle.phase != "select" or battle.mp < 9
		battle_buttons[3].disabled = battle.phase != "select" or battle.potions < 1 or battle.hp >= int(values.hp)

func _battle_result() -> void:
	if battle_committed: return
	battle_committed = true
	battle_auto = false
	battle_status.text = "战斗结束"
	for button in battle_buttons: button.disabled = true
	var epoch := _ui_epoch
	var current := battle
	var leveled := await battle.commit()
	if epoch != _ui_epoch or current != battle or _closing: return
	var title := "战 斗 胜 利" if battle.victory else ("撤离山林" if battle.escaped else "重整旗鼓")
	var description := "获得 %d 铜钱、%d 修为。" % [int(battle.enemy.gold), int(battle.enemy.xp)] if battle.victory else ("未获得奖励，当前生命与灵力已保留。" if battle.escaped else "道人送你回到了山门，元气已经恢复。")
	if leveled: description += "\n境界提升！生命与灵力已恢复。"
	if int(Game.player.quest) == 4: description += "\n\n妖王伏诛，蜀山初行已完成！"
	description += "\n\n" + Game.quest_text()
	if battle.save_result != null and not battle.save_result.ok: description += "\n保存未确认：" + battle.save_result.message
	var panel := _modal_panel(title)
	_label(panel, description, Rect2(18, 56, 248, 126), 12)
	_button(panel, "返回山道", Rect2(18, 192, 248, 32), _enter_world, true)

func _request_exit() -> void:
	if Game.storage_busy: return
	var result := Platform.context.system_actions.request_exit() if Platform.is_available() else PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "PLATFORM_NOT_READY", "平台尚未就绪，暂时无法处理退出请求。")
	if not result.ok:
		_closing = false
		_message("无法退出", result.message)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_close_requested()

func _close_requested() -> void:
	if _closing: return
	_closing = true
	await Game.wait_for_storage()
	if not is_inside_tree(): return
	if mode != "online_world" and not Game.player.is_empty():
		if mode == "battle" and battle != null:
			if battle.finished and battle.phase == "settlement":
				battle.finish_round()
				await battle.commit()
			elif not battle.finished:
				Game.player.hp = battle.hp
				Game.player.mp = battle.mp
				Game.player.potions = battle.potions
		var result := await _save_current()
		if result.status == PlatformResult.Status.CANCELLED:
			_closing = false
			return
		if not result.ok:
			_closing = false
			_message("保存失败，尚未退出", result.message)
			return
	_request_exit()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 480), INK)
	if mode == "create":
		draw_circle(Vector2(260, 103), 37, Color("223b3d"))
		draw_polygon(PackedVector2Array([Vector2(0, 238), Vector2(53, 166), Vector2(98, 224), Vector2(161, 149), Vector2(227, 226), Vector2(280, 181), Vector2(320, 227), Vector2(320, 480), Vector2(0, 480)]), PackedColorArray([Color("183239")]))
		draw_polygon(PackedVector2Array([Vector2(0, 319), Vector2(70, 229), Vector2(146, 296), Vector2(242, 217), Vector2(320, 297), Vector2(320, 480), Vector2(0, 480)]), PackedColorArray([Color("1e403f")]))
		for i in 18:
			draw_circle(Vector2((i * 73 + 11) % 320, (i * 43 + 19) % 224), 0.8, Color(0.8, 0.83, 0.61, 0.4))
