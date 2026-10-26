class_name BuildRules
extends RefCounted
## All procs read the encounter's frozen equipment snapshot, never live inventory.
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/builds-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/builds-v1.json").replace("\r\n","\n").sha256_text()
static func index(id:String)->int:
	for i in rules.items.size():
		if rules.items[i].id==id:return i
	return -1
static func compatible(id:String,job:int,slot:String,legendary:bool)->bool:
	var i:=index(id)
	return i>=0 and int(rules.items[i].job)==job and (rules.items[i].legend_slot==slot if legendary else slot in rules.set_slots)
static func snapshot()->Dictionary:return {"legendary":0,"sets":[0,0,0,0,0,0]}
static func tier(s:Dictionary,i:int)->int:return int((int(s.legendary)&(1<<i))!=0)+int(int(s.sets[i])>=4)
static func valid_snapshot(s:Variant)->bool:
	if not s is Dictionary or not ShopRules._integer(s.get("legendary"),0,63) or not s.get("sets") is Array or s.sets.size()!=6:return false
	var total:=0
	for value in s.sets:
		if not ShopRules._integer(value,0,4):return false
		total+=int(value)
	return total<=4
static func aggregate(loot:Dictionary,stats:Dictionary)->void:
	if not stats.has("balance"):return
	var s:=snapshot()
	for item in loot.get("items",[]):
		if not item.equipped or item.legacy:continue
		if item.get("legendary")!=null:s.legendary=int(s.legendary)|(1<<index(item.legendary))
		if item.get("set_id")!=null:s.sets[index(item.set_id)]+=1
	if int(s.legendary)==0 and s.sets==[0,0,0,0,0,0]:return
	stats.balance.builds=s
	for i in 6:
		if int(s.sets[i])<2:continue
		for kind in rules.items[i].two:
			var value:=int(rules.items[i].two[kind])
			match kind:
				"reduction":stats.balance.reduction_bp+=value
				"dot":stats.balance.dot_bp+=value
				"crit","hit":
					var key:="crit_bonus" if kind=="crit" else "hit_bonus"
					for channel in 2:stats.balance[key][channel]+=value
				"mana":stats.mp+=value
static func param(s:Dictionary,i:int,key:String)->int:
	var t:=tier(s,i)
	return 0 if t==0 else int(rules.items[i][key][t-1])
static func progress()->Dictionary:return {"charges":[0,0,0,0,0,0],"used":false,"bonus_bp":0,"dot_bp":0}
static func valid_progress(p:Variant)->bool:
	if not p is Dictionary or not p.get("charges") is Array or p.charges.size()!=6 or not p.get("used") is bool:return false
	for charge in p.charges:
		if not ShopRules._integer(charge,0,2):return false
	return ShopRules._integer(p.get("bonus_bp"),0,10000) and ShopRules._integer(p.get("dot_bp"),0,6000)
static func cast(skill:Dictionary,stats:Dictionary,state:Dictionary,hp:int,mp:int,damage:int,stolen:int,control_applied:bool)->Dictionary:
	var s:Dictionary=stats.get("balance",{}).get("builds",{})
	if s.is_empty():return {"hp":hp,"mp":mp,"damage":damage}
	if not state.has("builds"):state.builds=progress()
	var p:Dictionary=state.builds;var once:bool=not p.used;p.used=true
	var heal:=0;var refund:=0
	if once:
		if tier(s,0)>0:
			if skill.effect in ["defense","reflect_physical","reflect_magic"]:p.charges[0]=1
			elif damage>0 and int(p.charges[0])>0:p.charges[0]=0;p.bonus_bp+=param(s,0,"bonus");heal+=int(stats.hp)*param(s,0,"heal")/10000
		if tier(s,1)>0 and skill.effect=="bleed":heal+=int(stats.hp)*param(s,1,"heal")/10000
		if tier(s,2)>0 and damage>0:
			if skill.target=="all_enemies":p.bonus_bp+=int(p.charges[2])*param(s,2,"bonus");p.charges[2]=0
			else:p.charges[2]=mini(2,int(p.charges[2])+1)
		if tier(s,4)>0:
			if skill.effect in ["regen","heal"]:p.charges[4]=1
			elif damage>0 and int(p.charges[4])>0:p.charges[4]=0;p.bonus_bp+=param(s,4,"bonus");refund=int(stats.mp)*param(s,4,"refund")/10000
		if tier(s,5)>0:
			if skill.effect=="mana_steal" and stolen>0:p.charges[5]=1;heal+=mini(stolen*2,int(stats.hp)*param(s,5,"heal_cap")/10000)
			elif skill.effect=="bleed" and int(p.charges[5])>0:p.charges[5]=0;p.dot_bp=param(s,5,"dot")
	damage=damage*(10000+mini(int(p.bonus_bp),int(rules.final_bonus_cap_bp)))/10000
	if skill.effect=="bleed":
		if tier(s,1)>0:state.enemy_bleed=2;state.bleed_damage=int(state.bleed_damage)*param(s,1,"tick")/10000
		state.bleed_damage=int(state.bleed_damage)*(10000+int(p.dot_bp))/10000
	if tier(s,3)>0 and skill.effect=="sleep" and control_applied and int(state.enemy_poison)>0:damage+=int(state.poison_damage)*param(s,3,"ticks")
	if hp>0:
		var amount:=mini(heal,int(stats.hp)-hp);hp+=amount;state.last_healed+=amount
	return {"hp":hp,"mp":mini(mp+refund,int(stats.mp)),"damage":damage}
static func describe(s:Dictionary)->String:
	var lines:Array[String]=[]
	for i in 6:
		var pieces:=int(s.get("sets",[0,0,0,0,0,0])[i]);var active:=tier(s,i) if not s.is_empty() else 0
		if pieces==0 and active==0:continue
		lines.append("%s · %d/4件 · %s"%[rules.items[i].name,pieces,"特效%d阶"%active if active>0 else "2件属性待激活" if pieces<2 else "2件属性生效"])
		if active>0:lines.append(rules.items[i].description)
	return "\n".join(lines)
static func two_text(entry:Dictionary)->String:
	var parts:Array[String]=[]
	for kind in entry.two:
		parts.append("%s+%s"%[LootRules.rules.affix_names[kind],("%.2f%%"%(int(entry.two[kind])/100.0)) if kind in ["reduction","dot"] else str(int(entry.two[kind]))])
	return "、".join(parts)
