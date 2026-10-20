extends "res://tests/combat_balance_test.gd"
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://balance_activation_%d.json"%Time.get_ticks_usec()
	Game.new_player("数值实战",0,3,0)
	Game.player.level=30;Game.player.allocated_attributes=[30,0,90,30,0];Game.player.balance_revision=0;Game.player.attribute_rules_revision=2;Game.player.hp=100;Game.player.mp=50
	check((await Game.save_game()).ok and (await Game.load_game()).ok,"Real legacy local save loads and migrates")
	check(Game.player.balance_revision==1 and Game.player.hp==100*998/882 and Game.player.mp==50,"Local migration preserves exactly the same ratios as Rust")
	var stats:=Game.stats()
	check(stats.has("balance") and Game.attribute_profile().formula_revision==3,"Actual local stat path uses the new kernel")
	var battle:=ShushanBattle.new(ShushanWorld.ENEMIES[0]);var frozen:=battle.frozen_stats.duplicate(true)
	Game.player.allocated_attributes=[0,0,150,0,0]
	check(matches(battle.frozen_stats,frozen),"Local encounter freezes its own stats instead of following later character changes")
	Game.player.allocated_attributes=[30,0,90,30,0]
	var hp:int=Game.player.hp;var maximum:int=Game.stats().hp
	check((await Game.respec_attributes()).ok and Game.allocated_attributes()==[0,0,0,0,0],"Free local respec is reachable and saved")
	check(Game.player.hp==maxi(1,hp*int(Game.stats().hp)/maximum) and not Game.player.balance_respec_available,"Respec preserves health ratio and consumes entitlement")
	check(not (await Game.respec_attributes()).ok,"Free respec cannot be reused")
	var panel:OriginalCharacterAttributes=load("res://scenes/ui/character_attributes.tscn").instantiate();add_child(panel);panel.select_tab(1)
	check(panel.content.get_node("Respec").disabled,"Used entitlement is visibly disabled")
	var fixture:=OS.get_environment("SSJX_BALANCE_ACTIVATION_FIXTURES")
	if not fixture.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(fixture)):
			var model:=OnlinePve.new();model.character_id=snapshot.character.id
			check(model.valid(snapshot),"Real migrated/active-battle/respec server snapshot validates")
	var output:=OS.get_environment("SSJX_BALANCE_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Actual extended attributes/respec screen renders")
	panel.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=path
	print("BALANCE ACTIVATION CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
