extends "res://tests/combat_balance_test.gd"
const DELAYED=preload("res://tests/fixtures/delayed_storage.gd")
func same(a:Variant,b:Variant)->bool:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in b:
			if not a.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	return a==b
func load_result(results:Array)->void:results.append(await Game.load_game())
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var account:=OnlineAccount.characters.duplicate(true);var outbox:=OnlineAccount.pending_pve.duplicate(true);OnlineAccount.pending_pve={}
	var vectors:=OS.get_environment("SSJX_LOOT_VECTORS")
	if not vectors.is_empty():
		for row in JSON.parse_string(FileAccess.get_file_as_string(vectors)):
			var expected:Dictionary=row.item
			var item:=LootRules.roll(expected.template,int(expected.level),expected.quality,int(row.seed),expected.id);item.equipped=true
			check(same(item,expected),"Actual Rust/Godot seeded roll parity")
			var state:=LootRules.empty();state.items=[item];state.skins=[item.template]
			check(LootRules.valid(state,int(row.job),int(row.gender)),"Legal slot, class, level, quality and affix bounds")
			var points:Array=row.points.map(func(n:Variant)->int:return int(n))
			var stats:=CharacterAttributeRules.balanced_stats(int(row.job),int(item.level),false,points);LootRules.apply_stats(state,stats,int(row.job))
			check(same(stats,row.stats) and same(CharacterAttributeRules.profile_for(stats,int(row.job),int(item.level),points),row.profile),"Full rolled attribute and profile parity")
			var effects:=SkillRules.new_state(int(row.job),3,60,60)
			check(CharacterAttributeRules.direct_damage(stats,240,16000)==row.damage and CharacterAttributeRules.dot_damage(stats,240,3000)==row.dot and CharacterAttributeRules.incoming(400,int(item.level),stats)==row.incoming and CharacterAttributeRules.critical_at(stats,int(row.job)==2,effects,100,0)==row.critical and CharacterAttributeRules.hit_chance(stats,{},int(row.job)==2)==row.hit,"Affixes affect actual damage, DOT, defense, critical and hit calculations")
	Game.save_path="user://loot_instances_%d.json"%Time.get_ticks_usec();Game.new_player("装备验证",0,3,0);Game.player.level=60;Game.player.allocated_attributes=[60,0,180,60,0];Game.restore()
	var a:=LootRules.roll("ai/eva01/mzs/weapon",30,"yellow",17);var b:=LootRules.roll(a.template,30,"yellow",29)
	Game.player.loot_state.items.append_array([a,b]);Game.player.hp=1;Game.player.mp=1
	check((await Game.loot_command("gear_equip",a.id)).ok and Game.player.hp==1 and Game.player.mp==1,"Real local equip saves without refilling HP/MP")
	check(Game.stats().attack>CharacterAttributeRules.balanced_stats(0,60,false,Game.allocated_attributes()).attack and Game.appearance_key().contains("w40"),"Actual local stats and appearance use the rolled instance")
	var expected:Dictionary=Game.player.loot_state.duplicate(true);var stats:=Game.stats()
	check((await Game.load_game()).ok and same(Game.player.loot_state,expected) and same(Game.stats(),stats),"Reload retains each UUID, affix and equipped slot")
	var inventory:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(inventory)
	check(inventory._slot_item("weapon").instance_id==a.id and inventory.items.any(func(i:Dictionary)->bool:return i.get("instance_id")==b.id),"Production backpack shows the equipped copy and the other copy independently")
	inventory.open_menu()
	var button:Button
	for child in inventory.item_menu.get_children():
		if child is Button and child.text=="装备实例":button=child
	check(button!=null,"Equipment manager is reachable through the native backpack menu")
	if button!=null:button.pressed.emit()
	check(is_instance_valid(inventory.loot_panel) and inventory.loot_panel.rows.size()==3,"Production manager lists imported fixed gear and both rolled copies")
	inventory.loot_panel.list.select(1);inventory.loot_panel.list.item_selected.emit(1)
	check(inventory.loot_panel.details.text.contains("稀有") and inventory.loot_panel.equip.text=="卸下","Manager presents the selected rolled item's affixes and equipped action")
	var output:=OS.get_environment("SSJX_LOOT_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Actual equipment manager, affixes and pending controls render")
	inventory.queue_free();await get_tree().process_frame
	var context:=Platform.context;var storage:=DELAYED.new();Platform.context=PlatformContext.new("loot-test",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	var before:=Game.player.duplicate(true)
	Game.loot_command("gear_unequip",a.id)
	check(Game.storage_busy and storage.operations.size()==1,"Equip operations wait for durable confirmation")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试保存失败"));await get_tree().process_frame
	check(Game.player==before,"Storage failure rolls back the whole inventory and resources")
	Platform.context=context
	var old_save:=Game.player.duplicate(true);old_save.erase("loot_state")
	var file:=FileAccess.open(Game.save_path,FileAccess.WRITE);file.store_string(JSON.stringify(old_save));file.close()
	check((await Game.load_game()).ok,"Legacy save migrates without requiring a new character")
	var migrated:Dictionary=Game.player.loot_state.duplicate(true)
	check(migrated.items.size()==1 and migrated.items[0].legacy and same(JSON.parse_string(FileAccess.get_file_as_string(Game.save_path)).loot_state,migrated),"Legacy IDs are persisted before migration is reported successful")
	check((await Game.load_game()).ok and same(Game.player.loot_state,migrated),"Repeated load never generates replacement legacy UUIDs")
	Game.player=before.duplicate(true)
	storage=DELAYED.new();Platform.context=PlatformContext.new("loot-migration-test",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	var loads:Array=[];load_result(loads);storage.complete(PlatformResult.success(JSON.stringify(old_save)))
	check(Game.player==before and storage.operations.size()==1 and storage.operations[0].kind=="write" and loads.is_empty(),"Legacy migration waits for persistence before publishing new UUIDs")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试迁移失败"));await get_tree().process_frame
	check(loads.size()==1 and not loads[0].ok and Game.player==before and not Game.storage_busy,"Failed migration retains the previous character and reports an explicit error")
	Platform.context=context
	while ShopRules.bag_slots(ShopRules.local_state(Game.player),int(Game.player.potions))+LootRules.extra_bag(Game.player.loot_state)<60:Game.player.loot_state.items.append(LootRules.roll(a.template,1,"white",1))
	var full:=Game.player.duplicate(true)
	check(not (await Game.loot_command("gear_unequip",a.id)).ok and Game.player==full,"A full shared backpack rejects unequip atomically")
	Game.player=before.duplicate(true);Game.become_soul();var soul:=Game.player.duplicate(true)
	check(not (await Game.loot_command("gear_unequip",a.id)).ok and Game.player==soul,"Soul state cannot alter equipment or recover resources")
	Game.player=before.duplicate(true)
	check((await Game.set_local_test_level(1)).ok and not LootRules.equipped(Game.player.loot_state,"weapon").get("equipped",false) and Game.valid_save(Game.player),"Local level downgrade safely unequips high-level instances instead of producing an unloadable save")
	Game.player=before.duplicate(true)
	var bad:=Game.player.duplicate(true);bad.loot_state.items.append(bad.loot_state.items[1].duplicate(true));check(not Game.valid_save(bad),"Duplicate instance IDs cannot enter saved stats")
	bad=Game.player.duplicate(true);bad.loot_state.items[1].affixes[0].value=1000000;check(not Game.valid_save(bad),"Malformed affix values are rejected before aggregation")
	var fixtures:=OS.get_environment("SSJX_LOOT_FIXTURES")
	if not fixtures.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(fixtures)):
			var model:=OnlinePve.new();model.character_id=snapshot.character.id
			check(model.receive({"type":"pve.state","state":snapshot}),"Actual migrated/equipped server snapshot validates and renders authoritative values")
			var malformed:Dictionary=snapshot.duplicate(true);malformed.loot.appearance[0]=999;check(not model.valid(malformed),"Forged appearance cannot bypass ownership-derived look")
			check(OnlineWorldClient.valid_packet_size({"type":"pve.state","state":snapshot},65536) and not OnlineWorldClient.valid_packet_size({"type":"pve.state","state":snapshot},131073),"Full rolled inventory has a bounded larger PVE envelope, never an unlimited packet")
			if snapshot.loot.state.items.size()==3 and int(snapshot.loot.appearance[0])==40 and not model.active():
				var remote:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();remote.online_model=model;add_child(remote);remote.open_loot()
				check(remote.preview.get_meta("art_key").contains("w40") and remote.loot_panel.online_model==model,"Actual online backpack and manager render the server-owned instance appearance")
				var packets:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:packets.append(packet))
				remote.loot_panel.list.select(2);remote.loot_panel.list.item_selected.emit(2);remote.loot_panel.equip.pressed.emit()
				check(packets.size()==1 and packets[0].command.action=="gear_equip" and packets[0].command.target==snapshot.loot.state.items[2].id and packets[0].command.expected_revision==snapshot.character.state_revision,"Online manager sends a UUID and authoritative revision, never client stats or a reroll seed")
				OnlineAccount.pending_pve={};remote.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path;OnlineAccount.characters=account;OnlineAccount.pending_pve=outbox
	check(not OnlineWorldClient.valid_packet_size({"type":"duel.state"},65536) and not OnlineWorldClient.valid_packet_size({"type":"pve.state","state":{}},65536),"Unrelated or legacy packets cannot bypass their existing size limit")
	print("LOOT INSTANCES: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
