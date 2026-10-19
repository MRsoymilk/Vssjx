class_name BattleEffects
extends Node2D
## One-shot original ANI effects, attached by canvas position without inheriting facing.
## Bindings are authored from each skill's meaning, using original ANI artwork.
static var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/skill-effects-v1.json"))
var _attachments:Array[Dictionary]=[]
var _sounds:Array[AudioStreamPlayer]=[]
signal audio_played(id:String)

func _init()->void:
	# BattleActionPlayback advances in its owning view first.
	process_priority=10

func play_action(command:String,job:int,skill_id:String,hero:AnimatedSprite2D,enemy:AnimatedSprite2D)->AnimatedSprite2D:
	if command not in ["attack","skill"]:return null
	if command=="attack":return attach("effect/flash",enemy)
	# Old servers omit the selected ID; resolve their known legacy skill explicitly.
	var id:=skill_id if not skill_id.is_empty() else "legacy_%d"%clampi(job,0,2)
	return play_binding(id,"cast_impact",hero,enemy)

static func binding(id:String)->Dictionary:
	return catalog.bindings.get(id,{})

static func preload_keys(job:int,school:int,level:int,legacy_only:bool=false)->Array[String]:
	var keys:Array[String]=[]
	for skill in SkillRules.list_for(job,school,level):
		if legacy_only and not String(skill.id).begins_with("legacy_"):continue
		for layer in binding(skill.id).get("layers",[]):
			if not keys.has(layer.art):keys.append(layer.art)
	return keys

func play_binding(id:String,trigger:String,hero:AnimatedSprite2D,enemy:AnimatedSprite2D)->AnimatedSprite2D:
	var selected:=binding(id)
	if selected.is_empty() or selected.trigger!=trigger:return null
	var primary:AnimatedSprite2D
	for layer in selected.layers:
		var sprite:=attach(layer.art,hero if layer.anchor=="hero" else enemy,int(layer.sequence),Vector2(layer.canvas_offset[0],layer.canvas_offset[1]))
		if sprite!=null:
			sprite.set_meta("skill_id",id);sprite.set_meta("trigger",trigger)
			if primary==null:primary=sprite
	if primary!=null and selected.has("audio_id"):
		var sound:=GameAudio.player(selected.audio_id)
		if sound!=null:
			add_child(sound,false,Node.INTERNAL_MODE_BACK)
			_sounds.append(sound)
			sound.finished.connect(func()->void:_sounds.erase(sound);sound.queue_free())
			sound.play()
			audio_played.emit(selected.audio_id)
	return primary

func play_reflection(job:int,school:int,level:int,state:Dictionary,magical:bool,hero:AnimatedSprite2D,enemy:AnimatedSprite2D)->void:
	if int(state.get("last_reflected",0))<=0:return
	var percent:=int(state.get("passive_magic" if magical else "passive_physical",0))
	if int(state.get("last_incoming",0))*percent/100<1:return
	for skill in SkillRules.list_for(job,school,level):
		if not skill.active and skill.effect==("reflect_magic" if magical else "reflect_physical"):
			play_binding(skill.id,"magic_reflect" if magical else "physical_reflect",hero,enemy)

func attach(key:String,subject:Node2D,sequence:int=0,anchor_offset:Vector2=Vector2.ZERO)->AnimatedSprite2D:
	if not is_instance_valid(subject) or not subject.is_inside_tree() or subject.is_queued_for_deletion():return null
	var sprite:=OriginalArt.effect(key,sequence)
	sprite.name="AttachedEffect"
	sprite.set_meta("subject_id",subject.get_instance_id())
	sprite.set_meta("anchor_offset",anchor_offset)
	add_child(sprite)
	_attachments.append({"sprite":sprite,"subject":weakref(subject),"offset":anchor_offset})
	_follow(sprite,subject,anchor_offset)
	return sprite

func _follow(sprite:AnimatedSprite2D,subject:Node2D,anchor_offset:Vector2=Vector2.ZERO)->void:
	# Both views can have translated/scaled HUD and actor station parents.
	# Preserve the ANI origin and upright pixels; reflected actors must not flip FX.
	sprite.position=get_global_transform_with_canvas().affine_inverse()*subject.get_global_transform_with_canvas().origin+anchor_offset

func _process(_delta:float)->void:
	for index in range(_attachments.size()-1,-1,-1):
		var entry:Dictionary=_attachments[index]
		var sprite:AnimatedSprite2D=entry.sprite
		var subject:Node2D=entry.subject.get_ref()
		if not is_instance_valid(sprite) or sprite.is_queued_for_deletion():
			_attachments.remove_at(index)
		elif not is_instance_valid(subject) or subject.is_queued_for_deletion() or not subject.is_inside_tree() or not subject.visible:
			sprite.hide();sprite.queue_free();_attachments.remove_at(index)
		else:_follow(sprite,subject,entry.offset)

func clear()->void:
	for sound in _sounds:
		if is_instance_valid(sound):sound.stop();sound.queue_free()
	_sounds.clear()
	for entry in _attachments:
		if is_instance_valid(entry.sprite):entry.sprite.hide();entry.sprite.queue_free()
	_attachments.clear()
