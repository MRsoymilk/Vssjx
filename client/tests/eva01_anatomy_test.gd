extends Node
var checks:=0
var failures:=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("EVA01 ANATOMY: "+message)

func _ready()->void:_run.call_deferred()

func _run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/eva01-equipment.json"))
	var weapon_codes:=[9,9,9,17,2,7]
	for index in data.sets.size():
		var row:Dictionary=data.sets[index]
		var base:=OriginalArt.actor_info("hero/"+row.stem)
		var native:=HeroAppearance.build("hero/%s_w%d_c9_h2"%[row.stem,weapon_codes[index]],base)
		var equipped:=HeroAppearance.build("hero/%s_w%d_c%d_h%d"%[row.stem,int(row.weapon_code),int(row.clothing_code),int(row.head_code)],base)
		check(not native.is_empty() and not equipped.is_empty(),row.stem+" builds both actual atlases")
		if native.is_empty() or equipped.is_empty():continue
		check(native.info.frame_regions==equipped.info.frame_regions and native.info.origin==equipped.info.origin,row.stem+" keeps every native frame rectangle and origin")
		check(native.info.playback==equipped.info.playback and native.info.native_battle==equipped.info.native_battle,row.stem+" keeps animation timing, ground anchors and attack movement")
		var original:Image=native.texture.get_image()
		var updated:Image=equipped.texture.get_image()
		check(original.get_size()==updated.get_size(),row.stem+" has the same atlas dimensions")
		var a:=original.get_data();var b:=updated.get_data();var same:=a.size()==b.size()
		if same:
			for pixel in range(3,a.size(),4):
				if a[pixel]!=b[pixel]:same=false;break
		check(same,row.stem+" alpha matches original armor through EVERY pose, including hair/neck and hand/grip seams")
		check(a!=b,row.stem+" contains the actual new appearance")
		for action in equipped.info.playback:
			var sprite:=OriginalArt.actor("hero/%s_w%d_c%d_h%d"%[row.stem,int(row.weapon_code),int(row.clothing_code),int(row.head_code)])
			check(sprite.sprite_frames.has_animation(action),row.stem+" plays "+action)
			sprite.free()
	print("EVA01 ANATOMY: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
