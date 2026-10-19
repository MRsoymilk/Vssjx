class_name GameAudio
extends RefCounted
## Shared game/asset-browser registry. No account or gameplay state is modified.
const PATH := "res://assets/data/audio-v1.json"
const PLAYER := preload("res://scenes/skill_sound.tscn")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))

static func item(id: String) -> Dictionary:
	for entry in catalog.items:
		if entry.id == id: return entry
	return {}

static func stream(id: String) -> AudioStream:
	var entry := item(id)
	return load(entry.path) as AudioStream if not entry.is_empty() else null

static func player(id: String) -> AudioStreamPlayer:
	var audio := stream(id)
	if audio == null: return null
	var result: AudioStreamPlayer = PLAYER.instantiate()
	result.stream = audio
	result.volume_db = float(item(id).volume_db)
	result.set_meta("audio_id",id)
	return result
