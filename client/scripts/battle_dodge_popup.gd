extends Node2D
## Theme-colored, outlined CJK text; no hit number or critical screen flash.
func present()->void:
	var rise:=create_tween()
	rise.tween_property(self,"position:y",position.y-16,0.65)
	rise.parallel().tween_property(self,"modulate:a",0.0,0.20).set_delay(0.45)
	rise.tween_callback(queue_free)
