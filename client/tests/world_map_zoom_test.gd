extends "res://tests/shared_interface_test.gd"

func click(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.pressed = pressed
	return event

func touch(page: OriginalWorldMap, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = pressed
	page._map_input(event)

func drag_touch(page: OriginalWorldMap, index: int, point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index; event.position = point; event.relative = relative
	page._map_input(event)

func _run() -> void:
	await Game.when_ready()
	var old := Game.player.duplicate(true)
	Game.new_player("总图缩放", 0, 3)
	var before := Game.player.duplicate(true)
	var page: OriginalWorldMap = load("res://scenes/ui/world_map.tscn").instantiate()
	add_child(page); page.present("ai_007", Vector2i(6,18))
	await get_tree().process_frame
	check(page.locations.size() == 79, "Only recovered locations are shown")
	for id in page.locations:
		var icon: Sprite2D = page.graph.get_node("Locations/Location%d" % id)
		var data: Dictionary = page.locations[id]
		var name_label: Label = icon.get_node("LocationName")
		var levels: Label = icon.get_node("LevelRange")
		check(name_label.text == data.name and levels.text == "%d～%d级" % [int(data.level_min), int(data.level_max)], "Every icon permanently shows its recovered name and level: %d" % id)
		check(name_label.mouse_filter == Control.MOUSE_FILTER_IGNORE and levels.mouse_filter == Control.MOUSE_FILTER_IGNORE and name_label.get_minimum_size().x <= page.STEP.x, "Node labels fit without intercepting touch input: %d" % id)
	check(not page.tooltip.visible, "Permanent text does not need an obstructing default tooltip")
	page.get_node("MapMenu/Details").pressed.emit()
	check(page.tooltip.visible and page.tooltip.get_node("Name").text == "天化村", "Explicit details remain available in the map menu")
	page.select_location(7,true)
	var anchor := Vector2(145,165)
	var graph_point := (anchor - page.graph.position) / page.zoom_level
	page.set_zoom(1.5,anchor)
	check(page.zoom_level == 1.5 and page.graph.scale == Vector2(1.5,1.5), "Icons, labels and routes scale together")
	check((page.graph.position + graph_point * page.zoom_level).distance_to(anchor) < 1, "Mouse-anchored zoom keeps the viewed point stable")
	check(page.get_node("ZoomControls/Reset").text == "150%", "Current zoom percentage is visible")
	page.select_location(6,true)
	check((page.graph.position + page.location_point(6)*page.zoom_level).is_equal_approx(page.map_area.size/2), "Centering respects zoom")
	var label_point := page.graph.position + (page.location_point(6) + Vector2(0,23))*page.zoom_level
	page._map_input(click(label_point,true)); page._map_input(click(label_point,false))
	check(page.selected_id == 6 and page.travel_confirmation.visible and page.travel_destination == "ai_006", "Clicking a scaled location name resolves the same travel destination")
	var zoom_before := page.zoom_level
	page.set_zoom(2)
	check(page.zoom_level == zoom_before, "Confirmation blocks zoom and accidental travel underneath")
	page.cancel_travel()
	page.set_zoom(999)
	check(page.zoom_level == page.MAX_ZOOM and page.get_node("ZoomControls/ZoomIn").disabled, "Maximum zoom is bounded and button reflects the limit")
	page.pan_by(Vector2(-99999,-99999))
	check(page.graph.position == page.map_area.size-page.GRAPH_SIZE*page.zoom_level, "Panning uses scaled right and bottom bounds")
	page.set_zoom(-999)
	check(page.zoom_level == page.MIN_ZOOM and page.get_node("ZoomControls/ZoomOut").disabled, "Minimum zoom remains positive and bounded")
	page.pan_by(Vector2(99999,99999))
	check(page.graph.position == Vector2.ZERO, "Scaled top and left bounds remain reachable")
	page.get_node("ZoomControls/Reset").pressed.emit()
	check(page.zoom_level == 1 and page.get_node("ZoomControls/Reset").text == "100%", "Reset button restores the default scale")
	page.select_location(7,true)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.position = Vector2(160,200); wheel.pressed = true
	page._map_input(wheel)
	check(page.zoom_level == 1.25, "Mouse wheel zooms rather than unexpectedly scrolling vertically")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; page._map_input(wheel)
	check(page.zoom_level == 1, "Reverse wheel zooms out")
	var gesture := InputEventMagnifyGesture.new(); gesture.factor = 1.5; gesture.position = Vector2(160,200)
	page._map_input(gesture)
	check(page.zoom_level == 1.5, "Trackpad magnify gesture uses the same zoom path")
	page.set_zoom(1); page.select_location(7,true)
	graph_point = (Vector2(150,200)-page.graph.position)/page.zoom_level
	touch(page,0,Vector2(100,200),true); touch(page,1,Vector2(200,200),true)
	drag_touch(page,1,Vector2(250,200),Vector2(50,0))
	check(is_equal_approx(page.zoom_level,1.5), "Two-finger pinch scales by finger separation")
	check((page.graph.position+graph_point*page.zoom_level).distance_to(Vector2(175,200)) < 1, "Pinch follows the moving gesture center")
	touch(page,0,Vector2(100,200),false); touch(page,1,Vector2(250,200),false)
	check(not page.travel_confirmation.visible and page._touches.is_empty(), "Releasing a pinch never opens a travel prompt")
	page.set_zoom(2); page.select_location(7,true)
	var position_before := page.graph.position
	touch(page,0,Vector2(100,200),true); touch(page,1,Vector2(200,200),true)
	drag_touch(page,1,Vector2(250,200),Vector2(50,0))
	check(page.zoom_level == 2 and page.graph.position == position_before+Vector2(25,0), "Pinch at maximum scale can still pan")
	touch(page,1,Vector2(250,200),false)
	drag_touch(page,0,Vector2(110,210),Vector2(10,10)); touch(page,0,Vector2(110,210),false)
	check(not page.travel_confirmation.visible, "Switching from pinch to one finger still cannot tap a destination")
	page.set_zoom(1); page.select_location(7,true)
	page._map_input(click(Vector2(100,100),true))
	position_before = page.graph.position
	var motion := InputEventMouseMotion.new()
	motion.position = page.map_area.global_position+Vector2(-50,100); motion.relative = Vector2(-150,0)
	page._input(motion)
	page._input(click(page.map_area.global_position+Vector2(-50,100),false))
	check(page.graph.position == position_before+Vector2(-150,0) and not page._dragging and not page.travel_confirmation.visible, "A drag released outside the map cannot stick or trigger travel")
	touch(page,0,Vector2(100,100),true); touch(page,1,Vector2(200,100),true)
	page.dismiss(); page.present("ai_007",Vector2i(9,17))
	check(page._touches.is_empty() and not page._dragging and page.current_cell == Vector2i(9,17), "Reopening clears stale gestures and follows the latest player cell")
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_PLUS
	page._unhandled_key_input(key)
	check(page.zoom_level == 1.25, "Keyboard plus zooms in")
	key.keycode = KEY_HOME; page._unhandled_key_input(key)
	check(page.zoom_level == 1, "Keyboard Home restores 100%")
	check(Game.player == before, "Map text, zoom and gesture browsing never modify the offline character")
	page.queue_free(); await get_tree().process_frame; Game.player = old
	print("WORLD MAP ZOOM: %d checks, %d failures" % [checks,failures]); get_tree().quit(1 if failures else 0)
