@tool
class_name NativeHeroSprite
extends NativeActorSprite
## One scene per sex/job. Outfit Resources drive both editor and runtime previews.
@export var base_frames:SpriteFrames
@export_storage var actor_stem:=""
@export var outfit:NativeHeroOutfit:
	set(value):
		if outfit!=null and outfit.changed.is_connected(_outfit_changed):outfit.changed.disconnect(_outfit_changed)
		outfit=value
		if outfit!=null and not outfit.changed.is_connected(_outfit_changed):outfit.changed.connect(_outfit_changed)
		_configured=false
		if is_node_ready() and not _applying:_refresh_outfit()
var _configured:=false
var _applying:=false
func _ready()->void:
	super._ready()
	if not _configured:_refresh_outfit()
func _outfit_changed()->void:
	AppearanceResources.invalidate()
	_configured=false
	if is_node_ready():_refresh_outfit()
func configure(value:NativeHeroOutfit,frames:SpriteFrames,info:Dictionary,key:String)->void:
	_applying=true;outfit=value;_applying=false
	art_key=key;sprite_frames=frames
	offset=Vector2(info.origin[0]-info.get("anchor_x",0),info.origin[1])
	set_meta("art_key",key);set_meta("ground_pose_x",info.get("native_battle",{}).get("pose_x",{}))
	set_meta("appearance_edit_revision",AppearanceEdits.revision);_configured=true
func _refresh_outfit()->void:
	update_configuration_warnings()
	if outfit==null or not outfit.valid() or definition==null or outfit.stem!=actor_stem:return
	var mode:=animation;var old_frame:=frame;var playing:=is_playing()
	var info:=definition.to_info();var frames:=base_frames
	if not outfit.uses_baked():
		var built:=HeroAppearance.build_outfit(outfit,info)
		if built.is_empty():return
		info=built.info;frames=HeroAppearance.sprite_frames(info,built.texture)
	var key:="hero/"+outfit.stem if outfit.codes()==[1,0,0] else outfit.key()
	configure(outfit,frames,info,key)
	play(mode if frames.has_animation(mode) else &"idle");frame=mini(old_frame,frames.get_frame_count(animation)-1)
	if not playing:pause()
func _get_configuration_warnings()->PackedStringArray:
	return PackedStringArray(["请选择与本人物性别／职业一致的武器、衣服、头饰及动作配方Resource。"] if outfit==null or not outfit.valid() or outfit.stem!=actor_stem or (definition!=null and outfit.recipe.frames.size()!=definition.frame_count) else [])
