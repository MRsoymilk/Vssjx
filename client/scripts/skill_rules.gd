class_name SkillRules
extends RefCounted
## Reference names/effect descriptions, with explicitly reconstructed battle values.
static var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/skills-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/skills-v1.json").replace("\r\n","\n").sha256_text()
static var _items:Dictionary={}
const TIMERS:=["defense","crit","reflect_physical","reflect_magic","enemy_sleep","enemy_silence"]

static func item(id:String)->Dictionary:
	if _items.is_empty():
		for skill in catalog.items:_items[skill.id]=skill
	return _items.get(id,{}).duplicate(true)

static func eligible(skill:Dictionary,job:int,school:int,level:int)->bool:
	return not skill.is_empty() and int(skill.job)==job and (int(skill.school)<0 or int(skill.school)==school) and level>=int(skill.unlock_level)

static func list_for(job:int,school:int,level:int,locked:bool=false)->Array:
	return catalog.items.filter(func(s:Dictionary)->bool:return int(s.job)==job and (int(s.school)<0 or int(s.school)==school) and (locked or level>=int(s.unlock_level)))

static func default_id(job:int,school:int,level:int)->String:
	for skill in list_for(job,school,level):
		if skill.active and int(skill.school)<0:return skill.id
	return "legacy_%d"%job

static func check(id:String,job:int,school:int,level:int)->String:
	var skill:=item(id)
	if skill.is_empty():return "INVALID_SKILL"
	if int(skill.job)!=job or (int(skill.school)>=0 and int(skill.school)!=school):return "SKILL_ROLE_MISMATCH"
	if level<int(skill.unlock_level):return "SKILL_LEVEL_REQUIRED"
	if not skill.active:return "PASSIVE_SKILL"
	return ""

static func new_state(job:int,school:int,level:int,enemy_level:int=1)->Dictionary:
	var state:Dictionary={"last_skill":"","last_enemy_acted":false,"enemy_mp":30+enemy_level*2}
	for key in ["enemy_bleed","bleed_damage","enemy_poison","poison_damage","enemy_sleep","enemy_silence","regen","regen_amount","defense","defense_percent","crit","crit_chance","reflect_physical","physical_percent","reflect_magic","magic_percent","passive_physical","passive_magic","last_damage","last_incoming","last_reflected","last_healed"]:state[key]=0
	for skill in list_for(job,school,level):
		if not skill.active:
			state["passive_magic" if skill.effect=="reflect_magic" else "passive_physical"]=int(skill.value)
	return state

static func reset_turn(state:Dictionary)->void:
	for key in ["last_damage","last_incoming","last_reflected","last_healed"]:state[key]=0
	state.last_enemy_acted=false;state.last_skill=""

static func critical(state:Dictionary,damage:int,roll:int)->int:
	return damage*3/2 if int(state.crit)>0 and roll<int(state.crit_chance) else damage

static func cast(skill:Dictionary,state:Dictionary,stats:Dictionary,hp:int,mp:int,enemy_defense:int,roll:int)->Dictionary:
	state.last_skill=skill.id
	mp-=int(skill.mp_cost)
	var damage:=maxi(1,int(stats.attack)*int(skill.damage_percent)/100-enemy_defense) if int(skill.damage_percent)>0 else 0
	var healed:=mini(int(skill.legacy_heal),int(stats.hp)-hp)
	hp+=healed
	var value:=int(skill.value);var duration:=int(skill.duration)
	# Direct damage wakes existing sleep before this action can apply new sleep.
	if damage>0:state.enemy_sleep=0
	match String(skill.effect):
		"bleed","poison":
			state["enemy_"+skill.effect]=duration
			state[skill.effect+"_damage"]=maxi(1,int(stats.attack)*value/100)
		"sleep","silence":
			if roll<int(skill.chance):state["enemy_"+skill.effect]=duration
		"regen":state.regen=duration;state.regen_amount=maxi(1,int(stats.hp)*value/100)
		"defense":state.defense=duration;state.defense_percent=value
		"crit":state.crit=duration;state.crit_chance=value
		"reflect_physical":state.reflect_physical=duration;state.physical_percent=value
		"reflect_magic":state.reflect_magic=duration;state.magic_percent=value
		"mana_steal":
			var stolen:=mini(value,int(state.enemy_mp));state.enemy_mp=int(state.enemy_mp)-stolen
			mp=mini(int(stats.mp),mp+stolen)
	state.last_healed=int(state.last_healed)+healed
	return {"damage":damage,"hp":hp,"mp":mp}

static func after_player(state:Dictionary,hp:int,max_hp:int)->Dictionary:
	var damage:=0
	for status in ["bleed","poison"]:
		if int(state["enemy_"+status])>0:
			damage+=int(state[status+"_damage"]);state["enemy_"+status]=int(state["enemy_"+status])-1
	if int(state.regen)>0:
		var healed:=mini(int(state.regen_amount),max_hp-hp)
		hp+=healed;state.last_healed=int(state.last_healed)+healed;state.regen=int(state.regen)-1
	return {"damage":damage,"hp":hp}

static func enemy_hit(state:Dictionary,incoming:int,magical:bool=false)->Vector2i:
	if int(state.defense)>0:incoming=maxi(1,incoming*(100-int(state.defense_percent))/100)
	var percent:=int(state.passive_magic if magical else state.passive_physical)
	if int(state.reflect_magic if magical else state.reflect_physical)>0:percent=maxi(percent,int(state.magic_percent if magical else state.physical_percent))
	return Vector2i(incoming,incoming*percent/100)

static func end_turn(state:Dictionary)->void:
	for key in TIMERS:state[key]=maxi(0,int(state[key])-1)

static func status_text(state:Dictionary)->String:
	var parts:Array[String]=[]
	for row in [["enemy_bleed","流血"],["enemy_poison","中毒"],["enemy_sleep","睡眠"],["enemy_silence","沉默"],["regen","回春"],["defense","护体"],["crit","暴击"],["reflect_physical","物反"],["reflect_magic","法反"]]:
		if int(state.get(row[0],0))>0:parts.append("%s%d"%[row[1],int(state[row[0]])])
	return " · ".join(parts)
