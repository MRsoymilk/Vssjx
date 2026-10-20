extends "res://tests/online_pve_test.gd"
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path;Game.save_path="user://dodge_rules_%d.json"%OS.get_process_id()
	Game.new_player("闪避验证",1,3);Game.player.level=60;Game.restore()
	var sources:Array=SharedWorldMap.population("qingyun_trail").filter(func(e:Dictionary)->bool:return e.kind=="wolf")
	for e in sources:e.hp=10000;e.attack=1
	var observed:=false;var sample:Dictionary={}
	for seed_value in 256:
		var model:=SoloEncounter.new();model.start(sources);model.rng.seed=seed_value;model.engine.rng.seed=seed_value
		var area:Dictionary=SkillRules.list_for(1,3,60).filter(func(s:Dictionary)->bool:return s.active and s.target=="all_enemies")[0]
		model.submit("skill","m0",area.id)
		var hits:Array=model.state.events.filter(func(e:Dictionary)->bool:return e.actor==model.character_id and e.action=="skill")
		if hits.any(func(e:Dictionary)->bool:return e.missed) and hits.any(func(e:Dictionary)->bool:return not e.missed and int(e.damage)>0):
			check(hits.filter(func(e:Dictionary)->bool:return e.missed).all(func(e:Dictionary)->bool:return int(e.damage)==0 and not e.critical),"A missed AoE target has its own zero-damage flag")
			check(hits.filter(func(e:Dictionary)->bool:return int(e.damage)>0).all(func(e:Dictionary)->bool:return not e.missed),"One target's miss cannot contaminate later successful targets")
			sample=model.state.duplicate(true)
			for event in sample.events:
				if event.actor==model.character_id:event.actor=SELF
				if event.target==model.character_id:event.target=SELF
			sample.id=EPOCH;sample.fighters[0].id=SELF;observed=true;break
	check(observed,"Real local area attacks expose both hit and miss outcomes")
	check(OnlineTeamModel.valid_battle(sample,SELF,{SELF:true}),"Authoritative per-target miss metadata validates")
	var invalid:=sample.duplicate(true);invalid.events[0].missed="yes"
	check(not OnlineTeamModel.valid_battle(invalid,SELF,{SELF:true}),"Non-boolean miss metadata is rejected")
	invalid=sample.duplicate(true);invalid.events[0].missed=true;invalid.events[0].damage=9
	check(not OnlineTeamModel.valid_battle(invalid,SELF,{SELF:true}),"A damaging direct hit cannot also be a dodge")
	var legacy:=sample.duplicate(true)
	for event in legacy.events:event.erase("missed")
	check(OnlineTeamModel.valid_battle(legacy,SELF,{SELF:true}),"Existing battle snapshots remain compatible")
	var flags:=SkillRules.new_state(1,3,60);flags.last_missed=true;flags.last_enemy_missed=true
	check(SkillRules.valid_state(flags),"Optional miss flags coexist with legacy skill states")
	SkillRules.reset_turn(flags);check(not flags.has("last_missed") and not flags.has("last_enemy_missed"),"Miss flags reset each turn")
	flags.last_critical=true;SkillRules.miss(SkillRules.item("sheet_010"),flags,Game.stats(),int(Game.stats().mp))
	check(flags.last_missed and not flags.get("last_critical",false),"A missed skill cannot inherit the previous target critical flag")
	flags.last_missed="bad";check(not SkillRules.valid_state(flags),"Malformed legacy miss flag is rejected")
	Game.player=old;Game.save_path=path
	print("DODGE RULES: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
