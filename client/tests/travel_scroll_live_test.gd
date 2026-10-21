extends "res://tests/online_maps_live_test.gd"

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
	bag.use_item();check(is_instance_valid(bag.travel_picker) and bag.travel_picker.allow_ruins,"Online use opens available destination picker")
	bag.travel_picker.back_requested.emit()
	check(ShopRules.quantity(view.network.pve.state.shop,ShopRules.TRAVEL_SCROLL)==2 and not view.network.pve.pending(),"Online cancel does not submit or consume")
	for destination in ["ai_021","qingyun_trail"]:
		if not is_instance_valid(view.backpack):view._open_inventory()
		bag=view.backpack
		for i in bag.items.size():
			if bag.items[i].id==ShopRules.TRAVEL_SCROLL:bag.select_item(i)
		bag.use_item();bag.travel_picker.selected_map=destination;bag.travel_picker.refresh()
		for child in bag.travel_picker.body.get_children():
			if child is Button and child.text=="消耗1张并传送":child.pressed.emit();break
		check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id==destination and not view.map_transition.blocking),"Real confirm button completes talisman map change")
		check(view.map_data.map_id==destination and view.network.pve.state.character.map_id==destination,"World and authoritative character agree on destination")
	check(ShopRules.quantity(view.network.pve.state.shop,ShopRules.TRAVEL_SCROLL)==0 and view.network.pve.state.character.gold==240,"Exactly two selections consume two talismans without extra charge")
	check(Game.player==before,"Online travel never writes the offline player")
	view.network.leave();view.queue_free();await get_tree().process_frame;OnlineAccount.clear()
	print("TRAVEL SCROLL LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
