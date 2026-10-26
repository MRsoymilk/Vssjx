extends RefCounted
## Compare item contributions, not a prediction of final character damage.
const PERCENT := ["hp_percent","crit_damage","penetration","damage","dot","reduction"]
const ORDER := ["power","defense","hp","mana","hp_percent","crit","hit","evasion","crit_damage","penetration","damage","dot","reduction"]

static func values(entry: Dictionary) -> Dictionary:
	var result: Dictionary={}
	if entry.is_empty():return result
	var base:Array=LootRules.base(entry.instance) if entry.has("instance_id") else [int(entry.get("attack",0)),int(entry.get("defense",0)),0,0]
	for i in 4:result[ORDER[i]]=int(base[i])
	for affix in entry.get("instance",{}).get("affixes",[]):result[affix.kind]=int(result.get(affix.kind,0))+int(affix.value)
	return result

static func format_value(kind: String, value: int) -> String:
	if kind in PERCENT:return "%.2f%%"%(value/100.0)
	return str(value)

static func rows(current: Dictionary, selected: Dictionary, job: int) -> Array:
	var left:=values(current);var right:=values(selected);var result:Array=[]
	var before_score:=LootRules.entry_score(current);var after_score:=LootRules.entry_score(selected)
	var score_delta:=after_score-before_score
	result.append({"kind":"score","label":"装备评分","current":before_score,"selected":after_score,"delta":score_delta,"change":"无变化" if score_delta==0 else ("增加" if score_delta>0 else "减少")+str(absi(score_delta))})
	for kind in ORDER:
		var before:=int(left.get(kind,0));var after:=int(right.get(kind,0))
		if before==0 and after==0:continue
		var label:String=LootRules.rules.affix_names[kind]
		if kind=="power":label="法术攻击" if job==2 else "物理攻击"
		var delta:=after-before
		var change:="无变化" if delta==0 else ("增加" if delta>0 else "减少")+("%.2f个百分点"%(absi(delta)/100.0) if kind in PERCENT else str(absi(delta)))
		result.append({"kind":kind,"label":label,"current":before,"selected":after,"delta":delta,"change":change})
	return result

static func special(entry: Dictionary) -> String:
	var instance:Dictionary=entry.get("instance",{})
	var id:Variant=instance.get("legendary") if instance.get("legendary")!=null else instance.get("set_id")
	if id==null:return ""
	var build:Dictionary=BuildRules.rules.items[BuildRules.index(id)]
	if instance.get("legendary")!=null:return build.legend_name+"："+build.description
	return build.name+"\n2件："+BuildRules.two_text(build)+"\n4件："+build.description
