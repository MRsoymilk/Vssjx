class_name OriginalCharacterAttributes
extends Control
## Layout follows the game area of the supplied properties screenshot.

signal back_requested
@export var online_mode := false
var _online_character: Dictionary = {}
var _online_stats: Dictionary = {}
const BROWN := Color("654518")
const PAGES := [
	preload("res://scenes/ui/attributes_regular.tscn"),
	preload("res://scenes/ui/attributes_extended.tscn"),
	preload("res://scenes/ui/attributes_skills.tscn"),
	preload("res://scenes/ui/attributes_inner.tscn")
]
const TABS := ["常规", "扩展", "武功", "心法"]
var selected_tab := 0
var content: Control
@onready var signature: LineEdit = $Signature
var preview: AnimatedSprite2D
var tab_buttons: Array[Button] = []
var bars: Dictionary = {}
var numbers: Dictionary = {}
var snapshot: Dictionary = {}
@onready var cursor: TextureRect = $Cursor
var palette: Dictionary

func _ready() -> void:
	palette = OriginalUITheme.palette("attributes")
	for i in 4:
		var button: Button = get_node("TabButtons%d" % i)
		button.pressed.connect(select_tab.bind(i))
		tab_buttons.append(button)
	_configure_signature()
	signature.text_changed.connect(func(value: String) -> void:
		if not online_mode: Game.player.signature = value
	)
	signature.text_submitted.connect(func(_value: String) -> void: signature.release_focus())
	$EditSignature.pressed.connect(func() -> void: signature.grab_focus(); signature.caret_column = signature.text.length())
	$Back.pressed.connect(func() -> void: back_requested.emit())
	select_tab(0)

func select_tab(index: int) -> void:
	selected_tab = posmod(index, 4)
	for i in 4:
		var fill: Color = Color("bef38b") if i == selected_tab else palette.main
		for state in ["normal", "hover", "pressed"]:
			tab_buttons[i].add_theme_stylebox_override(state, _style(fill, Color("e3ee9d") if i == selected_tab else fill))
		tab_buttons[i].add_theme_color_override("font_color", Color("507030") if i == selected_tab else palette.deep)
	cursor.position.x = 105 + selected_tab * 45
	for child in $Pages.get_children():
		$Pages.remove_child(child)
		child.queue_free()
	content = PAGES[selected_tab].instantiate()
	$Pages.add_child(content)
	preview = null
	bars.clear()
	numbers.clear()
	if online_mode and _online_character.is_empty(): return
	if selected_tab == 0: _regular()
	elif selected_tab == 1: _extended()
	else: _skills()
	move_child(cursor, get_child_count() - 1)

func display_online(character: Dictionary, stats: Dictionary) -> void:
	var unchanged := online_mode and _online_character == character and _online_stats == stats
	online_mode = true
	_online_character = character.duplicate(true)
	_online_stats = stats.duplicate(true)
	if is_node_ready() and not unchanged:
		_configure_signature()
		select_tab(selected_tab)

func _configure_signature() -> void:
	signature.text = "" if online_mode else String(Game.player.get("signature", ""))
	signature.editable = not online_mode
	signature.placeholder_text = "联网签名暂未开放" if online_mode else ""
	$EditSignature.disabled = online_mode
	$EditSignature.tooltip_text = "联网签名暂未开放" if online_mode else "编辑签名"

func _player_data() -> Dictionary:
	if not online_mode: return Game.player
	var value := _online_character.duplicate(true)
	value.name = value.get("display_name", "")
	return value

func _stats_data() -> Dictionary:
	return _online_stats if online_mode else Game.stats()

func _regular() -> void:
	var player := _player_data()
	var stats := _stats_data()
	snapshot = player.duplicate(true)
	if stats.has("hp"): snapshot.max_hp = stats.hp
	if stats.has("mp"): snapshot.max_mp = stats.mp
	snapshot.next_xp = int(player.get("level", 1)) * 40
	var keys := ["mzs", "mck", "mfs"] if int(player.get("gender", 0)) == 0 else ["wzs", "wck", "wfs"]
	preview = OriginalArt.actor("hero/" + keys[int(player.get("job", 0))])
	preview.position = Vector2(76, 193)
	preview.scale = Vector2(1.8, 1.8)
	content.add_child(preview)
	content.get_node("NameValue").text = String(player.get("name", ""))
	content.get_node("JobValue").text = Game.JOBS[int(player.get("job", 0))]
	content.get_node("SchoolValue").text = Game.SCHOOLS[int(player.get("school", 0))] + "派"
	var title := String(player.get("title", ""))
	content.get_node("TitleValue").text = "无" if title.is_empty() else title
	for key in ["level", "hp", "mp", "xp", "gold", "ingots", "guild_contribution", "essence"]:
		var number: OriginalNumber = content.get_node("Numbers" + String(key).to_pascal_case())
		var unavailable := online_mode and not player.has(key)
		if key in ["hp", "mp", "xp"]:
			var maximum := int(snapshot.next_xp) if key == "xp" else int(stats.get(key, 0))
			number.value = "%d/%d" % [int(player.get(key, 0)), maximum] if maximum > 0 else str(int(player.get(key, 0)))
			var bar: ProgressBar = content.get_node("Bars" + String(key).to_pascal_case())
			bar.max_value = maxi(1, maximum)
			bar.value = int(player.get(key, 0))
			bar.visible = maximum > 0
			bars[key] = bar
		else: number.value = "" if unavailable else str(int(player.get(key, 0)))
		var placeholder := content.get_node_or_null("Unavailable" + String(key).to_pascal_case())
		if placeholder != null: placeholder.visible = unavailable
		number.queue_redraw()
		numbers[key] = number

func _extended() -> void:
	var player := _player_data()
	var stats := _stats_data()
	for i in 16:
		var value := "—"
		if i == 5 and int(player.get("job", 0)) != 2 and stats.has("attack"): value = str(int(stats.attack))
		if i == 6 and int(player.get("job", 0)) == 2 and stats.has("attack"): value = str(int(stats.attack))
		if i == 11 and stats.has("defense"): value = str(int(stats.defense))
		content.get_node("StatValue%d" % i).text = value

func _skills() -> void:
	if selected_tab == 3: return
	var player := _player_data()
	var names := ["破山诀", "御剑诀", "摄灵诀"]
	var descriptions := ["重击敌人，并造成额外伤害。", "剑气攻击敌人，并造成额外伤害。", "攻击敌人，同时恢复自身气血。"]
	content.get_node("SkillName").text = names[int(player.get("job", 0))]
	content.get_node("Description").text = descriptions[int(player.get("job", 0))]

func _style(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style
