extends "res://tests/shared_interface_test.gd"

func _run()->void:
	output=OS.get_environment("SSJX_MAPPING_CAPTURE_PATH")
	var field:=OriginalBattleField.new();field.kind="arena";field.position=Vector2(0,28);add_child(field)
	var caption:=Label.new();caption.position=Vector2(20,35);caption.size=Vector2(280,32);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.theme=preload("res://scenes/ui/online_pve_theme.tres");add_child(caption)
	var hero:=OriginalArt.battle_actor("hero/mck");hero.position=Vector2(250,280);add_child(hero)
	var enemy:=OriginalArt.battle_actor("monster/langw");enemy.position=Vector2(65,280);enemy.scale.x=-1;add_child(enemy)
	var effects:=BattleEffects.new();add_child(effects)
	check(BattleEffects.catalog.bindings.size()==33,"All 30 named and three compatibility skills have a binding")
	for skill in SkillRules.catalog.items:
		hero.position=Vector2(250,280);enemy.position=Vector2(65,280)
		caption.text=skill.name
		var binding:=BattleEffects.binding(skill.id)
		check(not binding.is_empty() and binding.name==skill.name,"Explicit binding for "+skill.name)
		if skill.active:
			effects.play_action("skill",int(skill.job),skill.id,hero,enemy)
		else:
			check(effects.play_action("skill",int(skill.job),skill.id,hero,enemy)==null,"Passive cannot play as an active cast")
			var state:=SkillRules.new_state(int(skill.job),int(skill.school),60)
			state.last_incoming=100;state.last_reflected=20
			var magical:bool=skill.effect=="reflect_magic"
			effects.play_reflection(int(skill.job),int(skill.school),60,state,not magical,hero,enemy)
			check(effects.get_child_count()==0,"Wrong damage type cannot trigger passive FX")
			effects.play_reflection(int(skill.job),int(skill.school),60,state,magical,hero,enemy)
		check(effects.get_child_count()==binding.layers.size(),"Expected layer count for "+skill.name)
		for i in binding.layers.size():
			var sprite:AnimatedSprite2D=effects.get_child(i)
			var layer:Dictionary=binding.layers[i]
			var subject:AnimatedSprite2D=hero if layer.anchor=="hero" else enemy
			check(sprite.get_meta("art_key")==layer.art and sprite.get_meta("subject_id")==subject.get_instance_id(),"Art and attachment for "+skill.name)
			check(not sprite.sprite_frames.get_animation_loop(sprite.animation) and sprite.sprite_frames.get_frame_count(sprite.animation)>0,"Native one-shot sequence for "+skill.name)
			subject.position+=Vector2(9,-2);effects._process(0)
			var anchor:=effects.get_global_transform_with_canvas().affine_inverse()*subject.get_global_transform_with_canvas().origin+Vector2(layer.canvas_offset[0],layer.canvas_offset[1])
			check(sprite.position.is_equal_approx(anchor),"Mapped layer follows its own subject and configured body offset for "+skill.name)
		var prepared:=BattleEffects.preload_keys(int(skill.job),maxi(0,int(skill.school)),60)
		for layer in binding.layers:check(prepared.has(layer.art),"Character preparation includes "+layer.art)
		if not output.is_empty() and skill.id in ["sheet_010","sheet_018","sheet_035","sheet_039","sheet_042","sheet_047","sheet_051","sheet_052"]:
			await get_tree().create_timer(.3).timeout
			await capture(skill.id)
		effects.clear();await get_tree().process_frame
	check(effects.play_action("skill",0,"unknown_skill",hero,enemy)==null,"Unknown ID never falls back to a generic job effect")
	var compatibility:=effects.play_action("skill",1,"",hero,enemy)
	check(compatibility!=null and compatibility.get_meta("skill_id")=="legacy_1","Old server without ID resolves only its explicit legacy skill")
	effects.clear();await get_tree().process_frame
	var legacy_keys:=BattleEffects.preload_keys(1,2,60,true)
	check(legacy_keys==["effect/t40"],"Old server only prepares its legacy effects")
	hero.queue_free();enemy.queue_free();effects.queue_free()
	print("SKILL EFFECT MAPPING: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
