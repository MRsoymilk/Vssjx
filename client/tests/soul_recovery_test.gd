extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("SOUL: "+text)
func _ready()->void:_run.call_deferred()
func capture(name:String)->void:
	var output:=OS.get_environment("SSJX_SOUL_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	for frame in 4:await get_tree().process_frame
	RenderingServer.force_draw()
	var image:=get_viewport().get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"Captured actual soul UI: "+name)
	var colorful:=0
	for y in range(0,image.get_height(),8):
		for x in range(0,image.get_width(),8):
			var pixel:=image.get_pixel(x,y)
			if absf(pixel.r-pixel.g)>0.02 or absf(pixel.g-pixel.b)>0.02:colorful+=1
	check(colorful==0 if not name.ends_with("revived") else colorful>100,"Full viewport grayscale follows only the soul state")
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	var old_hash:=FileAccess.get_sha256(old_path) if FileAccess.file_exists(old_path) else ""
	var pending:=OnlineAccount.pending_pve.duplicate(true)
	Game.save_path="user://soul_test_%d.json"%Time.get_ticks_usec()
	var markers: SoulMarkers=load("res://scenes/actors/soul_markers.tscn").instantiate()
	check(not markers.get_node("ResurrectionPoint").visible,"Resurrection point is hidden before the first state snapshot")
	add_child(markers)
	check(not markers.spawn_marker.visible and not markers.grave.visible,"Living state hides resurrection point and corpse by default")
	markers.display("qingyun_trail",SoulRules.create("qingyun_trail",Vector2i(22,9)))
	check(markers.spawn_marker.visible and markers.grave.visible,"Death reveals the shared local/online resurrection markers")
	markers.display("ancient_ruins",markers.corpse)
	check(not markers.spawn_marker.visible and not markers.grave.visible,"A different map cannot show stale death markers")
	markers.display("qingyun_trail")
	check(not markers.spawn_marker.visible and not markers.grave.visible,"Clearing the authoritative death state hides both markers again")
	markers.queue_free();await get_tree().process_frame
	AIWorld.prepare()
	var maps:Array=SharedWorldMap.MAPS.keys()+AIWorld.maps.keys()
	for map_id in maps:
		var spawn:=SoulRules.resurrection_point(map_id)
		var map_data:=SharedWorldMap.load_data(map_id)
		check(not map_data.blocked[spawn.y*32+spawn.x],"Every map has one walkable fixed resurrection point: "+map_id)
		check(SoulRules.valid_corpse(SoulRules.create(map_id,spawn)),"Corpse schema covers each map")
	Game.new_player("寻魂测试",1,3,0)
	Game.player.quest=1;Game.player.cell=[22,9]
	var battle:=ShushanBattle.new(ShushanWorld.ENEMIES[0])
	battle.finished=true;battle.phase="finished";battle.hp=0;battle.mp=0
	var resources:=[Game.player.gold,Game.player.xp,Game.player.potions,ShopRules.local_state(Game.player)]
	await battle.commit()
	check(Game.is_soul() and Game.player.hp==0,"Actual defeat settlement enters soul state instead of free healing")
	var corpse:Dictionary=Game.player.corpse.duplicate(true)
	check(corpse.cell==[22,9] and corpse.map_id=="qingyun_trail","Grave records the death position, not the spawn")
	check(Game.player.cell==[10,16],"Soul appears at this map's fixed resurrection point")
	check(resources==[Game.player.gold,Game.player.xp,Game.player.potions,ShopRules.local_state(Game.player)],"Death does not remove gold, XP or items")
	check(Game.valid_save(Game.player),"Current soul snapshot is a valid save")
	var loaded:=await Game.load_game()
	check(loaded.ok,"Soul save loads successfully: "+loaded.code)
	check(Game.player.corpse.id==corpse.id and Game.player.corpse.map_id==corpse.map_id and Vector2i(Game.player.corpse.cell[0],Game.player.corpse.cell[1])==Vector2i(corpse.cell[0],corpse.cell[1]),"Grave identity and death position survive a real save/load")
	Game.restore();check(Game.is_soul() and Game.player.hp==0,"Ordinary restore cannot bypass corpse recovery")
	check((await Game.shop_command("use","potion")).code=="SOUL_STATE","Potions cannot bypass recovery")
	check((await Game.allocate_attributes([1,0,0,0,0])).code=="SOUL_STATE","Stat allocation cannot resurrect")
	check(not (await Game.recover_corpse(corpse.id,Vector2i(10,16))).ok,"Remote corpse recovery rejected")
	check(not (await Game.recover_corpse("wrong",Vector2i(10,16))).ok,"Wrong corpse identity rejected")
	var forged:=Game.player.duplicate(true);forged.hp=10
	check(not Game.valid_save(forged),"Positive health with a ghost corpse is rejected")
	forged=Game.player.duplicate(true);forged.corpse.cell=[-1,9]
	check(not Game.valid_save(forged),"Invalid corpse coordinates are rejected")
	var app=load("res://scenes/main.tscn").instantiate();add_child(app);app._enter_world()
	check(app.world.soul_markers.grave.visible and app.world.hero.modulate.a<1,"Map has a native gravestone and translucent soul actor")
	check(app.world.soul_markers.spawn_marker.visible and app.world.soul_markers.spawn_marker.position==Vector2(168,264),"Death reveals the resurrection marker at the shared spawn definition")
	await capture("soul-spawn")
	var target:Dictionary=app.world.soul_markers.target()
	var near:Vector2i=target.cell+Vector2i.DOWN
	var route:Array[Vector2i]=app.world.astar.get_id_path(app.world.cell,near)
	check(not route.is_empty(),"Soul can reach its grave by normal map pathfinding")
	route.pop_front();app.world.path=route;app.world._process(20.0)
	check(SoulRules.nearby(corpse,app.world.map_id,app.world.cell),"Soul walks to the corpse without teleporting through terrain")
	await capture("corpse-nearby")
	var good_path:=Game.save_path
	Game.save_path="invalid://soul-save-denied"
	var failure:=await Game.recover_corpse(corpse.id,app.world.cell)
	Game.save_path=good_path
	check(not failure.ok and Game.is_soul() and Game.player.hp==0,"Failed durable save rolls recovery back to soul state")
	await app._world_interaction("corpse",corpse)
	check(not Game.is_soul() and Game.player.hp==Game.stats().hp and Game.player.mp==Game.stats().mp,"Nearby corpse interaction restores full health and mana")
	check(not app.world.soul_markers.spawn_marker.visible and not app.world.soul_markers.grave.visible and not app.soul_overlay.visible and app.world.hero.modulate==Color.WHITE,"Revival clears resurrection marker, grave, gray UI and spirit transparency")
	await capture("revived")
	check((await Game.load_game()).ok and not Game.is_soul(),"Revived state survives disk reload")
	check(not (await Game.recover_corpse(corpse.id,app.world.cell)).ok,"Duplicate recovery cannot create another restore")
	var fixture:=OS.get_environment("SSJX_SOUL_SERVER_FIXTURES")
	app.queue_free();await get_tree().process_frame
	if not fixture.is_empty():
		for record in JSON.parse_string(FileAccess.get_file_as_string(fixture)):
			var model:=OnlinePve.new();model.bind_character(record.character.id,"http://127.0.0.1:1")
			check(model.valid(record),"Real server soul/revived snapshots validate")
			var online:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
			online.character_id=record.character.id;add_child(online);online.set_process(false);online.network.set_process(false)
			online.network.pve.state=record;online.network.pve.ready=true
			var c:Dictionary=record.character
			var entity:Dictionary={"id":c.id,"display_name":c.display_name,"job":c.job,"gender":c.gender,"cell":[c.cell_x,c.cell_y],"next_cell":null,"segment_progress":0,"entity_revision":"1","world_epoch":"1","last_input_seq":0}
			online.network.entities={c.id:entity};online._snapshot(online.network.entities)
			online.camera.position=online.actors[c.id].root.position
			online._update_soul_visuals()
			var spirit:bool=c.get("corpse") is Dictionary
			check(online.soul_overlay.visible==spirit and online.soul_markers.grave.visible==spirit and online.soul_markers.spawn_marker.visible==spirit,"Production online view reveals resurrection markers only in authoritative soul state")
			check((online.actors[c.id].sprite.modulate.a<1)==spirit,"Online actor transparency follows authoritative soul state")
			await capture("online-soul" if spirit else "online-revived")
			online.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(good_path))
	Game.player=old;Game.save_path=old_path
	check(OnlineAccount.pending_pve==pending and (FileAccess.get_sha256(old_path) if FileAccess.file_exists(old_path) else "")==old_hash,"Test leaves real saves and online commands untouched")
	print("SOUL RECOVERY: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)
