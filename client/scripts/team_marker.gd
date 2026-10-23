extends Sprite2D
## Recovered flags with a shared readiness palette for world markers and team cards.
const LEADER=preload("res://assets/ui/team_leader.png")
const MEMBER=preload("res://assets/ui/team_member.png")
const AWAY=preload("res://assets/ui/team_away.png")
static func prepared(state:Dictionary)->bool:
	return state.get("leader",false) or (state.get("following",true) and state.get("ready",true))
static func texture_for(state:Dictionary)->Texture2D:
	return LEADER if state.get("leader",false) else MEMBER if prepared(state) else AWAY
static func material_for(state:Dictionary)->Material:
	return null
func _init()->void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	position=Vector2(-20,-67)
	z_index=5
	visible=false
func update_state(state:Dictionary)->void:
	visible=not state.is_empty()
	if visible:
		texture=texture_for(state)
		material=material_for(state)
