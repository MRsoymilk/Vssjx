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
const RATING_HELP := "暴击、命中和闪避为评级，每点相当于0.1个百分点；命中抵消闪避，最低命中50%，总暴击最高75%。"

static func power(values:Dictionary,job:int,magical:bool)->Dictionary:
	var result:=values.duplicate(true)
	var a:Array=values.get("attributes",[0,0,0,0,0])
	result.attack+=2*(int(a[1 if magical else 2])-int(a[1 if job==2 else 2]))
	return result

static func hit_chance(attacker:Dictionary,defender:Dictionary,magical:bool=false)->int:
	var i:=4 if magical else 3
	return clampi(10000+(int(attacker.get("attributes",[0,0,0,0,0])[i])-int(defender.get("attributes",[0,0,0,0,0])[i]))*10,5000,10000)

static func critical_at(values:Dictionary,magical:bool,state:Dictionary,damage:int,roll:int)->int:
	var rating:=int(values.get("attributes",[0,0,0,0,0])[4 if magical else 3])
	var buff:=int(state.crit_chance)*100 if int(state.crit)>0 else 0
	state.last_critical=damage>0 and roll<clampi(rating*10+buff,0,7500)
	return damage*3/2 if state.last_critical else damage
