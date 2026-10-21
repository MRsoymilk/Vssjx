extends "res://tests/loot_instances_test.gd"
func without_ids(state:Dictionary)->Dictionary:
	var s:=state.duplicate(true)
	for item in s.items+s.pending:item.erase("id")
	s.skins.sort();return s
func _run()->void:
	await Game.when_ready()
	var input:=OS.get_environment("SSJX_PROGRESSION_VECTORS")
	check(not input.is_empty(),"Economy regression requires actual Rust-generated draws and transactions")
	if input.is_empty():get_tree().quit(1);return
	var rows:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input))
	for row in rows.rewards:
		var player:Dictionary={"job":int(row.job),"gender":int(row.gender),"potions":5940,"weapon_owned":false,"shop_owned":[],"loot_state":row.before.duplicate(true)}
		ProgressionRules.reward(player,int(row.level),row.boss,int(row.seed))
		check(same(without_ids(player.loot_state),without_ids(row.after)),"Actual Rust/Godot rewards, smart templates, directed slots, qualities, pity, materials and pending placement agree")
		check(LootRules.valid(player.loot_state,int(row.job),int(row.gender)),"Every generated drop is a legal immutable character-owned instance")
	for row in rows.crafts:
		var player:Dictionary={"job":int(row.job),"gold":100000,"loot_state":row.before.duplicate(true)};var id:String=player.loot_state.items[0].id
		for step in row.steps:
			if step.quote!=null:check(same(ProgressionRules.quote(player.loot_state.items[0],step.action).cost,step.quote),"Authoritative gold, scrap and essence price parity")
			check(ProgressionRules.craft(player,id,step.action,-1 if step.index==null else int(step.index),int(step.seed)).is_empty(),"Actual crafting transaction succeeds")
			check(player.gold==step.gold and same(player.loot_state,step.after),"Upgrade, single-affix lock, repeated reroll and salvage preserve all unaffected fields and consume identical resources")
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var combat:=Game.local_combat
	Game.local_combat=null;Game.new_player("掉落养成验收",1,3,0);Game.player.level=60;Game.player.gold=100000;Game.player.loot_state.scrap=10000;Game.player.loot_state.essence=100;Game.player.loot_state.bosses=7;Game.restore()
	Game.save_path="user://progression_%d.json"%Time.get_ticks_usec()
	var encounter:=SoloEncounter.new();encounter.start([{"id":"guardian","name":"养成首领","kind":"boss","art":"monster/xt1","level":60,"hp":1,"mp":0,"attack":1,"defense":1,"gold":120,"xp":0}]);encounter.engine.rng.seed=1;encounter.rng.seed=1;Game.local_combat=weakref(encounter)
	check(not (await Game.loot_command("gear_focus","weapon")).ok,"Local combat excludes equipment/economy mutations just like the server")
	for i in 16:
		if not encounter.active():break
		encounter.submit("attack","m0")
	check(encounter.committed and encounter.save_result.ok and Game.player.loot_state.bosses==8,"Actual solo victory awards and durably saves exactly one encounter's materials and pity counter")
	var drops:Array=Game.player.loot_state.items.filter(func(i:Dictionary)->bool:return not i.legacy)
	check(drops.size()==2 and drops.any(func(i:Dictionary)->bool:return i.get("legendary")!=null or i.get("set_id")!=null),"An actual eligible eighth boss produces a build item and a second independently rolled drop")
	var receipt:=Game.player.duplicate(true);encounter._commit();check(Game.player==receipt,"Repeating local settlement cannot add loot, materials or pity again")
	check((await Game.load_game()).ok and same(Game.player.loot_state,receipt.loot_state),"Reload never rerolls an awarded UUID, affix, legendary or set")
	Game.local_combat=null
	var target:Dictionary=drops[0];var id:String=target.id
	var inventory:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(inventory);inventory.open_loot();inventory.loot_panel.selected_id=id;inventory.loot_panel.open_crafting()
	var panel:CraftingPanel=inventory.loot_panel.get_node("CraftingPanel")
	var gold:=int(Game.player.gold);panel.upgrade.pressed.emit();check(Game.player.gold==gold and not panel.confirmation.is_empty(),"Native equipment UI requires a second confirmation before charging")
	panel.upgrade.pressed.emit();await get_tree().process_frame
	check(panel._item().upgrade==1 and Game.player.gold<gold,"Actual crafting panel upgrades and saves the selected UUID")
	var output:=OS.get_environment("SSJX_PROGRESSION_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Actual upgrade/reroll/salvage/focus controls render")
	panel.reroll.pressed.emit();panel.reroll.pressed.emit();await get_tree().process_frame
	check(panel._item().reroll_index!=null and panel._item().rerolls==1 and panel.affix.disabled,"Production UI locks exactly one reroll slot after confirmed payment")
	panel.focus.select(1);panel.focus.item_selected.emit(1);await get_tree().process_frame;check(Game.player.loot_state.focus=="weapon","Actual directed-drop setting persists through the equipment UI")
	inventory.queue_free();await get_tree().process_frame
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world();app._scene_action("craft")
	check(is_instance_valid(app.backpack) and is_instance_valid(app.backpack.loot_panel),"The original local HUD craft entry opens the actual equipment manager instead of an unopened-feature message")
	app._close_modal();app.queue_free();await get_tree().process_frame
	var context:=Platform.context;var storage:=DELAYED.new();Platform.context=PlatformContext.new("craft-failure",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	var before:=Game.player.duplicate(true);Game.loot_command("gear_salvage",id)
	check(Game.storage_busy and storage.operations.size()==1,"Destructive crafting waits for durable storage confirmation")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试分解失败"));await get_tree().process_frame
	check(Game.player==before,"Failed salvage restores exact UUID, affixes, currency and materials")
	Platform.context=context
	check((await Game.loot_command("gear_salvage",id)).ok and not Game.player.loot_state.items.any(func(i:Dictionary)->bool:return i.id==id),"Successful salvage removes exactly one confirmed item")
	var fixtures:=OS.get_environment("SSJX_PROGRESSION_FIXTURES")
	if not fixtures.is_empty():
		for fixture in JSON.parse_string(FileAccess.get_file_as_string(fixtures)):
			var online:=OnlinePve.new();online.character_id=fixture.character.id;check(online.receive({"type":"pve.state","state":fixture}),"Actual server reward/crafting snapshots pass the production wire decoder")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path;Game.local_combat=combat
	print("PROGRESSION: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
