extends "res://tests/loot_instances_test.gd"
var captures := ""

func capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name()=="headless":return
	for frame in 3:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(captures.path_join(name+".png"))==OK,"Capture "+name)

func open_details(bag: OriginalInventory, id: String) -> EquipmentDetails:
	for i in bag.items.size():
		if bag.items[i].get("instance_id",bag.items[i].id)==id:
			bag.select_item(i);bag.open_menu()
			for child in bag.item_menu.get_children():
				if child is Button and child.text=="查看":child.pressed.emit();break
			return bag.equipment_details
	return null

func page_text(detail: EquipmentDetails) -> String:
	var lines:Array[String]=[]
	for page in detail.pages:
		for row in page:lines.append(row.label+row.text)
	return "\n".join(lines)

func _run() -> void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path;var outbox:=OnlineAccount.pending_pve.duplicate(true)
	OnlineAccount.pending_pve={};Game.save_path="user://equipment_details_%d.json"%OS.get_process_id()
	Game.new_player("装备详情",0,3);Game.player.level=60;Game.player.gold=50000;Game.restore()
	var rolled:=LootRules.roll("ai/eva01/mzs/armor",60,"yellow",17);rolled.upgrade=4
	var other:=LootRules.roll(rolled.template,31,"yellow",29)
	var build:Dictionary=BuildRules.rules.items.filter(func(value:Dictionary)->bool:return int(value.job)==0)[0]
	var legend:=LootRules.roll_special("ai/eva01/mzs/"+build.legend_slot,60,"orange",build.id,31)
	Game.player.loot_state.items.append_array([rolled,other,legend])
	var before:=Game.player.duplicate(true)
	captures=OS.get_environment("SSJX_EQUIPMENT_DETAILS_CAPTURE")
	if not captures.is_empty():DirAccess.make_dir_recursive_absolute(captures)
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(bag)
	var detail:=open_details(bag,rolled.id)
	check(is_instance_valid(detail) and not bag.tooltip.visible and bag.item_menu==null,"Backpack View opens its own equipment paper instead of the tiny tooltip")
	check(detail.item.instance_id==rolled.id and detail.title.text==LootRules.bag_item(rolled).name,"Same-template items are identified by their owned UUID")
	var all_text:=page_text(detail)
	check(all_text.contains("4 / 6") and all_text.contains("双防 +75") and all_text.contains("气血 +194"),"Details show the actual upgraded base attributes")
	for affix in rolled.affixes:check(all_text.contains(LootRules.affix_text(affix)),"Every rolled affix is readable across pages")
	check(detail.pages.size()>=2 and detail.previous.disabled and not detail.next.disabled,"Long equipment data has real pagination")
	await capture("01-details")
	detail.next.pressed.emit();check(detail.page==1 and not detail.previous.disabled,"Next page exposes the remaining properties")
	await capture("02-details-page2")
	var index:=bag.selected_index;bag.select_item(0);check(bag.selected_index==index,"Modal inspection does not retarget the backpack behind it")
	check(Game.player==before and OnlineAccount.pending_pve.is_empty(),"Reading and paging never mutate equipment or send commands")
	detail.back.pressed.emit();check(bag.equipment_details==null and bag._selected().instance_id==rolled.id,"Return retains the inspected backpack item")
	detail=open_details(bag,legend.id)
	check(page_text(detail).contains(build.legend_name) and page_text(detail).contains(build.description),"Legendary effects are included rather than clipped from the tiny tooltip")
	detail._turn_page(detail.pages.size()-1);await capture("03-legendary")
	detail.back.pressed.emit()
	detail=open_details(bag,"sword")
	check(not detail.item.has("instance_id") and detail.meta.text.contains("固定") and page_text(detail).contains("无随机词条"),"Fixed shop equipment uses its catalog properties without fabricated affixes")
	check(not detail.title.text.contains("绑"),"A binding flag is not invented for equipment without binding data")
	await capture("04-fixed")
	await get_tree().process_frame
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape);Input.flush_buffered_events();await get_tree().process_frame
	check(bag.equipment_details==null and is_instance_valid(bag),"Escape dismisses the detail layer before the backpack")
	bag.queue_free();await get_tree().process_frame
	var fixture=load("res://tests/online_pve_test.gd").new();var model:=OnlinePve.new()
	model.character_id=fixture.SELF;model.ready=true;model.state=fixture.pve_state()
	model.state.character.job=0;model.state.character.level=60
	model.state.shop=ShopRules.local_state(Game.player);model.state.loot={"state":Game.player.loot_state.duplicate(true),"progression_sha256":ProgressionRules.catalog_hash}
	bag=load("res://scenes/ui/inventory.tscn").instantiate();bag.online_model=model;add_child(bag)
	detail=open_details(bag,other.id)
	model.state.loot.state.items.reverse();model.changed.emit()
	check(detail.item.instance_id==other.id and int(detail.item.level)==31,"Authoritative row reorder cannot replace the inspected instance")
	for value in model.state.loot.state.items:
		if value.id==other.id:value.upgrade=2
	model.changed.emit();check(page_text(detail).contains("2 / 6"),"An authoritative update refreshes the currently inspected item")
	model.ready=false;model.changed.emit();check(detail.meta.text.contains("离线快照"),"Disconnected inspection labels its last known snapshot")
	model.state.loot.state.items=model.state.loot.state.items.filter(func(value:Dictionary)->bool:return value.id!=other.id)
	model.changed.emit();check(detail.item.is_empty() and detail.meta.text.contains("已不在"),"Removed equipment does not fall back to another copy of its template")
	await capture("05-removed")
	check(Game.player==before and OnlineAccount.pending_pve.is_empty(),"Online viewing preserves offline progress and the command outbox")
	bag.queue_free();fixture.free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.player=old;Game.save_path=old_path;OnlineAccount.pending_pve=outbox
	print("EQUIPMENT DETAILS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
