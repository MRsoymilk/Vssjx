extends "res://tests/loot_instances_test.gd"
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	for frame in 3:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png("res://../work/crafting-"+name+".png")==OK,"Capture "+name)
func wait_storage()->void:
	for frame in 120:
		if not Game.storage_busy:return
		await get_tree().process_frame
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path;var combat:=Game.local_combat;var outbox:=OnlineAccount.pending_pve.duplicate(true)
	Game.local_combat=null;OnlineAccount.pending_pve={};Game.save_path="user://crafting_layout_%d.json"%OS.get_process_id()
	Game.new_player("养成布局",0,3);Game.player.level=60;Game.player.gold=5000;Game.player.loot_state.scrap=1000;Game.player.loot_state.essence=100;Game.restore()
	var item:=LootRules.roll("ai/eva01/mzs/weapon",27,"yellow",17);Game.player.loot_state.items.append(item)
	var inventory:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(inventory);inventory.open_loot();inventory.loot_panel.selected_id=item.id;inventory.loot_panel.open_crafting()
	var panel:CraftingPanel=inventory.loot_panel.get_node("CraftingPanel")
	await get_tree().process_frame
	for badge in panel.materials.get_children():
		for child in badge.get_children():
			if child is TextureRect:check(child.size.x<=13 and child.size.y<=13,"Resource icon stays inside its badge without covering the amount")
	check(panel.paper.get_rect()==Rect2(12,57,296,372),"Crafting frame covers the same original equipment window without green edges peeking through")
	check(panel.item_name.text==LootRules.bag_item(item).name and panel.item_icon.texture!=null,"Selected item remains identifiable above the scroll area")
	check(not panel.details.text.contains("编号") and not panel.details.text.contains("铜／"),"Scrollable properties contain equipment information instead of technical IDs or buried operation costs")
	check(panel.upgrade_cost.text.contains("54铜") and panel.upgrade_cost.text.contains("10炼材"),"All upgrade costs remain directly below their action")
	check(panel.affix.get_popup().theme==panel.theme and not panel.affix.get_popup().prefer_native_menu,"Affix popup uses the game's gold paper theme")
	check(panel.focus.get_popup().theme==panel.theme and not panel.focus.get_popup().prefer_native_menu,"Directed-drop popup uses the same theme")
	for control in [panel.affix,panel.focus,panel.reroll,panel.upgrade,panel.salvage,panel.back,panel.detail_scroll]:
		check(panel.paper.get_rect().encloses(control.get_rect()),"Interactive control stays inside the original frame: "+control.name)
	check(panel.detail_scroll.get_rect().end.y<panel.affix.position.y and panel.affix.get_rect().end.y<panel.upgrade.position.y,"Scrollable details and selector never overlap action buttons")
	check(panel.upgrade.get_rect().end.y<panel.upgrade_cost.position.y and panel.upgrade_cost.get_rect().end.y<panel.focus.position.y,"Cost labels have their own row between action groups")
	await shot("ready")
	if DisplayServer.get_name()!="headless":
		panel.focus.get_popup().popup(Rect2i(164,175,134,210));await shot("dropdown")
		check(panel.focus.get_popup().visible and panel.focus.get_popup().size.y<=210,"Long category popup stays within the themed viewport-sized menu")
		panel.focus.get_popup().hide()
	var before_gold:=int(Game.player.gold);panel.upgrade.pressed.emit()
	check(Game.player.gold==before_gold and not panel.confirmation.is_empty(),"First upgrade click only requests confirmation")
	await shot("confirm")
	check(panel.status.get_rect().end.y<=panel.back.position.y,"Long confirmation text remains above the footer")
	panel.upgrade.pressed.emit();await wait_storage();panel.refresh()
	check(panel._item().upgrade==1 and int(Game.player.gold)==before_gold-54,"Confirmed upgrade still saves the selected instance and exact quoted price")
	panel.affix.select(1);panel.affix.item_selected.emit(1);panel.reroll.pressed.emit();panel.reroll.pressed.emit();await wait_storage();panel.refresh()
	check(panel._item().reroll_index==1 and panel.affix.disabled,"Confirmed reroll locks only the selected slot")
	Game.player.loot_state.scrap=0;panel.refresh()
	check(panel.upgrade.disabled and panel.reroll.disabled and panel.upgrade.tooltip_text.contains("炼材不足"),"Disabled actions explain the missing resource")
	await shot("insufficient")
	Game.player.loot_state.scrap=1000
	panel.focus.select(1);panel.focus.item_selected.emit(1);await wait_storage();panel.refresh()
	check(Game.player.loot_state.focus=="weapon","Original directed-drop action still persists")
	Game.player.gold=2147483647;Game.player.loot_state.scrap=1000000000;Game.player.loot_state.essence=1000000000;panel.refresh();await get_tree().process_frame
	check(panel.resource_counts.all(func(label:Label)->bool:return label.get_rect().end.x<=88),"Maximum resource amounts fit their three separate badges")
	await shot("large-resources")
	var plain:=LootRules.roll(item.template,1,"white",1);Game.player.loot_state.items.append(plain);panel.selected_id=plain.id;panel.refresh()
	check(panel.affix.disabled and panel.reroll.disabled and panel.affix.get_item_text(0).contains("没有随机词条"),"White equipment has a meaningful disabled selector")
	panel.salvage.pressed.emit();check(Game.player.loot_state.items.any(func(i:Dictionary)->bool:return i.id==plain.id),"First salvage click cannot remove equipment")
	panel.salvage.pressed.emit();await wait_storage();panel.refresh()
	check(not Game.player.loot_state.items.any(func(i:Dictionary)->bool:return i.id==plain.id),"Second salvage click removes exactly the confirmed item and clears its preview")
	panel.selected_id="missing";panel.refresh()
	check(panel.item_icon.texture==null and panel.upgrade.disabled and panel.reroll.disabled and panel.salvage.disabled,"Missing or removed equipment clears the old preview and actions")
	await shot("empty")
	panel.selected_id=item.id;panel.refresh();Game.player.loot_state.items.filter(func(i:Dictionary)->bool:return i.id==item.id)[0].equipped=true;panel.refresh()
	check(panel.salvage.disabled and panel.salvage.tooltip_text.contains("卸下"),"Worn equipment retains the salvage protection")
	panel.back.pressed.emit();check(panel.is_queued_for_deletion() and is_instance_valid(inventory.loot_panel),"Return closes only crafting and keeps the equipment list")
	inventory.queue_free();await get_tree().process_frame
	var fixture=load("res://tests/online_pve_test.gd").new();var online:=OnlinePve.new();online.character_id=fixture.SELF;online.ready=true;online.state=fixture.pve_state()
	online.state.loot={"state":Game.player.loot_state.duplicate(true),"progression_sha256":ProgressionRules.catalog_hash};online.state.character.gold=100000
	panel=CraftingPanel.new();panel.online_model=online;panel.selected_id=item.id;add_child(panel)
	panel.upgrade.pressed.emit();check(OnlineAccount.pending_pve.is_empty(),"Online first click never sends a paid command")
	panel.upgrade.pressed.emit()
	check(OnlineAccount.pending_pve.command.action=="gear_upgrade" and OnlineAccount.pending_pve.command.target==item.id,"Confirmed online operation still carries only the owned instance and command")
	check(panel.upgrade.disabled and panel.focus.disabled,"Pending authoritative operation locks all edits")
	panel.queue_free();fixture.free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=old_path;Game.local_combat=combat;OnlineAccount.pending_pve=outbox
	print("CRAFTING LAYOUT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
