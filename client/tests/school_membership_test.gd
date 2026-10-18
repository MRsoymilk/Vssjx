extends "res://tests/online_pve_test.gd"
const DELAYED:=preload("res://tests/fixtures/delayed_storage.gd")

func legacy(data:Dictionary)->void:
	data.erase("school_membership_version");data.school=0
	for entry in data.get("local_characters",{}).get("characters",[]):legacy(entry.data)

func _run()->void:
	var old:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	var old_pending:=OnlineAccount.pending_pve.duplicate(true)
	OnlineAccount.pending_pve={}
	Game.save_path="user://school_membership_%d.json"%OS.get_process_id()
	check((await Game.create_local_character("入派检查",1,0,1)).ok and Game.player.school==SchoolRules.UNJOINED,"New local creation ignores an old preselected school and starts unjoined")
	await Game.set_local_test_level(50)
	Game.player.gold=77;Game.player.quest=4
	await Game.save_game()
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world()
	check(app.world_identity.text.contains("闲云野鹤") and app.world.quest_marker.visible,"Unjoined identity and recruitment marker remain visible even after old quests complete")
	check(SkillRules.list_for(1,SchoolRules.UNJOINED,50).size()==8 and SkillRules.check("sheet_004",1,SchoolRules.UNJOINED,50).is_empty(),"Unjoined characters receive all level-eligible skills of their job")
	app._npc()
	var dialog:OriginalNpcDialog=app.modal
	check(dialog.extra_buttons.size()==3 and dialog.allows("school_join","kunlun"),"Original NPC paper offers three explicit school options")
	dialog.extra_buttons[2].pressed.emit()
	check(Game.player.school==SchoolRules.UNJOINED,"Local NPC action rejects recruitment while out of reach")
	app._close_modal();app.world.cell=Vector2i(10,14);Game.player.cell=[10,14];app._npc()
	dialog=app.modal
	output=OS.get_environment("SSJX_SCHOOL_CAPTURE_PATH")
	await capture("unjoined-npc")
	dialog.extra_buttons[2].pressed.emit()
	await get_tree().process_frame
	check(Game.player.school==2 and app.modal==null and app.world_identity.text.contains("昆仑派"),"Nearby NPC confirms admission only after saving and refreshes the local map")
	check(Game.player.level==50 and Game.player.gold==77 and Game.player.quest==4,"Admission preserves level, money and quest progress")
	check(SkillRules.list_for(1,2,50).size()==8 and not SkillRules.list_for(1,2,50).any(func(s:Dictionary)->bool:return s.id=="sheet_008"),"Admission retains the same job skills without opening level 55 skill")
	check(not (await Game.join_local_school(1)).ok and Game.player.school==2,"Already admitted characters cannot switch schools directly")
	check((await Game.load_game()).ok and Game.player.school==2,"Admitted membership survives reopening; reset is not repeated")
	app._attributes();app.attributes.select_tab(2)
	await capture("joined-skills")
	app._home()
	var previous:=Game.player.duplicate(true);legacy(previous)
	FileAccess.open(Game.save_path,FileAccess.WRITE).store_string(JSON.stringify(previous))
	check((await Game.load_game()).ok and Game.player.school==SchoolRules.UNJOINED and Game.player.level==50 and Game.player.gold==77,"Legacy save resets membership once without resetting progress")
	check(Game.local_character_entries().all(func(entry:Dictionary)->bool:return entry.data.school==SchoolRules.UNJOINED and entry.data.school_membership_version==1),"All stored local roster entries receive the one-time membership reset")
	var context:=Platform.context
	var storage:=DELAYED.new()
	Platform.context=PlatformContext.new("school-save-test",storage,context.runtime_config,context.display,context.lifecycle,context.resource_loader,context.text_input,context.system_actions)
	var before:=Game.player.duplicate(true)
	var results:Array=[]
	_join(results)
	check(Game.storage_busy and results.is_empty(),"Admission waits for actual persistence")
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE,"SYNC_FAILED","保存失败"))
	check(results.size()==1 and not results[0].ok and Game.player==before,"Failed admission rolls back membership atomically")
	Platform.context=context
	app.free()
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:9999");model.ready=true
	model.state=pve_state();model.state.character.school=SchoolRules.UNJOINED;model.state.character.level=50
	model.state.skills={"version":"skills-v1","catalog_sha256":SkillRules.catalog_hash,"available":SkillRules.list_for(1,SchoolRules.UNJOINED,50).map(func(s:Dictionary)->String:return s.id)}
	check(model.valid(model.state),"Online unjoined snapshots validate with all level-eligible job skills")
	var remote:OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate();add_child(remote);remote.present("qingwei",{"name":"清微道人"},model)
	check(remote.extra_buttons.size()==3 and remote.allows("school_join","kunlun"),"Online uses the same recruitment paper")
	var packets:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:packets.append(packet))
	check(model.submit("school_join","kunlun") and packets.size()==1 and packets[0].command.expected_revision==model.state.character.state_revision,"Online admission submits target and expected character revision")
	check(not model.submit("school_join","emei"),"Unconfirmed admission blocks a second request")
	remote.refresh();check(not remote.allows("school_join","kunlun"),"NPC locks admission while waiting for confirmation")
	OnlineAccount.pending_pve={};remote.free()
	if FileAccess.file_exists(Game.save_path):DirAccess.remove_absolute(Game.save_path)
	Game.save_path=old_path;Game.player=old;OnlineAccount.pending_pve=old_pending
	print("SCHOOL MEMBERSHIP: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func _join(results:Array)->void:
	results.append(await Game.join_local_school(2))
