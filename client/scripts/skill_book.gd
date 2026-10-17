class_name SkillBook
extends Control
## Native eba0..ed16: compact name/rank list above a separate description.
var items:Array=[]
var level:=1
var selected_index:=0
@onready var rows:VBoxContainer=$SkillCatalog/Rows
@onready var detail:Label=$Description

func present(player:Dictionary,martial:bool)->void:
	level=int(player.level)
	items=SkillRules.list_for(int(player.job),int(player.school),level,true).filter(func(s:Dictionary)->bool:return bool(s.active)==martial)
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	for index in items.size():
		var skill:Dictionary=items[index]
		var row:=Button.new();row.custom_minimum_size=Vector2(0,28);row.alignment=HORIZONTAL_ALIGNMENT_LEFT;row.clip_text=true
		for state in ["normal","hover","pressed","focus"]:row.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var name_label:=Label.new();name_label.name="Name";name_label.text=skill.name;name_label.position=Vector2(6,3);name_label.size=Vector2(190,22);name_label.add_theme_font_size_override("font_size",14);name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(name_label)
		var rank:=Label.new();rank.name="Rank";rank.text="—/—";rank.position=Vector2(211,3);rank.size=Vector2(61,22);rank.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;rank.add_theme_font_size_override("font_size",13);rank.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(rank)
		row.tooltip_text="技能阶数尚未恢复";rows.add_child(row);row.pressed.connect(select_skill.bind(index))
	$Label0.visible=items.is_empty()
	if not items.is_empty():
		var first_unlocked:=items.find_custom(func(s:Dictionary)->bool:return level>=int(s.unlock_level))
		select_skill(maxi(0,first_unlocked))
	else:detail.text="";$SkillName.text=""

func select_skill(index:int)->void:
	if items.is_empty():return
	selected_index=clampi(index,0,items.size()-1)
	var skill:Dictionary=items[selected_index]
	$SkillName.text=skill.name
	detail.text=String(skill.description)
	if int(skill.mp_cost)>0:detail.text+="\n（消耗灵力%d）"%int(skill.mp_cost)
	detail.text+="\n%d级解锁"%int(skill.unlock_level) if level<int(skill.unlock_level) else ("\n已生效" if not skill.active else "")
	for i in rows.get_child_count():
		var row:Button=rows.get_child(i)
		var selected:=i==selected_index
		var bg:=StyleBoxFlat.new();bg.bg_color=Color("bc791d") if selected else Color.TRANSPARENT
		row.add_theme_stylebox_override("normal",bg)
		for child in row.get_children():child.add_theme_color_override("font_color",Color("fff10d") if selected else Color("402718"))
	$Provenance.text="阶数 —/— · 按角色等级解锁"

func _unhandled_key_input(event:InputEvent)->void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:return
	if event.keycode in [KEY_UP,KEY_DOWN]:
		select_skill(selected_index+(-1 if event.keycode==KEY_UP else 1))
		get_viewport().set_input_as_handled()
