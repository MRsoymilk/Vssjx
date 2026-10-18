extends "res://tests/online_maps_live_test.gd"

func _run()->void:
	var old:=Game.player.duplicate(true)
	OnlineAccount.login(OS.get_environment("SSJX_SCHOOL_TEST_BASE"),"school_ui","owned-school-password")
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Owned recruitment account logs in")
	OnlineAccount.list_characters();await OnlineAccount.completed
	if OnlineAccount.characters.is_empty():get_tree().quit(1);return
	view=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=OnlineAccount.characters[0].id;add_child(view)
	if not await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and view.residents.has("qingwei")):
		check(false,"Unjoined online state synchronizes");view.queue_free();get_tree().quit(1);return
	check(view.network.pve.state.character.school==SchoolRules.UNJOINED and view.screen.hud.get_node("WorldIdentity").text.contains("闲云野鹤"),"Online map displays unjoined identity")
	check(view.network.pve.state.skills.available.size()==8,"Level 50 unjoined character receives all eligible job skills")
	view.resident_selected.emit("qingwei")
	check(await wait_until(func()->bool:return view.npc_dialog.visible and view._approach.is_empty()),"Clicking actual NPC walks within recruitment range")
	if not view.npc_dialog.visible:view.queue_free();get_tree().quit(1);return
	check(view.npc_dialog.extra_buttons.size()==3,"NPC displays all three school choices")
	view.npc_dialog.extra_buttons[2].pressed.emit()
	check(await wait_until(func()->bool:return view.network.pve.ready and not view.network.pve.pending() and view.network.pve.state.character.school==2),"Real dialog button completes authoritative admission")
	check(not view.npc_dialog.visible and view.screen.hud.get_node("WorldIdentity").text.contains("昆仑派"),"Receipt closes dialogue and refreshes membership")
	check(view.network.pve.state.skills.available.size()==8 and view.network.pve.state.skills.available.has("sheet_004"),"Admission preserves all level 50 job skills")
	check(not view.network.pve.submit("school_join","emei"),"Joined UI blocks direct faction switching")
	check(Game.player==old,"Online admission never changes the offline player")
	view.network.leave();view.queue_free();await get_tree().process_frame
	OnlineAccount.clear()
	print("SCHOOL LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
