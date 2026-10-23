extends Node
var failures:=0
var checks:=0
func _ready() -> void:_run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("SOCIAL LIVE: "+text)
func wait_for(condition: Callable, seconds: float=15) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return condition.call()
func _run() -> void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true)
	var credentials: Dictionary=JSON.parse_string(OS.get_environment("SSJX_SOCIAL_TEST"))
	OnlineAccount.clear()
	OnlineAccount.login(credentials.base,credentials.username,"owned-social-test-password")
	if not await wait_for(func()->bool:return OnlineAccount.is_logged_in(),40):
		check(false,"Real account login");get_tree().quit(1);return
	check(true,"Real HTTP login")
	var view: OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=credentials.character;add_child(view)
	check(await wait_for(func()->bool:return view.network.world_ready and not view.social.state.is_empty()),"Real world and authenticated social snapshot ready")
	if view.social.state.is_empty():view.queue_free();get_tree().quit(1);return
	check(view.social.state.incoming.size()==1 and view.social.state.incoming[0].id==credentials.other,"Incoming application arrives through the actual account HTTP transport")
	view._open_social("requests")
	check(view.social.submit("friend_accept",credentials.other),"Accept friend through production model")
	check(await wait_for(func()->bool:return not view.social.state.friends.is_empty() and not view.social.pending()),"Real durable friend response reaches UI")
	view.social_panel.dismiss()
	check(await wait_for(func()->bool:return view.network.entities.has(credentials.other)),"Inspectable target is a real same-map online player")
	view._select_player(credentials.other)
	check(view.target_view.visible and not view.social_panel.visible and not view.target_view.actions.visible,"Real map selection shows a card without opening a modal or submitting an interaction")
	check(await wait_for(func()->bool:return view.target.profile.get("id")==credentials.other and view.target.profile.has("vitals")),"Independent target transport fetches authoritative current vitals")
	check(view.target_view.hp_bar.value==53 and view.target_view.mp_bar.value==17,"Target bars show actual non-full health and mana, not their maxima")
	view.target_view.card.pressed.emit()
	check(view.target_view.actions.visible and not view.social_panel.visible,"Only a deliberate target-card click opens actions")
	view.target_view.buttons.profile.pressed.emit()
	check(await wait_for(func()->bool:return view.social.profile.get("id")==credentials.other),"Real public profile validates and displays")
	check(view.social_panel.preview!=null and view.social.profile.equipment.size()==10,"Target appearance and ten equipment slots are shown")
	view._scene_action("guild")
	check(view.social.submit("guild_create","","测试同盟"),"Create a guild through the production model")
	check(await wait_for(func()->bool:return view.social.state.guild is Dictionary and not view.social.pending()),"Created guild is persisted and returned by API")
	check(view.social.state.guild.role=="leader" and view.social.state.guild.members.size()==1,"Server assigns creator leader without trusting client role")
	check(view.social.submit("guild_announce","","","来自真实客户端的公告"),"Publish guild announcement")
	check(await wait_for(func()->bool:return view.social.state.guild.announcement=="来自真实客户端的公告" and not view.social.pending()),"Published announcement reaches production guild UI")
	check(Game.player==old,"Online social actions do not mutate local player")
	view._leave_world();view.queue_free();await get_tree().process_frame
	OnlineAccount.clear()
	print("SOCIAL LIVE CLIENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
