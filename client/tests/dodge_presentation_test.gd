extends "res://tests/team_test.gd"
func _run()->void:
	await Platform.when_ready();await Game.when_ready()
	var old:=Game.player.duplicate(true)
	var a:=OriginalArt.battle_actor(ShopRules.actor_key(1,0,[1,0,0]));var b:=OriginalArt.battle_actor("monster/langw");add_child(a);add_child(b)
	a.position=Vector2(220,180);b.position=Vector2(40,180);b.scale.x=-1
	var fx:=BattleEffects.new();add_child(fx)
	for subject in [a,b]:
		var attacker:Node2D=b if subject==a else a
		var home:Vector2=subject.position;var popup:=fx.dodge(subject,attacker)
		check(popup.get_node("Text").text=="闪避" and popup.get_node("Text").get_theme_constant("outline_size")==2,"Dodge has a themed outlined Chinese popup")
		check(fx._critical_flash==null and fx.number(subject,0)==null,"Dodge cannot emit zero damage or critical flash")
		fx.advance_reactions(0.12)
		check(absf(subject.position.x-attacker.position.x)>absf(home.x-attacker.position.x),"Both sides retreat away from the attacker")
		fx.advance_reactions(0.20)
		check(subject.position.is_equal_approx(home) and not fx.has_reactions(),"Dodge returns to the exact station without drifting")
		fx.dodge(subject,attacker);fx.advance_reactions(0.10);fx.clear()
		check(subject.position==home and not fx.has_reactions(),"Cancellation restores the original station")
	var floating:Node2D=fx.dodge(a,b);var floating_y:=floating.position.y
	await get_tree().create_timer(0.25).timeout
	check(floating.position.y<floating_y and floating.position.y>=floating_y-16,"Popup rises relative to its final anchor instead of flying toward scene origin")
	fx.clear();fx.queue_free();a.queue_free();b.queue_free();await get_tree().process_frame
	var model:=OnlineTeamModel.new();model.bind_character(SELF);model.state=state(encounter())
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present()
	var hero:Dictionary=view.actors[SELF];var home:Vector2=hero.sprite.position;var hp:=int(hero.hp.value)
	view._play({"actor":"m0","target":SELF,"action":"attack","skill":"","damage":0,"healed":0,"critical":false,"missed":true})
	check(not view.effects.has_reactions(),"Dodge does not occur before the authoritative impact")
	view.motion.advance(view.motion.impact_time)
	check(view.effects.has_reactions() and int(hero.hp.value)==hp and hero.sprite.animation!="hurt","Missed hit starts retreat without damage or hurt pose")
	view.motion.advance(view.motion.duration);view._process(0)
	view.queue=[{"actor":SELF,"target":"m0","action":"attack","skill":"","damage":1,"healed":0,"critical":false}]
	view._process(0.10)
	check(view.motion==null and view.queue.size()==1 and view.command_toggle.disabled,"Next action waits for dodge recovery")
	check(hero.sprite.position.x>home.x and absf(hero.hp.position.x+hero.hp.size.x/2-view._actor_hud_anchor(hero).x)<0.01,"Retreat keeps character bars aligned")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../work/battle-dodge.png")
	view._process(0.22)
	check(view.queue.is_empty() and view.motion!=null and view.motion.actor==hero.sprite and view.motion.home==home,"Counterattack starts only after restoration and captures the correct home")
	view._cancel()
	for action in ["attack","guard"]:
		view._play({"actor":SELF,"target":"m0" if action=="attack" else SELF,"action":action,"skill":"","damage":0,"healed":0,"critical":false})
		view.motion.advance(view.motion.impact_time)
		check(not view.effects.has_reactions(),"Zero damage without an explicit miss does not dodge: "+action)
		view._cancel()
	var first_hp:=int(view.actors.m0.hp.value);var second_hp:=int(view.actors.m1.hp.value)
	view.queue=[{"actor":SELF,"target":"m1","action":"skill","skill":"sheet_010","damage":9,"healed":0,"critical":false,"missed":false,"packet":1}]
	view._play({"actor":SELF,"target":"m0","action":"skill","skill":"sheet_010","damage":0,"healed":0,"critical":false,"missed":true,"packet":1})
	view.motion.advance(view.motion.impact_time)
	check(view.effects._dodges.size()==1 and view.effects._dodges[0].actor==view.actors.m0.sprite,"Mixed area outcome dodges only the missed target")
	check(int(view.actors.m0.hp.value)==first_hp and int(view.actors.m1.hp.value)==second_hp-9,"Mixed area outcome retains damage on the landed target")
	view._cancel();view.queue_free();await get_tree().process_frame
	# Actual legacy online presentation uses the two explicit flags, with no zero-damage inference.
	var fixture=load("res://tests/online_pve_test.gd").new();var pve:=OnlinePve.new();pve.character_id=fixture.SELF;pve.ready=true
	var snapshot:Dictionary=fixture.pve_state();snapshot.battle={"id":BATTLE,"revision":"0","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3},"skill_rules_version":1,"skills":SkillRules.new_state(1,3,60)}
	pve.state=snapshot
	var online:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(online);online.set_process(false);online.present(pve)
	snapshot.battle.revision="1";snapshot.battle.round=1;snapshot.battle.skills.last_missed=true;snapshot.battle.skills.last_enemy_missed=true;snapshot.battle.skills.last_enemy_acted=true;pve.last_action="attack";online.present(pve)
	online._hero_motion.advance(online._hero_motion.impact_time)
	check(online.effects._dodges.size()==1 and online.effects._dodges[0].actor==online.enemy,"Legacy online outbound miss dodges the enemy")
	online._hero_motion.advance(online._hero_motion.duration)
	check(online._enemy_motion==null and online._reaction_next.is_valid(),"Legacy retaliation also waits for dodge recovery")
	online._process(0.32)
	online._enemy_motion.advance(online._enemy_motion.impact_time)
	check(online.effects._dodges.size()==1 and online.effects._dodges[0].actor==online.hero,"Legacy monster miss dodges the hero")
	online._process(0.10)
	check(online.hero.position.x>0 and online.get_node("Hud/BattleHeroHp").position.x>online._hero_hp_home.x,"Legacy online health bar follows the retreating hero")
	online._cancel_motion();online.present(pve)
	check(not online.effects.has_reactions(),"Repeated revision cannot replay a dodge")
	online.queue_free();await get_tree().process_frame
	var duel_fixture=load("res://tests/duel_test.gd").new()
	var duel_view:DuelBattleView=load("res://scenes/ui/duel_battle_view.tscn").instantiate();add_child(duel_view);duel_view.set_process(false);duel_view.present(pve)
	duel_view.channel=OnlineDuel.new();duel_view.channel.character_id=SELF
	duel_view.opponent=duel_fixture.fighter(OTHER,0)
	duel_view._playing={"actor":SELF,"action":"attack","skill":"","damage":0,"reflected":0,"missed":true,"fighters":[duel_fixture.fighter(SELF,0),duel_fixture.fighter(OTHER,1)]}
	duel_view._hero_motion=BattleActionPlayback.new();duel_view._hero_impact()
	check(duel_view.effects._dodges.size()==1 and duel_view.effects._dodges[0].actor==duel_view.enemy,"Duel outbound miss uses the same retreat and popup")
	duel_view._cancel_motion();duel_view._playing.actor=OTHER;duel_view._start_enemy_motion();duel_view._enemy_motion.advance(duel_view._enemy_motion.impact_time)
	check(duel_view.effects._dodges.size()==1 and duel_view.effects._dodges[0].actor==duel_view.hero,"Duel opponent miss uses the same retreat and popup")
	duel_view._cancel_motion();duel_view.queue_free();duel_fixture.free();fixture.free();await get_tree().process_frame
	check(Game.player==old,"Presentation does not alter character data")
	await get_tree().create_timer(0.25).timeout
	print("DODGE PRESENTATION: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
