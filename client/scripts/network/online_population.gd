class_name OnlinePopulation
extends RefCounted
signal changed(entities: Dictionary)
var entities: Dictionary = {}
var epoch := ""
var revision := -1
const ARTS := {"npc": "hero/mfs", "wolf": "monster/langw", "spirit": "monster/hs1", "guardian": "monster/xt1", "boss": "monster/nt1"}

func clear() -> void:
	entities = {}
	epoch = ""
	revision = -1
	changed.emit(entities)

func receive(packet: Dictionary) -> bool:
	if not OnlineWorldClient._uuid(packet.get("epoch")) or not OnlineWorldClient._decimal(packet.get("revision")): return false
	var values: Variant = packet.get("entities")
	if not values is Array or values.size() > 32: return false
	if packet.epoch == epoch and int(packet.revision) <= revision: return int(packet.revision) == revision
	var next := {}
	for value in values:
		if not value is Dictionary or not value.get("id") is String or RegEx.create_from_string("^[a-z_]{1,32}$").search(value.id) == null or next.has(value.id): return false
		if not value.get("kind") in ARTS or value.get("art") != ARTS[value.kind] or not OnlineAccount.valid_nickname(value.get("name", "")): return false
		if not OnlineWorldClient._cell(value.get("cell")) or (value.get("next_cell") != null and not OnlineWorldClient._cell(value.next_cell)): return false
		if value.next_cell != null and absi(int(value.cell[0]) - int(value.next_cell[0])) + absi(int(value.cell[1]) - int(value.next_cell[1])) != 1: return false
		if not OnlineWorldClient._integer(value.get("segment_progress"), 0, 1000) or not OnlineWorldClient._decimal(value.get("world_epoch")) or not OnlineWorldClient._decimal(value.get("entity_revision")): return false
		for field in ["level", "hp", "attack", "defense", "gold", "xp"]:
			if not OnlineWorldClient._integer(value.get(field), 0, 100000): return false
		next[value.id] = value.duplicate(true)
	epoch = packet.epoch
	revision = int(packet.revision)
	entities = next
	changed.emit(entities)
	return true
