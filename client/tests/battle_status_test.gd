extends "res://tests/team_test.gd"
func ids(rows:Array)->Array:return rows.map(func(r:Dictionary)->String:return r.id)
func _run()->void:
	await Game.when_ready()
	var old:=Game.player.duplicate(true);var saved:=OnlineAccount.pending_team.duplicate(true);OnlineAccount.pending_team={}
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BattleStatusStrip.CATALOG_PATH))
	check(catalog.original_binding_recovered==false,"Authored status mapping is not represented as recovered original rules")
	for icon in catalog.icons.values():
		check(FileAccess.get_sha256(icon.texture)==icon.decoded_sha256,"Runtime icon bytes match the original decoded frame")
	var state0:=SkillRules.new_state(1,3,60);state0.enemy_poison=3;state0.enemy_bleed=2;state0.enemy_sleep=1;state0.defense=2
	check(ids(BattleStatusStrip.fighter(state0,[2,5]))==["bleed","defense"],"Caster-side harmful fields never appear on the PVE caster")
	check(ids(BattleStatusStrip.harmful(state0,{}))==["sleep"],"Empty authoritative DOT map clears stale legacy counters")
	var dot_rows:=BattleStatusStrip.harmful(state0,{SELF+"/poison":[1,5],OTHER+"/poison":[3,7]})
	check(dot_rows.size()==2 and dot_rows[0].id=="poison" and dot_rows[0].turns==3,"Independent DOT sources combine by longest duration without duplicate icons")
	var model:=OnlineTeamModel.new();model.bind_character(SELF);var b:=encounter();b.wounds={SELF:[2,8]}
	b.fighters[0].effects=state0;b.fighters[1].effects.regen=1
	b.enemies[0].effects=state0.duplicate(true);b.enemies[0].dots={SELF+"/poison":[3,7]}
	b.enemies[1].effects.enemy_silence=2;b.enemies[2].effects.enemy_bleed=1
	model.state=state(b);model.server_time=10000;model.received_at=Time.get_ticks_msec()
	var chrome:Control=load("res://scenes/ui/battle_chrome.tscn").instantiate();chrome.use_local_player=false;add_child(chrome)
	var view:Control=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present();view._process(0)
	var mine:BattleStatusStrip=view.actors[SELF].status;var enemy:BattleStatusStrip=view.actors.m0.status
	check(ids(mine.entries)==["bleed","defense"] and ids(enemy.entries)==["poison","sleep"],"Actual shared view assigns wounds, buffs and target debuffs to correct actors")
	mine.buttons[0].pressed.emit();view._process(0)
	check(view.hint.text.contains("流血") and view.hint.text.contains("2回合"),"Tapping a badge shows its name and remaining rounds")
	var hero:Dictionary=view.actors[SELF];var before:Vector2=mine.position;hero.sprite.position.x+=12;view._refresh_actor_anchors()
	check(is_equal_approx(mine.position.x,before.x+12),"Status strip follows the rendered body during movement")
	hero.sprite.position=hero.home;view._refresh_actor_anchors()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../work/battle-status-party.png")
	var final:=b.duplicate(true);final.revision=1;final.enemies[0].effects.enemy_sleep=0;final.enemies[0].dots={};final.events=[{"actor":SELF,"target":"m0","action":"attack","skill":"","damage":1,"healed":0,"critical":false}]
	model.state=state(final);view.present()
	check(ids(enemy.entries)==["poison","sleep"],"Resolved packet cannot remove statuses ahead of queued action playback")
	view._process(0);view._process(2);view._process(0)
	check(enemy.entries.is_empty() and not enemy.visible,"Expired statuses disappear after the authoritative round is presented")
	var all:=state0.duplicate(true)
	for key in ["regen","crit","reflect_physical","reflect_magic"]:all[key]=2
	mine.set_statuses(BattleStatusStrip.fighter(all,[2,8]));check(mine.entries.size()==6 and mine.buttons.size()==3,"Many statuses occupy at most three compact slots")
	mine.buttons[2].pressed.emit();check(mine.page==2,"Overflow advances to the next pair of statuses")
	mine.buttons[2].pressed.emit();check(mine.page==4,"Overflow can reach the final statuses without resetting early")
	mine.buttons[-1].pressed.emit();check(mine.page==0,"Final status page returns to the first page")
	hero.dead=true;view._refresh_actor_anchors();check(not mine.visible,"Dead combatant hides persistent status badges")
	view.queue_free();await get_tree().process_frame
	view=load("res://scenes/ui/team_battle_view.tscn").instantiate();view.model=model;add_child(view);view.set_process(false);view.present();view._process(0)
	check(ids(view.actors[SELF].status.entries)==["bleed","defense"] and view.actors[SELF].status.entries[0].turns==2 and view.actors.m0.status.entries.is_empty(),"Fresh presentation restores remaining statuses from the current snapshot without replaying stale DOTs")
	view.queue_free();chrome.queue_free();await get_tree().process_frame
	var fixture=load("res://tests/online_pve_test.gd").new();var pve:=OnlinePve.new();pve.character_id=fixture.SELF;pve.ready=true
	var snapshot:Dictionary=fixture.pve_state();snapshot.battle={"id":BATTLE,"revision":"0","round":0,"outcome":"active","hp":95,"mp":45,"potions":6,"enemy_hp":1000,"enemy":{"id":"wolf_a","name":"山狼","art":"monster/langw","level":1,"hp":1000,"attack":13,"defense":3},"skill_rules_version":1,"skills":state0}
	pve.state=snapshot
	var online:OnlineBattleView=load("res://scenes/ui/online_battle_view.tscn").instantiate();add_child(online);online.set_process(false);online.present(pve);online.refresh()
	check(ids(online.status_hero.entries)==["defense"] and ids(online.status_enemy.entries)==["bleed","poison","sleep"],"Legacy PVE also separates own buffs from outgoing debuffs")
	online.queue_free();await get_tree().process_frame
	var duel:DuelBattleView=load("res://scenes/ui/duel_battle_view.tscn").instantiate();add_child(duel);duel.set_process(false);duel.present(pve)
	duel.opponent={"effects":{"enemy_silence":2,"regen":1}}
	var duel_rows:Array=duel._status_sources()
	check(ids(duel_rows[0])==["silence","defense"] and ids(duel_rows[1])==["bleed","poison","sleep","regen"],"Duel harmful fields are read from the opposing caster, buffs from self")
	duel.queue_free();fixture.free();await get_tree().process_frame
	check(Game.player==old,"Status presentation cannot change saved character data")
	OnlineAccount.pending_team=saved
	await get_tree().create_timer(0.25).timeout
	print("BATTLE STATUS: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
