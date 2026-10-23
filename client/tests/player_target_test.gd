extends "res://tests/social_test.gd"

func packet(model:OnlineTarget,p:Variant)->Dictionary:
	return {"version":"social-v1","character_id":SELF,"operation_id":null,"ok":true,"code":"OK","replayed":false,"state":state(),"profile":p}

func entity(id:String,cell:Array)->Dictionary:
	var value:=person(id)
	value.merge({"cell":cell,"next_cell":null,"segment_progress":0,"world_epoch":"1"})
	return value

func click_player(world:OnlineWorldView,id:String,touch:bool=false)->void:
	var point:Vector2=world.actors[id].root.position-Vector2(0,30)-world.camera.get_screen_center_position()+Vector2(world.viewport.size)/2
	if touch:
		var event:=InputEventScreenTouch.new();event.position=point;event.pressed=true;world._map_input(event)
	else:
		var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;world._map_input(event)

func gui_click(control:Control)->void:
	var event:=InputEventMouseButton.new();event.position=get_viewport().get_final_transform()*control.get_global_rect().get_center();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	Input.parse_input_event(event)
	var release:=event.duplicate();release.pressed=false;Input.parse_input_event(release)
	for i in 3:await get_tree().process_frame

func _run()->void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true);var outbox:=OnlineAccount.pending_social.duplicate(true);var team_outbox:=OnlineAccount.pending_team.duplicate(true)
	var model:=OnlineTarget.new();model.character_id=SELF
	model.send_requested.connect(func(p:Dictionary)->void:sent.append(p))
	model.select(OTHER);model.tick(false)
	check(sent.is_empty(),"Selection alone cannot send any write or bypass unavailable transport")
	model.tick(true)
	check(sent.size()==1 and sent[-1].action=="profile" and not sent[-1].has("operation_id"),"Target inspection is exclusively a read without operation UUID")
	var p:=profile();p.vitals={"hp":37,"mp":11}
	model.select(THIRD)
	check(not model.receive(packet(model,p)) and model.profile.is_empty(),"Late previous-target response cannot replace the newly selected player")
	model.tick(true);p.id=THIRD;p.display_name="峨嵋客"
	check(model.receive(packet(model,p)) and model.profile.id==THIRD,"Rapid selection coalesces to the final requested target")
	var count:=sent.size();model.tick(true)
	check(sent.size()==count,"Successful target snapshots are throttled for three seconds")
	OnlineAccount.pending_social={"request":{"action":"friend_request","operation_id":SELF}}
	var pending:=OnlineAccount.pending_social.duplicate(true)
	model.next_poll=0;model.tick(true)
	var bad:=packet(model,p);bad.profile.vitals.hp=-1
	check(not model.receive(bad) and OnlineAccount.pending_social==pending,"Invalid target vitals cannot acknowledge or erase a durable social mutation")
	model.next_poll=0;model.tick(true);model.clear()
	check(not model.receive(packet(model,p)) and model.selected.is_empty() and model.profile.is_empty(),"Clearing the target rejects late results without resurrecting its card")
	var rules:=MODEL.new();rules.character_id=SELF;rules.request={"action":"profile","target":OTHER}
	p=profile();p.vitals={"hp":int(p.combat.hp)+1,"mp":0}
	check(not rules.valid(response(rules,state(),p)),"Current vital larger than its authoritative maximum is rejected")
	p.vitals={"hp":0,"mp":0}
	check(rules.valid(response(rules,state(),p)),"Zero health and mana are valid, not treated as missing or full")
	var world:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate();world.character_id=SELF;add_child(world)
	world.set_process(false);world.network.set_process(false);world.network.world_ready=true
	world.network.entities={SELF:entity(SELF,[10,16]),OTHER:entity(OTHER,[12,16]),THIRD:entity(THIRD,[14,16])}
	world._snapshot(world.network.entities);world.camera.force_update_scroll()
	world.target.send_requested.disconnect(OnlineAccount.target_profile_request)
	world.target.send_requested.connect(func(value:Dictionary)->void:sent.append(value))
	var input_before:=world.network._input_seq
	click_player(world,OTHER)
	check(world.target.selected==OTHER and world.target_view.visible and not world.social_panel.visible and not world.target_view.actions.visible,"Actual map click selects a small upper-right card without modal/action menus")
	check(world.network._input_seq==input_before and not world.social.pending() and not world.team.pending(),"Accidentally selecting a character neither stops the route nor submits gameplay/social commands")
	world.target.tick(true);p=profile();p.vitals={"hp":37,"mp":11};world.target.receive(packet(world.target,p))
	check(world.target_view.hp_bar.value==37 and world.target_view.mp_bar.value==11 and world.target_view.hp_bar.max_value==p.combat.hp,"Card bars use current server vitals and separate maxima")
	check(world.target_view.portrait.texture.resource_path.ends_with("create_portrait_2.png"),"Target portrait uses the selected player's job and gender")
	world._scene_action("menu");world._refresh_target()
	check(world.menu.visible and not world.target_view.visible and not world.target_view.actions.visible,"Main menu hides the target's hit regions rather than overlapping modals")
	world.menu.dismiss();world._refresh_target()
	check(world.target_view.visible and world.target.selected==OTHER,"Closing the main menu restores the same selected target without another map click")
	await capture("target-selected")
	await gui_click(world.target_view.card)
	check(world.target_view.actions.visible and not world.social_panel.visible,"Only clicking the HUD card opens the five explicit interaction entries")
	check(world.target_view.buttons.size()==5 and world.target_view.actions.position.x>=180,"Action menu remains beside the upper-right target, not over the selected world actor")
	await capture("target-actions")
	input_before=world.network._input_seq;click_player(world,THIRD,true)
	check(not world.target_view.actions.visible and world.target.selected==OTHER and world.network._input_seq==input_before,"Outside touch closes the menu and is consumed rather than changing target or moving")
	click_player(world,THIRD,true)
	check(world.target.selected==THIRD and world.target.profile.is_empty() and world.target_view.hp_text.text.contains("—"),"Touch selection switches target immediately and never reuses previous player's vitals")
	await gui_click(world.target_view.card);await gui_click(world.target_view.buttons.profile)
	check(world.social_panel.visible and world.social.request.get("target")==THIRD,"View-info entry opens only the explicitly selected character profile")
	world.social_panel.dismiss();world._refresh_target()
	world.target_view.buttons.clear.pressed.emit()
	check(world.target.selected.is_empty() and not world.target_view.visible,"Cancel selection removes the portrait and all hit regions")
	world._select_player(OTHER);world.network.entities.erase(OTHER);world._snapshot(world.network.entities)
	check(world.target.selected.is_empty() and not world.target_view.visible,"A player leaving the map clears selection automatically")
	world._select_player(THIRD);world.network.world_ready=false;world._status_changed("连接中断")
	check(world.target.selected.is_empty(),"Disconnect cannot leave a stale clickable target")
	world.network.world_ready=true;world._select_player(THIRD);world.target.tick(true)
	var third:=profile();third.id=THIRD;third.display_name="峨嵋客" # Legacy server has maxima but no vitals.
	world.target.receive(packet(world.target,third))
	check(world.target_view.hp_text.text.contains("—") and world.target_view.hp_bar.value==0,"Older server without vitals shows unknown, never invented full-health bars")
	world.social.request={};world.social.inflight=false;world._refresh_target()
	world.target_view.buttons.friend.pressed.emit()
	check(world.social.request.get("action")=="friend_request" and world.social.request.get("target")==THIRD,"Explicit friend entry submits the selected target through the existing durable social outbox")
	world.target_view.buttons.team.pressed.emit()
	check(world.team.request.get("action")=="invite" and world.team.request.get("target")==THIRD,"Explicit team entry invites only the selected player through the original team model")
	world._begin_map_transition()
	check(world.target.selected.is_empty(),"Map-transfer loading clears selection before a late profile can arrive")
	world.queue_free();await get_tree().process_frame
	check(Game.player==old,"Target inspection never touches offline character state")
	OnlineAccount.pending_social=outbox
	OnlineAccount.pending_team=team_outbox
	print("PLAYER TARGET: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
