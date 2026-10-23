class_name GatheringRules
extends RefCounted
const MATERIALS={"iron":"铁矿","copper":"铜矿","gancao":"甘草","danggui":"当归"}
static var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/gathering-v1.json"))
const RECIPE_PATH="res://assets/data/gathering-recipes-v1.json"
static var recipes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(RECIPE_PATH))
static var recipes_hash:String=FileAccess.get_file_as_string(RECIPE_PATH).replace("\r\n","\n").sha256_text()
static func recipe(id:String)->Dictionary:
	for entry in recipes.recipes:
		if entry.id==id:return entry
	return {}
static func recipe_text(id:String,batches:int=1)->String:
	var entry:=recipe(id);var inputs:=PackedStringArray()
	if entry.is_empty():return ""
	for material in entry.materials:inputs.append("%s×%d"%[MATERIALS[material],int(entry.materials[material])*batches])
	return "%s → %s×%d"%["＋".join(inputs),"炼材" if entry.output=="scrap" else "回春散",int(entry.quantity)*batches]
static func craft_error(id:String,batches:int,materials:Dictionary,scrap:int,potions:int,bag_count:int)->String:
	var entry:=recipe(id)
	if entry.is_empty() or batches<1 or batches>int(recipes.batch_limit):return "INVALID_GATHER_COMMAND"
	var output:=int(entry.quantity)*batches
	if entry.output=="scrap" and scrap>1000000000-output:return "CRAFT_RESOURCE_FULL"
	if entry.output=="potion" and (potions>99-output or (potions==0 and bag_count>=60)):return "BAG_FULL"
	for material in entry.materials:
		if int(materials.get(material,0))<int(entry.materials[material])*batches:return "MATERIALS_INSUFFICIENT"
	return ""
static func craft_local(player:Dictionary,id:String,batches:int)->String:
	var gear:=ShopRules.local_state(player)
	var error:=craft_error(id,batches,player.get("gathering",{}).get("materials",{}),int(player.get("loot_state",{}).get("scrap",0)),int(player.potions),ShopRules.bag_slots(gear,int(player.potions))+LootRules.extra_bag(player.get("loot_state",{})))
	if not error.is_empty():return error
	var entry:=recipe(id)
	for material in entry.materials:
		player.gathering.materials[material]=int(player.gathering.materials[material])-int(entry.materials[material])*batches
		if int(player.gathering.materials[material])==0:player.gathering.materials.erase(material)
	if entry.output=="scrap":
		if not player.has("loot_state"):player.loot_state=LootRules.empty()
		player.loot_state.scrap=int(player.loot_state.scrap)+int(entry.quantity)*batches
	else:player.potions=int(player.potions)+int(entry.quantity)*batches
	return ""
static func definition(id:String)->Dictionary:
	for node in catalog.nodes:
		if node.id==id:return node
	return {}
static func nodes_for(map_id:String)->Array:
	var result:Array=[]
	for node in catalog.nodes:
		if node.map_id==map_id:
			var value:Dictionary=node.duplicate(true);value.available_at_ms=int(Game.player.get("gathering",{}).get("respawns",{}).get(node.id,0));result.append(value)
	return result
static func valid_local(value:Variant)->bool:
	if not value is Dictionary or not value.get("materials") is Dictionary or value.materials.size()>4 or not value.get("respawns") is Dictionary or value.respawns.size()>catalog.nodes.size():return false
	for id in value.materials:
		if not MATERIALS.has(id) or not OnlinePve.integer(value.materials[id],1,999):return false
	for id in value.respawns:
		if definition(id).is_empty() or not OnlinePve.integer(value.respawns[id],0,253402300799999):return false
	return true
static func kind(material:String)->String:return "ore" if material in ["iron","copper"] else "herb"
static func valid(v:Variant)->bool:
	if not v is Dictionary or v.get("version")!="gathering-v1" or v.get("stack_limit")!=999 or not v.get("materials") is Dictionary or v.materials.size()>4 or not v.get("nodes") is Array or v.nodes.size()>16 or not v.has("active"):return false
	if v.has("recipes_sha256") and (not v.recipes_sha256 is String or v.recipes_sha256.length()!=64 or not v.recipes_sha256.is_valid_hex_number()):return false
	for id in v.materials:
		if not MATERIALS.has(id) or not OnlinePve.integer(v.materials[id],1,999):return false
	var seen:={}
	for n in v.nodes:
		if not n is Dictionary or not n.get("id") is String or n.id.length()>32 or seen.has(n.id) or not n.get("map_id") is String or not MATERIALS.has(n.get("material")) or not n.get("cell") is Array or n.cell.size()!=2:return false
		seen[n.id]=true
		for coordinate in n.cell:
			if not OnlinePve.integer(coordinate,0,31):return false
		if not OnlinePve.integer(n.get("duration_ms"),1000,60000) or not OnlinePve.integer(n.get("respawn_ms"),1000,86400000) or not OnlinePve.integer(n.get("min_quantity"),1,10) or not OnlinePve.integer(n.get("max_quantity"),int(n.min_quantity),10) or not OnlinePve.integer(n.get("available_at_ms"),0,253402300799999):return false
	if v.active!=null:
		var a:Variant=v.active
		if not a is Dictionary or not OnlinePve.uuid(a.get("token")) or not a.get("node_id") is String or not a.get("map_id") is String or not MATERIALS.has(a.get("material")) or not OnlinePve.integer(a.get("duration_ms"),1000,60000) or not OnlinePve.integer(a.get("ready_at_ms"),1,253402300799999) or not OnlinePve.integer(a.get("expires_at_ms"),int(a.ready_at_ms)+1,253402300799999):return false
		for key in ["owner_epoch","connection_epoch","position_revision","revision"]:
			if not OnlinePve.decimal(a.get(key)):return false
		if not a.get("cell") is Array or a.cell.size()!=2:return false
		for coordinate in a.cell:
			if not OnlinePve.integer(coordinate,0,31):return false
	return true

static func active(model:OnlinePve)->Dictionary:
	var value:Variant=model.state.get("gathering",{}).get("active")
	return value if value is Dictionary else {}
