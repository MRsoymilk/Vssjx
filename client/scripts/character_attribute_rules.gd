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
	return {
		"hp": [120,95,85][job] + (level-1)*18 + int(a[0])*8 + int(a[2])*2,
		"mp": [35,45,65][job] + (level-1)*8 + int(a[1])*5 + int(a[4])*2,
		"attack": [18,23,21][job] + (level-1)*4 + (5 if equipped else 0) + int(a[1] if job == 2 else a[2])*2 + int(a[3]),
		"defense": [7,4,3][job] + (level-1)*2 + floori(float(a[0])/2.0) + int(a[3]) + int(a[4])*2
	}

static func profile(job: int, level: int, equipped: bool, a: Array) -> Dictionary:
	var values := stats(job,level,equipped,a)
	var base: int = [18,23,21][job] + (level-1)*4 + (5 if equipped else 0)
	var spent := 0
	var recommended: Array = []
	for n in a:
		spent += int(n)
		recommended.append(int(n))
	var pattern: Array = [[0,0,0,2,4],[0,2,2,2,3],[0,1,1,1,4]][job]
	for i in level*5-spent: recommended[int(pattern[i%5])] += 1
	return {"version":"attributes-v1","allocated":a.duplicate(),"available":level*5-spent,"recommended":recommended,
		"combat":{"hp":values.hp,"mp":values.mp,"physical_attack":base+int(a[2])*2+int(a[3]),"magic_attack":base+int(a[1])*2+int(a[3]),
		"physical_defense":values.defense,"magic_defense":values.defense,"physical_crit":0,"magic_crit":0,
		"physical_hit":100,"magic_hit":100,"physical_evasion":0,"magic_evasion":0,"damage_reduction":0}}
