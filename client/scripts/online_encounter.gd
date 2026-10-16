class_name OnlineEncounter
extends BattleEncounterTransition
## The local encounter visual, without another confirmation dialog.
## An indeterminate segment means server acknowledgement, never a percentage.
var waiting := false
var _phase := 0.0

func present(action: String, resident_name: String, hero_point: Vector2) -> void:
	if action != "challenge":
		hide()
		return
	progress = 0.0
	configure(resident_name, hero_point)
	set_waiting("等待服务器确认……")
	show()

func set_waiting(text_value: String) -> void:
	waiting = true
	progress = 0.0
	detail.text = text_value
	queue_redraw()

func set_progress(value: float, text_value: String) -> void:
	waiting = false
	super.set_progress(value, text_value)

func _process(delta: float) -> void:
	if visible and waiting:
		_phase = fposmod(_phase + delta * 0.8, 1.0)
		queue_redraw()

func _draw() -> void:
	super._draw()
	if not waiting: return
	var track := BAR_RECT.grow(-6)
	var width := 30.0
	var offset := floorf((track.size.x - width) * (1.0 - absf(_phase * 2.0 - 1.0)))
	draw_rect(Rect2(track.position + Vector2(offset, 0), Vector2(width, track.size.y)), Color("49b9d1"))
