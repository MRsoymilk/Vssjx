class_name SkillProficiency
extends RefCounted
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/skill-proficiency-v1.json"))
static func level(progress:Dictionary,id:String)->int:
	return mini(int(rules.max_level),1+int(progress.get(id,0))/int(rules.casts_per_level))
static func stage(rank:int)->int:
	return 3 if rank>=15 else 2 if rank>=10 else 1 if rank>=6 else 0
static func record(progress:Dictionary,id:String)->int:
	var skill:=SkillRules.item(id)
	if not skill.is_empty() and skill.active:
		progress[id]=mini((int(rules.max_level)-1)*int(rules.casts_per_level),int(progress.get(id,0))+1)
	return level(progress,id)
static func valid(progress:Variant,job:int=-1,character_level:int=60)->bool:
	if not progress is Dictionary or progress.size()>SkillRules.catalog.items.size():return false
	for id in progress:
		if not id is String or not OnlinePve.integer(progress[id],0,(int(rules.max_level)-1)*int(rules.casts_per_level)):return false
		var skill:=SkillRules.item(id)
		if skill.is_empty() or not skill.active or (job>=0 and not SkillRules.eligible(skill,job,0,character_level)):return false
	return true
