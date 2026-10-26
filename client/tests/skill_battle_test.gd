extends "res://tests/online_pve_test.gd"

func _run()->void:
	output=OS.get_environment("SSJX_SKILL_CAPTURE_PATH")
	var old:=Game.player.duplicate(true)
	var old_path:=Game.save_path
	Game.save_path="user://skill_battle_%d.json"%OS.get_process_id()
	for skill in SkillRules.catalog.items:
		Game.new_player("技能验证",int(skill.job),maxi(0,int(skill.school)))
		Game.player.level=60;Game.player.hp=100;Game.player.mp=200
		var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
		var battle:=ShushanBattle.new(opponent)
		var start:=battle.begin_action("skill",skill.id)
		check(start.ok==bool(skill.active),"Active/passive local eligibility "+skill.id)
		if not start.ok:
			check(battle.round_number==0 and battle.mp==200,"Passive rejection never consumes a turn")
			continue
		battle.resolve_player()
		if battle.phase=="enemy":battle.resolve_enemy()
		battle.finish_round()
		check(battle.pending_skill==skill.id and battle.skills.last_skill==skill.id,"Named skill resolves in local encounter "+skill.id)
		check(battle.round_number==1 and battle.phase=="select" and battle.mp>=0,"Exactly one bounded local turn "+skill.id)
	Game.new_player("菜单验证",0,2)
	Game.player.level=60;Game.player.hp=100;Game.player.mp=200
	check(Game.valid_save(Game.player),"Level 60 local save accepted")
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app._enter_world()
	var opponent:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);opponent.hp=10000;opponent.attack=1
	app._start_battle(opponent)
	app._battle_skills()
	var picker:SkillPicker=app.modal.get_child(app.modal.get_child_count()-1)
	check(picker.choices.size()==13,"Local picker includes every active skill of the job across all schools")
	await capture("local-skills")
	picker.activate("sheet_011")
	var home:Vector2=app.battle_hero.position
	await get_tree().create_timer(0.4).timeout
	check(app.battle_hero.position==home,"Reflection skill casts in place without approaching enemy")
	var deadline:=Time.get_ticks_msec()+6000
	while app.battle.phase!="select" and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	check(app.battle.skills.last_skill=="sheet_011" and app.battle.skills.reflect_physical==1,"Selected support skill applies two-turn reflection")
	var attributes:OriginalCharacterAttributes=load("res://scenes/ui/character_attributes.tscn").instantiate();app.ui.add_child(attributes);attributes.select_tab(2)
	var book:SkillBook=attributes.content.get_node("SkillBook")
	check(book.rows.get_child_count()==13 and book.rows.get_child(0).get_node("Rank").text=="1/15","Native skill list shows actual proficiency ranks")
	book.select_skill(1)
	var expected_cost:="消耗灵力12点 · 冷却2轮" if book.balanced else "消耗灵力12"
	check(book.detail.text.contains("反伤") and book.detail.text.contains(expected_cost),"Selecting a row shows its versioned cost and cooldown in the separate description")
	check(attributes.get_node("Label5").text=="人物技能" and not attributes.signature.visible,"Skill page uses original title and replaces signature footer")
	check(book.get_node("Upgrade").disabled and book.get_node("NextInfo").disabled,"Unrecovered growth actions cannot invent points or upgrade levels")
	await capture("skill-attributes")
	attributes.select_tab(3)
	book=attributes.content.get_node("SkillBook")
	check(book.items.size()==2 and book.items[0].name=="霸王卸甲" and book.detail.text.contains("已生效"),"Inner page shows both physical and magical reflection passives separately")
	await capture("inner-attributes")
	Game.new_player("资料核对",1,0)
	Game.player.level=50;Game.restore()
	attributes.display_local();attributes.select_tab(2)
	book=attributes.content.get_node("SkillBook")
	check(book.items.size()==10 and not book.get_node("Coverage").visible,"Level 50 Emei knight sees every known job skill instead of an empty school list")
	check(book.get_node("Provenance").text.contains("50级") and book.get_node("Provenance").text.contains("已解锁9项"),"Skill book displays actual character level and unlocked count")
	book.select_skill(1)
	var selected:Button=book.rows.get_child(1)
	check(selected.get_theme_stylebox("hover")==selected.get_theme_stylebox("normal") and selected.get_theme_stylebox("pressed")==selected.get_theme_stylebox("normal") and selected.tooltip_text.is_empty(),"Selection retains the dark fill under hover/press without an obstructing rank tooltip")
	await capture("emei-knight-level50")
	attributes.display_online({"job":1,"school":0,"level":50},{})
	attributes.select_tab(2)
	book=attributes.content.get_node("SkillBook")
	check(book.items.size()==10 and book.get_node("Provenance").text.contains("门派不限"),"Online skill book uses the same school-independent job list")
	attributes.display_online({"job":1,"school":2,"level":50},{})
	attributes.select_tab(2)
	book=attributes.content.get_node("SkillBook")
	check(book.items.size()==10 and book.get_node("Provenance").text.contains("已解锁9项") and not book.get_node("Coverage").visible,"Level 50 knight keeps level 55 skill locked alongside the added skill")
	attributes.display_online({"job":1,"school":3,"level":50},{})
	attributes.select_tab(2)
	book=attributes.content.get_node("SkillBook")
	check(book.items.size()==10 and book.get_node("Provenance").text.contains("已解锁9项"),"Unjoined skill book shares exactly the same job list")
	book.select_skill(8)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check(book.selected_index==8 and book.get_node("SkillCatalog").scroll_vertical>0,"Longer cross-school list scrolls to keep the selected last skill visible")
	attributes.display_local()
	attributes.select_tab(0)
	check(attributes.signature.visible and attributes.get_node("Label5").text=="人物属性","Returning to properties restores the signature and title")
	attributes.queue_free()
	app._home();app.queue_free();await get_tree().process_frame
	var model:=OnlinePve.new();model.bind_character(SELF,"http://127.0.0.1:9999")
	var state:=pve_state();state.character.job=1;state.character.school=1;state.character.level=60
	state.skills={"version":"skills-v1","catalog_sha256":SkillRules.catalog_hash,"available":SkillRules.list_for(1,1,60).map(func(s:Dictionary)->String:return s.id)}
	state.battle={"id":PEER,"revision":"1","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3}}
	check(model.receive({"type":"pve.state","state":state}),"Skill capability snapshot accepted at level 60")
	var forged:=state.duplicate(true);forged.skills.available.append("sheet_011")
	check(not model.valid(forged),"Foreign skill in available list rejected")
	forged=state.duplicate(true);forged.skills.catalog_sha256="bad"
	check(not model.valid(forged),"Mismatched numeric catalog fails validation")
	var view:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(view)
	var packets:Array=[];model.send_requested.connect(func(packet:Dictionary)->void:packets.append(packet))
	view.skill_requested.connect(func(id:String)->void:model.submit("skill",id))
	view.present(model);view.choose("skill")
	check(view.skill_picker.visible and not view.get_node("Choice").visible,"Online named skill selection replaces old single-skill confirmation")
	await capture("online-skills")
	view.skill_picker.activate("sheet_051")
	check(packets.size()==1 and packets[0].command.target=="sheet_051" and packets[0].command.battle_id==PEER and packets[0].command.expected_revision=="1","Chosen skill carries battle ID, revision and skill ID")
	OnlineAccount.pending_pve={}
	var sleeping:=state.duplicate(true);sleeping.character.state_revision="2";sleeping.battle.revision="2";sleeping.battle.skill_rules_version=1;sleeping.battle.skills=SkillRules.new_state(1,1,60);sleeping.battle.skills.last_skill="sheet_051";sleeping.battle.skills.last_damage=30;sleeping.battle.skills.enemy_sleep=1;sleeping.battle.enemy_hp=970
	model.last_action="skill";model.state=sleeping;view.present(model)
	check(not view._should_enemy_act(),"Sleeping enemy cannot play an attack animation")
	view._cancel_motion();view.queue_free();Game.player=old;Game.save_path=old_path
	print("SKILL BATTLE: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
