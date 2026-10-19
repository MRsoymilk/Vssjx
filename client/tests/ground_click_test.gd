extends "res://tests/population_test.gd"

func visible_point(sprite: AnimatedSprite2D) -> Vector2:
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame)
	var image := texture.get_image()
	var bounds := image.get_used_rect()
	var nearest := Vector2.ZERO
	var distance := INF
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			if image.get_pixel(x,y).a < 0.8: continue
			var pixel := Vector2(x+0.5,y+0.5)
			if pixel.distance_squared_to(bounds.get_center()) < distance:
				nearest=pixel;distance=pixel.distance_squared_to(bounds.get_center())
	if texture is AtlasTexture and image.get_size()!=Vector2i(texture.get_size()): nearest+=texture.margin.position
	return sprite.to_global(sprite.offset+nearest-(texture.get_size()*0.5 if sprite.centered else Vector2.ZERO))

func local_click(world: ShushanWorld, point: Vector2) -> void:
	world.click(point-world.camera.get_screen_center_position()+Vector2(world.get_viewport().size)/2.0)

func online_click(view: OnlineWorldView, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=point-view.camera.get_screen_center_position()+Vector2(view.viewport.size)/2.0
	view._map_input(event)

func _run() -> void:
	await Platform.when_ready()
	output=OS.get_environment("SSJX_GROUND_CLICK_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	await check_packed_sprite()
	var old:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	Game.save_path="user://ground_click_%d.json"%OS.get_process_id()
	Game.new_player("地面点击",1,0)
	Game.player.cell=[16,17]
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,375);add_child(viewport)
	var world:=ShushanWorld.new();viewport.add_child(world);world.set_process(false)
	var image:=TextureRect.new();image.texture=viewport.get_texture();image.position=Vector2(0,28);image.size=Vector2(320,375);image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;add_child(image)
	world.camera.force_update_scroll()
	var ground:=Vector2i(18,11)
	check(world.target_at_pixel(world.cell_center(ground)).is_empty(),"Ground directly below a wolf is not its body")
	local_click(world,world.cell_center(ground)+Vector2(3,2))
	check(world.pending.is_empty() and world.path.back()==ground,"Ground near a live wolf preserves the clicked destination")
	check(world.move_target.destination==ground and world.move_target.position==world.cell_center(ground),"Marker matches the snapped path endpoint")
	await capture("local_ground")
	for tick in 180: world._process(1.0/60.0)
	check(world.cell==ground and world.hero.position==world.cell_center(ground) and not world.move_target.visible,"Feet arrive at the indicated cell without opening combat")
	world.cell=Vector2i(16,17);world.stop_moving()
	var wolf: AnimatedSprite2D=world.enemy_nodes.wolf_a
	var moved_cell:=Vector2i(20,11)
	wolf.position=world.cell_center(moved_cell)
	var body:=world.to_local(visible_point(wolf))
	check(world.target_at_pixel(body).get("data",{}).get("id")=="wolf_a","Visible moving wolf remains clickable")
	local_click(world,body)
	check(world.pending.cell==moved_cell and world.path.back().distance_to(moved_cell)==1,"Approach targets the patrol's current cell instead of its home")
	check(world.move_target.destination==world.path.back(),"Interaction marker indicates the actual adjacent stopping cell")
	await capture("local_patrol_approach")
	world.stop_moving()
	check(world.target_at(Vector2i(10,14)).is_empty(),"NPC proximity no longer counts as an exact target")
	var npc:=world.quest_marker.get_parent() as AnimatedSprite2D
	check(world.target_at_pixel(world.to_local(visible_point(npc))).get("kind")=="npc","NPC body still starts interaction")
	image.queue_free();viewport.queue_free();await get_tree().process_frame
	var view:OnlineWorldView=load("res://scenes/ui/online_world_view.tscn").instantiate()
	view.character_id=SELF;add_child(view);view.set_process(false);view.network.set_process(false)
	view.network.world_ready=true
	view.network.entities={SELF:entity(SELF,1,"地面点击",1,0,[16,17])}
	view.network.changed.emit(view.network.entities)
	view.network.stream=EPOCH
	var packet:=residents_packet()
	view.network._receive(packet,JSON.stringify(packet).to_utf8_buffer())
	view.camera.force_update_scroll()
	var selected:Array=[]
	view.resident_selected.connect(func(id:String)->void:selected.append(id))
	var resident:OnlineResident=view.residents.wolf_a
	check(not resident.hit(Vector2(296,184)),"Online wolf does not capture nearby ground")
	online_click(view,Vector2(299,186))
	check(selected.is_empty() and view.network._pending_motion.get("target")==[18,11],"Online ground click sends the intended cell without a monster action")
	check(view.move_target.destination==ground,"Online marker matches the sent movement target")
	await capture("online_ground")
	var point:=view.scene.to_local(visible_point(resident.sprite))
	online_click(view,point)
	check(selected==["wolf_a"],"Clicking the online wolf body still selects it once")
	resident.sprite.scale.x=-1
	point=view.scene.to_local(visible_point(resident.sprite))
	check(resident.hit(point),"Mirrored patrol graphics preserve picking")
	view.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.player=old;Game.save_path=old_path
	print("GROUND CLICK: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func check_packed_sprite() -> void:
	var pixels:=Image.create(20,20,false,Image.FORMAT_RGBA8)
	pixels.fill_rect(Rect2i(8,8,4,4),Color.WHITE)
	var atlas:=AtlasTexture.new()
	atlas.atlas=ImageTexture.create_from_image(pixels)
	atlas.region=Rect2(6,6,8,8)
	atlas.margin=Rect2(5,7,12,12)
	var sprite:=AnimatedSprite2D.new()
	sprite.centered=false;sprite.position=Vector2(100,100);sprite.offset=Vector2(-10,-15)
	sprite.sprite_frames=SpriteFrames.new();sprite.sprite_frames.add_frame("default",atlas)
	add_child(sprite)
	check(WorldSpriteHit.hit(sprite,sprite.to_global(sprite.offset+Vector2(8,10))),"Packed atlas margins preserve visible pixel selection")
	check(not WorldSpriteHit.hit(sprite,sprite.to_global(sprite.offset)),"Transparent atlas corners do not select an actor")
	sprite.scale.x=-1
	check(WorldSpriteHit.hit(sprite,sprite.to_global(sprite.offset+Vector2(8,10))),"Negative facing scale preserves picking")
	sprite.flip_h=true
	check(WorldSpriteHit.hit(sprite,sprite.to_global(sprite.offset+Vector2(12,10))),"Explicit texture flip preserves picking")
	sprite.centered=true
	check(WorldSpriteHit.hit(sprite,sprite.to_global(sprite.offset+Vector2(2,0))),"Centered sprites preserve their original offsets")
	sprite.queue_free();await get_tree().process_frame
