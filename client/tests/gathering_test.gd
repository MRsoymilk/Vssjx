extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("GATHERING: "+text)
func _ready()->void:run.call_deferred()
func run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;var combat:Variant=Game.local_combat
	Game.save_path="user://gathering_%d.json"%Time.get_ticks_usec();Game.local_combat=null;Game.new_player("采集测试",0,3,0)
	check(GatheringRules.catalog.nodes.size()==418,"Bundled resource points match the seeded database catalog")
	for n in GatheringRules.catalog.nodes:
		var map:=SharedWorldMap.load_data(n.map_id)
		check(not map.blocked[int(n.cell[1])*32+int(n.cell[0])],"Resource remains on original walkable ground: "+n.id)
	var node:Dictionary=GatheringRules.nodes_for("qingyun_trail")[0];var cell:=Vector2i(node.cell[0],node.cell[1]);Game.player.cell=[cell.x,cell.y]
	check(Game.begin_gathering(node.id,cell,"qingyun_trail").is_empty(),"Local confirmation begins a nonpersistent collection timer")
	var early:=await Game.finish_gathering(cell,"qingyun_trail")
	check(not early.ok and early.code=="GATHER_NOT_READY" and not Game.player.has("gathering"),"Local collection cannot grant before duration")
	Game.local_gather.started=Time.get_ticks_msec()-int(node.duration_ms)-1
	var result:=await Game.finish_gathering(cell,"qingyun_trail")
	check(result.ok and int(Game.player.gathering.materials[node.material])>=1 and int(Game.player.gathering.materials[node.material])<=3,"Local completion saves a bounded material stack")
	check(Game.local_gather.is_empty() and Game.valid_save(Game.player),"Completed timer disappears and new optional save data validates")
	check(Game.begin_gathering(node.id,cell,"qingyun_trail")=="GATHER_COOLDOWN","Local cooldown survives reopening the resource panel")
	var saved:Dictionary=Game.player.gathering.duplicate(true);var loaded:=await Game.load_game()
	check(loaded.ok and int(Game.player.gathering.materials[node.material])==int(saved.materials[node.material]) and int(Game.player.gathering.respawns[node.id])==int(saved.respawns[node.id]),"Materials and refresh deadlines survive a real local save/load")
	var bad:=Game.player.duplicate(true);bad.gathering.materials[node.material]=1000
	check(not Game.valid_save(bad),"Corrupt out-of-range material stacks are rejected")
	var legacy:=Game.player.duplicate(true);legacy.erase("gathering")
	check(Game.valid_save(legacy),"Existing saves without gathering remain valid")
	var bag:=GatheringMaterialBag.new();add_child(bag)
	check(bag.rows.text.contains(GatheringRules.MATERIALS[node.material]),"Local material bag shows persisted gathering materials")
	var panel:=GatheringPanel.new();panel.local_mode=true;add_child(panel);panel.present(node)
	check(panel.visible and panel.frame.size.x<=320,"Mining/herbalism panel fits existing portrait viewport")
	var output:=OS.get_environment("SSJX_GATHERING_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(output);await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(output.path_join("materials-and-gathering.png"))==OK,"Actual material and collection UI render capture")
	panel.queue_free();bag.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(Game.save_path);Game.player=old;Game.save_path=path;Game.local_combat=combat;Game.local_gather={}
	print("GATHERING CLIENT: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
