extends "res://tests/online_pve_test.gd"

func _run() -> void:
	AIWorld.prepare()
	var validator := OnlinePve.new()
	validator.character_id=SELF
	var arts := {}
	for m in AIWorld.maps.values():
		for r in m.residents:
			if r.kind=="npc": continue
			var state := pve_state()
			state.character.map_id=m.map_id
			state.battle={"id":SELF,"revision":"1","outcome":"active","round":1,"enemy":r.duplicate(true),"hp":95,"mp":45,"enemy_hp":r.hp,"potions":6}
			check(validator.valid(state),"Authoritative monster battle accepted: "+r.id)
			state.battle.enemy.hp+=1
			check(not validator.valid(state),"Cannot substitute monster stats: "+r.id)
			state.battle.enemy=r.duplicate(true)
			state.battle.enemy.art="monster/langw" if r.art!="monster/langw" else "monster/x1"
			check(not validator.valid(state),"Cannot substitute a different valid monster atlas: "+r.id)
			arts[r.art]=true
	check(arts.size()>=70,"Generated world actually uses varied original monster assets")
	for key in arts:
		var actor := OriginalArt.battle_actor(key)
		actor.position=Vector2(400,300)
		add_child(actor)
		for mode in ["idle","walk","attack","hurt"]:
			check(actor.sprite_frames.get_frame_count(mode)>0,"Native combat mode exists: "+key+" "+mode)
			actor.play(mode)
			for i in actor.sprite_frames.get_frame_count(mode):
				actor.frame=i
				check(actor.sprite_frames.get_frame_texture(mode,i).get_image()!=null,"Runtime atlas frame decodes: "+key)
		var action := BattleActionPlayback.new()
		action.start(actor,OriginalArt.actor_info(key),Vector2(100,300))
		action.advance(action.duration)
		check(not action.active and action.impacted and actor.position==Vector2(400,300),"Original attack resolves and returns home: "+key)
		actor.free()
	var progress := {"version":"ai-world-v1","catalog_sha256":AIWorld.catalog_hash,"completed":[],"completed_count":0,"active":{},"respawns":{}}
	for r in AIWorld.map_data("ai_087").residents:
		if r.kind!="npc":progress.respawns[r.id]=1000
	check(progress.respawns.size()==4 and AIWorld.valid_progress(progress,true),"All four table monsters retain independent network cooldowns")
	print("AI MONSTERS: %d checks, %d failures"%[checks,failures])
	get_tree().quit(1 if failures else 0)
