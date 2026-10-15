class_name OnlineWorldView
extends Control
## Public online scene: no Game.player, local quest/monster or local save calls.
signal close_requested
var character_id := ""
@onready var network: OnlineWorldClient = $Network
@onready var viewport: SubViewport = $Viewport
@onready var scene: Node2D = $Viewport/Scene
@onready var camera: Camera2D = $Viewport/Scene/Camera
@onready var image: TextureRect = $Image
@onready var status: Label = $Status
@onready var count_label: Label = $CountLabel
var actors: Dictionary = {}
var map_data: Dictionary
var _key_timer := 0.0
var _was_keyboard := false
@onready var chat_panel: Panel = $ChatPanel
@onready var chat_log: RichTextLabel = $ChatPanel/ChatLog
@onready var chat_input: LineEdit = $ChatPanel/ChatInput
@onready var chat_send: Button = $ChatPanel/ChatSend
@onready var chat_status: Label = $ChatPanel/ChatStatus
@onready var chat_button: Button = $ChatButton

func _ready() -> void:
	map_data = JSON.parse_string(FileAccess.get_file_as_string(OnlineWorldClient.MAP_PATH))
	_build_map()
	image.texture = viewport.get_texture()
	image.gui_input.connect(_map_input)
	$Back.pressed.connect(func() -> void:
		network.leave()
		close_requested.emit()
	)
	chat_button.pressed.connect(_toggle_chat)
	$ChatPanel/Collapse.pressed.connect(_toggle_chat)
	chat_send.pressed.connect(_send_chat)
	chat_input.text_submitted.connect(func(_text: String) -> void: _send_chat())
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
		elif actor.sprite.animation != "idle" or not actor.sprite.is_playing(): actor.sprite.play("idle")
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
