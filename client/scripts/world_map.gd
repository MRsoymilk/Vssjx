class_name OriginalWorldMap
extends Control
## Recovered overview coordinates are browsing data, not teleport destinations.
signal back_requested
signal ai_requested(map_id: String)
const STEP := Vector2(46, 56)
const PADDING := Vector2(24, 24)
const GRAPH_SIZE := Vector2(1060, 1448)
var locations: Dictionary = {}
var selected_id := 14
var _dragging := false
var _drag_distance := 0.0
var _touch_index := -1
@onready var map_area: Control = $MapArea
@onready var graph: Node2D = $MapArea/Graph
@onready var selection: TextureRect = $MapArea/Selection
@onready var tooltip: Panel = $MapArea/LocationTip
@onready var popup: Panel = $MapMenu

func _ready() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/original_world.json"))
	for node in source.maps.world_overview.nodes: locations[int(node.original_map_id)] = node
	map_area.gui_input.connect(_map_input)
	$Header/Wild.pressed.connect(cycle_kind.bind(0))
	$Header/City.pressed.connect(cycle_kind.bind(1))
	$Header/School.pressed.connect(cycle_kind.bind(2))
	$MainCity.pressed.connect(cycle_kind.bind(1))
	$Footer/Back.pressed.connect(func() -> void: back_requested.emit())
	$Footer/Menu.pressed.connect(func() -> void: popup.visible = not popup.visible)
	$MapMenu/Details.pressed.connect(func() -> void: popup.hide(); _place_selection())
	$MapMenu/City.pressed.connect(func() -> void: popup.hide(); cycle_kind(1))
	$MapMenu/Close.pressed.connect(func() -> void: back_requested.emit())
	var ai_button := Button.new()
	ai_button.text = "AI生成 · 驿路目录"
	ai_button.position = Vector2(130, 404); ai_button.size = Vector2(180, 30)
	ai_button.add_theme_font_size_override("font_size", 12)
	add_child(ai_button)
	ai_button.pressed.connect(func() -> void: ai_requested.emit("ai_%03d" % selected_id))
	select_location(selected_id, true)

func present() -> void:
	popup.hide()
	_dragging = false
	_touch_index = -1
	show()
	_place_selection()

func select_location(id: int, center: bool = false) -> void:
	if not locations.has(id): return
	selected_id = id
	var node: Dictionary = locations[id]
	tooltip.get_node("Name").text = node.name
	tooltip.get_node("Level").text = "%d～%d级" % [int(node.level_min), int(node.level_max)]
	if center:
		graph.position = Vector2(170, 240) - location_point(id)
		_clamp_pan()
	_place_selection()

func location_point(id: int) -> Vector2:
	var position: Array = locations[id].world_position
	return Vector2(position[0], position[1]) * STEP + PADDING

func cycle_kind(kind: int) -> void:
	var ids: Array[int] = []
	for id in locations:
		if int(locations[id].location_kind) == kind: ids.append(id)
	if ids.is_empty(): return
	var index := ids.find(selected_id)
	select_location(ids[(index + 1) % ids.size()], true)

func pan_by(delta: Vector2) -> void:
	graph.position += delta
	_clamp_pan()
	_place_selection()

func _clamp_pan() -> void:
	graph.position.x = roundf(clampf(graph.position.x, map_area.size.x - GRAPH_SIZE.x, 0))
	graph.position.y = roundf(clampf(graph.position.y, map_area.size.y - GRAPH_SIZE.y, 0))

func _place_selection() -> void:
	if not locations.has(selected_id): return
	var point := graph.position + location_point(selected_id)
	var onscreen := Rect2(Vector2.ZERO, map_area.size).grow(-12).has_point(point)
	selection.visible = onscreen
	tooltip.visible = onscreen
	selection.position = point + Vector2(4, 3)
	tooltip.position = Vector2(clampf(point.x - tooltip.size.x / 2, 3, map_area.size.x - tooltip.size.x - 3), clampf(point.y + 25, 3, map_area.size.y - tooltip.size.y - 3)).round()

func _select_at(point: Vector2) -> void:
	var nearest := -1
	var distance := 16.0
	for id in locations:
		var candidate := point.distance_to(graph.position + location_point(id))
		if candidate < distance:
			distance = candidate
			nearest = id
	if nearest >= 0: select_location(nearest)

func _map_input(event: InputEvent) -> void:
	popup.hide()
	if event is InputEventMouse and _touch_index >= 0:
		map_area.accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_distance = 0
			else:
				if _dragging and _drag_distance < 6: _select_at(event.position)
				_dragging = false
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var delta := -80.0 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 80.0
			pan_by(Vector2(delta, 0) if event.shift_pressed else Vector2(0, delta))
	elif event is InputEventMouseMotion and _dragging:
		_drag_distance += event.relative.length()
		pan_by(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed and _touch_index < 0:
			_dragging = false
			_touch_index = event.index
			_drag_distance = 0
		elif not event.pressed and event.index == _touch_index:
			if _drag_distance < 6: _select_at(event.position)
			_touch_index = -1
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_drag_distance += event.relative.length()
		pan_by(event.relative)
	map_area.accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed: return
	var input_viewport := get_viewport()
	match event.keycode:
		KEY_ESCAPE, KEY_3: back_requested.emit()
		KEY_0: cycle_kind(1)
		KEY_LEFT, KEY_A: pan_by(Vector2(STEP.x, 0))
		KEY_RIGHT, KEY_D: pan_by(Vector2(-STEP.x, 0))
		KEY_UP, KEY_W: pan_by(Vector2(0, STEP.y))
		KEY_DOWN, KEY_S: pan_by(Vector2(0, -STEP.y))
		KEY_ENTER: _place_selection()
		_: return
	input_viewport.set_input_as_handled()
