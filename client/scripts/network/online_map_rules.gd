class_name OnlineMapRules
extends RefCounted
signal changed
var map_id:=""
var revision:=-1
var rules:Dictionary={}
func clear()->void:map_id="";revision=-1;rules={}
static func cell(value:Variant,map:String)->bool:
	if not value is Array or value.size()!=2 or not OnlinePve.integer(value[0],0,31) or not OnlinePve.integer(value[1],0,31):return false
	return not SharedWorldMap.load_data(map).blocked[int(value[1])*32+int(value[0])]
func receive(packet:Dictionary,expected_map:String)->bool:
	if packet.get("version")!=1 or packet.get("map_id")!=expected_map or not SharedWorldMap.exists(expected_map) or not OnlinePve.decimal(packet.get("revision")):return false
	var d:Variant=packet.get("rules")
	if not d is Dictionary or not d.get("entry_enabled") is bool or not d.get("station_enabled") is bool or not cell(d.get("spawn"),expected_map) or not cell(d.get("station"),expected_map):return false
	if not d.get("portals") is Array or d.portals.size()>32 or not d.get("residents") is Array or d.residents.size()>32 or not d.get("gathering") is Array or d.gathering.size()>16:return false
	var seen:={}
	for p in d.portals:
		if not p is Dictionary or not p.get("id") is String or p.id.length()>32 or seen.has(p.id) or not cell(p.get("cell"),expected_map) or not p.get("cells") is Array or p.cells.is_empty() or p.cells.size()>32 or not SharedWorldMap.exists(p.get("target_map")) or not p.get("enabled") is bool or not p.get("legacy") is bool or not p.get("name") is String or p.name.length()>64:return false
		seen[p.id]=true
		for c in p.cells:
			if not cell(c,expected_map):return false
		if not p.has("arrival") or (p.arrival!=null and not cell(p.arrival,p.target_map)):return false
	seen={}
	var originals:={}
	for p in SharedWorldMap.population(expected_map):originals[p.id]=true
	if d.residents.size()!=originals.size():return false
	for p in d.residents:
		if not p is Dictionary or not originals.has(p.get("id")) or seen.has(p.id) or not p.get("enabled") is bool or not cell(p.get("cell"),expected_map) or not OnlinePve.integer(p.get("respawn_seconds"),1,86400):return false
		seen[p.id]=true
	var gathering:Array=d.gathering.duplicate(true)
	for n in gathering:
		if not n is Dictionary or n.get("map_id")!=expected_map or not n.get("enabled") is bool or not cell(n.get("cell"),expected_map):return false
		n.available_at_ms=0
	if not GatheringRules.valid({"version":"gathering-v1","stack_limit":999,"materials":{},"nodes":gathering,"active":null}):return false
	if map_id==expected_map and int(packet.revision)<revision:return true
	if map_id==expected_map and int(packet.revision)==revision:return rules==d
	map_id=expected_map;revision=int(packet.revision);rules=d.duplicate(true);changed.emit();return true
func exits(id:String)->Array:
	if id!=map_id or rules.is_empty():return SharedWorldMap.exits(id)
	return rules.portals.filter(func(p:Dictionary)->bool:return p.enabled)
func exit_at(id:String,point:Vector2i)->Dictionary:
	for p in exits(id):
		for c in p.get("cells",[p.cell]):
			if point==Vector2i(int(c[0]),int(c[1])):return p
	return {}
func portal(id:String)->Dictionary:
	if id!=map_id or rules.is_empty():return SharedWorldMap.portal(id)
	for p in exits(id):
		if p.get("legacy",false):return p
	return {}
func station(id:String)->Vector2i:
	return Vector2i(int(rules.station[0]),int(rules.station[1])) if id==map_id and not rules.is_empty() else AIWorld.station(id)
func station_enabled(id:String)->bool:return id!=map_id or rules.is_empty() or rules.station_enabled
