extends Node
const DOCUMENT:=preload("res://scripts/admin/pixel_document.gd")
const PART:="boneglow/wzs/wzst2"
const KEY:="hero/wzs_w29_c13_h11"
var checks:=0
var failures:=0
var fixture:=""

func check(ok:bool,text:String)->void:
	checks+=1
	if not ok: failures+=1;push_error("PIXEL EDITOR: "+text)

func settle()->void:
	for frame in 6: await get_tree().process_frame

func _ready()->void: _run.call_deferred()

func _run()->void:
	var player:=Game.player.duplicate(true)
	var save_path:=Game.save_path
	var save_hash:=FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else ""
	var real_manifest:=AppearanceEdits.manifest_path
	var real_folder:=AppearanceEdits.image_folder
	var real_hash:=AppearanceEdits.fingerprint()
	var original_path:String=AppearanceEdits.specs()[PART].texture
	var source_hash:=FileAccess.get_sha256(original_path)
	fixture="user://pixel_editor_test_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	AppearanceEdits.manifest_path=fixture+"/manifest.tres"
	AppearanceEdits.image_folder=fixture+"/images"
	AppearanceEdits.reload_saved()
	var doc:=DOCUMENT.new();doc.open(PART)
	var tail:=doc.image.get_region(doc.region(1)).get_data()
	var old_pixel:Color=doc.sample(0,Vector2i(2,2))
	doc.checkpoint();doc.paint(0,Vector2i(2,2),Color.MAGENTA)
	check(doc.sample(0,Vector2i(2,2))==Color.MAGENTA,"Pencil paints native pixels")
	check(doc.image.get_region(doc.region(1)).get_data()==tail,"Painting does not spill into lower hair frame")
	doc.checkpoint();doc.paint(0,Vector2i(2,2),Color.TRANSPARENT)
	check(doc.sample(0,Vector2i(2,2)).a==0,"Eraser creates real transparency")
	check(doc.undo() and doc.sample(0,Vector2i(2,2))==Color.MAGENTA,"Undo restores erased pixel")
	check(doc.undo() and doc.sample(0,Vector2i(2,2))==old_pixel,"Undo restores original pixel")
	check(doc.redo() and doc.sample(0,Vector2i(2,2))==Color.MAGENTA,"Redo restores stroke")
	var native:=OriginalArt.actor_info("hero/wzs")
	var baseline:=HeroAppearance.build(KEY,native)
	var old_pose=baseline.info.native_battle.pose_x.duplicate(true)
	var old_image:Image=baseline.texture.get_image()
	doc.move(0,Vector2i(2,-3),true)
	check(doc.offsets==[[2,-3],[2,-3]],"Move can link head and lower hair without cropping")
	AppearanceEdits.set_draft({PART:doc.data()})
	var changed:=HeroAppearance.build(KEY,native)
	check(changed.texture.get_image().get_data()!=old_image.get_data(),"Draft pixels/placement appear in real composed texture")
	check(changed.info.native_battle.pose_x==old_pose,"Movement retains native ground anchors")
	var expected:=[Vector2i(2,-3),Vector2i(3,2),Vector2i(-2,3),Vector2i(-3,-2),Vector2i(-2,-3),Vector2i(3,-2),Vector2i(2,3),Vector2i(-3,2)]
	for transform in 8: check(AppearanceEdits.offset_for(PART,0,transform)==expected[transform],"Placement transforms correctly "+str(transform))
	var actor:=OriginalArt.actor(KEY);var before_frames:=actor.sprite_frames
	var result:=AppearanceEdits.save({PART:doc.data()},AppearanceEdits.fingerprint())
	check(result.ok,"Save PNG and manifest atomically: "+result.message)
	AppearanceEdits.reload_saved()
	check(AppearanceEdits.image_for(PART).get_data()==doc.image.get_data(),"Saved pixels survive reload")
	check(AppearanceEdits.offsets_for(PART)==[[2,-3],[2,-3]],"Saved positions survive reload")
	var after:=OriginalArt.actor(KEY)
	check(after.sprite_frames!=before_frames,"Save invalidates strong and weak actor caches")
	check(after.sprite_frames.get_frame_count("attack")==actor.sprite_frames.get_frame_count("attack"),"Saving preserves animation steps")
	actor.free();after.free()
	check(FileAccess.get_sha256(original_path)==source_hash,"Save never overwrites source atlas")
	var stable_manifest:=AppearanceEdits.fingerprint()
	check(not AppearanceEdits.save({PART:{"image":Image.create(2,2,false,Image.FORMAT_RGBA8),"offsets":[[0,0],[0,0]]}},stable_manifest).ok,"Reject wrong atlas dimensions")
	check(not AppearanceEdits.save({PART:{"image":doc.image,"offsets":[[0,129],[0,0]]}},stable_manifest).ok,"Reject unbounded placement")
	check(AppearanceEdits.fingerprint()==stable_manifest,"Invalid edits do not change saved manifest")
	var stale:=AppearanceEdits.fingerprint()
	var file:=FileAccess.open(AppearanceEdits.manifest_path,FileAccess.READ_WRITE);file.seek_end();file.store_string(" ");file.close()
	check(not AppearanceEdits.save({PART:doc.data()},stale).ok,"Reject stale save from another window")
	AppearanceEdits.reload_saved()
	# A native default hero also uses corrected parts, not its old baked atlas.
	var native_doc:=DOCUMENT.new();native_doc.open("wzst1")
	native_doc.paint(0,Vector2i(0,0),Color.MAGENTA)
	AppearanceEdits.set_draft({"wzst1":native_doc.data()})
	check(HeroAppearance.composition_key("hero/wzs")=="hero/wzs_w1_c0_h0","Default heroes use overrides")
	check(HeroAppearance.composition_key("hero/wzs_w0_c2")=="hero/wzs_w0_c2_h0","Legacy appearance aliases use overrides")
	var default_actor:=OriginalArt.actor("hero/wzs")
	check(OriginalArt.actor_info("hero/wzs").has("frame_regions"),"Default actor rebuilds from edited native layers")
	default_actor.free();AppearanceEdits.clear_draft()
	await _test_ui()
	# Invalid manifest paths cannot redirect image loading outside edited assets.
	var unsafe:=NativeAppearanceOverrides.new()
	unsafe.parts={PART:{"texture":"res://project.godot","offsets":[[0,0],[0,0]]}}
	ResourceSaver.save(unsafe,AppearanceEdits.manifest_path)
	AppearanceEdits.reload_saved()
	check(AppearanceEdits.image_for(PART)==null and not AppearanceEdits.load_error.is_empty(),"Reject unsafe texture path")
	AppearanceEdits.clear_draft()
	AppearanceEdits.manifest_path=real_manifest;AppearanceEdits.image_folder=real_folder;AppearanceEdits.reload_saved()
	check(AppearanceEdits.fingerprint()==real_hash,"Tests never alter actual override manifest")
	check(Game.player==player and Game.save_path==save_path,"Editing never changes player state")
	check((FileAccess.get_sha256(save_path) if FileAccess.file_exists(save_path) else "")==save_hash,"Editing never writes player save")
	_remove_fixture(fixture)
	print("EQUIPMENT PIXEL EDITOR: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)

func _test_ui()->void:
	var browser=load("res://scenes/admin/data_browser.tscn").instantiate()
	browser.configure_window=false
	get_window().size=Vector2i(1100,760);get_window().content_scale_size=Vector2i(1100,760)
	add_child(browser);await settle()
	var panel=browser.get_node("%AppearanceComparison")
	panel.set_equipment(ShopRules.item("ai/boneglow/wzs/hat"))
	check(panel.get_node("%EditAppearance").visible,"Actual equipment panel exposes editor entry")
	panel.get_node("%EditAppearance").pressed.emit()
	await settle()
	var editor=panel.pixel_editor
	check(is_instance_valid(editor) and editor.documents.has(PART),"Editor opens the actual mapped head atlas")
	if not is_instance_valid(editor): browser.queue_free();return
	check(editor.frame_choice.item_count==2 and editor.frame_choice.get_item_text(1).contains("下方发尾"),"Native lower hair is labelled correctly")
	var canvas=editor.canvas
	var point:Vector2=(canvas.origin+Vector2(canvas.document.offsets[0][0],canvas.document.offsets[0][1])+Vector2(3.5,3.5))*canvas.zoom
	editor.palette.color=Color.CYAN;canvas.color=Color.CYAN;editor.set_tool("pencil")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=point;click.pressed=true
	canvas._gui_input(click);canvas.finish_stroke()
	check(editor.document().sample(0,Vector2i(3,3))==Color.CYAN,"Real pencil tool handles canvas input")
	editor.set_tool("picker");canvas._gui_input(click)
	check(editor.palette.color==Color.CYAN and canvas.tool=="pencil","Eyedropper picks exact RGBA and returns to pencil")
	editor.set_tool("eraser");canvas._gui_input(click);canvas.finish_stroke()
	check(editor.document().sample(0,Vector2i(3,3)).a==0,"Real eraser tool clears a pixel")
	editor._undo()
	check(editor.document().sample(0,Vector2i(3,3))==Color.CYAN,"Toolbar undo restores pixel")
	editor.set_tool("move")
	canvas._gui_input(click)
	var motion:=InputEventMouseMotion.new();motion.position=point+Vector2(canvas.zoom,-canvas.zoom);canvas._gui_input(motion);canvas.finish_stroke()
	var offsets:Array=editor.document().offsets
	check(offsets[0]==offsets[1],"Dragging linked head moves both segments")
	editor.preview_timer.stop();editor._preview()
	editor.save_changes()
	check(not editor.document().dirty() and not editor.status.text.contains("失败"),"Save button applies and clears dirty state")
	editor._set_offset(Vector2i(4,-4));editor.request_close()
	check(editor.discard_dialog.visible and is_instance_valid(editor),"Closing dirty editor prompts instead of losing changes")
	editor.discard_dialog.hide();editor._undo()
	await settle()
	var output:=OS.get_environment("SSJX_PIXEL_EDITOR_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		editor._restore_source()
		editor.save_changes()
		editor.set_tool("eraser")
		editor._center_canvas()
		await settle()
		DirAccess.make_dir_recursive_absolute(output)
		RenderingServer.force_draw()
		check(editor.get_texture().get_image().save_png(output.path_join("pixel-editor.png"))==OK,"Capture actual editor")
		for button in [editor.save_button,editor.undo_button,editor.redo_button]:
			check(Rect2(Vector2.ZERO,Vector2(editor.size)).encloses(button.get_global_rect()),"Editor action fits window")
	editor.discard_and_close();await settle()
	check(is_instance_valid(panel.after_preview.sprite),"Closing editor refreshes saved equipment preview")
	panel.set_equipment(ShopRules.item("ai/boneglow/wzs/boots"))
	check(not panel.get_node("%EditAppearance").visible,"Stat-only single item has no invented editable layer")
	panel.get_node("%SetPreview").button_pressed=true
	check(panel.get_node("%EditAppearance").visible,"Full-set view exposes the real visual layers even from a stat-only item")
	panel.open_pixel_editor();await settle()
	var full_editor=panel.pixel_editor
	check(full_editor.documents.size()==5,"Full-set editor includes weapon, three clothing layers and head")
	check(not full_editor.frame_choice.get_item_text(1).contains("下方发尾"),"Weapon poses are not incorrectly labelled as hair")
	full_editor.discard_and_close();await settle()
	browser.queue_free();await settle()

func _remove_fixture(path:String)->void:
	var absolute:=ProjectSettings.globalize_path(path)
	check(absolute.begins_with(ProjectSettings.globalize_path(fixture)),"Cleanup stays inside owned fixture")
	var directory:=DirAccess.open(path)
	if directory==null: return
	for sub in directory.get_directories(): _remove_fixture(path+"/"+sub)
	for filename in directory.get_files(): directory.remove(filename)
	DirAccess.remove_absolute(path)
