extends Node

const FAKE := preload("res://tests/fixtures/resource_loader_backend.gd")
const NATIVE := preload("res://scripts/interface/adapters/native/native_resource_loader.gd")
const A := "res://assets/%s.png" % "loader-fixture-a"
const B := "res://assets/%s.png" % "loader-fixture-b"
const MISSING := "res://assets/%s.png" % "loader-fixture-missing"
const REAL := "res://assets/actors/map_m10.png"
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("RESOURCE FAIL: " + description)

func fake():
	var loader := FAKE.new()
	loader.files[A] = ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
	loader.files[B] = ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
	add_child(loader)
	return loader

func _run() -> void:
	_test_validation()
	_test_progress_and_sharing()
	_test_cancel_and_owner()
	_test_faults()
	await _test_native_io()
	print("RESOURCE LOADER: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_validation() -> void:
	var base := PlatformResourceLoaderInterface.new()
	check(base.prepare([A], self, 1).result.code == "UNSUPPORTED", "Base contract is explicitly unsupported")
	base.free()
	var loader = fake()
	for paths in [PackedStringArray(), PackedStringArray(["https://example.com/image.png"]), PackedStringArray(["user://texture.png"])]:
		var invalid: PlatformResourceRequest = loader.prepare(paths, self, 1)
		check(invalid.is_finished() and invalid.result.status == PlatformResult.Status.INVALID_DATA, "Invalid/remote manifests fail before scheduling")
	check(loader.prepare([A], self, -1).result.code == "INVALID_REQUEST", "Negative caller generation is rejected")
	check(loader.prepare([A], self, 0, "Texture2D", 0).result.code == "INVALID_REQUEST", "Timeout must be positive")
	check(loader.prepare([A], self, 0, "Node").result.code == "INVALID_TYPE", "Only Resource types may be prepared")
	var too_many := PackedStringArray()
	for index in 129: too_many.append(A)
	check(loader.prepare(too_many, self, 1).result.code == "INVALID_REQUEST", "Manifest size is bounded")
	check(loader.prepare([A, MISSING], self, 1).result.code == "RESOURCE_MISSING", "Missing file rejects entire manifest")
	check(loader.starts.is_empty(), "Preflight errors schedule no partial IO")
	var absent_owner := Node.new()
	check(loader.prepare([A], absent_owner, 1).result.status == PlatformResult.Status.CANCELLED, "Detached owner cannot start work")
	absent_owner.free()
	loader.free()

func _test_progress_and_sharing() -> void:
	var loader = fake()
	var first: PlatformResourceRequest = loader.prepare([A, A, B], self, 10)
	var second: PlatformResourceRequest = loader.prepare([A], self, 20)
	check(first.request_id != second.request_id and first.generation == 10 and second.generation == 20, "Each consumer keeps its own ID and generation")
	check(loader.starts[A] == 1 and loader.starts[B] == 1 and not first.is_finished(), "Concurrent requests and duplicate paths share one engine task")
	loader.amounts[A] = 0.6
	loader.amounts[B] = 0.2
	loader._process(0.0)
	check(is_equal_approx(first.progress, 0.4) and is_equal_approx(second.progress, 0.6), "Progress reflects per-resource work and unique manifest size")
	loader.amounts[A] = 0.1
	loader._process(0.0)
	check(is_equal_approx(first.progress, 0.4), "Late lower progress does not regress")
	loader.statuses[A] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(second.is_finished() and second.result.ok and second.progress == 1.0, "A smaller consumer can finish independently")
	check(not first.is_finished() and first.progress < 1.0, "Partial preparation never advertises completion")
	check(loader.gets[A] == 1, "Shared engine result is claimed only once")
	loader.amounts[B] = NAN
	loader._process(0.0)
	check(is_finite(first.progress), "Malformed engine progress cannot poison UI")
	loader.statuses[B] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(first.result.ok and first.progress == 1.0 and first.result.value.size() == 2, "Complete result retains exactly the requested unique resources")
	check(first.result.value[A] == second.result.value[A], "Concurrent results reuse the identical resource")
	check(loader._requests.is_empty() and loader._tasks.is_empty() and not loader.is_processing(), "Finished loader has no extra cache or polling loop")
	var cached: PlatformResourceRequest = loader.prepare([A], self, 30)
	check(cached.is_finished() and cached.result.ok and loader.starts[A] == 1, "Cached resources finish without a second IO request")
	var completed := cached.result
	cached.cancel()
	cached._set_progress(0.0)
	check(cached.result == completed and cached.progress == 1.0, "Late cancel/progress cannot rewrite a terminal success")
	loader.free()

func _test_cancel_and_owner() -> void:
	var loader = fake()
	var old_owner := Node.new()
	add_child(old_owner)
	var old: PlatformResourceRequest = loader.prepare([A], old_owner, 40)
	var surviving: PlatformResourceRequest = loader.prepare([A], self, 41)
	old.cancel()
	old.cancel()
	check(old.result.status == PlatformResult.Status.CANCELLED and old.result.value == null, "Cancellation is terminal, idempotent and exposes no partial data")
	loader.statuses[A] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(surviving.result.ok and old.result.code == "CANCELLED", "One cancellation cannot cancel a shared consumer or receive a late success")
	var orphan: PlatformResourceRequest = loader.prepare([B], old_owner, 42)
	old_owner.free()
	loader._process(0.0)
	check(orphan.is_finished() and orphan.result.status == PlatformResult.Status.CANCELLED, "Freed owners are detected without retaining their scene")
	var replacement: PlatformResourceRequest = loader.prepare([A], self, 43)
	loader.statuses[B] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(orphan.result.code == "CANCELLED" and replacement.generation == 43 and replacement.result.value.has(A) and not replacement.result.value.has(B), "Orphan completion cannot overwrite a newer generation's result")
	check(loader.gets[B] == 1 and loader._tasks.is_empty(), "Cancelled orphan engine task is still drained")
	var queued := Node.new()
	add_child(queued)
	var waiting = fake()
	var doomed: PlatformResourceRequest = waiting.prepare([A], queued, 44)
	queued.queue_free()
	waiting._process(0.0)
	check(doomed.result.code == "CANCELLED", "Queued deletion cancels before actual scene destruction")
	var on_shutdown: PlatformResourceRequest = waiting.prepare([B], self, 45)
	waiting.free()
	check(on_shutdown.result.code == "CANCELLED", "Adapter shutdown resolves pending handles, never leaves a waiter hanging")
	loader.free()

func _test_faults() -> void:
	var loader = fake()
	loader.start_error = ERR_CANT_CREATE
	var refused: PlatformResourceRequest = loader.prepare([A], self, 50)
	check(refused.result.code == "RESOURCE_REQUEST_FAILED" and refused.progress < 1.0, "Threaded request refusal is not success")
	loader.free()
	loader = fake()
	var failed: PlatformResourceRequest = loader.prepare([A, B], self, 51)
	loader.statuses[A] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	loader.statuses[B] = ResourceLoader.THREAD_LOAD_FAILED
	loader._process(0.0)
	check(failed.result.code == "RESOURCE_LOAD_FAILED" and failed.result.value == null and failed._prepared.is_empty(), "Failed batches release their partial resources")
	loader.free()
	loader = fake()
	loader.files[A] = Resource.new()
	var wrong: PlatformResourceRequest = loader.prepare([A], self, 52)
	loader.statuses[A] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(wrong.result.code == "RESOURCE_TYPE_MISMATCH", "Prepared resources must actually match the requested type")
	loader.free()
	loader = fake()
	var impatient: PlatformResourceRequest = loader.prepare([A], self, 53, "Texture2D", 10)
	var patient: PlatformResourceRequest = loader.prepare([A], self, 54, "Texture2D", 100)
	loader.clock = 10
	loader._process(0.0)
	check(impatient.result.code == "RESOURCE_TIMEOUT" and not patient.is_finished(), "Timeout is consumer-specific even for shared IO")
	loader.statuses[A] = ResourceLoader.THREAD_LOAD_LOADED
	loader._process(0.0)
	check(patient.result.ok and impatient.result.code == "RESOURCE_TIMEOUT", "Late completion cannot reverse a timeout")
	loader.free()

func _test_native_io() -> void:
	check(Platform.context.capabilities().resource_preparation and Platform.context.resource_loader.is_inside_tree(), "Factory publishes a ready native resource interface")
	var loader := NATIVE.new()
	add_child(loader)
	var cold := loader.prepare([REAL], self, 60)
	var parallel := loader.prepare([REAL], self, 61)
	check(not cold.is_finished() and loader._tasks.size() == 1, "Real uncached package texture starts shared asynchronous work")
	cold.cancel()
	var deadline := Time.get_ticks_msec() + 5000
	while not parallel.is_finished() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	check(parallel.is_finished() and parallel.result.ok and parallel.result.value[REAL] is Texture2D, "Actual engine threaded IO completes with a real package texture")
	check(cold.result.code == "CANCELLED", "Real shared IO survives cancellation without a stale result")
	if parallel.is_finished() and parallel.result.ok:
		var cached := loader.prepare([REAL], self, 62)
		check(cached.is_finished() and cached.result.ok and cached.result.value[REAL] == parallel.result.value[REAL], "Real engine cache is reused with strong reference identity")
		check(loader.prepare([REAL], self, 63, "PackedScene").result.code == "RESOURCE_TYPE_MISMATCH", "Real cached wrong-type resource is rejected")
	loader.free()
