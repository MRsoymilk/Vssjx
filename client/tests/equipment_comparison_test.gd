extends "res://tests/equipment_details_test.gd"
const Comparison = preload("res://scripts/equipment_comparison.gd")

func wait_storage() -> void:
	for frame in 120:
		if not Game.storage_busy:return
		await get_tree().process_frame

func click(control: Control, touch: bool = false) -> void:
	await get_tree().process_frame
	var point:=get_viewport().get_final_transform()*control.get_global_rect().get_center()
	var event:InputEvent
	if touch:event=InputEventScreenTouch.new();event.position=point;event.pressed=true
	else:event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events()
	var release:=event.duplicate();release.pressed=false;Input.parse_input_event(release);Input.flush_buffered_events()
	for frame in 3:await get_tree().process_frame

func state_for(fixture: Node, player: Dictionary, revision: int) -> Dictionary:
	var state:Dictionary=fixture.pve_state(revision)
	for key in ["job","gender","school","level","gold","hp","mp"]:state.character[key]=player[key]
	state.stats=CharacterAttributeRules.local_stats(player)
	state.shop=ShopRules.local_state(player);state.shop.catalog_sha256=ShopRules.catalog_hash
	state.equipment={"version":"equipment-v1","weapon_owned":player.weapon_owned,"weapon":"sword" if state.shop.weapon=="sword" else null}
	state.loot={"version":"loot-v1","state":player.loot_state.duplicate(true),"appearance":LootRules.look(player.loot_state,ShopRules.appearance(state.shop)),"progression_sha256":ProgressionRules.catalog_hash}
	return state

func receipt(model: OnlinePve, state: Dictionary) -> Dictionary:
	return {"type":"pve.result","state":state,"operation_id":OnlineAccount.pending_pve.command.operation_id,"ok":true,"code":"OK","replayed":false,"lines":[]}

func _run() -> void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path;var outbox:=OnlineAccount.pending_pve.duplicate(true);var characters:=OnlineAccount.characters.duplicate(true)
	OnlineAccount.pending_pve={};Game.save_path="user://equipment_comparison_%d.json"%OS.get_process_id()
	Game.new_player("装备对比",0,3);Game.player.level=60;Game.player.gold=50000
	Game.player.loot_state.scrap=1000;Game.player.loot_state.essence=100;Game.restore()
	var current:=LootRules.roll("ai/eva01/mzs/weapon",60,"yellow",17)
	current.affixes=[{"kind":"power","value":30},{"kind":"crit","value":30},{"kind":"damage","value":400},{"kind":"hit","value":20}]
	var candidate:=LootRules.roll(current.template,60,"yellow",29);candidate.upgrade=2
	candidate.affixes=[{"kind":"power","value":50},{"kind":"crit","value":20},{"kind":"damage","value":800},{"kind":"penetration","value":300}]
	Game.player.loot_state.items.append_array([current,candidate])
	check(LootRules.valid_item(current,0,0) and LootRules.valid_item(candidate,0,0),"Comparison fixtures are legal same-template owned copies")
	check((await Game.loot_command("gear_equip",current.id)).ok,"The comparison starts from a genuinely equipped item")
	captures=OS.get_environment("SSJX_EQUIPMENT_DETAILS_CAPTURE")
	if not captures.is_empty():DirAccess.make_dir_recursive_absolute(captures)
	var bag:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(bag)
	var detail:=open_details(bag,candidate.id)
	await click(detail.compare_button,true)
	check(detail.comparing and detail.comparison_view.visible and not detail.detail_view.visible,"Touch opens comparison inside the existing backpack detail")
	var rows:=detail.comparison_rows
	check(rows.any(func(row:Dictionary)->bool:return row.kind=="power" and row.current==158 and row.selected==183 and row.delta==25),"Upgraded base and flat power affix are summed once, with the correct delta")
	check(rows.any(func(row:Dictionary)->bool:return row.kind=="crit" and row.delta==-10),"Lower ratings are a decrease rather than an improvement")
	check(rows.any(func(row:Dictionary)->bool:return row.kind=="hit" and row.selected==0 and row.delta==-20),"Lost affixes remain visible as zero and a decrease")
	check(rows.any(func(row:Dictionary)->bool:return row.kind=="penetration" and row.current==0 and row.delta==300),"New affixes compare against zero")
	check(rows.any(func(row:Dictionary)->bool:return row.kind=="damage" and row.change=="增加4.00个百分点"),"Percentage affixes compare in percentage points")
	check(Comparison.rows({},LootRules.bag_item(candidate),2).any(func(row:Dictionary)->bool:return row.kind=="power" and row.label=="法术攻击"),"Caster main attack is labelled correctly")
	check(rows[0].kind=="score" and rows[0].current==116 and rows[0].selected==141 and rows[0].delta==25,"Comparison leads with actual equipment scores and their difference")
	check(Comparison.values(ShopRules.bag_item("sword")).power==5,"Fixed shop equipment has the actual catalog contribution")
	await capture("06-comparison")
	var before:=Game.player.duplicate(true)
	var context:=Platform.context;var storage:=DELAYED.new()
	Platform.context=PlatformContext.new("equipment-detail-save",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	detail.equip_selected();detail.equip_selected()
	check(Game.storage_busy and storage.operations.size()==1 and detail.equip_button.disabled,"Rapid equip clicks submit only one durable operation")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试写入失败"));await get_tree().process_frame
	check(Game.player==before and not detail._worn(detail.item) and detail.operation_message.contains("失败"),"Failed equip rolls back inventory and leaves comparison on the same item")
	detail.equip_selected();detail.back.pressed.emit()
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","关闭后写入失败"))
	for frame in 3:await get_tree().process_frame
	check(Game.player==before and bag.items.any(func(entry:Dictionary)->bool:return entry.get("instance_id")==candidate.id) and not bag.selected_equipment and bag._selected().get("instance_id")==candidate.id,"Closing the detail during a failed save restores the real backpack and the original selected UUID")
	Platform.context=context
	bag.refresh();detail=open_details(bag,candidate.id);detail.show_comparison()
	await detail.equip_selected()
	check(LootRules.equipped(Game.player.loot_state,"weapon").id==candidate.id and detail.equip_button.disabled,"Compare equips the selected UUID rather than the other identical template")
	check(detail.comparison_rows.all(func(row:Dictionary)->bool:return row.delta==0),"After equipping, comparison refreshes against the new current item")
	check(detail.score_change.text=="已穿戴" and detail.score_label.text=="141","Equipping refreshes both the detail score and its worn-state caption")
	detail.show_details();detail._turn_page(1);var original_page:=detail.page
	var gold:=int(Game.player.gold);await click(detail.craft_button)
	var crafting:=detail.crafting
	check(is_instance_valid(crafting) and crafting.selected_id==candidate.id and crafting.from_details and crafting.back.text=="返回详情","Detail opens crafting directly with the exact selected equipment")
	check(Game.player.gold==gold and OnlineAccount.pending_pve.is_empty(),"Navigation to crafting never charges or sends a mutation")
	await capture("07-direct-crafting")
	var original_affixes:Array=crafting._item().affixes.duplicate(true)
	var quote:=ProgressionRules.quote(crafting._item(),"gear_reroll")
	crafting.affix.select(1);crafting.affix.item_selected.emit(1);crafting.reroll.pressed.emit()
	check(Game.player.gold==gold and int(crafting._item().get("rerolls",0))==0,"First wash click only asks for the existing confirmation")
	crafting.reroll.pressed.emit();await wait_storage();crafting.refresh()
	var washed:Dictionary=crafting._item().duplicate(true)
	check(washed.reroll_index==1 and int(washed.rerolls)==1 and int(Game.player.gold)==gold-int(quote.cost[0]),"Confirmed washing spends the quoted amount and locks the selected affix")
	for i in [0,2,3]:check(washed.affixes[i]==original_affixes[i],"Washing preserves the unselected affix")
	await get_tree().process_frame
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	Input.parse_input_event(escape);Input.flush_buffered_events();await get_tree().process_frame
	check(detail.crafting==null and bag.equipment_details==detail and detail.detail_view.visible and detail.page==original_page,"Escape from crafting returns one level and retains the detail page")
	check(page_text(detail).contains(LootRules.affix_text(washed.affixes[1])) and page_text(detail).contains("已锁定第2条"),"Returning refreshes actual washed attributes and lock information")
	check(detail.score_label.text==str(LootRules.score(washed)),"Confirmed paid washing refreshes the score from the actual saved attributes")
	detail.open_crafting();check(detail.crafting.affix.selected==1 and detail.crafting.affix.disabled,"Reopening retains the persisted locked affix")
	detail.crafting.back.pressed.emit();detail.back.pressed.emit()
	check(bag.selected_equipment and bag.selected_slot=="weapon" and bag._selected().instance_id==candidate.id,"Returning to the backpack selects the item now in the equipment slot")
	var plain:=LootRules.roll(candidate.template,1,"white",5);Game.player.loot_state.items.append(plain);bag.refresh()
	detail=open_details(bag,plain.id)
	check(detail.craft_button.disabled and not detail.craft_button.tooltip_text.is_empty(),"Equipment without affixes explains its disabled wash entry")
	detail.open_crafting();check(detail.crafting==null,"A forced click cannot bypass the no-affix restriction")
	detail.show_comparison();check(detail._current_item().instance_id==candidate.id,"Empty or weak candidates still compare against the real equipped instance")
	await capture("08-white-comparison")
	detail.show_details();detail.back.pressed.emit()
	detail=open_details(bag,"sword");check(detail.craft_button.disabled,"Fixed catalog gear cannot enter paid reroll")
	detail.back.pressed.emit()
	var spare:=LootRules.roll(candidate.template,60,"blue",7);Game.player.loot_state.items.append(spare);bag.refresh()
	detail=open_details(bag,spare.id);detail.open_crafting();detail.crafting.salvage.pressed.emit();detail.crafting.salvage.pressed.emit();await wait_storage()
	detail.crafting.back.pressed.emit()
	check(detail.item.is_empty() and detail.compare_button.disabled and detail.craft_button.disabled,"Salvaging the inspected item clears its detail and all item actions")
	detail.back.pressed.emit()
	var build:Dictionary=BuildRules.rules.items.filter(func(value:Dictionary)->bool:return int(value.job)==0)[0]
	var legend:=LootRules.roll_special("ai/eva01/mzs/"+build.legend_slot,60,"orange",build.id,31)
	Game.player.loot_state.items.append(legend);bag.refresh();detail=open_details(bag,legend.id);detail.show_comparison()
	check(detail.current_name.text=="未穿戴" and detail.comparison_rows.all(func(row:Dictionary)->bool:return row.current==0),"An empty equipment slot compares against zero without reusing another slot's stats")
	check(detail.comparison_content.get_children().any(func(node:Node)->bool:return node is Label and node.text.contains(build.description)),"Legendary effects remain readable text instead of being folded into a misleading stat total")
	var set_item:=LootRules.roll_special("ai/eva01/mzs/armor",60,"green",build.id,33)
	check(Comparison.special(LootRules.bag_item(set_item)).contains(BuildRules.two_text(build)),"Set comparisons include their two-piece properties as well as their effect description")
	detail.comparison_scroll.scroll_vertical=10000;await capture("09-special-comparison")
	bag.queue_free();await get_tree().process_frame
	var offline:=Game.player.duplicate(true);var remote:=Game.player.duplicate(true)
	var fixture=load("res://tests/online_pve_test.gd").new();var model:=OnlinePve.new();model.character_id=fixture.SELF
	check(model.receive({"type":"pve.state","state":state_for(fixture,remote,1)}),"Online UI starts from a fully validated equipment snapshot")
	var packets:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:packets.append(packet))
	bag=load("res://scenes/ui/inventory.tscn").instantiate();bag.online_model=model;add_child(bag)
	detail=open_details(bag,current.id);detail.show_comparison();detail.equip_button.pressed.emit();detail.equip_button.pressed.emit()
	check(packets.size()==1 and packets[0].command.action=="gear_equip" and packets[0].command.target==current.id and packets[0].command.expected_revision=="1","Online compare sends one UUID and authoritative revision")
	check(packets[0].command.size()==4 and detail.equip_button.disabled and detail.compare_craft.disabled,"Online request contains no client-computed stats and locks pending actions")
	check(LootRules.apply_local(remote,"gear_equip",current.id).is_empty(),"Prepare the authoritative equip response")
	check(model.receive(receipt(model,state_for(fixture,remote,2))) and detail._worn(detail.item),"Authoritative equip response refreshes the comparison")
	detail.show_details();detail.open_crafting();crafting=detail.crafting
	crafting.affix.select(1);crafting.affix.item_selected.emit(1);crafting.reroll.pressed.emit()
	check(packets.size()==1,"First online wash click sends no command")
	crafting.reroll.pressed.emit()
	check(packets.size()==2 and packets[1].command.action=="gear_reroll" and packets[1].command.target==current.id and packets[1].command.quantity==2,"Direct online washing retains the target UUID and chosen affix index")
	check(ProgressionRules.craft(remote,current.id,"gear_reroll",1,77).is_empty(),"Prepare the authoritative reroll response")
	check(model.receive(receipt(model,state_for(fixture,remote,3))),"Authoritative washed equipment passes the normal protocol validator")
	crafting.back.pressed.emit();check(page_text(detail).contains("已锁定第2条") and detail.item.instance_id==current.id,"Online return reads the server's changed affix on the same equipment")
	var server_item:Dictionary=remote.loot_state.items.filter(func(value:Dictionary)->bool:return value.id==current.id)[0]
	check(detail.score_label.text==str(LootRules.score(server_item)),"Online score follows the authoritative reroll response without changing offline progress")
	model.ready=false;model.changed.emit();detail.show_comparison()
	check(detail.equip_button.disabled and detail.compare_craft.disabled,"Disconnected snapshots remain readable with mutation controls locked")
	model.ready=true;model.state.character.corpse={"id":"test"};model.changed.emit()
	check(detail.craft_button.disabled and detail.equip_button.disabled,"Soul state cannot enter equipment mutations through the new UI")
	model.state.character.erase("corpse");model.changed.emit();detail.back.pressed.emit()
	detail=open_details(bag,"sword");detail.show_comparison();detail.equip_selected()
	check(packets.size()==3 and packets[2].command.action=="equip" and packets[2].command.target=="sword","Fixed equipment uses its existing shop command rather than a fabricated instance ID")
	OnlineAccount.pending_pve={};model.character_id="another-character";model.changed.emit();detail.equip_selected();detail.open_crafting()
	check(detail.item.is_empty() and packets.size()==3 and detail.crafting==null,"A changed character binding cannot reuse the old equipment target")
	check(Game.player==offline,"Online comparison and paid operations never install an offline player")
	bag.queue_free();fixture.free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.player=old;Game.save_path=old_path;OnlineAccount.pending_pve=outbox;OnlineAccount.characters=characters
	print("EQUIPMENT COMPARISON: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
