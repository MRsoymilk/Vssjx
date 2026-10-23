extends Node
## Compare the real compositor before/after grading, including editor overrides.
const ROOT := "res://../"
const DATA := ROOT+"analysis/ai-generated/equipment/pixel-refinement/"
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("EQUIPMENT REFINEMENT: "+message)

func _ready() -> void:_run.call_deferred()

func _run() -> void:
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA+"baseline.json"))
	var report:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DATA+"refinement.json"))
	var output:=OS.get_environment("SSJX_REFINEMENT_CAPTURE")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	AppearanceEdits.ensure_loaded()
	var saved:=AppearanceEdits._saved.duplicate(true)
	for row in GeneratedEquipment.manifest().sets:
		if row.id not in report.sets:continue
		var docs:Dictionary={}
		for source in [row.head]+row.body+[row.weapon]:
			var part:=AppearanceResources.part(source)
			var path:String=baseline.textures["client/"+part.texture_path.trim_prefix("res://")].input
			var offsets:Array=[]
			for region in part.regions:offsets.append([0,0])
			if baseline.overrides.has(source):
				path=baseline.overrides[source].texture
				offsets=baseline.overrides[source].offsets
			else:path=ROOT+path
			var image:=Image.new()
			check(image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))==OK,"Read baseline pixels "+source)
			docs[source]={"image":image,"offsets":offsets}
		var key:="hero/%s_w%d_c%d_h%d"%[row.stem,row.weapon_code,row.clothing_code,row.head_code]
		var native:=OriginalArt.actor_info("hero/"+row.stem)
		AppearanceEdits.set_draft(docs)
		var before:=HeroAppearance.build(key,native)
		AppearanceEdits.clear_draft()
		var after:=HeroAppearance.build(key,native)
		check(not before.is_empty() and not after.is_empty(),row.id+" composes both versions")
		if before.is_empty() or after.is_empty():continue
		check(before.info==after.info,row.id+" retains ALL frame rectangles, timing and battle anchors")
		var a:Image=before.texture.get_image();var b:Image=after.texture.get_image()
		var first:=a.get_data();var second:=b.get_data();var equal_mask:=first.size()==second.size()
		if equal_mask:
			for i in range(3,first.size(),4):
				if first[i]!=second[i]:equal_mask=false;break
		check(equal_mask,row.id+" retains silhouette, hand/grip and hair seams through every composed pose")
		check(first!=second,row.id+" actually applies the refined pixels")
		for action in after.info.playback:
			var frames:=HeroAppearance.sprite_frames(after.info,after.texture)
			check(frames.get_frame_count(action)==after.info.playback[action].size(),row.id+" plays "+action)
			if output.is_empty():continue
			var region:Array=after.info.frame_regions[int(after.info.playback[action][0][0])]
			var rect:=Rect2i(region[0],region[1],region[2],region[3])
			for pair in [["before",a],["after",b]]:
				var image:Image=pair[1].get_region(rect)
				check(image.save_png(output.path_join(row.id.replace("/","-")+"-"+action+"-"+pair[0]+".png"))==OK,"Save compositor review "+row.id+" / "+action)
	check(AppearanceEdits._draft.is_empty() and AppearanceEdits._saved==saved,"Review restores the active editor overrides without writing them")
	print("EQUIPMENT REFINEMENT: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
