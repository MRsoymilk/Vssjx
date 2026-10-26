extends "res://tests/shared_interface_test.gd"

func mouse_event(point: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	return event

func _run() -> void:
	var old := Game.player.duplicate(true)
	var old_path := Game.save_path
	var old_characters := OnlineAccount.characters.duplicate(true)
	Game.save_path = "user://world_map_%d.json" % OS.get_process_id()
	Game.new_player("地图修士",1,2)
	Game.player.ai_map="ai_001";Game.player.cell=[7,21]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_world()
	app.minimap.gui_input.emit(mouse_event(Vector2(25,25),true))
	var page: OriginalWorldMap = app.modal
	check(page != null and page.scene_file_path == "res://scenes/ui/world_map.tscn" and not app.world.enabled, "Map entry opens authored overview and pauses local world")
	check(app.minimap.size==Vector2(80,82),"Clicking the minimap opens the map without collapsing the HUD")
	var before := Game.player.duplicate(true)
	check(page.locations.size() == 79 and page.graph.get_node("Locations").get_child_count() == 79 and page.graph.get_node("Routes").get_child_count() == 78, "Overview preserves all recovered locations and routes")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/original_world.json"))
	var valid := true
	for node in source.maps.world_overview.nodes:
		var icon: Sprite2D = page.graph.get_node("Locations/Location%d" % int(node.original_map_id))
		valid = valid and icon.position == page.location_point(int(node.original_map_id)) and icon.texture.resource_path == "res://assets/ui/worldmap_node_%d.png" % int(node.location_kind)
	check(valid, "Scene positions and original icons match recovered data")
	valid = true
	for route in source.maps.world_overview.routes:
		var line: Line2D = page.graph.get_node("Routes/Route%d" % int(route.index))
		valid = valid and line.points[0] == Vector2(route["from"][0],route["from"][1])*page.STEP+page.PADDING and line.points[1] == Vector2(route.to[0],route.to[1])*page.STEP+page.PADDING
	check(valid, "Authored lines preserve original endpoints without inventing connections")
	check(page.selected_id == 1 and page.tooltip.get_node("Name").text == "灵空台" and page.tooltip.get_node("Level").text == "1～5级", "Opening selects the player's actual map and its recovered levels")
	check((page.graph.position+page.location_point(1)).is_equal_approx(page.map_area.size/2.0),"Current map is centered in the visible graph")
	check(page.get_node("CurrentLocation").text=="当前位置：灵空台 (7,21)","Current location includes the live player cell")
	check(page.get_node("Header/Wild").text == "野外" and page.get_node("Header/City").text == "城市" and page.get_node("Header/School").text == "门派", "Header matches reference legend")
	check(page.get_node("Footer/TravelCount").text == "0", "Map displays the real local talisman stock")
	check(not page.find_children("*","Button",true,false).any(func(b:Button)->bool:return b.text.contains("目录")),"Map has no station directory entry")
	output = OS.get_environment("SSJX_WORLD_MAP_CAPTURE_PATH") if DisplayServer.get_name() != "headless" else ""
	await capture("local_world_map")
	if not output.is_empty():
		page.select_location(7,true)
		await capture("named_world_map")
		page.set_zoom(2)
		await capture("named_world_map_200")
		page.set_zoom(.5)
		await capture("named_world_map_50")
		page.set_zoom(1)
	page.select_location(14,true) # Bring the clicked destination into the visible viewport.
	var point := page.graph.position+page.location_point(15)
	page._map_input(mouse_event(point,true))
	page._map_input(mouse_event(point,false))
	check(page.selected_id == 15 and page.tooltip.get_node("Name").text == "跃阳湖", "Mouse click selects actual map location")
	check(page.travel_confirmation.visible and page.travel_destination=="ai_015" and page.travel_confirm.disabled and Game.player==before,"Click asks about the selected destination and insufficient stock cannot spend")
	var cancel_key:=InputEventKey.new();cancel_key.keycode=KEY_ESCAPE;cancel_key.pressed=true
	get_viewport().push_input(cancel_key,true)
	check(app.modal==page and not page.travel_confirmation.visible and not app.world.enabled,"Escape cancels the confirmation without closing the local map or resuming movement")
	var start := page.graph.position
	page._map_input(mouse_event(Vector2(100,100),true))
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(-50,30)
	page._map_input(motion)
	page._map_input(mouse_event(Vector2(50,130),false))
	check(page.graph.position == start+Vector2(-50,30) and page.selected_id == 15 and not page.travel_confirmation.visible, "Dragging pans map without selecting or requesting travel")
	var touch := InputEventScreenTouch.new(); touch.index = 0; touch.pressed = true; touch.position = Vector2(100,100)
	page._map_input(touch)
	var drag := InputEventScreenDrag.new(); drag.index = 0; drag.relative = Vector2(20,-20)
	start = page.graph.position
	page._map_input(drag)
	touch.pressed = false
	page._map_input(touch)
	check(page.graph.position == start+Vector2(20,-20), "Touch drag pans the same authored graph")
	page.pan_by(Vector2(99999,99999))
	check(page.graph.position == Vector2.ZERO and not page.selection.visible and not page.tooltip.visible, "Map bounds clamp panning and offscreen selection is hidden")
	page.pan_by(Vector2(-99999,-99999))
	check(page.graph.position == page.map_area.size-page.GRAPH_SIZE, "Bottom and right panning limits remain bounded")
	page.get_node("MainCity").pressed.emit()
	check(page.selected_id == 13 and page.selection.visible and int(page.locations[page.selected_id].location_kind) == 1, "Main city button centers first actual city")
	var key := InputEventKey.new(); key.keycode = KEY_0; key.pressed = true
	page._unhandled_key_input(key)
	check(page.selected_id == 29 and page.tooltip.get_node("Name").text == "慈云寺", "Zero key cycles recovered cities")
	page.get_node("Header/School").pressed.emit()
	check(page.selected_id == 4 and page.tooltip.get_node("Name").text == "峨眉派", "School legend centers a recovered school")
	page.get_node("Footer/Menu").pressed.emit()
	check(page.popup.visible, "Reference footer menu opens authored options")
	page.popup.get_node("City").pressed.emit()
	check(not page.popup.visible and page.selected_id == 13, "Map menu switches city without changing game location")
	check(Game.player == before, "Overview browsing does not change offline inventory, position or progress")
	page.get_node("Footer/Back").pressed.emit()
	check(app.modal == null and app.world.enabled, "Back resumes same local world")
	app.world.cell=Vector2i(11,23);app.world.hero.position=app.world.cell_center(app.world.cell);Game.player.cell=[11,23]
	key.keycode = KEY_3
	app._unhandled_key_input(key)
	check(app.modal is OriginalWorldMap and not app.world.enabled, "Three key opens world map")
	check(app.modal.selected_id==1 and app.modal.get_node("CurrentLocation").text=="当前位置：灵空台 (11,23)","Reopening follows the latest cell instead of the last browsed city")
	key.keycode = KEY_ESCAPE
	app.modal._unhandled_key_input(key)
	check(app.modal == null and app.world.enabled, "Map Escape closes without consuming input through a detached node")
	var local_touch:=InputEventScreenTouch.new();local_touch.pressed=true;local_touch.position=Vector2(20,20)
	app.minimap.gui_input.emit(local_touch)
	check(app.modal is OriginalWorldMap and app.modal.selected_id==1,"Touching the minimap opens the same current location")
	app._close_modal()
	app.queue_free()
	await get_tree().process_frame
	await online_map()
	OnlineAccount.characters = old_characters
	Game.player = old
	Game.save_path = old_path
	print("WORLD MAP: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if failures == 0 else 1)

func online_map() -> void:
	var offline := Game.player.duplicate(true)
	OnlineAccount.characters = [{"id":SELF,"display_name":"联网修士","job":1,"gender":0,"school":2,"level":1,"hp":95,"mp":45,"gold":30}]
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_online_world(SELF)
	var view: OnlineWorldView = app.ui.get_node("OnlineWorld")
	view.network.set_process(false)
	view.network.world_ready = true
	view._map_changed("ai_007")
	view.network.entities = {SELF:entity(SELF,1,"联网修士",1,0,[6,18])}
	view.network.changed.emit(view.network.entities)
	var chat_id := view.chat_panel.get_instance_id()
	view.chat_input.text = "未发送的聊天草稿"
	view.move_target.set_destination(Vector2i(14,16))
	view.screen.hud.get_node("Minimap").gui_input.emit(mouse_event(Vector2(25,25),true))
	var page := view.world_map
	check(page.visible and page.scene_file_path == "res://scenes/ui/world_map.tscn" and not view.details.visible, "Online map entry opens shared reference scene instead of text dialog")
	check(page.selected_id==7 and page.get_node("CurrentLocation").text=="当前位置：天化村 (6,18)","Online location uses the current server map and own entity, not the offline character")
	check(page.get_node("Footer/TravelCount").text=="—","Unsynchronized online stock never falls back to the offline inventory")
	check((page.graph.position+page.location_point(7)).is_equal_approx(page.map_area.size/2.0),"Online map centers on the current location")
	check(view.network._pending_motion.get("type") == "world.stop" and not view.move_target.visible, "Online map stops movement and clears destination marker")
	check(page.locations.size() == 79 and page.graph.get_node("Routes").get_child_count() == 78, "Online map uses full recovered world graph")
	var timer := view._key_timer
	var pending := view.network._pending_motion.duplicate(true)
	view._process(.2)
	check(timer == view._key_timer, "World map blocks online keyboard walking")
	view._map_input(mouse_event(Vector2(220,260),true))
	check(view.network._pending_motion == pending, "Clicks browsing world map cannot move the character underneath")
	await capture("online_world_map")
	page.select_location(4,true)
	var destination_point:=page.graph.position+page.location_point(4)
	page._map_input(mouse_event(destination_point,true));page._map_input(mouse_event(destination_point,false))
	check(page.travel_confirmation.visible and page.travel_confirm.disabled,"Unsynchronized online map click can show a prompt but cannot confirm consumption")
	var cancel_key:=InputEventKey.new();cancel_key.keycode=KEY_ESCAPE;cancel_key.pressed=true
	get_viewport().push_input(cancel_key,true)
	check(page.visible and not page.travel_confirmation.visible,"Escape only cancels the online prompt and preserves the world map")
	page.get_node("MainCity").pressed.emit()
	page.get_node("CurrentLocation").pressed.emit()
	check(page.selected_id==7,"Current-location control returns from browsing to the player's map")
	page.get_node("Footer/Back").pressed.emit()
	check(not page.visible and view.network.world_ready and view.chat_panel.get_instance_id() == chat_id and view.chat_input.text == "未发送的聊天草稿", "Return keeps current online session, shared chat and input draft")
	check(view.network.entities[SELF].cell == [6,18] and Game.player == offline, "Map browsing neither teleports online character nor changes offline state")
	var key := InputEventKey.new(); key.keycode = KEY_3; key.pressed = true
	view._unhandled_key_input(key)
	check(page.visible and page.selected_id==7, "Online three key opens at the player's current map")
	page._unhandled_key_input(key)
	check(not page.visible, "Three key returns from online world map")
	view._map_changed("qingyun_trail");view.network.entities[SELF].cell=[14,17]
	view._scene_action("map")
	check(page.selected_id==-1 and not page.selection.visible and not page.tooltip.visible,"Unlisted map never retains another location's selection")
	check(page.get_node("CurrentLocation").text=="当前位置：青云山道 (14,17) · 总图未标注","Unlisted map still shows its real name and live coordinates")
	page.present("ai_213",Vector2i(15,26))
	check(page.selected_id==-1 and page.get_node("CurrentLocation").text.contains("守方基地 (15,26)"),"Extended regions without overview nodes keep their own location context")
	view._close_world_map()
	view._scene_action("map")
	view._scene_action("properties")
	check(not page.visible and view.attributes.visible, "Online properties dismiss world map before opening")
	view.attributes.get_node("Back").pressed.emit()
	view._scene_action("map")
	view._open_expanded_chat()
	check(not page.visible and view.expanded_chat.visible, "Expanded chat does not overlap world map")
	view.expanded_chat.dismiss()
	view.network.pve.state = {"battle":{"outcome":"active"}}
	view._open_world_map()
	check(not page.visible, "Active battle cannot open field world map")
	view.network.pve.state = {}
	app.queue_free()
	await get_tree().process_frame
