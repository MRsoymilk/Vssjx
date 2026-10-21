class_name OnlineWorldClient
extends Node
## Full initial baseline + bounded, authenticated world deltas. No Game dependency.
signal changed(entities: Dictionary)
signal status_changed(text: String)
signal map_changed(map_id: String)
signal map_transfer_started
signal connection_failed
signal movement_cancelled
const MAP_PATH := SharedWorldMap.MAP_PATH
var map_id := "qingyun_trail"
var world_ready := false
var team_active := false
var team_following := false
var team_marks: Dictionary = {}
var team_travel: Dictionary = {}
var _team_version := 0
var character_id := ""
var entities: Dictionary = {}
var server := ""
var login_session := ""
var config_hash := ""
var game_session := ""
var connection_epoch := ""
var world_epoch := ""
var stream := ""
var world_stream := ""
var _world_seq := 0
var _net_ids: Dictionary = {}
var socket: WebSocketPeer
var chat := OnlinePublicChat.new()
var announcements := OnlineAnnouncements.new()
var population := OnlinePopulation.new()
var pve := OnlinePve.new()
var duel := OnlineDuel.new()
var _duel_version := 0
var _pve_version := 0
var _maps_version := 0
var _shop_version := 0
var appearances: Dictionary = {}
var _ticket := ""
var _announcement_version := 0
var _population_version := 0
var _state := "idle"
var _deadline := 0.0
var _heartbeat := 0.0
var _last_received := 0.0
var _retry_at := 0.0
var _attempts := 0
var _input_seq := 0
var _seq := 0
var _last_input_at := -100
var _pending_motion: Dictionary = {}
var _motion_waiting := 0
var _motion_retry_at := 0
var _snapshot: Dictionary = {}
var _records: Dictionary = {}
var _digest: HashingContext
var _chunk_index := 0
var _snapshot_bytes := 0

func _ready() -> void:
	config_hash = FileAccess.get_sha256(MAP_PATH)
	OnlineAccount.world_ticket_received.connect(_on_ticket)
	duel.send_requested.connect(func(packet: Dictionary) -> void:
		if socket != null and world_ready:
			if socket.send_text(JSON.stringify(packet)) != OK: _failed("SEND_FAILED", true)
	)
	pve.send_requested.connect(func(packet: Dictionary) -> void:
		if socket != null and world_ready:
			if socket.send_text(JSON.stringify(packet)) != OK: _failed("SEND_FAILED", true)
	)
	chat.send_requested.connect(func(message: Dictionary) -> void:
		if socket != null and world_ready:
			if socket.send_text(JSON.stringify(message)) != OK: _failed("SEND_FAILED", true)
	)

func start(id: String) -> void:
	character_id = id
	server = OnlineAccount.server_address
	login_session = OnlineAccount.login_session_id
	pve.bind_character(id, server)
	duel.bind_character(id)
	_attempts = 0
	_state = "request"
	_retry_at = 0.0
	status_changed.emit("正在申请入场票据……")

func leave() -> void:
	_pending_motion.clear()
	if socket != null:
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN: socket.send_text(JSON.stringify({"type": "world.leave"}))
		socket.close()
	socket = null
	_state = "idle"
	_ticket = ""
	world_ready = false
	team_following=false;team_marks={};team_travel={}
	entities = {}
	_net_ids = {}
	_snapshot = {}
	_records = {}
	chat.clear()
	announcements.clear()
	population.clear()
	pve.disconnect_channel()
	duel.clear()

func _exit_tree() -> void:
	leave()

func _failed(code: String, retry: bool = false) -> void:
	duel.disconnect_channel()
	connection_failed.emit()
	_pending_motion.clear()
	chat.disconnect_channel()
	announcements.clear()
	population.clear()
	pve.disconnect_channel()
	world_ready = false
	_ticket = ""
	_snapshot = {}
	_records = {}
	_net_ids = {}
	if socket != null: socket.close()
	socket = null
	var messages := {"WORLD_PROTOCOL_MISMATCH": "世界协议版本不一致，请更新客户端。", "CHARACTER_BUSY": "该角色已在另一登录会话中在线。", "SESSION_REPLACED": "连接已被同会话的新连接接管。", "SESSION_REVOKED": "账号会话失效，请重新登录。", "CONFIG_MISMATCH": "地图版本不一致，请更新客户端。", "WORLD_FULL": "服务器人数已满，请稍后再试。", "DATABASE_UNAVAILABLE": "数据库暂不可用，移动已停止。", "PVE_CATALOG_MISMATCH": "客户端与服务器的地图数据版本不一致，请同步更新后重试。", "SHOP_CATALOG_MISMATCH": "客户端与服务器的商城数据版本不一致，请重新编译并重启服务器；打包客户端也需同步更新。"}
	status_changed.emit(String(messages.get(code, "连接中断：" + code)))
	if retry and _attempts < 3 and OnlineAccount.is_logged_in():
		_attempts += 1
		_retry_at = Time.get_unix_time_from_system() + pow(2.0, _attempts - 1) + randf() * 0.3
		_state = "request"
	else: _state = "failed"

func _reconnect_map() -> void:
	duel.clear()
	map_transfer_started.emit()
	# Keep the account-owned outbox: a lost transfer receipt is replayed on the new map.
	_pending_motion.clear()
	world_ready = false
	if socket != null: socket.close()
	socket = null
	population.clear()
	pve.disconnect_channel()
	chat.disconnect_channel()
	entities = {}
	changed.emit(entities)
	_state = "request"
	_attempts = 0
	_retry_at = 0.0
	status_changed.emit("正在切换地图……")

func _on_ticket(result: Dictionary) -> void:
	if OnlineAccount.network_suspended: return
	if _state != "ticket": return
	if not result.ok:
		_failed(String(result.get("code", "TICKET_FAILED")), result.get("code") in ["NETWORK_ERROR", "SERVER_BUSY", "RATE_LIMITED", "DATABASE_UNAVAILABLE"])
		return
	if not Platform.is_available():
		_failed("PLATFORM_NOT_READY")
		return
	var allowed := Platform.context.runtime_config.check_network_target(server)
	if not allowed.ok:
		_failed(allowed.code)
		return
	_ticket = result.ticket
	_announcement_version = 1 if result.get("announcement_version") == 1 else 0
	_pve_version = 1 if result.get("pve_version") == 1 else 0
	_maps_version = int(result.get("maps_version", 0)) if result.get("maps_version") in [1, 2] else 0
	# Servers keep maps_version=1 for older clients and advertise the expansion separately.
	if _maps_version >= 1 and result.get("ai_world_version") == 1: _maps_version = 2
	_shop_version = int(result.get("shop_version")) if result.get("shop_version") in [1,2] else 0
	_team_version = 1 if result.get("team_version") == 1 else 0
	team_following=false;team_marks={};team_travel={}
	_duel_version = 2 if result.get("duel_version") == 2 else 0
	duel.enabled = _duel_version == 2
	if not duel.enabled: duel.clear()
	appearances = {}
	_population_version = 1 if result.get("population_version") == 1 else 0
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 2097152
	socket.outbound_buffer_size = 8192
	socket.max_queued_packets = 128
	var url := server.replace("https://", "wss://").replace("http://", "ws://") + "/api/v1/world/ws"
	if socket.connect_to_url(url) != OK:
		_failed("CONNECT_FAILED", true)
		return
	_state = "connecting"
	_deadline = Time.get_unix_time_from_system() + 8.0
	status_changed.emit("正在连接共享地图……")

func _process(_delta: float) -> void:
	if OnlineAccount.network_suspended:
		if _state != "idle": leave()
		return
	if _state == "idle": return
	if not OnlineAccount.is_logged_in() or OnlineAccount.server_address != server or OnlineAccount.login_session_id != login_session:
		_failed("SESSION_REVOKED")
		_state = "idle"
		return
	var now := Time.get_unix_time_from_system()
	if _state == "request" and now >= _retry_at and not OnlineAccount.busy:
		_state = "ticket"
		_deadline = now + 20.0
		OnlineAccount.request_world_ticket(character_id, config_hash)
	if _state in ["ticket", "connecting", "syncing"] and now > _deadline:
		_failed("TIMEOUT", true)
		return
	if socket == null: return
	var polled_socket := socket
	socket.poll()
	var socket_state := socket.get_ready_state()
	if socket_state not in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED]: return
	if socket_state == WebSocketPeer.STATE_OPEN and _state == "connecting":
		_state = "syncing"
		_seq = 0
		_input_seq = 0
		_motion_waiting = 0
		_motion_retry_at = 0
		_last_input_at = -100
		stream = ""
		world_stream = ""
		_world_seq = 0
		_net_ids = {}
		_deadline = now + 8.0
		socket.send_text(JSON.stringify(_exchange_packet()))
		_ticket = ""
		_heartbeat = now
		_last_received = now
	for _packet in 64:
		if socket != polled_socket or socket.get_available_packet_count() == 0: break
		var raw := socket.get_packet()
		_last_received = now
		if not socket.was_string_packet():
			if not _receive_delta(raw): _failed("INVALID_WORLD_DELTA", true)
			continue
		if raw.size() > 131072:
			_failed("INVALID_PACKET")
			return
		var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if not data is Dictionary:
			_failed("INVALID_PACKET")
			return
		if not valid_packet_size(data,raw.size()):
			_failed("INVALID_PACKET"); return
		_receive(data, raw)
	# A transfer receipt and the old room's close can arrive in the same poll.
	# Consume queued receipts/errors before deciding whether the close was unexpected.
	if socket != polled_socket: return
	if socket_state == WebSocketPeer.STATE_CLOSED:
		if socket.get_available_packet_count() > 0: return
		if world_ready and pve.pending() and OnlineAccount.pending_pve.command.action in ["transfer", "ai_travel", "school_join", "scroll_travel"]:
			# A lost receipt is still pending. Rejoin and replay its UUID to confirm the outcome.
			_reconnect_map()
		else: _failed("DISCONNECTED", true)
		return
	if socket_state != WebSocketPeer.STATE_OPEN: return
	if socket != null and now - _heartbeat >= 3.0:
		socket.send_text(JSON.stringify({"type": "ping"}))
		_heartbeat = now
	if not _snapshot.is_empty() and now > float(_snapshot.deadline): _failed("SNAPSHOT_TIMEOUT", true)
	if socket != null and now - _last_received > 12.0: _failed("HEARTBEAT_TIMEOUT", true)
	chat.enabled = world_ready
	chat.tick()
	duel.tick()
	if pve.ready and pve.pending() and now - pve.sent_at > 8.0: _failed("TIMEOUT", true)
	_flush_motion()

static func valid_packet_size(data:Dictionary,bytes:int)->bool:
	if bytes<0 or bytes>131072:return false
	if bytes<=32768 or data.get("type") in ["world.appearance","world.team"]:return true
	# Full instance inventories exceed the old fixed-item envelope. They retain
	# the existing hard 128KiB bound and must still pass OnlinePve.valid in _receive.
	if data.get("type") not in ["pve.state","pve.result"] or not data.get("state") is Dictionary:return false
	var loot:Variant=data.state.get("loot")
	return loot is Dictionary and loot.get("version")=="loot-v1"

func _exchange_packet() -> Dictionary:
	var packet := {"type": "auth.exchange", "ticket": _ticket, "protocol_version": 1, "config_hash": config_hash, "world_sync_version": 2}
	if _announcement_version == 1: packet.announcement_version = 1
	if _population_version == 1: packet.population_version = 1
	if _pve_version == 1: packet.pve_version = 1
	if _maps_version in [1, 2]: packet.maps_version = _maps_version
	if _shop_version in [1,2]: packet.shop_version = _shop_version
	if _duel_version == 2: packet.duel_version = 2
	if _team_version == 1: packet.team_version = 1
	return packet

static func _decimal(value: Variant) -> bool:
	if not value is String: return false
	if RegEx.create_from_string("^(0|[1-9][0-9]{0,18})\\z").search(value) == null: return false
	return value.length() < 19 or value <= "9223372036854775807"

static func _uuid(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z").search(value) != null

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floor(float(value))

static func _cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], 0, 31) and _integer(value[1], 0, 31)

func _entity(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not _integer(value.get("net_id"), 1, 4294967295): return false
	if not _uuid(value.get("id")) or not value.get("display_name") is String or not OnlineAccount.valid_nickname(value.display_name): return false
	if not _integer(value.get("job"), 0, 2) or not _integer(value.get("gender"), 0, 1): return false
	if not _cell(value.get("cell")) or (value.get("next_cell") != null and not _cell(value.next_cell)): return false
	if not _integer(value.get("segment_progress"), 0, 1000): return false
	for key in ["entity_revision", "last_input_seq", "world_epoch"]:
		if not _decimal(value.get(key)): return false
	if value.next_cell != null and absi(int(value.cell[0]) - int(value.next_cell[0])) + absi(int(value.cell[1]) - int(value.next_cell[1])) != 1: return false
	return true

func _receive(data: Dictionary, raw: PackedByteArray) -> void:
	var kind: Variant = data.get("type")
	if kind in ["duel.state", "duel.result"]:
		if not world_ready or _duel_version != 2 or not duel.receive(data):
			push_warning("Rejected duel packet: "+String(kind))
			_failed("INVALID_DUEL",true)
		return
	if kind == "error":
		var code := String(data.get("code", "SERVER_ERROR"))
		if code in ["INVALID_TARGET", "STALE_INPUT", "RATE_LIMITED", "BATTLE_ACTIVE","TEAM_BATTLE_ACTIVE","TEAM_FOLLOWING"]:
			_motion_waiting=0
			if code=="RATE_LIMITED":_motion_retry_at=Time.get_ticks_msec()+250
			if code in ["BATTLE_ACTIVE","TEAM_BATTLE_ACTIVE","TEAM_FOLLOWING"]:_pending_motion.clear();movement_cancelled.emit()
			status_changed.emit("跟随中由队长控制移动，可在队伍界面暂离。" if code=="TEAM_FOLLOWING" else "战斗中暂不能移动。" if code in ["BATTLE_ACTIVE","TEAM_BATTLE_ACTIVE"] else "目标不可达或操作过快，请重试。")
		else: _failed(code, code in ["DATABASE_UNAVAILABLE", "SERVER_BUSY", "WORLD_STREAM_LAGGED"])
		return
	if kind == "pong": return
	if kind == "world.team":
		if not world_ready or _team_version!=1 or not valid_team_packet(data,map_id):
			_failed("INVALID_TEAM_STATE");return
		team_marks=data.members.duplicate(true);team_following=data.following
		team_travel=data.travel.duplicate(true) if data.travel is Dictionary else {}
		if not team_travel.is_empty():team_travel.cell=[int(team_travel.cell[0]),int(team_travel.cell[1])]
		if team_following:_pending_motion.clear();movement_cancelled.emit()
		changed.emit(entities)
		return
	if kind == "world.appearance":
		if not world_ready or not _shop_version in [1,2] or data.get("map_id") != map_id or not data.get("looks") is Dictionary or data.looks.size() > 1000:
			_failed("INVALID_APPEARANCE"); return
		for id in data.looks:
			var look: Variant = data.looks[id]
			if not _uuid(id) or not look is Array or look.size() != (3 if _shop_version==2 else 2):
				_failed("INVALID_APPEARANCE"); return
			if (_shop_version==2 and not ShopRules.valid_appearance(look)) or (_shop_version==1 and (not _integer(look[0],0,3) or not _integer(look[1],0,2))):
				_failed("INVALID_APPEARANCE"); return
		var removed: Variant = data.get("removed",[])
		if not removed is Array or removed.size()>1000:
			_failed("INVALID_APPEARANCE"); return
		for id in removed:
			if not _uuid(id):
				_failed("INVALID_APPEARANCE"); return
		for id in removed: appearances.erase(id)
		appearances.merge(data.looks,true)
		changed.emit(entities)
		return
	if kind in ["pve.state", "pve.result"]:
		if not world_ready or _pve_version != 1:
			_failed("INVALID_PVE")
		elif not pve.receive(data):
			_failed(pve.validation_error if not pve.validation_error.is_empty() else "INVALID_PVE")
		elif pve.state.character.map_id != map_id:
			_reconnect_map()
		return
	if kind == "population.state":
		if stream.is_empty() or not population.receive(data): _failed("INVALID_POPULATION")
		return
	if kind == "announcement.state":
		if stream.is_empty() or not announcements.receive(data): _failed("INVALID_ANNOUNCEMENT")
		return
	if kind is String and kind.begins_with("chat."):
		if stream.is_empty() or not chat.receive(data): _failed("INVALID_CHAT")
		return
	if kind == "auth.ready":
		if _state != "syncing" or not stream.is_empty() or data.get("character_id") != character_id or data.get("config_hash") != config_hash or not SharedWorldMap.exists(data.get("map_id")) or data.get("instance_id") != "main":
			_failed("INVALID_HANDSHAKE"); return
		if not _uuid(data.get("game_session_id")) or not _uuid(data.get("stream_id")) or not _decimal(data.get("connection_epoch")) or not _decimal(data.get("world_epoch")) or not _uuid(data.get("world_stream_id")) or data.get("world_sync_version") != 2:
			_failed("INVALID_HANDSHAKE"); return
		if data.has("map_hash") and data.map_hash != SharedWorldMap.map_hash(data.map_id):
			_failed("CONFIG_MISMATCH"); return
		if data.map_id != "qingyun_trail" and not data.has("map_hash"):
			_failed("CONFIG_MISMATCH"); return
		map_id = data.map_id
		map_changed.emit(map_id)
		game_session = data.game_session_id
		connection_epoch = data.connection_epoch
		world_epoch = data.world_epoch
		stream = data.stream_id
		world_stream = data.world_stream_id
		return
	if stream.is_empty() or data.get("stream_id") != stream or not _decimal(data.get("seq")):
		_failed("INVALID_STREAM"); return
	if kind == "snapshot.begin":
		if world_ready or _state != "syncing" or _seq != 0 or not _decimal(data.get("base_world_seq")) or int(data.base_world_seq) < 1: _failed("INVALID_SNAPSHOT"); return
		if not _snapshot.is_empty() or int(data.seq) != _seq + 1 or not _uuid(data.get("snapshot_id")) or not _integer(data.get("count"), 1, 1000) or not _integer(data.get("chunks"), 1, 32) or int(data.chunks) != ceili(float(data.count) / 32.0):
			_failed("INVALID_SNAPSHOT"); return
		_snapshot = data.duplicate()
		_snapshot.deadline = Time.get_unix_time_from_system() + 8.0
		_records = {}
		_chunk_index = 0
		_snapshot_bytes = 0
		_digest = HashingContext.new()
		_digest.start(HashingContext.HASH_SHA256)
		return
	if _snapshot.is_empty() or data.get("snapshot_id") != _snapshot.snapshot_id or data.seq != _snapshot.seq:
		_failed("INVALID_SNAPSHOT"); return
	if kind == "snapshot.chunk":
		if not _integer(data.get("chunk_index"), 0, 31) or int(data.chunk_index) != _chunk_index or not data.get("records") is Array or data.records.is_empty() or data.records.size() > 32:
			_failed("INVALID_CHUNK"); return
		_snapshot_bytes += raw.size()
		if _snapshot_bytes > 1048576: _failed("SNAPSHOT_LIMIT"); return
		var length := raw.size()
		_digest.update(PackedByteArray([(length >> 24) & 255, (length >> 16) & 255, (length >> 8) & 255, length & 255]))
		_digest.update(raw)
		for value in data.records:
			if not _entity(value) or _records.has(value.id): _failed("INVALID_ENTITY"); return
			_records[value.id] = value
		_chunk_index += 1
	elif kind == "snapshot.end":
		if data.get("count") != _snapshot.count or data.get("chunks") != _snapshot.chunks or _chunk_index != int(_snapshot.chunks) or _records.size() != int(_snapshot.count) or not _records.has(character_id) or _records[character_id].world_epoch != world_epoch or data.get("sha256") != _digest.finish().hex_encode():
			_failed("SNAPSHOT_INCOMPLETE"); return
		_seq = int(data.seq)
		_world_seq = int(_snapshot.base_world_seq)
		var mapping: Dictionary = {}
		for id in _records:
			var net_id := int(_records[id].net_id)
			if mapping.has(net_id): _failed("INVALID_ENTITY"); return
			mapping[net_id] = id
		_net_ids = mapping
		entities = _records
		_records = {}
		_snapshot = {}
		world_ready = true
		_state = "ready"
		changed.emit(entities)
	else: _failed("INVALID_MESSAGE")

func _receive_delta(raw: PackedByteArray) -> bool:
	if not world_ready or not _snapshot.is_empty() or raw.size() < 70 or raw.size() > 1048576: return false
	if raw.slice(0, 4).get_string_from_ascii() != "VWD2": return false
	var hex := raw.slice(4, 20).hex_encode()
	var epoch := "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]
	if epoch != world_stream: return false
	var packet := StreamPeerBuffer.new()
	packet.big_endian = true
	packet.data_array = raw
	packet.seek(20)
	var seq := packet.get_u64()
	var json_bytes := packet.get_u32()
	var left_count := packet.get_u16()
	var move_count := packet.get_u16()
	if seq != _world_seq + 1 or json_bytes > 1048576 or left_count > 1000 or move_count > 1000: return false
	if 36 + json_bytes + left_count * 4 + move_count * 26 + 32 != raw.size(): return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(raw.slice(0, raw.size() - 32))
	if digest.finish() != raw.slice(raw.size() - 32): return false
	var entered: Variant = JSON.parse_string(raw.slice(36, 36 + json_bytes).get_string_from_utf8())
	if not entered is Array or entered.size() > 1000: return false
	# Stage only touched records. No full-world Dictionary deep copy on each tick.
	var additions: Dictionary = {}
	var new_ids: Dictionary = {}
	for entity in entered:
		if not _entity(entity) or additions.has(entity.id): return false
		var net_id := int(entity.net_id)
		if _net_ids.has(net_id) or new_ids.has(net_id): return false
		additions[entity.id] = entity
		new_ids[net_id] = entity.id
	packet.seek(36 + json_bytes)
	var removed: Dictionary = {}
	for _item in left_count:
		var net_id := packet.get_u32()
		if not _net_ids.has(net_id) or removed.has(net_id): return false
		removed[net_id] = true
	for id in additions:
		if entities.has(id) and not removed.has(int(entities[id].net_id)): return false
	var motions: Dictionary = {}
	for _item in move_count:
		var net_id := packet.get_u32()
		var cell := packet.get_u16()
		var next_cell := packet.get_u16()
		var progress := packet.get_u16()
		var revision := packet.get_u64()
		var input_seq := packet.get_u64()
		if not _net_ids.has(net_id) or removed.has(net_id) or motions.has(net_id) or revision < 0 or input_seq < 0 or cell > 1023 or (next_cell != 65535 and next_cell > 1023) or progress > 1000: return false
		if next_cell == 65535 and progress != 0: return false
		if next_cell != 65535 and absi(cell % 32 - next_cell % 32) + absi(cell / 32 - next_cell / 32) != 1: return false
		var current: Dictionary = entities[_net_ids[net_id]]
		if revision < int(current.entity_revision): return false
		motions[net_id] = {"cell": [cell % 32, cell / 32], "next_cell": null if next_cell == 65535 else [next_cell % 32, next_cell / 32], "segment_progress": progress, "entity_revision": str(revision), "last_input_seq": str(input_seq)}
	if entities.size() + additions.size() - removed.size() < 1 or entities.size() + additions.size() - removed.size() > 1000: return false
	if removed.has(int(entities[character_id].net_id)): return false
	# Commit after every field, length, sequence and digest has been verified.
	for net_id in removed:
		entities.erase(_net_ids[net_id])
		_net_ids.erase(net_id)
	for id in additions: entities[id] = additions[id]
	_net_ids.merge(new_ids)
	for net_id in motions: entities[_net_ids[net_id]].merge(motions[net_id], true)
	_world_seq = seq
	if not additions.is_empty() or not removed.is_empty() or not motions.is_empty(): changed.emit(entities)
	return true

func move_to(cell: Vector2i) -> void:
	_send_motion("world.move_to", [cell.x, cell.y])

func stop_moving() -> void:
	movement_cancelled.emit()
	_send_motion("world.stop")

func _send_motion(kind: String, target: Array = []) -> void:
	if not world_ready or pve.active() or pve.pending() or duel.active() or team_active or (team_following and kind=="world.move_to"): return
	_pending_motion = {"type": kind, "target": target.duplicate()}
	_flush_motion()

func _flush_motion() -> void:
	if pve.active() or pve.pending() or duel.active() or team_active or (team_following and _pending_motion.get("type")=="world.move_to"): _pending_motion.clear(); return
	# Only one motion packet may be awaiting authority. A slow/mobile link can
	# otherwise deliver regularly-spaced inputs as a burst and trip the 80ms gate.
	if _motion_waiting>0:
		if int(entities.get(character_id,{}).get("last_input_seq","0"))<_motion_waiting:return
		_motion_waiting=0
	if Time.get_ticks_msec()<_motion_retry_at:return
	var now := Time.get_ticks_msec()
	if not world_ready or socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN or _pending_motion.is_empty() or now - _last_input_at < 100: return
	var intent := _pending_motion
	_pending_motion = {}
	_last_input_at = now
	_input_seq += 1
	_motion_waiting=_input_seq
	var message := {"type": intent.type, "game_session_id": game_session, "connection_epoch": connection_epoch, "world_epoch": world_epoch, "input_seq": str(_input_seq)}
	if intent.type == "world.move_to": message.target = intent.target
	if socket.send_text(JSON.stringify(message)) != OK: _failed("SEND_FAILED", true)

static func valid_team_packet(data:Dictionary,current_map:String)->bool:
	if data.get("map_id")!=current_map or not data.get("following") is bool or not data.get("members") is Dictionary or data.members.size()>1000:return false
	for id in data.members:
		var m:Variant=data.members[id]
		if not _uuid(id) or not m is Dictionary or not m.get("leader") is bool or not m.get("following") is bool:return false
		if m.has("ready") and not m.ready is bool:return false
	var travel:Variant=data.get("travel")
	if travel==null:return true
	return travel is Dictionary and travel.get("action") in ["transfer","ai_travel"] and travel.get("target") is String and travel.target.length()<=32 and _cell(travel.get("cell"))
