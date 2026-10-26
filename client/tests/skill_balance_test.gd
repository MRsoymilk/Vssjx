extends "res://tests/combat_balance_test.gd"
func _same(actual:Variant,expected:Variant)->bool:
	if actual is Dictionary and expected is Dictionary:
		if actual.size()!=expected.size():return false
		for key in expected:
			if not actual.has(key) or not _same(actual[key],expected[key]):return false
		return true
	if actual is Array and expected is Array:
		if actual.size()!=expected.size():return false
		for i in actual.size():
			if not _same(actual[i],expected[i]):return false
		return true
	return actual==expected
func _run()->void:
	await Game.when_ready();var old:=Game.player.duplicate(true);var path:=Game.save_path
	var vectors:=OS.get_environment("SSJX_BALANCE_SKILL_VECTORS")
	if not vectors.is_empty():
		for row in JSON.parse_string(FileAccess.get_file_as_string(vectors)):
			var skill:=SkillRules.item(row.id);var stats:Dictionary=row.stats
			var state:=SkillRules.new_state(int(skill.job),3,60,60);SkillRules.activate(state,stats);state.balance.targets=int(row.targets)
			var cast:=SkillRules.cast(skill,state,stats,100,int(stats.mp),240,0)
			var immediate:=SkillRules.after_player(state,int(cast.hp),int(stats.hp))
			var after:=SkillRules.end_balance_round(state,int(immediate.hp),int(stats.hp));SkillRules.end_turn(state)
			check(cast.damage==row.damage and cast.mp==row.mp and immediate.damage==row.immediate and after.damage==row.dot and after.hp==row.hp,"Actual Rust/Godot revised skill result: "+row.id)
			check(_same(state,row.state),"Actual full cooldown/status clock parity: "+row.id)
			check(SkillRules.valid_state(state)==bool(skill.active),"State accepts active skills and rejects impossible passive casts")
	Game.new_player("技能预算",1,3,0);Game.player.level=60;Game.player.allocated_attributes=[60,0,180,60,0];Game.restore()
	var enemy:Dictionary=ShushanWorld.ENEMIES[0].duplicate(true);enemy.hp=100000
	var battle:=ShushanBattle.new(enemy)
	var aoe:Dictionary=SkillRules.list_for(1,3,60).filter(func(s:Dictionary)->bool:return s.active and s.target=="all_enemies")[0]
	check(battle.begin_action("skill",aoe.id).ok,"Revised battle accepts its first area skill")
	battle.resolve_player();battle.resolve_enemy();battle.finish_round()
	var before_mp:=battle.mp;var before_round:=battle.round_number
	check(battle.begin_action("skill",aoe.id).ok and battle.mp==before_mp and battle.round_number==before_round+1,"Same skill can start again without a cooldown; cost is paid at resolution")
	var picker:=SkillPicker.new();add_child(picker);picker.present(1,3,60,battle.mp,[],false,battle.frozen_stats,battle.skills)
	var chosen:Array=[];picker.chosen.connect(func(id:String)->void:chosen.append(id));picker.activate(aoe.id)
	check(chosen==[aoe.id] and picker.description.text.contains("无冷却"),"Production skill picker permits consecutive casts")
	var output:=OS.get_environment("SSJX_BALANCE_CAPTURE")
	var server_fixtures:=OS.get_environment("SSJX_BALANCE_SKILL_FIXTURES")
	if not server_fixtures.is_empty():
		for snapshot in JSON.parse_string(FileAccess.get_file_as_string(server_fixtures)):
			var model:=OnlinePve.new();model.character_id=snapshot.character.id
			check(model.valid(snapshot),"Actual cooldown and magic-AI server snapshots validate")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		for frame in 3:await get_tree().process_frame
		RenderingServer.force_draw();check(get_viewport().get_texture().get_image().save_png(output)==OK,"Production skill picker renders actual mana costs and cooldown")
	picker.queue_free();await get_tree().process_frame;Game.player=old;Game.save_path=path
	print("SKILL BALANCE: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
