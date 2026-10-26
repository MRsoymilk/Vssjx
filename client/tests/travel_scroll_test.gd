extends "res://tests/online_pve_test.gd"
class RejectWrites extends "res://scripts/interface/adapters/native/native_storage.gd":
	func write(_path:String,_text:String)->PlatformStorageRequest:
		return PlatformStorageRequest.resolved(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"WRITE_FAILED","测试保存失败"))
class ActiveBattle extends RefCounted:
	func active()->bool:return true

func click_location(page:OriginalWorldMap,id:int,touch:bool=false)->void:
	page.select_location(id,true)
	var point:=page.graph.position+page.location_point(id)*page.zoom_level
	for down in [true,false]:
		if touch:
			var event:=InputEventScreenTouch.new();event.index=0;event.position=point;event.pressed=down
			page.map_area.gui_input.emit(event)
		else:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.pressed=down
			page.map_area.gui_input.emit(event)

func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var storage:=Platform.context.storage
	var outbox:=OnlineAccount.pending_pve.duplicate(true);OnlineAccount.pending_pve={}
	Game.save_path="user://travel_scroll_%d.json"%OS.get_process_id()
	Game.new_player("神行符验证",0,3);Game.player.gold=300
	output=OS.get_environment("SSJX_SCROLL_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	var item:=ShopRules.item(ShopRules.TRAVEL_SCROLL)
	check(item.name=="神行符" and item.price==30 and item.sections.has("rare") and item.effect=="teleport","Catalog sells a typed travel talisman in the rare shop")
	var shop:ShopPanel=load("res://scenes/ui/shop_panel.tscn").instantiate();shop.section="rare";shop.category="特殊";shop.selected=item.id;add_child(shop)
	check(shop.goods.any(func(i:Dictionary)->bool:return i.id==item.id),"Actual rare shop includes the talisman")
	shop.quantity_box.value=3;shop.buy_button.pressed.emit()
	check(Game.player.gold==210 and ShopRules.quantity(ShopRules.local_state(Game.player),item.id)==3,"Shop purchase stacks talismans and deducts exact copper")
	await capture("scroll-shop");shop.free()
	var purchased:=Game.player.duplicate(true)
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world();app._scene_action("bag")
	var bag:OriginalInventory=app.backpack
	bag.select_item(bag.items.find(bag.items.filter(func(i:Dictionary)->bool:return i.id==item.id)[0]))
	bag.open_menu()
	check(not bag.item_menu.get_children().any(func(n:Node)->bool:return n is Button and n.text=="使用"),"Talisman backpack menu no longer offers the removed directory use action")
	bag.use_item()
	check(not bag.has_node("TravelPicker") and bag.description.text.contains("地图") and Game.player==purchased,"Direct backpack use only explains map entry and cannot open a directory or spend")
	app._close_modal()
	app._scene_action("map")
	var page:OriginalWorldMap=app.modal
	check(page.get_node("Footer/TravelCount").text=="3" and not app.world.enabled,"Map shows purchased talisman stock and pauses local movement")
	page.set_zoom(1.5)
	click_location(page,4)
	check(page.travel_confirmation.visible and page.travel_destination=="ai_004" and not page.travel_confirm.disabled and Game.player==purchased,"Map click opens destination confirmation without consuming")
	output=OS.get_environment("SSJX_SCROLL_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	await capture("scroll-map-confirmation")
	page.get_node("TravelConfirmation/Panel/Cancel").pressed.emit()
	check(Game.player==purchased and not page.travel_confirmation.visible and app.modal==page,"Cancel keeps the map open and consumes nothing")
	page.set_zoom(.75)
	click_location(page,4,true)
	check(page.travel_confirmation.visible and page.travel_destination=="ai_004","Touching a destination uses the same confirmation")
	Platform.context._storage=RejectWrites.new()
	page.travel_confirm.pressed.emit()
	await Game.wait_for_storage()
	check(Game.player==purchased and app.modal==page and not page.travel_busy and not page.travel_confirm.disabled and not page.travel_notice.is_empty(),"Failed map confirmation restores stock and allows retry on the same dialog")
	Platform.context._storage=storage
	page.travel_confirm.pressed.emit()
	await Game.wait_for_storage()
	check(app.world.map_id=="ai_004" and Game.player.cell==SharedWorldMap.load_data("ai_004").spawn and ShopRules.quantity(ShopRules.local_state(Game.player),item.id)==2,"Confirmation directly reaches chosen map and consumes exactly one")
	check(Game.player.hp==purchased.hp and Game.player.mp==purchased.mp and Game.player.gold==210,"Travel does not heal or charge extra copper")
	await capture("scroll-arrival")
	check((await Game.load_game()).ok and Game.player.ai_map=="ai_004" and ShopRules.quantity(ShopRules.local_state(Game.player),item.id)==2,"Arrival and consumed stock reload together")
	var before:=Game.player.duplicate(true)
	for destination in ["ai_004","ancient_ruins","ai_999"]:
		check(not (await Game.shop_command("scroll_travel",destination)).ok and Game.player==before,"Current, locked and unknown destinations never consume: "+destination)
	check((await Game.shop_command("use",item.id)).code=="TRAVEL_DESTINATION_REQUIRED" and Game.player==before,"Direct use without a destination cannot silently consume")
	Platform.context._storage=RejectWrites.new()
	var raw:=FileAccess.get_file_as_string(Game.save_path)
	check(not (await Game.shop_command("scroll_travel","ai_032")).ok and Game.player==before and FileAccess.get_file_as_string(Game.save_path)==raw,"Write failure rolls back both stock and location")
	Platform.context._storage=storage
	var combat:=ActiveBattle.new();var previous_combat:Variant=Game.local_combat;Game.local_combat=weakref(combat)
	check((await Game.shop_command("scroll_travel","ai_032")).code=="BATTLE_ACTIVE" and Game.player==before,"Active battle blocks item travel")
	Game.local_combat=previous_combat
	Game.become_soul();var soul:=Game.player.duplicate(true)
	check((await Game.shop_command("scroll_travel","ai_032")).code=="SOUL_STATE" and Game.player==soul,"Soul state cannot use item travel")
	Game.player=before.duplicate(true)
	check((await Game.shop_command("scroll_travel","qingyun_trail")).ok and Game.player.ai_map.is_empty() and ShopRules.quantity(ShopRules.local_state(Game.player),item.id)==1,"Return to original map consumes one and clears AI map marker")
	check((await Game.shop_command("scroll_travel","ai_032")).ok and not ShopRules.local_state(Game.player).owned.has(item.id),"Last talisman is removed without a zero-count stack")
	check((await Game.shop_command("scroll_travel","ai_021")).code=="TRAVEL_SCROLL_REQUIRED","No stock cannot teleport")
	app._enter_world();app._scene_action("map");page=app.modal
	click_location(page,21)
	check(page.travel_confirmation.visible and page.travel_confirm.disabled and page.get_node("Footer/TravelCount").text=="0","Map confirmation explains empty stock and disables consumption")
	page.travel_confirm.pressed.emit()
	check(AIWorld.local_map_id()=="ai_032","Even an emitted disabled confirmation cannot teleport without stock")
	page.cancel_travel();click_location(page,32)
	check(page.travel_confirm.disabled and page.get_node("TravelConfirmation/Panel/Status").text==OnlinePve.error_text("AI_SAME_MAP"),"Clicking current map cannot consume a talisman")
	app._close_modal()
	Game.player=purchased.duplicate(true);Game.player.quest=3
	check((await Game.shop_command("scroll_travel","ancient_ruins")).ok and Game.player.zone==1 and Game.player.ai_map.is_empty(),"Unlocked original ruins are valid destinations")
	app.free()
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:1");model.state=pve_state();model.ready=true
	model.state.shop=ShopRules.local_state(purchased);model.state.shop.catalog_sha256=ShopRules.catalog_hash
	var packets:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:packets.append(packet))
	check(model.submit("scroll_travel","ai_021") and packets[0].command.target=="ai_021" and packets[0].command.expected_revision==model.state.character.state_revision,"Online command sends destination and authoritative revision through durable outbox")
	check(not model.submit("scroll_travel","ai_032"),"Unknown result blocks a second consume operation")
	OnlineAccount.pending_pve={};DirAccess.remove_absolute(Game.save_path)
	Game.player=old;Game.save_path=path;OnlineAccount.pending_pve=outbox
	print("TRAVEL SCROLL: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
