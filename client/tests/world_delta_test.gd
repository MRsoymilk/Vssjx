extends Node
var checks := 0
var failures := 0
const SELF_ID := "10000000-0000-4000-8000-000000000001"
const PEER_ID := "10000000-0000-4000-8000-000000000002"
const EPOCH := "20000000-0000-4000-8000-000000000001"
var world: OnlineWorldClient

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)

func entity(id: String, net_id: int) -> Dictionary:
	return {"id": id, "net_id": net_id, "display_name": "测试%d" % net_id, "job": 2, "gender": 0, "cell": [10, 16], "next_cell": null, "segment_progress": 0, "entity_revision": "0", "last_input_seq": "0", "world_epoch": "1"}

func packet(seq: int, entered: Array = [], removed: Array = [], moves: Array = [], epoch: String = EPOCH) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = true
	buffer.put_data("VWD2".to_ascii_buffer())
	buffer.put_data(epoch.replace("-", "").hex_decode())
	buffer.put_u64(seq)
	var json := JSON.stringify(entered).to_utf8_buffer()
	buffer.put_u32(json.size())
	buffer.put_u16(removed.size())
	buffer.put_u16(moves.size())
	buffer.put_data(json)
	for net_id in removed: buffer.put_u32(net_id)
	for move in moves:
		buffer.put_u32(move[0])
		buffer.put_u16(move[1])
		buffer.put_u16(move[2])
		buffer.put_u16(move[3])
		buffer.put_u64(move[4])
		buffer.put_u64(move[5])
	var bytes := buffer.data_array
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	bytes.append_array(digest.finish())
	return bytes

func reject(bytes: PackedByteArray, message: String) -> void:
	var before := world.entities.duplicate(true)
	var ids := world._net_ids.duplicate()
	var seq := world._world_seq
	check(not world._receive_delta(bytes), message)
	check(before == world.entities and ids == world._net_ids and seq == world._world_seq, "Rejected publication never half-installs")

func _ready() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../shared/protocol/world-sync-v2.json")))
	check(packet(7).hex_encode() == fixture.golden_quiet_seq7_hex, "Quiet encoding matches Rust golden vector")
	check(packet(8, [], [], [[1, 522, 523, 450, 1, 7]]).hex_encode() == fixture.golden_motion_seq8_hex, "Motion encoding matches Rust golden vector")
	world = OnlineWorldClient.new()
	add_child(world)
	world.set_process(false)
	world.world_ready = true
	world.character_id = SELF_ID
	world.world_stream = EPOCH
	world._world_seq = 10
	world.entities = {SELF_ID: entity(SELF_ID, 1)}
	world._net_ids = {1: SELF_ID}
	var offline := Game.player.duplicate(true)
	check(world._receive_delta(packet(11, [entity(PEER_ID, 2)])), "Ordered enter installed")
	check(world.entities.size() == 2, "Peer is visible without replacing own state")
	check(world._receive_delta(packet(12, [], [], [[2, 522, 523, 450, 1, 7]])), "Compact movement installed")
	check(world.entities[PEER_ID].cell == [10, 16] and world.entities[PEER_ID].next_cell == [11, 16] and world.entities[PEER_ID].last_input_seq == "7", "Movement fields reconstruct original entity schema")
	check(world._receive_delta(packet(13, [entity(PEER_ID, 3)], [2])), "Atomic leave/re-enter with same UUID and new network ID")
	check(not world._net_ids.has(2) and world._net_ids[3] == PEER_ID and world.entities.size() == 2, "No duplicate or ghost peer")
	reject(packet(15), "Sequence gap rejected")
	reject(packet(13), "Duplicate old publication rejected")
	reject(packet(14, [], [], [], SELF_ID), "Wrong world stream rejected")
	var bad := packet(14)
	bad[-1] = bad[-1] ^ 1
	reject(bad, "Corrupt digest rejected")
	reject(packet(14, [], [1]), "Own entity cannot silently disappear")
	reject(packet(14, [], [999]), "Unknown leave rejected")
	reject(packet(14, [], [3, 3]), "Duplicate leave rejected")
	reject(packet(14, [entity(PEER_ID, 4)]), "Duplicate identity without leave rejected")
	reject(packet(14, [entity("30000000-0000-4000-8000-000000000001", 1)]), "Network ID collision rejected")
	reject(packet(14, [], [], [[3, 522, 523, 450, 1, 8], [999, 522, 523, 450, 1, 8]]), "Invalid trailing record rejects entire motion batch")
	reject(packet(14, [], [], [[3, 522, 523, 450, 1, 8], [3, 522, 523, 450, 1, 8]]), "Duplicate motion rejected")
	reject(packet(14, [], [], [[3, 522, 525, 450, 1, 8]]), "Non-adjacent segment rejected")
	reject(packet(14, [], [], [[3, 1024, 65535, 0, 1, 8]]), "Out-of-map cell rejected")
	reject(packet(14, [], [], [[3, 522, 523, 1001, 1, 8]]), "Out-of-range progress rejected")
	reject(packet(14, [], [], [[3, 522, 65535, 450, 1, 8]]), "Stationary entity cannot retain a moving-segment progress")
	check(world._receive_delta(packet(14, [], [], [[3, 522, 523, 450, 2, 8]])), "Valid next packet still installs after preflight rejections")
	reject(packet(15, [], [], [[3, 522, 523, 450, 1, 9]]), "Entity revision regression rejected")
	check(world._receive_delta(packet(15)), "Quiet authoritative tick advances frontier without replacing entities")
	check(world.entities.size() == 2 and world._world_seq == 15, "Quiet tick retains all players")
	check(world._receive_delta(packet(16, [], [3])), "Leave removes exactly one peer")
	var many: Array = []
	for index in range(2, 1001): many.append(entity("40000000-0000-4000-8000-%012d" % index, index + 10))
	check(world._receive_delta(packet(17, many)), "All 1000 identities install, no visibility truncation")
	check(world.entities.size() == 1000 and world._net_ids.size() == 1000, "Client keeps the complete population")
	reject(packet(18, [entity(PEER_ID, 2000)]), "Population limit rejects extra player atomically")
	check(Game.player == offline, "Replication never mutates offline state")
	var complete := world.entities.duplicate(true)
	world._state = "ready"
	world.stream = EPOCH
	world._seq = 1
	world._receive({"type": "snapshot.begin", "stream_id": EPOCH, "seq": "2", "snapshot_id": SELF_ID, "count": 1, "chunks": 1, "base_world_seq": "1"}, PackedByteArray())
	check(not world.world_ready and world.entities == complete and world._world_seq == 17, "Unsolicited full snapshot cannot rewind a live delta stream")
	world.queue_free()
	print("WORLD DELTA PROTOCOL: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
