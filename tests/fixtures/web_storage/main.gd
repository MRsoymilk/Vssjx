extends Control
var _callback: JavaScriptObject
var _test: JavaScriptObject
var _busy := false

func _ready() -> void:
	var result := await Game.when_ready()
	_test = JavaScriptBridge.get_interface("__vssjxStorageTest")
	_callback = JavaScriptBridge.create_callback(_command)
	_test.attach(_callback)
	_report("ready", result, {"web": OS.has_feature("web"), "status": Platform.context.storage.status(), "slot": Game.save_path})

func _report(action: String, result: PlatformResult, extra: Dictionary = {}) -> void:
	_test.done(JSON.stringify({"action": action, "ok": result.ok, "code": result.code, "value": result.value,
		"extra": extra, "engine": Engine.get_version_info().string}))

func _command(args: Array) -> void:
	if _busy or args.size() != 1 or not args[0] is String: return
	var action: String = args[0]
	_busy = true
	var result := PlatformResult.unsupported()
	var extra: Dictionary = {}
	match action:
		"write":
			Game.new_player("网页存档", 2, 1, 1)
			Game.player.gold = 147
			Game.player.signature = "刷新后验证原样恢复"
			result = await Game.save_game()
		"write-alternate":
			Game.new_player("未确认新角色", 1, 2)
			Game.player.gold = 299
			result = await Game.save_game()
			extra = {"receipt": Game.last_save_receipt, "name": Game.player.name, "gold": Game.player.gold}
		"read":
			Game.new_player("读取前内存角色", 0, 0)
			result = await Game.load_game()
			extra = {"name": Game.player.name, "gold": Game.player.gold, "gender": Game.player.gender, "version": Game.player.version, "signature": Game.player.signature}
		"probe": result = await Game.probe_save()
		"small-read": result = await Platform.context.storage.read(Game.save_path, 4).wait()
		"wrong-path": result = await Platform.context.storage.write("user://connection.cfg.login", "not-a-save").wait()
		"oversize": result = await Platform.context.storage.write(Game.save_path, "界".repeat(400000)).wait()
		"credentials":
			var config := Platform.context.runtime_config
			Platform.context.runtime_config = preload("res://scripts/interface/adapters/native/native_runtime_config.gd").new()
			var login := RememberedLogin.new("user://forbidden.login")
			extra = {"native_policy": Platform.context.runtime_config.allows_remembered_login(), "supported": login.is_supported(), "path": login.path,
				"read": login.load_saved("https://game.example.test"),
				"write": login.remember("https://game.example.test", "not_saved", "not-saved-password-1234"), "forget": login.forget(),
				"files": Array(DirAccess.get_files_at("user://"))}
			Platform.context.runtime_config = config
			result = PlatformResult.success()
		"close":
			Platform.context.storage.close()
			result = await Platform.context.storage.probe(Game.save_path).wait()
		"status": result = PlatformResult.success(Platform.context.storage.status())
		"recover": result = await Platform.context.storage.initialize().wait()
		"cancel-read":
			var request := Platform.context.storage.read(Game.save_path)
			Platform.context.storage.close()
			result = await request.wait()
		"release-read":
			var request := Platform.context.storage.read(Game.save_path)
			Platform.context.storage = null
			result = await request.wait()
	_busy = false
	_report(action, result, extra)
