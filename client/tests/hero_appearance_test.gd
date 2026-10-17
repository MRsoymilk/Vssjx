extends Node
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error("HERO PARTS: "+message)
func _ready() -> void:
	for stem in ["mzs","wzs","mck","wck","mfs","wfs"]:
		var base := OriginalArt.actor_info("hero/"+stem)
		var built := HeroAppearance.build("hero/%s_w1_c0_h0"%stem,base)
		check(not built.is_empty(),"Can compose "+stem)
		if built.is_empty(): continue
		var texture: Texture2D = load(base.texture)
		var expected := texture.get_image()
		if expected.is_compressed(): expected.decompress()
		expected.convert(Image.FORMAT_RGBA8)
		var atlas: Image = built.texture.get_image()
		check(int(built.info.origin[0])==int(base.origin[0]) and int(built.info.origin[1])==int(base.origin[1]) and built.info.width==base.width and built.info.height==base.height,"Original canvas bounds preserved")
		for i in int(base.count):
			var r: Array = built.info.frame_regions[i]
			var actual := Image.create(int(base.width),int(base.height),false,Image.FORMAT_RGBA8)
			actual.blit_rect(atlas,Rect2i(int(r[0]),int(r[1]),int(r[2]),int(r[3])),Vector2i(int(r[4]),int(r[5])))
			var reference := expected.get_region(Rect2i((i%int(base.columns))*int(base.width),(i/int(base.columns))*int(base.height),int(base.width),int(base.height)))
			var actual_flat := Image.create(actual.get_width(),actual.get_height(),false,Image.FORMAT_RGBA8)
			actual_flat.fill(Color.BLACK);actual_flat.blend_rect(actual,Rect2i(Vector2i.ZERO,actual.get_size()),Vector2i.ZERO)
			var reference_flat := Image.create(reference.get_width(),reference.get_height(),false,Image.FORMAT_RGBA8)
			reference_flat.fill(Color.BLACK);reference_flat.blend_rect(reference,Rect2i(Vector2i.ZERO,reference.get_size()),Vector2i.ZERO)
			check(actual_flat.get_data()==reference_flat.get_data(),"Original ANI pixel identity: %s frame %d"%[stem,i])
		var key := "hero/%s_w%d_c11_h9" % [stem,21 if stem.ends_with("ck") else 19]
		var sprite := OriginalArt.battle_actor(key)
		check(sprite.sprite_frames.get_frame_count("attack")==base.playback.attack.size(),"Full weapon, clothing and head retain native attack")
		check(sprite.get_meta("art_key")==key and sprite.get_meta("native_ground_anchor"),"Dynamic actor keeps battle ground anchor")
		sprite.free()
	print("HERO PARTS: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
