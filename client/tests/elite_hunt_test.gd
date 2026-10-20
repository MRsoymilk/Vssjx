extends "res://tests/online_pve_test.gd"
func _run()->void:
	await Game.when_ready()
	var previous:=Game.player.duplicate(true);var previous_path:=Game.save_path
	Game.save_path="user://elite_hunt_%d.json"%OS.get_process_id()
	Game.new_player("精英验证",1,3);Game.player.level=60;Game.restore()
	var wolf:Dictionary=SharedWorldMap.population("qingyun_trail").filter(func(d:Dictionary)->bool:return d.id=="wolf_a")[0]
	check(MonsterCombat.pressure_valid({}),"Old saves without a counter remain valid")
	for i in 4:
		Game.player.cell=[10+i,16]
		var recorded:=await Game.record_local_hunt("qingyun_trail",wolf.art)
		check(recorded.ok and not recorded.value.elite and int(Game.player.hunt_pressure.count)==i+1,"Movement within a map cannot reset consecutive encounters")
	var loaded:=await Game.load_game()
	check(loaded.ok and int(Game.player.hunt_pressure.count)==4,"Counter survives a real storage reload")
	var recorded:=await Game.record_local_hunt("qingyun_trail",wolf.art)
	check(recorded.ok and recorded.value.elite,"Fifth accepted encounter triggers the elite")
	recorded=await Game.record_local_hunt("qingyun_trail",wolf.art)
	check(recorded.value.elite and int(Game.player.hunt_pressure.count)==5,"Uncleared elite stays due")
	var before:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://missing_hunt_folder/save.json"
	var failed:=await Game.record_local_hunt("ancient_ruins","monster/nt1")
	check(not failed.ok and Game.player==before,"Failed storage write rolls counter back")
	Game.save_path=path
	check(int(MonsterCombat.note_pressure(Game.player.hunt_pressure,"ancient_ruins",wolf.art).count)==1,"A new map resets the run")
	check(int(MonsterCombat.note_pressure(Game.player.hunt_pressure,"qingyun_trail","monster/hs1").count)==1,"A different species resets the run")
	check(not MonsterCombat.pressure_valid({"map":"x","species":"y","count":6}),"Out-of-range counters are rejected")
	var solo:=SoloEncounter.new();solo.start([wolf],true)
	check(solo.state.enemies[0].elite.revives_left==1 and solo.state.enemies[0].hp>int(wolf.hp),"Local elite has a finite extra life and increased HP")
	var elite:Dictionary=solo.state.enemies[0]
	check(MonsterCombat.elite_plan(elite,0,false,false).hits==3,"Solo elite has a three-hit combo")
	check(MonsterCombat.elite_critical(elite,100,34)=={"damage":175,"critical":true},"Elite uses the high critical chance and multiplier")
	elite.hp=1;solo.engine.rng.seed=12;solo.submit("attack","m0")
	check(solo.active() and int(elite.elite.revives_left)==0 and solo.state.events.any(func(e:Dictionary)->bool:return e.action=="revive"),"Lethal attack revives before deciding victory")
	check(Game.player.hunt_pressure.count==5,"Revival cannot clear the hunt counter")
	elite.hp=1
	for i in 10:
		if not solo.active():break
		solo.submit("attack","m0")
	while solo.saving:await get_tree().process_frame
	check(solo.state.outcome=="victory" and Game.player.hunt_pressure.is_empty(),"Final victory clears the sticky counter")
	check(solo.save_result.ok,"Victory and counter clearing share a confirmed save")
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world()
	Game.player.hunt_pressure={"map":"qingyun_trail","species":wolf.art,"count":4}
	await app._start_local_encounter([wolf],true)
	var view:Control=app.local_encounter_view;view.set_process(false);view._process(0)
	check(app.local_encounter.state.enemies[0].has("elite") and view.actors.m0.tag.text.begins_with("精英·"),"Real game entry counts and labels the fifth encounter")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../work/elite-hunt.png")
	var actor:Dictionary=view.actors.m0
	actor.hp.value=0;actor.dead=true
	# A lethal skill may finish its native FX after movement; death must start before revive.
	view._effect_wait="sheet_010"
	view.queue=[{"actor":"m0","target":"m0","action":"revive","skill":"monster_rebirth","damage":0,"healed":20,"critical":false}]
	view._process(0)
	check(view.queue.size()==1 and not actor.sprite.visible,"Revival waits for native death after the skill FX tail")
	for death in view.deaths:death.advance(death.duration)
	view._process(0)
	check(view.queue.is_empty() and actor.sprite.visible and not actor.dead and int(actor.hp.value)==20 and view.deaths.is_empty(),"Revival restores the actor and removes its tombstone")
	view._cancel();app._home();app.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=previous;Game.save_path=previous_path
	print("ELITE HUNT: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
