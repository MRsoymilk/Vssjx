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
	return chosen
