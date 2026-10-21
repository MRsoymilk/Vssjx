extends Node
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("NATIVE EDITOR: "+text)
func _ready()->void:_run.call_deferred()
func _run()->void:
	var before:=Game.player.duplicate(true)
	get_window().size=Vector2i(1100,760);get_window().content_scale_size=Vector2i(1100,760)
	var paused:=OriginalArt.actor("monster/langw");paused.pause();add_child(paused)
	await get_tree().process_frame
	check(not paused.is_playing(),"Factory-created actors preserve a caller's pre-tree pause instead of replaying scene autoplay")
	paused.free()
	var browser=load("res://scenes/admin/data_browser.tscn").instantiate()
	browser.configure_window=false;add_child(browser)
	await get_tree().process_frame
	check(browser.catalog.errors.is_empty(),"All game/admin sources still load after the native migration")
	var registry:NativeActorCatalog=load(OriginalArt.INDEX_PATH)
	var entries:Array=browser.catalog.find("art")
	check(entries.size()==registry.scenes.size(),"Browser lists the entire native actor catalog without old fixed counts")
	for entry in entries:
		check(entry.source==registry.scenes[entry.id] and ResourceLoader.exists(entry.source),"Browser links the actual editable TSCN: "+entry.id)
	for key in ["hero/mfs","hero/wzs_w2_c1","npc/ssjx_baishouxian","monster/langw","monster/nt1"]:
		var selected:Dictionary={}
		for entry in entries:
			if entry.id==key:selected=entry;break
		browser._show_entry(selected)
		var preview=browser.get_node("%Preview")
		check(preview.sprite is NativeActorSprite and preview.sprite.scene_file_path==selected.source,"Actual data-browser preview instances the native scene: "+key)
		var chooser:OptionButton=browser.get_node("%Animations")
		check(chooser.item_count>0,"Native actions remain selectable: "+key)
		for i in chooser.item_count:
			chooser.select(i);chooser.item_selected.emit(i)
			check(preview.sprite.animation==chooser.get_item_metadata(i),"Browser action uses the same stable native animation ID: "+key)
	var definition:NativeActorDefinition=load(registry.definitions["monster/langw"])
	check(definition.texture_path.ends_with("monster_langw.png") and not definition.playback.is_empty(),"Inspector exposes lightweight atlas/motion configuration")
	var paths:=PackedStringArray([definition.texture_path,registry.scenes["monster/langw"]])
	var request:=Platform.context.resource_loader.prepare(paths,self,0,"Resource")
	var deadline:=Time.get_ticks_msec()+10000
	while not request.is_finished() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(request.is_finished() and request.result.ok and request.result.value[paths[0]] is Texture2D and request.result.value[paths[1]] is PackedScene,"Battle preparation accepts the actual mixed texture/PackedScene resource batch")
	var recipe:=AppearanceResources.recipe("mfs")
	check(recipe is NativeAppearanceRecipe and recipe.frames.size()>0 and AppearanceResources.part(recipe.sources[0]) is NativeAppearancePart,"Inspector exposes native part regions and composition recipes")
	check(AppearanceEdits.manifest_path.ends_with(".tres") and ResourceLoader.load(AppearanceEdits.manifest_path) is NativeAppearanceOverrides,"Pixel overrides are native Godot Resources, not JSON runtime data")
	check(Game.player==before,"Browsing native resources does not mutate the player")
	var folder:=OS.get_environment("SSJX_NATIVE_ACTOR_CAPTURE")
	if not folder.is_empty() and DisplayServer.get_name()!="headless":
		browser.select_category("art")
		browser.get_node("%Search").text="npc/ssjx_baishouxian";browser._fill_list()
		browser._show_entry(browser.catalog.find("art","npc/ssjx_baishouxian")[0])
		for i in 3:await get_tree().process_frame
		RenderingServer.force_draw()
		check(get_viewport().get_texture().get_image().save_png(folder.path_join("native-npc-browser.png"))==OK,"Capture the actual NPC native preview")
	browser.queue_free();await get_tree().process_frame
	print("NATIVE ACTOR EDITOR: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
