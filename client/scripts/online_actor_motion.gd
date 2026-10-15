class_name OnlineActorMotion
extends RefCounted
## Follow received grid segments, preserving corners instead of chasing chords.
const SPEED := 72.0
var speed := SPEED
var position := Vector2.ZERO
var travelled := 0.0
var waypoints: Array[Vector2] = []
var moving := false
var _cell := Vector2i.ZERO
var _next := Vector2i(-1, -1)
var _sample := Vector2.ZERO
var _epoch := ""
var _initialized := false

static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell * 16) + Vector2(8, 8)

func receive(entity: Dictionary, grid: AStarGrid2D) -> void:
	var cell := Vector2i(entity.cell[0], entity.cell[1])
	var next := Vector2i(-1, -1) if entity.next_cell == null else Vector2i(entity.next_cell[0], entity.next_cell[1])
	var point := center(cell)
	if next.x >= 0: point = point.lerp(center(next), float(entity.segment_progress) / 1000.0)
	var reset := not _initialized or _epoch != String(entity.world_epoch)
	# Reconnect/correction can replace an unfinished segment with a baseline.
	if cell == _cell and _next.x >= 0 and next != _next: reset = true
	if cell == _cell and next == _next and next.x >= 0 and point.distance_to(center(cell)) + 0.01 < _sample.distance_to(center(cell)): reset = true
	if reset:
		position = point
		waypoints.clear()
		travelled = 0.0
	elif cell != _cell:
		var exit_cell := _next if _next.x >= 0 else _cell
		_append(center(exit_cell))
		if cell != exit_cell:
			# Only needed after a publication gap; never draw a diagonal through terrain.
			var route := grid.get_id_path(exit_cell, cell)
			if route.is_empty():
				position = point
				waypoints.clear()
			else:
				for index in range(1, route.size()): _append(center(route[index]))
		_append(point)
	else:
		_append(point)
	_cell = cell
	_next = next
	_sample = point
	_epoch = String(entity.world_epoch)
	_initialized = true
	moving = next.x >= 0
	if waypoints.size() > 128:
		# Bound rendering history after a long application stall. The new baseline
		# is authoritative; no old commands or guessed movement are replayed.
		position = point
		waypoints.clear()

func _append(point: Vector2) -> void:
	var last := position if waypoints.is_empty() else waypoints[-1]
	if last.is_equal_approx(point): return
	if not waypoints.is_empty():
		var before := position if waypoints.size() == 1 else waypoints[-2]
		var previous := last - before
		var following := point - last
		if absf(previous.cross(following)) < 0.001 and previous.dot(following) >= 0:
			waypoints[-1] = point
			return
	waypoints.append(point)

func advance(delta: float) -> void:
	travelled = 0.0
	var backlog := 0.0
	var previous := position
	for point in waypoints:
		backlog += previous.distance_to(point)
		previous = point
	# Ordinary 100ms updates render at 72px/s. Only a genuine backlog permits
	# bounded catch-up; never use the old permanently faster chase speed.
	var render_speed := speed * clampf(backlog / (speed * 0.2), 1.0, 1.5)
	var budget := render_speed * minf(maxf(delta, 0.0), 0.1)
	while budget > 0 and not waypoints.is_empty():
		var distance := position.distance_to(waypoints[0])
		var step := minf(distance, budget)
		position = position.move_toward(waypoints[0], step)
		travelled += step
		budget -= step
		if distance <= step + 0.0001: waypoints.pop_front()

func has_motion() -> bool:
	return moving or not waypoints.is_empty()
