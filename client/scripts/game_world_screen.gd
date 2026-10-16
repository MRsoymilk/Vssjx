class_name GameWorldScreen
extends Control
## One authored HUD for both the local game and the authoritative online map.
signal action_requested(action: String)
signal movement_pause_requested
@export var online_mode := false
@onready var chrome: OriginalSceneChrome = $Chrome
@onready var hud: Control = $Hud
@onready var chat: Panel = $Chat
var _clock := 0.0
var local_chat: LocalWorldChat
var local_messages: Array[Dictionary] = []

func _enter_tree() -> void:
	$Chrome.use_local_player = not online_mode

func _ready() -> void:
	theme = chrome.theme
	chrome.action_requested.connect(func(action: String) -> void:
		if action == "social" and local_chat != null: local_chat.toggle()
		else:
			if local_chat != null: local_chat.close()
			action_requested.emit(action)
	)
	chat.visible = online_mode
	chrome.log_label.visible = not online_mode
	$CountLabel.visible = online_mode
	$GameMode.text = "联机模式" if online_mode else "本地模式"
	if not online_mode:
		local_chat = LocalWorldChat.new()
		add_child(local_chat)

func _process(delta: float) -> void:
	if not online_mode: return
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		chrome.update_clock()
