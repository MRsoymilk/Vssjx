extends Node
var checks := 0
var failures := 0
const ID := "10000000-0000-4000-8000-000000000001"

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error("FAIL: " + message)

func ready_packet() -> Dictionary:
	return {"type":"auth.ready", "character_id":ID, "config_hash":"test", "map_id":"qingyun_trail", "instance_id":"main", "game_session_id":ID, "stream_id":ID, "world_stream_id":ID, "connection_epoch":"1", "world_epoch":"1", "world_sync_version":2}

func client() -> OnlineWorldClient:
	var world := OnlineWorldClient.new()
	world.character_id = ID
	world.config_hash = "test"
	world._state = "syncing"
	return world

func _ready() -> void:
	var world := client()
	check(world.world_time_seconds() == -1.0, "No online lighting source before authenticated clock sync")
	var packet := ready_packet()
	packet.server_time_ms = 7200000
	world._receive(packet, PackedByteArray())
	check(world.stream == ID and absf(world.world_time_seconds() - 7200.0) < 0.1, "Handshake installs server time before publishing the map")
	world._world_clock_tick -= 1250
	check(absf(world.world_time_seconds() - 7201.25) < 0.1, "Monotonic elapsed time advances without using local wall time")
	world._failed("TEST_RECONNECT")
	check(world.world_time_seconds() > 7201.0, "Disconnect does not reset the world clock")
	world._reconnect_map()
	check(world.world_time_seconds() > 7201.0, "Map transfer does not reset the world clock")
	world.stream = ID
	world._receive({"type":"pong", "server_time_ms":10800000.0}, PackedByteArray())
	check(absf(world.world_time_seconds() - 10800.0) < 0.1, "Heartbeat resynchronizes even when the server clock corrects")
	world._receive({"type":"pong"}, PackedByteArray())
	check(world.world_time_seconds() >= 10800.0, "Legacy heartbeat cannot erase a synchronized clock")
	var before := world._world_clock_ms
	for value in [null, "7200000", -1, 0, 0.5, INF, NAN, 253402300800000]:
		check(not world._sync_world_clock({"server_time_ms":value}) and world._world_clock_ms == before, "Invalid timestamps never mutate the clock")
	world._receive({"type":"pong", "server_time_ms":"invalid"}, PackedByteArray())
	check(world._state == "failed", "Malformed heartbeat is rejected by the actual receive path")
	world.leave()
	check(world.world_time_seconds() == -1.0, "Leaving clears time before another server/character can start")
	world.free()
	world = client()
	world._receive(ready_packet(), PackedByteArray())
	check(world.stream == ID and world.world_time_seconds() == -1.0, "Legacy server handshake remains usable without a lighting clock")
	world.free()
	world = client()
	packet = ready_packet(); packet.server_time_ms = -1
	world._receive(packet, PackedByteArray())
	check(world._state == "failed" and world.stream.is_empty(), "Invalid handshake time cannot half-install the new map/stream")
	world.free()
	world = client()
	world._receive({"type":"pong", "server_time_ms":7200000}, PackedByteArray())
	check(world._state == "failed" and world.world_time_seconds() == -1.0, "Pre-authentication pong cannot install time")
	world.free()
	print("WORLD CLOCK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
