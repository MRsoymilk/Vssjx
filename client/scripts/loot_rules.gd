class_name LootRules
extends RefCounted
## Offline and wire validation for character-owned equipment; never invents online loot.
static var rules:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/loot-v1.json"))
static var catalog_hash:String=FileAccess.get_file_as_string("res://assets/data/loot-v1.json").sha256_text()
static func uuid()->String:
	var bytes:=Crypto.new().generate_random_bytes(16);bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
	var h:=bytes.hex_encode();return "%s-%s-%s-%s-%s"%[h.substr(0,8),h.substr(8,4),h.substr(12,4),h.substr(16,4),h.substr(20,12)]
static func empty()->Dictionary:return {"version":1,"items":[],"pending":[],"scrap":0,"essence":0,"kills":0,"bosses":0,"difficulty":1,"skins":[]}
static func bounds(kind:String,level:int)->Vector2i:
	var v:Array=rules.affixes[kind];return Vector2i(maxi(1,int(v[0])*level/60),maxi(1,int(v[1])*level/60))
static func _draw(dice:Array,limit:int)->int:
	dice[0]=(int(dice[0])*1664525+1013904223)&0xffffffff
	return int(dice[0])%limit
static func roll(template:String,level:int,quality:String,seed:int,id:String="")->Dictionary:
	var d:=ShopRules.item(template)
	if not ShopRules.is_equipment(d) or level<1 or level>60 or quality not in ["white","blue","yellow"]:return {}
	var result:Dictionary={"id":uuid() if id.is_empty() else id,"template":template,"level":level,"quality":quality,"equipped":false,"legacy":false,"affixes":[],"upgrade":0,"reroll_index":null,"legendary":null,"set_id":null,"skin":null,"legacy_attack":0,"legacy_defense":0}
	var dice:=[seed];var pool:Array=rules.pools[d.slot].duplicate()
	for i in int(rules.quality_affixes[quality]):
		var kind:String=pool.pop_at(_draw(dice,pool.size()));var r:=bounds(kind,level)
		result.affixes.append({"kind":kind,"value":r.x+_draw(dice,r.y-r.x+1)})
	return result
static func valid_item(i:Variant,job:int,gender:int)->bool:
	if not i is Dictionary:return false
	var d:=ShopRules.item(str(i.get("template","")))
	if not ShopRules.is_equipment(d) or not ShopRules.equipment_error(d,job,gender).is_empty():return false
	if not i.get("id") is String or RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").search(i.id)==null:return false
	if not ShopRules._integer(i.get("level"),1,60) or not ShopRules._integer(i.get("upgrade",0),0,6) or not i.get("quality") in rules.quality_affixes:return false
	if not i.get("equipped") is bool or not i.get("legacy") is bool or i.legacy!=(i.quality=="legacy"):return false
	if not i.get("affixes") is Array or i.affixes.size()!=int(rules.quality_affixes[i.quality]):return false
	if i.legacy and (i.level!=1 or i.upgrade!=0 or i.get("legacy_attack")!=d.attack or i.get("legacy_defense")!=d.defense):return false
	if i.get("legendary")!=null or i.get("set_id")!=null:return false
	if i.get("reroll_index")!=null and not ShopRules._integer(i.reroll_index,0,i.affixes.size()-1):return false
	if i.get("skin")!=null:
		var skin:=ShopRules.item(str(i.skin))
		if skin.get("slot")!=d.slot or not ShopRules.equipment_error(skin,job,gender).is_empty():return false
	var seen:={}
	for a in i.affixes:
		if not a is Dictionary or not a.get("kind") in rules.pools[d.slot] or seen.has(a.kind):return false
		var r:=bounds(a.kind,int(i.level))
		if not ShopRules._integer(a.get("value"),r.x,r.y):return false
		seen[a.kind]=true
	return true
static func valid(s:Variant,job:int,gender:int)->bool:
	if not s is Dictionary or s.get("version")!=1 or not s.get("items") is Array or not s.get("pending") is Array or s.items.size()>90 or s.pending.size()>20:return false
	for key in ["scrap","essence","kills","bosses"]:
		if not ShopRules._integer(s.get(key),0,1000000000):return false
	if not ShopRules._integer(s.get("difficulty"),1,3) or not s.get("skins") is Array or s.skins.size()>ShopRules.catalog.items.size():return false
	var ids:={};var slots:={};var legacy:={};var skins:={}
	for i in s.items+s.pending:
		if not valid_item(i,job,gender) or ids.has(i.id):return false
		ids[i.id]=true
		if i.legacy:
			if legacy.has(i.template):return false
			legacy[i.template]=true
		if i.equipped:
			var slot:String=ShopRules.item(i.template).slot
			if slots.has(slot) or s.pending.has(i):return false
			slots[slot]=true
	for id in s.skins:
		if not id is String or skins.has(id):return false
		var d:=ShopRules.item(id)
		if not ShopRules.is_equipment(d) or not ShopRules.equipment_error(d,job,gender).is_empty():return false
		skins[id]=true
	return true
static func sync_legacy(player:Dictionary)->void:
	if not player.has("loot_state"):player.loot_state=empty()
	var s:Dictionary=player.loot_state;var gear:=ShopRules.local_state(player)
	s.items=s.items.filter(func(i:Dictionary)->bool:return not i.legacy or gear.owned.has(i.template))
	for id in gear.owned:
		var d:=ShopRules.item(id)
		if not ShopRules.is_equipment(d) or not ShopRules.equipment_error(d,int(player.job),int(player.gender)).is_empty():continue
		if not s.skins.has(id):s.skins.append(id)
		var found:Dictionary={}
		for i in s.items:
			if i.legacy and i.template==id:found=i;break
		if found.is_empty():
			found={"id":uuid(),"template":id,"level":1,"quality":"legacy","legacy":true,"affixes":[],"upgrade":0,"reroll_index":null,"legendary":null,"set_id":null,"skin":null,"legacy_attack":int(d.attack),"legacy_defense":int(d.defense)};s.items.append(found)
		found.equipped=ShopRules.equipped_id(gear,d.slot)==id
static func extra_bag(s:Dictionary)->int:return s.get("items",[]).filter(func(i:Dictionary)->bool:return not i.legacy and not i.equipped).size()
static func base(i:Dictionary)->Array:
	if i.legacy:return [int(i.legacy_attack),int(i.legacy_defense),0,0]
	var d:Dictionary=rules.base[ShopRules.item(i.template).slot];var l:=int(i.level);var scale:=100+2*int(i.upgrade)
	return [(int(d.power_base)+l*int(d.power_step))*scale/100,(int(d.defense_base)+l*int(d.defense_step_bp)/10000)*scale/100,l*int(d.hp_step)*scale/100,l*int(d.mp_step)*scale/100]
static func look(s:Dictionary,original:Array)->Array:
	var result:=original.duplicate()
	for i in s.get("items",[]):
		if not i.equipped or i.legacy:continue
		var d:=ShopRules.item(i.skin if i.get("skin")!=null else i.template);var slot:String=ShopRules.item(i.template).slot
		if slot in ["weapon","armor","hat"]:result[["weapon","armor","hat"].find(slot)]=int(d.head_visual if slot=="hat" else d.visual)
	return result
static func apply_stats(s:Dictionary,stats:Dictionary,job:int)->void:
	if not stats.has("balance"):return
	var b:Dictionary=stats.balance;var channel:="magic_attack" if job==2 else "physical_attack";var hp:=0;var mp:=0;var percent:=0
	for i in s.get("items",[]):
		if not i.equipped or i.legacy:continue
		var v:=base(i);b[channel]+=int(v[0]);CharacterAttributeRules.gear_bonus(stats,0,int(v[1]));hp+=int(v[2]);mp+=int(v[3])
		for a in i.affixes:
			var value:=int(a.value)
			match a.kind:
				"power":b[channel]+=value
				"hp":hp+=value
				"mana":mp+=value
				"hp_percent":percent+=value
				"defense":CharacterAttributeRules.gear_bonus(stats,0,value)
				"crit","hit","evasion":
					var key:String={"crit":"crit_bonus","hit":"hit_bonus","evasion":"evade_bonus"}[a.kind]
					for index in 2:b[key][index]+=value
				_:
					var key:String={"crit_damage":"crit_damage_bp","damage":"increased_bp","dot":"dot_bp","penetration":"penetration_bp","reduction":"reduction_bp"}[a.kind]
					b[key]+=value
	stats.hp=mini(1000000,(int(stats.hp)+hp)*(10000+mini(percent,4000))/10000);stats.mp=mini(1000000,int(stats.mp)+mp);stats.attack=b[channel]
static func apply_local(player:Dictionary,action:String,id:String)->String:
	if player.get("corpse") is Dictionary:return "SOUL_STATE"
	sync_legacy(player)
	var s:Dictionary=player.loot_state;var gear:=ShopRules.local_state(player);var bag:=ShopRules.bag_slots(gear,int(player.potions))+extra_bag(s)
	if action=="gear_claim":
		if bag>=60:return "BAG_FULL"
		for i in s.pending:
			if i.id==id:s.items.append(i);s.pending.erase(i);return ""
		return "INSTANCE_NOT_OWNED"
	var item:Dictionary={}
	for i in s.items:
		if i.id==id:item=i;break
	if item.is_empty():return "INSTANCE_NOT_OWNED"
	var slot:String=ShopRules.item(item.template).slot
	if action=="gear_equip":
		if int(item.level)>int(player.level):return "EQUIPMENT_LEVEL_REQUIRED"
		if item.equipped:return "EQUIPMENT_UNCHANGED"
		for i in s.items:
			if ShopRules.item(i.template).slot==slot:i.equipped=false
		gear.slots[slot]=item.template if item.legacy else null;item.equipped=true
	elif action=="gear_unequip":
		if not item.equipped:return "NOT_EQUIPPED"
		if bag>=60:return "BAG_FULL"
		item.equipped=false
		if item.legacy:gear.slots[slot]=null
	else:return "INVALID_LOOT_COMMAND"
	gear.weapon=gear.slots.weapon;gear.armor=gear.slots.armor;ShopRules._store(player,gear)
	return ""
