extends Node2D
var amount := 0
var critical := false

func present(value:int,is_critical:bool=false,healed:bool=false)->void:
	amount=value;critical=is_critical and not healed
	$Number.text=("+" if healed else "-")+str(value)
	$Number.add_theme_font_size_override("font_size",23 if critical else 19)
	if healed:$Number.add_theme_color_override("font_color",Color("69ee66"))
	$Critical.visible=critical;$Burst.visible=critical
	scale=Vector2.ONE*0.75
	var pop:=create_tween()
	pop.tween_property(self,"scale",Vector2.ONE*(1.15 if critical else 1.0),0.09)
	pop.tween_property(self,"scale",Vector2.ONE,0.10)
	var lifetime:=create_tween()
	lifetime.tween_property(self,"position:y",position.y-19,0.8)
	lifetime.parallel().tween_property(self,"modulate:a",0.0,0.3).set_delay(0.5)
	lifetime.tween_callback(queue_free)
	if critical:
		var flash:=create_tween()
		flash.tween_property($Burst,"modulate:a",0.0,0.18)
