extends "res://tests/online_maps_live_test.gd"

func click_location(page:OriginalWorldMap,id:int)->void:
	page.select_location(id,true)
	var point:=page.graph.position+page.location_point(id)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=down
		page.map_area.gui_input.emit(event)

func _run()->void:
	var before:=Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_SCROLL_TEST_BASE"),"scroll_ui","owned-scroll-password-1234")
	await OnlineAccount.completed
	OnlineAccount.list_characters();await OnlineAccount.completed
	check(not OnlineAccount.characters.is_empty(),"Owned talisman account loads")
	if OnlineAccount.characters.is_empty():get_tree().quit(1);return
	view=load("res://scenes/ui/online_world_view.tscn").instantiate();view.character_id=OnlineAccount.characters[0].id;add_child(view)
	check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready),"Online map synchronizes")
	view._open_shop();view.shop.section="rare";view.shop.category="特殊";view.shop.selected=ShopRules.TRAVEL_SCROLL;view.shop._filter()
	check(view.shop.goods.any(func(i:Dictionary)->bool:return i.id==ShopRules.TRAVEL_SCROLL),"Actual online rare shop lists talisman")
	view.shop.quantity_box.value=2;view.shop.buy_button.pressed.emit()
	check(await wait_until(func()->bool:return not view.network.pve.pending() and ShopRules.quantity(view.network.pve.state.shop,ShopRules.TRAVEL_SCROLL)==2),"Actual shop purchase credits two talismans")
	view._close_inventory();view._open_inventory()
	var bag:OriginalInventory=view.backpack
	for i in bag.items.size():
		if bag.items[i].id==ShopRules.TRAVEL_SCROLL:bag.select_item(i)
	bag.open_menu()
	check(not bag.item_menu.get_children().any(func(n:Node)->bool:return n is Button and n.text=="使用"),"Online backpack removes the talisman directory use entry")
	view._close_inventory();view._scene_action("map")
	var page:OriginalWorldMap=view.world_map
	check(page.get_node("Footer/TravelCount").text=="2","Map reads the real server-owned talisman count")
	click_location(page,21)
	check(page.travel_confirmation.visible and not page.travel_confirm.disabled and not view.network.pve.pending(),"Online map click prompts before submitting any consume operation")
	page.get_node("TravelConfirmation/Panel/Cancel").pressed.emit()
	check(ShopRules.quantity(view.network.pve.state.shop,ShopRules.TRAVEL_SCROLL)==2 and not view.network.pve.pending() and page.visible,"Online cancel keeps map open without submission or consumption")
	for destination in ["ai_021","ai_004"]:
		if not page.visible:view._scene_action("map")
		click_location(page,int(destination.right(3)))
		page.travel_confirm.pressed.emit();page.travel_confirm.pressed.emit()
		check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id==destination and not view.map_transition.blocking),"Real confirm button completes talisman map change")
		check(view.map_data.map_id==destination and view.network.pve.state.character.map_id==destination,"World and authoritative character agree on destination")
	check(ShopRules.quantity(view.network.pve.state.shop,ShopRules.TRAVEL_SCROLL)==0 and view.network.pve.state.character.gold==240,"Exactly two selections consume two talismans without extra charge")
	view._scene_action("map");click_location(page,21)
	check(page.get_node("Footer/TravelCount").text=="0" and page.travel_confirm.disabled and not view.network.pve.pending(),"Exhausted authoritative inventory disables map confirmation")
	check(Game.player==before,"Online travel never writes the offline player")
	view.network.leave();view.queue_free();await get_tree().process_frame;OnlineAccount.clear()
	print("TRAVEL SCROLL LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
