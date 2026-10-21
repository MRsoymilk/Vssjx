extends Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)

func timings(values: Array) -> Dictionary:
	values.sort()
	return {"samples": values.size(), "p50_us": values[values.size() / 2], "p95_us": values[mini(values.size() - 1, ceili(values.size() * 0.95) - 1)]}

func _ready() -> void:
	var offline := Game.player.duplicate(true)
	check(OriginalArt.catalog.is_empty() and OriginalArt.cached.is_empty(), "No metadata or textures loaded by registering the art class")
	var cold_started := Time.get_ticks_usec()
	var info := OriginalArt.actor_info("hero/mfs")
	var cold_us := Time.get_ticks_usec() - cold_started
	var first := OriginalArt.metadata_stats()
	var expected_count:int=(load(OriginalArt.INDEX_PATH) as NativeActorCatalog).definitions.size()
	check(first.indexed_actors == expected_count and first.loaded_actors == 1 and first.resource_files_loaded == 2 and first.json_files_read==0, "First lookup loads only native index and requested lightweight Resource, no JSON")
	var expected_bytes:=FileAccess.get_file_as_bytes(OriginalArt.INDEX_PATH).size()+FileAccess.get_file_as_bytes("res://assets/actor_resources/hero/mfs.tres").size()
	check(first.resource_bytes == expected_bytes and first.json_bytes_read == 0, "Native metadata loading does not read legacy JSON or load textures")
	check(not OriginalArt.catalog.has("hero/wfs") and not OriginalArt.catalog.has("creation/mfs") and not OriginalArt.catalog.has("effect/t47"), "Unrequested categories remain unloaded")
	check(info.playback.has("cast") and not info.sequences.is_empty() and OriginalArt.cached.is_empty(), "Metadata lookup retains all sequences without building SpriteFrames")
	var warm_started := Time.get_ticks_usec()
	for _lookup in 1000: OriginalArt.actor_info("hero/mfs")
	var warm_us := Time.get_ticks_usec() - warm_started
	check(OriginalArt.metadata_stats() == first, "1000 cached lookups perform no additional file IO")
	check(OriginalArt.has_actor("monster/langw") and OriginalArt.metadata_stats() == first, "Index membership does not eagerly load metadata")
	check(OriginalArt.actor_info("hero/unknown").is_empty() and OriginalArt.metadata_stats() == first, "Unknown actor does not read arbitrary paths")
	var actor := OriginalArt.actor("hero/mfs")
	var second := OriginalArt.actor("hero/mfs")
	check(actor.sprite_frames == second.sprite_frames and actor.sprite_frames == OriginalArt.cached["hero/mfs"], "SpriteFrames cache is still shared")
	check(OriginalArt.metadata_stats().resource_files_loaded == 2 and actor is NativeActorSprite and actor.scene_file_path==OriginalArt.scene_path("hero/mfs"), "Native PackedScene instantiation reuses lightweight metadata and authored SpriteFrames")
	check(actor.sprite_frames.has_animation("cast") and not actor.sprite_frames.get_animation_loop("cast") and not actor.sprite_frames.get_animation_loop("attack"), "Mage one-shot modes preserved")
	check(actor.sprite_frames.get_frame_count("walk") == 6 and actor.sprite_frames.has_animation("source_0"), "Native walking and original numbered sequences preserved")
	var first_actor_stats := OriginalArt.metadata_stats()
	check(OriginalArt.actor_info("effect/t47").texture.ends_with("effect_t47.png") and not OriginalArt.cached.has("effect/t47"), "Battle effect metadata is independently prepared before its texture")
	var effect := OriginalArt.effect("effect/t47")
	check(not effect.sprite_frames.get_animation_loop(effect.animation), "Native sequence zero effect remains a one-shot")
	for key in OriginalArt._index:
		check(not OriginalArt.actor_info(key).is_empty(), "Every indexed shard passes validation: " + key)
	check(OriginalArt.catalog.size() == expected_count and OriginalArt.cached.size() == 2, "Enumerating metadata does not allocate all actor textures/frames")
	check(not FileAccess.file_exists("res://assets/data/%s.json" % "original_animations"), "Original ANI archive is no longer a runtime resource")
	check(Game.player == offline, "Asset metadata never mutates offline state")
	var all_stats := OriginalArt.metadata_stats()
	actor.free()
	second.free()
	effect.free()
	var benchmark: Dictionary = {}
	var legacy := OS.get_environment("SSJX_ACTOR_CATALOG_LEGACY")
	if not legacy.is_empty():
		var monolithic: Array = []
		var split: Array = []
		for _sample in 31:
			var started := Time.get_ticks_usec()
			var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(legacy))
			monolithic.append(Time.get_ticks_usec() - started)
			check(old is Dictionary and old.size() == 33, "Benchmark baseline contains all legacy metadata")
			OriginalArt.catalog.clear()
			OriginalArt._index={};OriginalArt._native_catalog={};OriginalArt._scene_paths={}
			OriginalArt._index_loaded = false
			started = Time.get_ticks_usec()
			OriginalArt.actor_info("hero/mfs")
			split.append(Time.get_ticks_usec() - started)
		benchmark = {"os_cache": "warm; application catalog cold; metadata only, no texture loading", "legacy_monolith": timings(monolithic), "split_first_actor": timings(split)}
	var output := OS.get_environment("SSJX_ACTOR_CATALOG_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cold_metadata_us": cold_us, "warm_1000_metadata_us": warm_us, "first_metadata": first, "first_actor": first_actor_stats, "all_metadata": all_stats, "benchmark": benchmark}, "  "))
	print("ACTOR CATALOG: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
