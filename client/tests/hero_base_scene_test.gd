extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("HERO BASE: "+text)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	var player:=Game.player.duplicate(true)
	var actors:Array[NativeHeroSprite]=[]
	for stem in ["mzs","wzs","mck","wck","mfs","wfs"]:
		var default:=AppearanceResources.default_outfit(stem)
		check(default.valid() and default.uses_baked() and default.signature()==default.baked_signature,"Unedited default Resource shares the original baked atlas: "+stem)
		var exposed:=default.get_property_list().filter(func(p:Dictionary)->bool:return p.name in ["weapon","clothing","head"] and p.type==TYPE_OBJECT)
		check(exposed.size()==3,"Godot Inspector exposes the three typed Resource pickers: "+stem)
		var actor:NativeHeroSprite=load("res://scenes/actors/catalog/hero/"+stem+".tscn").instantiate()
		add_child(actor);actor.pause()
		var id:=actor.get_instance_id();var scene:=actor.scene_file_path
		var outfit:=default.duplicate() as NativeHeroOutfit
		outfit.weapon=AppearanceResources.equipment(stem,"weapon",0)
		actor.outfit=outfit
		check(actor.get_instance_id()==id and actor.scene_file_path==scene and actor.outfit.codes()==[0,0,0] and actor.get_meta("art_key")=="hero/%s_w0_c0_h0"%stem,"Dropping a native outfit Resource changes the existing base scene to unarmed: "+stem)
		var frames:=actor.sprite_frames
		outfit.weapon=AppearanceResources.equipment(stem,"weapon",2)
		check(actor.sprite_frames!=frames and actor.outfit.codes()==[2,0,0],"Editing the nested weapon Resource refreshes the visible sprite automatically: "+stem)
		frames=actor.sprite_frames;outfit.clothing=AppearanceResources.equipment(stem,"clothing",1)
		check(actor.sprite_frames!=frames and actor.outfit.codes()==[2,1,0],"Clothing switches by Resource without another TSCN: "+stem)
		frames=actor.sprite_frames;outfit.head=AppearanceResources.equipment(stem,"head",3)
		check(actor.sprite_frames!=frames and actor.outfit.codes()==[2,1,3],"Head style switches by Resource without another TSCN: "+stem)
		check(actor.scene_file_path==scene and actor.get_instance_id()==id and actor.sprite_frames.has_animation("attack"),"All three switches retain the same node, base scene and original actions: "+stem)
		var edited:=outfit.duplicate(true) as NativeHeroOutfit
		actor.outfit=edited;frames=actor.sprite_frames
		edited.weapon.parts=AppearanceResources.equipment(stem,"weapon",3).parts.duplicate()
		check(actor.sprite_frames!=frames and actor.outfit.codes()==[2,1,3],"Nested part Resource edits refresh rendering even when the cosmetic code stays unchanged: "+stem)
		actor.outfit=outfit
		var path:="user://hero_outfit_%s_%d.tres"%[stem,Time.get_ticks_usec()]
		check(ResourceSaver.save(outfit,path)==OK,"Save an actual Godot outfit Resource: "+stem)
		var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as NativeHeroOutfit
		check(loaded!=null and loaded.valid() and loaded.codes()==[2,1,3] and loaded.signature()==outfit.signature(),"Outfit resource roundtrip retains parts and visual codes: "+stem)
		DirAccess.remove_absolute(path)
		var alias:=OriginalArt.actor("hero/%s_w0_c0"%stem)
		check(alias.scene_file_path==scene and alias.get_meta("art_key")=="hero/%s_w0_c0"%stem and alias.outfit.codes()==[0,0,0],"Old stored/network appearance IDs still resolve to the one base scene: "+stem)
		alias.free()
		var default_alias:=OriginalArt.actor("hero/%s_w1_c0_h0"%stem)
		check(default_alias is NativeHeroSprite and default_alias.scene_file_path==scene and default_alias.outfit.uses_baked(),"Explicit default/h0 aliases also resolve without a separate metadata or scene file: "+stem)
		default_alias.free()
		var creation:=OriginalArt.actor("creation/"+stem)
		check(creation.scene_file_path==scene and creation.outfit.weapon.visual_code==(2 if stem.ends_with("zs") else 1),"Creation preview reuses the same scene and preserves its original weapon preset: "+stem)
		creation.free()
		var bad:=outfit.duplicate() as NativeHeroOutfit;bad.weapon=AppearanceResources.equipment("wfs" if stem!="wfs" else "mck","weapon",1)
		frames=actor.sprite_frames;actor.outfit=bad
		check(not bad.valid() and actor.sprite_frames==frames and not actor._get_configuration_warnings().is_empty(),"A foreign sex/job Resource is rejected without corrupting visible frames: "+stem)
		actor.outfit=outfit;actors.append(actor)
	var base:=AppearanceResources.default_outfit("mck")
	var mutated:=base.duplicate(true) as NativeHeroOutfit
	mutated.weapon.visual_code=2
	check(not mutated.uses_baked(),"Editing a default preset disables the baked fast path instead of hiding Inspector edits")
	for n in range(20):
		var a:=OriginalArt.actor("hero/mck_w%d_c%d_h%d"%[n%4,n%3,n%5]);a.free()
	check(AppearanceResources._outfits.size()<=6 and OriginalArt._dynamic_order.size()<=6 and HeroAppearance._prepared.size()<=6,"Resource/atlas/frame caches remain bounded across many combinations")
	check(Game.player==player,"Editing visual Resources never mutates player/save data")
	var folder:=OS.get_environment("SSJX_HERO_BASE_CAPTURE")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":
		var viewport:=SubViewport.new();viewport.size=Vector2i(480,240);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
		for i in actors.size():
			remove_child(actors[i]);viewport.add_child(actors[i]);actors[i].position=Vector2(45+80*i,170);actors[i].play("idle");actors[i].pause()
		for i in 3:await get_tree().process_frame
		RenderingServer.force_draw();DirAccess.make_dir_recursive_absolute(folder)
		check(viewport.get_texture().get_image().save_png(folder.path_join("six-base-scenes-switched.png"))==OK,"Capture six actual base scenes after Resource-only switching")
		viewport.queue_free()
	else:
		for actor in actors:actor.free()
	print("HERO BASE SCENES: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
