extends "res://tests/loot_instances_test.gd"
func _run()->void:
	await Game.when_ready()
	var input:=OS.get_environment("SSJX_BUILD_VECTORS")
	check(not input.is_empty(),"Build regression requires actual Rust-generated vectors")
	if input.is_empty():get_tree().quit(1);return
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string(input))
	for row in rows:
		check(LootRules.valid(row.loot,int(row.job),int(row.gender)),"All legendary and set copies obey class, slot, quality and frozen roll validation")
		for item in row.loot.items:
			var rolled:=LootRules.roll_special(item.template,int(item.level),item.quality,item.legendary if item.legendary!=null else item.set_id,17,item.id);rolled.equipped=true
			check(same(rolled,item),"Rust/Godot special-item seeded affix parity")
		var stats:=CharacterAttributeRules.balanced_stats(int(row.job),60,false,[0,0,0,0,0]);LootRules.apply_stats(row.loot,stats,int(row.job))
		var wire:=stats.duplicate(true)
		if not row.stats.has("attributes"):wire.erase("attributes") # Rust omits an all-zero allocation.
		check(same(wire,row.stats) and CharacterAttributeRules.valid_balance(stats),"Two-piece bonuses and legendary/four-piece frozen activation agree")
		var state:=SkillRules.new_state(int(row.job),3,60,60);var hp:=int(stats.hp)/2;var mp:=int(stats.mp)
		for turn in row.turns:
			SkillRules.reset_turn(state);SkillRules.activate(state,stats);state.balance.targets=5
			var result:=SkillRules.cast(SkillRules.item(turn.skill),state,stats,hp,mp,100,0);hp=int(result.hp);mp=int(result.mp)
			check(result.damage==turn.damage and hp==turn.hp and mp==turn.mp,"Actual six-build skill rotations match Rust damage, resource and healing results")
			check(same(state,turn.state) and SkillRules.valid_state(state),"Persistent charge, poison clock, immunity and once-per-action proc state agree")
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.new_player("流派验收",0,3,0);Game.player.level=60;Game.player.loot_state=rows[4].loot.duplicate(true);Game.player.shop_owned=[];Game.player.equipped=false;Game.player.shop_slots={}
	LootRules.sync_legacy(Game.player);Game.restore();Game.save_path="user://builds_%d.json"%Time.get_ticks_usec()
	check((await Game.save_game()).ok and (await Game.load_game()).ok and Game.valid_save(Game.player),"Actual local character persists legendary identity, set pieces and frozen aggregation")
	var inventory:OriginalInventory=load("res://scenes/ui/inventory.tscn").instantiate();add_child(inventory);inventory.open_loot();inventory.loot_panel.get_node("BuildOverview").pressed.emit()
	check(inventory.loot_panel.details.text.contains("铁壁反击") and inventory.loot_panel.details.text.contains("特效2阶") and inventory.loot_panel.details.text.contains("赤血斩"),"Production equipment menu explains both class styles and actual four-piece plus legendary activation")
	var output:=OS.get_environment("SSJX_BUILD_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Actual build overview renders with a scrollable description")
	inventory.queue_free();await get_tree().process_frame
	var malformed:Dictionary=rows[4].loot.duplicate(true);malformed.items[0].legendary="siphon";check(not LootRules.valid(malformed,0,0),"Cross-class legendary identity is rejected")
	malformed=rows[4].loot.duplicate(true);malformed.items[0].quality="yellow";check(not LootRules.valid(malformed,0,0),"A rare cannot secretly carry a legendary effect")
	var fixtures:=OS.get_environment("SSJX_BUILD_FIXTURES")
	if not fixtures.is_empty():
		for fixture in JSON.parse_string(FileAccess.get_file_as_string(fixtures)):
			var online:=OnlinePve.new();online.character_id=fixture.character.id
			check(online.receive({"type":"pve.state","state":fixture}),"Actual server frozen legendary procs and persisted charges pass the production client decoder")
			var forged:Dictionary=fixture.duplicate(true);forged.stats.balance.builds.sets[0]=9
			check(not online.valid(forged),"Malformed set counts never enter the battle view")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("BUILDS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
