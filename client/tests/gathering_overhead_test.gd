extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("GATHER OVERHEAD: "+text)
func wait_for(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+12000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return predicate.call()
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var old_combat:Variant=Game.local_combat
	Game.local_combat=null
	Game.save_path="user://gather_overhead_%d.json"%Time.get_ticks_usec()
	var main=load("res://scenes/main.tscn").instantiate();add_child(main)
	Game.new_player("采矿进度",0,3,0)
	var ore:Dictionary=GatheringRules.nodes_for("qingyun_trail")[0]
	Game.player.cell=ore.cell.duplicate();main._enter_world()
	main._world_interaction("gather",ore)
	check(not Game.local_gather.is_empty() and main.modal is GatheringPanel,"Arriving at ore begins immediately without confirmation")
	var bar:GatheringPanel=main.modal
	await get_tree().process_frame;bar._process(0)
	check(bar.get_child_count()==1 and bar.progress.size==Vector2(48,6) and not bar.progress.show_percentage,"Gathering shows only a 48 by 6 bar without text")
	check(bar.position.is_equal_approx(main.world.hero.get_global_transform_with_canvas().origin+main.world_view.position+Vector2(-24,-86)),"Bar is centered above the real player, clear of their name")
	Game.local_gather.started=Time.get_ticks_msec()-int(ore.duration_ms)/2;bar._process(0)
	check(bar.progress.value>=0.49 and bar.progress.value<=0.6,"Overhead fill tracks real elapsed collection time")
	var output:=OS.get_environment("SSJX_GATHERING_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(output);await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output.path_join("gathering-overhead.png"))==OK,"Actual world capture shows the compact overhead indicator")
	var event:=InputEventKey.new();event.physical_keycode=KEY_RIGHT;event.pressed=true
	Input.parse_input_event(event);Input.flush_buffered_events();bar._process(0)
	event=InputEventKey.new();event.physical_keycode=KEY_RIGHT;event.pressed=false;Input.parse_input_event(event);Input.flush_buffered_events()
	check(Game.local_gather.is_empty() and main.modal==null and main.world.enabled,"Arrow movement cancels collection and restores world control")
	main._open_local_gathering(ore)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=Vector2(160,216)
	main.world_view.gui_input.emit(click)
	check(Game.local_gather.is_empty() and main.modal==null,"Map click cancels collection without an extra dialog")
	main.world.stop_moving();main._open_local_gathering(ore)
	Game.local_gather.started=Time.get_ticks_msec()-int(ore.duration_ms)-1
	check(await wait_for(func()->bool:return main.modal==null and not Game.storage_busy),"Elapsed collection saves and closes automatically")
	check(int(Game.player.gathering.materials.get(ore.material,0))>0 and main.world.enabled,"Automatic completion retains material rewards and restores movement")
	main._open_local_gathering(ore)
	check(main.modal==null and Game.local_gather.is_empty() and main.quest_label.text.contains("刷新"),"Cooldown uses existing status text, never a large explanation panel")
	var battle:ShushanBattle=ShushanBattle.new(ShushanWorld.ENEMIES[0]);battle.finished=true
	Game.local_combat=weakref(battle)
	await harvest(main,GatheringRules.nodes_for("qingyun_trail")[1])
	var cooldowns:Dictionary=Game.player.gathering.respawns.duplicate(true)
	battle=null
	for destination in ["ai_001","ai_002","qingyun_trail"]:
		main.world.travel(destination)
		check(await wait_for(func()->bool:return main.mode=="world" and main.world.map_id==destination and main.world.enabled and not main.map_transition.blocking),"Local gathering survives a real map transition to "+destination)
		if main.world.map_id!=destination:break
		check(Game.local_combat!=null and Game.local_combat.get_ref()==null,"An expired battle reference remains harmless after the world is rebuilt")
		check(main.world.gathering_nodes.size()==2 and Game.local_gather.is_empty(),"New local map creates both resource nodes and no stale collection timer")
		if destination=="qingyun_trail":
			for id in cooldowns:check(Game.player.gathering.respawns[id]==cooldowns[id],"Returning retains original resource cooldown: "+id)
		else:
			for node in GatheringRules.nodes_for(destination):
				check(int(node.available_at_ms)==0,"Other maps have independent resource cooldowns: "+node.id)
				if not await harvest(main,node):break
	main.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path);Game.player=old;Game.save_path=path;Game.local_gather={};Game.local_combat=old_combat
	print("GATHER OVERHEAD: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)

func harvest(main:Control,node:Dictionary)->bool:
	var quantity:=int(Game.player.gathering.materials.get(node.material,0))
	var resource:GatheringNode=main.world.gathering_nodes[node.id]
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=resource.position+Vector2(0,-12)-main.world.camera.get_screen_center_position()+main.world.get_viewport_rect().size/2.0
	main.world_view.gui_input.emit(click)
	var started:=await wait_for(func()->bool:return main.modal is GatheringPanel and not Game.local_gather.is_empty())
	check(started,"Click and approach start local collection after battle: "+node.id)
	if not started:return false
	Game.local_gather.started=Time.get_ticks_msec()-int(node.duration_ms)-1
	check(await wait_for(func()->bool:return main.modal==null and not Game.storage_busy),"Post-battle collection closes its progress and persists")
	check(int(Game.player.gathering.materials.get(node.material,0))>quantity and main.world.enabled,"Post-battle resource reward is credited: "+node.id)
	return true
