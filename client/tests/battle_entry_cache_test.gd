extends "res://tests/team_test.gd"
func _run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path;var old_combat:=Game.local_combat
	var outbox:=OnlineAccount.pending_team.duplicate(true)
	Game.save_path="user://battle_entry_cache_%d.json"%Time.get_ticks_usec()
	for kind in ["courtyard","arena","wilderness","snow","ruins"]:
		var field:=OriginalBattleField.new();field.kind=kind;add_child(field)
		var bytes:PackedByteArray=field.terrain.tile_map_data
		check(field.terrain.tile_set==OriginalBattleField.TILE_SET and field.terrain.get_used_cells().size()==500,"Battlefield reuses the native 756-tile resource: "+kind)
		field.free();field=OriginalBattleField.new();field.kind=kind;add_child(field)
		check(field.terrain.tile_map_data==bytes,"Repeated field copies identical baked cells, not a new atlas: "+kind);field.free()
	var actor:=OriginalArt.actor("hero/mck");actor.free()
	var loads:=OriginalArt._scene_loads
	for i in 8:actor=OriginalArt.actor("hero/mck");actor.free()
	check(OriginalArt._scene_loads==loads and OriginalArt.is_prepared("hero/mck"),"Repeated actors retain their native scene instead of parsing it for every battle")
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app)
	for pass_index in 2:
		Game.local_combat=null;Game.new_player("缓存验证",1,3,0);Game.player.quest=1
		app._enter_world();await get_tree().process_frame
		var first_frame:=Engine.get_process_frames();loads=OriginalArt._scene_loads
		app._world_interaction("enemy",ShushanWorld.ENEMIES[0])
		var deadline:=Time.get_ticks_msec()+15000
		while app.mode=="battle_loading" and app.battle_transition.progress<1 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		var frames:=Engine.get_process_frames()-first_frame
		check(app.mode=="battle_loading" and app.battle_transition.progress==1,"Real local preparation reaches a complete resource state")
		if pass_index==1:
			check(frames<=8,"Warm local battle preparation takes at most eight process frames, without fixed 360ms waits")
			check(OriginalArt._scene_loads==loads,"Warm preparation neither reloads nor recreates native actor scenes")
		while app.mode=="battle_loading" and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		check(app.mode=="local_encounter","Actual local encounter still uses the original command/actor view")
		print("BATTLE ENTRY LOCAL pass=%d preparation_frames=%d"%[pass_index,frames])
		app._home();await get_tree().process_frame
	app.queue_free();await get_tree().process_frame
	var world:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate();world.character_id=SELF;add_child(world)
	world.set_process(false);world.network.set_process(false);world.team.bind_character(SELF)
	for pass_index in 2:
		var b:=encounter();b.id=BATTLE if pass_index==0 else TEAM
		world.team.request={"action":"snapshot"};world.team.inflight=true
		loads=OriginalArt._scene_loads;var first_frame:=Engine.get_process_frames()
		check(world.team.receive(response(world.team,state(b))),"Actual team decoder accepts a new authoritative battle")
		check(not world.team.presentation_ready() and not world.team_battle.visible and world.encounter.visible,"Team entry yields before constructing the formation on an HTTP callback")
		var deadline:=Time.get_ticks_msec()+15000
		while not world.team.presentation_ready() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		var frames:=Engine.get_process_frames()-first_frame
		check(world.team.presentation_ready() and world.team_battle.visible and world.team_battle.actors.size()==5,"All team heroes and monsters appear only after resource readiness")
		if pass_index==1:
			check(frames<=8 and OriginalArt._scene_loads==loads,"Warm team entry reuses prepared actors without a per-actor frame delay")
		print("BATTLE ENTRY TEAM pass=%d preparation_frames=%d"%[pass_index,frames])
	check(OriginalArt._loaded_scenes.size()<=OriginalArt.MAX_SCENES and OriginalBattleField._terrain_templates.size()<=6,"Scene and battlefield template caches stay bounded")
	var cancelled:=encounter();cancelled.id="66666666-6666-4666-8666-666666666666"
	world.team.request={"action":"snapshot"};world.team.inflight=true
	check(world.team.receive(response(world.team,state(cancelled))) and not world._team_loading.is_empty(),"Cancellation fixture enters a real team resource preparation")
	world.team.request={"action":"snapshot"};world.team.inflight=true
	check(world.team.receive(response(world.team,state())),"A newer team snapshot may remove the preparing battle")
	for i in 3:await get_tree().process_frame
	check(world._team_loading.is_empty() and not world.team_battle.visible and not world.encounter.visible and world.screen.hud.visible,"Cancelled team preparation cannot reopen its battle or strand the world HUD")
	world.queue_free();await get_tree().process_frame
	if FileAccess.file_exists(Game.save_path):DirAccess.remove_absolute(Game.save_path)
	Game.save_path=old_path;Game.player=old;Game.local_combat=old_combat;OnlineAccount.pending_team=outbox
	print("BATTLE ENTRY CACHE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
