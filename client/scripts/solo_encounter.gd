class_name SoloEncounter
extends RefCounted
## Common presentation model: remote results are read-only, local rules use frozen stats.
signal changed
signal message(text:String)
var character_id:="00000000-0000-4000-8000-000000000001"
var server_time:=0
var received_at:=0
var pve:OnlinePve
var state:Dictionary={}
var engine:ShushanBattle
var sources:Array=[]
var committed:=false
var saving:=false
var save_result:PlatformResult
var display_ready:=true
var _remote_id:=""
var rng:=RandomNumberGenerator.new()
const ENEMY_FIELDS:=["enemy_mp","enemy_bleed","bleed_damage","enemy_poison","poison_damage","enemy_sleep","enemy_silence"]
func attach(remote:OnlinePve)->void:
	pve=remote;character_id=pve.character_id;pve.changed.connect(_remote_changed);_remote_changed()
func _remote_changed()->void:
	character_id=pve.character_id
	var id:String=pve.state.get("battle",{}).get("id","") if pve.state.get("battle") is Dictionary else ""
	if id!=_remote_id:display_ready=false;_remote_id=id
	server_time=pve.server_time_ms();received_at=Time.get_ticks_msec();changed.emit()
func presentation_ready()->bool:return display_ready
func connected()->bool:return pve==null or pve.ready
func battle()->Dictionary:
	if pve!=null:
		var b:Dictionary=pve.state.get("battle",{}) if pve.state.get("battle") is Dictionary else {}
		if not b.get("formation") is Dictionary:return {}
		var copy:Dictionary=b.formation.duplicate(true);copy.erase("commands");copy.solo=true
		if b.has("endless"):copy.endless=b.endless.duplicate(true)
		return copy
	return state
func party()->Dictionary:return {"leader":true}
func active()->bool:return battle().get("outcome")=="active"
func pending()->bool:return not pve.ready or pve.pending() if pve!=null else saving
func can_submit()->bool:return not pending()
func my_turn()->bool:return active() and can_submit()
func auto_command()->Dictionary:
	if pve==null:
		if engine.hp<int(engine.frozen_stats.hp)/3 and engine.potions>0:return {"action":"potion","skill":""}
		var id:=engine.selected_skill
		if not id.is_empty() and engine.mp>=SkillBalance.cost(SkillRules.item(id),engine.frozen_stats) and SkillRules.remaining(engine.skills,id)==0:return {"action":"skill","skill":id}
	return {"action":"attack","skill":""}
func start(opponents:Array,elite:bool=false,endless:Dictionary={})->void:
	sources=opponents.duplicate(true);rng.randomize();engine=ShushanBattle.new(sources[0])
	var enemies:Array=[]
	for i in sources.size():
		var d:Dictionary=ProgressionRules.monster(SkillBalance.monster(sources[i])) if engine.frozen_stats.has("balance") else sources[i].duplicate(true)
		var effects:=SkillRules.new_state(0,3,1,int(d.level));SkillRules.activate(effects,engine.frozen_stats)
		enemies.append({"slot":"m%d"%i,"definition":d,"hp":int(d.hp),"effects":effects})
	if engine.frozen_stats.has("balance"):
		for e in enemies:
			if e.definition.kind=="boss" or e.definition.id=="boss":
				var budget:=int(e.hp);var total:=0
				for other in enemies:total+=int(other.hp)
				var left:=budget
				for i in enemies.size():
					var allotted:=left if i==enemies.size()-1 else int(enemies[i].hp)*budget/total
					enemies[i].hp=maxi(1,allotted);enemies[i].definition.hp=enemies[i].hp;left-=allotted
				break
	if elite:
		enemies[0].definition=MonsterCombat.empower(enemies[0].definition,1);enemies[0].hp=enemies[0].definition.hp
		enemies[0].elite={"party_size":1,"revives_left":MonsterCombat.elite_n(1,"revives")}
	var f:Dictionary={"id":character_id,"name":Game.player.name,"job":Game.player.job,"gender":Game.player.gender,"school":Game.player.school,"level":Game.player.level,"appearance":LootRules.look(Game.player.get("loot_state",{}),ShopRules.appearance(ShopRules.local_state(Game.player))),"stats":engine.frozen_stats,"hp":engine.hp,"mp":engine.mp,"potions":engine.potions,"effects":engine.skills}
	state={"id":"local-%d"%Time.get_ticks_usec(),"solo":true,"fighters":[f],"enemies":enemies,"turn":0,"round":1,"revision":0,"events_revision":0,"deadline_ms":0,"outcome":"active","events":[],"lines":[],"wounds":{},"monster_revision":2 if elite else 1}
	if not endless.is_empty():state.endless=endless.duplicate(true)
	if elite:state.lines.append("同图同种怪连续挑战达到5场，精英现身！警惕连击、暴击、流血与妖躯复生。")
	_sync()
func _sync()->void:
	var f:Dictionary=state.fighters[0];f.hp=engine.hp;f.mp=engine.mp;f.potions=engine.potions;f.effects=engine.skills
	server_time=int(Time.get_unix_time_from_system()*1000);received_at=Time.get_ticks_msec();state.deadline_ms=server_time+30000
func _copy_enemy(from:Dictionary,to:Dictionary)->void:
	for key in ENEMY_FIELDS:to[key]=from[key]
	if int(from.get("enemy_stun",0))>0:to.enemy_stun=int(from.enemy_stun)
	else:to.erase("enemy_stun")
	if from.has("balance") and to.has("balance"):to.balance.control_protection=from.balance.control_protection
func _event(actor:String,target:String,action:String,skill:String,damage:int=0,healed:int=0,critical:bool=false,missed:bool=false)->void:
	state.events.append({"actor":actor,"target":target,"action":action,"skill":skill,"damage":damage,"healed":healed,"critical":critical,"missed":missed})
func submit(action:String,target:String="",skill:String="")->bool:
	if not my_turn():return false
	if pve!=null:return pve.submit(action,skill,[],1,target if action in ["attack","skill"] else "")
	if action not in ["attack","skill","guard","potion","flee"]:return false
	var selected:Dictionary={}
	for e in state.enemies:
		if e.slot==target and int(e.hp)>0:selected=e;break
	if action in ["attack","skill"] and selected.is_empty():return false
	if selected.is_empty():
		for e in state.enemies:
			if int(e.hp)>0:selected=e;break
	engine.enemy=selected.definition;engine.enemy_hp=int(selected.hp);engine.phase="select";engine.finished=false
	_copy_enemy(selected.effects,engine.skills)
	var begun:=engine.begin_action(action,skill)
	if not begun.ok:message.emit("\n".join(PackedStringArray(begun.lines)));return false
	state.events=[];state.lines=begun.lines.duplicate()
	var used:=SkillRules.item(skill)
	var targets:Array=state.enemies.filter(func(e:Dictionary)->bool:return int(e.hp)>0) if action=="skill" and used.get("target")=="all_enemies" else [selected]
	if engine.skills.has("balance"):engine.skills.balance.targets=state.enemies.filter(func(e:Dictionary)->bool:return int(e.hp)>0).size()
	for i in targets.size():
		var e:Dictionary=targets[i];engine.enemy=e.definition;engine.enemy_hp=int(e.hp);engine.phase="player";engine.finished=false
		_copy_enemy(e.effects,engine.skills)
		if i>0:engine.mp+=SkillBalance.cost(used,engine.frozen_stats)
		var old_hp:=engine.hp
		var resolved:=engine.resolve_player();state.lines.append_array(resolved.lines);e.hp=engine.enemy_hp;_copy_enemy(engine.skills,e.effects)
		var receiver:String=character_id if action in ["guard","potion"] or used.get("target") in ["self","all_allies"] else e.slot
		_event(character_id,receiver,action,skill,int(resolved.get("direct_damage",engine.skills.last_damage)),maxi(0,engine.hp-old_hp),engine.skills.get("last_critical",false),engine.skills.get("last_missed",false))
		var dot:=maxi(0,int(engine.skills.last_damage)-int(resolved.get("direct_damage",engine.skills.last_damage)))
		if dot>0:_event(character_id,e.slot,"dot","",dot)
	if action!="flee":_revive_fallen()
	if action=="flee":state.outcome="fled"
	elif state.enemies.all(func(e:Dictionary)->bool:return int(e.hp)==0):state.outcome="victory"
	else:_enemy_round()
	state.round+=1;state.revision+=1;state.events_revision=state.revision
	if state.outcome=="active" and int(state.round)>30:state.outcome="fled"
	engine.phase="select";_sync();changed.emit()
	if not active():_commit()
	return true
func _enemy_round()->void:
	for e in state.enemies:
		if int(e.hp)<=0 or engine.hp<=0:continue
		if SkillRules.consume_stun(e.effects):
			state.lines.append("%s处于眩晕，跳过本次行动。"%e.definition.name)
			_event(e.slot,e.slot,"stun","")
			continue
		if int(e.effects.enemy_sleep)>0:state.lines.append("%s处于睡眠，无法行动。"%e.definition.name);continue
		var magical:=SkillBalance.monster_magical(e.definition,int(state.round),int(e.effects.enemy_mp),int(e.effects.enemy_silence)>0)
		var plan:=MonsterCombat.elite_plan(e,rng.randi_range(0,99),magical,int(e.effects.enemy_silence)>0)
		if plan.magical:e.effects.enemy_mp=int(e.effects.enemy_mp)-10
		for hit in int(plan.hits):
			if int(e.hp)<=0 or engine.hp<=0:break
			var landed:=rng.randi_range(0,9999)<CharacterAttributeRules.hit_chance({},engine.frozen_stats,plan.magical)
			var raw:=CharacterAttributeRules.incoming(int(e.definition.attack),int(e.definition.level),engine.frozen_stats,plan.magical,0)*int(plan.coefficient)/10000 if landed else 0
			var crit:=MonsterCombat.elite_critical(e,raw,rng.randi_range(0,99));var damage:=int(crit.damage)
			if engine.guarding and landed:damage=maxi(1,damage/2)
			var taken:=SkillRules.enemy_hit(engine.skills,maxi(1,damage),int(engine.frozen_stats.attack),plan.magical) if landed else Vector2i.ZERO
			var reflected:=mini(int(e.hp),taken.y+(6 if landed and int(Game.player.job)==0 and engine.guarding else 0))
			damage=mini(engine.hp,taken.x);engine.hp-=damage;e.hp=int(e.hp)-reflected
			_event(e.slot,character_id,"skill" if not plan.skill.is_empty() else "attack",plan.skill,damage,0,crit.critical,not landed)
			if reflected>0:_event(character_id,e.slot,"dot","",reflected)
			if plan.bleed and damage>0 and engine.hp>0:
				var previous:Array=state.wounds.get(character_id,[0,0]);state.wounds[character_id]=[int(MonsterCombat.rules.bleed_rounds),maxi(int(previous[1]),maxi(1,taken.x*int(MonsterCombat.rules.bleed_bp)/10000))]
			state.lines.append("%s%s，造成%d点伤害%s。"%[e.definition.name,MonsterCombat.action_name(plan.skill),damage,"（暴击）" if crit.critical else ""])
	var before:=engine.hp
	var after:=SkillRules.end_balance_round(engine.skills,engine.hp,int(engine.frozen_stats.hp));engine.hp=int(after.hp)
	if engine.hp>before:_event(character_id,character_id,"regen","",0,engine.hp-before)
	if state.wounds.has(character_id) and engine.hp>0:
		var wound:Array=state.wounds[character_id];var damage:=mini(engine.hp,int(wound[1]));engine.hp-=damage;wound[0]=int(wound[0])-1
		_event(character_id,character_id,"dot","monster_bleed",damage)
		if int(wound[0])==0:state.wounds.erase(character_id)
	SkillRules.end_turn(engine.skills)
	for e in state.enemies:
		var tail:=SkillRules.end_balance_round(e.effects,0,0);var damage:=mini(int(e.hp),int(tail.damage));e.hp=int(e.hp)-damage
		if damage>0:_event(e.slot,e.slot,"dot","",damage)
		SkillRules.end_turn(e.effects)
	_revive_fallen()
	if engine.hp==0:state.outcome="defeat"
	elif state.enemies.all(func(e:Dictionary)->bool:return int(e.hp)==0):state.outcome="victory"
func _revive_fallen()->void:
	if engine.hp<=0:return
	for e in state.enemies:
		if int(e.hp)==0:e.effects.erase("enemy_stun")
		if int(e.hp)==0 and e.has("elite") and int(e.elite.revives_left)>0:
			e.elite.revives_left=int(e.elite.revives_left)-1
			e.hp=maxi(1,int(e.definition.hp)*MonsterCombat.elite_n(int(e.elite.party_size),"revive_bp")/10000)
			e.effects=SkillRules.new_state(0,3,1,int(e.definition.level));SkillRules.activate(e.effects,engine.frozen_stats)
			_event(e.slot,e.slot,"revive","monster_rebirth",0,int(e.hp))
			state.lines.append("%s妖躯复生，剩余%d次复活。"%[MonsterCombat.enemy_name(e),int(e.elite.revives_left)])
func _commit()->void:
	if committed:return
	committed=true;saving=true
	Game.player.hp=engine.hp;Game.player.mp=engine.mp;Game.player.potions=engine.potions
	if state.outcome=="victory":
		if state.enemies[0].has("elite"):
			var pressure:Dictionary=Game.player.get("hunt_pressure",{})
			if pressure.get("map")==AIWorld.local_map_id() and pressure.get("species")==sources[0].art and int(pressure.get("count",0))==int(MonsterCombat.rules.hunt_threshold):Game.player.hunt_pressure={}
		var gold:=0;var xp:=0;var recorded:={}
		for d in sources:
			gold+=int(d.gold);xp+=int(d.xp)
			if state.has("endless"):Game.add_rewards(int(d.gold),int(d.xp))
			elif not recorded.has(d.id):Game.finish_enemy(d);recorded[d.id]=true
			else:Game.add_rewards(int(d.gold),int(d.xp))
		state.lines.append("战斗胜利！获得%d铜钱、%d修为。"%[gold,xp])
		var loot_sources:Array=sources.duplicate(true)
		if state.enemies[0].has("elite"):loot_sources[0].kind="boss"
		state.lines.append(Game.award_loot(loot_sources,rng.randi()))
	elif state.outcome=="defeat":Game.become_soul()
	if state.has("endless"):
		var done:=EndlessRules.finish(Game.player.endless_state,state.endless,state.outcome=="victory")
		assert(done,"Endless settlement must match the saved character run")
		state.lines.append("无尽第%d层已通过，下次挑战第%d层；最高已过%d层。"%[int(state.endless.stage),int(Game.player.endless_state.stage),int(Game.player.endless_state.best)] if state.outcome=="victory" else "本轮无尽试炼结束，下次从第1层开始；最高已过%d层。"%int(Game.player.endless_state.best))
	save_result=await Game.save_game();saving=false
	if not save_result.ok:state.lines.append("保存未确认："+save_result.message)
	message.emit("\n".join(PackedStringArray(state.lines)));changed.emit()
