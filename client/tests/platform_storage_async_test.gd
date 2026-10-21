extends Node
const DELAYED := preload("res://tests/fixtures/delayed_storage.gd")
const ACTIONS := preload("res://tests/fixtures/system_actions_backend.gd")
var checks := 0
var failures := 0
var original: PlatformContext
var storage := DELAYED.new()
var actions := ACTIONS.new()
var app: Control

func _ready() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ASYNC STORAGE FAIL: " + description)

func receipt(durability: String = "native_file") -> PlatformResult:
	return PlatformResult.success({"written": true, "durability": durability, "bytes": 12})

func failure() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "SYNC_FAILED", "测试持久化失败，当前进度仍在内存中。")

func _save(results: Array) -> void:
	results.append(await Game.save_game())

func _load(results: Array) -> void:
	results.append(await Game.load_game())

func _probe(results: Array) -> void:
	results.append(await Game.probe_save())

func _wait(request: PlatformStorageRequest, results: Array) -> void:
	results.append(await request.wait())

func _commit(model: ShushanBattle, results: Array) -> void:
	results.append(await model.commit())

func _contains(node: Node, text: String) -> bool:
	if node is Label and node.text.contains(text): return true
	for child in node.get_children():
		if _contains(child, text): return true
	return false

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _run() -> void:
	await Platform.when_ready()
	original = Platform.context
	add_child(actions)
	var old_player := Game.player.duplicate(true)
	var old_path := Game.save_path
	Game.save_path = "user://async_storage_fixture_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	Game.new_player("原生立即回执", 1, 0)
	var busy_events: Array[bool] = []
	var listener := func(active: bool) -> void: busy_events.append(active)
	Game.storage_changed.connect(listener)
	var native_saved := await Game.save_game()
	check(native_saved.ok and native_saved.value.durability == "native_file" and busy_events.is_empty(), "Immediate native saves preserve synchronous behavior without UI/animation pause events")
	Game.storage_changed.disconnect(listener)
	check(DirAccess.remove_absolute(Game.save_path) == OK, "Remove only the owned native save probe")
	var pending := PlatformStorageRequest.new()
	var waiting: Array = []
	_wait(pending, waiting)
	_wait(pending, waiting)
	check(waiting.is_empty(), "Request cannot report completion while pending")
	pending.finish(receipt())
	pending.finish(failure())
	check(waiting.size() == 2 and waiting[0].ok and waiting[1] == waiting[0] and (await pending.wait()).ok, "Multiple and late waiters receive one completion")
	check(not (await PlatformStorageInterface.new().write("unused", "x").wait()).ok, "Base async contract is not fake success")
	var invalid := PlatformStorageRequest.new()
	invalid.finish(null)
	check((await invalid.wait()).code == "INVALID_STORAGE_RESULT", "Invalid completion does not hang waiters or report success")
	Platform.context = PlatformContext.new("delayed-storage-test", storage, original.runtime_config, original.display,
		original.lifecycle, original.resource_loader, original.text_input, actions)
	await _test_game_operations()
	await _test_pages()
	await _test_inventory_and_battle()
	await _test_close()
	check(not Game.storage_busy and storage.operations.is_empty(), "All consumers and delayed operations drained")
	Platform.context = original
	actions.queue_free()
	Game.player = old_player
	Game.save_path = old_path
	check(preload("res://scripts/interface/platform_factory.gd").create("web") == null, "Async contract migration does not enable Web")
	print("PLATFORM ASYNC STORAGE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_game_operations() -> void:
	Game.new_player("异步快照", 1, 0)
	var results: Array = []
	_save(results)
	check(Game.storage_busy and results.is_empty() and storage.operations.size() == 1, "Save waits for actual storage completion")
	Game.player.gold = 81
	check(int(JSON.parse_string(storage.operations[0].text).gold) == 30, "Queued payload is a submission-time snapshot, not a mutable dictionary")
	check((await Game.save_game()).code == "STORAGE_BUSY" and (await Game.load_game()).code == "STORAGE_BUSY" and (await Game.probe_save()).code == "STORAGE_BUSY", "Single-flight fence rejects conflicting save/load/probe")
	check(storage.operations.size() == 1 and results.is_empty(), "Rejected conflicts cannot enqueue or finish the active write")
	storage.complete(PlatformResult.success({"written": true, "durability": "memory"}))
	check(results[0].code == "SAVE_UNCONFIRMED" and Game.last_save_receipt.is_empty(), "Memory-only write cannot become a successful save")
	for result in [PlatformResult.success(), PlatformResult.success({"written": false, "durability": "native_file"}), failure(), receipt(), receipt("browser_sync")]:
		results.clear()
		_save(results)
		check(results.is_empty() and Game.last_save_receipt.is_empty(), "Every save clears the previous receipt and waits")
		storage.complete(result)
		check(results[0].ok == (result.ok and result.value is Dictionary and result.value.get("written") == true), "Only confirmed persistence receipts succeed")
	results.clear()
	_save(results)
	Game.new_player("新角色", 2, 1)
	Game.last_save_error = "当前角色提示"
	storage.complete(failure())
	check(results[0].status == PlatformResult.Status.CANCELLED and Game.player.name == "新角色" and Game.last_save_error == "当前角色提示", "Late old-character save cannot replace current state or error")
	results.clear()
	_save(results)
	var path := Game.save_path
	Game.save_path = path + ".other"
	storage.complete(receipt())
	check(results[0].status == PlatformResult.Status.CANCELLED and Game.last_save_receipt.is_empty(), "Changing save slots invalidates old completion receipts")
	Game.save_path = path
	var valid := JSON.stringify(Game.player)
	results.clear()
	_load(results)
	Game.new_player("读取期间新建", 0, 0)
	storage.complete(PlatformResult.success(valid))
	check(results[0].status == PlatformResult.Status.CANCELLED and Game.player.name == "读取期间新建", "Late load cannot overwrite a newer character")
	results.clear()
	_load(results)
	storage.complete(PlatformResult.success("{broken"))
	check(results[0].code == "INVALID_SAVE" and Game.player.name == "读取期间新建", "Delayed corrupt load preserves current character")
	results.clear()
	_load(results)
	storage.complete(PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "NOT_FOUND", "无存档"))
	check(results[0].code == "NOT_FOUND" and Game.last_save_error.is_empty(), "Missing is distinct from corruption and clears stale errors")
	results.clear()
	_load(results)
	storage.complete(PlatformResult.success(valid))
	check(results[0].ok and Game.player.name == "新角色" and Game.player.version == 1, "Delayed valid v1 load applies only after completion")
	for value in [false, true, "false"]:
		results.clear()
		_probe(results)
		check(results.is_empty() and storage.operations[0].kind == "probe", "Probe is also an explicit completion barrier")
		storage.complete(PlatformResult.success(value))
		check(results[0].ok == (value is bool), "Only boolean probe results can decide absence versus presence")

func _test_pages() -> void:
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._create()
	app.nickname.text = "等待保存"
	app._begin_new("等待保存")
	check(app.mode == "create" and app.ui.process_mode == Node.PROCESS_MODE_DISABLED and not _contains(app, "山门初见"), "Creation cannot enter the map or claim success before persistence")
	var previous := Game.player.duplicate(true)
	app._begin_new("重复创建")
	check(storage.operations.size() == 1 and storage.operations[0].kind == "probe" and Game.player == previous, "Repeated creation cannot bypass the roster probe or mutate the pending character")
	storage.complete(PlatformResult.success(false))
	check(storage.operations.size() == 1 and storage.operations[0].kind == "write" and Game.player.name == "等待保存", "Confirmed empty roster advances to one atomic character write")
	storage.complete(failure())
	check(app.mode == "create" and _contains(app, "创建存档失败") and app.ui.process_mode != Node.PROCESS_MODE_DISABLED, "Failed initial save keeps a visible recoverable creation page")
	app._begin_new("等待保存")
	storage.complete(PlatformResult.success(false))
	storage.complete(receipt())
	check(app.mode == "local_select" and app.world == null, "Only confirmed creation proceeds to character selection")
	app.character_selection.enter_button.pressed.emit()
	check(storage.operations.size() == 1 and storage.operations[0].kind == "read", "Selection explicitly loads the confirmed character")
	storage.complete(PlatformResult.success(JSON.stringify(Game.player)))
	check(app.mode == "world", "Confirmed character enters after explicit selection")
	app._close_modal()
	app._save_feedback()
	check(not _contains(app, "修行已保存") and Game.storage_busy and not app.world.enabled, "Manual save keeps input paused and success hidden while pending")
	storage.complete(receipt("browser_sync"))
	check(_contains(app, "修行已保存") and _contains(app, "清理站点数据"), "Browser-sync receipt has a non-permanent-storage explanation")
	app._close_modal()
	app._save_feedback()
	storage.complete(failure())
	check(_contains(app, "保存失败") and not _contains(app, "修行已保存"), "Failed persistence never displays save success")
	app._close_modal()
	app._save_feedback()
	app._home()
	storage.complete(receipt())
	check(app.mode == "home" and app.modal == null, "Old-page save completion cannot replace a newer screen")
	var before := Game.player.duplicate(true)
	app._continue()
	app._home()
	var older := before.duplicate(true)
	older.name = "旧页面读取"
	storage.complete(PlatformResult.success(JSON.stringify(older)))
	check(Game.player == before and app.mode == "home" and app.modal == null, "Page generation invalidates the read before applying any player state")
	app._enter_local_game()
	check(storage.operations[0].kind == "probe", "Local entry first probes a slot asynchronously")
	storage.complete(failure())
	check(_contains(app, "无法确认存档") and app.mode == "home", "Probe errors never masquerade as absent saves or start creation")
	app._continue()
	app.queue_free()
	await get_tree().process_frame
	storage.complete(PlatformResult.success(JSON.stringify(older)))
	check(Game.player == before and not Game.storage_busy, "Freed page cannot apply a delayed load; operation still drains")
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._enter_world()

func _test_inventory_and_battle() -> void:
	app._bag()
	var bag: OriginalInventory = app.backpack
	bag.sort_items()
	var gold := int(Game.player.gold)
	bag.buy_potion()
	check(storage.operations.size() == 1 and int(Game.player.gold) == gold, "Pending inventory write prevents a second purchase/mutation")
	storage.complete(failure())
	check(bag.description.text.contains("保存失败") and not bag.description.text.contains("整理完毕"), "Inventory sort cannot overwrite the failure with a success label")
	app._close_modal()
	Game.player.quest = 1
	var duel := ShushanBattle.new(ShushanWorld.ENEMIES[0])
	duel.rng.seed=1 # Legal deterministic hit; random dodge is covered separately.
	duel.enemy_hp = 1
	duel.action("attack")
	var results: Array = []
	_commit(duel, results)
	var awarded := Game.player.duplicate(true)
	check(duel.committed and results.is_empty() and storage.operations.size() == 1, "Battle applies settlement once, then waits for save completion")
	check(not (await duel.commit()) and Game.player == awarded and storage.operations.size() == 1, "Repeated settlement while IO is pending cannot grant rewards twice")
	storage.complete(failure())
	check(results.size() == 1 and not duel.save_result.ok and Game.player == awarded, "Failed battle save preserves the already-applied outcome, not a replayable reward")
	results.clear()
	_save(results)
	storage.complete(receipt())
	var confirmed := Game.player.duplicate(true)
	confirmed.erase("local_characters")
	var awarded_stats := awarded.duplicate(true)
	awarded_stats.erase("local_characters")
	check(results[0].ok and confirmed == awarded_stats, "Retrying persistence updates roster bookkeeping without rerunning gameplay settlement")
	Game.player.quest = 2
	app.world.cell=Vector2i(10,13);Game.player.cell=[10,13]
	app._npc()
	var reward:Button=app.modal.quest_button
	var before_reward := int(Game.player.gold)
	reward.pressed.emit()
	reward.pressed.emit()
	check(Game.player.quest == 3 and int(Game.player.gold) == before_reward + 60 and storage.operations.size() == 1, "Pending quest save cannot grant the NPC reward twice")
	storage.complete(failure())
	reward.pressed.emit()
	check(int(Game.player.gold) == before_reward + 60 and storage.operations.is_empty(), "Stale reward callback cannot replay a memory-applied reward after failed persistence")
	app._close_modal()
	app._autosave()
	app._autosave()
	check(storage.operations.size() == 1, "Autosave cannot overlap another autosave")
	storage.complete(failure())
	check(_contains(app, "自动保存失败") and not _contains(app, "修行已保存"), "Autosave failure is visible and never a success toast")
	app._close_modal()
	Game.player.quest = 3
	app._world_interaction("portal", {})
	await get_tree().process_frame # Current travel presents its cover before starting IO.
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	var target: Array = JSON.parse_string(storage.operations[0].text).cell
	check(int(target[0]) == 5 and int(target[1]) == 16, "Pausing input must not overwrite the destination cell during a portal save")
	storage.complete(receipt())
	check(Game.player.zone == 1 and app.world.cell == Vector2i(5, 16), "Confirmed delayed portal change reaches the correct destination")
	await get_tree().process_frame
	if app.map_transition.blocking:await app.map_transition.finished
	await get_tree().process_frame # Leave the transition's signal stack before the close fixture frees its owner.

func _test_close() -> void:
	app._save_feedback()
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(actions.requests == 0 and storage.operations.size() == 1, "Close waits behind an in-flight save; repeated close is fenced")
	storage.complete(receipt())
	check(actions.requests == 0 and Game.storage_busy and storage.operations.size() == 1, "Exit still awaits the final save of the latest state")
	storage.complete(failure())
	check(actions.requests == 0 and not app._closing and _contains(app, "尚未退出"), "Failed final save does not request native exit")
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	storage.complete(receipt())
	check(actions.requests == 1 and not Game.storage_busy, "Only confirmed final save permits native exit request")
	app.free()
	app = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app.mode = "online_world"
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(actions.requests == 2 and storage.operations.is_empty(), "Online close does not write an offline character or import offline state")
	app.free()
	await get_tree().process_frame
