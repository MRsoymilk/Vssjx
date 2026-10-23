class_name CharacterAttributeRules
extends RefCounted
## Local implementation of the server's versioned attributes-v1 contract.
## Online values always come from the server; this never computes online rewards.

static func valid_points(value: Variant, level: int, minimum: Array = []) -> bool:
	if not value is Array or value.size() != 5 or level < 1 or level > 60: return false
	var spent := 0
	for i in 5:
		var n: Variant = value[i]
		if not (n is int or n is float) or not is_finite(float(n)): return false
		if float(n) != floor(float(n)) or n < 0 or n > 300: return false
		if not minimum.is_empty() and (minimum.size() != 5 or int(n) < int(minimum[i])): return false
		spent += int(n)
	return spent <= level * 5

static func reset_allocation(player: Dictionary, current: Dictionary) -> void:
	player.allocated_attributes=[0,0,0,0,0]
	# Reapply flat and percentage gear bonuses to the new base before rescaling.
	var next:=local_stats(player)
	player.hp=clampi(int(player.hp)*int(next.hp)/int(current.hp),1,int(next.hp))
	player.mp=clampi(int(player.mp)*int(next.mp)/int(current.mp),0,int(next.mp))

static func local_stats(player: Dictionary) -> Dictionary:
	var job:=int(player.get("job",1));var level:=int(player.get("level",1));var equipped:=bool(player.get("equipped",false))
	var points:Array=player.get("allocated_attributes",[0,0,0,0,0]).map(func(n:Variant)->int:return int(n))
	var value:=balanced_stats(job,level,equipped,points) if player.get("balance_revision",0)==1 else stats(job,level,equipped,points)
	var bonus:=ShopRules.bonus(ShopRules.local_state(player))
	gear_bonus(value,bonus.x-(5 if equipped else 0),bonus.y)
	LootRules.apply_stats(player.get("loot_state",{}),value,job)
	return value

static func stats(job: int, level: int, equipped: bool, a: Array) -> Dictionary:
	var result := {
		"hp": [120,95,85][job] + (level-1)*18 + int(a[0])*8,
		"mp": [35,45,65][job] + (level-1)*8 + int(a[0]) + int(a[1])*5 + int(a[2]),
		"attack": [18,23,21][job] + (level-1)*4 + (5 if equipped else 0) + int(a[1] if job == 2 else a[2])*2,
		"defense": [7,4,3][job] + (level-1)*2
	}
	if a.any(func(n:Variant)->bool:return int(n)!=0):result.attributes=a.duplicate()
	return result

static func profile(job: int, level: int, equipped: bool, a: Array) -> Dictionary:
	var values := stats(job,level,equipped,a)
	var base: int = [18,23,21][job] + (level-1)*4 + (5 if equipped else 0)
	var spent := 0
	var recommended: Array = []
	for n in a:
		spent += int(n)
		recommended.append(int(n))
	var pattern: Array = [[0,0,0,2,3],[0,2,3,3,3],[0,1,1,1,4]][job]
	for i in level*5-spent: recommended[int(pattern[i%5])] += 1
	return {"version":"attributes-v1","formula_revision":2,"allocated":a.duplicate(),"available":level*5-spent,"recommended":recommended,
		"combat":{"hp":values.hp,"mp":values.mp,"physical_attack":base+int(a[2])*2,"magic_attack":base+int(a[1])*2,
		"physical_defense":values.defense,"magic_defense":values.defense,"physical_crit":int(a[3]),"magic_crit":int(a[4]),
		"physical_hit":100+int(a[3]),"magic_hit":100+int(a[4]),"physical_evasion":int(a[3]),"magic_evasion":int(a[4]),"damage_reduction":0}}

const POINT_HELP := ["体质：每点气血+8、灵力+1", "灵性：每点灵力+5、法攻+2", "力量：每点灵力+1、物攻+2", "敏捷：每点物暴、物闪、命中各+1", "定力：每点法暴、法闪、法命各+1"]
const RATING_HELP := "新版评级随等级递减，基础暴击5%、最高50%；命中包含闪避，范围80%～99%。防御比例减伤最高60%。"

static func balanced_stats(job:int,level:int,equipped:bool,a:Array)->Dictionary:
	var p:Dictionary=CombatBalance.profile(job,level,a).value
	var result:Dictionary={"hp":p.hp,"mp":p.mp,"attack":p.magic_attack if job==2 else p.physical_attack,"defense":p.physical_defense,"attributes":a.duplicate(),
		"balance":{"skills_revision":1,"level":level,"physical_attack":p.physical_attack,"magic_attack":p.magic_attack,"physical_defense":p.physical_defense,"magic_defense":p.magic_defense,"ratings":[int(a[3]),int(a[4])]}}
	for key in ["crit_bonus","hit_bonus","evade_bonus"]:result.balance[key]=[0,0]
	for key in ["crit_damage_bp","increased_bp","dot_bp","penetration_bp","reduction_bp"]:result.balance[key]=0
	if equipped:gear_bonus(result,5,0)
	return result

static func valid_balance(stats:Dictionary)->bool:
	if not stats.has("balance"):return true
	var b:Variant=stats.balance
	if not b is Dictionary or not OnlinePve.integer(b.get("level"),1,60) or not OnlinePve.integer(b.get("skills_revision",0),0,1):return false
	if not b.get("ratings") is Array or b.ratings.size()!=2:return false
	for rating in b.ratings:
		if not OnlinePve.integer(rating,0,1000000):return false
	for key in ["physical_attack","magic_attack","physical_defense","magic_defense"]:
		if not OnlinePve.integer(b.get(key),0,1000000):return false
	for key in ["crit_bonus","hit_bonus","evade_bonus"]:
		var ratings:Variant=b.get(key,[0,0])
		if not ratings is Array or ratings.size()!=2:return false
		for n in ratings:
			if not OnlinePve.integer(n,0,1000000):return false
	for key in ["crit_damage_bp","increased_bp","dot_bp","penetration_bp","reduction_bp"]:
		if not OnlinePve.integer(b.get(key,0),0,1000000):return false
	if b.has("builds") and not BuildRules.valid_snapshot(b.builds):return false
	return b.physical_defense==stats.get("defense")

static func gear_bonus(s:Dictionary,attack:int,defense:int)->void:
	s.attack+=attack;s.defense+=defense
	if s.has("balance"):
		for key in ["physical_attack","magic_attack"]:s.balance[key]+=attack
		for key in ["physical_defense","magic_defense"]:s.balance[key]+=defense

static func profile_for(s:Dictionary,job:int,level:int,a:Array)->Dictionary:
	var p:=profile(job,level,false,a)
	p.formula_revision=3
	var recommended:Array=a.duplicate();var spent:=0
	for value in a:spent+=int(value)
	for i in level*5-spent:recommended[int(CombatBalance.rules.recommended_patterns[job][i%5])]+=1
	p.recommended=recommended
	for key in ["hp","mp"]:p.combat[key]=s[key]
	for key in ["physical_attack","magic_attack","physical_defense","magic_defense"]:p.combat[key]=s.balance[key]
	for i in 2:
		var prefix:String=["physical_","magic_"][i]
		var rating:=int(s.balance.ratings[i])
		p.combat[prefix+"crit"]=rating+int(s.balance.get("crit_bonus",[0,0])[i])
		p.combat[prefix+"hit"]=rating+int(s.balance.get("hit_bonus",[0,0])[i])
		p.combat[prefix+"evasion"]=rating+int(s.balance.get("evade_bonus",[0,0])[i])
	p.combat.damage_reduction=mini(2500,int(s.balance.get("reduction_bp",0)))/100
	return p

static func direct_damage(s:Dictionary,defense:int,coefficient:int=10000,variance:int=0)->int:
	if s.has("balance"):return int(CombatBalance.damage({"attack":maxi(0,int(s.attack)+variance),"defense":maxi(0,defense),"level":int(s.balance.level),"coefficient_bp":coefficient,"increased_bp":int(s.balance.get("increased_bp",0)),"penetration_bp":int(s.balance.get("penetration_bp",0))}).value.damage)
	return maxi(1,int(s.attack)*coefficient/10000-defense+variance)

static func incoming(attack:int,level:int,defender:Dictionary,magical:bool=false,variance:int=0)->int:
	if defender.has("balance"):
		return int(CombatBalance.damage({"attack":maxi(0,attack+variance),"defense":int(defender.balance.magic_defense if magical else defender.balance.physical_defense),"level":clampi(level,1,60),"extra_reduction_bp":int(defender.balance.get("reduction_bp",0))}).value.damage)
	return maxi(1,attack-int(defender.defense)+variance)

static func power(values:Dictionary,job:int,magical:bool)->Dictionary:
	var result:=values.duplicate(true)
	if values.has("balance"):
		result.attack=values.balance.magic_attack if magical else values.balance.physical_attack
		return result
	var a:Array=values.get("attributes",[0,0,0,0,0])
	result.attack+=2*(int(a[1 if magical else 2])-int(a[1 if job==2 else 2]))
	return result

static func hit_chance(attacker:Dictionary,defender:Dictionary,magical:bool=false)->int:
	if attacker.has("balance") or defender.has("balance"):
		var a:Dictionary=attacker.get("balance",{});var d:Dictionary=defender.get("balance",{})
		var index:=1 if magical else 0
		return int(CombatBalance.hit_chance(int(a.get("level",d.get("level",1))),int(a.get("ratings",[0,0])[index])+int(a.get("hit_bonus",[0,0])[index]),int(d.get("ratings",[0,0])[index])+int(d.get("evade_bonus",[0,0])[index])).value)
	var i:=4 if magical else 3
	return clampi(10000+(int(attacker.get("attributes",[0,0,0,0,0])[i])-int(defender.get("attributes",[0,0,0,0,0])[i]))*10,5000,10000)

static func critical_at(values:Dictionary,magical:bool,state:Dictionary,damage:int,roll:int)->int:
	var rating:=int(values.get("attributes",[0,0,0,0,0])[4 if magical else 3])
	var buff:=int(state.crit_chance)*100 if int(state.crit)>0 else 0
	var chance:=int(CombatBalance.critical_chance(int(values.balance.level),int(values.balance.ratings[1 if magical else 0])+int(values.balance.get("crit_bonus",[0,0])[1 if magical else 0]),buff).value) if values.has("balance") else clampi(rating*10+buff,0,7500)
	state.last_critical=damage>0 and roll<chance
	return damage*mini(22500,15000+int(values.get("balance",{}).get("crit_damage_bp",0)))/10000 if state.last_critical else damage

static func dot_damage(stats:Dictionary,defense:int,coefficient:int)->int:
	var s:=stats.duplicate(true)
	if s.has("balance"):s.balance.increased_bp=int(s.balance.get("increased_bp",0))+int(s.balance.get("dot_bp",0))
	return direct_damage(s,defense,coefficient)
