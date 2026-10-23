extends Node
var checks:=0
var failures:=0
var view:OnlineWorldView
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("GATHER LIVE: "+text)
	if not ok and is_instance_valid(view):print("GATHER DIAGNOSTICS: code=",view.network.pve.last_code," action=",view.network.pve.last_action," active=",GatheringRules.active(view.network.pve)," own=",view.network.entities.get(view.character_id,{})," owner=",view.network.world_epoch," conn=",view.network.connection_epoch," cancel=",view._gather_cancel_requested," time=",view.network.pve.server_time_ms())
func wait_for(predicate:Callable,seconds:float=20)->bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<until:await get_tree().process_frame
	return predicate.call()
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true)
	var cfg:Dictionary=JSON.parse_string(OS.get_environment("SSJX_GATHERING_TEST"))
	OnlineAccount.login(cfg.base,"gather_ui","owned-balance-test-password");await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Owned real account login")
	view=load("res://scenes/ui/online_world_view.tscn").instantiate();view.character_id=cfg.character;add_child(view)
	view.network.pve.message.connect(func(text:String)->void:print("GATHER LIVE MESSAGE: ",text))
	check(await wait_for(func()->bool:return view.network.world_ready and view.network.pve.ready and view.gathering_nodes.size()==2),"Real server resource configuration renders mining and herbalism markers")
	if failures:get_tree().quit(1);return
	for resource in view.gathering_nodes.values():
		var data:Dictionary=resource.data.duplicate(true)
		view._resident_action("gather",data.id)
		check(await wait_for(func()->bool:return view.gathering_panel.visible and view._approach.is_empty()),"Walk to resource and show explicit collection confirmation")
		check(not view.network.pve.pending() and GatheringRules.active(view.network.pve).is_empty(),"Opening resource panel cannot award or begin collection")
		view.gathering_panel.confirm.pressed.emit()
		check(await wait_for(func()->bool:return not GatheringRules.active(view.network.pve).is_empty()),"Server accepts and returns a real collection deadline")
		check(await wait_for(func()->bool:return int(view.network.pve.state.gathering.materials.get(data.material,0))>0 and not view.network.pve.pending()),"Progress auto-completes through authoritative finish command")
		check(not view.gathering_panel.visible and int(resource.data.available_at_ms)>view.network.pve.server_time_ms(),"Successful harvest closes progress and displays personal resource cooldown")
	view._scene_action("bag")
	check(view.backpack!=null,"Existing backpack remains available")
	view.backpack.open_material_bag()
	check(view.backpack.material_bag.rows.text.contains("铁矿") and view.backpack.material_bag.rows.text.contains("甘草") and int(view.network.pve.state.gathering.materials.get("iron",0))>0 and int(view.network.pve.state.gathering.materials.get("gancao",0))>0,"Actual harvested mineral and herb stacks appear in the separate material bag")
	check(Game.player==old,"Online gathering leaves offline character data untouched")
	view.queue_free();await get_tree().process_frame;OnlineAccount.clear()
	print("GATHERING LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
