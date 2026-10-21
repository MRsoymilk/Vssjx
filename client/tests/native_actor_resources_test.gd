extends Node
var checks := 0
var failures := 0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("FAIL: "+text)
func _ready()->void:
	_run.call_deferred()
func legacy_actor(info:Dictionary)->AnimatedSprite2D:
	# Test-only baseline from the pre-migration JSON algorithm. Production never
	# loads this source evidence or constructs static actor animations this way.
	var actor:=AnimatedSprite2D.new();actor.centered=false;actor.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	actor.offset=Vector2(info.origin[0]-info.get("anchor_x",0),info.origin[1])
	var frames:=SpriteFrames.new();frames.remove_animation("default")
	var texture:Texture2D=load(info.texture);var regions:Array[AtlasTexture]=[]
	for i in int(info.count):
		var region:=AtlasTexture.new();region.atlas=texture;region.filter_clip=true
		region.region=Rect2((i%int(info.columns))*int(info.width),(i/int(info.columns))*int(info.height),info.width,info.height);regions.append(region)
	for i in info.sequences.size():
		var name:="source_%d"%i;frames.add_animation(name);frames.set_animation_speed(name,10)
		for step in OriginalArt.source_steps(info,i):frames.add_frame(name,regions[int(step[0])],maxf(1,float(step[1])))
	for mode in ["idle","walk","attack","cast","hurt"]:
		if mode in ["cast","hurt"] and not info.get("playback",{}).has(mode):continue
		frames.add_animation(mode);frames.set_animation_speed(mode,6 if mode=="idle" else (8 if mode=="cast" else 10));frames.set_animation_loop(mode,mode in ["idle","walk"])
		var steps:Array=info.get("playback",{}).get(mode,OriginalArt.source_steps(info,maxi(0,info.sequences.size()-(6 if mode=="attack" else 1))))
		if steps.is_empty():steps=[[0,1]]
		for step in steps:frames.add_frame(mode,regions[int(step[0])],maxf(1,float(step[1])))
	actor.sprite_frames=frames;actor.play("idle");return actor
func _run()->void:
	var registry:NativeActorCatalog=load("res://assets/actor_resources/catalog.tres")
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/actors.json")).actors
	check(registry.definitions.size()==source.size() and registry.scenes.size()==source.size(),"All actors, NPCs, monsters and supporting effects have native resources")
	var appearance:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/hero-parts.json"))
	for family in GeneratedEquipment.FAMILIES:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/"+family.id+"-equipment.json"))
		var resource:NativeEquipmentFamily=load(family.path)
		check(JSON.parse_string(JSON.stringify(resource.sets))==expected.sets and JSON.parse_string(JSON.stringify(resource.weapons))==expected.get("weapons",[]),"Native equipment-family mappings preserve every approved visual code: "+family.id)
		appearance.parts.merge(expected.parts)
	for stem in appearance.recipes:
		check(JSON.parse_string(JSON.stringify(AppearanceResources.recipe(stem).to_spec()))==appearance.recipes[stem],"Native Inspector recipe preserves all layer draw orders and transforms: "+stem)
	for key in appearance.parts:
		check(JSON.parse_string(JSON.stringify(AppearanceResources.part(key).to_spec()))==appearance.parts[key],"Native part Resource preserves exact texture and regions: "+key)
	for key in source:
		var expected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source[key]))
		var definition:NativeActorDefinition=load(registry.definitions[key])
		check(JSON.parse_string(JSON.stringify(definition.to_info()))==expected,"Native editable metadata preserves source motion and provenance: "+key)
		var native:NativeActorSprite=load(registry.scenes[key]).instantiate()
		native.initialize()
		var runtime:=OriginalArt.actor(key)
		check(runtime is NativeActorSprite and runtime.scene_file_path==registry.scenes[key] and runtime.sprite_frames==native.sprite_frames,"Production factory actually instantiates the native scene and shared SpriteFrames: "+key)
		runtime.free()
		var legacy:=legacy_actor(expected)
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
				var sprite:AnimatedSprite2D=legacy_actor(JSON.parse_string(FileAccess.get_file_as_string(source[examples[index]]))) if column==0 else load(registry.scenes[examples[index]]).instantiate()
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
	check(OriginalArt.metadata_stats().json_files_read==0 and OriginalArt.metadata_stats().json_bytes_read==0,"Production actor metadata has no JSON adapter")
	print("NATIVE ACTOR RESOURCES: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
