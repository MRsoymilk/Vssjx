extends CanvasLayer
var _pulse:Tween
func pulse()->void:
	if _pulse!=null:_pulse.kill()
	$Veil.show();$Veil.color.a=0.45
	_pulse=create_tween()
	_pulse.tween_property($Veil,"color:a",0.0,0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse.tween_callback($Veil.hide)
func clear()->void:
	if _pulse!=null:_pulse.kill()
	$Veil.hide();$Veil.color.a=0
