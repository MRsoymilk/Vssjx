extends Node
var checks := 0
var failures := 0
var view: OnlineWorldView
var notices: Array[String] = []
func _ready() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1;push_error("DUEL UI FAIL: " + text)
func wait_until(predicate: Callable, seconds: float = 15.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < until: await get_tree().process_frame
	return predicate.call()
func capture(name_value: String) -> void:
	var path := OS.get_environment("SSJX_DUEL_CAPTURE")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(path.path_join(name_value + ".png")) == OK,"Capture " + name_value)

func _run() -> void:
	var old := Game.player.duplicate(true)
	var role := OS.get_environment("SSJX_DUEL_ROLE")
	OnlineAccount.login(OS.get_environment("SSJX_DUEL_BASE"),"duel_ui_"+role,OS.get_environment("SSJX_DUEL_PASSWORD"))
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Owned PK account logs in")
	OnlineAccount.list_characters();await OnlineAccount.completed
	if OnlineAccount.characters.is_empty(): get_tree().quit(1);return
	view = load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id = OnlineAccount.characters[0].id
	add_child(view)
	view.network.status_changed.connect(func(text: String)->void:notices.append(text))
	check(await wait_until(func()->bool:return view.network.world_ready and view.network.pve.ready and view.network.duel.connected and view.network.entities.size()>=2,60),"PK capability and both map actors synchronize")
	if failures: print("DUEL START DIAGNOSTICS ",role," base=",view.network.server," map=",view.network.map_id," status=",view._system_text," world=",view.network.world_ready," pve=",view.network.pve.ready," duel-enabled=",view.network.duel.enabled," duel-connected=",view.network.duel.connected," peers=",view.network.entities.values().map(func(e:Dictionary)->String:return e.display_name))
	if role == "a":
		var peer := ""
		for id in view.network.entities:
			if view.network.entities[id].display_name == "duel_ui_b": peer = id
		check(not peer.is_empty(),"Same-map opponent is selectable")
		if peer.is_empty():get_tree().quit(1);return
		view._select_player(peer)
		check(view.duel_invitation.visible and view.duel_invitation.confirm.text=="邀请决斗","Player selection exposes the duel invitation action")
		view.duel_invitation.confirm.pressed.emit()
		check(await wait_until(func()->bool:return view.network.duel.state.get("outgoing") is Dictionary or view.network.duel.active()),"Invite is sent through the real socket")
	else:
		check(await wait_until(func()->bool:return view.network.duel.state.get("incoming") is Dictionary),"Recipient receives the invitation")
		check(view.duel_invitation.visible and view.duel_invitation.caption.text.contains("duel_ui_a") and view.duel_invitation.confirm.text=="确认" and view.duel_invitation.reject.text=="拒绝","Left notice identifies the inviter with separate confirm and reject buttons")
		check(view.duel_invitation.panel.position.x<10 and view.duel_invitation.panel.size.x<240,"Invitation occupies the left side rather than the center")
		check(not view.duel_battle.visible,"Recipient is not placed into battle before accepting")
		await capture("incoming")
		view.duel_invitation.confirm.pressed.emit()
	check(await wait_until(func()->bool:return view.network.duel.active() and view.duel_battle.visible),"Both confirmations start the original battle interface")
	if not view.network.duel.active():print(view._system_text);get_tree().quit(1);return
	check(view.duel_battle.hero != null and view.duel_battle.enemy != null and not view.duel_invitation.visible,"Two actual player characters replace monster combat")
	check(view.duel_battle.buttons[3].disabled,"Duel cannot consume PvE inventory")
	await capture("battle-"+role)
	var deadline := Time.get_ticks_msec()+65000
	while view.network.duel.active() and Time.get_ticks_msec()<deadline:
		if view.network.duel.my_turn() and not view.network.duel.pending() and view.duel_battle.animation_time<=0:
			view.duel_battle.choose("attack")
		await get_tree().process_frame
	check(not view.network.duel.active() and view.network.duel.state.battle.status=="finished","Real UI actions complete the two-player fight")
	check(await wait_until(func()->bool:return not view.duel_battle.visible,15),"Original result animation returns to map")
	view.network.move_to(Vector2i(11,16))
	check(await wait_until(func()->bool:return view.network.entities.has(view.character_id) and view.network.entities[view.character_id].cell==[11,16] and view.network.entities[view.character_id].next_cell==null),"Movement resumes after PK")
	check(not notices.any(func(s:String)->bool:return s.begins_with("连接中断")),"PK does not trigger a disconnect")
	check(Game.player==old,"Online PK never installs or modifies a local character")
	view.network.leave();view.queue_free();await get_tree().process_frame
	print("DUEL UI %s: %d checks, %d failures"%[role,checks,failures])
	get_tree().quit(1 if failures else 0)
