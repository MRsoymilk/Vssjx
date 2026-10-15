class_name OnlineWorldView
extends Control
## Public online scene: no Game.player, local quest/monster or local save calls.
signal close_requested
var character_id := ""
var network: OnlineWorldClient
var viewport: SubViewport
var scene: Node2D
var camera: Camera2D
var image: TextureRect
var status: Label
var count_label: Label
var actors: Dictionary = {}
var map_data: Dictionary
var _key_timer := 0.0
var _was_keyboard := false
var chat_panel: Panel
var chat_log: RichTextLabel
var chat_input: LineEdit
var chat_send: Button
var chat_status: Label
var chat_button: Button

func _ready() -> void:
	size = Vector2(320, 480)
	map_data = JSON.parse_string(FileAccess.get_file_as_string(OnlineWorldClient.MAP_PATH))
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 390)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	scene = Node2D.new()
	viewport.add_child(scene)
	_build_map()
	camera = Camera2D.new()
	camera.position = Vector2(168, 264)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 512
	camera.limit_bottom = 512
	scene.add_child(camera)
	image = TextureRect.new()
	image.position = Vector2(0, 28)
	image.size = Vector2(320, 390)
	image.texture = viewport.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	image.gui_input.connect(_map_input)
	add_child(image)
	OriginalSceneChrome.panel(self, Rect2(0, 0, 320, 28), Color("507fb6"), Color("e8e0aa"))
	count_label = OriginalSceneChrome.label(self, "青云山道 · 共享地图", Rect2(5, 4, 245, 20), 12, Color("fff5dc"))
	OriginalSceneChrome.button(self, "返回", Rect2(266, 1, 52, 26), 12).pressed.connect(func() -> void:
		network.leave()
		close_requested.emit()
	)
	OriginalSceneChrome.panel(self, Rect2(0, 418, 320, 62), Color("507fb6"), Color("e8e0aa"))
	status = OriginalSceneChrome.label(self, "正在连接……", Rect2(6, 424, 308, 48), 11, Color("fff5dc"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size = Vector2(250, 48)
	chat_button = OriginalSceneChrome.button(self, "聊天", Rect2(263, 432, 52, 30), 12)
	chat_button.pressed.connect(_toggle_chat)
	_build_chat()
	network = OnlineWorldClient.new()
	add_child(network)
	network.changed.connect(_snapshot)
	network.status_changed.connect(func(text_value: String) -> void: status.text = text_value)
	network.chat.changed.connect(_chat_changed)
	network.chat.status_changed.connect(func(text_value: String) -> void: chat_status.text = text_value)
	network.chat.confirmed.connect(func() -> void: chat_input.clear())
	network.start(character_id)

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
	count_label.text = "青云山道 · 同图%d人" % actors.size()
	status.text = "共享地图 · 点击移动 / WASD\n公共聊天已开放\n线上任务与战斗后续接入。"

func _build_chat() -> void:
	chat_panel = OriginalSceneChrome.panel(self, Rect2(6, 244, 308, 168), Color("365b83"), Color("e8e0aa"))
	chat_panel.name = "PublicChat"
	chat_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	OriginalSceneChrome.label(chat_panel, "公共频道 · 最近记录", Rect2(8, 6, 240, 20), 12, Color("fff5dc"))
	OriginalSceneChrome.button(chat_panel, "收起", Rect2(254, 4, 48, 24), 11).pressed.connect(_toggle_chat)
	chat_log = RichTextLabel.new()
	chat_log.position = Vector2(8, 32)
	chat_log.size = Vector2(292, 74)
	chat_log.bbcode_enabled = false
	chat_log.selection_enabled = true
	chat_log.scroll_following = true
	chat_log.add_theme_font_size_override("normal_font_size", 11)
	chat_log.add_theme_color_override("default_color", Color("fff5dc"))
	chat_panel.add_child(chat_log)
	chat_status = OriginalSceneChrome.label(chat_panel, "纯文本 · 最多120字", Rect2(8, 106, 292, 22), 10, Color("fff0a5"))
	chat_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_input = LineEdit.new()
	chat_input.position = Vector2(8, 132)
	chat_input.size = Vector2(234, 28)
	chat_input.max_length = 120
	chat_input.placeholder_text = "向大家说句话……"
	chat_input.add_theme_font_size_override("font_size", 11)
	chat_panel.add_child(chat_input)
	chat_send = OriginalSceneChrome.button(chat_panel, "发送", Rect2(246, 132, 54, 28), 12)
	chat_send.pressed.connect(_send_chat)
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
	chat_panel.hide()

func _toggle_chat() -> void:
	chat_panel.visible = not chat_panel.visible
	if chat_panel.visible:
		network.stop_moving()
		chat_input.grab_focus()
	else: chat_input.release_focus()

func _send_chat() -> void:
	network.chat.submit(chat_input.text)

func _chat_changed() -> void:
	var lines := PackedStringArray()
	for message in network.chat.messages: lines.append("%s：%s" % [message.display_name, message.text])
	chat_log.text = "\n".join(lines)
	chat_button.text = "聊天%d" % network.chat.messages.size() if not network.chat.messages.is_empty() else "聊天"

func _process(delta: float) -> void:
	if network != null:
		chat_send.disabled = not network.world_ready or not network.chat.connected or not network.chat.pending.is_empty()
		chat_input.editable = network.chat.pending.is_empty()
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
		elif actor.sprite.animation != "idle": actor.sprite.play("idle")
	if actors.has(character_id): camera.position = actors[character_id].root.position
	if chat_panel.visible:
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
	if not network.world_ready or chat_panel.visible: return
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed: point = event.position
	elif event is InputEventScreenTouch and event.pressed: point = event.position
	else: return
	var world_point := camera.get_screen_center_position() + point - Vector2(viewport.size) / 2.0
	network.move_to(Vector2i(floori(world_point.x / 16.0), floori(world_point.y / 16.0)))
