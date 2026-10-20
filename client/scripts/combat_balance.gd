class_name CombatBalance
extends RefCounted
## Candidate contract only: existing saved battles still use their legacy rules.
static var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/balance-v1.json"))

static func _level(value: Variant) -> bool:
	return _integer(value,1,int(rules.max_level))

static func _integer(value: Variant, low: int=0, high: int=1000000) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and value>=low and value<=high

static func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code}

static func profile(job: int, level: int, points: Array) -> Dictionary:
	if not _level(level):return _fail("INVALID_LEVEL")
	if job<0 or job>2:return _fail("INVALID_JOB")
	if points.size()!=5:return _fail("INVALID_VALUE")
	var a:Array[int]=[]
	for point in points:
		if not _integer(point):return _fail("INVALID_VALUE")
		a.append(int(point))
	var available:int=level*int(rules.points_per_level)
	for point in a:available-=point
	if available<0:return _fail("ATTRIBUTE_POINTS_EXCEEDED")
	var growth:=level-1
	var defense:int=int(rules.defense_base[job])+growth*int(rules.defense_growth)
	return {"ok":true,"value":{
		"hp":int(rules.hp_base[job])+growth*int(rules.hp_growth[job])+a[0]*int(rules.vitality_hp),
		"mp":int(rules.mp_base[job])+growth*int(rules.mp_growth)+a[0]+a[1]*int(rules.spirit_mp)+a[2],
		"physical_attack":int(rules.physical_base[job])+growth*int(rules.attack_growth)+a[2]*int(rules.primary_attack),
		"magic_attack":int(rules.magic_base[job])+growth*int(rules.attack_growth)+a[1]*int(rules.primary_attack),
		"physical_defense":defense,"magic_defense":defense+a[4]/2,"available":available}}

static func damage(input: Dictionary) -> Dictionary:
	var h:Dictionary={"attack":0,"defense":0,"level":1,"coefficient_bp":int(rules.basis),"increased_bp":0,"penetration_bp":0,"flat_penetration":0,"critical":false,"critical_multiplier_bp":int(rules.critical_damage_base_bp),"extra_reduction_bp":0,"legendary_bp":int(rules.basis),"guarding":false}
	for key in input:
		if not h.has(key):return _fail("INVALID_VALUE")
		if key in ["critical","guarding"]:
			if not input[key] is bool:return _fail("INVALID_VALUE")
			h[key]=input[key]
		else:
			if key=="level" and not _level(input[key]):return _fail("INVALID_LEVEL")
			if not _integer(input[key]):return _fail("INVALID_VALUE")
			h[key]=int(input[key])
	if int(h.coefficient_bp)>int(rules.skill_coefficient_cap_bp):return _fail("INVALID_COEFFICIENT")
	var b:int=rules.basis
	var effective:=maxi(0,int(h.defense)*(b-mini(int(h.penetration_bp),int(rules.penetration_cap_bp)))/b-int(h.flat_penetration))
	var k:int=int(rules.armor_constant)+int(rules.armor_per_level)*int(h.level)
	var reduction:=mini(effective*b/(effective+k),int(rules.armor_cap_bp))
	var n:int=int(h.attack)*int(h.coefficient_bp)/b
	n=n*(b+mini(int(h.increased_bp),int(rules.increased_cap_bp)))/b
	n=n*(b-reduction)/b
	if h.critical:n=n*clampi(int(h.critical_multiplier_bp),b,int(rules.critical_damage_cap_bp))/b
	n=n*(b-mini(int(h.extra_reduction_bp),int(rules.extra_reduction_cap_bp)))/b
	n=n*clampi(int(h.legendary_bp),b,int(rules.legendary_cap_bp))/b
	if h.guarding:n=n/2
	if int(h.attack)>0 and int(h.coefficient_bp)>0:n=maxi(1,n)
	return {"ok":true,"value":{"damage":n,"effective_defense":effective,"reduction_bp":reduction}}

static func critical_chance(level: int, rating: int, bonus: int=0) -> Dictionary:
	if not _level(level):return _fail("INVALID_LEVEL")
	if not _integer(rating) or not _integer(bonus):return _fail("INVALID_VALUE")
	var k:int=int(rules.rating_constant)+int(rules.rating_per_level)*level
	return {"ok":true,"value":mini(int(rules.critical_base_bp)+int(rules.critical_rating_bonus_bp)*rating/(rating+k)+bonus,int(rules.critical_cap_bp))}

static func hit_chance(level: int, hit: int, evasion: int) -> Dictionary:
	if not _level(level):return _fail("INVALID_LEVEL")
	if not _integer(hit) or not _integer(evasion):return _fail("INVALID_VALUE")
	var delta:=hit-evasion
	var k:int=int(rules.rating_constant)+int(rules.rating_per_level)*level
	return {"ok":true,"value":clampi(int(rules.hit_base_bp)+int(rules.hit_rating_bonus_bp)*delta/(absi(delta)+k),int(rules.hit_floor_bp),int(rules.hit_cap_bp))}

static func aoe_coefficient(coefficient: int, targets: int) -> Dictionary:
	if not _integer(targets,1,int(rules.max_combatants)) or not _integer(coefficient,0,int(rules.skill_coefficient_cap_bp)):return _fail("INVALID_AOE")
	return {"ok":true,"value":mini(coefficient,int(rules.aoe_budget_bp)/targets)}

static func boss_hp(hp: int, members: int) -> Dictionary:
	if not _integer(hp):return _fail("INVALID_VALUE")
	if not _integer(members,1,int(rules.max_combatants)):return _fail("INVALID_PARTY_SIZE")
	return {"ok":true,"value":hp*(int(rules.basis)+int(rules.boss_hp_per_member_bp)*(members-1))/int(rules.basis)}
