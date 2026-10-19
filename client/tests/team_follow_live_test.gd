extends Node
var checks:=0
var failures:=0
var world:OnlineWorldView
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("TEAM FOLLOW LIVE: "+text)
func wait_until(test:Callable,seconds:float=30)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not test.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return test.call()
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready()
	var cfg:Dictionary=JSON.parse_string(OS.get_environment("SSJX_TEAM_FOLLOW_TEST"))
	OnlineAccount.login(cfg.base,"follow_ui_b","owned-follow-test-password")
	await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Real account login")
	OnlineAccount.list_characters();await OnlineAccount.completed
	world=load("res://scenes/ui/online_world_view.tscn").instantiate();world.character_id=cfg.character;add_child(world)
	check(await wait_until(func()->bool:return world.network.world_ready and not world.team.state.incoming.is_empty()),"Live leader invitation")
	if world.team.state.incoming.is_empty():get_tree().quit(1);return
	world.team.submit("accept",world.team.state.incoming[0].id)
	check(await wait_until(func()->bool:return world.network.team_following and world.network.team_marks.size()==2),"Accepted party publishes both native flags")
	check(await wait_until(func()->bool:return world.network.entities.has(cfg.character) and int(world.network.entities[cfg.character].cell[1])>10),"Follower walks without clicking or keyboard input")
	if world.actors.has(cfg.character):
		check(world.actors[cfg.character].flag.texture==preload("res://assets/ui/team_member.png"),"Following member uses recovered blue flag")
	var capture:=OS.get_environment("SSJX_TEAM_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture.path_join("following.png"))
	check(await wait_until(func()->bool:return world.network.map_id=="ancient_ruins" and world.network.world_ready,40),"Client automatically follows through the validated portal and rejoins the new room")
	if world.network.map_id!="ancient_ruins":print("FOLLOW DIAGNOSTIC ",JSON.stringify({"map":world.network.map_id,"travel":world.network.team_travel,"own":world.network.entities.get(cfg.character),"pending":OnlineAccount.pending_pve,"code":world.network.pve.last_code,"action":world.network.pve.last_action,"trip":world._follow_trip,"transition":world.map_transition.blocking,"following":world.network.team_following,"state":world.network._state,"status":world.chat_status.text}))
	check(await wait_until(func()->bool:return world.network.team_following and world.network.team_travel.is_empty(),5),"Destination continues following without repeating the transfer")
	check(not world.chat_status.text.contains("DISCONNECTED"),"Expected room transfer does not show a disconnection error")
	world.queue_free();await get_tree().process_frame
	print("TEAM FOLLOW LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
