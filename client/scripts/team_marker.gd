extends Sprite2D
## Recovered sceneui.imgs frames 19/20/21. Keep original pixels and transparency.
const LEADER=preload("res://assets/ui/team_leader.png")
const MEMBER=preload("res://assets/ui/team_member.png")
const AWAY=preload("res://assets/ui/team_away.png")
func _init()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	position=Vector2(-20,-67)
	z_index=5
	visible=false
func update_state(state:Dictionary)->void:
	visible=not state.is_empty()
	if visible:texture=LEADER if state.get("leader",false) else MEMBER if state.get("following",false) else AWAY
