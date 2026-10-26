class_name SkillPicker
extends Control
## Native rows and cost column, expanded vertically to show the current skill pool.
signal chosen(id: String)
signal dismissed
var rows: VBoxContainer
var description: Label
var scroll: ScrollContainer
var selected_id := ""
var choices: Array = []
var current_mp := 0
var submitted := false
var locked := false
var combat_stats:Dictionary={}
var combat_effects:Dictionary={}
var paper:Panel
var heading:ColorRect
var name_heading:Label
var mana_heading:Label
var strip:Panel
var back:Button
const INK := Color("643019")
const ROW_HEIGHT := 19
const MAX_VISIBLE_ROWS := 13

func _init() -> void:
	size = Vector2(320, 424)
	mouse_filter = Control.MOUSE_FILTER_STOP
	paper = Panel.new()
	paper.position = Vector2(90, 165); paper.size = Vector2(140, 150)
	paper.add_theme_stylebox_override("panel", _paper(Color("fff6bc"), true))
	add_child(paper)
	heading = ColorRect.new()
	heading.position = Vector2(92, 167); heading.size = Vector2(136, 20)
	heading.color = Color("ff684a"); heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(heading)
	name_heading=_caption("技能", Vector2(105, 168), Vector2(60, 17), Color("fff6bc"))
	mana_heading=_caption("灵力", Vector2(189, 168), Vector2(32, 17), Color("fff6bc"))
	scroll = ScrollContainer.new(); scroll.name = "Skills"
	scroll.position = Vector2(94, 194); scroll.size = Vector2(132, 114)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	rows = VBoxContainer.new(); rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 0); scroll.add_child(rows)
	strip = Panel.new()
	strip.position = Vector2(0, 134); strip.size = Vector2(320, 30)
	strip.add_theme_stylebox_override("panel", _paper(Color("fff6bc"), true))
	add_child(strip)
	description = _caption("", Vector2(4, 137), Vector2(312, 25), INK)
	description.add_theme_font_size_override("font_size", 10)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.clip_text = true
	back = Button.new(); back.name = "Back"; back.text = "返回"
	back.position = Vector2(134, 316); back.size = Vector2(52, 22)
	_style_button(back); add_child(back)
	back.pressed.connect(func() -> void: dismissed.emit())
	_layout_choices()

func _layout_choices()->void:
	# Thirteen rows fit between the countdown and bottom chat at the native size.
	# Retain scrolling as a fallback if a future catalog adds more skills.
	var list_height:=float(ROW_HEIGHT*clampi(choices.size(),6,MAX_VISIBLE_ROWS))
	var paper_height:=maxf(150.0,list_height+30.0)
	var top:=240.0-paper_height*0.5
	paper.position=Vector2(90,top);paper.size=Vector2(140,paper_height)
	heading.position=Vector2(92,top+2)
	name_heading.position=Vector2(105,top+3);mana_heading.position=Vector2(189,top+3)
	scroll.position=Vector2(94,top+26);scroll.size=Vector2(132,list_height)
	strip.position=Vector2(0,top-31);description.position=Vector2(4,top-28)
	back.position=Vector2(134,top+paper_height+1)
	back.size=Vector2(52,22)

static func usable_choices(job: int, school: int, level: int, available: Array = [], legacy_only: bool = false) -> Array:
	return SkillRules.list_for(job,school,level).filter(func(skill: Dictionary) -> bool:
		return skill.active and (not legacy_only or String(skill.id).begins_with("legacy_")) and (available.is_empty() or skill.id in available))

static func has_usable(job: int, school: int, level: int, mp: int, available: Array = [], legacy_only: bool = false, stats:Dictionary={}, effects:Dictionary={}) -> bool:
	return usable_choices(job,school,level,available,legacy_only).any(func(skill: Dictionary) -> bool: return mp >= SkillBalance.cost(skill,stats) and SkillRules.remaining(effects,skill.id)==0)

func present(job: int, school: int, level: int, mp: int, available: Array = [], legacy_only: bool = false, stats:Dictionary={}, effects:Dictionary={}) -> void:
	current_mp = mp; selected_id = ""; submitted = false; locked = false
	combat_stats=stats;combat_effects=effects
	choices = usable_choices(job,school,level,available,legacy_only).duplicate(true)
	_layout_choices()
	scroll.scroll_vertical=0
	for skill in choices:
		skill.mp_cost=SkillBalance.cost(skill,stats)
		skill.description=SkillRules.description(skill,SkillRules.stun_enabled(effects))
		skill.full_description=skill.description
		if skill.has("stun") and SkillRules.stun_enabled(effects):skill.description="%d%%眩晕：跳过下次行动，受击不解除"%int(skill.stun.chance)
		if SkillBalance.revised(stats):
			var cooldown_text:=" · 冷却%d轮"%SkillBalance.cooldown(skill,SkillRules.stun_enabled(effects))
			skill.description+=cooldown_text;skill.full_description+=cooldown_text
	for child in rows.get_children(): rows.remove_child(child); child.queue_free()
	for skill in choices:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = skill.full_description
		_style_button(button); rows.add_child(button)
		var name_label := _caption(String(skill.name),Vector2(3,1),Vector2(92,17),INK,button)
		name_label.name = "Name"; name_label.clip_text = true
		var cost := _caption(str(int(skill.mp_cost)),Vector2(95,1),Vector2(26,17),INK,button)
		cost.name = "Cost"; cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.mouse_entered.connect(_select.bind(String(skill.id)))
		button.pressed.connect(activate.bind(String(skill.id)))
	if not choices.is_empty(): _select(choices[0].id)
	else: description.text = "尚无可用技能。"
	show()

func _select(id: String) -> void:
	if choices.find_custom(func(skill: Dictionary) -> bool: return skill.id == id) < 0: return
	selected_id = id
	var skill:Dictionary=choices[choices.find_custom(func(s:Dictionary)->bool:return s.id==id)]
	var remaining:=SkillRules.remaining(combat_effects,id)
	description.text = String(skill.description) + ("（尚余%d轮）"%remaining if remaining>0 else ("（灵力不足）" if current_mp < int(skill.mp_cost) else ""))
	description.tooltip_text = String(skill.get("full_description",skill.description)) + ("（尚余%d轮）"%remaining if remaining>0 else "")
	for index in rows.get_child_count():
		var row: Button = rows.get_child(index)
		var selected: bool = choices[index].id == id
		# Hover/press/focus must retain the selected fill as well as its text color.
		# Otherwise the button's paper hover style erases the dark highlight.
		for state in ["normal","hover","pressed","focus","disabled"]:
			row.add_theme_stylebox_override(state,_paper(Color("a33d2f") if selected else Color("fff6bc")))
		for label in row.get_children():
			var unavailable: bool=current_mp < int(choices[index].mp_cost) or SkillRules.remaining(combat_effects,choices[index].id)>0
			label.add_theme_color_override("font_color",(Color("e5c59d") if selected else Color("808080")) if unavailable else (Color("fdf10a") if selected else INK))
		if selected: scroll.ensure_control_visible(row)

func activate(id: String) -> void:
	if not is_visible_in_tree() or locked or submitted: return
	if choices.find_custom(func(skill: Dictionary) -> bool: return skill.id == id) < 0: return
	_select(id)
	if current_mp < SkillBalance.cost(SkillRules.item(id),combat_stats) or SkillRules.remaining(combat_effects,id)>0:return
	submitted = true
	chosen.emit(id)

func _caption(text: String, point: Vector2, extent: Vector2, color: Color, parent: Node = null) -> Label:
	var label := Label.new(); label.text = text; label.position = point; label.size = extent
	label.add_theme_font_size_override("font_size",12); label.add_theme_color_override("font_color",color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent == null: add_child(label)
	else: parent.add_child(label)
	return label

func _paper(fill: Color, border: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = fill; style.border_color = INK
	style.set_border_width_all(1 if border else 0)
	return style

func _style_button(button: Button) -> void:
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,_paper(Color("fff6bc")))
	button.add_theme_font_size_override("font_size",12)
	button.add_theme_color_override("font_color",INK)
	button.add_theme_color_override("font_hover_color",INK)
	button.add_theme_color_override("font_pressed_color",INK)

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var index := choices.find_custom(func(skill: Dictionary) -> bool: return skill.id == selected_id)
	match event.keycode:
		KEY_UP, KEY_DOWN:
			if not choices.is_empty(): _select(choices[clampi(index + (-1 if event.keycode == KEY_UP else 1),0,choices.size()-1)].id)
		KEY_ENTER, KEY_KP_ENTER: activate(selected_id)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var target: int = event.keycode - KEY_1
			if target < choices.size(): activate(choices[target].id)
		KEY_ESCAPE: dismissed.emit()
		_: return
	get_viewport().set_input_as_handled()
