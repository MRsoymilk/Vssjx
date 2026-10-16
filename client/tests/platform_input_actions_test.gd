extends Node

const TEXT := preload("res://tests/fixtures/text_input_backend.gd")
const ACTIONS := preload("res://tests/fixtures/system_actions_backend.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("INPUT/ACTIONS FAIL: " + message)

func _run() -> void:
	var text_port := TEXT.new()
	var actions := ACTIONS.new()
	check(actions.request_exit().code == "PLATFORM_NOT_READY", "Detached native actions fail explicitly")
	add_child(actions)
	var old_text := Platform.context.text_input
	var old_actions := Platform.context.system_actions
	Platform.context._text_input = text_port
	Platform.context._system_actions = actions
	check(Platform.context.capabilities().godot_text_input and Platform.context.capabilities().exit_application, "Factory advertises the implemented operations only")
	_test_fields(text_port)
	_test_forms(text_port)
	_test_chat(text_port)
	await _test_game_and_exit(text_port, actions)
	Platform.context._text_input = old_text
	Platform.context._system_actions = old_actions
	actions.queue_free()
	await get_tree().process_frame
	print("PLATFORM INPUT ACTIONS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_fields(port) -> void:
	check(PlatformTextInputInterface.new().check_submission([]).code == "UNSUPPORTED", "Base text contract does not silently succeed")
	var unsupported := PlatformSystemActionsInterface.new()
	check(unsupported.request_exit().code == "UNSUPPORTED", "Base system operation is explicitly unsupported")
	unsupported.free()
	var field := LineEdit.new()
	field.text = "native draft"
	field.size = Vector2(250, 32)
	add_child(field)
	check(port.request_focus(field, true).ok and field.has_focus() and field.has_selection(), "Native focus and selection use the actual Godot control")
	check(port.check_submission([field]).ok, "Committed native field may submit")
	port.composing = true
	var composing: PlatformResult = port.check_submission([field])
	check(not composing.ok and composing.code == "INPUT_COMPOSING", "Uncommitted composition returns a stable retryable code")
	check(not composing.message.contains(field.text) and composing.value == null, "Input result exposes no field contents")
	port.composing = false
	field.editable = false
	check(port.request_focus(field).ok, "Read-only drafts retain native focus/selection behavior")
	check(port.check_submission([field]).ok, "Read-only fields do not block business-owned retry/selection flows")
	field.focus_mode = Control.FOCUS_NONE
	check(port.request_focus(field).code == "FOCUS_DISABLED", "Focus-disabled controls report refusal rather than fake success")
	field.focus_mode = Control.FOCUS_ALL
	field.hide()
	check(port.check_submission([field]).code == "INPUT_UNAVAILABLE", "Hidden controls cannot submit")
	field.show()
	check(port.release_focus(field).ok and not field.has_focus(), "Focus release is observable and does not change the draft")
	check(field.text == "native draft", "Platform input does not mutate contents")
	field.queue_free()
	check(port.check_submission([field]).code == "INPUT_UNAVAILABLE", "Queued deletion is rejected before touching a stale field")
	check(port.request_focus(null).code == "INPUT_UNAVAILABLE" and port.check_submission([]).code == "INPUT_UNAVAILABLE", "Null/empty requests fail safely")
	check(port.check_submission([null, 1, "not a field"]).code == "INPUT_UNAVAILABLE", "Dynamically supplied invalid fields return an outcome instead of a script error")
	var detached := LineEdit.new()
	check(port.release_focus(detached).code == "INPUT_UNAVAILABLE", "Detached focus release fails without calling a viewport-less control")
	detached.free()

func _test_forms(port) -> void:
	var page: ServerLogin = load("res://scenes/ui/server_login.tscn").instantiate()
	add_child(page)
	page.address_input.text = "http://127.0.0.1:1"
	page.username_input.text = "input_test"
	page.password_input.text = "must-not-submit-1234"
	port.composing = true
	page._login()
	check(not OnlineAccount.busy and OnlineAccount._request == null and page.status.text.contains("候选"), "Composition blocks login before any credentials are sent")
	check(page.password_input.text == "must-not-submit-1234" and page._pending_credentials.is_empty(), "Blocked login preserves the draft without persisting credentials")
	page._register()
	check(not OnlineAccount.busy and page._registration_secret.is_empty(), "Composition also blocks the register button")
	page.connect_server()
	check(page.discovery.request == null and page.status.text.contains("候选"), "Address submission cannot probe during composition")
	port.composing = false
	page.free()
	var creation: OriginalCharacterCreation = load("res://scenes/ui/character_creation.tscn").instantiate()
	add_child(creation)
	var submitted: Array[bool] = []
	creation.create_requested.connect(func() -> void: submitted.append(true))
	creation.nickname.text = "输入修士"
	port.composing = true
	creation._request_create()
	check(submitted.is_empty(), "Composition cannot emit an offline character creation command")
	creation.online_mode = true
	var flow: OnlineCreationFlow = creation.get_node("Online")
	flow._loaded = true
	creation.get_node("Create").disabled = false
	flow._create()
	check(flow.status.text.contains("候选") and OnlineAccount.pending_creation.is_empty(), "Online creation guard runs before operation-ID generation")
	port.composing = false
	creation._request_create()
	check(submitted.size() == 1, "Confirmed text emits a single normal creation request")
	creation.free()

func _test_chat(port) -> void:
	var view: OnlineWorldView = load("res://scenes/ui/online_world_view.tscn").instantiate()
	add_child(view)
	view.network.set_process(false)
	view.network.world_ready = true
	view.network.chat.connected = true
	view.network.chat.enabled = true
	var sent: Array[Dictionary] = []
	view.network.chat.send_requested.connect(func(value: Dictionary) -> void: sent.append(value))
	view.chat_input.text = "候选尚未确认"
	port.composing = true
	view._send_chat()
	view._insert_emote("[微笑]")
	check(sent.is_empty() and view.network.chat.pending.is_empty(), "Composition cannot send a message or create a retry receipt")
	check(view.chat_input.text == "候选尚未确认" and view.chat_status.text.contains("候选"), "Blocked send/emote insertion preserves the same draft")
	port.composing = false
	view._send_chat()
	view._send_chat()
	check(sent.size() == 1 and not view.network.chat.pending.is_empty(), "Existing pending-ID fence still prevents duplicate confirmed submits")
	check(view.chat_input.text == "候选尚未确认", "Accepted submission still waits for the server receipt before clearing")
	view.network.chat.receive({"type": "chat.result", "result": {"client_message_id": sent[0].client_message_id, "status": "SENT", "message_id": "40000000-0000-4000-8000-000000000001"}})
	check(view.chat_input.text.is_empty(), "Only the existing receipt path clears the draft")
	view.free()

func _test_game_and_exit(port, actions) -> void:
	var old_path := Game.save_path
	var old_player := Game.player.duplicate(true)
	Game.save_path = "user://platform_input_actions_%d.json" % OS.get_process_id()
	var app: Control = load("res://scenes/main.tscn").instantiate()
	add_child(app)
	app._create()
	app.nickname.text = "输入验证"
	port.composing = true
	app._start_new()
	check(app.mode == "create" and not (await Game.probe_save()).value and Game.player == old_player, "Direct page submit cannot bypass the composition guard or mutate an offline save")
	port.composing = false
	app._start_new()
	check(app.mode == "local_select" and Game.player.name == "输入验证" and (await Game.probe_save()).value, "Confirmed offline creation saves and reaches the shared character selection flow")
	app._request_exit()
	check(actions.requests == 1, "Game requests an exit through the system port")
	Game.player.gold = 73
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(actions.requests == 2 and int(JSON.parse_string(FileAccess.get_file_as_string(Game.save_path)).gold) == 73, "Window close saves in the business layer before the platform exit request")
	actions.blocked = true
	app._request_exit()
	check(actions.requests == 2 and app.modal != null, "Unsupported exit remains visible and recoverable, not fake success")
	actions.blocked = false
	app.free()
	DirAccess.remove_absolute(Game.save_path)
	Game.save_path = old_path
	Game.player = old_player
