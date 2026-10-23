class_name GatheringPanel
extends Control
signal start_requested
signal cancel_requested
var node:Dictionary={}
var progress:ProgressBar
var hero_point:Callable
var local_mode:=false
var auto_finished:=false
func _ready()->void:
	mouse_filter=MOUSE_FILTER_IGNORE;z_index=18;process_priority=20
	progress=OriginalSceneChrome.progress(self,Rect2(0,0,48,6),Color("40b5a0"));progress.max_value=1
	progress.mouse_filter=MOUSE_FILTER_IGNORE
	hide()
func present(value:Dictionary)->void:node=value.duplicate(true);progress.value=0;auto_finished=false;show()
func display(model:OnlinePve)->void:
	if node.is_empty():return
	var active:=GatheringRules.active(model)
	if not active.is_empty() and active.node_id==node.id:
		var left:=maxi(0,int(active.ready_at_ms)-model.server_time_ms())
		progress.value=clampf(1.0-float(left)/float(active.duration_ms),0,1)

func _process(_delta:float)->void:
	if visible and hero_point.is_valid():position=hero_point.call()+Vector2(-24,-86)
	if not local_mode or not visible or node.is_empty():return
	if not Game.storage_busy and movement_pressed():cancel_requested.emit();return
	var active:Dictionary=Game.local_gather
	if active.is_empty():
		hide()
	else:
		var left:=maxi(0,int(node.duration_ms)-(Time.get_ticks_msec()-int(active.started)))
		progress.value=clampf(1.0-float(left)/int(node.duration_ms),0,1)
		if left==0 and not auto_finished and not Game.storage_busy:auto_finished=true;start_requested.emit()
static func movement_pressed()->bool:
	return [KEY_W,KEY_A,KEY_S,KEY_D,KEY_UP,KEY_LEFT,KEY_DOWN,KEY_RIGHT].any(func(key:int)->bool:return Input.is_physical_key_pressed(key))
func _unhandled_key_input(event:InputEvent)->void:
	if local_mode and visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:cancel_requested.emit();get_viewport().set_input_as_handled()
