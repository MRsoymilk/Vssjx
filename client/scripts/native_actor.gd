@tool
class_name NativeActorSprite
extends AnimatedSprite2D
## Also works when a catalog scene is opened/instantiated without OriginalArt.
@export var definition: NativeActorDefinition
@export var art_key := ""

func initialize() -> void:
	set_meta("art_key",art_key)
	if definition!=null and art_key.begins_with("hero/") and not has_meta("ground_pose_x"):
		set_meta("ground_pose_x",definition.native_battle.get("pose_x",{}))
	if not animation_finished.is_connected(_return_to_idle): animation_finished.connect(_return_to_idle)

func _ready() -> void:
	initialize()

func _return_to_idle() -> void:
	if animation in ["attack","cast","hurt"] and sprite_frames.has_animation("idle"): play("idle")
