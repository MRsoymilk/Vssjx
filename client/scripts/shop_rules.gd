class_name ShopRules
extends RefCounted
## Catalog values are reconstruction rules; visual parts come only from ssjx/hero.
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/shop-v1.json"))

static func item(id: String) -> Dictionary:
	for entry in catalog.items:
		if entry.id == id: return entry.duplicate(true)
	return {}

static func local_state(player: Dictionary) -> Dictionary:
	var owned: Array = player.get("shop_owned", []).duplicate()
	if player.get("weapon_owned", true) and not owned.has("sword"): owned.append("sword")
	return {"version":"shop-v1", "catalog":catalog.items, "owned":owned,
		"weapon":player.get("shop_weapon", "sword" if player.get("equipped",false) else null), "armor":player.get("shop_armor")}

static func valid_gear(gear: Variant) -> bool:
	if not gear is Dictionary or gear.get("version") != "shop-v1" or not gear.get("owned") is Array or gear.owned.size() > 5: return false
	var seen := {}
	for id in gear.owned:
		if not id is String or item(id).is_empty() or id == "potion" or seen.has(id): return false
		seen[id] = true
	for slot in ["weapon","armor"]:
		if not gear.has(slot): return false
		if gear[slot] != null and (not gear[slot] is String or not seen.has(gear[slot]) or item(gear[slot]).get("slot") != slot): return false
	return true

static func bonus(gear: Dictionary) -> Vector2i:
	var result := Vector2i.ZERO
	for slot in ["weapon","armor"]:
		var entry := item(String(gear[slot])) if gear.get(slot) != null else {}
		result += Vector2i(int(entry.get("attack",0)),int(entry.get("defense",0)))
	return result

static func appearance(gear: Dictionary) -> Array:
	var result := [0,0]
	for i in 2:
		var id: Variant = gear.get(["weapon","armor"][i])
		if id != null: result[i] = int(item(String(id)).get("visual",0))
	return result

static func actor_key(job: int, gender: int, look: Array) -> String:
	var stem: String = (["mzs","mck","mfs"] if gender == 0 else ["wzs","wck","wfs"])[clampi(job,0,2)]
	if int(look[0]) == 1 and int(look[1]) == 0: return "hero/"+stem
	return "hero/%s_w%d_c%d" % [stem,int(look[0]),int(look[1])]

static func bag_item(id: String, job: int = 1) -> Dictionary:
	var entry := item(id)
	if entry.is_empty(): return {}
	entry.count = 1
	entry.level = 1
	if id.begins_with("weapon_"):
		entry.icon = "res://assets/ui/shop_%s%d.png" % [["ezs","eck","efs"][clampi(job,0,2)],int(entry.visual)]
	return entry

static func description(id: String) -> String:
	var entry := item(id)
	if entry.is_empty(): return ""
	if id == "potion": return "恢复45点气血"
	return "攻击 +%d" % int(entry.attack) if entry.slot == "weapon" else "防御 +%d" % int(entry.defense)

static func bag_slots(gear: Dictionary, potions: int) -> int:
	var count := ceili(potions / 99.0)
	for id in gear.owned:
		if gear.weapon != id and gear.armor != id: count += 1
	return count

static func apply_local(player: Dictionary, action: String, id: String) -> String:
	var gear := local_state(player)
	var entry := item(id)
	if entry.is_empty(): return "INVALID_EQUIPMENT"
	if action == "buy":
		if id != "potion" and gear.owned.has(id): return "ITEM_ALREADY_OWNED"
		if id == "potion" and int(player.potions) >= 99: return "BAG_FULL"
		if int(player.gold) < int(entry.price): return "GOLD_INSUFFICIENT"
		if id != "potion" and bag_slots(gear,int(player.potions)) >= 60: return "BAG_FULL"
		player.gold = int(player.gold) - int(entry.price)
		if id == "potion": player.potions = int(player.potions) + 1
		elif id == "sword": player.weapon_owned = true
		else:
			var owned: Array = player.get("shop_owned",[]).duplicate()
			owned.append(id)
			player.shop_owned = owned
		return ""
	if not action in ["equip","unequip"] or entry.slot == "consumable": return "INVALID_EQUIPMENT"
	if not gear.owned.has(id): return "WEAPON_NOT_OWNED"
	var on: bool = action == "equip"
	if (gear[entry.slot] == id) == on: return "EQUIPMENT_UNCHANGED"
	if not on and bag_slots(gear,int(player.potions)) >= 60: return "BAG_FULL"
	var value: Variant = id if on else null
	if entry.slot == "weapon":
		player.shop_weapon = value
		player.equipped = value != null
	else: player.shop_armor = value
	return ""
