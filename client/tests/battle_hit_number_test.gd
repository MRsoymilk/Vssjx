extends "res://tests/online_pve_test.gd"

func _run()->void:
	var old:=Game.player.duplicate(true);var old_path:=Game.save_path
	Game.save_path="user://hit_number_%d.json"%OS.get_process_id()
	var effects:=BattleEffects.new();effects.position=Vector2(40,30);add_child(effects)
	var actor:=OriginalArt.battle_actor("hero/mzs");actor.position=Vector2(200,230);actor.scale.x=-1;add_child(actor)
	check(effects.number(actor,0)==null,"Zero damage never invents a miss or a hit")
	var popup=effects.number(actor,123,true)
	check(popup.get_node("Number").text=="-123" and popup.get_node("Critical").visible and popup.get_node("Burst").visible,"Critical feedback uses the reference red outlined number and impact flash")
	check(popup.global_position==actor.global_position+Vector2(0,-53) and popup.scale.x>0,"Damage is placed above the receiver without inheriting mirrored facing")
	await get_tree().create_timer(0.95).timeout
	check(not is_instance_valid(popup) and effects._numbers.is_empty(),"Floating damage expires and releases tracking")
	popup=effects.number(actor,20,false,true)
	check(popup.get_node("Number").text=="+20" and not popup.critical,"Healing has a separate positive display")
	effects.clear();check(popup.is_queued_for_deletion(),"Cancelling a battle removes pending numbers")
	effects.queue_free();actor.queue_free();await get_tree().process_frame
	var state:=SkillRules.new_state(0,0,60)
	state.crit=1;state.crit_chance=100
	check(SkillRules.critical(state,20,0)==30 and state.last_critical,"Critical display flag comes from the existing roll")
	SkillRules.reset_turn(state);check(not state.get("last_critical",false),"A later normal action cannot inherit a critical flag")
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app)
	Game.new_player("伤害飘字",0,2);Game.player.level=60;Game.player.hp=200;Game.player.mp=200
	app._enter_world()
	var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
	app._start_battle(opponent);app.battle.skills.crit=1;app.battle.skills.crit_chance=100
	app._battle_turn("attack")
	var deadline:=Time.get_ticks_msec()+4000
	while app.battle_playback==null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(app.battle_effects._numbers.is_empty(),"Local attack does not show damage before impact")
	app.battle_playback.advance(app.battle_playback.impact_time)
	check(app.battle_effects._numbers.size()==1 and app.battle_effects._numbers[0].critical,"Actual local critical produces one number at impact")
	output=OS.get_environment("SSJX_HIT_NUMBER_CAPTURE") if DisplayServer.get_name()!="headless" else ""
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		await get_tree().create_timer(0.12).timeout
		await capture("local_critical")
	deadline=Time.get_ticks_msec()+5000
	while app.battle_playback!=null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	app._home();app.queue_free();await get_tree().process_frame
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:9999")
	var original:=pve_state();original.character.level=60
	original.battle={"id":PEER,"revision":"1","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3}}
	model.state=original;model.ready=true
	var view:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(view);view.set_process(false);view.present(model)
	var result:Dictionary=original.duplicate(true);result.battle.revision="2";result.battle.round=1;result.battle.enemy_hp=970;result.battle.hp=83;result.battle.skill_rules_version=1;result.battle.skills=SkillRules.new_state(1,2,60)
	result.battle.skills.last_damage=30;result.battle.skills.last_incoming=12;result.battle.skills.last_critical=true;result.battle.skills.last_enemy_acted=true
	model.state=result;model.last_action="attack";view.present(model)
	check(view.effects._numbers.is_empty(),"Server receipt alone does not show damage early")
	view._hero_motion.advance(view._hero_motion.impact_time)
	check(view.effects._numbers.size()==1 and view.effects._numbers[0].amount==30 and view.effects._numbers[0].critical,"Online impact uses the authoritative damage and critical flag")
	view.present(model);check(view.effects._numbers.size()==1,"Refreshing the same revision never duplicates damage")
	await capture("online_critical")
	view._hero_motion.advance(view._hero_motion.remaining())
	view._enemy_motion.advance(view._enemy_motion.impact_time)
	check(view.effects._numbers.size()==2 and view.effects._numbers[1].amount==12,"Enemy impact displays damage above the hero")
	view._cancel_motion();check(view.effects._numbers.is_empty(),"Leaving online playback clears all numbers")
	view.queue_free();await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.save_path=old_path;Game.player=old
	print("HIT NUMBER: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
