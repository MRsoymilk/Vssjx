extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error("STUN: "+message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	var thunder:=SkillRules.item("sheet_010")
	var stats:=CharacterAttributeRules.balanced_stats(0,60,false,[60,60,60,60,60])
	check(int(thunder.stun.chance)==35 and int(thunder.stun.actions)==1 and int(thunder.stun.cooldown)==0 and int(thunder.unlock_level)==5,"Only the existing level-five thunder skill gains the explicit authored effect")
	check(SkillBalance.kind(thunder)=="single" and SkillBalance.coefficient(thunder)==16000 and SkillBalance.cost(thunder,stats)==9,"Original damage coefficient and mana budget stay unchanged")
	var successful:=0
	for roll in 100:
		var effects:=SkillRules.new_state(0,3,60,1);SkillRules.enable_stun(effects,stats)
		var cast:=SkillRules.cast(thunder,effects,stats,int(stats.hp),int(stats.mp),20,roll)
		var count:=int(effects.get("enemy_stun",0));successful+=count
		check(count==(1 if roll<35 else 0) and cast.damage>0,"Exactly the first 35 of 100 effect rolls stun without changing damage")
		check(SkillRules.remaining(effects,thunder.id)==0,"Casting creates no cooldown")
		SkillRules.end_turn(effects)
		check(SkillRules.remaining(effects,thunder.id)==0 and int(effects.get("enemy_stun",0))==count,"Round end keeps cooldown zero and preserves the pending stun")
	check(successful==35,"Effect probability is exactly 35 percent")
	var effects:=SkillRules.new_state(0,3,60,1);SkillRules.activate(effects,stats)
	SkillRules.cast(thunder,effects,stats,int(stats.hp),int(stats.mp),20,0)
	check(not effects.has("enemy_stun") and SkillRules.remaining(effects,thunder.id)==0,"Old frozen battle remains readable without granting stun or cooldown")
	SkillRules.enable_stun(effects,stats);effects.balance.control_protection=0
	SkillRules.miss(thunder,effects,stats,int(stats.mp))
	check(not effects.has("enemy_stun") and effects.balance.control_protection==0,"Miss consumes mana without granting control or a cooldown")
	SkillRules.cast(thunder,effects,stats,int(stats.hp),int(stats.mp),20,0)
	SkillRules.cast(SkillRules.item("legacy_0"),effects,stats,int(stats.hp),int(stats.mp),20,0)
	check(effects.enemy_stun==1,"Follow-up direct damage does not wake a stunned target")
	for id in ["sheet_051","sheet_021"]:
		SkillRules.cast(SkillRules.item(id),effects,stats,int(stats.hp),int(stats.mp),20,0)
	check(effects.enemy_sleep==0 and effects.enemy_silence==0,"Stun shares protection with sleep and seal")
	var restored:Dictionary=JSON.parse_string(JSON.stringify(effects))
	check(SkillRules.valid_state(restored) and restored.enemy_stun==1 and SkillRules.stun_enabled(restored),"Snapshot roundtrip preserves the same pending stun and rules revision")
	check(SkillRules.consume_stun(restored) and not SkillRules.consume_stun(restored),"Exactly one action consumes the pending token")
	for invalid in [-1,2,0.5,"1",true]:
		var bad:=effects.duplicate(true);bad.enemy_stun=invalid
		check(not SkillRules.valid_state(bad),"Malformed stun counts are rejected")
	var bad:=effects.duplicate(true);bad.balance.stun_revision=2
	check(not SkillRules.valid_state(bad),"Unknown stun rules revisions are rejected")
	var old_player:=Game.player.duplicate(true);var old_path:=Game.save_path
	Game.save_path="user://stun_rules_%d.json"%OS.get_process_id();Game.new_player("眩晕验证",0,3);Game.player.level=60;Game.restore()
	var source:Dictionary=SharedWorldMap.population()[1].duplicate(true);source.hp=100000
	var observed:=false
	for seed_value in 100:
		var solo:=SoloEncounter.new();solo.start([source]);solo.engine.rng.seed=seed_value
		check(solo.submit("skill","m0","sheet_010"),"Actual local encounter accepts thunder")
		if solo.state.events.any(func(e:Dictionary)->bool:return e.action=="stun"):
			check(not solo.state.events.any(func(e:Dictionary)->bool:return e.actor=="m0" and e.action in ["attack","skill"]),"Actual solo target skips its whole action")
			check(int(solo.state.enemies[0].effects.get("enemy_stun",0))==0 and SkillRules.remaining(solo.engine.skills,"sheet_010")==0,"Local engine consumes target stun once without a cooldown")
			observed=true;break
	check(observed,"Observe an actual landed local stun through production combat")
	Game.player=old_player;Game.save_path=old_path
	print("STUN RULES: %d checks, %d failures"%[checks,failures]);get_tree().quit(1 if failures else 0)
