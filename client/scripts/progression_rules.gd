class_name ProgressionRules
extends RefCounted
## Local-only draws; online requests never contain seeds, prices, or rolled values.
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/progression-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/progression-v1.json").replace("\r\n","\n").sha256_text()
static func monster(definition:Dictionary)->Dictionary:
	var d:=definition.duplicate(true)
	if d.kind=="boss" or d.id=="boss":d.hp=int(d.hp)*int(rules.boss_hp_budget_bp)/10000
	return d
static func can_fight(state:Dictionary)->bool:return state.get("pending",[]).size()+3<=20
static func quote(item:Dictionary,action:String)->Dictionary:
	if item.legacy:return {"error":"LEGACY_CRAFT_LOCKED"}
	if action=="gear_upgrade":
		var next:=int(item.upgrade)+1
		if next>int(rules.max_upgrade):return {"error":"UPGRADE_LIMIT"}
		return {"cost":[int(item.level)*next*int(rules.upgrade_gold_per_level),next*int(rules.upgrade_scrap),int(next>=int(rules.upgrade_essence_from))]}
	if action=="gear_reroll":
		if item.affixes.is_empty():return {"error":"NO_AFFIXES"}
		var rolls:=int(item.get("rerolls",0))
		if rolls>=int(rules.max_rerolls):return {"error":"REROLL_LIMIT"}
		return {"cost":[int(item.level)*(rolls+1)*int(rules.reroll_gold_per_level),int(rules.reroll_scrap_base)+rolls,int(item.get("legendary")!=null or item.get("set_id")!=null)]}
	return {"error":"INVALID_LOOT_COMMAND"}
static func craft(player:Dictionary,id:String,action:String,index:int=-1,seed:int=0)->String:
	var state:Dictionary=player.loot_state;var position:=-1
	for i in state.items.size():
		if state.items[i].id==id:position=i;break
	if position<0:return "INSTANCE_NOT_OWNED"
	var item:Dictionary=state.items[position]
	if item.legacy:return "LEGACY_CRAFT_LOCKED"
	if action=="gear_salvage":
		if index!=-1:return "INVALID_LOOT_COMMAND"
		if item.equipped:return "UNEQUIP_BEFORE_SALVAGE"
		state.scrap=mini(1000000000,int(state.scrap)+int(rules.salvage_scrap[item.quality]));state.essence=mini(1000000000,int(state.essence)+int(rules.salvage_essence[item.quality]))
		if not state.skins.has(item.template):state.skins.append(item.template)
		state.items.remove_at(position);return ""
	var price:=quote(item,action)
	if price.has("error"):return price.error
	if action=="gear_reroll":
		if index<0 or index>=item.affixes.size():return "INVALID_AFFIX_INDEX"
		if item.get("reroll_index")!=null and int(item.reroll_index)!=index:return "REROLL_SLOT_LOCKED"
	elif index!=-1:return "INVALID_LOOT_COMMAND"
	var cost:Array=price.cost
	if int(player.gold)<int(cost[0]):return "GOLD_INSUFFICIENT"
	if int(state.scrap)<int(cost[1]) or int(state.essence)<int(cost[2]):return "MATERIALS_INSUFFICIENT"
	if action=="gear_upgrade":item.upgrade=int(item.upgrade)+1
	else:
		var pool:Array=[]
		for kind in LootRules.rules.pools[ShopRules.item(item.template).slot]:
			if kind==item.affixes[index].kind:continue
			var duplicate:=false
			for i in item.affixes.size():
				if i!=index and item.affixes[i].kind==kind:duplicate=true
			if not duplicate:pool.append(kind)
		var dice:=[seed];var kind:String=pool[LootRules._draw(dice,pool.size())];var bounds:=LootRules.bounds(kind,int(item.level))
		item.affixes[index]={"kind":kind,"value":bounds.x+LootRules._draw(dice,bounds.y-bounds.x+1)};item.reroll_index=index;item.rerolls=int(item.get("rerolls",0))+1
	player.gold=int(player.gold)-int(cost[0]);state.scrap=int(state.scrap)-int(cost[1]);state.essence=int(state.essence)-int(cost[2]);return ""
static func reward(player:Dictionary,level:int,boss:bool,seed:int)->Array:
	LootRules.sync_legacy(player)
	var state:Dictionary=player.loot_state;var dice:=[seed];var job:=int(player.job);var gender:=int(player.get("gender",0))
	assert(can_fight(state),"Loot storage must be reserved before combat")
	state.kills=mini(1000000000,int(state.kills)+1)
	if boss:state.bosses=mini(1000000000,int(state.bosses)+1)
	state.scrap=mini(1000000000,int(state.scrap)+int(rules.boss_scrap if boss else rules.victory_scrap))
	if boss:state.essence=mini(1000000000,int(state.essence)+int(rules.boss_essence))
	if not boss and LootRules._draw(dice,100)>=int(rules.normal_drop_percent) and int(state.kills)%int(rules.normal_pity)!=0:return []
	var used:=ShopRules.bag_slots(ShopRules.local_state(player),int(player.potions))+LootRules.extra_bag(state);var ids:Array=[]
	for drop in (int(rules.boss_drops) if boss else 1):
		var pity:bool=boss and drop==0 and int(state.bosses)%int(rules.boss_pity)==0 and level>=int(rules.min_special_level)
		var focus:String=state.get("focus","")
		var slot:String=focus if not focus.is_empty() and LootRules._draw(dice,100)<int(rules.focus_percent) else ShopRules.SLOTS[LootRules._draw(dice,ShopRules.SLOTS.size())]
		var roll:=LootRules._draw(dice,100);var total:=0;var quality:="yellow"
		for q in ["white","blue","yellow","orange","green"]:
			total+=int((rules.boss_weights if boss else rules.normal_weights).get(q,0))
			if roll<total:quality=q;break
		if pity:quality="orange" if LootRules._draw(dice,2)==0 else "green"
		if level<int(rules.min_special_level) and quality in ["orange","green"]:quality="yellow"
		var special:Array=BuildRules.rules.items.filter(func(b:Dictionary)->bool:return BuildRules.compatible(b.id,job,slot,quality=="orange"))
		if quality in ["orange","green"] and special.is_empty():
			if pity:
				var choices:Array=BuildRules.rules.items.filter(func(b:Dictionary)->bool:return int(b.job)==job);var b:Dictionary=choices[LootRules._draw(dice,choices.size())]
				slot=b.legend_slot if quality=="orange" else BuildRules.rules.set_slots[LootRules._draw(dice,4)]
			else:quality="green" if quality=="orange" else "orange"
			special=BuildRules.rules.items.filter(func(b:Dictionary)->bool:return BuildRules.compatible(b.id,job,slot,quality=="orange"))
			if special.is_empty():quality="yellow"
		var exact:=LootRules._draw(dice,100)<80
		var candidates:Array=ShopRules.catalog.items.filter(func(d:Dictionary)->bool:return ShopRules.is_equipment(d) and d.slot==slot and ShopRules.equipment_error(d,job,gender).is_empty() and (int(d.job)==job if exact else int(d.job)<0))
		if candidates.is_empty():candidates=ShopRules.catalog.items.filter(func(d:Dictionary)->bool:return ShopRules.is_equipment(d) and d.slot==slot and ShopRules.equipment_error(d,job,gender).is_empty())
		var d:Dictionary=candidates[LootRules._draw(dice,candidates.size())];var item_seed:=LootRules._draw(dice,0xffffffff)
		var item:=LootRules.roll_special(d.id,clampi(level,1,60),quality,special[LootRules._draw(dice,special.size())].id,item_seed) if quality in ["orange","green"] else LootRules.roll(d.id,clampi(level,1,60),quality,item_seed)
		if not state.skins.has(d.id):state.skins.append(d.id)
		ids.append(item.id)
		if used<60:state.items.append(item);used+=1
		else:state.pending.append(item)
	return ids
