extends Node2D

var elapsed := 0.0

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var alpha := 0.65 + sin(elapsed * 2.0) * 0.2
	draw_circle(Vector2(0, -18), 13, Color(0.4, 0.87, 1.0, 0.24))
	draw_arc(Vector2(0, -18), 18, 0, TAU, 32, Color(0.6, 0.96, 1.0, alpha), 2)
	draw_arc(Vector2(0, -18), 11, elapsed, elapsed + PI * 1.5, 24, Color("b3f4f1"), 1)
	draw_line(Vector2(-20, 1), Vector2(20, 1), Color("7cc7bd"), 2)
