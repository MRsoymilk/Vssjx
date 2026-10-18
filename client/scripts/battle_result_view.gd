class_name BattleResultView
extends Control
## Original ANI glyphs over the battlefield; settlement remains owned by the caller.
signal finished
const ART_KEYS: Array[String] = ["main/ltz_win", "main/ltz_lose"]
const DISPLAY_SECONDS := 1.6
const MINIMUM_SECONDS := 0.4
var glyph: AnimatedSprite2D
var elapsed := 0.0
var outcome := ""
var manual_clock := false
var paused := false
var automatic_return := true
var _completed := false

func present(value: String, details: String = "", auto_return: bool = true) -> void:
	if outcome == value:
		show()
		return
	if is_instance_valid(glyph):
		remove_child(glyph)
		glyph.queue_free()
	glyph = null
	outcome = value
	elapsed = 0.0
	_completed = false
	automatic_return = auto_return
	$Title.text = "撤退" if value == "fled" else ""
	$Body.text = details
	$Body.visible = not auto_return
	if value in ["victory", "defeat"]:
		glyph = OriginalArt.actor(ART_KEYS[0 if value == "victory" else 1])
		# Preserve both native layer offsets and sequence durations; no new tween.
		glyph.position = Vector2(160, 183)
		add_child(glyph)
		glyph.play("source_0")
	show()
	$Return.disabled = true

func reset() -> void:
	hide()
	outcome = ""
	elapsed = 0.0
	_completed = false
	if is_instance_valid(glyph):
		remove_child(glyph)
		glyph.queue_free()
	glyph = null

func can_return() -> bool:
	return visible and not paused and not outcome.is_empty() and elapsed >= MINIMUM_SECONDS

func advance(delta: float) -> void:
	if not visible or paused or _completed: return
	elapsed += maxf(0.0, delta)
	$Return.disabled = not can_return()
	if automatic_return and elapsed >= DISPLAY_SECONDS:
		_completed = true
		finished.emit()

func _process(delta: float) -> void:
	if not manual_clock: advance(delta)
