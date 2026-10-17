extends "res://tests/online_pve_test.gd"

func aligned(effect:AnimatedSprite2D,subject:Node2D)->bool:
	return effect.get_global_transform_with_canvas().origin.is_equal_approx(subject.get_global_transform_with_canvas().origin)

func _run()->void:
	output=OS.get_environment("SSJX_EFFECT_CAPTURE_PATH")
	var original:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	Game.save_path="user://battle_effects_%d.json"%OS.get_process_id()
	# Exercise independent mirrored/scaled actor and HUD branches, not local-position subtraction.
	var station:=Node2D.new();station.position=Vector2(91,57);station.scale=Vector2(-1.3,1.3);add_child(station)
	var actor:=OriginalArt.battle_actor("hero/mck");actor.position=Vector2(30,60);station.add_child(actor)
	var hud:=Node2D.new();hud.position=Vector2(17,28);hud.scale=Vector2(.8,.8);add_child(hud)
	var effects:=BattleEffects.new();hud.add_child(effects)
	var fx:=effects.attach("effect/t36",actor)
	check(aligned(fx,actor),"Initial effect anchor converts between separate canvas branches")
	actor.position+=Vector2(45,-7);station.position+=Vector2(14,12);effects._process(0)
	check(aligned(fx,actor),"Moving actor and its station moves the effect in the same frame")
	check(fx.scale==Vector2.ONE and is_zero_approx(fx.rotation),"Actor facing and scale do not reverse or stretch effect artwork")
	check(fx.offset==Vector2(-20,-42),"Original ANI image origin is preserved")
	actor.hide();effects._process(0)
	check(fx.is_queued_for_deletion() and not fx.visible,"Hidden/dead subject removes its attached effect")
	actor.show();fx=effects.attach("effect/flash",actor)
	var lifetime:=0.0
	for index in fx.sprite_frames.get_frame_count(fx.animation):lifetime+=fx.sprite_frames.get_frame_duration(fx.animation,index)/fx.sprite_frames.get_animation_speed(fx.animation)
	await get_tree().create_timer(lifetime+0.2).timeout
	check(not is_instance_valid(fx),"One-shot effect frees itself at the end of its original sequence")
	fx=effects.attach("effect/t36",actor);actor.queue_free();await get_tree().process_frame;effects._process(0)
	check(not is_instance_valid(fx) or fx.is_queued_for_deletion(),"Freed subject cannot leave a detached effect")
	station.queue_free();hud.queue_free();await get_tree().process_frame
	# Real local action impact spawns FX for each job, with support attached to its caster.
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app)
	for job in 3:
		Game.new_player("特效验证",job,2 if job==0 else 1)
		Game.player.level=60;Game.player.hp=100;Game.player.mp=200
		app._enter_world()
		var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
		app._start_battle(opponent)
		var id:String=["sheet_011","sheet_003","sheet_039"][job]
		app._battle_turn("skill",id)
		check(app.battle_effects.get_child_count()==0,"No local skill effect before impact, job %d"%job)
		var deadline:=Time.get_ticks_msec()+4000
		while app.battle_effects.get_child_count()==0 and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		check(app.battle_effects.get_child_count()==1,"Exactly one local skill effect at impact, job %d"%job)
		if app.battle_effects.get_child_count()>0:
			fx=app.battle_effects.get_child(0)
			var subject:AnimatedSprite2D=app.battle_enemy if job==1 else app.battle_hero
			check(fx.get_meta("subject_id")==subject.get_instance_id() and fx.get_meta("art_key")==BattleEffects.binding(id).layers[0].art,"Damage targets enemy; support follows caster with the individually mapped art")
			var previous:Vector2=subject.position;subject.position+=Vector2(16,3);app.battle_effects._process(0)
			check(aligned(fx,subject),"Local effect stays attached when target moves")
			subject.position=previous;app.battle_effects._process(0)
			if job==2:await capture("local-support-effect")
			app._home()
			check(not is_instance_valid(fx) or fx.is_queued_for_deletion(),"Leaving local encounter cancels unfinished FX")
	app.queue_free();await get_tree().process_frame
	# Real online presentation: spawn only at authoritative impact, never on replay/refresh.
	for support in [false,true]:
		var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:9999")
		var state:=pve_state();state.character.job=0 if support else 1;state.character.school=2;state.character.level=60
		state.battle={"id":PEER,"revision":"1","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3}}
		model.state=state;model.ready=true
		var view:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(view);view.set_process(false);view.effects.set_process(false);view.present(model)
		var result:Dictionary=state.duplicate(true);result.battle.revision="2";result.battle.round=1;result.battle.skill_rules_version=1
		result.battle.skills=SkillRules.new_state(int(state.character.job),2,60)
		result.battle.skills.last_skill="sheet_011" if support else "sheet_003";result.battle.skills.last_enemy_acted=true;result.battle.skills.last_damage=0 if support else 20;result.battle.enemy_hp=1000 if support else 980
		model.state=result;model.last_action="skill";view.present(model)
		check(view.effects.get_child_count()==0,"Online receipt does not spawn FX before its animation impact")
		view._hero_motion.advance(view._hero_motion.impact_time)
		check(view.effects.get_child_count()==1,"Online skill impact now displays a one-shot effect")
		fx=view.effects.get_child(0)
		var subject:AnimatedSprite2D=view.hero if support else view.enemy
		check(fx.get_meta("subject_id")==subject.get_instance_id(),"Online support and offensive effects use the same attachment rule")
		view.present(model);check(view.effects.get_child_count()==1,"Same revision refresh cannot duplicate an effect")
		view._hero_motion.advance(view._hero_motion.remaining());view.effects._process(0)
		check(aligned(fx,subject),"Effect follows target during native enemy approach, not departing caster")
		view._enemy_motion.advance(view._enemy_motion.remaining());view.effects._process(0)
		check(aligned(fx,subject),"Effect follows the actor back to its station")
		if not support:
			await get_tree().create_timer(.3).timeout
			await capture("online-target-effect")
		model.disconnect_channel();view._process(0)
		check(fx.is_queued_for_deletion() and not fx.visible,"Online disconnect clears any unfinished effect")
		view.queue_free();await get_tree().process_frame
	Game.player=original;Game.save_path=old_path
	print("BATTLE EFFECTS: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
