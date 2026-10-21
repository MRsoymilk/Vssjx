extends Node
var checks := 0
var failures := 0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+text)
func _ready()->void:
	_run.call_deferred()
func _run()->void:
	var registry:NativeActorCatalog=load("res://assets/actor_resources/catalog.tres")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/actors.json")).actors
	check(registry.definitions.size()==source.size() and registry.scenes.size()==source.size(),"All actors, NPCs, monsters and supporting effects have native resources")
	for key in source:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source[key]))
		var definition:NativeActorDefinition=load(registry.definitions[key])
		check(JSON.parse_string(JSON.stringify(definition.to_info()))==expected,"Native editable metadata preserves source motion and provenance: "+key)
		var native:NativeActorSprite=load(registry.scenes[key]).instantiate()
		native.initialize()
		var legacy:=OriginalArt.actor(key)
		check(native.art_key==key and native.offset==legacy.offset and native.centered==legacy.centered and native.texture_filter==legacy.texture_filter,"Directly instanced native scene preserves anchor and pixel sampling: "+key)
		var a:=native.sprite_frames;var b:=legacy.sprite_frames
		check(a.get_animation_names()==b.get_animation_names(),"Native SpriteFrames exposes every action and source sequence: "+key)
		for name in b.get_animation_names():
			check(a.get_animation_loop(name)==b.get_animation_loop(name) and a.get_animation_speed(name)==b.get_animation_speed(name) and a.get_frame_count(name)==b.get_frame_count(name),"Action duration, frame count and looping agree: "+key+"/"+name)
			for i in b.get_frame_count(name):
				var x:AtlasTexture=a.get_frame_texture(name,i);var y:AtlasTexture=b.get_frame_texture(name,i)
				check(x.atlas.resource_path==y.atlas.resource_path and x.region==y.region and x.margin==y.margin and x.filter_clip==y.filter_clip and a.get_frame_duration(name,i)==b.get_frame_duration(name,i),"Every native animation frame uses the exact source pixels and timing: "+key+"/"+name+"/"+str(i))
		native.free();legacy.free()
	var viewport:=SubViewport.new();viewport.size=Vector2i(320,480);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	var examples:Array=["hero/mfs","hero/wzs_w2_c1","monster/langw","monster/nt1"]
	for key in source:
		if key.begins_with("npc/") and examples.size()<6:examples.append(key)
	for mode in ["idle","attack"]:
		for index in examples.size():
			for column in 2:
				var sprite:AnimatedSprite2D=OriginalArt.actor(examples[index]) if column==0 else load(registry.scenes[examples[index]]).instantiate()
				viewport.add_child(sprite);sprite.position=Vector2(80+160*column,70+65*index)
				sprite.play(mode);sprite.pause();sprite.frame=mini(3,sprite.sprite_frames.get_frame_count(mode)-1)
		for i in 3:await get_tree().process_frame
		if DisplayServer.get_name()!="headless":
			RenderingServer.force_draw()
			var image:=viewport.get_texture().get_image()
			check(image.get_region(Rect2i(0,0,160,480)).get_data()==image.get_region(Rect2i(160,0,160,480)).get_data(),"Actual native and legacy rendering is pixel-identical for player, NPC and monster "+mode)
			var folder:=OS.get_environment("SSJX_NATIVE_ACTOR_CAPTURE")
			if not folder.is_empty():
				DirAccess.make_dir_recursive_absolute(folder)
				check(image.save_png(folder.path_join("native-parity-"+mode+".png"))==OK,"Save actual native scene rendering")
		for child in viewport.get_children():viewport.remove_child(child);child.queue_free()
	viewport.queue_free()
	print("NATIVE ACTOR RESOURCES: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
