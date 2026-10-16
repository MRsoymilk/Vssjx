class_name OriginalArt
extends RefCounted

static var catalog: Dictionary = {}
static var cached: Dictionary = {}
static var _index: Dictionary = {}
static var _index_loaded := false
static var _metadata_reads := 0
static var _metadata_bytes := 0
const ACTOR_SCENE := preload("res://scenes/actors/original_actor.tscn")
const INDEX_PATH := "res://assets/data/actors.json"

static func _read_metadata(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	_metadata_reads += 1
	_metadata_bytes += file.get_length()
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return {}
	return parser.data

static func has_actor(key: String) -> bool:
	if not _index_loaded:
		var manifest := _read_metadata(INDEX_PATH)
		if manifest.get("format_version") != 2 or not manifest.get("actors") is Dictionary: return false
		_index = manifest.actors
		_index_loaded = true
	return _index.has(key)

static func actor_info(key: String) -> Dictionary:
	# Metadata and SpriteFrames are separate caches: battle preparation may read
	# only the requested metadata before loading its texture asynchronously.
	if catalog.has(key): return catalog[key]
	if not has_actor(key): return {}
	var path: Variant = _index[key]
	if not path is String or path != "res://assets/data/actors/" + key + ".json": return {}
	var info := _read_metadata(path)
	if not _valid_info(info): return {}
	catalog[key] = info
	return info

static func metadata_stats() -> Dictionary:
	return {"indexed_actors": _index.size(), "loaded_actors": catalog.size(), "sprite_frames": cached.size(), "json_files_read": _metadata_reads, "json_bytes_read": _metadata_bytes}

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))

static func _valid_steps(value: Variant, count: int) -> bool:
	if not value is Array: return false
	for step in value:
		if not step is Array or step.size() != 2 or not _integer(step[0], 0, count - 1) or not _integer(step[1], 0, 255): return false
	return true

static func _valid_info(info: Dictionary) -> bool:
	if not info.get("texture") is String or not info.texture.begins_with("res://assets/actors/") or not info.texture.ends_with(".png"): return false
	for key in ["width", "height", "columns", "count"]:
		if not _integer(info.get(key), 1, 4096): return false
	if not info.get("origin") is Array or info.origin.size() != 2: return false
	for coordinate in info.origin:
		if not _integer(coordinate, -4096, 4096): return false
	if not _integer(info.get("anchor_x", 0), -4096, 4096): return false
	if not info.get("sequences") is Array or info.sequences.is_empty() or not info.get("playback", {}) is Dictionary: return false
	for sequence in info.sequences:
		if not _valid_steps(sequence, int(info.count)): return false
	for sequence in info.get("playback", {}).values():
		if not _valid_steps(sequence, int(info.count)): return false
	return true

static func actor(key: String) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = ACTOR_SCENE.instantiate()
	var info := actor_info(key)
	if info.is_empty():
		push_error("Missing original actor: " + key)
		return sprite
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
			for step in source_steps(info, i):
				frames.add_frame(animation, regions[int(step[0])], maxf(1.0, float(step[1])))
		var modes := ["idle", "walk", "attack"]
		for optional in ["cast", "hurt"]:
			if info.get("playback", {}).has(optional): modes.append(optional)
		for mode in modes:
			frames.add_animation(mode)
			frames.set_animation_speed(mode, 6.0 if mode == "idle" else (8.0 if mode == "cast" else 10.0))
			frames.set_animation_loop(mode, mode in ["idle", "walk"])
			var seq_index := maxi(0, sequences.size() - 1)
			if mode == "attack":
				seq_index = maxi(0, sequences.size() - 6)
			var steps: Array = info.get("playback", {}).get(mode, source_steps(info, seq_index))
			if steps.is_empty():
				steps = [[0, 1]]
			for step in steps:
				frames.add_frame(mode, regions[int(step[0])], maxf(1.0, float(step[1])))
		cached[key] = frames
	sprite.sprite_frames = cached[key]
	sprite.offset = Vector2(info.origin[0] - info.get("anchor_x", 0), info.origin[1])
	sprite.animation_finished.connect(func() -> void:
		if sprite.animation in ["attack", "cast", "hurt"]: sprite.play("idle")
	)
	sprite.play("idle")
	return sprite

static func source_steps(info: Dictionary, serialized_sequence: int) -> Array:
	# Native 22d74 fills the frame pointer table from count-1 down to zero.
	# Keep serialized evidence intact; resolve native frame references on use.
	var count := int(info.get("native_battle", {}).get("source_frame_count", info.count))
	var steps: Array = []
	for step in info.sequences[serialized_sequence]: steps.append([count - 1 - int(step[0]), step[1]])
	return steps

static func effect(key: String, sequence: int = 0) -> AnimatedSprite2D:
	var sprite := actor(key)
	var animation := "source_%d" % (actor_info(key).sequences.size() - 1 - sequence)
	sprite.sprite_frames.set_animation_loop(animation, false)
	sprite.animation_finished.connect(sprite.queue_free)
	sprite.play(animation)
	return sprite
