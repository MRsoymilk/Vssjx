extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	for id in ["sheet_015","sheet_037","sheet_006","sheet_042","sheet_008"]:
		for targets in [1,2,5]:check(SkillBalance.coefficient(SkillRules.item(id),targets)==30000,"Three-hundred-percent override applies at every target count")
	for modern in [false,true]:
		var stats:Dictionary=CharacterAttributeRules.balanced_stats(1,60,false,[0,0,0,0,0]) if modern else {"hp":10000,"mp":1000,"attack":137,"defense":5}
		var state:=SkillRules.new_state(1,3,60);state.last_skill="sheet_008"
		var criticals:=0
		for roll in 10000:
			if CharacterAttributeRules.critical_at(stats,false,state,100,roll)>100:criticals+=1
		check(criticals==7000,"Wanjian has exactly seventy percent critical rolls")
		SkillRules.reset_turn(state)
		check(CharacterAttributeRules.critical_at(stats,false,state,100,6999)==100,"Wanjian critical chance does not leak to normal attacks")
		for defense in [0,100000]:
			state=SkillRules.new_state(1,3,60)
			SkillRules.cast(SkillRules.item("sheet_052"),state,stats,int(stats.hp),int(stats.mp),defense,99)
			check(state.poison_fixed and int(state.poison_damage)==int(stats.attack),"Poison tick equals the caster attack without defense scaling")
			var tail:=SkillRules.end_balance_round(state,int(stats.hp),int(stats.hp)) if modern else SkillRules.after_player(state,int(stats.hp),int(stats.hp))
			check(int(tail.damage)==int(stats.attack),"Actual poison tick deals exactly own attack")
	for id in ["sheet_039","sheet_041"]:
		for maximum in [10000,20000]:
			var state:=SkillRules.new_state(2,3,60)
			var cast:=SkillRules.cast(SkillRules.item(id),state,{"hp":maximum,"mp":1000,"attack":137},1,1000,0,99)
			check(cast.hp==138 and state.last_healed==137 and state.regen==0,"Healing is immediate, attack-based, and independent of max HP")
	for job in 3:
		for skill in SkillRules.list_for(job,3,60):
			if not skill.active:continue
			var state:=SkillRules.new_state(job,3,60);SkillRules.enable_stun(state,CharacterAttributeRules.balanced_stats(job,60,false,[0,0,0,0,0]));state.balance.cooldowns[skill.id]=3
			check(SkillBalance.cooldown(skill)==0 and SkillRules.remaining(state,skill.id)==0,"Saved cooldown never blocks a skill")
	var state:=SkillRules.new_state(0,3,60)
	for magical in [false,true]:
		check(SkillRules.enemy_hit(state,1,137,magical)==Vector2i(1,137),"Both Lishi passives reflect exactly own physical attack")
		SkillRules.cast(SkillRules.item("sheet_033" if magical else "sheet_011"),state,{"hp":10000,"mp":1000,"attack":137},1,1000,0,99)
		check(SkillRules.enemy_hit(state,1,137,magical)==Vector2i(1,137),"Active and passive reflection do not stack")
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://skill_rebalance_%d.json"%OS.get_process_id()
	Game.new_player("技能验证",2,3);Game.player.level=60;Game.restore()
	var enemy:Dictionary={"id":"rebalance_probe","name":"训练目标","art":"monster/langw","kind":"wolf","level":1,"hp":100000,"attack":1,"defense":1,"gold":0,"xp":0}
	var local:=SoloEncounter.new();local.start([enemy,enemy.duplicate(true),enemy.duplicate(true)])
	local.engine.skills.balance.cooldowns.sheet_045=3
	var mp:=local.engine.mp
	for round in 2:
		check(local.submit("skill","m2","sheet_045"),"Paishan can cast in consecutive rounds despite old saved cooldown")
		check(local.state.events.filter(func(e:Dictionary)->bool:return e.skill=="sheet_045").size()==3,"Paishan reaches the entire living enemy group")
	check(local.engine.mp==mp-24 and Game.player.skill_proficiency.sheet_045==2,"Consecutive group casts each cost once and train once")
	Game.new_player("万剑验证",1,3);Game.player.level=60;Game.restore()
	var book:SkillBook=load("res://scenes/ui/skill_book.tscn").instantiate();add_child(book);book.present(Game.player,true)
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_008"))
	check(book.detail.text.contains("300%") and book.detail.text.contains("70%") and not book.detail.text.contains("240%"),"Skill book shows actual Wanjian damage and critical chance")
	check(book.get_node("CombatMeta").text.contains("无冷却"),"Skill book explains removed cooldown")
	book.queue_free();Game.player=old;Game.save_path=path
	print("SKILL REBALANCE: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
