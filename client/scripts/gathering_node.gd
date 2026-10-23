class_name GatheringNode
extends Node2D
## Authored pixel resource markers, not claimed as recovered original artwork.
var data:Dictionary={}
var remaining:=0
var label:Label
var local_mode:=false
func _ready()->void:
	label=OriginalSceneChrome.label(self,"",Rect2(-50,-43,100,18),10,Color("c2f7f4"))
	preload("res://scripts/world_nameplate.gd").apply(label,Color("c2f7f4"))
func display(value:Dictionary,now:int)->void:
	data=value;position=Vector2(int(data.cell[0])*16+8,int(data.cell[1])*16+8)
	remaining=maxi(0,ceili((int(data.get("available_at_ms",0))-now)/1000.0))
	if label!=null:label.text=GatheringRules.MATERIALS.get(data.material,"采集点")+(" · %ds"%remaining if remaining>0 else " · 可采集")
	queue_redraw()
func _draw()->void:
	if data.is_empty():return
	var faded:=remaining>0
	if GatheringRules.kind(data.material)=="ore":
		draw_rect(Rect2(-12,-8,24,9),Color("645d55"));draw_rect(Rect2(-9,-17,17,11),Color("858780"))
		draw_rect(Rect2(-6,-23,7,15),Color("615b51") if faded else Color("94c7d8"));draw_rect(Rect2(2,-19,6,13),Color("615b51") if faded else Color("d6b277"))
		draw_line(Vector2(-5,-22),Vector2(-5,-13),Color("efe9bd"),2)
	else:
		draw_rect(Rect2(-2,-21,4,22),Color("6b694a") if faded else Color("507d32"))
		for i in 3:
			var y:=-7-i*6
			draw_rect(Rect2(-9,y-3,8,4),Color("74714e") if faded else Color("67b34b"));draw_rect(Rect2(2,y-6,8,4),Color("74714e") if faded else Color("8ad363"))
		draw_rect(Rect2(-2,-26,4,5),Color("86715a") if faded else Color("f0d095"))
func hit(point:Vector2)->bool:return Rect2(position-Vector2(15,30),Vector2(30,34)).has_point(point)
func _process(_delta:float)->void:
	if local_mode and not data.is_empty():
		data.available_at_ms=int(Game.player.get("gathering",{}).get("respawns",{}).get(data.id,0));display(data,int(Time.get_unix_time_from_system()*1000))
