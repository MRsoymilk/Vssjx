class_name WorldDayNight
extends CanvasModulate
## Presentation only, attached inside the map viewport, never the HUD canvas.
## Unix even hours are day, odd hours night; the last minute fades to the next.
const PHASE_SECONDS := 3600.0
const FADE_SECONDS := 60.0
const CYCLE_SECONDS := PHASE_SECONDS * 2.0
const DAY := Color.WHITE
const NIGHT := Color(0.62, 0.69, 0.84, 1.0)
# These underground maps do not use the cave biome in the existing catalog.
const FIXED_LIGHT_MAPS := ["ai_047", "ai_087", "ai_101", "ai_109"]
var time_source: Callable = Time.get_unix_time_from_system
var cycle_enabled := true

static func uses_cycle(data: Dictionary) -> bool:
	if data.has("day_night_enabled"): return data.day_night_enabled == true
	return data.get("biome", "") != "cave" and data.get("map_id", "") not in FIXED_LIGHT_MAPS

static func night_weight(unix_seconds: float) -> float:
	# Missing online time stays bright rather than trusting the player's clock.
	if not is_finite(unix_seconds) or unix_seconds < 0.0: return 0.0
	var phase := fposmod(unix_seconds, CYCLE_SECONDS)
	if phase < PHASE_SECONDS - FADE_SECONDS: return 0.0
	if phase < PHASE_SECONDS: return smoothstep(PHASE_SECONDS - FADE_SECONDS, PHASE_SECONDS, phase)
	if phase < CYCLE_SECONDS - FADE_SECONDS: return 1.0
	return 1.0 - smoothstep(CYCLE_SECONDS - FADE_SECONDS, CYCLE_SECONDS, phase)

static func tint_at(unix_seconds: float) -> Color:
	return DAY.lerp(NIGHT, night_weight(unix_seconds))

func set_map(data: Dictionary) -> void:
	cycle_enabled = uses_cycle(data)
	refresh()

func refresh() -> void:
	var next_color := tint_at(float(time_source.call())) if cycle_enabled and time_source.is_valid() else DAY
	if color != next_color: color = next_color

func _ready() -> void:
	refresh()

func _process(_delta: float) -> void:
	# Sample absolute time, not accumulated delta: hidden tabs and scene reloads
	# immediately resume the correct phase without replaying missed transitions.
	refresh()
