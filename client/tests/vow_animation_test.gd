extends Node
## Compare the real composited outfits against their native joint templates.
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error("VOW ANIMATION: "+message)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	var family: NativeEquipmentFamily = load("res://assets/appearance_resources/families/vow.tres")
	var templates := [[9,6,7],[9,6,5],[9,4,5],[9,4,1],[7,6,2],[7,7,2]]
	var folder := OS.get_environment("SSJX_VOW_ACTION_CAPTURE")
	if not folder.is_empty(): DirAccess.make_dir_recursive_absolute(folder)
	for index in family.sets.size():
		var row: Dictionary = family.sets[index]
		var base := OriginalArt.actor_info("hero/"+row.stem)
		var codes: Array = templates[index]
		var native := HeroAppearance.build("hero/%s_w%d_c%d_h%d"%[row.stem,codes[0],codes[1],codes[2]],base)
		var dressed := HeroAppearance.build("hero/%s_w%d_c%d_h%d"%[row.stem,row.weapon_code,row.clothing_code,row.head_code],base)
		check(not native.is_empty() and not dressed.is_empty(),row.stem+" builds native template and ceremonial outfit")
		if native.is_empty() or dressed.is_empty(): continue
		check(dressed.info.origin==native.info.origin and dressed.info.width==native.info.width and dressed.info.height==native.info.height,row.stem+" preserves attachment frame extents and actor origin")
		check(dressed.info.native_battle==native.info.native_battle,row.stem+" preserves every battle impact, root, recoil and ground anchor")
		check(dressed.info.sequences==native.info.sequences and dressed.info.playback==native.info.playback,row.stem+" preserves all native source and gameplay timelines")
		var image: Image = dressed.texture.get_image()
		for region in dressed.info.frame_regions:
			var rect := Rect2i(region[0],region[1],region[2],region[3])
			check(Rect2i(Vector2i.ZERO,image.get_size()).encloses(rect) and not image.get_region(rect).is_invisible(),row.stem+" nonempty, valid composed source frame")
		var frames := HeroAppearance.sprite_frames(dressed.info,dressed.texture)
		var original := HeroAppearance.sprite_frames(native.info,native.texture)
		check(frames.get_animation_names()==original.get_animation_names(),row.stem+" exposes every source action")
		for action in frames.get_animation_names():
			check(frames.get_frame_count(action)==original.get_frame_count(action) and frames.get_animation_speed(action)==original.get_animation_speed(action) and frames.get_animation_loop(action)==original.get_animation_loop(action),row.stem+" timing "+action)
			for step in frames.get_frame_count(action):
				check(frames.get_frame_duration(action,step)==original.get_frame_duration(action,step),row.stem+" duration "+action+" / "+str(step))
		for action in dressed.info.playback:
			if folder.is_empty(): continue
			var steps: Array = dressed.info.playback[action]
			for step in steps.size():
				var region: Array = dressed.info.frame_regions[int(steps[step][0])]
				var crop := image.get_region(Rect2i(region[0],region[1],region[2],region[3]))
				check(crop.save_png(folder.path_join("%s-%s-%02d.png"%[row.stem,action,step]))==OK,"Save actual compositor action "+row.stem+" / "+action)
	print("VOW ANIMATION: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
