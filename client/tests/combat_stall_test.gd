extends "res://tests/duel_test.gd"

func _run()->void:
	await Platform.when_ready()
	var captures:=OS.get_environment("SSJX_DUEL_CAPTURE")
	if not captures.is_empty():DirAccess.make_dir_recursive_absolute(captures)
	var texture:=GradientTexture2D.new()
	# Real SpriteFrames at timings not exactly representable by Godot's scalar helpers.
	for rate in [7.0,10.0,15.0]:
		for count in range(1,31):
			var actor:=AnimatedSprite2D.new();var frames:=SpriteFrames.new()
			frames.add_animation("idle");frames.add_frame("idle",texture)
			frames.add_animation("attack");frames.set_animation_speed("attack",rate)
			for i in count:frames.add_frame("attack",texture)
			actor.sprite_frames=frames;add_child(actor)
			var playback:=BattleActionPlayback.new();var signals:=[0,0]
			playback.impact.connect(func()->void:signals[0]+=1)
			playback.completed.connect(func()->void:signals[1]+=1)
			playback.start(actor,{},Vector2.ZERO)
			for i in ceili(playback.duration*60)+10:playback.advance(1.0/60.0)
			check(not playback.active and playback.remaining()==0.0 and signals==[1,1],"Playback terminates exactly once: %d frames at %d FPS"%[count,int(rate)])
			playback.advance(10)
			check(signals==[1,1],"Completed playback is idempotent")
			actor.free()
	for mode in ["missing","empty","zero_speed"]:
		var actor:=AnimatedSprite2D.new();var frames:=SpriteFrames.new()
		if mode!="missing":frames.add_animation("attack")
		if mode=="zero_speed":frames.add_frame("attack",texture);frames.set_animation_speed("attack",0)
		actor.sprite_frames=frames;add_child(actor)
		var p:=BattleActionPlayback.new();var signals:=[0,0]
		p.impact.connect(func()->void:signals[0]+=1);p.completed.connect(func()->void:signals[1]+=1)
		p.start(actor,{},Vector2.ZERO);p.advance(1.0/60.0)
		check(not p.active and p.remaining()==0.0 and signals==[1,1],"Unavailable animation cannot hold a combat queue: "+mode)
		actor.free()
	var actor:=OriginalArt.battle_actor("hero/mck");add_child(actor)
	var malformed:=BattleActionPlayback.new();var hits:=[0,0]
	malformed.impact.connect(func()->void:hits[0]+=1);malformed.completed.connect(func()->void:hits[1]+=1)
	malformed.start(actor,{"native_battle":{"impact_steps":{"attack":[999]}}},Vector2.ZERO)
	malformed.advance(10)
	check(not malformed.active and hits==[1,1],"Out-of-range native metadata cannot strand an otherwise valid actor")
	actor.free()
	actor=AnimatedSprite2D.new();actor.sprite_frames=SpriteFrames.new();add_child(actor)
	malformed.start(actor,{},Vector2.ZERO);malformed.advance(1.0/60.0)
	check(not malformed.active and hits==[2,2],"Reusing a playback with missing frames clears its preceding hit deadline")
	actor.free()
	await _duel_skills()
	await _team_queue()
	print("COMBAT STALL: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func _duel_skills()->void:
	var world:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
	world.character_id=SELF;add_child(world);world.set_process(false);world.network.set_process(false);world.duel_battle.set_process(false)
	var duel:OnlineDuel=world.network.duel;duel.enabled=true
	var revision:=0
	for skill in SkillRules.catalog.items:
		if not skill.active:continue
		var b:=battle();b.id="99999999-9999-4999-8999-%012d"%revision
		for f in b.fighters:f.job=int(skill.job);f.level=60;f.effects=SkillRules.new_state(int(skill.job),3,60,60)
		var packet:=state(revision);packet.battle=b
		check(duel.receive(packet),"Duel baseline accepts job for "+skill.id)
		var first:Array=b.fighters.duplicate(true);first[1].effects.last_skill=skill.id
		var second:Array=first.duplicate(true);second[0].effects.last_skill=skill.id
		b.events=[{"actor":OTHER,"action":"skill","skill":skill.id,"damage":0,"reflected":0,"fighters":first},{"actor":SELF,"action":"skill","skill":skill.id,"damage":0,"reflected":0,"fighters":second}]
		b.fighters=second;b.revision="3";b.phase="resolving";b.resolved_round=1;b.submitted=[true,true];b.your_choice={"action":"skill","skill":skill.id};revision+=1;packet.revision=str(revision)
		check(duel.receive(packet),"Both authoritative casts accepted for "+skill.id)
		b.phase="planning";b.round=2;b.decision_revision="1";b.revision="4";b.submitted=[false,false];b.your_choice=null;revision+=1;packet.revision=str(revision)
		check(duel.receive(packet),"Next decision may arrive while casts play")
		for i in 600:
			world.duel_battle._process(1.0/60.0)
			if not world.duel_battle.adapter.playing:break
		check(not world.duel_battle.adapter.playing and world.duel_battle.animation_time==0 and not world.duel_battle.buttons[0].disabled,"Duel always releases input after both casts: "+skill.id)
		revision+=1
		await get_tree().process_frame
	await capture("stall-duel-skills")
	world.free();await get_tree().process_frame

func _team_queue()->void:
	var saved:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var helper:Node=load("res://tests/team_test.gd").new()
	var model:RefCounted=preload("res://scripts/network/online_team.gd").new();model.bind_character(SELF)
	model.bind_character(helper.SELF)
	model.request={"action":"snapshot","character_id":helper.SELF};model.inflight=true
	check(model.receive(helper.response(model,helper.state(helper.encounter()))),"Install team battle before a delayed refresh")
	model.refresh();model.inflight=true
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	check(not view.action_buttons[0].disabled,"Automatic refresh never disables combat buttons")
	check(model.submit("attack","m0"),"Player choice queues behind in-flight snapshot")
	var command:Dictionary=OnlineAccount.pending_team.request.duplicate(true)
	check(model.pending() and not model.submit("guard") and model.request.action=="snapshot","Queued choice locks only repeats, preserving read correlation")
	check(model.receive(helper.response(model,helper.state(helper.encounter()))),"Delayed read still validates against its original request")
	check(model.request==command and OnlineAccount.pending_team.request==command and model.next_poll==0,"Read acknowledgement promotes, never erases, the player's UUID")
	var sent:Array=[];model.send_requested.connect(func(payload:Dictionary)->void:sent.append(payload))
	model.tick(true);check(sent==[command],"Queued command is sent ahead of the next poll")
	model.receive({"ok":false,"code":"NETWORK_ERROR"})
	check(model.request==command and OnlineAccount.pending_team.request==command,"Ambiguous write failure retains original UUID for retry")
	model.next_poll=0;model.tick(true)
	check(sent==[command,command],"Retry sends the exact same intent, not a new attack")
	var restored:RefCounted=preload("res://scripts/network/online_team.gd").new();restored.bind_character(helper.SELF)
	check(restored.request==command,"Rebinding restores the queued or uncertain write from the account-owned outbox")
	model.request={};model.inflight=false;model.refresh();model.inflight=true
	check(model.submit("guard"),"A second read may queue a new legal choice after the previous request is cleared")
	var second:Dictionary=OnlineAccount.pending_team.request.duplicate(true)
	model.receive({"ok":false,"code":"NETWORK_ERROR"})
	check(model.request==second and OnlineAccount.pending_team.request==second and model.next_poll==0,"Failure of a background read cannot erase or delay its queued choice")
	model.request={};model.inflight=false;model.refresh();model.inflight=true;model.submit("guard")
	model.receive({"ok":false,"code":"UNAUTHORIZED"})
	check(model.request.is_empty() and model.queued_command.is_empty() and OnlineAccount.pending_team.is_empty(),"Revoked authorization drops queued writes rather than replaying them under another session")
	view.queue_free();helper.free();await get_tree().process_frame
	OnlineAccount.pending_team=saved
