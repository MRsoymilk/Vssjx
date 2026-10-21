extends "res://tests/online_pve_test.gd"
class RejectWrites extends "res://scripts/interface/adapters/native/native_storage.gd":
	func write(_path:String,_text:String)->PlatformStorageRequest:
		return PlatformStorageRequest.resolved(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"WRITE_FAILED","测试保存失败"))
class ActiveBattle extends RefCounted:
	func active()->bool:return true

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
	bag.use_item()
	check(is_instance_valid(bag.travel_picker) and not bag.travel_picker.allow_ruins and Game.player==purchased,"Use opens destination selection at full HP without consuming or unlocking ruins")
	bag.travel_picker.back_requested.emit()
	check(Game.player==purchased and not is_instance_valid(bag.travel_picker),"Cancel consumes nothing and closes picker")
	bag.use_item();bag.travel_picker.selected_map="ai_004";bag.travel_picker.refresh()
	output=OS.get_environment("SSJX_SCROLL_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	await capture("scroll-destination")
	bag.travel_picker.requested.emit("scroll_travel","ai_004")
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
