extends "res://tests/team_test.gd"

func receive_b(model:RefCounted,b:Dictionary)->bool:
	model.request={"character_id":SELF,"action":"snapshot"};model.inflight=true
	var packet:=state(b)
	for f in b.fighters:
		if f.id not in [SELF,OTHER]:packet.team.members.append(member(f.id))
	return model.receive(response(model,packet))

func _run()->void:
	await Platform.when_ready()
	var local:=Game.player.duplicate(true)
	var saved:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var model:RefCounted=preload("res://scripts/network/online_team.gd").new();model.bind_character(SELF)
	var b:=encounter()
	b.commands={};b.round_revision=0;b.events_revision=0;b.selection_starts_ms=10000
	for id in ["66666666-6666-4666-8666-666666666666","77777777-7777-4777-8777-777777777777","88888888-8888-4888-8888-888888888888"]:b.fighters.append(fighter(id))
	for i in 2:
		var e:Dictionary=b.enemies[0].duplicate(true);e.slot="m%d"%(i+3);b.enemies.append(e)
	check(receive_b(model,b),"Full-party shared input window validates")
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	check(view.actors.size()==10,"Five players and five monsters render together")
	model.character_id=OTHER
	check(model.my_turn(),"Non-leading player can submit before the first formation slot")
	model.character_id=SELF
	check(model.my_turn() and view.hint.text.contains("0/5"),"All living players share the same collection window")
	view._process(0)
	await capture("round-select")
	view._send("attack")
	check(model.request.action=="attack" and model.request.expected_revision==0,"Choosing attack submits intent, not a local damage calculation")
	model.inflight=true
	b.commands[SELF]={"action":"attack","target":"m0","skill":null};b.revision=1
	check(model.receive(response(model,state(b)))==false,"Malformed five-member packet without complete membership is rejected")
	model.request={};model.inflight=false;OnlineAccount.pending_team={}
	check(receive_b(model,b) and not model.my_turn(),"Accepted intent locks only this player's commands")
	check(view.queue.is_empty() and view.motion==null and view.actors.m0.hp.value==110,"Collection snapshots never play attacks or mutate visible HP")
	check(not model.submit("guard"),"Second command for the same round is blocked locally")
	var bad:=b.duplicate(true);bad.deadline_ms+=1
	model.request={"character_id":SELF,"action":"snapshot"}
	check(not model.valid(response(model,state(bad))),"Invalid shared window length is rejected")
	b.commands[OTHER]={"action":"guard","target":null,"skill":null};b.revision=2
	check(receive_b(model,b) and view.queue.is_empty() and b.deadline_ms==40000,"Other submissions preserve deadline and do not replay prior events")
	for broken in [{"action":"skill","target":"m0","skill":7},{"action":"teleport","target":"m0","skill":null},{"action":"attack","target":[0,0],"skill":null}]:
		var malformed:=b.duplicate(true);malformed.commands[OTHER]=broken
		model.request={"character_id":SELF,"action":"snapshot"}
		var packet:=state(malformed)
		for f in b.fighters:
			if f.id not in [SELF,OTHER]:packet.team.members.append(member(f.id))
		check(not model.valid(response(model,packet)),"Malformed queued intents cannot reach skill or target rendering")
	var resolved:=b.duplicate(true);resolved.commands={};resolved.revision=6;resolved.round_revision=6;resolved.events_revision=6;resolved.round=2
	resolved.selection_starts_ms=42000;resolved.deadline_ms=72000;resolved.events=[]
	for i in 5:
		resolved.enemies[i].hp-=40;resolved.fighters[i].hp-=9
		resolved.events.append({"actor":resolved.fighters[i].id,"target":"m%d"%i,"action":"attack","skill":"","damage":40,"healed":0})
	for i in 5:resolved.events.append({"actor":"m%d"%i,"target":resolved.fighters[i].id,"action":"attack","skill":"","damage":9,"healed":0})
	check(receive_b(model,resolved) and view.queue.size()==10,"A resolved round queues all five player and five monster actions")
	check(view.actors.m0.hp.value==110,"Final server HP is not shown ahead of the first action impact")
	var actors_seen:Array=[]
	for i in 10:
		view._process(0)
		check(view.motion!=null and view.playing.actor==resolved.events[i].actor,"Only the next authoritative actor begins: %d"%i)
		actors_seen.append(view.playing.actor)
		var duration:float=view.motion.duration
		check(duration<=3.0,"Native action fits the separate server presentation allowance")
		var remaining:int=view.queue.size()
		view._process(duration*0.6)
		check(view.queue.size()==remaining and view.motion!=null,"No second actor starts while the first is still playing")
		if i==0:
			check(view.actors.m0.hp.value==70 and view.actors.m1.hp.value==110,"Health changes one target at a time at the impact frame")
			await capture("round-player-action")
		if i==5:await capture("round-monster-action")
		view._process(duration)
	check(actors_seen.size()==10 and view.queue.is_empty() and view.motion==null,"All ten actions finish one at a time without truncation")
	view._process(0)
	check(view.actors.m4.hp.value==70,"Visible resources reconcile after complete playback")
	check(receive_b(model,resolved) and view.queue.is_empty(),"Repeated poll of the same event revision cannot replay attacks")
	resolved.revision=7;resolved.commands[OTHER]={"action":"guard","target":null,"skill":null}
	check(receive_b(model,resolved) and view.queue.is_empty(),"Next-round intent revisions never replay the preceding round")
	model.server_time=42000;model.received_at=Time.get_ticks_msec()
	check(model.my_turn(),"Next input window grants its own complete 30 seconds after presentation")
	model.server_time=72000
	check(not model.my_turn(),"Commands close at the common deadline")
	model.server_time=42000;view._refresh_controls();await capture("round-next-window")
	var fixtures:=OS.get_environment("SSJX_TEAM_ROUND_FIXTURES")
	if not fixtures.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(fixtures)):
			model.character_id=snapshot.character_id;model.request={"action":"snapshot"}
			check(model.valid(snapshot),"Actual server collected/resolved round validates in the production client")
	view.queue_free();await get_tree().process_frame
	check(Game.player==local,"Round test never overwrites the local player")
	OnlineAccount.pending_team=saved
	print("TEAM ROUND: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
