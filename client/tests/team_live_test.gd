extends Node
var checks:=0
var failures:=0
func _ready()->void:_run.call_deferred()
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("TEAM LIVE: "+text)
func until(condition:Callable,seconds:float=30)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return condition.call()
func _run()->void:
	await Platform.when_ready()
	var config:Dictionary=JSON.parse_string(OS.get_environment("SSJX_TEAM_TEST"))
	var old:=Game.player.duplicate(true)
	OnlineAccount.clear();OnlineAccount.login(config.base,"team_ui_a","owned-team-test-password")
	if not await until(func()->bool:return OnlineAccount.is_logged_in()):check(false,"Login");get_tree().quit(1);return
	var view:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate();view.character_id=config.character;add_child(view)
	check(await until(func()->bool:return view.network.world_ready and not view.team.state.incoming.is_empty()),"Actual client receives an online teammate invitation")
	if view.team.state.incoming.is_empty():view.queue_free();get_tree().quit(1);return
	check(view.team_notice.visible,"Team invitation appears in the map's left prompt")
	view.team_confirm.pressed.emit()
	check(await until(func()->bool:return not view.team.party().is_empty() and not view.team.pending()),"Explicit acceptance joins the server team")
	view._scene_action("team")
	check(view.team_panel.visible,"Team menu opens real membership")
	check(view.team.party().members.any(func(m:Dictionary)->bool:return m.id==config.character and m.ready and m.following),"Accepted member defaults to prepared without submitting another ready command")
	check(await until(func()->bool:return view.team.active()),"Leader encounter enters shared battle on this client")
	if not view.team.active():view.queue_free();get_tree().quit(1);return
	check(await until(func()->bool:return view.team.presentation_ready() and view.team_battle.visible and view.team_battle.actors.size()>=4 and view.network.team_active),"Multiple monsters and both players render after asynchronous preparation while map movement is gated")
	var deadline:=Time.get_ticks_msec()+45000
	var acted:=false
	var guarded:=false
	while view.team.active() and Time.get_ticks_msec()<deadline:
		if view.team.presentation_ready() and view.team_battle.visible and view.team.my_turn() and not view.team.pending() and not view.team.inflight and view.team_battle.motion==null and view.team_battle.queue.is_empty():
			# Force a second round so real production playback must acknowledge
			# completion, rather than allowing a one-round victory to skip it.
			if not guarded:
				guarded=view.team.submit("guard");await get_tree().process_frame;continue
			for e in view.team.battle().enemies:
				if e.hp>0:
					acted=view.team.submit("attack",e.slot) or acted;break
		await get_tree().process_frame
	check(acted and view.team.battle().get("outcome")=="victory","Client and independent peer take turns and reach a shared victory")
	check(view.team.party().members.all(func(m:Dictionary)->bool:return m.ready),"Victory keeps the original readiness preference")
	check(await until(func()->bool:return not view.team_battle.visible,10),"Original result animation returns to the map")
	check(not view.network.team_active and view.network.world_ready,"Victory releases map without disconnecting")
	check(Game.player==old,"Online team does not overwrite local character")
	view._leave_world();view.queue_free();await get_tree().process_frame;OnlineAccount.clear()
	print("TEAM LIVE CLIENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
