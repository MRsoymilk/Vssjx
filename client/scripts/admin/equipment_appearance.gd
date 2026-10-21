extends RefCounted
## Read-only explanation of the same single-item looks used by ShopRules.
const PARTS_PATH := "res://assets/appearance_resources/catalog.tres"
const JOBS := ["力士", "侠客", "隐者"]
static var _parts: Dictionary = {}

static func parts() -> Dictionary:
	if _parts.is_empty(): _parts = {"recipes":AppearanceResources.recipe_specs(),"parts":AppearanceResources.part_specs()}
	return _parts

static func changes(entry: Dictionary) -> String:
	return {"weapon":"替换武器部件", "armor":"替换衣服及前后层", "hat":"替换头饰部件"}.get(entry.get("slot", ""), "仅影响属性，不改变人物样式")

static func variant(entry: Dictionary, job: int, gender: int, full_set: bool = false) -> Dictionary:
	if not ShopRules.is_equipment(entry) or job not in range(3) or gender not in range(2): return {}
	if not ShopRules.equipment_error(entry, job, gender).is_empty(): return {}
	var gear := {"weapon":null, "armor":null, "slots":{}}
	if entry.slot in ["weapon", "armor"]: gear[entry.slot] = entry.id
	else: gear.slots[entry.slot] = entry.id
	if full_set and entry.has("set_id"):
		for member in ShopRules.catalog.items:
			if member.get("set_id", "") != entry.set_id: continue
			gear.slots[member.slot] = member.id
			if member.slot in ["weapon", "armor"]: gear[member.slot] = member.id
	var before_key := ShopRules.actor_key(job, gender, [0,0,0])
	var look := ShopRules.appearance(gear)
	var key := ShopRules.actor_key(job, gender, look)
	var stem := before_key.trim_prefix("hero/").get_slice("_", 0)
	var sources: Array = parts().recipes[stem].sources
	var before := {"头饰":[sources[0]], "衣服":[sources[1],sources[3],sources[4]], "武器":[]}
	var after: Dictionary = before.duplicate(true)
	var outfit:=AppearanceResources.outfit(stem,look if look.size()==3 else [look[0],look[1],0])
	if outfit==null:return {}
	after["武器"]=outfit.weapon.parts.map(func(part:NativeAppearancePart)->String:return part.source_id)
	after["衣服"]=outfit.clothing.parts.map(func(part:NativeAppearancePart)->String:return part.source_id)
	after["头饰"]=outfit.head.parts.map(func(part:NativeAppearancePart)->String:return part.source_id)
	var resources := {}
	for component in [outfit.weapon,outfit.clothing,outfit.head]:
		for part in component.parts:resources[part.source_id]=part.texture_path
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
