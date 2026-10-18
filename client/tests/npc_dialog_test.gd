extends "res://tests/shared_interface_test.gd"

func snapshot(dialog: OriginalNpcDialog) -> Array:
	return [dialog.get_node("Paper/Name").text,dialog.get_node("Paper/Greeting").text,
		dialog.quest_button.text,dialog.quest_button.visible,dialog.quest_button.disabled,
		dialog.restore_button.visible,dialog.restore_button.disabled,dialog.hint.text,dialog.get_node("Paper").get_rect()]

func _run() -> void:
	var old := Game.player.duplicate(true)
	var pending := OnlineAccount.pending_pve.duplicate(true)
	OnlineAccount.pending_pve={}
	Game.new_player("对话校验",1,0)
	var model := OnlinePve.new();model.ready=true
	model.state={"character":{"school":0,"quest_stage":0,"hp":Game.player.hp,"mp":Game.player.mp,"level":1},"stats":Game.stats(),"progress":{"kills":0},"battle":null}
	var local_dialog: OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate()
	var online_dialog: OriginalNpcDialog=load("res://scenes/ui/npc_dialog.tscn").instantiate()
	add_child(local_dialog);add_child(online_dialog)
	output=OS.get_environment("SSJX_NPC_CAPTURE_PATH") if DisplayServer.get_name()!="headless" else ""
	for stage in [0,1,2,3]:
		Game.player.quest=stage;Game.player.kills=1
		model.state.character.quest_stage=stage;model.state.progress.kills=1
		local_dialog.present_local({"id":"qingwei","name":"清微道人"})
		online_dialog.present("qingwei",{"name":"清微道人"},model)
		check(snapshot(local_dialog)==snapshot(online_dialog),"Local and online legacy NPC use identical paper, actions and progress at stage "+str(stage))
	Game.player.ai_map="ai_001"
	var state := AIWorld.progress()
	model.state.ai_world=state.duplicate(true)
	var guide := AIWorld.resident("ai_001_guide")
	local_dialog.present_ai(guide.id,guide,state,1)
	online_dialog.present_ai(guide.id,guide,state,1,model)
	check(snapshot(local_dialog)==snapshot(online_dialog),"AI acceptance has identical paper and task rows in both modes")
	check(local_dialog.quest_button.text.contains("接受") and not local_dialog.quest_button.disabled,"Available AI quest is an explicit NPC option")
	check(local_dialog.get_node("Paper").size.y<300 and not local_dialog.has_node("Tabs"),"NPC talk stays a compact original option list")
	online_dialog.hide();await capture("local-ai-npc-available")
	local_dialog.hide();online_dialog.show();await capture("online-ai-npc-available")
	state.active.ai_001_q1=[0,0];model.state.ai_world=state.duplicate(true)
	local_dialog.refresh();online_dialog.refresh()
	check(snapshot(local_dialog)==snapshot(online_dialog) and local_dialog.quest_button.text.contains("0/2") and local_dialog.quest_button.disabled,"Accepted task progress and repeat-accept prevention agree")
	check(AIWorld.npc_marker("ai_001_survey",state,1).stage==2 and AIWorld.npc_marker("ai_001_courier",state,1).stage==-1,"Ordered target marker is shared by both maps")
	check(AIWorld.event("interact","ai_001_survey"),"First NPC objective advances the shared progress")
	check(AIWorld.npc_marker("ai_001_survey",state,1).stage==-1 and AIWorld.npc_marker("ai_001_courier",state,1).stage==2,"Objective marker moves to the next NPC")
	check(AIWorld.event("interact","ai_001_courier"),"Delivery advances the shared progress")
	model.state.ai_world=state.duplicate(true);local_dialog.refresh();online_dialog.refresh()
	check(snapshot(local_dialog)==snapshot(online_dialog) and local_dialog.quest_button.text.contains("完成") and not local_dialog.quest_button.disabled,"Both modes offer the same turn-in option")
	check(AIWorld.npc_marker(guide.id,state,1).stage==2,"Ready reward returns the marker to the publisher")
	await capture("online-ai-npc-ready")
	var requests: Array=[]
	online_dialog.action_requested.connect(func(action:String,id:String)->void:requests.append([action,id]))
	OnlineAccount.pending_pve={"command":{"action":"ai_claim"}}
	online_dialog.refresh();online_dialog.quest_button.pressed.emit()
	check(requests.is_empty() and online_dialog.quest_button.disabled and online_dialog.restore_button.disabled,"Pending online receipt blocks duplicate NPC options")
	OnlineAccount.pending_pve={};model.ready=false;online_dialog.refresh()
	check(online_dialog.hint.text.contains("连接中断") and not online_dialog.allows("ai_claim","ai_001_q1"),"Reconnection stays inline and cannot submit from stale state")
	model.ready=true
	var ambient := AIWorld.resident("ai_213_npc03")
	online_dialog.present_ai(ambient.id,ambient,{},60,model)
	check(not online_dialog.quest_button.visible and not online_dialog.restore_button.visible,"Ambient NPC does not acquire unrelated tasks or free restoration")
	state.active.clear();state.completed=["ai_001_q1","ai_001_q2","ai_001_q3"];model.state.ai_world=state.duplicate(true)
	local_dialog.present_ai(guide.id,guide,state,1);online_dialog.present_ai(guide.id,guide,state,1,model)
	check(snapshot(local_dialog)==snapshot(online_dialog) and local_dialog.quest_button.text.contains("[完成]") and local_dialog.quest_button.disabled,"Completed AI chain keeps the same explicit completed row as the legacy NPC")
	local_dialog.queue_free();online_dialog.queue_free();await get_tree().process_frame
	Game.player=old;OnlineAccount.pending_pve=pending
	print("NPC DIALOG: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
