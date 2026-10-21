extends "res://tests/loot_instances_test.gd"
func capture_endless(name:String)->void:
	var path:=OS.get_environment("SSJX_ENDLESS_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(path)
	for frame in 3:await get_tree().process_frame
	RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))==OK,"Actual endless presentation renders "+name)
func begin_result(results:Array)->void:results.append(await Game.start_endless())
func _run()->void:
	await Game.when_ready()
	var path:=OS.get_environment("SSJX_ENDLESS_VECTORS")
	check(not path.is_empty(),"Endless regression requires actual Rust rule vectors")
	if path.is_empty():get_tree().quit(1);return
	var vectors:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	for row in vectors.monsters:check(same(EndlessRules.monster(row.run),row.enemy),"Actual Rust/Godot stage, level, appearance, integer growth and rewards agree")
	var p:=EndlessRules.empty()
	for row in vectors.progress:
		var started:=EndlessRules.begin(p,15);check(same(started.run,row.run) and same(p,row.started),"Entry level and current stage freeze consistently")
		check(EndlessRules.finish(p,started.run,row.victory) and same(p,row.finished),"Win advances once; failure resets only the run, not the best")
	var old:=Game.player.duplicate(true);var save_path:=Game.save_path;var old_combat:=Game.local_combat
	Game.local_combat=null;Game.new_player("试炼客",1,3,0);Game.player.level=15;Game.player.allocated_attributes=[15,0,45,15,0]
	Game.player.ai_map="ai_001";Game.player.cell=[10,15];Game.restore();Game.save_path="user://endless_%d.json"%Time.get_ticks_usec()
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world()
	check(app.world.ai_npcs.has(EndlessRules.rules.npc.id) and AIWorld.resident(EndlessRules.rules.npc.id).cell==EndlessRules.rules.npc.cell,"The new NPC is an actual clickable resident in the existing hub map")
	await capture_endless("hub-npc")
	app._open_ai_npc(EndlessRules.rules.npc.id)
	check(app.modal.quest_button.text.contains("第1层") and not app.modal.quest_button.disabled and app.modal.allows("endless",EndlessRules.rules.npc.id),"Production NPC dialogue exposes the first challenge and personal record")
	await capture_endless("npc-dialogue")
	check(app.modal.get_node("Paper/Greeting").size.x==284 and app.modal.get_node("Paper/Greeting").get_line_count()>1,"The actual NPC instructions wrap inside the paper instead of running offscreen")
	var hp:=int(Game.player.hp);var mp:=int(Game.player.mp);app.modal.quest_button.pressed.emit();await get_tree().process_frame
	check(app.mode=="local_encounter" and app.local_encounter.state.endless.stage==1 and Game.player.endless_state.in_progress and Game.player.hp==hp and Game.player.mp==mp,"Actual NPC button durably marks entry and starts the first fight without refilling resources")
	var encounter:SoloEncounter=app.local_encounter;encounter.engine.rng.seed=1;encounter.rng.seed=1
	var first:Dictionary=encounter.state.enemies[0].definition.duplicate(true)
	await capture_endless("first-stage")
	var tag:Label=app.local_encounter_view.actors.m0.tag
	check(tag.text=="试炼幻影 Lv.15" and tag.get_theme_font("font").get_string_size(tag.text,HORIZONTAL_ALIGNMENT_LEFT,-1,tag.get_theme_font_size("font_size")).x<=tag.size.x,"Stage caption carries the layer while the enemy name and level fit the battle nameplate")
	for i in 20:
		if not encounter.active():break
		encounter.submit("attack","m0")
	check(encounter.state.outcome=="victory" and encounter.save_result.ok and Game.player.endless_state.stage==2 and Game.player.endless_state.best==1,"Winning the actual local stage persists the next stage and best record")
	check(Game.player.defeated.is_empty() and Game.player.get("enemy_respawns",{}).is_empty(),"Arena kills do not counterfeit world quest kills or respawn cooldowns")
	var before:=Game.player.duplicate(true);encounter._commit();check(Game.player==before,"Repeated settlement cannot advance stages or issue rewards twice")
	app._enter_world();app._open_ai_npc(EndlessRules.rules.npc.id);check(app.modal.quest_button.text.contains("第2层"),"Reopening the NPC offers the stronger next stage")
	app.modal.quest_button.pressed.emit();await get_tree().process_frame;encounter=app.local_encounter
	var second:Dictionary=encounter.state.enemies[0].definition
	check(second.hp>first.hp and second.attack>first.attack and second.defense>=first.defense,"The actual next enemy is stronger, not merely renamed")
	var close_context:=Platform.context;var close_storage:=DELAYED.new()
	Platform.context=PlatformContext.new("endless-close-failure",close_storage,close_context.runtime_config,close_context.display,close_context.lifecycle,close_context.resource_loader,close_context.text_input,close_context.system_actions)
	app._close_requested();check(Game.storage_busy and app._closing,"Graceful exit waits for the trial resource save")
	close_storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试退出保存失败"));await get_tree().process_frame
	check(not app._closing and Game.player.endless_state.in_progress and encounter.active(),"A failed exit does not reset an active trial that can still be played and settled")
	Platform.context=close_context
	encounter.submit("flee");check(encounter.save_result.ok and Game.player.endless_state.stage==1 and Game.player.endless_state.best==1 and not Game.player.endless_state.in_progress,"Retreat ends this run while retaining the cleared-stage record")
	app._enter_world()
	check((await Game.start_endless()).ok and Game.player.endless_state.in_progress,"An entry record is confirmed before local combat begins")
	check((await Game.load_game()).ok and Game.player.endless_state.stage==1 and Game.player.endless_state.best==1 and not Game.player.endless_state.in_progress,"Loading an interrupted local fight ends the abandoned run without losing the best score or reissuing rewards")
	var context:=Platform.context;var storage:=DELAYED.new();Platform.context=PlatformContext.new("endless-save-failure",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	before=Game.player.duplicate(true);var results:Array=[];begin_result(results)
	check(Game.storage_busy and results.is_empty() and storage.operations.size()==1,"Entry waits for durable storage, so a second click cannot skip to another stage")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","测试试炼保存失败"));await get_tree().process_frame
	check(results.size()==1 and not results[0].ok and Game.player==before,"Failed entry rolls back the whole character and does not start combat")
	Platform.context=context
	Game.player.hp=1;var entered:=await Game.start_endless();encounter=SoloEncounter.new();encounter.start([entered.value.enemy],false,entered.value.run);encounter.rng.seed=1;encounter.engine.rng.seed=1
	for i in 16:
		if not encounter.active():break
		encounter.submit("guard")
	check(encounter.state.outcome=="defeat" and Game.is_soul() and Game.player.hp==0 and Game.player.endless_state.best==1 and Game.player.endless_state.stage==1,"Defeat keeps the existing same-map corpse recovery and the personal best")
	check(not (await Game.start_endless()).ok,"Souls cannot bypass corpse recovery by entering a new trial")
	var fixtures:=OS.get_environment("SSJX_ENDLESS_FIXTURES")
	if not fixtures.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(fixtures)):
			var model:=OnlinePve.new();model.character_id=snapshot.character.id;check(model.receive({"type":"pve.state","state":snapshot}),"Actual server NPC progression and synthetic battle snapshots validate in the production client")
			var forged:Dictionary=snapshot.duplicate(true);forged.endless.progress.best=-1;check(not model.valid(forged),"Malformed personal records never reach the NPC dialogue")
			if snapshot.get("battle") is Dictionary and snapshot.battle.has("endless"):
				forged=snapshot.duplicate(true);forged.battle.enemy.attack+=1;check(not model.valid(forged),"A synthetic enemy must match its frozen stage, not arbitrary injected stats")
				forged=snapshot.duplicate(true);forged.battle.formation.erase("enemies");check(not model.valid(forged),"Malformed endless formation is rejected without a client exception")
			else:
				var pending:=OnlineAccount.pending_pve.duplicate(true);OnlineAccount.pending_pve={}
				var sent:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:sent.append(packet))
				var dialogue:OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate();add_child(dialogue)
				dialogue.action_requested.connect(func(action:String,target:String)->void:model.submit(action,target))
				dialogue.present_ai(EndlessRules.rules.npc.id,EndlessRules.rules.npc,snapshot.ai_world,int(snapshot.character.level),model)
				dialogue.quest_button.pressed.emit()
				check(sent.size()==1 and sent[0].command.action=="endless" and sent[0].command.expected_revision==snapshot.character.state_revision and sent[0].command.encounter_version==2,"The actual online NPC button submits the authoritative revision and new encounter protocol")
				dialogue.queue_free();OnlineAccount.pending_pve=pending
	app.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.player=old;Game.save_path=save_path;Game.local_combat=old_combat
	print("ENDLESS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
