class_name OnlineWorldView
extends Control
## Shared game interface backed by online state; never installs Game.player.
signal close_requested
var character_id := ""
@onready var network: OnlineWorldClient = $Network
@onready var viewport: SubViewport = $Viewport
@onready var scene: Node2D = $Viewport/Scene
@onready var camera: Camera2D = $Viewport/Scene/Camera
@onready var image: TextureRect = $Image
@onready var screen: GameWorldScreen = $Screen
@onready var status: Label = $Screen/Chrome/MessagePanel/LogLabel
@onready var count_label: Label = $Screen/CountLabel
var actors: Dictionary = {}
var map_data: Dictionary
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
@onready var menu: Control = $Menu
var _character: Dictionary = {}
var _system_text := "正在连接共享地图……"
var _rendered_chat := ""

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
	$Menu/Panel/Continue.pressed.connect(func() -> void: menu.hide())
	$Menu/Panel/Leave.pressed.connect(_leave_world)
	$Menu/Panel/Chat.pressed.connect(func() -> void: menu.hide(); _focus_chat())
	chat_send.pressed.connect(_send_chat)
	emote_button.pressed.connect(_toggle_emotes)
	emote_picker.chosen.connect(_insert_emote)
	emote_picker.dismissed.connect(func() -> void: chat_input.grab_focus())
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
	chat_input.focus_entered.connect(func() -> void:
		if network.world_ready: network.stop_moving()
		_was_keyboard = false
	)
	chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			if emote_picker.visible: emote_picker.hide()
			else: chat_input.release_focus()
			chat_input.accept_event()
	)
	network.changed.connect(_snapshot)
	network.status_changed.connect(_status_changed)
	network.chat.changed.connect(_chat_changed)
	network.chat.status_changed.connect(func(text_value: String) -> void: chat_status.text = text_value)
	network.chat.confirmed.connect(func() -> void: chat_input.clear())
	chat_status.text = "公共频道 · 最多120字"
	network.start(character_id)

func _leave_world() -> void:
	network.leave()
	close_requested.emit()

func _scene_action(action: String) -> void:
	if action == "social":
		_toggle_chat()
		return
	if action == "menu" and menu.visible:
		menu.hide()
		return
	if network.world_ready: network.stop_moving()
	emote_picker.hide()
	chat_input.release_focus()
	_was_keyboard = false
	var titles := {"menu": "菜单", "properties": "人物属性", "quest": "任务", "bag": "背包", "map": "地图", "mail": "邮件", "reward": "奖励"}
	$Menu/Panel/Title.text = titles.get(action, "提示")
	var body := "同图%d人 · 点击地图移动 / WASD\n公共消息在底部直接发送。\n线上进度由服务器保存。" % actors.size()
	if action == "properties":
		body = "%s\n等级%d · %s · %s派\n气血%d · 灵力%d · 铜币%d" % [String(_character.get("display_name", "")), int(_character.get("level", 1)), ["力士", "侠客", "隐者"][int(_character.get("job", 0))], ["峨眉", "花涧", "昆仑"][int(_character.get("school", 0))], int(_character.get("hp", 0)), int(_character.get("mp", 0)), int(_character.get("gold", 0))]
	elif action == "map": body = "青云山道 · 同图%d人\n当前位置：%s\n小地图中的蓝点代表其他玩家。" % [actors.size(), screen.hud.get_node("MapCoordinates").text]
	elif action in ["quest", "bag", "reward"]: body = "线上%s尚未开放。\n可在当前地图移动，与同图玩家聊天。" % titles[action]
	elif action == "mail": body = "暂无邮件。"
	$Menu/Panel/Body.text = body
	menu.show()

func _status_changed(text_value: String) -> void:
	status.text = text_value
	_system_text = text_value
	if not network.world_ready:
		for actor in actors.values(): actor.sprite.play("idle")
	_chat_changed()

func _build_map() -> void:
	var terrain := TileMapLayer.new()
	var tiles := TileSet.new()
	tiles.tile_size = Vector2i(16, 16)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load("res://assets/tiles/original_tiles.png")
	atlas.texture_region_size = Vector2i(16, 16)
	for index in 756: atlas.create_tile(Vector2i(index % 32, index / 32))
	tiles.add_source(atlas)
	terrain.tile_set = tiles
	scene.add_child(terrain)
	for index in map_data.tiles.size():
		var tile := int(map_data.tiles[index])
		terrain.set_cell(Vector2i(index % 32, index / 32), 0, Vector2i(tile % 32, tile / 32))
	for prop in map_data.scenery:
		var actor := OriginalArt.actor(prop.art)
		actor.position = Vector2(prop.x, prop.y)
		scene.add_child(actor)

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
			root.z_index = 2
			scene.add_child(root)
			var key: String = (["mzs", "mck", "mfs"] if int(entity.gender) == 0 else ["wzs", "wck", "wfs"])[int(entity.job)]
			var sprite := OriginalArt.actor("hero/" + key)
			root.add_child(sprite)
			var label := OriginalSceneChrome.label(root, entity.display_name, Rect2(-65, -72, 130, 18), 11, Color("fff0a5") if id == character_id else Color("9ef6ff"))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.add_theme_constant_override("outline_size", 1)
			label.add_theme_color_override("font_outline_color", Color("1e343b"))
			actors[id] = {"root": root, "sprite": sprite, "target": point, "distance": 0.0}
		actors[id].target = point
	count_label.text = "同图%d人" % actors.size()
	screen.hud.get_node("Minimap").set_shared_world(map_data, values, character_id)
	if values.has(character_id):
		var own: Dictionary = values[character_id]
		screen.hud.get_node("MapCoordinates").text = "%d  %d" % [int(own.cell[0]), int(own.cell[1])]
		screen.hud.get_node("WorldIdentity").text = "等级 %d\n%s派" % [int(_character.get("level", 1)), ["峨眉", "花涧", "昆仑"][int(_character.get("school", 0))]]
	_system_text = "同图%d人 · 点击移动 / WASD" % actors.size()
	status.text = _system_text
	_chat_changed()

func _toggle_chat() -> void:
	emote_picker.hide()
	if chat_input.has_focus(): chat_input.release_focus()
	else: _focus_chat()

func _focus_chat() -> void:
	menu.hide()
	emote_picker.hide()
	chat_input.grab_focus()

func _toggle_emotes() -> void:
	if not _can_insert_emote(): return
	menu.hide()
	chat_input.grab_focus()
	if network.world_ready: network.stop_moving()
	_was_keyboard = false
	emote_picker.visible = not emote_picker.visible

func _insert_emote(token: String) -> void:
	if not _can_insert_emote() or not chat_input.editable or ChatEmotePicker.CATALOG.texture_for(token) == null: return
	var start := chat_input.get_selection_from_column() if chat_input.has_selection() else chat_input.caret_column
	var end := chat_input.get_selection_to_column() if chat_input.has_selection() else start
	var draft := chat_input.text.left(start) + token + chat_input.text.substr(end)
	if draft.length() > 120 or draft.to_utf8_buffer().size() > 480:
		chat_status.text = "消息最多120字，请删减后再添加表情。"
		return
	chat_input.text = draft
	chat_input.deselect()
	chat_input.caret_column = start + token.length()
	emote_picker.hide()
	chat_input.grab_focus()

func _can_insert_emote() -> bool:
	return network.world_ready and network.chat.connected and network.chat.pending.is_empty()

func _send_chat() -> void:
	emote_picker.hide()
	network.chat.submit(chat_input.text)
	_update_chat_controls()

func _chat_changed() -> void:
	var lines := PackedStringArray()
	if network.chat.messages.is_empty() or not network.world_ready: lines.append("[系统] " + _system_text)
	for message in network.chat.messages: lines.append("[公共] %s：%s" % [message.display_name, message.text])
	var text_value := "\n".join(lines)
	if text_value != _rendered_chat:
		_rendered_chat = text_value
		chat_log.clear()
		if network.chat.messages.is_empty() or not network.world_ready:
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
		if emote_button.disabled: emote_picker.hide()

func _process(delta: float) -> void:
	_update_chat_controls()
	if network == null or not network.world_ready: return
	for id in actors:
		var actor: Dictionary = actors[id]
		var old: Vector2 = actor.root.position
		actor.root.position = old.move_toward(actor.target, 100.0 * delta)
		var distance: float = old.distance_to(actor.root.position)
		if distance > 0.001:
			actor.distance += distance
			if absf(actor.root.position.x - old.x) > 0.001: actor.sprite.scale.x = 1.0 if actor.root.position.x < old.x else -1.0
			actor.sprite.animation = "walk"
			actor.sprite.pause()
			var phase: float = actor.distance / 32.0 * actor.sprite.sprite_frames.get_frame_count("walk")
			actor.sprite.set_frame_and_progress(int(phase) % actor.sprite.sprite_frames.get_frame_count("walk"), fposmod(phase, 1.0))
		elif actor.sprite.animation != "idle" or not actor.sprite.is_playing(): actor.sprite.play("idle")
	if actors.has(character_id): camera.position = actors[character_id].root.position
	if chat_input.has_focus() or menu.visible or emote_picker.visible:
		_was_keyboard = false
		return
	_key_timer -= delta
	var direction := Vector2i(int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)), int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if direction.x != 0: direction.y = 0
	if direction != Vector2i.ZERO and _key_timer <= 0 and network.entities.has(character_id):
		_key_timer = 0.15
		var own: Dictionary = network.entities[character_id]
		var cell: Array = own.next_cell if own.next_cell != null else own.cell
		network.move_to(Vector2i(cell[0], cell[1]) + direction)
		_was_keyboard = true
	elif direction == Vector2i.ZERO and _was_keyboard and _key_timer <= 0:
		network.stop_moving()
		_was_keyboard = false

func _map_input(event: InputEvent) -> void:
	if not network.world_ready or menu.visible: return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: point = event.position
	elif event is InputEventScreenTouch and event.pressed: point = event.position
	else: return
	if emote_picker.visible:
		emote_picker.hide()
		return
	chat_input.release_focus()
	var world_point := camera.get_screen_center_position() + point - Vector2(viewport.size) / 2.0
	network.move_to(Vector2i(floori(world_point.x / 16.0), floori(world_point.y / 16.0)))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		if emote_picker.visible: emote_picker.hide()
		elif chat_input.has_focus(): chat_input.release_focus()
		else: _scene_action("menu")
	elif event.keycode == KEY_ENTER: _focus_chat()
	else: return
	get_viewport().set_input_as_handled()
