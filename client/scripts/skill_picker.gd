class_name SkillPicker
extends Panel
## Shared battle selection; original paper colors and recovered gold corner ornament.
signal chosen(id:String)
signal dismissed
var rows:VBoxContainer
var description:Label
var use_button:Button
var selected_id:=""
var choices:Array=[]
var current_mp:=0
const INK:=Color("654518")

func _init()->void:
	position=Vector2(25,89);size=Vector2(270,280)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color("fff0b8");paper.border_color=Color("b77c20");paper.set_border_width_all(4)
	add_theme_stylebox_override("panel",paper)
	add_theme_color_override("font_color",INK)
	var title:=Label.new();title.text="武功 · 选择招式";title.position=Vector2(12,8);title.add_theme_font_size_override("font_size",15);title.add_theme_color_override("font_color",INK);add_child(title)
	var scroll:=ScrollContainer.new();scroll.name="Skills";scroll.position=Vector2(10,35);scroll.size=Vector2(250,130);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	description=Label.new();description.position=Vector2(12,173);description.size=Vector2(246,61);description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;description.add_theme_font_size_override("font_size",12);description.add_theme_color_override("font_color",INK);add_child(description)
	use_button=Button.new();use_button.text="施展";use_button.position=Vector2(12,239);use_button.size=Vector2(117,30);add_child(use_button)
	_style_button(use_button)
	use_button.pressed.connect(func()->void:if not selected_id.is_empty():chosen.emit(selected_id))
	var back:=Button.new();back.text="返回";back.position=Vector2(141,239);back.size=Vector2(117,30);add_child(back);back.pressed.connect(func()->void:dismissed.emit())
	_style_button(back)
	for point in [Vector2(0,0),Vector2(260,0),Vector2(0,270),Vector2(260,270)]:
		var corner:=TextureRect.new();corner.texture=preload("res://assets/ui/chat_corner.png");corner.position=point;corner.size=Vector2(10,10);corner.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;corner.flip_h=point.x>0;corner.flip_v=point.y>0;corner.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(corner)

func present(job:int,school:int,level:int,mp:int,available:Array=[],legacy_only:bool=false)->void:
	current_mp=mp;selected_id="";choices=[]
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	for skill in SkillRules.list_for(job,school,level):
		if not skill.active or (legacy_only and not String(skill.id).begins_with("legacy_")) or (not available.is_empty() and not skill.id in available):continue
		choices.append(skill)
		var button:=Button.new();button.text="%s　%d灵力"%[skill.name,int(skill.mp_cost)];button.custom_minimum_size=Vector2(0,30);button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.add_theme_font_size_override("font_size",13);button.add_theme_color_override("font_color",INK);button.tooltip_text=skill.description;rows.add_child(button);button.pressed.connect(_select.bind(String(skill.id)))
		_style_button(button)
	if not choices.is_empty():_select(choices[0].id)
	else:description.text="尚无可用武功。";use_button.disabled=true
	show()

func _select(id:String)->void:
	selected_id=id
	var skill:=SkillRules.item(id)
	description.text=String(skill.description)+("\n灵力不足。" if current_mp<int(skill.mp_cost) else "")
	use_button.disabled=current_mp<int(skill.mp_cost)
	for i in rows.get_child_count():
		rows.get_child(i).text=("▶ " if choices[i].id==id else "   ")+"%s　%d灵力"%[choices[i].name,int(choices[i].mp_cost)]
		rows.get_child(i).add_theme_stylebox_override("normal",_paper(Color("f5d181") if choices[i].id==id else Color("fff0b8")))

func _paper(fill:Color)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=fill;style.border_color=Color("bb8d38");style.set_border_width_all(1);style.content_margin_left=4;style.content_margin_right=4
	return style

func _style_button(button:Button)->void:
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,_paper(Color("fff0b8") if state=="normal" else Color("f5d181")))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(key,INK)
	button.add_theme_color_override("font_disabled_color",Color("a08b5a"))
	button.add_theme_font_size_override("font_size",13)
