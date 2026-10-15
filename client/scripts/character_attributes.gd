class_name OriginalCharacterAttributes
extends Control
## Layout follows the game area of the supplied properties screenshot.

signal back_requested
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
	signature.text = String(Game.player.get("signature", ""))
	signature.text_changed.connect(func(value: String) -> void: Game.player.signature = value)
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
	if selected_tab == 0: _regular()
	elif selected_tab == 1: _extended()
	else: _skills()
	move_child(cursor, get_child_count() - 1)

func _regular() -> void:
	var stats := Game.stats()
	snapshot = Game.player.duplicate(true)
	snapshot["max_hp"] = stats.hp
	snapshot["max_mp"] = stats.mp
	snapshot["next_xp"] = int(Game.player.level) * 40
	preview = OriginalArt.actor(Game.actor_key())
	preview.position = Vector2(76, 193)
	preview.scale = Vector2(1.8, 1.8)
	content.add_child(preview)
	content.get_node("NameValue").text = String(Game.player.name)
	content.get_node("JobValue").text = Game.JOBS[int(Game.player.job)]
	content.get_node("SchoolValue").text = Game.SCHOOLS[int(Game.player.school)] + "派"
	var title := String(Game.player.get("title", ""))
	content.get_node("TitleValue").text = "无" if title.is_empty() else title
	for key in ["level", "hp", "mp", "xp", "gold", "ingots", "guild_contribution", "essence"]:
		var number: OriginalNumber = content.get_node("Numbers" + String(key).to_pascal_case())
		if key in ["hp", "mp", "xp"]:
			var maximum := int(snapshot.next_xp) if key == "xp" else int(stats[key])
			number.value = "%d/%d" % [int(Game.player[key]), maximum]
			var bar: ProgressBar = content.get_node("Bars" + String(key).to_pascal_case())
			bar.max_value = maximum
			bar.value = int(Game.player[key])
			bars[key] = bar
		else: number.value = str(int(Game.player.get(key, 0)))
		number.queue_redraw()
		numbers[key] = number

func _extended() -> void:
	var stats := Game.stats()
	for i in 16:
		var value := "—"
		if i == 5 and int(Game.player.job) != 2: value = str(int(stats.attack))
		if i == 6 and int(Game.player.job) == 2: value = str(int(stats.attack))
		if i == 11: value = str(int(stats.defense))
		content.get_node("StatValue%d" % i).text = value

func _skills() -> void:
	if selected_tab == 3: return
	var names := ["破山诀", "御剑诀", "摄灵诀"]
	var descriptions := ["重击敌人，并造成额外伤害。", "剑气攻击敌人，并造成额外伤害。", "攻击敌人，同时恢复自身气血。"]
	content.get_node("SkillName").text = names[int(Game.player.job)]
	content.get_node("Description").text = descriptions[int(Game.player.job)]

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
