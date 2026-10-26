class_name BattleEffects
extends Node2D
## One-shot original ANI effects, attached by canvas position without inheriting facing.
## Bindings are authored from each skill's meaning, using original ANI artwork.
static var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/skill-effects-v1.json"))
var _attachments:Array[Dictionary]=[]
var _sounds:Array[AudioStreamPlayer]=[]
var _numbers:Array[Node2D]=[]
var _dodges:Array[BattleDodgePlayback]=[]
var _critical_flash:CanvasLayer
signal audio_played(id:String)

func _init()->void:
	# BattleActionPlayback advances in its owning view first.
	process_priority=10

func play_action(command:String,job:int,skill_id:String,hero:AnimatedSprite2D,enemy:AnimatedSprite2D,skill_level:int=1)->AnimatedSprite2D:
	if command not in ["attack","skill"]:return null
	if command=="attack":return attach("effect/flash",enemy)
	# Old servers omit the selected ID; resolve their known legacy skill explicitly.
	var id:=skill_id if not skill_id.is_empty() else "legacy_%d"%clampi(job,0,2)
	return play_binding(id,"cast_impact",hero,enemy,true,skill_level)

static func binding(id:String,skill_level:int=1)->Dictionary:
	var selected:Dictionary=catalog.bindings.get(id,{}).duplicate(true)
	for stage in selected.get("stages",[]):
		if clampi(skill_level,1,15)>=int(stage.level):selected.layers=stage.layers
	return selected

static func preload_keys(job:int,school:int,level:int,legacy_only:bool=false)->Array[String]:
	var keys:Array[String]=[]
	for skill in SkillRules.list_for(job,school,level):
		if legacy_only and not String(skill.id).begins_with("legacy_"):continue
		var selected:=binding(skill.id)
		var layers:Array=selected.get("layers",[]).duplicate()
		for stage in selected.get("stages",[]):layers.append_array(stage.layers)
		for layer in layers:
			if not keys.has(layer.art):keys.append(layer.art)
	return keys

func play_binding(id:String,trigger:String,hero:AnimatedSprite2D,enemy:AnimatedSprite2D,with_audio:bool=true,skill_level:int=1)->AnimatedSprite2D:
	var selected:=binding(id,skill_level)
	if selected.is_empty() or selected.trigger!=trigger:return null
	var primary:AnimatedSprite2D
	for layer in selected.layers:
		var sprite:=attach(layer.art,hero if layer.anchor=="hero" else enemy,int(layer.sequence),Vector2(layer.canvas_offset[0],layer.canvas_offset[1]))
		if sprite!=null:
			sprite.set_meta("skill_id",id);sprite.set_meta("trigger",trigger);sprite.set_meta("skill_level",clampi(skill_level,1,15))
			if primary==null:primary=sprite
	if primary!=null and with_audio and selected.has("audio_id"):
		var sound:=GameAudio.player(selected.audio_id)
		if sound!=null:
			add_child(sound,false,Node.INTERNAL_MODE_BACK)
			_sounds.append(sound)
			sound.finished.connect(func()->void:_sounds.erase(sound);sound.queue_free())
			sound.play()
			audio_played.emit(selected.audio_id)
	return primary

func has_skill_effects(id:String)->bool:
	for entry in _attachments:
		var sprite:AnimatedSprite2D=entry.sprite
		if is_instance_valid(sprite) and not sprite.is_queued_for_deletion() and sprite.get_meta("skill_id","")==id:return true
	return false

func play_reflection(job:int,school:int,level:int,state:Dictionary,magical:bool,hero:AnimatedSprite2D,enemy:AnimatedSprite2D)->void:
	if int(state.get("last_reflected",0))<=0:return
	var percent:=int(state.get("passive_magic" if magical else "passive_physical",0))
	if int(state.get("last_incoming",0))*percent/100<1:return
	for skill in SkillRules.list_for(job,school,level):
		if not skill.active and skill.effect==("reflect_magic" if magical else "reflect_physical"):
			play_binding(skill.id,"magic_reflect" if magical else "physical_reflect",hero,enemy)

func dodge(subject:Node2D,attacker:Node2D)->Node2D:
	if not is_instance_valid(subject) or not subject.is_inside_tree() or not subject.visible:return null
	for reaction in _dodges.duplicate():
		if reaction.actor==subject:reaction.cancel();_dodges.erase(reaction)
	var reaction:=BattleDodgePlayback.new();reaction.start(subject,attacker);_dodges.append(reaction)
	var popup:Node2D=preload("res://scenes/ui/battle_dodge_popup.tscn").instantiate()
	var point:=Vector2.ZERO
	if subject is AnimatedSprite2D and subject.get_meta("native_ground_anchor",false):
		var info:=OriginalArt.actor_info(subject.get_meta("art_key",""))
		point.x=subject.offset.x-float(info.origin[0])+float(info.get("anchor_x",0))
	add_child(popup,false,Node.INTERNAL_MODE_BACK)
	popup.position=get_global_transform_with_canvas().affine_inverse()*(subject.get_global_transform_with_canvas()*point)+Vector2(0,-64)
	popup.present()
	popup.set_meta("feedback","dodge");_numbers.append(popup)
	popup.tree_exiting.connect(func()->void:_numbers.erase(popup))
	return popup
func advance_reactions(delta:float)->void:
	for reaction in _dodges.duplicate():
		reaction.advance(delta)
		if not reaction.active:_dodges.erase(reaction)
func reaction_remaining()->float:
	var seconds:=0.0
	for reaction in _dodges:seconds=maxf(seconds,reaction.remaining())
	return seconds
func has_reactions()->bool:return not _dodges.is_empty()
func number(subject:Node2D,amount:int,critical:bool=false,healed:bool=false)->Node2D:
	if amount<=0 or not is_instance_valid(subject) or not subject.is_inside_tree():return null
	var popup:Node2D=preload("res://scenes/ui/battle_hit_number.tscn").instantiate()
	add_child(popup,false,Node.INTERNAL_MODE_BACK)
	popup.position=get_global_transform_with_canvas().affine_inverse()*subject.get_global_transform_with_canvas().origin+Vector2(0,-53)
	_numbers.append(popup)
	popup.tree_exiting.connect(func()->void:_numbers.erase(popup))
	popup.present(amount,critical,healed)
	if critical and not healed:
		if not is_instance_valid(_critical_flash):
			_critical_flash=preload("res://scenes/ui/battle_critical_flash.tscn").instantiate()
			add_child(_critical_flash,false,Node.INTERNAL_MODE_BACK)
		_critical_flash.pulse()
	return popup

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
	for reaction in _dodges:reaction.cancel()
	_dodges.clear()
	if is_instance_valid(_critical_flash):_critical_flash.clear()
	for popup in _numbers.duplicate():
		if is_instance_valid(popup):popup.hide();popup.queue_free()
	_numbers.clear()
	for sound in _sounds:
		if is_instance_valid(sound):sound.stop();sound.queue_free()
	_sounds.clear()
	for entry in _attachments:
		if is_instance_valid(entry.sprite):entry.sprite.hide();entry.sprite.queue_free()
	_attachments.clear()
