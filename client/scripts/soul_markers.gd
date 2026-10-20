class_name SoulMarkers
extends Node2D
## Native final death frame as a persistent private gravestone; one map spawn marker.
var map_id := "qingyun_trail"
var corpse: Dictionary = {}
var grave: AnimatedSprite2D
@onready var spawn_marker: Node2D = $ResurrectionPoint

func _ready() -> void:
	grave=OriginalArt.actor("main/death")
	grave.name="Corpse"
	add_child(grave)
	grave.animation="source_0"
	grave.pause()
	grave.frame=grave.sprite_frames.get_frame_count("source_0")-1
	var tag:=Label.new()
	tag.text="你的尸体 · 靠近交互复活"
	tag.position.y=-28
	preload("res://scripts/world_nameplate.gd").apply(tag,Color("dce8df"))
	grave.add_child(tag)
	display(map_id,corpse)

func display(id: String, value: Dictionary = {}) -> void:
	map_id=id;corpse=value.duplicate(true)
	if not is_node_ready():return
	spawn_marker.position=Vector2(SoulRules.resurrection_point(id)*16)+Vector2(8,8)
	grave.visible=not corpse.is_empty() and corpse.get("map_id")==id
	if grave.visible:grave.position=Vector2(int(corpse.cell[0])*16+8,int(corpse.cell[1])*16+8)

func target() -> Dictionary:
	if corpse.is_empty() or corpse.map_id!=map_id:return {}
	return {"kind":"corpse","cell":Vector2i(corpse.cell[0],corpse.cell[1]),"data":corpse}

func hit(point: Vector2) -> bool:
	return grave!=null and grave.visible and Rect2(grave.position-Vector2(16,28),Vector2(32,36)).has_point(point)
