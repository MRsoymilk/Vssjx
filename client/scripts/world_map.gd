class_name OriginalWorldMap
extends Control
## Recovered overview locations with confirmed, inventory-backed talisman travel.
signal back_requested
signal travel_requested(map_id: String)
const STEP := Vector2(64, 76)
const PADDING := Vector2(40, 28)
const GRAPH_SIZE := Vector2(1488, 1956)
const MIN_ZOOM := 0.5
const MAX_ZOOM := 2.0
const ZOOM_STEP := 1.25
const LOCATION_RECT := Rect2(-32, -13, 64, 62)
var locations: Dictionary = {}
var selected_id := 14
var current_map_id := ""
var current_cell := Vector2i(-1,-1)
var online_model: OnlinePve
var travel_destination := ""
var travel_busy := false
var travel_notice := ""
var zoom_level := 1.0
var _dragging := false
var _drag_distance := 0.0
var _touch_index := -1
var _touches: Dictionary = {}
var _touch_gesture_used := false
var _details_requested := false
@onready var map_area: Control = $MapArea
@onready var graph: Node2D = $MapArea/Graph
@onready var selection: TextureRect = $MapArea/Selection
@onready var tooltip: Panel = $MapArea/LocationTip
@onready var popup: Panel = $MapMenu
@onready var travel_confirmation: Control = $TravelConfirmation
@onready var travel_confirm: Button = $TravelConfirmation/Panel/Confirm

func _ready() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/original_world.json"))
	for node in source.maps.world_overview.nodes: locations[int(node.original_map_id)] = node
	_layout_graph(source.maps.world_overview)
	map_area.gui_input.connect(_map_input)
	map_area.resized.connect(func() -> void: _clamp_pan(); _place_selection())
	$Header/Wild.pressed.connect(cycle_kind.bind(0))
	$Header/City.pressed.connect(cycle_kind.bind(1))
	$Header/School.pressed.connect(cycle_kind.bind(2))
	$MainCity.pressed.connect(cycle_kind.bind(1))
	$Footer/Back.pressed.connect(_request_back)
	$Footer/Travel.pressed.connect(func() -> void: request_travel(selected_destination()))
	$Footer/Menu.pressed.connect(func() -> void: popup.visible = not popup.visible)
	$MapMenu/Details.pressed.connect(func() -> void: popup.hide(); _details_requested = true; _place_selection())
	$MapMenu/City.pressed.connect(func() -> void: popup.hide(); cycle_kind(1))
	$MapMenu/Close.pressed.connect(_request_back)
	$CurrentLocation.pressed.connect(_locate_current)
	$ZoomControls/ZoomOut.pressed.connect(func() -> void: set_zoom(zoom_level / ZOOM_STEP))
	$ZoomControls/ZoomIn.pressed.connect(func() -> void: set_zoom(zoom_level * ZOOM_STEP))
	$ZoomControls/Reset.pressed.connect(func() -> void: set_zoom(1.0))
	travel_confirm.pressed.connect(_confirm_travel)
	$TravelConfirmation/Panel/Cancel.pressed.connect(cancel_travel)
	Game.storage_changed.connect(func(_busy: bool) -> void: _refresh_travel())
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): _reset_gestures()
	)
	select_location(selected_id, true)
	_refresh_zoom()

func _layout_graph(overview: Dictionary) -> void:
	# Keep the recovered topology; larger display spacing makes room for text.
	for id in locations:
		var icon: Sprite2D = graph.get_node("Locations/Location%d" % id)
		icon.position = location_point(id)
		var node: Dictionary = locations[id]
		for row in [["LocationName", String(node.name), 15.0, 12], ["LevelRange", "%d～%d级" % [int(node.level_min), int(node.level_max)], 33.0, 11]]:
			var label := Label.new()
			label.name = row[0]
			label.text = row[1]
			label.position = Vector2(-32, row[2])
			label.size = Vector2(64, 18)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_override("font", get_theme_font("font"))
			label.add_theme_font_size_override("font_size", row[3])
			label.add_theme_color_override("font_color", Color("fff6d2"))
			label.add_theme_color_override("font_outline_color", Color("14271b"))
			label.add_theme_constant_override("outline_size", 2)
			icon.add_child(label)
	for route in overview.routes:
		var line: Line2D = graph.get_node("Routes/Route%d" % int(route.index))
		line.points = PackedVector2Array([Vector2(route["from"][0], route["from"][1]) * STEP + PADDING, Vector2(route.to[0], route.to[1]) * STEP + PADDING])

func _reset_gestures() -> void:
	_dragging = false
	_drag_distance = 0.0
	_touch_index = -1
	_touches.clear()
	_touch_gesture_used = false

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]: _reset_gestures()

func present(map_id: String = "", cell: Vector2i = Vector2i(-1,-1), model: OnlinePve = null) -> void:
	if online_model != model:
		if online_model != null and online_model.changed.is_connected(_refresh_travel): online_model.changed.disconnect(_refresh_travel)
		online_model = model
		if online_model != null: online_model.changed.connect(_refresh_travel)
	travel_busy = false
	cancel_travel()
	popup.hide()
	_reset_gestures()
	_details_requested = false
	current_map_id=map_id;current_cell=cell
	show()
	$CurrentLocation.visible=not map_id.is_empty()
	if map_id.is_empty():_place_selection()
	else:_locate_current()
	_refresh_travel()

func selected_destination() -> String:
	return "ai_%03d" % selected_id if locations.has(selected_id) else ""

func scroll_count() -> int:
	if online_model == null: return ShopRules.quantity(ShopRules.local_state(Game.player), ShopRules.TRAVEL_SCROLL)
	if not online_model.ready or online_model.state.get("shop", {}).get("version") != "shop-v2": return -1
	return ShopRules.quantity(online_model.state.shop, ShopRules.TRAVEL_SCROLL)

func _travel_error(destination: String) -> String:
	if travel_busy: return "正在确认传送，请稍候……"
	if online_model != null:
		if not online_model.ready or scroll_count() < 0: return "神行符数量正在同步，请稍候。"
		if online_model.pending(): return "上一项操作尚未确认，请稍候。"
		if online_model.active(): return OnlinePve.error_text("BATTLE_ACTIVE")
		if online_model.is_soul(): return OnlinePve.error_text("SOUL_STATE")
	else:
		if Game.storage_busy: return "正在保存，请稍候。"
		if Game.local_battle_active(): return OnlinePve.error_text("BATTLE_ACTIVE")
		if Game.is_soul(): return OnlinePve.error_text("SOUL_STATE")
	var stage := int(Game.player.get("quest", 0) if online_model == null else online_model.state.character.quest_stage)
	var error := ShopRules.travel_error(destination, current_map_id, stage)
	if not error.is_empty(): return OnlinePve.error_text(error)
	if scroll_count() < 1: return OnlinePve.error_text("TRAVEL_SCROLL_REQUIRED")
	return ""

func _refresh_travel() -> void:
	if not is_node_ready(): return
	var count := scroll_count()
	$Footer/TravelCount.text = str(count) if count >= 0 else "—"
	$Footer/Travel.disabled = travel_busy or selected_destination().is_empty()
	$Footer/Travel.tooltip_text = "点击地图上的目的地，确认使用1张神行符。"
	if not travel_confirmation.visible: return
	$TravelConfirmation/Panel/Question.text = "是否使用1张神行符前往\n%s？\n持有：%s张" % [SharedWorldMap.title(travel_destination), str(count) if count >= 0 else "—"]
	var error := _travel_error(travel_destination)
	$TravelConfirmation/Panel/Status.text = error if not error.is_empty() else travel_notice
	travel_confirm.disabled = not error.is_empty()
	$TravelConfirmation/Panel/Cancel.disabled = travel_busy

func request_travel(destination: String) -> void:
	if travel_busy or destination.is_empty() or not SharedWorldMap.exists(destination): return
	_reset_gestures()
	popup.hide()
	travel_destination = destination
	travel_notice = ""
	travel_confirmation.show()
	_refresh_travel()

func _confirm_travel() -> void:
	if not travel_confirmation.visible or travel_busy: return
	if not _travel_error(travel_destination).is_empty(): _refresh_travel(); return
	travel_busy = true
	_refresh_travel()
	travel_requested.emit(travel_destination)

func finish_travel(message: String) -> void:
	travel_busy = false
	travel_notice = message
	_refresh_travel()

func cancel_travel() -> void:
	if travel_busy: return
	travel_confirmation.hide()
	travel_destination = ""
	travel_notice = ""

func dismiss() -> void:
	_reset_gestures()
	travel_busy = false
	cancel_travel()
	hide()

func _request_back() -> void:
	if not travel_busy: back_requested.emit()

func _locate_current() -> void:
	var data:=AIWorld.map_data(current_map_id)
	var id:=int(data.get("original_map_id",-1))
	var known:=locations.has(id)
	var location_name:=String(data.get("name",SharedWorldMap.title(current_map_id)))
	var coordinates:=" (%d,%d)"%[current_cell.x,current_cell.y] if current_cell.x>=0 and current_cell.y>=0 else ""
	$CurrentLocation.text="当前位置："+location_name+coordinates+("" if known else " · 总图未标注")
	$CurrentLocation.disabled=not known
	if known:select_location(id,true)
	else:
		selected_id=-1
		_place_selection()

func select_location(id: int, center: bool = false) -> void:
	if not locations.has(id): return
	selected_id = id
	_details_requested = false
	var node: Dictionary = locations[id]
	tooltip.get_node("Name").text = node.name
	tooltip.get_node("Level").text = "%d～%d级" % [int(node.level_min), int(node.level_max)]
	if center:
		graph.position = map_area.size/2.0 - location_point(id) * zoom_level
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

func set_zoom(value: float, anchor: Vector2 = Vector2(-1, -1)) -> void:
	if travel_confirmation.visible or travel_busy: return
	if anchor.x < 0 or anchor.y < 0: anchor = map_area.size / 2.0
	_zoom_at(value, anchor, anchor)

func _zoom_at(value: float, old_anchor: Vector2, new_anchor: Vector2) -> void:
	var graph_point := (old_anchor - graph.position) / zoom_level
	zoom_level = clampf(value, MIN_ZOOM, MAX_ZOOM)
	graph.scale = Vector2.ONE * zoom_level
	graph.position = new_anchor - graph_point * zoom_level
	_clamp_pan()
	_place_selection()
	_refresh_zoom()

func _refresh_zoom() -> void:
	$ZoomControls/Reset.text = "%d%%" % roundi(zoom_level * 100)
	$ZoomControls/ZoomOut.disabled = travel_busy or zoom_level <= MIN_ZOOM
	$ZoomControls/ZoomIn.disabled = travel_busy or zoom_level >= MAX_ZOOM

func _clamp_pan() -> void:
	var extent := GRAPH_SIZE * zoom_level
	for axis in 2:
		graph.position[axis] = roundf((map_area.size[axis] - extent[axis]) / 2.0 if extent[axis] <= map_area.size[axis] else clampf(graph.position[axis], map_area.size[axis] - extent[axis], 0))

func _place_selection() -> void:
	_refresh_travel()
	if not locations.has(selected_id):
		selection.hide();tooltip.hide()
		return
	var point := graph.position + location_point(selected_id) * zoom_level
	var onscreen := Rect2(Vector2.ZERO, map_area.size).grow(-12).has_point(point)
	selection.visible = onscreen
	tooltip.visible = onscreen and _details_requested
	selection.position = point + Vector2(4, 3)
	tooltip.position = Vector2(clampf(point.x - tooltip.size.x / 2, 3, map_area.size.x - tooltip.size.x - 3), clampf(point.y + 52 * zoom_level, 3, map_area.size.y - tooltip.size.y - 3)).round()

func _select_at(point: Vector2) -> void:
	if not Rect2(Vector2.ZERO, map_area.size).has_point(point): return
	var graph_point := (point - graph.position) / zoom_level
	var nearest := -1
	var distance := INF
	for id in locations:
		var offset := graph_point - location_point(id)
		var candidate := offset.length()
		if LOCATION_RECT.has_point(offset) and candidate < distance:
			distance = candidate
			nearest = id
	if nearest >= 0:
		select_location(nearest)
		request_travel(selected_destination())

func _input(event: InputEvent) -> void:
	# Finish drags/releases even outside MapArea, without leaking into the world.
	if not is_visible_in_tree() or travel_confirmation.visible or travel_busy: return
	var captured_mouse: bool = _dragging and (event is InputEventMouseMotion or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed))
	var captured_touch: bool = (event is InputEventScreenDrag or (event is InputEventScreenTouch and not event.pressed)) and _touches.has(event.index)
	if captured_mouse or captured_touch:
		_map_input(event.xformed_by(map_area.get_global_transform_with_canvas().affine_inverse()))
		get_viewport().set_input_as_handled()

func _map_input(event: InputEvent) -> void:
	if travel_confirmation.visible or travel_busy: return
	popup.hide()
	if event is InputEventMouse and not _touches.is_empty():
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
			if event.shift_pressed: pan_by(Vector2(-80 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 80, 0))
			else: set_zoom(zoom_level * (ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP), event.position)
	elif event is InputEventMouseMotion and _dragging:
		_drag_distance += event.relative.length()
		pan_by(event.relative)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_dragging = false
			if _touches.is_empty():
				_touch_index = event.index
				_drag_distance = 0
				_touch_gesture_used = false
			_touches[event.index] = event.position
			if _touches.size() > 1: _touch_gesture_used = true
		elif _touches.has(event.index):
			var tapped := _touches.size() == 1 and not _touch_gesture_used and _drag_distance < 6
			_touches.erase(event.index)
			if _touches.is_empty():
				_touch_index = -1
				if tapped: _select_at(event.position)
			else: _touch_index = int(_touches.keys()[0])
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if _touches.size() >= 2:
			var ids := _touches.keys()
			var first: Vector2 = _touches[ids[0]]
			var second: Vector2 = _touches[ids[1]]
			var old_center := (first + second) / 2.0
			var old_distance := first.distance_to(second)
			_touches[event.index] = event.position
			first = _touches[ids[0]]; second = _touches[ids[1]]
			var new_distance := first.distance_to(second)
			if old_distance > 1 and new_distance > 1: _zoom_at(zoom_level * new_distance / old_distance, old_center, (first + second) / 2.0)
		else:
			_touches[event.index] = event.position
			_drag_distance += event.relative.length()
			pan_by(event.relative)
	elif event is InputEventMagnifyGesture:
		set_zoom(zoom_level * event.factor, event.position)
	elif event is InputEventPanGesture:
		pan_by(-event.delta * 32)
	map_area.accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	var input_viewport := get_viewport()
	if travel_confirmation.visible:
		if event.keycode in [KEY_ESCAPE, KEY_3]: cancel_travel()
		elif event.keycode == KEY_ENTER: _confirm_travel()
		input_viewport.set_input_as_handled()
		return
	match event.keycode:
		KEY_ESCAPE, KEY_3: _request_back()
		KEY_0: cycle_kind(1)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: set_zoom(zoom_level * ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT: set_zoom(zoom_level / ZOOM_STEP)
		KEY_HOME: set_zoom(1.0)
		KEY_LEFT, KEY_A: pan_by(Vector2(STEP.x, 0))
		KEY_RIGHT, KEY_D: pan_by(Vector2(-STEP.x, 0))
		KEY_UP, KEY_W: pan_by(Vector2(0, STEP.y))
		KEY_DOWN, KEY_S: pan_by(Vector2(0, -STEP.y))
		KEY_ENTER: request_travel(selected_destination())
		_: return
	input_viewport.set_input_as_handled()
