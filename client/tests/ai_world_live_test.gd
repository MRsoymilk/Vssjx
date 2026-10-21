extends "res://tests/online_maps_live_test.gd"

func _run() -> void:
	var old := Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_AI_TEST_BASE"),"ai_ui","owned-ai-world-password")
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Owned expansion account logs in")
	OnlineAccount.list_characters();await OnlineAccount.completed
	if OnlineAccount.characters.is_empty(): get_tree().quit(1);return
	view=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=OnlineAccount.characters[0].id;add_child(view)
	view.network.status_changed.connect(func(text: String)->void:print("AI LIVE STATUS: ",text))
	view.network.status_changed.connect(func(text: String)->void:connection_statuses.append(text))
	check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and view.residents.size()==SharedWorldMap.population("ai_001").size()),"Shared AI map, hash, residents and progress (including guardian) validate")
	if not view.network.pve.ready: print(view._system_text);get_tree().quit(1);return
	check(view.map_data==SharedWorldMap.load_data("ai_001"),"Offline and online use identical generated layout")
	check(view.network._maps_version==2,"Real client negotiates expansion support from the ticket capability")
	check("AI生成" in view.screen.hud.get_node("MapName").text,"HUD marks synthetic scene")
	view._open_ai("quests","ai_001_guide")
	check(await wait_until(func()->bool:return view.npc_dialog.visible and view.npc_dialog.target=="ai_001_guide",30),"Walk to giver and open the same original NPC paper dialogue")
	view.npc_dialog.quest_button.pressed.emit()
	check(await wait_until(func()->bool:return not view.network.pve.pending() and view.network.pve.state.ai_world.active.has("ai_001_q1")),"Client walks to guide and accepts authoritative quest")
	check(await talk_to("ai_001_survey"),"Walk to the marked survey NPC before choosing its task option")
	view.npc_dialog.quest_button.pressed.emit()
	check(await wait_until(func()->bool:return int(view.network.pve.state.ai_world.active.ai_001_q1[0])==1),"Client walks to survey landmark")
	check(await talk_to("ai_001_courier"),"Delivery uses the same NPC option list")
	view.npc_dialog.quest_button.pressed.emit()
	check(await wait_until(func()->bool:return int(view.network.pve.state.ai_world.active.ai_001_q1[1])==1),"Client delivers findings")
	check(await talk_to("ai_001_guide"),"Return to publisher for the original completion option")
	view.npc_dialog.quest_button.pressed.emit()
	check(await wait_until(func()->bool:return "ai_001_q1" in view.network.pve.state.ai_world.completed),"Quest reward arrives through server receipt")
	view._close_inventory()
	var exit: Dictionary=SharedWorldMap.exits("ai_001").filter(func(g:Dictionary)->bool:return g.target_map=="ai_002")[0]
	view.network.move_to(Vector2i(exit.cell[0],exit.cell[1]))
	check(await wait_until(func()->bool:return view.map_transition.blocking,30),"Generated map exits show the shared original-style loading page")
	check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id=="ai_002" and view.residents.has("ai_002_guide"),30),"Station approach transfers and automatically reconnects to another AI map")
	check(view.network.pve.state.ai_world.completed_count==1 and not view.network.pve.state.ai_world.completed.has("ai_001_q1"),"Network sends current-map history and global count only")
	check(await wait_until(func()->bool:return not view.map_transition.blocking),"AI destination is fully synchronized before loading ends")
	view._close_inventory()
	view._resident_action("challenge","ai_002_mob")
	check(await wait_until(func()->bool:return view.network.pve.active() and (view.battle_view.visible or view.solo_battle.visible),30),"New regional monster reaches the real online battle view")
	if view.network.pve.active():
		check(view.network.pve.state.battle.enemy.art==AIWorld.resident("ai_002_mob").art,"Battle uses the same distinct monster as the map")
		view.network.pve.submit("flee")
		check(await wait_until(func()->bool:return not view.network.pve.active() and not view.network.pve.pending()),"New monster battle settles through authoritative protocol")
		check(await wait_until(func()->bool:return not view.battle_view.visible and not view.solo_battle.visible),"Original result presentation automatically returns to the map")
	var return_gate: Dictionary=SharedWorldMap.exits("ai_002")[0]
	view.network.move_to(Vector2i(return_gate.cell[0],return_gate.cell[1]))
	check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and not view.network.pve.pending() and view.network.map_id=="qingyun_trail",30),"Return to existing world from generated scene")
	check(await wait_until(func()->bool:return not view.map_transition.blocking),"Return from AI maps restores input after loading")
	check(Game.player==old,"Online expansion never touches local player")
	check(not connection_statuses.any(func(text: String)->bool:return text.begins_with("连接中断")),"Generated map round trip has no false disconnect or stopped reconnect")
	view.network.leave();view.queue_free();await get_tree().process_frame
	print("AI WORLD LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func talk_to(id: String) -> bool:
	view._resident_action("ai_npc",id)
	return await wait_until(func()->bool:return view.npc_dialog.visible and view.npc_dialog.target==id,30)
