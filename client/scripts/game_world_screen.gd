class_name GameWorldScreen
extends Control
## One authored HUD for both the local game and the authoritative online map.
signal action_requested(action: String)
signal movement_pause_requested
signal chat_expand_requested
@export var online_mode := false
@onready var chrome: OriginalSceneChrome = $Chrome
@onready var hud: Control = $Hud
@onready var chat: Panel = $Chat
var _clock := 0.0
var local_chat: LocalWorldChat
var local_messages: Array[Dictionary] = []
const CHAT_UP := preload("res://assets/ui/chat_expand.svg")
const CHAT_DOWN := preload("res://assets/ui/chat_collapse.svg")

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
	$ExpandedChat.visibility_changed.connect(_update_chat_arrow)
	$Chat/Expand.pressed.connect(func() -> void:
		if $ExpandedChat.visible: $ExpandedChat.dismiss()
		else: chat_expand_requested.emit()
	)
	_update_chat_arrow()
	if not online_mode:
		local_chat = LocalWorldChat.new()
		add_child(local_chat)

func _update_chat_arrow() -> void:
	$Chat/Expand.icon = CHAT_DOWN if $ExpandedChat.visible else CHAT_UP
	$Chat/Expand.tooltip_text = "收起聊天" if $ExpandedChat.visible else "展开聊天"

func _process(delta: float) -> void:
	if not online_mode: return
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		chrome.update_clock()
