class_name MonsterCombat
extends RefCounted
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster-combat-v1.json"))
static func strong(d:Dictionary)->bool:return d.id=="boss" or int(d.level)>=int(rules.strong_level) or d.kind in rules.strong_kinds
static func solo_count(roll:int)->int:
	for i in rules.solo_counts.size():
		if posmod(roll,100)<int(rules.solo_counts[i]):return i+1
	return 3
static func plan(d:Dictionary,roll:int,magical:bool,silenced:bool)->Dictionary:
	var p:Dictionary={"skill":"","hits":1,"all":false,"magical":magical,"coefficient":10000,"bleed":false}
	if not strong(d):return p
	roll=posmod(roll,100)
	if roll<int(rules.combo_chance):p.merge({"skill":"monster_combo","hits":2,"coefficient":int(rules.combo_bp),"magical":false},true)
	elif roll<int(rules.combo_chance)+int(rules.sweep_chance) and not silenced:p.merge({"skill":"monster_sweep","all":true,"coefficient":int(rules.sweep_bp)},true)
	elif roll<int(rules.combo_chance)+int(rules.sweep_chance)+int(rules.rend_chance):p.merge({"skill":"monster_rend","coefficient":int(rules.rend_bp),"bleed":true,"magical":false},true)
	return p
static func critical(d:Dictionary,damage:int,roll:int)->Dictionary:
	var crit:=damage>0 and posmod(roll,100)<int(rules.strong_crit if strong(d) else rules.normal_crit)
	return {"damage":damage*int(rules.crit_bp)/10000 if crit else damage,"critical":crit}
static func action_name(id:String)->String:return {"monster_combo":"疾风连击","monster_sweep":"横扫千军","monster_rend":"撕裂重击"}.get(id,"攻击")
static func formation(primary:Dictionary,pool:Array,roll:int)->Array:
	var chosen:Array=[primary.duplicate(true)]
	var candidates:=pool.filter(func(d:Dictionary)->bool:return d.kind!="npc" and d.id!=primary.id and d.kind!="boss" and absi(int(d.level)-int(primary.level))<=3)
	candidates.shuffle()
	for d in candidates:
		if chosen.size()>=solo_count(roll):break
		chosen.append(d.duplicate(true))
	var reinforcements:Array=candidates.duplicate()
	if primary.kind!="boss":reinforcements.append(primary)
	while chosen.size()<solo_count(roll) and not reinforcements.is_empty():chosen.append(reinforcements.pick_random().duplicate(true))
	return chosen

static func pressure_valid(v:Variant)->bool:
	if not v is Dictionary:return false
	if v.is_empty():return true
	if v.size()!=3 or not v.get("map") is String or not v.get("species") is String or not OnlinePve.integer(v.get("count"),0,int(rules.hunt_threshold)):return false
	return v.map.length()<=64 and v.species.length()<=128 and ((v.map.is_empty() and v.species.is_empty()) if int(v.count)==0 else (not v.map.is_empty() and not v.species.is_empty()))
static func note_pressure(v:Dictionary,map_id:String,species:String)->Dictionary:
	var count:=int(v.get("count",0)) if v.get("map")==map_id and v.get("species")==species else 0
	return {"map":map_id,"species":species,"count":mini(int(rules.hunt_threshold),count+1)}
static func elite_n(party:int,key:String)->int:return int(rules.elite_party[key] if party>1 else rules.elite_solo[key])
static func empower(d:Dictionary,party:int)->Dictionary:
	var result:=d.duplicate(true)
	var extra:=100+25*(party-1) if party>1 and d.kind!="boss" and d.id!="boss" else 100
	result.hp=clampi(int(d.hp)*elite_n(party,"hp_bp")*extra/1000000,1,100000)
	result.attack=clampi(int(d.attack)*elite_n(party,"attack_bp")/10000,1,100000)
	result.defense=clampi(int(d.defense)*elite_n(party,"defense_bp")/10000,0,100000)
	return result
static func elite_valid(v:Variant,party:int)->bool:
	return v is Dictionary and v.size()==2 and OnlinePve.integer(v.get("party_size"),party,party) and OnlinePve.integer(v.get("revives_left"),0,elite_n(party,"revives"))
static func elite_plan(e:Dictionary,roll:int,magical:bool,silenced:bool)->Dictionary:
	if not e.has("elite"):return plan(e.definition,roll,magical,silenced)
	var combo:=posmod(roll,100)<elite_n(int(e.elite.party_size),"combo_chance")
	return {"skill":"monster_combo" if combo else "monster_sweep","hits":elite_n(int(e.elite.party_size),"hits") if combo else 1,"all":not combo and not silenced,"magical":not combo and magical and not silenced,"coefficient":elite_n(int(e.elite.party_size),"combo_bp") if combo else 10000,"bleed":true}
static func elite_critical(e:Dictionary,damage:int,roll:int)->Dictionary:
	if not e.has("elite"):return critical(e.definition,damage,roll)
	var crit:=damage>0 and posmod(roll,100)<elite_n(int(e.elite.party_size),"crit")
	return {"damage":damage*elite_n(int(e.elite.party_size),"crit_bp")/10000 if crit else damage,"critical":crit}
static func enemy_name(e:Dictionary)->String:return ("精英·" if e.has("elite") else "")+String(e.definition.name)
