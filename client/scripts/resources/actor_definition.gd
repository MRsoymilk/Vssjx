@tool
class_name NativeActorDefinition
extends Resource
## Lightweight motion/source metadata. Loading this resource never loads the atlas.
@export_file("*.png") var texture_path := ""
@export var frame_size := Vector2i.ONE
@export var columns := 1
@export var frame_count := 1
@export var origin := Vector2i.ZERO
@export var anchor_x := 0
@export var sequences: Array = []
@export var playback: Dictionary = {}
@export var native_battle: Dictionary = {}
@export var extra: Dictionary = {}

func to_info() -> Dictionary:
	var info := {"texture":texture_path,"width":frame_size.x,"height":frame_size.y,"columns":columns,"count":frame_count,"origin":[origin.x,origin.y],"anchor_x":anchor_x,"sequences":sequences.duplicate(true),"playback":playback.duplicate(true)}
	if not native_battle.is_empty(): info.native_battle=native_battle.duplicate(true)
	info.merge(extra.duplicate(true))
	return info
