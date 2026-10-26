class_name ShopRules
extends RefCounted
## All original icons, with explicitly reconstructed names, classifications and rules.
static var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/shop-v2.json"))
static var catalog_hash: String = FileAccess.get_file_as_string("res://assets/data/shop-v2.json").replace("\r\n","\n").sha256_text()
static var _index: Dictionary = {}
const SLOTS := ["weapon","pendant","armor","wrist","belt","pants","boots","ring","necklace","hat"]
const TRAVEL_SCROLL := "restored/shenxing_scroll"
static var APPEARANCE_LIMITS: Array = GeneratedEquipment.appearance_limits()

static func valid_appearance(look: Variant) -> bool:
	if not look is Array or look.size() != 3: return false
	for index in 3:
		var value: Variant = look[index]
		if not (value is int or value is float) or not is_finite(float(value)) or floor(float(value)) != value or value < 0 or value > APPEARANCE_LIMITS[index]: return false
	return true

static func equipment_error(entry: Dictionary, job: int, gender: int) -> String:
	if int(entry.get("job", -1)) >= 0 and int(entry.job) != job: return "WRONG_JOB"
	if int(entry.get("gender", -1)) >= 0 and int(entry.gender) != gender: return "WRONG_GENDER"
	return ""

static func item(id: String) -> Dictionary:
	if _index.is_empty():
		for entry in catalog.items: _index[entry.id] = entry
	return _index.get(id,{}).duplicate(true)

static func icon_path(entry: Dictionary) -> String:
	# Presentation-only overrides keep the server catalog hash and old saves intact.
	match entry.get("id", ""):
		"supply/hp_gourd":return "res://assets/items/original/ix62.png"
		"supply/mp_gourd":return "res://assets/items/original/ix63.png"
	return String(entry.get("icon", ""))

static func is_equipment(entry: Dictionary) -> bool:
	return entry.get("slot") in SLOTS

static func unique(entry:Dictionary)->bool:
	return is_equipment(entry) or entry.get("slot")=="gourd"

static func equipped_id(gear: Dictionary, slot: String) -> Variant:
	return gear.get(slot) if slot in ["weapon","armor"] else gear.get("slots",{}).get(slot)

static func local_state(player: Dictionary) -> Dictionary:
	var owned: Array = player.get("shop_owned", []).duplicate()
	if player.get("weapon_owned", true) and not owned.has("sword"): owned.append("sword")
	var slots: Dictionary = player.get("shop_slots",{}).duplicate(true)
	for slot in SLOTS:
		if not slots.has(slot): slots[slot] = null
	slots.weapon = player.get("shop_weapon", "sword" if player.get("equipped",false) else null)
	slots.armor = player.get("shop_armor")
	var quantities := {"potion":int(player.get("potions",0))}
	for id in owned: quantities[id] = player.get("shop_quantities",{}).get(id,1)
	return {"version":"shop-v2","owned":owned,"quantities":quantities,"slots":slots,"weapon":slots.weapon,"armor":slots.armor}

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floor(float(value))==float(value) and value>=low and value<=high

static func valid_gear(gear: Variant) -> bool:
	if not gear is Dictionary or not gear.get("version") in ["shop-v1","shop-v2"] or not gear.get("owned") is Array or gear.owned.size()>catalog.items.size(): return false
	var seen := {}
	for id in gear.owned:
		if not id is String or item(id).is_empty() or id=="potion" or seen.has(id): return false
		seen[id] = true
	if gear.get("version")=="shop-v2":
		if not gear.get("slots") is Dictionary or not gear.get("quantities") is Dictionary: return false
		if gear.slots.size()!=10 or gear.quantities.size()>catalog.items.size()+1: return false
		for id in gear.quantities:
			if id=="potion":
				if not _integer(gear.quantities[id],0,1000000): return false
			elif not seen.has(id) or not _integer(gear.quantities[id],1,1 if unique(item(id)) else 99): return false
		for id in seen:
			if not gear.quantities.has(id): return false
	for slot in SLOTS:
		if gear.get("version")=="shop-v2" and not gear.slots.has(slot): return false
		var id: Variant = equipped_id(gear,slot)
		if id!=null and (not id is String or not seen.has(id) or item(id).get("slot")!=slot): return false
	if not gear.has("weapon") or not gear.has("armor"): return false
	if gear.get("version")=="shop-v2" and (gear.slots.weapon!=gear.weapon or gear.slots.armor!=gear.armor): return false
	return true

static func bonus(gear: Dictionary) -> Vector2i:
	var result := Vector2i.ZERO
	for slot in SLOTS:
		var id: Variant = equipped_id(gear,slot)
		var entry := item(String(id)) if id!=null else {}
		result += Vector2i(int(entry.get("attack",0)),int(entry.get("defense",0)))
	return result

static func appearance(gear: Dictionary) -> Array:
	var result := [0,0,0]
	for i in 3:
		var id: Variant = equipped_id(gear,["weapon","armor","hat"][i])
		if id!=null: result[i] = int(item(String(id)).get("head_visual" if i==2 else "visual",0))
	return result

static func actor_key(job: int, gender: int, look: Array) -> String:
	var stem: String = (["mzs","mck","mfs"] if gender==0 else ["wzs","wck","wfs"])[clampi(job,0,2)]
	var head := int(look[2]) if look.size()>2 else 0
	if int(look[0])==1 and int(look[1])==0 and head==0: return "hero/"+stem
	if int(look[0])<=3 and int(look[1])<=2 and head==0: return "hero/%s_w%d_c%d"%[stem,int(look[0]),int(look[1])]
	return "hero/%s_w%d_c%d_h%d"%[stem,int(look[0]),int(look[1]),head]

static func bag_item(id: String, job: int=1) -> Dictionary:
	var entry := item(id)
	if entry.is_empty(): return {}
	entry.count=1
	if id.begins_with("weapon_"): entry.icon="res://assets/ui/shop_%s%d.png"%[["ezs","eck","efs"][clampi(job,0,2)],int(entry.visual)]
	return entry

static func description(id: String, stats: Dictionary={}) -> String:
	var entry := item(id)
	if entry.is_empty(): return ""
	if entry.slot=="gourd":return "容量%d；仅战斗外补给，空瓶可补充。"%int(entry.capacity)
	if entry.get("effect")=="teleport":return "自选已开放地图；成功耗1张，取消不消耗。"
	if entry.get("effect")=="reset_attributes": return "返还全部属性点；耗1颗，保留气血灵力比例。"
	if is_equipment(entry): return ("攻击 +%d"%int(entry.attack)) if entry.slot=="weapon" else ("防御 +%d"%int(entry.defense))
	if entry.has("attribute"):return "%s类宝石材料，可购买并存入背包"%entry.attribute
	if id=="potion" and (stats.is_empty() or SkillBalance.revised(stats)):
		return "恢复最大气血的%d%%（至少%d点）"%[int(SkillBalance.rules.potion_restore_bp)/100,int(entry.restore_hp)]
	if entry.slot=="consumable":
		var parts: Array[String] = []
		if int(entry.restore_hp)>0: parts.append("恢复%d点气血"%int(entry.restore_hp))
		if int(entry.restore_mp)>0: parts.append("恢复%d点灵力"%int(entry.restore_mp))
		return " / ".join(parts)+("（%s）"%entry.usage_note if entry.has("usage_note") else "")
	return "%s，可购买并存入背包"%entry.category

static func use_error(entry: Dictionary, player: Dictionary, limits: Dictionary, points: Array=[]) -> String:
	if player.get("corpse") is Dictionary: return "SOUL_STATE"
	if entry.get("slot")!="consumable" or limits.is_empty(): return "ITEM_NOT_USABLE"
	if entry.get("effect")=="teleport":return ""
	if entry.get("effect")=="reset_attributes":
		var allocated:Array=points if not points.is_empty() else player.get("allocated_attributes",[0,0,0,0,0])
		return "" if allocated.any(func(value:Variant)->bool:return int(value)>0) else "NO_ALLOCATED_ATTRIBUTES"
	if (int(entry.restore_hp)==0 or int(player.hp)>=int(limits.hp)) and (int(entry.restore_mp)==0 or int(player.mp)>=int(limits.mp)): return "HP_FULL"
	return ""

static func quantity(gear: Dictionary, id: String) -> int:
	return int(gear.get("quantities",{}).get(id,1 if gear.get("owned",[]).has(id) else 0))

static func bag_slots(gear: Dictionary, potions: int) -> int:
	var count := ceili(potions/99.0)
	for id in gear.owned:
		var on := false
		for slot in SLOTS:
			if equipped_id(gear,slot)==id: on=true
		if not on: count+=1
	return count

static func _store(player: Dictionary, gear: Dictionary) -> void:
	player.shop_owned=gear.owned.filter(func(id: String) -> bool: return id!="sword")
	player.weapon_owned=gear.owned.has("sword")
	player.shop_quantities=gear.quantities.duplicate(true)
	player.shop_quantities.erase("potion")
	player.shop_quantities.erase("sword")
	player.shop_slots=gear.slots.duplicate(true)
	player.shop_weapon=gear.slots.weapon;player.shop_armor=gear.slots.armor
	player.equipped=gear.slots.weapon!=null

static func apply_local(player: Dictionary, action: String, id: String, count: int=1, limits: Dictionary={}) -> String:
	if player.get("corpse") is Dictionary:return "SOUL_STATE"
	if action in GourdRules.ACTIONS:return GourdRules.apply_local(player,action,id) if count==1 else "INVALID_QUANTITY"
	if action=="scroll_travel":return _travel_local(player,id,count)
	var gear := local_state(player)
	var entry := item(id)
	if entry.is_empty(): return "INVALID_EQUIPMENT"
	if count<1 or count>99 or (unique(entry) and count!=1): return "INVALID_QUANTITY"
	if action=="buy":
		if unique(entry) and gear.owned.has(id): return "ITEM_ALREADY_OWNED"
		if quantity(gear,id)+count>99: return "BAG_FULL"
		if int(player.gold)<int(entry.price)*count: return "GOLD_INSUFFICIENT"
		if quantity(gear,id)==0 and bag_slots(gear,int(player.potions))+LootRules.extra_bag(player.get("loot_state",{}))>=60: return "BAG_FULL"
		player.gold=int(player.gold)-int(entry.price)*count
		if id=="potion": player.potions=int(player.potions)+count
		else:
			gear.quantities[id]=quantity(gear,id)+count
			if not gear.owned.has(id): gear.owned.append(id)
		_store(player,gear)
		if entry.slot=="gourd":
			if not player.has("gourds"):player.gourds={}
			player.gourds[id]={"remaining":int(entry.capacity),"enabled":true}
		return ""
	if quantity(gear,id)<count: return "WEAPON_NOT_OWNED"
	if action=="use":
		if count!=1: return "INVALID_QUANTITY"
		if entry.get("effect")=="teleport":return "TRAVEL_DESTINATION_REQUIRED"
		var error:=use_error(entry,player,limits)
		if not error.is_empty(): return error
		if entry.get("effect")=="reset_attributes":
			CharacterAttributeRules.reset_allocation(player,limits)
		else:
			var healing:=SkillBalance.potion(limits) if id=="potion" else int(entry.restore_hp)
			player.hp=mini(int(limits.hp),int(player.hp)+healing)
			player.mp=mini(int(limits.mp),int(player.mp)+int(entry.restore_mp))
	if action in ["use","discard"]:
		if entry.slot=="gourd":player.get("gourds",{}).erase(id)
		if id=="potion": player.potions=int(player.potions)-count
		else:
			gear.quantities[id]=quantity(gear,id)-count
			if gear.quantities[id]==0:
				gear.quantities.erase(id);gear.owned.erase(id)
				for slot in SLOTS:
					if gear.slots[slot]==id: gear.slots[slot]=null
		_store(player,gear)
		return ""
	if not action in ["equip","unequip"] or not is_equipment(entry) or count!=1: return "INVALID_EQUIPMENT"
	if action=="equip":
		var restriction := equipment_error(entry, int(player.job), int(player.get("gender",0)))
		if not restriction.is_empty(): return restriction
	var on: bool = action=="equip"
	if (gear.slots[entry.slot]==id)==on: return "EQUIPMENT_UNCHANGED"
	if not on and bag_slots(gear,int(player.potions))+LootRules.extra_bag(player.get("loot_state",{}))>=60: return "BAG_FULL"
	gear.slots[entry.slot]=id if on else null
	_store(player,gear)
	return ""

static func travel_error(destination:String,current:String,quest_stage:int)->String:
	if destination==current:return "AI_SAME_MAP"
	if destination=="ancient_ruins" and quest_stage<3:return "QUEST_REQUIRED"
	if destination not in ["qingyun_trail","ancient_ruins"] and AIWorld.map_data(destination).is_empty():return "AI_INVALID_TARGET"
	return ""

static func _travel_local(player:Dictionary,destination:String,count:int)->String:
	if count!=1:return "INVALID_QUANTITY"
	var current:String=player.get("ai_map","")
	if current.is_empty():current="qingyun_trail" if int(player.get("zone",0))==0 else "ancient_ruins"
	var error:=travel_error(destination,current,int(player.get("quest",0)))
	if not error.is_empty():return error
	var gear:=local_state(player)
	var left:=quantity(gear,TRAVEL_SCROLL)
	if left<1:return "TRAVEL_SCROLL_REQUIRED"
	var data:=SharedWorldMap.load_data(destination)
	if data.is_empty():return "AI_INVALID_TARGET"
	if left==1:gear.quantities.erase(TRAVEL_SCROLL);gear.owned.erase(TRAVEL_SCROLL)
	else:gear.quantities[TRAVEL_SCROLL]=left-1
	_store(player,gear)
	player.ai_map=destination if destination.begins_with("ai_") else ""
	player.zone=1 if destination=="ancient_ruins" else 0
	player.cell=data.spawn.duplicate();player.hunt_pressure={}
	return ""
