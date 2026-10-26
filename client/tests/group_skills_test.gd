extends Node
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func encounter(job:int,skill:String,count:int)->SoloEncounter:
	Game.new_player("群攻验证",job,3);Game.player.level=60;Game.restore()
	Game.player.skill_proficiency={skill:99}
	var enemies:Array=[]
	for i in count:enemies.append({"id":"group_probe_%d"%i,"name":"训练目标","art":"monster/langw","kind":"wolf","level":1,"hp":100000,"attack":1,"defense":1,"gold":0,"xp":0})
	var local:=SoloEncounter.new();local.start(enemies);local.rng.seed=12;local.engine.rng.seed=12
	return local
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://group_skills_%d.json"%OS.get_process_id()
	var skill:="user_shuanglong_xizhu"
	for count in [1,2,5]:
		var local:=encounter(2,skill,count)
		var mp:=local.engine.mp
		var primary:="m%d"%(count-1)
		check(local.submit("skill",primary,skill),"Dragons can be submitted against %d enemies"%count)
		var events:Array=local.state.events.filter(func(e:Dictionary)->bool:return e.actor==local.character_id and e.skill==skill)
		check(events.size()==mini(2,count) and events[0].target==primary,"Two-enemy cap preserves primary target")
		if count>1:check(events[1].target=="m0","Second target is the next living enemy")
		check(local.engine.mp==mp-15,"Group pays fixed MP only once")
		check(Game.player.skill_proficiency[skill]==100,"Group trains once, including across rank boundary")
		check(events.all(func(e:Dictionary)->bool:return int(e.get("skill_level",0))==6),"Every target uses the same frozen effect stage")
		check(int(local.engine.skills.balance.targets)==mini(2,count),"Damage budget uses the actual target count")
		for enemy in local.state.enemies:
			if not events.any(func(e:Dictionary)->bool:return e.target==enemy.slot):check(enemy.hp==enemy.definition.hp,"Other enemies receive no damage")
	var local:=encounter(2,skill,5);local.state.enemies[0].hp=0
	var revision:int=local.state.revision
	check(not local.submit("skill","m0",skill) and int(local.state.revision)==revision,"Dead primary is rejected without advancing")
	check(local.submit("skill","m4",skill),"Valid primary still casts with a dead enemy present")
	var targets:Array=local.state.events.filter(func(e:Dictionary)->bool:return e.skill==skill).map(func(e:Dictionary)->String:return e.target)
	check(targets==["m4","m1"],"Dead enemies never consume a target slot")
	check(local.submit("skill","m4",skill),"Same skill remains available in the next round")
	check(SkillRules.check(skill,2,3,24)=="SKILL_LEVEL_REQUIRED","New skill unlocks at character level 25")
	for spec in [["user_hengsao_qianjun",0],["sheet_004",1]]:
		local=encounter(spec[1],spec[0],5)
		var mp:=local.engine.mp
		check(local.submit("skill","m4",spec[0]),"Existing full group skill is accepted")
		var events:Array=local.state.events.filter(func(e:Dictionary)->bool:return e.skill==spec[0])
		check(events.size()==5,"Full group skill reaches all five living enemies")
		check(local.engine.mp==mp-int(SkillRules.item(spec[0]).mp_cost),"Full group skill pays only once")
		check(Game.player.skill_proficiency[spec[0]]==100,"Full group trains once for five targets")
		check(events.all(func(e:Dictionary)->bool:return int(e.get("skill_level",0))==6),"All five targets use rank six")
	for rank in [1,5,6,9,10,14,15]:
		check(BattleEffects.binding(skill,rank).layers==BattleEffects.binding("sheet_045",rank).layers,"Dragons uses exact Paishan effect at rank %d"%rank)
	var book:SkillBook=load("res://scenes/ui/skill_book.tscn").instantiate();add_child(book)
	local=encounter(2,skill,2);book.present(Game.player,true)
	var index:=book.items.find_custom(func(s:Dictionary)->bool:return s.id==skill)
	check(index>=0,"Mage skill book contains Dragons")
	book.select_skill(index)
	check(book.detail.text.contains("最多命中2个敌人") and book.detail.text.contains("每个目标威力80%"),"Skill book explains target limit and per-enemy power")
	book.queue_free();Game.player=old;Game.save_path=path
	print("GROUP SKILLS: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
