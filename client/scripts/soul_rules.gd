class_name SoulRules
extends RefCounted
## The existing map spawn is also its one fixed resurrection point.
static func resurrection_point(map_id: String) -> Vector2i:
	var data := SharedWorldMap.load_data(map_id)
	return Vector2i(data.spawn[0],data.spawn[1])

static func valid_corpse(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=3 or not value.get("id") is String: return false
	if RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z").search(value.id)==null:return false
	if not SharedWorldMap.exists(value.get("map_id")) or not value.get("cell") is Array or value.cell.size()!=2:return false
	for coordinate in value.cell:
		if not ShopRules._integer(coordinate,0,31):return false
	var data:=SharedWorldMap.load_data(value.map_id)
	return not data.blocked[int(value.cell[1])*int(data.width)+int(value.cell[0])]

static func create(map_id: String, cell: Vector2i) -> Dictionary:
	var bytes:=Crypto.new().generate_random_bytes(16)
	bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
	var hex:=bytes.hex_encode()
	return {"id":"%s-%s-%s-%s-%s"%[hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)],"map_id":map_id,"cell":[cell.x,cell.y]}

static func nearby(corpse: Dictionary, map_id: String, cell: Vector2i) -> bool:
	return corpse.get("map_id")==map_id and absi(int(corpse.cell[0])-cell.x)+absi(int(corpse.cell[1])-cell.y)<=2

static func hint(corpse: Dictionary) -> String:
	return "灵魂状态：前往 %s（%d，%d）寻回自己的尸体。靠近坟堆后交互复活。"%[SharedWorldMap.title(corpse.map_id),int(corpse.cell[0]),int(corpse.cell[1])]
