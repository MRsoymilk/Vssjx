extends RefCounted
## Read-only explanation of the same single-item looks used by ShopRules.
const PARTS_PATH := "res://assets/data/hero-parts.json"
const JOBS := ["力士", "侠客", "隐者"]
static var _parts: Dictionary = {}

static func parts() -> Dictionary:
	if _parts.is_empty(): _parts = JSON.parse_string(FileAccess.get_file_as_string(PARTS_PATH))
	return _parts

static func changes(entry: Dictionary) -> String:
	return {"weapon":"替换武器部件", "armor":"替换衣服及前后层", "hat":"替换头饰部件"}.get(entry.get("slot", ""), "仅影响属性，不改变人物样式")

static func variant(entry: Dictionary, job: int, gender: int) -> Dictionary:
	if not ShopRules.is_equipment(entry) or job not in range(3) or gender not in range(2): return {}
	if int(entry.get("job", -1)) >= 0 and int(entry.job) != job: return {}
	var gear := {"weapon":null, "armor":null, "slots":{}}
	if entry.slot in ["weapon", "armor"]: gear[entry.slot] = entry.id
	else: gear.slots[entry.slot] = entry.id
	var before_key := ShopRules.actor_key(job, gender, [0,0,0])
	var look := ShopRules.appearance(gear)
	var key := ShopRules.actor_key(job, gender, look)
	var stem := before_key.trim_prefix("hero/").get_slice("_", 0)
	var sources: Array = parts().recipes[stem].sources
	var before := {"头饰":[sources[0]], "衣服":[sources[1],sources[3],sources[4]], "武器":[]}
	var after: Dictionary = before.duplicate(true)
	if int(look[0]) > 0: after["武器"] = ["e" + stem.substr(1) + str(int(look[0]))]
	var clothing := int(look[1])
	if clothing > 0:
		var body := clothing - 2 if clothing >= 3 else clothing + (2 if stem.ends_with("fs") else 1)
		after["衣服"] = [stem+str(body), stem+str(body)+"q", stem+str(body)+"x"]
	if int(look[2]) > 0: after["头饰"] = [stem+"t"+str(int(look[2]))]
	var resources := {}
	for group in after.values():
		for id in group: resources[id] = parts().parts.get(id, {}).get("texture", "缺少部件资源")
	return {"职业":JOBS[job], "性别":"男" if gender == 0 else "女", "外观编码":look,
		"装备前动画":before_key, "装备后动画":key, "装备前部件":before, "装备后部件":after,
		"部件贴图":resources, "原始配方":"ssjx/hero.mrp:"+stem+".ani"}

static func describe(entry: Dictionary) -> Dictionary:
	var variants := {}
	for job in 3:
		for gender in 2:
			var value := variant(entry, job, gender)
			if not value.is_empty(): variants["%s · %s" % [value["职业"], value["性别"]]] = value
	return {"装备ID":entry.id, "槽位":ShopRules.catalog.slot_labels[entry.slot], "样式变化":changes(entry),
		"对照基准":"空手、默认衣服与默认头饰，仅穿戴当前这一件装备；不读取玩家装备或存档。",
		"映射依据":entry.get("appearance_basis", "当前兼容装备的重建映射，按职业选择原包人物部件。"),
		"规则来源":"res://scripts/shop_rules.gd；res://scripts/hero_appearance.gd；"+PARTS_PATH,
		"职业与性别对应":variants}
