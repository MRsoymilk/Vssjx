class_name SkillBalance
extends RefCounted
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/skill-balance-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/skill-balance-v1.json").sha256_text()
static func revised(stats:Dictionary)->bool:return int(stats.get("balance",{}).get("skills_revision",0))>=1
static func kind(skill:Dictionary)->String:
	if skill.effect in ["sleep","silence"]:return "control"
	if skill.effect in ["bleed","poison"]:return "dot"
	if int(skill.damage_percent)==0:return "support"
	return "aoe" if skill.target=="all_enemies" else "single"
static func cost(skill:Dictionary,_stats:Dictionary)->int:
	return int(skill.mp_cost)
static func cooldown(skill:Dictionary,stun_enabled:bool=true)->int:
	return int(skill.stun.cooldown) if stun_enabled and skill.has("stun") else int(rules.cooldowns[kind(skill)])
static func coefficient(skill:Dictionary,targets:int=1)->int:
	if int(skill.damage_percent)==0:return 0
	var raw:int=rules.get({"dot":"dot_direct_bp","aoe":"aoe_bp","control":"control_direct_bp"}.get(kind(skill),"single_bp"))
	return int(CombatBalance.aoe_coefficient(raw,clampi(targets,1,5)).value) if skill.target=="all_enemies" else raw
static func recovery(stats:Dictionary,key:String,legacy:int=0)->int:
	return maxi(1,int(stats.mp)*int(rules[key])/10000) if revised(stats) else legacy
static func potion(stats:Dictionary)->int:return maxi(45,int(stats.hp)*int(rules.potion_restore_bp)/10000) if revised(stats) else 45
static func monster(definition:Dictionary)->Dictionary:
	var d:=definition.duplicate(true);d.defense=int(d.defense)*int(rules.monster_defense_multiplier)
	if d.kind=="boss" or d.id=="boss":d.hp=int(d.hp)*int(rules.boss_hp_multiplier)
	return d
static func monster_magical(d:Dictionary,round:int,mp:int,silenced:bool)->bool:
	return not silenced and mp>=10 and round%int(rules.cast_period)==0 and rules.magic_art_prefixes.any(func(prefix:String)->bool:return String(d.art).begins_with(prefix))
