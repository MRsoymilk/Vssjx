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
	if not await harvest_map():get_tree().quit(1);return
	view._scene_action("bag")
	check(view.backpack!=null,"Existing backpack remains available")
	view.backpack.open_material_bag()
	check(view.backpack.material_bag.rows.text.contains("铁矿") and view.backpack.material_bag.rows.text.contains("甘草") and int(view.network.pve.state.gathering.materials.get("iron",0))>0 and int(view.network.pve.state.gathering.materials.get("gancao",0))>0,"Actual harvested mineral and herb stacks appear in the separate material bag")
	var bag:GatheringMaterialBag=view.backpack.material_bag
	var model:=view.network.pve
	check(not model.submit("gather_craft","unknown") and not model.submit("gather_craft","smelt_iron",[],11),"Online client rejects unknown and oversized recipes before sending")
	var hash_value:String=model.state.gathering.recipes_sha256;model.state.gathering.erase("recipes_sha256")
	check(not model.submit("gather_craft","smelt_iron"),"Older servers without matching recipes cannot receive processing commands")
	model.state.gathering.recipes_sha256=hash_value
	for i in GatheringRules.recipes.recipes.size():
		var entry:Dictionary=GatheringRules.recipes.recipes[i];var before:Dictionary=model.state.duplicate(true)
		bag.recipe_picker.select(i);bag.batches.value=2;bag.refresh();bag.craft.pressed.emit()
		check(await wait_for(func()->bool:return not model.pending() and int(model.state.character.state_revision)>int(before.character.state_revision)),"Actual material bag settles online recipe "+entry.id)
		for material in entry.materials:check(int(model.state.gathering.materials[material])==int(before.gathering.materials[material])-2*int(entry.materials[material]),"Online UI debits exact ingredient: "+material)
		check(int(model.state.loot.state.scrap)==int(before.loot.state.scrap)+2 if entry.output=="scrap" else int(model.state.potions)==int(before.potions)+2,"Online UI output enters existing gear or potion resource")
	view._close_inventory()
	var original_nodes:Array=model.state.gathering.nodes.duplicate(true)
	for destination in ["ai_001","ai_002","qingyun_trail"]:
		var gates:Array=view.network.map_rules.exits(view.network.map_id).filter(func(gate:Dictionary)->bool:return gate.target_map==destination)
		check(not gates.is_empty(),"Gathering round trip has a real map exit to "+destination)
		if gates.is_empty():break
		view.network.move_to(Vector2i(gates[0].cell[0],gates[0].cell[1]))
		check(await wait_for(func()->bool:return view.network.map_id==destination and view.network.world_ready and model.ready and not model.pending() and not view.map_transition.blocking,30),"Resource collection can transfer and synchronize "+destination)
		check(view.gathering_nodes.size()==2 and model.state.gathering.nodes.all(func(n:Dictionary)->bool:return n.map_id==destination),"New map rebuilds its own resource markers: "+destination)
		if failures:break
		if destination=="qingyun_trail":
			for node in original_nodes:check(int(view.gathering_nodes[node.id].data.available_at_ms)==int(node.available_at_ms),"Returning preserves each original node's independent cooldown: "+node.id)
		else:
			check(model.state.gathering.nodes.all(func(n:Dictionary)->bool:return int(n.available_at_ms)==0),"Harvested ore and herbs never cool down another map's nodes")
			if not await harvest_map():break
	check(Game.player==old,"Online gathering leaves offline character data untouched")
	view.queue_free();await get_tree().process_frame;OnlineAccount.clear()
	print("GATHERING LIVE: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func harvest_map()->bool:
	for resource in view.gathering_nodes.values():
		var data:Dictionary=resource.data.duplicate(true)
		var initial_quantity:=int(view.network.pve.state.gathering.materials.get(data.material,0))
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		click.position=resource.position+Vector2(0,-12)-view.camera.get_screen_center_position()+Vector2(view.viewport.size)/2.0
		view._map_input(click)
		check(view._approach.get("action")=="gather" and view._approach.get("target")==data.id,"Clicking resource artwork selects gathering: "+data.id)
		if failures:return false
		check(await wait_for(func()->bool:return view.gathering_panel.visible and not GatheringRules.active(view.network.pve).is_empty()),"Walk to resource and automatically begin authoritative collection: "+data.id)
		if failures:return false
		check(view._approach.is_empty() and int(view.network.pve.state.gathering.materials.get(data.material,0))==initial_quantity,"Automatic start cannot grant materials before the server deadline")
		view.gathering_panel._process(0)
		check(view.gathering_panel.get_child_count()==1 and view.gathering_panel.progress.size==Vector2(48,6) and view.gathering_panel.position.is_equal_approx(view._hero_screen_point()+Vector2(-24,-86)),"Only a small progress bar follows the actual player head")
		check(await wait_for(func()->bool:return int(view.network.pve.state.gathering.materials.get(data.material,0))>initial_quantity and not view.network.pve.pending()),"Progress auto-completes through authoritative finish command: "+data.id)
		check(not view.gathering_panel.visible and int(resource.data.available_at_ms)>view.network.pve.server_time_ms(),"Successful harvest closes progress and displays personal resource cooldown")
		if failures:return false
	return true
