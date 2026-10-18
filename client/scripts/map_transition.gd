class_name OriginalMapTransition
extends Control
## Native video 422.600–423.000: blue tip page, walking hero, green loading strip.
signal finished
const MIN_DURATION := 0.45
var progress := 0.0
var blocking := false
var _elapsed := 0.0
var _completed_at := -1.0
var _display_progress := 0.0
var _fully_shown_at := -1.0
var runner: AnimatedSprite2D
@onready var tip: Label = $Tip

func begin(art: String) -> void:
	if blocking: return # A replay/reconnect continues the same journey.
	blocking = true
	progress = 0.0
	_elapsed = 0.0
	_completed_at = -1.0
	_display_progress = 0.0
	_fully_shown_at = -1.0
	if runner != null:
		remove_child(runner)
		runner.queue_free()
	runner = OriginalArt.actor(art)
	runner.scale.x = -1.0 # Source characters face left; the loading strip fills right.
	add_child(runner)
	runner.play("walk")
	runner.position = Vector2(32, 400)
	tip.text = "点击底部聊天框，可打开“聊天”界面，\n与蜀山的其他玩家对话交流。"
	show()
	set_progress(0.06)

func set_progress(value: float) -> void:
	if not blocking: return
	progress = maxf(progress, clampf(value, 0.0, 1.0))
	queue_redraw()

func complete() -> void:
	if not blocking or _completed_at >= 0.0: return
	set_progress(1.0)
	_completed_at = _elapsed

func cancel() -> void:
	if not blocking: return
	blocking = false
	hide()
	if runner != null: runner.pause()
	finished.emit()

func _process(delta: float) -> void:
	if not blocking: return
	_elapsed += delta
	# Smooth only confirmed stages; elapsed time never advances the load target.
	_display_progress = move_toward(_display_progress, progress, delta * 3.0)
	if runner != null: runner.position = Vector2(roundf(32.0 + 256.0 * _display_progress), 400)
	queue_redraw()
	if _completed_at >= 0.0 and _display_progress >= 1.0 and _fully_shown_at < 0.0: _fully_shown_at = _elapsed
	# Keep the fully loaded page for a rendered frame, even after a slow request.
	if _fully_shown_at >= 0.0 and _elapsed >= MIN_DURATION and _elapsed - _fully_shown_at >= 0.10:
		cancel()

func _input(event: InputEvent) -> void:
	if blocking and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag):
		get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 480), Color("247ba1"))
	draw_rect(Rect2(0, 80, 320, 200), Color("1b4f70"))
	draw_rect(Rect2(0, 402, 320, 14), Color("175174"))
	draw_rect(Rect2(0, 402, roundf(320 * _display_progress), 14), Color("b5f500"))
