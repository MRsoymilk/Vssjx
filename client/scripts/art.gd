class_name OriginalArt
extends RefCounted

static var catalog: Dictionary = {}
static var cached: Dictionary = {}

static func actor(key: String) -> AnimatedSprite2D:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/actors.json"))
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not catalog.has(key):
		push_error("Missing original actor: " + key)
		return sprite
	var info: Dictionary = catalog[key]
	if not cached.has(key):
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		var texture: Texture2D = load(info.texture)
		var regions: Array[AtlasTexture] = []
		for i in int(info.count):
			var region := AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2((i % int(info.columns)) * int(info.width), (i / int(info.columns)) * int(info.height), info.width, info.height)
			regions.append(region)
		var sequences: Array = info.sequences
		for i in sequences.size():
			var animation := "source_%d" % i
			frames.add_animation(animation)
			frames.set_animation_speed(animation, 10.0)
			for step in sequences[i]:
				frames.add_frame(animation, regions[int(step[0])], maxf(1.0, float(step[1])))
		for mode in ["idle", "walk", "attack"]:
			frames.add_animation(mode)
			frames.set_animation_speed(mode, 6.0 if mode == "idle" else 10.0)
			frames.set_animation_loop(mode, mode != "attack")
			var seq_index := maxi(0, sequences.size() - 1)
			if mode == "attack":
				seq_index = maxi(0, sequences.size() - 6)
			var steps: Array = info.get("playback", {}).get(mode, sequences[seq_index])
			if steps.is_empty():
				steps = [[0, 1]]
			for step in steps:
				frames.add_frame(mode, regions[int(step[0])], maxf(1.0, float(step[1])))
		cached[key] = frames
	sprite.sprite_frames = cached[key]
	sprite.centered = false
	sprite.offset = Vector2(info.origin[0] - info.get("anchor_x", 0), info.origin[1])
	sprite.animation_finished.connect(func() -> void:
		if sprite.animation == "attack": sprite.play("idle")
	)
	sprite.play("idle")
	return sprite

static func effect(key: String, sequence: int = 0) -> AnimatedSprite2D:
	var sprite := actor(key)
	var animation := "source_%d" % sequence
	sprite.sprite_frames.set_animation_loop(animation, false)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(animation)
	return sprite
