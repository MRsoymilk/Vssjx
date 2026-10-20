class_name OriginalCharacterAttributes
extends Control
## Layout follows the game area of the supplied properties screenshot.

signal back_requested
signal allocation_requested(points: Array)
signal respec_requested
@export var online_mode := false
var _online_character: Dictionary = {}
var _online_stats: Dictionary = {}
var _attribute_profile: Dictionary = {}
var allocation_draft: Array = []
var allocation_enabled := false
var allocation_hint := "停稳后可加点"
var allocation_focus := -1
const ONLINE_EXTENDED = preload("res://scenes/ui/attributes_online_extended.tscn")
const BROWN := Color("654518")
const PAGES := [
	preload("res://scenes/ui/attributes_regular.tscn"),
	ONLINE_EXTENDED,
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
	if not online_mode:
		_attribute_profile = Game.attribute_profile()
		allocation_draft = _attribute_profile.allocated.duplicate()
		allocation_enabled = not Game.storage_busy
	_configure_signature()
	signature.text_changed.connect(func(value: String) -> void:
		if not online_mode: Game.player.signature = value
	)
	signature.text_submitted.connect(func(_value: String) -> void:
		if Platform.context.text_input.check_submission([signature]).ok: Platform.context.text_input.release_focus(signature)
	)
	$EditSignature.pressed.connect(func() -> void: Platform.context.text_input.request_focus(signature); signature.caret_column = signature.text.length())
	$Back.pressed.connect(func() -> void: back_requested.emit())
	select_tab(0)

func select_tab(index: int) -> void:
	selected_tab = posmod(index, 4)
	$Label5.text="人物技能" if selected_tab>=2 else "人物属性"
	for node in [$Label14,$Signature,$CreateEdit16,$EditSignature]:node.visible=selected_tab<2
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

func display_online(character: Dictionary, stats: Dictionary, profile: Dictionary = {}) -> void:
	var unchanged := online_mode and _online_character == character and _online_stats == stats and _attribute_profile == profile
	if _online_character.get("id") != character.get("id") or _online_character.get("state_revision") != character.get("state_revision") or _attribute_profile != profile:
		allocation_draft = profile.get("allocated", []).duplicate()
	online_mode = true
	_online_character = character.duplicate(true)
	_online_stats = stats.duplicate(true)
	_attribute_profile = profile.duplicate(true)
	if is_node_ready() and not unchanged:
		_configure_signature()
		select_tab(selected_tab)

func display_local() -> void:
	var profile := Game.attribute_profile()
	if online_mode or _attribute_profile != profile:
		allocation_draft = profile.allocated.duplicate()
	online_mode = false
	_attribute_profile = profile
	allocation_enabled = not Game.storage_busy
	if is_node_ready():
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
	preview = OriginalArt.actor(ShopRules.actor_key(int(player.get("job",0)),int(player.get("gender",0)),player.get("appearance",[1,0])) if online_mode else Game.appearance_key())
	preview.position = Vector2(76, 193)
	preview.scale = Vector2(1.8, 1.8)
	content.add_child(preview)
	content.get_node("NameValue").text = String(player.get("name", ""))
	content.get_node("JobValue").text = Game.JOBS[int(player.get("job", 0))]
	content.get_node("SchoolValue").text = SchoolRules.label(int(player.get("school",SchoolRules.UNJOINED)))
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
	var combat: Dictionary = _attribute_profile.get("combat", {})
	for key in ["hp", "mp", "physical_attack", "magic_attack", "physical_defense", "magic_defense", "physical_crit", "magic_crit", "physical_hit", "magic_hit", "physical_evasion", "magic_evasion", "damage_reduction"]:
		var value: Variant = combat.get(key)
		if value == null and key in ["hp", "mp"]: value = _stats_data().get(key)
		if value == null and key in ["physical_defense", "magic_defense"]: value = _stats_data().get("defense")
		if value == null and key == ("magic_attack" if int(_player_data().get("job", 0)) == 2 else "physical_attack"): value = _stats_data().get("attack")
		var number: OriginalNumber = content.get_node("Value_" + key)
		number.value = "" if value == null else str(int(value))
		number.queue_redraw()
		content.get_node("Unknown_" + key).visible = value == null
		if key in ["physical_crit","magic_crit","physical_hit","magic_hit","physical_evasion","magic_evasion"]:number.tooltip_text=CharacterAttributeRules.RATING_HELP
	for i in 5:
		for prefix in ["Points","Minus","Plus"]:content.get_node(prefix+str(i)).tooltip_text=("定力：法术评级+1，每2点法防+1" if i==4 and _attribute_profile.get("formula_revision")==3 else CharacterAttributeRules.POINT_HELP[i]) if _attribute_profile.get("formula_revision") in [2,3] else "以当前服务端属性规则为准"
		content.get_node("Minus%d" % i).pressed.connect(_adjust_allocation.bind(i, -1))
		content.get_node("Plus%d" % i).pressed.connect(_adjust_allocation.bind(i, 1))
	content.get_node("Recommend").pressed.connect(_recommend_allocation)
	content.get_node("Confirm").pressed.connect(_confirm_allocation)
	content.get_node("Respec").pressed.connect(func()->void:
		var button:Button=content.get_node("Respec")
		if button.text!="确认重置":button.text="确认重置";content.get_node("Status").text="再次点击确认：仅一次，按比例保留血蓝，不会回满。"
		else:respec_requested.emit()
	)
	_refresh_allocation()

func set_allocation_enabled(enabled: bool, hint: String = "停稳后可加点") -> void:
	if allocation_enabled == enabled and allocation_hint == hint: return
	allocation_enabled = enabled
	allocation_hint = hint
	_refresh_allocation()

func _draft_remaining() -> int:
	var remaining := int(_attribute_profile.get("available", 0))
	var allocated: Array = _attribute_profile.get("allocated", [])
	for i in allocation_draft.size(): remaining -= int(allocation_draft[i]) - int(allocated[i])
	return remaining

func _refresh_allocation() -> void:
	if selected_tab != 1 or content == null: return
	var available: bool = allocation_draft.size() == 5 and _attribute_profile.get("allocated", []).size() == 5
	var enabled: bool = available and allocation_enabled
	var allocated: Array = _attribute_profile.get("allocated", [])
	for i in 5:
		content.get_node("Points%d" % i).text = str(int(allocation_draft[i])) if available else "—"
		content.get_node("Minus%d" % i).disabled = not enabled or int(allocation_draft[i]) <= int(allocated[i]) if available else true
		content.get_node("Plus%d" % i).disabled = not enabled or _draft_remaining() <= 0
	content.get_node("Remaining").text = str(_draft_remaining()) if available else "—"
	content.get_node("Recommend").disabled = not enabled or int(_attribute_profile.get("available", 0)) <= 0
	content.get_node("Confirm").disabled = not enabled or allocation_draft == allocated
	content.get_node("Respec").disabled=not enabled or not _player_data().get("balance_respec_available",false) or _player_data().get("corpse") is Dictionary or not allocated.any(func(v:Variant)->bool:return int(v)>0)
	content.get_node("Status").text = "同步中，请稍候" if not available else (allocation_hint if not allocation_enabled else (("确认后保存到服务端" if online_mode else "确认后保存到本地") if allocation_draft != allocated else "每级获得5点属性点"))
	if enabled and allocation_focus>=0 and _attribute_profile.get("formula_revision")==2:content.get_node("Status").text=CharacterAttributeRules.POINT_HELP[allocation_focus]

func _adjust_allocation(index: int, delta: int) -> void:
	if not allocation_enabled or allocation_draft.size() != 5: return
	if delta > 0 and _draft_remaining() <= 0: return
	if delta < 0 and int(allocation_draft[index]) <= int(_attribute_profile.allocated[index]): return
	allocation_draft[index] = int(allocation_draft[index]) + delta
	allocation_focus=index
	_refresh_allocation()

func _recommend_allocation() -> void:
	if not allocation_enabled or not _attribute_profile.has("recommended"): return
	allocation_draft = _attribute_profile.recommended.duplicate()
	allocation_focus=-1
	_refresh_allocation()

func _confirm_allocation() -> void:
	if not allocation_enabled or allocation_draft.is_empty() or allocation_draft == _attribute_profile.get("allocated", []): return
	allocation_requested.emit(allocation_draft.duplicate())

func _skills() -> void:
	var player := _player_data()
	for child in content.get_children():child.hide()
	var book:SkillBook=preload("res://scenes/ui/skill_book.tscn").instantiate()
	content.add_child(book);book.present(player,selected_tab==2)

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
