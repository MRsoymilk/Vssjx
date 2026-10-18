class_name OriginalSceneChrome
extends Control
## Common blue HUD and message area measured from the supplied in-game views.

signal action_requested(action: String)
@export var in_battle := false
@export var use_local_player := true
@onready var log_label: Label = $MessagePanel/LogLabel
@onready var round_label: Label = $RoundLabel
@onready var clock_label: Label = $ClockLabel
@onready var identity: Label = $Identity
@onready var hp_bar: ProgressBar = $HpBar
@onready var mp_bar: ProgressBar = $MpBar
@onready var hint: Label = $Hint
@onready var toolbar: Control = get_node_or_null("Toolbar")
@onready var message_panel: Panel = $MessagePanel
@onready var clock_hour: OriginalNumber = $ClockHour
@onready var clock_minute: OriginalNumber = $ClockMinute
var palette: Dictionary
@onready var xp_bar: ProgressBar = $XpBar

func _ready() -> void:
	palette = OriginalUITheme.palette("scene")
	$Properties.pressed.connect(func() -> void: action_requested.emit("properties"))
	if not in_battle:
		$Reward.pressed.connect(func() -> void: action_requested.emit("reward"))
		var entries := {"Menu": "menu", "Quest": "quest", "Map": "map", "Actions": "menu", "Mail": "mail", "Social": "social", "Bag": "bag"}
		for node_name in entries:
			toolbar.get_node(node_name).pressed.connect(_request_action.bind(entries[node_name]))
	if use_local_player:
		identity.text = "LV.%d" % int(Game.player.level)
		update_header(int(Game.player.hp), int(Game.player.mp), 0)
	else:
		identity.text = "LV.—"
		update_clock()

func _request_action(action: String) -> void:
	action_requested.emit(action)

func update_header(hp: int, mp: int, round_number: int) -> void:
	if use_local_player: identity.text = "LV.%d" % int(Game.player.level)
	var values := Game.stats()
	hp_bar.max_value = values.hp
	hp_bar.value = hp
	mp_bar.max_value = values.mp
	mp_bar.value = mp
	xp_bar.max_value = int(Game.player.level) * 40
	xp_bar.value = int(Game.player.xp)
	update_clock()
	round_label.text = "回合：%d/%d" % [round_number, ShushanBattle.MAX_ROUNDS] if in_battle else "常规模式"

func display_character(character: Dictionary) -> void:
	# Online data is an independent server snapshot, never Game.player.
	identity.text = "LV.%d" % int(character.get("level", 1))
	for key in ["hp", "mp"]:
		var bar: ProgressBar = hp_bar if key == "hp" else mp_bar
		bar.max_value = maxi(1, int(character.get("max_" + key, character.get(key, 1))))
		bar.value = int(character.get(key, 0))
		bar.tooltip_text = ("气血：" if key == "hp" else "灵力：") + str(int(character.get(key, 0)))
	xp_bar.max_value = maxi(1, int(character.get("next_xp", character.get("xp", 1))))
	xp_bar.value = int(character.get("xp", 0))
	round_label.text = "常规模式"
	update_clock()

func update_clock() -> void:
	var time := Time.get_time_dict_from_system()
	clock_label.text = "%02d:%02d" % [int(time.hour), int(time.minute)]
	clock_hour.value = "%02d" % int(time.hour)
	clock_minute.value = "%02d" % int(time.minute)
	clock_hour.queue_redraw()
	clock_minute.queue_redraw()

static func panel(parent: Node, rect: Rect2, fill: Color, border: Color) -> Panel:
	var node: Panel = preload("res://scenes/ui/dynamic_panel.tscn").instantiate()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func label(parent: Node, value: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var node: Label = preload("res://scenes/ui/dynamic_label.tscn").instantiate()
	node.text = value
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func button(parent: Node, value: String, rect: Rect2, font_size: int) -> Button:
	var node: Button = preload("res://scenes/ui/dynamic_button.tscn").instantiate()
	node.text = value
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", Color("fff8c5"))
	for state in ["normal", "hover", "pressed", "focus"]: node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node

static func progress(parent: Node, rect: Rect2, color: Color) -> ProgressBar:
	var node: ProgressBar = preload("res://scenes/ui/dynamic_progress.tscn").instantiate()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("456b90")
	bg.border_color = Color("739fd2")
	bg.set_border_width_all(1)
	var fill := bg.duplicate()
	fill.bg_color = color
	node.add_theme_stylebox_override("background", bg)
	node.add_theme_stylebox_override("fill", fill)
	parent.add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node
