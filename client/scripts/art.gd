class_name OriginalArt
extends RefCounted

static var catalog: Dictionary = {}
static var cached: Dictionary = {}
static var _dynamic_weak: Dictionary = {}
static var _dynamic_order: Array[String] = []
static var _index: Dictionary = {}
static var _index_loaded := false
static var _metadata_reads := 0
static var _metadata_bytes := 0
static var _native_catalog: Dictionary = {}
static var _scene_paths: Dictionary = {}
static var _edit_revision := -1
static var _appearance_revision := -1
static var _loaded_scenes:Dictionary={}
static var _scene_order:Array[String]=[]
static var _scene_loads:=0
const MAX_SCENES:=48
const ACTOR_SCENE := preload("res://scenes/actors/original_actor.tscn")
const INDEX_PATH := "res://assets/actor_resources/catalog.tres"

static func _record_metadata(path:String) -> void:
	_metadata_reads+=1
	var file:=FileAccess.open(path,FileAccess.READ)
	if file!=null:_metadata_bytes+=file.get_length()

static func actor_keys() -> Array:
	_prepare_index()
	return _index.keys()

static func _prepare_index() -> void:
	if _index_loaded:return
	var registry:=load(INDEX_PATH) as NativeActorCatalog
	if registry==null:return
	_record_metadata(INDEX_PATH)
	_index=registry.definitions;_scene_paths=registry.scenes;_index_loaded=true

static func scene_path(key:String) -> String:
	_prepare_index()
	var outfit:=HeroAppearance.outfit_for_key(key)
	var base:="hero/"+outfit.stem if outfit!=null else key
	return _scene_paths.get(base,"")

static func has_actor(key: String) -> bool:
	if HeroAppearance.is_key(key): return true
	_prepare_index()
	return _index.has(key)

static func actor_info(key: String) -> Dictionary:
	# Metadata and SpriteFrames are separate caches: battle preparation may read
	# only the requested metadata before loading its texture asynchronously.
	_sync_edits()
	if catalog.has(key): return catalog[key]
	var composition:=HeroAppearance.composition_key(key)
	if not composition.is_empty():
		var base := _native_info("hero/"+HeroAppearance.outfit_for_key(key).stem)
		var prepared := HeroAppearance.build(composition,base)
		if prepared.is_empty(): return {}
		catalog[key] = prepared.info
		return prepared.info
	var outfit:=HeroAppearance.outfit_for_key(key)
	_prepare_index()
	var native_key:="hero/"+outfit.stem if outfit!=null and not _index.has(key) else key
	var info:=_native_info(native_key)
	if not info.is_empty(): catalog[key]=info
	return info

static func _native_info(key: String) -> Dictionary:
	if _native_catalog.has(key): return _native_catalog[key]
	_prepare_index()
	if not _index.has(key): return {}
	var path: Variant = _index[key]
	if not path is String or path != "res://assets/actor_resources/" + key + ".tres": return {}
	var definition:=load(path) as NativeActorDefinition
	if definition==null:return {}
	_record_metadata(path)
	var info:=definition.to_info()
	if not _valid_info(info): return {}
	_native_catalog[key] = info
	return info

static func _sync_edits() -> void:
	AppearanceEdits.ensure_loaded()
	if _edit_revision==AppearanceEdits.revision and _appearance_revision==AppearanceResources.revision: return
	_edit_revision=AppearanceEdits.revision;_appearance_revision=AppearanceResources.revision
	# Invalidate strong AND weak sprite-frame caches, including native hero aliases.
	for key in catalog.keys():
		if key.begins_with("hero/") or key.begins_with("creation/"): catalog.erase(key)
	for key in cached.keys():
		if key.begins_with("hero/") or key.begins_with("creation/"): cached.erase(key)
	_dynamic_weak.clear();_dynamic_order.clear()

static func metadata_stats() -> Dictionary:
	return {"indexed_actors": _index.size(), "loaded_actors": catalog.size(), "sprite_frames": cached.size(), "json_files_read":0,"json_bytes_read":0,"resource_files_loaded":_metadata_reads,"resource_bytes":_metadata_bytes,"scene_loads":_scene_loads,"cached_scenes":_loaded_scenes.size()}

static func is_prepared(key:String)->bool:
	_sync_edits()
	return cached.has(key) and _loaded_scenes.has(scene_path(key))

static func _scene(path:String)->PackedScene:
	if path.is_empty():return null
	if not _loaded_scenes.has(path):
		var packed:=load(path) as PackedScene
		if packed==null:return null
		_loaded_scenes[path]=packed;_scene_loads+=1
	_scene_order.erase(path);_scene_order.append(path)
	while _scene_order.size()>MAX_SCENES:_loaded_scenes.erase(_scene_order.pop_front())
	return _loaded_scenes[path]

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
	var info := actor_info(key)
	if info.is_empty():
		push_error("Missing original actor: " + key)
		return ACTOR_SCENE.instantiate()
	var path:=scene_path(key)
	var scene:=_scene(path)
	if scene==null:
		push_error("Missing native actor scene: "+key)
		return ACTOR_SCENE.instantiate()
	var sprite:NativeActorSprite=scene.instantiate()
	# Direct scene previews autoplay. The game factory owns playback instead:
	# callers may pause before entering the tree (hit tests, battle sampling).
	sprite.autoplay=""
	sprite.art_key=key;sprite.initialize()
	var composition:=HeroAppearance.composition_key(key)
	if composition.is_empty():
		# Static actors are authored SpriteFrames, not reconstructed JSON animations.
		cached[key]=sprite.sprite_frames
	else:
		if not cached.has(key) and _dynamic_weak.has(key):
			var previous:SpriteFrames=_dynamic_weak[key].get_ref()
			if previous!=null:cached[key]=previous
		if not cached.has(key):
			var prepared:=HeroAppearance.build(composition,_native_info("hero/"+HeroAppearance.outfit_for_key(key).stem))
			cached[key]=_composed_frames(info,prepared.texture)
		sprite.sprite_frames=cached[key]
		sprite.offset=Vector2(info.origin[0]-info.get("anchor_x",0),info.origin[1])
		_dynamic_weak[key]=weakref(cached[key])
		_dynamic_order.erase(key);_dynamic_order.append(key)
		while _dynamic_order.size()>6:cached.erase(_dynamic_order.pop_front())
	sprite.set_meta("appearance_edit_revision",AppearanceEdits.revision)
	if key.begins_with("hero/"):sprite.set_meta("ground_pose_x",info.get("native_battle",{}).get("pose_x",{}))
	if sprite is NativeHeroSprite:sprite.configure(HeroAppearance.outfit_for_key(key),sprite.sprite_frames,info,key)
	sprite.play("idle")
	return sprite

static func _composed_frames(info:Dictionary,texture:Texture2D) -> SpriteFrames:
	return HeroAppearance.sprite_frames(info,texture)

static func battle_actor(key: String) -> AnimatedSprite2D:
	var sprite := actor(key)
	sprite.set_meta("native_ground_anchor", true)
	var base_offset := sprite.offset
	var offsets: Dictionary = actor_info(key).get("native_battle", {}).get("pose_x", {})
	# Gameplay atlases stabilize the body/head for walking. Battle rendering
	# must restore the source idle anchor and state-6 recoil at every frame.
	# Attack translation is owned by BattleActionPlayback instead.
	var sample := func() -> void:
		var poses: Array = offsets.get(String(sprite.animation), [])
		sprite.offset = base_offset + Vector2(float(poses[sprite.frame]) if sprite.frame < poses.size() else 0.0, 0.0)
	sprite.animation_changed.connect(sample)
	sprite.frame_changed.connect(sample)
	sample.call()
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

static func apply_appearance(sprite: AnimatedSprite2D, key: String) -> void:
	if sprite.get_meta("art_key", "") == key and int(sprite.get_meta("appearance_edit_revision",-1))==AppearanceEdits.revision: return
	var replacement := actor(key)
	var animation := sprite.animation
	var frame := sprite.frame
	sprite.sprite_frames = replacement.sprite_frames
	sprite.offset = replacement.offset
	sprite.set_meta("art_key",key)
	if sprite is NativeActorSprite:
		sprite.art_key=key;sprite.definition=replacement.definition
	if sprite is NativeHeroSprite and replacement is NativeHeroSprite:
		sprite.actor_stem=replacement.actor_stem;sprite.base_frames=replacement.base_frames
		sprite.configure(replacement.outfit,replacement.sprite_frames,actor_info(key),key)
	sprite.set_meta("appearance_edit_revision",AppearanceEdits.revision)
	sprite.set_meta("ground_pose_x",replacement.get_meta("ground_pose_x",{}))
	sprite.play(animation if sprite.sprite_frames.has_animation(animation) else &"idle")
	sprite.frame = mini(frame,sprite.sprite_frames.get_frame_count(sprite.animation)-1)
	replacement.free()
