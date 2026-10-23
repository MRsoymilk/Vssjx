extends "res://tests/team_test.gd"

var fixtures:Dictionary

func receive_packet(model:OnlineTeamModel,packet:Dictionary)->void:
	model.request={"action":"snapshot","operation_id":packet.get("operation_id")};model.inflight=true
	check(model.receive(packet),"Lifecycle snapshot passes the production team decoder")

func world_for(packet:Dictionary,prepare:bool=false)->OnlineWorldView:
	var world:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
	world.character_id=packet.character_id;add_child(world);world.set_process(false);world.network.set_process(false)
	world.team.prepare_battles=prepare;world.team_battle.set_process(false)
	receive_packet(world.team,packet)
	return world

func overlays(world:Node)->Array:
	return world.get_children().filter(func(n:Node)->bool:return n is TeamLootPanel and not n.is_queued_for_deletion() and n.is_visible_in_tree())

func loot_entry(world:OnlineWorldView)->Button:
	for button in world.team_panel.footer.find_children("*","Button",true,false):
		if button.text=="战利品":return button
	return null

func capture(name:String)->void:
	var path:=OS.get_environment("SSJX_TEAM_LOOT_CAPTURE")
	if path.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(path)
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path.path_join(name+".png"))==OK,"Render "+name)

func _run()->void:
	await Game.when_ready()
	var path:=OS.get_environment("SSJX_TEAM_LOOT_LIFECYCLE_FIXTURES")
	check(not path.is_empty(),"Lifecycle regression requires actual consecutive server encounters")
	if path.is_empty():get_tree().quit(1);return
	fixtures=JSON.parse_string(FileAccess.get_file_as_string(path))
	var saved:=OnlineAccount.pending_team.duplicate(true);var player:=Game.player.duplicate(true);OnlineAccount.pending_team={}
	await _settled_then_next_battle()
	await _fast_start_and_missed_battle()
	await _timeout_and_reconnect()
	await _dismiss_and_invalidate()
	check(Game.player==player,"Loot lifecycle does not change the offline character")
	OnlineAccount.pending_team=saved
	print("TEAM LOOT LIFECYCLE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func _settled_then_next_battle()->void:
	var world:=world_for(fixtures.first_active)
	receive_packet(world.team,fixtures.pending)
	for frame in 1200:
		world.team_battle._process(1.0/30.0)
		if not overlays(world).is_empty():break
	check(overlays(world).size()==1,"Normal victory playback automatically opens one loot overlay")
	if overlays(world).is_empty():world.queue_free();await get_tree().process_frame;return
	var panel:TeamLootPanel=overlays(world)[0];panel.set_process(false)
	world.team_battle.result.advance(2)
	check(not world.team_battle.visible and panel.is_visible_in_tree(),"Returning from victory keeps genuinely pending loot usable")
	receive_packet(world.team,fixtures.partial);panel._process(10)
	check(panel.is_visible_in_tree() and world.team.loot_pending(),"One teammate's roll cannot close a still-pending multi-player distribution")
	receive_packet(world.team,fixtures.resolved);panel._process(2.9)
	check(panel.is_visible_in_tree() and panel.results.text.contains("获得："),"Committed results remain readable briefly before auto-close")
	await capture("lifecycle-distributed")
	receive_packet(world.team,fixtures.resolved);panel._process(.2)
	check(panel.is_queued_for_deletion() and not panel.is_visible_in_tree(),"Repeated settled snapshots do not reset the three-second automatic close")
	# Keep the baseline runnable even when the old panel fails to close.
	if not panel.is_queued_for_deletion():panel.queue_free()
	await get_tree().process_frame
	receive_packet(world.team,fixtures.resolved)
	check(overlays(world).is_empty(),"Polling a distributed pool cannot reopen the automatic overlay")
	world.team_panel.open();var entry:=loot_entry(world)
	check(entry!=null,"The team page keeps a manual entry for the completed distribution")
	if entry!=null:entry.pressed.emit()
	check(overlays(world).size()==1,"Manual review reopens the completed result")
	if not overlays(world).is_empty():
		panel=overlays(world)[0];panel.set_process(false);panel._process(10)
		check(panel.is_visible_in_tree(),"Manually reopened completed results stay available for reading")
		receive_packet(world.team,fixtures.next_active)
		check(panel.is_queued_for_deletion() and not panel.is_visible_in_tree() and overlays(world).is_empty(),"The next authoritative battle synchronously removes the old modal blocker")
		panel.roll.pressed.emit();panel.pass_button.pressed.emit()
		check(not world.team.pending(),"Retired buttons cannot send old choices into the new battle")
		check(loot_entry(world)==null,"A new battle exposes no stale loot entry")
		check(world.team_battle.visible and not world.team_battle.action_buttons[0].disabled,"The next battle remains visible and accepts its normal combat commands")
		await capture("lifecycle-next-battle")
	world.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _fast_start_and_missed_battle()->void:
	var world:=world_for(fixtures.pending,true)
	var panel:TeamLootPanel=overlays(world)[0];panel.set_process(false)
	receive_packet(world.team,fixtures.resolved)
	# A teammate starts immediately, before this client's result-read timer ends.
	receive_packet(world.team,fixtures.next_active)
	check(panel.is_queued_for_deletion() and not panel.visible,"A teammate's immediate challenge cancels the prior result-read interval")
	check(world.encounter.visible and overlays(world).is_empty(),"The old modal is removed before asynchronous encounter preparation completes")
	for frame in 300:
		if world.team.presentation_ready():break
		await get_tree().process_frame
	check(world.team_battle.visible and not world.team_battle.action_buttons[0].disabled and overlays(world).is_empty(),"Real asynchronous preparation reaches an unobstructed playable battle")
	check(TeamLootPanel.open_for(world.team_panel,world.team)==null,"Loot cannot be manually opened during an active encounter")
	world.queue_free();await get_tree().process_frame
	world=world_for(fixtures.pending);panel=overlays(world)[0];panel.set_process(false)
	# A slow/reconnecting client may skip the active snapshot of the next battle.
	receive_packet(world.team,fixtures.next_pending)
	check(panel.is_queued_for_deletion() and overlays(world).size()==1 and overlays(world)[0]!=panel,"A later pending battle replaces the old bound panel instead of silently retargeting it")
	panel.pass_button.pressed.emit()
	check(not world.team.pending(),"An old panel callback cannot choose a new battle's item")
	var replacement:TeamLootPanel=overlays(world)[0]
	var item:String=world.team.loot_pool().drops[0].item.id
	replacement.pass_button.pressed.emit()
	check(world.team.request.get("action")=="loot_pass" and world.team.request.get("battle_id")==world.team.battle().id and world.team.request.get("target")==item,"The replacement panel still submits the current battle and item identities")
	world.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _timeout_and_reconnect()->void:
	var world:=world_for(fixtures.timeout_pending)
	check(overlays(world).size()==1,"Reconnecting to an unfinished pool restores one decision panel")
	var panel:TeamLootPanel=overlays(world)[0];panel.set_process(false)
	world.team.server_time=int(world.team.loot_pool().deadline_ms)+1;world.team.received_at=Time.get_ticks_msec()
	panel._process(60);panel.refresh()
	check(panel.is_visible_in_tree() and panel.clock.text.contains("正在确认") and panel.roll.disabled and panel.pass_button.disabled,"Local timeout waits for authoritative settlement and polling cannot re-enable expired choices")
	panel.pass_button.pressed.emit();check(not world.team.pending(),"Expired choices do not enter the durable outbox")
	receive_packet(world.team,fixtures.timeout_resolved);panel._process(0)
	check(panel.is_visible_in_tree() and panel.clock.text.contains("已分配"),"Timeout settlement displays the server's actual winner")
	receive_packet(world.team,fixtures.after_timeout)
	check(panel.is_queued_for_deletion() and overlays(world).is_empty(),"The first post-timeout encounter has no leftover distribution window")
	world.queue_free();await get_tree().process_frame
	world=world_for(fixtures.timeout_resolved)
	check(overlays(world).is_empty() and loot_entry(world)!=null,"Reconnecting after completed distribution keeps history without auto-opening it")
	world.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}

func _dismiss_and_invalidate()->void:
	var world:=world_for(fixtures.pending);var panel:TeamLootPanel=overlays(world)[0]
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	panel._unhandled_key_input(escape)
	check(panel.is_queued_for_deletion() and not panel.visible,"Manual dismissal removes the input blocker immediately")
	await get_tree().process_frame
	receive_packet(world.team,fixtures.pending)
	check(overlays(world).is_empty(),"Unchanged polling respects explicit dismissal of pending loot")
	world.team_panel.open_loot();check(overlays(world).size()==1,"Pending loot remains manually recoverable after dismissal")
	panel=overlays(world)[0]
	var lost:Dictionary=fixtures.pending.duplicate(true);lost.state.team=null
	receive_packet(world.team,lost)
	check(panel.is_queued_for_deletion() and not panel.visible,"Leaving or losing the team disposes its independent overlay")
	world.queue_free();await get_tree().process_frame
	world=world_for(fixtures.pending);panel=overlays(world)[0]
	var empty:Dictionary=fixtures.pending.duplicate(true);empty.state.team.battle.loot_pool.drops=[]
	receive_packet(world.team,empty)
	check(panel.is_queued_for_deletion() and not panel.visible and loot_entry(world)==null,"An empty pool clears the panel and its team-page entry")
	world.queue_free();await get_tree().process_frame;OnlineAccount.pending_team={}
