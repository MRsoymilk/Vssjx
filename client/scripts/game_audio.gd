class_name GameAudio
extends RefCounted
## Shared game/asset-browser registry. No account or gameplay state is modified.
const PATH := "res://assets/data/audio-v1.json"
const PLAYER := preload("res://scenes/skill_sound.tscn")
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
static var sound_enabled := true
static var settings_initialized := false
static var settings_error := ""

static func initialize_settings() -> void:
	if settings_initialized or not Platform.is_available(): return
	settings_initialized = true
	var result := Platform.context.runtime_config.load_sound_enabled()
	sound_enabled = result.value if result.ok and result.value is bool else true
	settings_error = "" if result.ok else result.message
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not sound_enabled)

static func set_sound_enabled(enabled: bool) -> PlatformResult:
	initialize_settings()
	sound_enabled = enabled
	# Muting the bus silences even sounds already playing, without losing music position.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), not enabled)
	var result := Platform.context.runtime_config.save_sound_enabled(enabled) if Platform.is_available() else PlatformResult.unsupported()
	settings_error = "" if result.ok else result.message
	return result

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
