class_name OnlineWorldView
extends Control
## Shared game interface backed by online state; never installs Game.player.
signal close_requested
signal resident_selected(id: String)
var character_id := ""
@onready var network: OnlineWorldClient = $Network
@onready var viewport: SubViewport = $Viewport
@onready var scene: Node2D = $Viewport/Scene
@onready var actor_layer: Node2D = $Viewport/Scene/Actors
@onready var camera: Camera2D = $Viewport/Scene/Camera
@onready var image: TextureRect = $Image
@onready var screen: GameWorldScreen = $Screen
@onready var status: Label = $Screen/Chrome/MessagePanel/LogLabel
@onready var count_label: Label = $Screen/CountLabel
var actors: Dictionary = {}
var residents: Dictionary = {}
var map_data: Dictionary
var _motion_grid := AStarGrid2D.new()
var _key_timer := 0.0
var _was_keyboard := false
@onready var chat_panel: Panel = $Screen/Chat
@onready var chat_log: RichTextLabel = $Screen/Chat/ChatLog
@onready var chat_input: LineEdit = $Screen/Chat/ChatInput
@onready var chat_send: Button = $Screen/Chat/ChatSend
@onready var chat_status: Label = $Screen/Chrome/Hint
@onready var chat_button: Button = $Screen/Chrome/Toolbar/Social
@onready var emote_button: Button = $Screen/Chat/ChatEmotes
@onready var emote_picker: ChatEmotePicker = $Screen/Chat/EmotePicker
@onready var expanded_chat: ExpandedChatPanel = $Screen/ExpandedChat
@onready var menu: OriginalGameMenu = $GameMenu
@onready var details: Control = $Menu
@onready var attributes: OriginalCharacterAttributes = $Attributes
var _character: Dictionary = {}
var _system_text := "正在连接共享地图……"
var _rendered_chat := ""
@onready var encounter: OnlineEncounter = $Encounter
@onready var battle_view: OnlineBattleView = $Battle
var _approach: Dictionary = {}
var _pve_log := ""
var _closed_battle := ""

func _ready() -> void:
	map_data = JSON.parse_string(FileAccess.get_file_as_string(OnlineWorldClient.MAP_PATH))
	_build_map()
	image.texture = viewport.get_texture()
	image.gui_input.connect(_map_input)
	for character in OnlineAccount.characters:
		if character.id == character_id: _character = character.duplicate(true)
	if not _character.is_empty(): screen.chrome.display_character(_character)
	screen.action_requested.connect(_scene_action)
	screen.hud.get_node("MapName").text = "青云山道"
	screen.hud.get_node("Minimap").set_shared_world(map_data, {}, character_id)
	menu.chosen.connect(_scene_action)
	attributes.back_requested.connect(_close_attributes)
	attributes.allocation_requested.connect(_allocate_attributes)
	$Menu/Panel/Continue.pressed.connect(func() -> void: details.hide())
	$Menu/Panel/Leave.pressed.connect(_leave_world)
	$Menu/Panel/Chat.pressed.connect(_focus_chat)
	$Screen/Chat/Expand.pressed.connect(_open_expanded_chat)
	expanded_chat.dismissed.connect(_expanded_chat_dismissed)
	expanded_chat.emotes_requested.connect(_toggle_emotes)
	expanded_chat.emote_chosen.connect(_insert_emote)
	expanded_chat.focus_requested.connect(func() -> void: chat_input.grab_focus())
	expanded_chat.add_system(_system_text)
	chat_send.pressed.connect(_send_chat)
	emote_button.pressed.connect(_toggle_emotes)
	emote_picker.chosen.connect(_insert_emote)
	emote_picker.dismissed.connect(func() -> void: chat_input.grab_focus())
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
	chat_input.focus_entered.connect(func() -> void:
		if network.world_ready: network.stop_moving()
		_was_keyboard = false
		_cancel_approach()
	)
	chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if expanded_chat.visible and expanded_chat.picker.visible: expanded_chat.close_emotes()
			elif emote_picker.visible: emote_picker.hide()
			elif expanded_chat.visible: expanded_chat.dismiss()
			else: chat_input.release_focus()
			chat_input.accept_event()
	)
	resident_selected.connect(_select_resident)
	encounter.action_requested.connect(_resident_action)
	encounter.dismissed.connect(_cancel_approach)
	battle_view.settings_requested.connect(func() -> void: _scene_action("system"))
	battle_view.action_requested.connect(func(action: String) -> void: network.pve.submit(action))
	battle_view.dismissed.connect(func() -> void:
		_closed_battle = battle_view.battle_id
		screen.hud.show()
		count_label.show()
		screen.chrome.round_label.text = "常规模式"
		_set_battle_layout(false)
	)
	network.pve.changed.connect(_pve_changed)
	network.pve.message.connect(func(text: String) -> void:
		_pve_log = text
		_system_text = text
		expanded_chat.add_system(text)
		_chat_changed()
		if network.pve.last_code.is_empty(): encounter.hide()
	)
	network.changed.connect(_snapshot)
	network.population.changed.connect(_population)
	network.status_changed.connect(_status_changed)
	network.chat.changed.connect(_chat_changed)
	network.chat.status_changed.connect(func(text_value: String) -> void:
		chat_status.text = text_value
		expanded_chat.set_status(text_value)
	)
	network.chat.confirmed.connect(func() -> void: chat_input.clear())
	chat_status.text = "公共频道 · 最多120字"
	network.start(character_id)

func _leave_world() -> void:
	network.leave()
	close_requested.emit()

func _scene_action(action: String) -> void:
	_close_attributes()
	if expanded_chat.visible: expanded_chat.dismiss()
	_cancel_approach()
	encounter.hide()
	if action == "menu":
		details.hide()
		emote_picker.hide()
		chat_input.release_focus()
		if network.world_ready: network.stop_moving()
		_was_keyboard = false
		if menu.visible: menu.dismiss()
		else: menu.open()
		return
	menu.hide()
	if action == "social":
		_toggle_chat()
		return
	if network.world_ready: network.stop_moving()
	emote_picker.hide()
	chat_input.release_focus()
	_was_keyboard = false
	if action == "properties":
		_open_attributes()
		return
	var titles := {"system": "系统", "properties": "人物属性", "quest": "任务", "bag": "背包", "map": "地图", "mail": "邮件", "reward": "奖励", "shop": "商城", "craft": "炼制", "team": "队伍", "guild": "帮会", "trade": "交易"}
	$Menu/Panel/Title.text = titles.get(action, "提示")
	var body := "同图%d人 · 点击地图移动 / WASD\n公共消息在底部直接发送。\n线上进度由服务器保存。" % actors.size()
	if action == "map": body = "青云山道 · 同图%d人\n当前位置：%s\n小地图中的蓝点代表其他玩家。" % [actors.size(), screen.hud.get_node("MapCoordinates").text]
	elif action == "quest": body = network.pve.quest_text()
	elif action == "bag" and not network.pve.state.is_empty(): body = "回春散 ×%d\n战斗中可恢复45点生命。\n铜钱：%d" % [int(network.pve.state.potions), int(_character.get("gold", 0))]
	elif action in ["bag", "reward", "shop", "craft", "team", "guild", "trade"]: body = "线上%s尚未开放。\n可在当前地图移动，与同图玩家聊天。" % titles[action]
	elif action == "mail": body = "暂无邮件。"
	$Menu/Panel/Body.text = body
	details.show()

func _status_changed(text_value: String) -> void:
	status.text = text_value
	_system_text = text_value
	expanded_chat.add_system(text_value)
	if not network.world_ready:
		for actor in actors.values(): actor.sprite.play("idle")
	_chat_changed()

func _build_map() -> void:
	_motion_grid.region = Rect2i(0, 0, 32, 32)
	_motion_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_motion_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_motion_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_motion_grid.update()
	for index in map_data.blocked.size(): _motion_grid.set_point_solid(Vector2i(index % 32, index / 32), map_data.blocked[index])
	var terrain: TileMapLayer = $Viewport/Scene/Terrain
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles/original_tiles.png")
	atlas.texture_region_size = Vector2i(16, 16)
	for index in 756: atlas.create_tile(Vector2i(index % 32, index / 32))
	tiles.add_source(atlas)
	terrain.tile_set = tiles
	for index in map_data.tiles.size():
		var tile := int(map_data.tiles[index])
		terrain.set_cell(Vector2i(index % 32, index / 32), 0, Vector2i(tile % 32, tile / 32))
	for prop in map_data.scenery:
		var actor := OriginalArt.actor(prop.art)
		actor.position = Vector2(prop.x, prop.y)
		actor_layer.add_child(actor)

func _population(values: Dictionary) -> void:
	var visible_values := values.duplicate()
	for id in network.pve.state.get("progress", {}).get("defeated", []): visible_values.erase(id)
	for id in residents.keys():
		if not visible_values.has(id):
			residents[id].queue_free()
			residents.erase(id)
	for id in visible_values:
		if not residents.has(id):
			var resident: OnlineResident = preload("res://scenes/actors/online_resident.tscn").instantiate()
			actor_layer.add_child(resident)
			residents[id] = resident
		residents[id].receive(visible_values[id], _motion_grid)
	screen.hud.get_node("Minimap").set_shared_population(visible_values)

func _snapshot(values: Dictionary) -> void:
	for id in actors.keys():
		if not values.has(id):
			actors[id].root.queue_free()
			actors.erase(id)
	for id in values:
		var entity: Dictionary = values[id]
		var point := Vector2(entity.cell[0] * 16 + 8, entity.cell[1] * 16 + 8)
		if entity.next_cell != null:
			point = point.lerp(Vector2(entity.next_cell[0] * 16 + 8, entity.next_cell[1] * 16 + 8), float(entity.segment_progress) / 1000.0)
		if not actors.has(id):
			var root := Node2D.new()
			root.position = point
			actor_layer.add_child(root)
			var key: String = (["mzs", "mck", "mfs"] if int(entity.gender) == 0 else ["wzs", "wck", "wfs"])[int(entity.job)]
			var sprite := OriginalArt.actor("hero/" + key)
			root.add_child(sprite)
			var label := OriginalSceneChrome.label(root, entity.display_name, Rect2(-65, -72, 130, 18), 11, Color("fff0a5") if id == character_id else Color("9ef6ff"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_constant_override("outline_size", 1)
			label.add_theme_color_override("font_outline_color", Color("1e343b"))
			actors[id] = {"root": root, "sprite": sprite, "target": point, "distance": 0.0, "motion": OnlineActorMotion.new()}
		actors[id].target = point
		actors[id].motion.receive(entity, _motion_grid)
		actors[id].root.position = actors[id].motion.position
	count_label.text = "同图%d人" % actors.size()
	screen.hud.get_node("Minimap").set_shared_world(map_data, values, character_id)
	if values.has(character_id):
		var own: Dictionary = values[character_id]
		screen.hud.get_node("MapCoordinates").text = "%d  %d" % [int(own.cell[0]), int(own.cell[1])]
		screen.hud.get_node("WorldIdentity").text = "等级 %d\n%s派" % [int(_character.get("level", 1)), ["峨眉", "花涧", "昆仑"][int(_character.get("school", 0))]]
	if _pve_log.is_empty(): _system_text = "同图%d人 · 点击移动 / WASD" % actors.size()
	status.text = _system_text
	_chat_changed()

func _toggle_chat() -> void:
	menu.hide()
	details.hide()
	emote_picker.hide()
	if chat_input.has_focus(): chat_input.release_focus()
	else: _focus_chat()

func _focus_chat() -> void:
	expanded_chat.close_emotes()
	menu.hide()
	details.hide()
	emote_picker.hide()
	chat_input.grab_focus()

func _toggle_emotes() -> void:
	if not _can_insert_emote(): return
	menu.hide()
	details.hide()
	chat_input.grab_focus()
	if network.world_ready: network.stop_moving()
	_was_keyboard = false
	if expanded_chat.visible: expanded_chat.toggle_emotes()
	else: emote_picker.visible = not emote_picker.visible

func _insert_emote(token: String) -> void:
	if not _can_insert_emote() or not chat_input.editable or ChatEmotePicker.CATALOG.texture_for(token) == null: return
	var start := chat_input.get_selection_from_column() if chat_input.has_selection() else chat_input.caret_column
	var end := chat_input.get_selection_to_column() if chat_input.has_selection() else start
	var draft := chat_input.text.left(start) + token + chat_input.text.substr(end)
	if draft.length() > 120 or draft.to_utf8_buffer().size() > 480:
		chat_status.text = "消息最多120字，请删减后再添加表情。"
		expanded_chat.set_status(chat_status.text)
		return
	chat_input.text = draft
	expanded_chat.close_emotes()
	chat_input.deselect()
	chat_input.caret_column = start + token.length()
	emote_picker.hide()
	chat_input.grab_focus()

func _can_insert_emote() -> bool:
	return network.world_ready and network.chat.connected and network.chat.pending.is_empty()

func _send_chat() -> void:
	emote_picker.hide()
	expanded_chat.close_emotes()
	network.chat.submit(chat_input.text)
	_update_chat_controls()

func _chat_changed() -> void:
	expanded_chat.sync_messages(network.chat.messages)
	var lines := PackedStringArray()
	if not _pve_log.is_empty() or network.chat.messages.is_empty() or not network.world_ready: lines.append("[系统] " + _system_text)
	for message in network.chat.messages: lines.append("[公共] %s：%s" % [message.display_name, message.text])
	var text_value := "\n".join(lines)
	if text_value != _rendered_chat:
		_rendered_chat = text_value
		chat_log.clear()
		if not _pve_log.is_empty() or network.chat.messages.is_empty() or not network.world_ready:
			chat_log.add_text("[系统] " + _system_text)
			if not network.chat.messages.is_empty(): chat_log.add_text("\n")
		for index in network.chat.messages.size():
			if index > 0: chat_log.add_text("\n")
			var message: Dictionary = network.chat.messages[index]
			chat_log.add_text("[公共] %s：" % message.display_name)
			ChatEmotePicker.CATALOG.append_body(chat_log, message.text)
	chat_button.tooltip_text = "公共聊天 · %d条消息" % network.chat.messages.size()

func _update_chat_controls() -> void:
	if network != null:
		chat_send.disabled = not network.world_ready or not network.chat.connected or not network.chat.pending.is_empty()
		chat_input.editable = network.chat.pending.is_empty()
		emote_button.disabled = chat_send.disabled
		expanded_chat.set_emotes_enabled(not emote_button.disabled)
		if emote_button.disabled: emote_picker.hide()

func _process(delta: float) -> void:
	_update_chat_controls()
	_update_allocation_controls()
	if network == null or not network.world_ready: return
	for resident in residents.values(): resident.advance(delta)
	for id in actors:
		var actor: Dictionary = actors[id]
		var old: Vector2 = actor.root.position
		var motion: OnlineActorMotion = actor.motion
		motion.advance(delta)
		actor.root.position = motion.position
		var distance := motion.travelled
		if distance > 0.001:
			actor.distance += distance
			if absf(actor.root.position.x - old.x) > 0.001: actor.sprite.scale.x = 1.0 if actor.root.position.x < old.x else -1.0
			actor.sprite.animation = "walk"
			actor.sprite.pause()
			var phase: float = actor.distance / 32.0 * actor.sprite.sprite_frames.get_frame_count("walk")
			actor.sprite.set_frame_and_progress(int(phase) % actor.sprite.sprite_frames.get_frame_count("walk"), fposmod(phase, 1.0))
		elif motion.has_motion():
			actor.sprite.animation = "walk"
			actor.sprite.pause()
		elif actor.sprite.animation != "idle" or not actor.sprite.is_playing():
			actor.distance = 0.0
			actor.sprite.play("idle")
	if actors.has(character_id): camera.position = actors[character_id].root.position
	_advance_approach()
	if chat_input.has_focus() or menu.visible or details.visible or emote_picker.visible or encounter.visible or battle_view.visible or expanded_chat.visible or attributes.visible or network.pve.pending():
		_was_keyboard = false
		return
	_key_timer -= delta
	var direction := Vector2i(int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if direction.x != 0: direction.y = 0
	if direction != Vector2i.ZERO and _key_timer <= 0 and network.entities.has(character_id):
		_key_timer = 0.15
		var own: Dictionary = network.entities[character_id]
		var cell: Array = own.next_cell if own.next_cell != null else own.cell
		var destination := Vector2i(cell[0], cell[1]) + direction
		if _motion_grid.region.has_point(destination) and not _motion_grid.is_point_solid(destination): network.move_to(destination)
		else: network.stop_moving()
		_was_keyboard = true
	elif direction == Vector2i.ZERO and _was_keyboard:
		network.stop_moving()
		_was_keyboard = false

func _map_input(event: InputEvent) -> void:
	if not network.world_ready or menu.visible or details.visible or encounter.visible or battle_view.visible or expanded_chat.visible or attributes.visible or network.pve.pending(): return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: point = event.position
	elif event is InputEventScreenTouch and event.pressed: point = event.position
	else: return
	if emote_picker.visible:
		emote_picker.hide()
		return
	chat_input.release_focus()
	_was_keyboard = false
	var world_point := camera.get_screen_center_position() + point - Vector2(viewport.size) / 2.0
	for id in residents:
		if residents[id].hit(world_point):
			resident_selected.emit(id)
			return
	_cancel_approach()
	var destination := Vector2i(floori(world_point.x / 16.0), floori(world_point.y / 16.0))
	if _motion_grid.region.has_point(destination) and not _motion_grid.is_point_solid(destination): network.move_to(destination)
	else:
		network.stop_moving()
		chat_status.text = "目标不可达，已停止原路线。"

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if attributes.visible:
		if event.keycode == KEY_ESCAPE:
			_close_attributes()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if expanded_chat.visible:
			if expanded_chat.picker.visible: expanded_chat.close_emotes()
			else: expanded_chat.dismiss()
			get_viewport().set_input_as_handled()
			return
		if battle_view.visible: return
		if encounter.visible:
			encounter.hide()
			_cancel_approach()
		elif emote_picker.visible: emote_picker.hide()
		elif menu.visible: menu.dismiss()
		elif details.visible: details.hide()
		elif chat_input.has_focus(): chat_input.release_focus()
		else: _scene_action("menu")
	elif event.keycode == KEY_C and not expanded_chat.visible and not battle_view.visible and not chat_input.has_focus(): _scene_action("properties")
	elif event.keycode == KEY_ENTER: _focus_chat()
	else: return
	get_viewport().set_input_as_handled()

func _pve_changed() -> void:
	var model := network.pve
	if not model.ready:
		_cancel_approach()
	if not model.state.is_empty():
		_character = model.state.character.duplicate(true)
		_character.max_hp = model.state.stats.hp
		_character.max_mp = model.state.stats.mp
		_character.next_xp = int(_character.level) * 40
		if attributes.visible: attributes.display_online(_character, model.state.stats, model.state.get("attributes", {}))
		screen.chrome.display_character(_character)
		screen.hud.get_node("WorldIdentity").text = "等级 %d\n%s派" % [int(_character.level), ["峨眉", "花涧", "昆仑"][int(_character.school)]]
		_population(network.population.entities)
		if model.state.battle is Dictionary and (model.active() or model.state.battle.id != _closed_battle):
			encounter.hide()
			battle_view.present(model)
			screen.chrome.round_label.text = "回合：%d/30" % int(model.state.battle.round)
			_set_battle_layout(true)
			screen.hud.hide()
			count_label.hide()
		elif battle_view.visible:
			battle_view.hide()
			_set_battle_layout(false)
			screen.hud.show()
			count_label.show()
	encounter.refresh()
	battle_view.refresh()

func _select_resident(id: String) -> void:
	if not residents.has(id) or network.pve.active() or network.pve.pending(): return
	_cancel_approach()
	if network.world_ready: network.stop_moving()
	menu.hide()
	details.hide()
	emote_picker.hide()
	encounter.present(id, network.population.entities[id], network.pve)

func _cancel_approach() -> void:
	if not _approach.is_empty() and network.world_ready: network.stop_moving()
	_approach = {}
	if encounter != null:
		encounter.approaching = false
		encounter.refresh()

func _resident_action(action: String, target: String) -> void:
	if not network.pve.ready or network.pve.pending(): return
	_approach = {"action": action, "target": target, "deadline": Time.get_unix_time_from_system() + 30.0, "stopped": true}
	encounter.approaching = true
	encounter.refresh()
	network.stop_moving()

func _advance_approach() -> void:
	if _approach.is_empty(): return
	if not network.world_ready or not network.pve.ready or Time.get_unix_time_from_system() > float(_approach.deadline):
		_cancel_approach()
		chat_status.text = "未能抵达，请重新选择目标。"
		return
	if not network.population.entities.has(_approach.target) or not network.entities.has(character_id):
		_cancel_approach()
		return
	var own: Dictionary = network.entities[character_id]
	if own.next_cell != null or not network._pending_motion.is_empty() or int(own.last_input_seq) < network._input_seq: return
	var cell := Vector2i(own.cell[0], own.cell[1])
	var resident: Dictionary = network.population.entities[_approach.target]
	var target := Vector2i(resident.cell[0], resident.cell[1])
	if absi(cell.x - target.x) + absi(cell.y - target.y) <= 2:
		if not _approach.stopped:
			_approach.stopped = true
			network.stop_moving()
			return
		var request := _approach
		_approach = {}
		encounter.approaching = false
		network.pve.submit(request.action, request.target)
		return
	var best := Vector2i(-1, -1)
	var shortest := 9999
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var goal: Vector2i = target + offset
		if not _motion_grid.region.has_point(goal) or _motion_grid.is_point_solid(goal): continue
		var path := _motion_grid.get_id_path(cell, goal)
		if not path.is_empty() and path.size() < shortest:
			best = goal
			shortest = path.size()
	if best.x < 0:
		_cancel_approach()
		chat_status.text = "目标不可达，请更换路线。"
	else:
		_approach.stopped = false
		network.move_to(best)

func _set_battle_layout(active: bool) -> void:
	screen.chrome.toolbar.visible = not active
	for name_value in ["Reward", "SceneReward13", "Panel11"]: screen.chrome.get_node(name_value).visible = not active
	screen.chrome.round_label.position.x = 205.0 if active else 210.0
	screen.chrome.round_label.size.x = 114.0 if active else 77.0
	screen.chrome.round_label.add_theme_color_override("font_color", Color("294d74") if active else Color("efe82e"))
	chat_panel.position.y = 424.0 if active else 403.0
	expanded_chat.get_node("Shade").size.y = chat_panel.position.y

func _open_expanded_chat() -> void:
	_close_attributes()
	_cancel_approach()
	if network.world_ready: network.stop_moving()
	_was_keyboard = false
	menu.hide()
	details.hide()
	encounter.hide()
	emote_picker.hide()
	chat_input.release_focus()
	battle_view.set_process_unhandled_key_input(false)
	expanded_chat.open()

func _expanded_chat_dismissed() -> void:
	chat_input.release_focus()
	battle_view.set_process_unhandled_key_input(true)

func _open_attributes() -> void:
	details.hide()
	if _character.is_empty():
		chat_status.text = "角色数据正在同步，请稍候。"
		return
	attributes.display_online(_character, network.pve.state.get("stats", {}), network.pve.state.get("attributes", {}))
	attributes.show()
	_update_allocation_controls()
	battle_view.set_process_unhandled_key_input(false)

func _close_attributes() -> void:
	if not attributes.visible: return
	attributes.signature.release_focus()
	attributes.hide()
	battle_view.set_process_unhandled_key_input(true)

func _can_allocate() -> bool:
	if network == null or not network.world_ready or not network.pve.ready or network.pve.pending() or network.pve.active() or not network.entities.has(character_id): return false
	var own: Dictionary = network.entities[character_id]
	return own.next_cell == null and network._pending_motion.is_empty() and int(own.last_input_seq) >= network._input_seq

func _update_allocation_controls() -> void:
	if not attributes.visible: return
	var hint := "停稳后可加点"
	if network.pve.pending(): hint = "正在保存，请稍候"
	elif not network.world_ready or not network.pve.ready: hint = "重新连接后可加点"
	elif network.pve.active(): hint = "战斗结束后可加点"
	attributes.set_allocation_enabled(_can_allocate(), hint)

func _allocate_attributes(points: Array) -> void:
	if not _can_allocate(): return
	if network.pve.submit("allocate", "", points):
		attributes.set_allocation_enabled(false, "正在保存，请稍候")
		chat_status.text = "正在保存属性点……"
