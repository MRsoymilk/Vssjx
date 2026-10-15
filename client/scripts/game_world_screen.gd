class_name GameWorldScreen
extends Control
## One authored HUD for both the local game and the authoritative online map.
signal action_requested(action: String)
@export var online_mode := false
@onready var chrome: OriginalSceneChrome = $Chrome
@onready var hud: Control = $Hud
@onready var chat: Panel = $Chat
var _clock := 0.0

func _enter_tree() -> void:
	$Chrome.use_local_player = not online_mode

func _ready() -> void:
	theme = chrome.theme
	chrome.action_requested.connect(func(action: String) -> void: action_requested.emit(action))
	chat.visible = online_mode
	chrome.log_label.visible = not online_mode
	$CountLabel.visible = online_mode

func _process(delta: float) -> void:
	if not online_mode: return
	_clock += delta
	if _clock >= 1.0:
		_clock = 0.0
		chrome.update_clock()
