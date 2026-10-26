extends Node
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _ready()->void:_run.call_deferred()
func _run()->void:
	await Game.when_ready()
	var progress:Dictionary={}
	for used in range(1,402):
		var rank:=SkillProficiency.record(progress,"sheet_010")
		check(rank==mini(15,1+used/20),"Exact 20-cast advancement at %d"%used)
	check(progress.sheet_010==280,"Training is capped at rank 15")
	check(not SkillProficiency.valid({"sheet_010":281}),"Over-cap training rejected")
	check(not SkillProficiency.valid({"sheet_010":1},1,60),"Foreign job progress rejected")
	check(not SkillProficiency.valid({"sheet_010":1},0,1),"Locked skill progress rejected")
	var old:=Game.player.duplicate(true);var path:=Game.save_path
	Game.save_path="user://skill_proficiency_test_%d.json"%OS.get_process_id()
	Game.new_player("熟练修士",0,3);Game.player.level=60;Game.restore()
	Game.player.skill_proficiency={"sheet_010":99}
	var battle:=ShushanBattle.new({"id":"mastery_probe","name":"训练目标","art":"monster/langw","kind":"wolf","level":1,"hp":100000,"attack":1,"defense":1,"gold":0,"xp":0})
	check(battle.begin_action("skill","sheet_010").ok,"Real local battle accepts the trained skill")
	battle.resolve_player()
	check(Game.player.skill_proficiency.sheet_010==100 and battle.skills.last_skill_level==6,"One resolved cast reaches first stage")
	battle.resolve_player()
	check(Game.player.skill_proficiency.sheet_010==100,"Repeated local resolution cannot grant twice")
	check(BattleEffects.binding("sheet_010",battle.skills.last_skill_level).layers[0].art=="effect/t172","Real battle rank selects corrected native resource")
	check((await Game.save_game()).ok,"Training saves with the character")
	Game.player.skill_proficiency={}
	check((await Game.load_game()).ok and Game.player.skill_proficiency.sheet_010==100,"Training survives local reload")
	var old_save:=Game.player.duplicate(true);old_save.erase("skill_proficiency")
	old_save.erase("local_characters")
	check(Game.valid_save(old_save),"Existing saves without training remain loadable")
	var book:SkillBook=load("res://scenes/ui/skill_book.tscn").instantiate();add_child(book);book.present(Game.player,true)
	var row_index:=book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_010")
	book.select_skill(row_index)
	check(book.rows.get_child(row_index).get_node("Rank").text=="6/15" and book.detail.text.contains("1阶段特效"),"Skill book shows persistent rank and resource stage")
	book.queue_free();Game.player=old;Game.save_path=path
	print("SKILL PROFICIENCY: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
