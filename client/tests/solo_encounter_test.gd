extends "res://tests/online_pve_test.gd"
func _run()->void:
	await Game.when_ready()
	var previous:=Game.player.duplicate(true);var previous_path:=Game.save_path
	Game.save_path="user://solo_encounter_%d.json"%OS.get_process_id()
	Game.new_player("阵列验证",1,3);Game.player.level=60;Game.restore()
	var pool:=SharedWorldMap.population("qingyun_trail").filter(func(d:Dictionary)->bool:return d.kind!="npc")
	for roll in [0,60,99]:
		var group:=MonsterCombat.formation(pool[0],pool,roll)
		check(group.size()==MonsterCombat.solo_count(roll),"Roll selects the requested solo encounter size")
		var ids:={}
		for d in group:check(not ids.has(d.id) and d.kind!="npc","Reinforcements are distinct current-map monsters");ids[d.id]=true
	check(MonsterCombat.formation(pool[0],[pool[0]],99).size()==3,"A map with one ordinary template can still supply independent reinforcements")
	check(MonsterCombat.formation({"id":"boss","kind":"boss","level":3},[],99).size()==1,"An isolated boss never duplicates itself")
	var sources:Array=pool.slice(0,3).duplicate(true)
	for d in sources:d.hp=10000
	var local:=SoloEncounter.new();local.start(sources);local.engine.rng.seed=12;local.rng.seed=12
	check(local.battle().enemies.size()==3 and local.my_turn(),"Local encounter exposes three independent enemies")
	var healthy_hp:=local.engine.hp;local.engine.hp=1
	check(local.auto_command().action=="potion","Local auto battle retains emergency healing")
	local.engine.hp=healthy_hp
	check(local.submit("attack","m2"),"A chosen non-primary monster can be attacked")
	check(local.state.events.filter(func(e:Dictionary)->bool:return e.actor==local.character_id and e.action=="attack" and e.target!="m2").is_empty(),"Single target never directly damages other enemies")
	check(local.state.events.filter(func(e:Dictionary)->bool:return e.actor==local.character_id and e.action=="attack" and e.target=="m2").size()==1,"Player result points to the selected enemy")
	check(local.state.events.filter(func(e:Dictionary)->bool:return String(e.actor).begins_with("m")).size()==3,"Each living ordinary monster acts once")
	var area:Dictionary=SkillRules.list_for(1,3,60).filter(func(s:Dictionary)->bool:return s.active and s.target=="all_enemies")[0]
	var mp:=local.engine.mp
	check(local.submit("skill","m0",area.id),"Area skill is accepted against a formation")
	check(local.engine.mp==mp-SkillBalance.cost(area,local.engine.frozen_stats),"Area skill pays MP once for all monsters")
	check(local.state.events.filter(func(e:Dictionary)->bool:return e.skill==area.id).size()==3,"Area skill emits one hit per living target")
	var revision:int=local.state.revision
	check(not local.submit("skill","m0",area.id) and int(local.state.revision)==revision,"Cooldown rejection does not advance the round")
	local.state.enemies[0].hp=0
	check(not local.submit("attack","m0"),"A dead target cannot be attacked")
	var boss:Dictionary=SharedWorldMap.population("ancient_ruins").filter(func(d:Dictionary)->bool:return d.id=="boss")[0].duplicate(true);boss.hp=10000
	var boss_group:=SoloEncounter.new();boss_group.start([boss,pool[0]])
	check(int(boss_group.state.enemies[0].hp)+int(boss_group.state.enemies[1].hp)==int(ProgressionRules.monster(SkillBalance.monster(boss)).hp),"Boss reinforcements share the same revised single-player HP budget")
	var observed:={}
	for seed_value in 100:
		var strong:=SoloEncounter.new();strong.start([boss]);strong.rng.seed=seed_value;strong.engine.rng.seed=seed_value;strong.submit("guard")
		for event in strong.state.events:
			if event.actor=="m0":observed[event.skill]=true
			if event.actor=="m0" and event.critical:observed.critical=true
		if not strong.state.wounds.is_empty():
			check(int(strong.state.wounds[strong.character_id][0])==2,"Bleeding ticks once at the first complete round end")
			strong.state.enemies[0].effects.enemy_sleep=3
			strong.submit("guard");strong.submit("guard")
			check(strong.state.wounds.is_empty(),"Local bleeding expires after three complete rounds")
			observed.bleeding=true
		if observed.has_all(["monster_combo","monster_sweep","monster_rend","critical","bleeding"]):break
	check(observed.has_all(["monster_combo","monster_sweep","monster_rend","critical","bleeding"]),"Local strong monsters use all specials and critical strikes")
	# Read the same validated formation through the online adapter and retry outbox.
	var group:Dictionary=local.state.duplicate(true);group.id=EPOCH;group.fighters[0].id=SELF
	for event in group.events:
		if event.actor==local.character_id:event.actor=SELF
		if event.target==local.character_id:event.target=SELF
	group.enemies[0].hp=1;group.outcome="active"
	var snapshot:=pve_state();snapshot.stats=local.engine.frozen_stats.duplicate(true)
	snapshot.character.merge({"job":1,"level":60,"school":3,"hp":local.engine.hp,"mp":local.engine.mp},true)
	snapshot.battle={"id":EPOCH,"revision":"0","round":0,"enemy":group.enemies[0].definition,"enemy_hp":1,"hp":local.engine.hp,"mp":local.engine.mp,"potions":local.engine.potions,"outcome":"active","skill_rules_version":1,"skills":local.engine.skills.duplicate(true),"formation":group}
	var remote:=OnlinePve.new();remote.bind_character(SELF,"http://127.0.0.1:9999");OnlineAccount.pending_pve={}
	check(remote.valid(snapshot),"Online validator accepts a bounded solo formation")
	check(remote.receive({"type":"pve.state","state":snapshot}),"Online formation can be installed")
	var adapter:=SoloEncounter.new();adapter.attach(remote);adapter.display_ready=true
	check(adapter.battle().enemies.size()==3 and not adapter.battle().has("commands"),"Solo presentation does not inherit the team's shared wait window")
	check(adapter.submit("attack","m2"),"Online selection submits through the existing PVE outbox")
	check(OnlineAccount.pending_pve.command.enemy_slot=="m2" and OnlineAccount.pending_pve.command.battle_id==EPOCH,"Outbox carries target slot and frozen battle revision")
	OnlineAccount.pending_pve={}
	var invalid:=snapshot.duplicate(true);invalid.battle.formation.wounds={SELF:[4,10]}
	check(not remote.valid(invalid),"Malformed wound duration is rejected")
	invalid=snapshot.duplicate(true);invalid.battle.formation.fighters[0].hp+=1
	check(not remote.valid(invalid),"Conflicting outer and formation HP is rejected")
	invalid=snapshot.duplicate(true);invalid.battle.formation=null
	check(not remote.valid(invalid),"Null formation is rejected without accessing missing properties")
	# Actual game entry and presentation, with current art and all three hit targets.
	var app:Control=load("res://scenes/main.tscn").instantiate();add_child(app);app.set_process(false);app._enter_world();app._start_local_encounter(sources)
	var view:Control=app.local_encounter_view;view.set_process(false)
	check(app.mode=="local_encounter" and view.visible and view.actors.size()==4,"Local game enters the shared pixel battle view with three enemies")
	check(view.menu.visible and view.auto_button.size==Vector2(72,20) and view.auto_button.position.x==124,"Original commands open directly with one compact centered auto control")
	check(view.auto_button.text=="自动战斗","Auto button label omits the keyboard shortcut")
	view._toggle_auto();check(view.auto_button.text=="手动战斗","Active auto mode shows a short manual label");view._toggle_auto()
	view.actors.m2.hit.pressed.emit();check(view.selected=="m2" and view.menu.visible,"Clicking an enemy selects it and opens commands")
	var sound:Array=[];view.effects.audio_played.connect(func(id:String)->void:sound.append(id))
	view.queue=[{"actor":app.local_encounter.character_id,"target":"m1","action":"skill","skill":"sheet_010","damage":7,"healed":0,"critical":false,"packet":1}]
	view._play({"actor":app.local_encounter.character_id,"target":"m0","action":"skill","skill":"sheet_010","damage":7,"healed":0,"critical":false,"packet":1})
	view.motion.advance(view.motion.impact_time)
	check(sound==["thunder"],"A multi-target cast plays its sound only once")
	view.motion.advance(view.motion.duration);view._process(0)
	check(view._effect_wait=="sheet_010" and view.action_buttons[0].disabled,"Native FX tail still locks the next action")
	view._cancel();view._play({"actor":"m0","target":app.local_encounter.character_id,"action":"skill","skill":"monster_combo","damage":15,"healed":0,"critical":true,"packet":2})
	view.motion.advance(view.motion.impact_time)
	check(view.effects._critical_flash!=null and view.effects._numbers.size()>0,"Monster critical hits reuse the damage numbers and screen flash")
	if DisplayServer.get_name()!="headless":
		view._cancel();view._process(0);await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://../work/solo-formation.png")
	app._home();app.queue_free();await get_tree().process_frame
	var online_app:Control=load("res://scenes/main.tscn").instantiate();add_child(online_app);online_app._enter_online_world(SELF)
	var online:OnlineWorldView=online_app.ui.get_node("OnlineWorld");online.network.set_process(false);online.network.stream=EPOCH;online.network.world_ready=true;online.network._pve_version=1
	online.network.pve.bind_character(SELF,"http://127.0.0.1:9999");online.network.entities={SELF:entity(SELF,1,"昆仑客",1,0,[10,16])};online.network.changed.emit(online.network.entities);online.network.population.receive(residents_packet())
	check(online.network.pve.receive({"type":"pve.state","state":snapshot}),"Real online world accepts a formation snapshot")
	check(await wait_until(func()->bool:return online.solo_battle.visible),"Online world prepares all actors before opening the formation")
	check(not online.battle_view.visible and online.solo_battle.actors.size()==4,"Formation view replaces the legacy single-enemy view")
	online.solo_battle.actors.m2.hit.pressed.emit();online.solo_battle._choose("attack")
	check(OnlineAccount.pending_pve.command.enemy_slot=="m2","Online world sends the clicked target to the authority")
	OnlineAccount.pending_pve={};online_app._home();online_app.queue_free();await get_tree().process_frame
	# Victory applies each distinct resident's rewards once and saves to an isolated path.
	Game.new_player("结算验证",0,3);Game.player.level=60;Game.restore()
	var easy:Array=pool.slice(0,3).duplicate(true)
	for d in easy:d.hp=1;d.defense=0
	var winner:=SoloEncounter.new();winner.start(easy);winner.engine.rng.seed=5
	var before_gold:=int(Game.player.gold);var expected:=0
	for d in easy:expected+=int(d.gold)
	for turn in 10:
		if not winner.active():break
		for e in winner.state.enemies:
			if int(e.hp)>0:winner.submit("attack",e.slot);break
	while winner.saving:await get_tree().process_frame
	check(winner.state.outcome=="victory" and int(Game.player.gold)==before_gold+expected,"Only a whole-encounter victory pays every defeated resident")
	winner._commit();check(int(Game.player.gold)==before_gold+expected,"Repeated presentation cannot pay rewards twice")
	check(winner.save_result!=null and winner.save_result.ok,"Formation outcome is saved locally")
	Game.new_player("同种增援",0,3);Game.player.level=60;Game.player.quest=1;Game.restore()
	var same:=SoloEncounter.new();same.start([easy[0],easy[0],easy[0]]);before_gold=int(Game.player.gold)
	for turn in 12:
		if not same.active():break
		for e in same.state.enemies:
			if int(e.hp)>0:same.submit("attack",e.slot);break
	while same.saving:await get_tree().process_frame
	check(same.state.outcome=="victory" and int(Game.player.gold)==before_gold+int(easy[0].gold)*3,"Same-template reinforcements each pay their own reward")
	check(int(Game.player.kills)==1 and Game.player.defeated.size()==1,"Resident task progress is deduplicated for same-template reinforcements")
	Game.new_player("阵列战败",0,3);Game.player.hp=1
	var lethal:Dictionary=boss.duplicate(true);lethal.attack=5000
	var loser:=SoloEncounter.new();loser.start([lethal]);loser.rng.seed=1;before_gold=int(Game.player.gold)
	for turn in 10:
		if not loser.active():break
		loser.submit("guard")
	while loser.saving:await get_tree().process_frame
	check(loser.state.outcome=="defeat" and Game.is_soul(),"Formation defeat enters the existing soul and corpse recovery rules")
	check(int(Game.player.gold)==before_gold,"Defeat cannot award partial monster rewards")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.save_path))
	Game.player=previous;Game.save_path=previous_path
	print("SOLO ENCOUNTER: %d checks, %d failures"%[checks,failures]);get_tree().quit(0 if failures==0 else 1)
