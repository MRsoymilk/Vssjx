extends "res://tests/team_round_test.gd"

func tick(target:String,damage:int,skill:String="",packet:int=1)->Dictionary:
	return {"actor":target,"target":target,"action":"dot","skill":skill,"damage":damage,"healed":0,"critical":false,"periodic":true,"packet":packet}

func round_state()->Dictionary:
	var b:=encounter();b.commands={};b.round_revision=0;b.events_revision=0;b.selection_starts_ms=10000;b.playback_ready=[]
	return b

func install(b:Dictionary)->Control:
	var model:=OnlineTeamModel.new();model.bind_character(SELF)
	check(receive_b(model,b),"Periodic fixture is accepted through the production network validator")
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	return view

func resolved(b:Dictionary)->Dictionary:
	var next:=b.duplicate(true);next.round+=1;next.revision+=1;next.round_revision=next.revision;next.events_revision=next.revision;next.selection_starts_ms=42000;next.deadline_ms=72000;next.events=[]
	return next

func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var outbox:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	await _full_batch()
	await _death_and_revival()
	await _queued_round_waits_for_deaths()
	await _boundaries_and_cancel()
	await _server_fixture()
	Game.save_path="user://periodic_damage_%d.json"%OS.get_process_id();Game.new_player("持续伤害验证",1,3);Game.player.level=60;Game.restore()
	_local_rules()
	DirAccess.remove_absolute(Game.save_path);Game.save_path=path;Game.player=old;OnlineAccount.pending_team=outbox
	print("PERIODIC DAMAGE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func _full_batch()->void:
	var b:=round_state();b.wounds={}
	for id in ["66666666-6666-4666-8666-666666666666","77777777-7777-4777-8777-777777777777","88888888-8888-4888-8888-888888888888"]:b.fighters.append(fighter(id))
	for i in 2:
		var e:Dictionary=b.enemies[0].duplicate(true);e.slot="m%d"%(i+3);b.enemies.append(e)
	for f in b.fighters:f.hp=100;b.wounds[f.id]=[1,10]
	for e in b.enemies:e.dots={SELF+"/bleed":[1,6],OTHER+"/poison":[2,9]}
	var view:=install(b);var model:OnlineTeamModel=view.model
	var next:=resolved(b);next.wounds={}
	next.events.append({"actor":SELF,"target":"m4","action":"dot","skill":"","damage":3,"healed":0})
	for f in next.fighters:f.hp-=10;next.events.append(tick(f.id,10,"monster_bleed"))
	for e in next.enemies:
		e.hp-=15;e.dots={OTHER+"/poison":[1,9]}
		# Future producers can emit more than one periodic status for the same target.
		next.events.append(tick(e.slot,6,"future_burn"));next.events.append(tick(e.slot,9,"poison"))
	next.enemies[4].hp-=3
	check(receive_b(model,next) and view.queue.size()==16,"Reflection and all status sources arrive in one authoritative round")
	view._process(0)
	check(view.motion!=null and view._periodic_remaining==0 and view.actors.m4.hp.value==110,"Reflected damage retains its own action position")
	view._process(view.motion.duration)
	check(view.actors.m4.hp.value==107 and view.actors.m0.hp.value==110,"Reflection resolves before the periodic batch")
	# The last attack's recoil can still be playing when the round-end batch lands.
	view.actors.m4.sprite.set_frame_and_progress(view.actors.m4.sprite.sprite_frames.get_frame_count("hurt")-1,0.75)
	var popups:int=view.effects._numbers.size();view._process(0)
	check(view.motion==null and view.queue.is_empty() and is_equal_approx(view._periodic_remaining,view.PERIODIC_SECONDS),"All fifteen status events share one playback interval")
	check(view.actors.values().all(func(a:Dictionary)->bool:return a.sprite.animation==&"hurt" and a.sprite.frame==0 and a.sprite.frame_progress==0.0),"Every hurt reaction starts together, including a target still recoiling from the preceding attack")
	for f in next.fighters:check(int(view.actors[f.id].hp.value)==90,"Every player's bleed updates in the same frame")
	for e in next.enemies:check(int(view.actors[e.slot].hp.value)==int(e.hp),"Every monster's combined bleed/poison updates in the same frame")
	check(view.effects._numbers.size()==popups+10,"Multiple statuses produce one damage number per target")
	check(not model.pending() and view.action_buttons[0].disabled and not view.menu.visible,"Next-round input and completion acknowledgement wait for the whole batch")
	check(receive_b(model,next) and view.queue.is_empty(),"Repeated state snapshots cannot enqueue or apply the batch twice")
	view._process(view.PERIODIC_SECONDS/2)
	check(not model.pending() and view.effects._numbers.size()==popups+10 and view.actors.m0.hp.value==95,"Mid-batch refresh cannot duplicate damage or numbers")
	await capture("periodic-full-formation")
	view._process(view.PERIODIC_SECONDS/2)
	check(model.request.get("action")=="playback_done" and view._periodic_remaining==0,"One shared interval releases the authoritative playback acknowledgement")
	view._process(0)
	check(view.actors[SELF].status.entries.is_empty() and view.actors.m0.status.entries.size()==1 and view.actors.m0.status.entries[0].id=="poison","Expired bleed badges clear while remaining poison duration survives")
	view.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _death_and_revival()->void:
	var b:=round_state();b.monster_revision=2;b.enemies[0].elite={"party_size":2,"revives_left":1}
	for e in b.enemies:e.hp=10
	var view:=install(b);var model:OnlineTeamModel=view.model;var next:=resolved(b)
	for e in next.enemies:e.hp=0;next.events.append(tick(e.slot,10))
	next.enemies[0].hp=55;next.enemies[0].elite.revives_left=0
	next.events.append({"actor":"m0","target":"m0","action":"revive","skill":"monster_rebirth","damage":0,"healed":55})
	check(receive_b(model,next),"Lethal status batch and subsequent elite revival validate together")
	view._process(0)
	check(view.deaths.is_empty() and view.actors.m0.hp.value==0 and view.actors.m1.hp.value==0 and view.actors.m2.hp.value==0,"All lethal ticks land before any death animation or revival")
	view._process(view.PERIODIC_SECONDS/2)
	check(view.deaths.is_empty() and view.queue.size()==1,"Death presentation cannot begin halfway through the batch")
	view._process(view.PERIODIC_SECONDS/2)
	check(view.deaths.size()==3 and not view.actors.m0.sprite.visible and not view.actors.m1.sprite.visible and not view.actors.m2.sprite.visible,"All periodic deaths start together after the shared interval")
	view._process(0)
	check(view.queue.size()==1 and not model.pending(),"Elite revival and next-round acknowledgement wait for death playback")
	await capture("periodic-simultaneous-deaths")
	for death in view.deaths:death.advance(death.remaining())
	view._process(0)
	check(view.motion!=null and view.actors.m0.sprite.visible and view.actors.m0.hp.value==55 and view.queue.is_empty(),"Revival happens only after the batch's native deaths finish")
	view._process(view.motion.duration)
	check(model.request.get("action")=="playback_done","Revival completes before the round is acknowledged")
	var victory:=resolved(next);victory.outcome="victory";victory.enemies[0].hp=0;victory.events=[tick("m0",55)]
	victory.events[0].erase("periodic")
	check(receive_b(model,victory),"Old self-targeted DOT receipts without batch metadata remain compatible")
	view._process(0);view._process(view.PERIODIC_SECONDS)
	check(not view.result.visible and view.deaths.size()==3,"Victory waits for the final periodic KO and its death effect")
	for death in view.deaths:death.advance(death.remaining())
	view._process(0)
	check(view.result.outcome=="victory","Victory is shown after every periodic death has completed")
	view.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _boundaries_and_cancel()->void:
	var b:=round_state();var view:=install(b)
	var future:=tick("m0",7,"future_corrosion");var next_round:=tick("m1",9,"poison",2)
	view.queue=[future,next_round];view._process(0)
	check(view.actors.m0.hp.value==103 and view.actors.m1.hp.value==110 and view.queue.size()==1,"Different authoritative rounds cannot merge into one damage batch")
	view._process(view.PERIODIC_SECONDS);view._process(0)
	check(view.actors.m1.hp.value==101 and view._periodic_remaining>0,"Future periodic status names automatically use the shared batch")
	view._cancel()
	check(view._periodic_remaining==0 and view._periodic_targets.is_empty() and view.queue.is_empty() and view.effects._numbers.is_empty(),"Leaving or replacing a battle clears the complete batch without delayed callbacks")
	var valid:=b.duplicate(true);valid.events=[tick("m0",7)]
	check(OnlineTeamModel.valid_battle(valid,SELF,{SELF:true,OTHER:true}),"Typed periodic metadata is accepted")
	for invalid in ["yes",1,{},null]:
		valid.events[0].periodic=invalid
		check(not OnlineTeamModel.valid_battle(valid,SELF,{SELF:true,OTHER:true}),"Malformed periodic metadata cannot reach playback")
	valid.events[0]=tick("m0",7);valid.events[0].actor=SELF
	check(not OnlineTeamModel.valid_battle(valid,SELF,{SELF:true,OTHER:true}),"Reflections cannot masquerade as periodic self damage")
	valid.events[0]=tick("m0",7);valid.events[0].healed=5
	check(not OnlineTeamModel.valid_battle(valid,SELF,{SELF:true,OTHER:true}),"Healing is not combined with the damage-only batch")
	view.queue_free();await get_tree().process_frame

func _queued_round_waits_for_deaths()->void:
	var b:=round_state();b.enemies[0].hp=10
	var view:=install(b);var model:OnlineTeamModel=view.model
	var next:=resolved(b);next.enemies[0].hp=0;next.events=[tick("m0",10)]
	check(receive_b(model,next),"First round's lethal periodic receipt validates")
	view._process(0)
	var later:=resolved(next);later.enemies[1].hp-=7
	later.events=[{"actor":SELF,"target":"m1","action":"attack","skill":"","damage":7,"healed":0}]
	check(receive_b(model,later) and view.queue.size()==1,"A delayed client can receive the next round during periodic playback")
	view._process(view.PERIODIC_SECONDS)
	check(view.deaths.size()==1 and is_equal_approx(view.deaths[0].remaining(),view.deaths[0].duration) and view.actors.m1.hp.value==110,"Periodic completion starts the native death without consuming its animation time")
	view._process(0)
	check(view.motion==null and view.queue.size()==1,"An ordinary next-round action cannot start before all batch deaths finish")
	# Server fallback can already open selection while a delayed renderer is busy.
	model.server_time=42000;model.received_at=Time.get_ticks_msec()
	view._send("guard")
	check(not model.pending(),"Direct skill/item submission also waits for the death barrier")
	for death in view.deaths:death.advance(death.remaining())
	view._process(0)
	check(view.motion!=null and view.queue.is_empty() and not model.pending(),"Next-round actions resume once the entire batch's deaths finish")
	view.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _server_fixture()->void:
	var path:=OS.get_environment("SSJX_PERIODIC_FIXTURE")
	if path.is_empty():return
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));var who:String=data.before.fighters[0].id;var ids:={}
	for f in data.before.fighters:ids[f.id]=true
	check(OnlineTeamModel.valid_battle(data.before,who,ids) and OnlineTeamModel.valid_battle(data.after,who,ids),"Actual Rust before/after snapshots validate in Godot")
	var model:=OnlineTeamModel.new();model.bind_character(who);model.state={"team":{"battle":data.before,"leader":true},"incoming":[]};model.server_time=1000;model.received_at=Time.get_ticks_msec()
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	model.state.team.battle=data.after;model.changed.emit()
	for frame in 2400:
		view._process(1.0/60.0)
		if view._periodic_remaining>0:break
	check(view._periodic_targets.size()==10 and view.queue.is_empty(),"Actual server healing events precede one ten-target periodic batch")
	for f in data.after.fighters:check(int(view.actors[f.id].hp.value)==int(f.hp),"Server and displayed fighter HP agree at simultaneous impact")
	for e in data.after.enemies:check(int(view.actors[e.slot].hp.value)==int(e.hp),"Server and displayed monster HP agree at simultaneous impact")
	view.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _local_rules()->void:
	var wolf:Dictionary=SharedWorldMap.population("qingyun_trail").filter(func(d:Dictionary)->bool:return d.id=="wolf_a")[0]
	var solo:=SoloEncounter.new();solo.start([wolf,wolf,wolf]);solo.engine.hp=100
	solo.state.wounds[solo.character_id]=[2,10]
	for e in solo.state.enemies:e.hp=100;e.definition.hp=100;e.effects.enemy_sleep=3;e.effects.enemy_bleed=1;e.effects.bleed_damage=6;e.effects.enemy_poison=2;e.effects.poison_damage=9
	solo._enemy_round()
	check(solo.engine.hp==90 and int(solo.state.wounds[solo.character_id][0])==1,"Offline player bleed ticks once per complete round")
	check(solo.state.events.size()==4 and solo.state.events.all(func(e:Dictionary)->bool:return e.get("periodic",false)),"Offline player and all monsters emit the same generic batch metadata")
	for e in solo.state.enemies:check(int(e.hp)==85 and int(e.effects.enemy_bleed)==0 and int(e.effects.enemy_poison)==1,"Offline mixed statuses combine damage and decrement separately")
	solo.state.events=[];solo._enemy_round()
	check(solo.engine.hp==80 and solo.state.wounds.is_empty() and solo.state.enemies.all(func(e:Dictionary)->bool:return int(e.hp)==76 and int(e.effects.enemy_poison)==0),"Last status tick removes the expired counter without an extra bleed tick")
