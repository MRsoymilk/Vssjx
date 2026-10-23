extends Node
var checks:=0
var failures:=0
var view:OnlineWorldView
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("MAP LIVE: "+text)
func wait_for(predicate:Callable,seconds:float=20)->bool:
	var until:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<until:await get_tree().process_frame
	return predicate.call()
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready()
	var old:=Game.player.duplicate(true);var cfg:Dictionary=JSON.parse_string(OS.get_environment("SSJX_MAP_TEST"))
	OnlineAccount.login(cfg.base,"maps_ui","owned-balance-test-password");await OnlineAccount.completed
	check(OnlineAccount.is_logged_in(),"Login with owned account")
	view=load("res://scenes/ui/online_world_view.tscn").instantiate();view.character_id=cfg.character;add_child(view)
	view.network.status_changed.connect(func(text:String)->void:print("MAP LIVE STATUS: ",text))
	check(await wait_for(func()->bool:return view.network.world_ready and view.network.pve.ready and view.network.population.revision>=0),"Authenticated runtime snapshot passes unchanged asset hashes")
	if failures:get_tree().quit(1);return
	var rules:=view.network.map_rules
	check(rules.revision>0 and rules.portal("qingyun_trail").cell==[12.0,16.0],"Dynamic portal replaces static online lookup")
	check(SharedWorldMap.portal("qingyun_trail").cell==[28,16],"Offline packaged portals remain unchanged")
	check(not view.network.population.entities.has("wolf_b") and Vector2i(view.network.population.entities.qingwei.cell[0],view.network.population.entities.qingwei.cell[1])==Vector2i(11,13),"Disabled monsters disappear and relocated NPC validates")
	check(view.portal_marker!=null and view.portal_marker.position==Vector2(200,264),"Online portal marker uses published coordinates")
	check(await wait_for(func()->bool:return view.gathering_nodes.has("qingyun_trail_ore")),"Gathering nodes receive runtime database configuration")
	check(view.gathering_nodes.qingyun_trail_ore.data.material=="copper" and view.gathering_nodes.qingyun_trail_ore.position==Vector2(216,312),"Published gathering material and position displayed")
	view.network.move_to(Vector2i(12,16))
	check(await wait_for(func()->bool:return view.network.map_id=="ai_002" and view.network.world_ready and view.network.pve.ready),"Automatic portal transfer resolves published destination")
	check(Vector2i(view.network.pve.state.character.cell_x,view.network.pve.state.character.cell_y)==Vector2i(6,16),"Published target spawn accepted without terrain hash bypass")
	check(Game.player==old,"Online operational settings never mutate offline saves")
	view.queue_free();await get_tree().process_frame;OnlineAccount.clear();print("MAP MANAGEMENT LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
