extends "res://tests/online_pve_test.gd"

func _run()->void:
	await Game.when_ready()
	output=OS.get_environment("SSJX_STATIONARY_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	var effects:=BattleEffects.new();add_child(effects);effects.set_process(false)
	var target:=OriginalArt.battle_actor("monster/langw");target.position=Vector2(60,220);add_child(target)
	for gender in 2:
		for job in 3:
			var stem:String=("m" if gender==0 else "w")+["zs","ck","fs"][job]
			for look in ["","_w2_c1_h1"]:
				var key:String="hero/"+stem+look
				var actor:=OriginalArt.battle_actor(key);actor.position=Vector2(245,260);add_child(actor)
				check(actor.sprite_frames.has_animation("cast") and not actor.sprite_frames.get_animation_loop("cast"),"Both sexes and equipped looks expose the original one-shot casting pose")
				var source:=StringName("source_%d"%(OriginalArt.actor_info(key).sequences.size()-1-8))
				check(actor.sprite_frames.get_frame_count("cast")==actor.sprite_frames.get_frame_count(source),"The full reviewed native sequence is retained")
				for step in actor.sprite_frames.get_frame_count("cast"):
					check(actor.sprite_frames.get_frame_texture("cast",step)==actor.sprite_frames.get_frame_texture(source,step) and actor.sprite_frames.get_frame_duration("cast",step)==actor.sprite_frames.get_frame_duration(source,step),"Raised weapon and hands keep original pixels, order and relative timing")
				var skills:Array=["sheet_010","sheet_015"] if job==0 else ["sheet_003","sheet_004","sheet_005","sheet_008"]
				if job==2:
					skills=[]
					for skill in SkillRules.list_for(2,3,60):
						if skill.active:skills.append(skill.id)
				for side in [-1,1]:
					actor.scale.x=side
					for id in skills:
						for rank in [1,6,10,15]:
							var home:=actor.position;var motion:=BattleActionPlayback.new();var hits:Array=[]
							motion.impact.connect(func()->void:hits.append(true))
							effects.start_motion(motion,"skill",job,id,actor,OriginalArt.actor_info(key),target,rank,false)
							check(motion.action==&"cast" and actor.position==home,"Requested skill casts at its station")
							motion.advance(motion.release_time)
							if BattleEffects.projectile_seconds(id)>0:
								check(hits.is_empty() and effects.has_skill_effects(id),"Raised hands launch a projectile before damage")
								var fx:AnimatedSprite2D=effects._attachments[0].sprite
								check(fx.position.is_equal_approx(actor.global_position) and not fx.is_playing(),"Projectile begins at its caster and keeps the original first frame until arrival")
								effects._process(0.14)
								check(fx.position.is_equal_approx(actor.global_position.lerp(target.global_position,0.5)),"Projectile crosses the field toward its target in either facing")
								effects._process(0.14);motion.advance(motion.remaining())
								check(fx.position.is_equal_approx(target.global_position) and fx.is_playing(),"The original ANI animation plays at the receiver after flight")
							else:
								effects.play_action("skill",job,id,actor,target,rank)
								motion.advance(motion.remaining())
							check(hits.size()==1 and actor.position==home,"Exactly one impact restores the original actor station")
							var binding:=BattleEffects.binding(id,rank)
							for index in binding.layers.size():
								var fx:AnimatedSprite2D=effects._attachments[index].sprite
								check(fx.get_meta("art_key")==binding.layers[index].art,"Skill rank preserves the exact base/6/10/15 resource")
							effects.clear()
				check(BattleEffects.animation_for("attack",job,"",actor)==&"attack","Normal attacks retain their original native motion")
				if job<2:check(BattleEffects.animation_for("skill",job,"sheet_013" if job==0 else "sheet_006",actor)==&"attack","Other melee skills keep their existing attack motion")
				var pending:=BattleActionPlayback.new()
				effects.start_motion(pending,"skill",job,skills[0],actor,OriginalArt.actor_info(key),target,1,false)
				pending.cancel();pending.advance(10)
				check(effects._attachments.is_empty() and actor.position==Vector2(245,260),"Cancelling before release cannot spawn a late effect or move the actor")
				actor.queue_free();await get_tree().process_frame
	effects.queue_free();target.queue_free();await get_tree().process_frame
	# The actual shared formation view must launch at every AOE receiver and
	# retain authoritative HP until arrival, including the local-solo adapter.
	var factory=load("res://tests/team_test.gd").new()
	var party=load("res://scripts/network/online_team.gd").new()
	party.character_id=factory.SELF;party.state=factory.state(factory.encounter())
	party.state.team.battle.fighters[0].job=1
	var team=load("res://scenes/ui/team_battle_view.tscn").instantiate();team.model=party;add_child(team);team.set_process(false);team.present();team.effects.set_process(false)
	var hero:AnimatedSprite2D=team.actors[factory.SELF].sprite;var home:=hero.position
	var events:Array=[]
	for slot in ["m0","m1"]:events.append({"actor":factory.SELF,"target":slot,"action":"skill","skill":"sheet_008","damage":44,"healed":0,"critical":false,"skill_level":10,"packet":"cast"})
	team.queue=[events[1]];team._play(events[0]);team._refresh_controls();var hp:=float(team.actors.m0.hp.value)
	team.motion.advance(team.motion.release_time)
	check(team.effects._attachments.size()==2 and hero.position==home,"One group cast launches once to every distinct authoritative receiver")
	check(team.actors.m0.hp.value==hp and team.effects._numbers.is_empty(),"Formation HP and hit numbers wait for projectile arrival")
	team.effects._process(0.14);await capture("knight-raised-projectiles")
	team.effects._process(0.14);team.motion.advance(team.motion.remaining())
	check(team.actors.m0.hp.value==hp-44 and team.effects._numbers.size()==2,"Arrival displays each receiver's authoritative damage exactly once")
	await capture("knight-target-impact")
	team._cancel();team.queue_free();await get_tree().process_frame
	party.state.team.battle.fighters[0].job=0
	team=load("res://scenes/ui/team_battle_view.tscn").instantiate();team.model=party;add_child(team);team.set_process(false);team.present();team.effects.set_process(false)
	hero=team.actors[factory.SELF].sprite;home=hero.position
	team._play({"actor":factory.SELF,"target":"m0","action":"skill","skill":"sheet_010","damage":44,"healed":0,"critical":false,"skill_level":6})
	team._refresh_controls();team.motion.advance(team.motion.impact_time)
	check(hero.position==home and hero.animation=="cast" and team.effects._attachments[0].subject.get_ref()==team.actors.m0.sprite,"Lishi raises the weapon at home while lightning appears on the opponent")
	await capture("lishi-raised-target-lightning")
	team._cancel();hp=float(team.actors.m0.hp.value)
	team._play({"actor":factory.SELF,"target":"m0","action":"skill","skill":"sheet_010","damage":44,"healed":0,"critical":false,"skill_level":6})
	team._cancel()
	check(team.actors.m0.hp.value==hp and team.effects._numbers.is_empty() and team.effects._attachments.is_empty(),"Cancelling the actual formation before impact cannot apply damage or respawn cleared feedback")
	team.queue_free();factory.free();await get_tree().process_frame
	# Exercise the mirrored opponent branch of the actual duel view, which has
	# its own playback entry point rather than the PvE hero branch.
	var duel_factory=load("res://tests/duel_test.gd").new();var channel:=OnlineDuel.new()
	channel.character_id=duel_factory.SELF;channel.connected=true;channel.state=duel_factory.state()
	var duel_state:Dictionary=duel_factory.battle()
	duel_state.fighters[1].job=1;duel_state.fighters[1].level=60;duel_state.fighters[1].effects=SkillRules.new_state(1,3,60,60)
	channel.state.battle=duel_state
	var duel=load("res://scenes/ui/duel_battle_view.tscn").instantiate();add_child(duel);duel.set_process(false);duel.present_duel(channel);duel.effects.set_process(false)
	var enemy_home:Vector2=duel.enemy.position
	duel_state.resolved_round=1;duel_state.phase="resolving";duel_state.revision="1"
	duel_state.events=[{"actor":duel_factory.OTHER,"action":"skill","skill":"sheet_003","damage":20,"reflected":0,"fighters":duel_state.fighters.duplicate(true)}]
	duel.present_duel(channel)
	check(duel._enemy_motion.action==&"cast" and duel.enemy.position==enemy_home,"The opponent also casts in place during a real duel")
	duel._enemy_motion.advance(duel._enemy_motion.release_time)
	check(duel.effects._attachments.size()==1 and duel.effects._numbers.is_empty(),"Opponent projectile launches before displaying the server damage")
	duel.effects._process(0.28);duel._enemy_motion.advance(duel._enemy_motion.remaining())
	check(duel.effects._numbers.size()==1 and duel.effects._numbers[0].amount==20 and duel.enemy.position==enemy_home,"Opponent projectile impact displays one authoritative damage number")
	duel._cancel_motion();duel.queue_free();duel_factory.free();await get_tree().process_frame
	print("STATIONARY SKILLS: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
