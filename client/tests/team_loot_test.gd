extends "res://tests/team_test.gd"
func _run()->void:
	await Game.when_ready()
	var input:=OS.get_environment("SSJX_TEAM_LOOT_FIXTURES")
	check(not input.is_empty(),"ROLL regression requires real server responses")
	if input.is_empty():get_tree().quit(1);return
	var fixtures:Array=JSON.parse_string(FileAccess.get_file_as_string(input));var previous:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var captures:=OS.get_environment("SSJX_TEAM_LOOT_CAPTURE");var captured:={}
	for response in fixtures:
		var model:=OnlineTeamModel.new();model.bind_character(response.character_id);model.request={"action":"snapshot","operation_id":response.operation_id};model.inflight=true
		check(model.receive(response),"Actual shared loot, eligibility, choices, points and ownership pass the production decoder")
		var pool:=model.loot_pool();check(not pool.is_empty(),"Shared loot survives in the ended battle snapshot")
		var forged:Dictionary=response.duplicate(true);forged.state.team.battle.loot_pool.deadline_ms=0
		model.request={"operation_id":forged.operation_id};check(not model.valid(forged),"Malformed roll deadlines are rejected")
		forged=response.duplicate(true)
		var d:Dictionary=forged.state.team.battle.loot_pool.drops[0];d.choices[model.character_id]=101
		model.request={"operation_id":forged.operation_id};check(not model.valid(forged),"Forged scores outside 1..100 never reach the loot screen")
		model.request={};var panel:=TeamLootPanel.new();panel.model=model;add_child(panel)
		var drop:Dictionary=pool.drops[0]
		if not drop.resolved and not drop.choices.has(model.character_id):
			check(not panel.roll.disabled and not panel.pass_button.disabled,"Eligible undecided members see both ROLL and pass")
			var packets:Array=[];model.send_requested.connect(func(p:Dictionary)->void:packets.append(p))
			panel.roll.pressed.emit();model.tick(true)
			check(packets.size()==1 and packets[0].action=="loot_roll" and packets[0].target==drop.item.id and packets[0].battle_id==model.battle().id and not packets[0].has("roll") and not packets[0].has("score"),"Actual ROLL button submits only identity and revision, never client-generated dice")
			check(panel.roll.disabled and panel.pass_button.disabled,"A pending decision cannot be clicked repeatedly")
		else:
			check(panel.roll.disabled and panel.pass_button.disabled,"Committed choices and resolved loot disable both buttons")
			check(panel.results.text.contains("ROLL") or panel.results.text.contains("放弃"),"The screen shows each participant's committed score or pass")
		var phase:="resolved" if drop.resolved else ("rolling" if not drop.choices.is_empty() else "pending")
		if not captures.is_empty() and not captured.has(phase) and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(captures)
			for frame in 3:await get_tree().process_frame
			RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(captures.path_join(phase+".png"))==OK,"Actual shared-loot screen renders "+phase);captured[phase]=true
		panel.queue_free();await get_tree().process_frame
		OnlineAccount.pending_team={};model.request={};model.inflight=false
		var page:Control=load("res://scenes/ui/team_panel.tscn").instantiate();page.model=model;add_child(page)
		var entry:Button
		for row in page.footer.get_children():
			for child in row.get_children():
				if child is Button and child.text=="战利品":entry=child
		check(entry!=null,"Returning to the world keeps a visible team-window loot entry")
		if entry!=null:entry.pressed.emit()
		check(page.has_node("TeamLoot"),"The native team-window entry reopens the same authoritative loot pool")
		page.queue_free();await get_tree().process_frame
	var five:Dictionary=fixtures[0].duplicate(true)
	for name in ["天涯明月清风剑客","山河故人醉卧云端"]:
		var id:=LootRules.uuid();var f:Dictionary=five.state.team.battle.fighters[-1].duplicate(true);f.id=id;f.name=name;five.state.team.battle.fighters.append(f)
		var member:Dictionary=five.state.team.members[-1].duplicate(true);member.id=id;member.display_name=name;member.leader=false;five.state.team.members.append(member)
		five.state.team.battle.loot_pool.members.append(id)
		for d in five.state.team.battle.loot_pool.drops:d.eligible.append(id)
	var full:=OnlineTeamModel.new();full.bind_character(five.character_id);full.request={"action":"snapshot","operation_id":five.operation_id};full.inflight=true
	check(full.receive(five),"Five-member long-name presentation fixture retains valid participant and eligibility bounds")
	var expanded:=TeamLootPanel.new();expanded.model=full;add_child(expanded)
	check(expanded.results.text.split("\n").size()==5 and expanded.results.get_parent() is ScrollContainer,"Five names and scores remain readable in a bounded board without covering ROLL/pass buttons")
	if not captures.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(captures.path_join("five-members.png"))==OK,"Actual five-member loot presentation renders")
	expanded.queue_free();await get_tree().process_frame
	OnlineAccount.pending_team=previous
	print("TEAM LOOT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
