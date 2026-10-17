class_name BattleEffects
extends Node2D
## One-shot original ANI effects, attached by canvas position without inheriting facing.
## Job fallback is reconstructed: original per-skill effect bindings remain unknown.
const SKILL_ART := ["effect/t71", "effect/t36", "effect/t47"]
var _attachments:Array[Dictionary]=[]

func _init()->void:
	# BattleActionPlayback advances in its owning view first.
	process_priority=10

func play_action(command:String,job:int,skill_id:String,hero:AnimatedSprite2D,enemy:AnimatedSprite2D)->AnimatedSprite2D:
	if command not in ["attack","skill"]:return null
	var skill:=SkillRules.item(skill_id)
	var support:=command=="skill" and not skill.is_empty() and int(skill.damage_percent)==0
	return attach(SKILL_ART[clampi(job,0,2)] if command=="skill" else "effect/flash",hero if support else enemy)

func attach(key:String,subject:Node2D)->AnimatedSprite2D:
	if not is_instance_valid(subject) or not subject.is_inside_tree() or subject.is_queued_for_deletion():return null
	var sprite:=OriginalArt.effect(key)
	sprite.name="AttachedEffect"
	sprite.set_meta("subject_id",subject.get_instance_id())
	add_child(sprite)
	_attachments.append({"sprite":sprite,"subject":weakref(subject)})
	_follow(sprite,subject)
	return sprite

func _follow(sprite:AnimatedSprite2D,subject:Node2D)->void:
	# Both views can have translated/scaled HUD and actor station parents.
	# Preserve the ANI origin and upright pixels; reflected actors must not flip FX.
	sprite.position=get_global_transform_with_canvas().affine_inverse()*subject.get_global_transform_with_canvas().origin

func _process(_delta:float)->void:
	for index in range(_attachments.size()-1,-1,-1):
		var entry:Dictionary=_attachments[index]
		var sprite:AnimatedSprite2D=entry.sprite
		var subject:Node2D=entry.subject.get_ref()
		if not is_instance_valid(sprite) or sprite.is_queued_for_deletion():
			_attachments.remove_at(index)
		elif not is_instance_valid(subject) or subject.is_queued_for_deletion() or not subject.is_inside_tree() or not subject.visible:
			sprite.hide();sprite.queue_free();_attachments.remove_at(index)
		else:_follow(sprite,subject)

func clear()->void:
	for entry in _attachments:
		if is_instance_valid(entry.sprite):entry.sprite.hide();entry.sprite.queue_free()
	_attachments.clear()
