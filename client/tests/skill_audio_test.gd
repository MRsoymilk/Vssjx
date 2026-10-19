extends "res://tests/online_pve_test.gd"

func _run()->void:
	var old:=Game.player.duplicate(true)
	var path:=Game.save_path
	Game.save_path="user://skill_audio_%d.json"%OS.get_process_id()
	for config in [{"skill":"sheet_010","audio":"thunder","job":0,"school":2,"duration":1.6484167},{"skill":"sheet_018","audio":"fire","job":2,"school":0,"duration":1.3749792}]:
		await _verify_sound(config)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path));Game.save_path=path;Game.player=old
	print("SKILL AUDIO: %d checks, %d failures"%[checks,failures])
	get_tree().quit(0 if failures==0 else 1)

func _verify_sound(config:Dictionary)->void:
	var stream:=GameAudio.stream(config.audio)
	check(stream is AudioStreamWAV and absf(stream.get_length()-float(config.duration))<0.001,"Original stereo WAV is imported at its full duration")
	check(GameAudio.stream("unknown")==null,"Unknown audio IDs cannot load arbitrary resources")
	var hero:=OriginalArt.battle_actor("hero/mzs");add_child(hero)
	var enemy:=OriginalArt.battle_actor("monster/langw");add_child(enemy)
	var effects:=BattleEffects.new();add_child(effects)
	var heard:Array=[];effects.audio_played.connect(func(id:String)->void:heard.append(id))
	effects.play_binding(config.skill,"wrong_trigger",hero,enemy)
	effects.play_action("attack",config.job,config.skill,hero,enemy)
	check(heard.is_empty(),"Wrong trigger and ordinary attacks do not play the selected sound")
	effects.play_action("skill",config.job,config.skill,hero,enemy)
	check(heard==[config.audio] and effects._sounds.size()==1 and effects._sounds[0].playing,"Selected skill emits one playing sound at impact")
	check(effects._sounds[0].volume_db==-6,"Skill volume uses the shared audio definition")
	var sound:AudioStreamPlayer=effects._sounds[0]
	effects.clear()
	check(not sound.playing and sound.is_queued_for_deletion(),"Clearing a battle stops and frees the active sound")
	hero.queue_free();enemy.queue_free();effects.queue_free();await get_tree().process_frame
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app)
	Game.new_player("技能音效",config.job,config.school);Game.player.level=60;Game.player.hp=200;Game.player.mp=200
	app._enter_world()
	var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
	app._start_battle(opponent)
	app.battle_effects.audio_played.connect(func(id:String)->void:heard.append(id))
	heard.clear();app._battle_turn("skill",config.skill)
	var deadline:=Time.get_ticks_msec()+4000
	while app.battle_playback==null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(heard.is_empty(),"Local skill command does not play audio before its native impact")
	app.battle_playback.advance(app.battle_playback.impact_time)
	check(heard==[config.audio],"Actual local impact plays the selected sound once")
	deadline=Time.get_ticks_msec()+5000
	while app.battle_playback!=null and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	app._home();app.queue_free();await get_tree().process_frame
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:9999")
	var state:=pve_state();state.character.job=config.job;state.character.school=config.school;state.character.level=60
	state.battle={"id":PEER,"revision":"1","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3}}
	model.state=state;model.ready=true
	var view:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(view);view.set_process(false);view.present(model)
	heard.clear();view.effects.audio_played.connect(func(id:String)->void:heard.append(id))
	var result:Dictionary=state.duplicate(true);result.battle.revision="2";result.battle.round=1;result.battle.skill_rules_version=1
	result.battle.skills=SkillRules.new_state(config.job,config.school,60);result.battle.skills.last_skill=config.skill;result.battle.skills.last_damage=20;result.battle.skills.last_enemy_acted=true;result.battle.enemy_hp=980
	model.state=result;model.last_action="skill";view.present(model)
	check(heard.is_empty(),"Online state receipt waits for impact before audio")
	view._hero_motion.advance(view._hero_motion.impact_time)
	check(heard==[config.audio],"Online impact uses the same skill sound")
	view.present(model)
	check(heard.size()==1,"Same revision refresh cannot replay the selected sound")
	view.effects.clear();view.queue_free();await get_tree().process_frame
	# The audio mixing thread releases stopped playback on its next update.
	await get_tree().create_timer(0.2).timeout
