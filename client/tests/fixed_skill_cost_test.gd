extends Node
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _ready() -> void:
	await Game.when_ready()
	for skill in SkillRules.catalog.items:
		for max_mp in [35,400,800,1000000]:
			var stats := CharacterAttributeRules.balanced_stats(int(skill.job),60,false,[0,0,0,0,0])
			stats.mp=max_mp
			check(SkillBalance.cost(skill,stats)==int(skill.mp_cost),"Fixed cost independent of maximum mana: "+skill.id)
		if skill.active:check(800/int(skill.mp_cost)>400/int(skill.mp_cost),"Mana growth grants more casts: "+skill.id)
	var stats := CharacterAttributeRules.balanced_stats(0,60,false,[0,0,0,0,0])
	var state := SkillRules.new_state(0,3,60)
	var solid := SkillRules.item("sheet_012")
	var cast := SkillRules.cast(solid,state,stats,int(stats.hp),int(stats.mp),0,99)
	check(cast.hp==stats.hp and cast.mp==int(stats.mp)-15,"Solid guard spends exactly 15 MP without self damage")
	check(state.defense==2 and state.defense_percent==0 and state.defense_flat==25,"Solid guard installs fixed protection")
	check(SkillRules.valid_state(state),"Fixed shield validates on the wire")
	var fixture_path := OS.get_environment("SSJX_FIXED_SKILL_FIXTURE")
	if not fixture_path.is_empty():
		var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
		var model:=OnlinePve.new();model.character_id=fixture.character.id
		check(model.valid(fixture),"Actual server snapshot with fixed protection validates")
	var invalid := state.duplicate(true);invalid.defense_flat=-25
	check(not SkillRules.valid_state(invalid),"Negative shield cannot turn into extra damage")
	for round_index in 2:
		for magical in [false,true]:
			for raw in [0,1,24,25,26,100,10000,2147483647]:
				check(SkillRules.enemy_hit(state,raw,int(stats.attack),magical).x==maxi(0,raw-25),"Fixed shield reduces physical and magical hits")
		SkillRules.end_turn(state)
	check(SkillRules.enemy_hit(state,100,int(stats.attack)).x==100,"Shield expires after two rounds")
	var other: Dictionary=SkillRules.catalog.items.filter(func(s:Dictionary)->bool:return s.effect=="defense" and s.id!="sheet_012")[0]
	SkillRules.cast(other,state,stats,int(stats.hp),int(stats.mp),0,99)
	check(not state.has("defense_flat") and SkillRules.enemy_hit(state,100,int(stats.attack)).x==100-int(other.value),"Other defense skill keeps its existing effect and replaces the shield")
	var book: SkillBook=load("res://scenes/ui/skill_book.tscn").instantiate();add_child(book)
	book.present({"job":0,"school":3,"level":60,"balance_revision":1},true)
	book.select_skill(book.items.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_012"))
	check(book.detail.text.contains("抵挡25点") and book.detail.text.contains("消耗灵力15点") and not book.detail.text.contains("最大灵力"),"Skill book explains actual fixed cost and protection")
	var picker:=SkillPicker.new();add_child(picker);picker.present(0,3,60,14,[],false,stats,state)
	var index:=picker.choices.find_custom(func(s:Dictionary)->bool:return s.id=="sheet_012")
	check(picker.rows.get_child(index).get_node("Cost").text=="15","Picker shows the fixed cost")
	var submitted:=[];picker.chosen.connect(func(id:String)->void:submitted.append(id));picker.activate("sheet_012")
	check(submitted.is_empty(),"Insufficient mana is rejected at the same fixed threshold")
	picker.present(0,3,60,15,[],false,stats,{})
	picker.activate("sheet_012");check(submitted==["sheet_012"],"Exact fixed mana is enough")
	print("FIXED SKILL COST: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
