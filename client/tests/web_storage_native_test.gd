extends Node
const WEB_STORAGE := preload("res://scripts/interface/adapters/web/web_storage.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("WEB STORAGE NATIVE FAIL: " + description)

func _run() -> void:
	var storage := WEB_STORAGE.new()
	check((await storage.initialize().wait()).status == PlatformResult.Status.UNSUPPORTED, "Native execution cannot initialize the Web adapter or native persistence fallback")
	check(storage.status().state == "uninitialized" and storage.status().retention == "unknown", "No manufactured browser persistence state")
	check((await storage.probe(WEB_STORAGE.SLOT).wait()).code == "STORAGE_NOT_READY", "Uninitialized storage is not an empty slot")
	check((await storage.read(WEB_STORAGE.SLOT).wait()).code == "STORAGE_NOT_READY", "No native-file read fallback")
	check((await storage.write(WEB_STORAGE.SLOT, "{}").wait()).code == "STORAGE_NOT_READY", "No native-file write fallback")
	check((await storage.write(WEB_STORAGE.SLOT, "界".repeat(400000)).wait()).code == "TOO_LARGE", "UTF8 byte cap applies before bridge dispatch")
	check(not storage.read_text(WEB_STORAGE.SLOT).ok and not storage.write_text_atomic(WEB_STORAGE.SLOT, "{}").ok, "Synchronous methods stay unsupported")
	storage.close()
	storage.close()
	check(storage.status().state == "closed" and (await storage.probe(WEB_STORAGE.SLOT).wait()).code == "STORAGE_CLOSED", "Idempotent close fences further operations")
	var config := preload("res://scripts/interface/adapters/web/web_runtime_config.gd").new()
	check(config.local_path("save").value == WEB_STORAGE.SLOT, "Web config selects only the named logical offline slot")
	check(not config.local_path("save", "user://override.json").ok and not config.local_path("connection").ok, "No native path or connection preferences accepted")
	for value in [[], [4], ["{broken"], ["{}"], ['{"id":1.5,"ok":true}']]:
		var port := WEB_STORAGE.new()
		var pending := PlatformStorageRequest.new()
		port._pending[1] = pending
		port._receive(value)
		check(pending.result != null and not pending.result.ok and port._pending.is_empty(), "Malformed completion is failure, never a stuck or successful request")
	var port := WEB_STORAGE.new()
	var pending := PlatformStorageRequest.new()
	port._pending[1] = pending
	port._receive(['{"id":99,"ok":true}'])
	check(pending.result == null, "Unknown late callback cannot complete a current request")
	port._receive(['{"id":1,"ok":false,"code":"do-not-log-sensitive"}'])
	check(pending.result.code == "SYNC_FAILED" and not pending.result.message.contains("do-not-log-sensitive"), "Unknown browser errors are mapped without echo")
	check(preload("res://scripts/interface/platform_factory.gd").create("web") == null, "Storage adapter does not enable the incomplete Web game")
	print("WEB STORAGE NATIVE GUARDS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
