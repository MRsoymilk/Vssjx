class_name BattleItemPicker
extends Control
## Opening this panel never submits an action or consumes inventory.
signal chosen(id:String)
signal dismissed
var item_button:Button
var description:Label
var quantity:=0
var current_hp:=0
var maximum_hp:=0
var submitted:=false

func _init()->void:
	name="BattleItemPicker";size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP;z_index=5
	theme=preload("res://scenes/ui/login_theme.tres")
	var shade:=ColorRect.new();shade.size=size;shade.color=Color(0,0,0,0.18);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	var paper:=Panel.new();paper.position=Vector2(43,144);paper.size=Vector2(234,178)
	var style:=StyleBoxFlat.new();style.bg_color=Color("fff6bc");style.border_color=Color("643019");style.set_border_width_all(2)
	paper.add_theme_stylebox_override("panel",style);add_child(paper)
	var title:=OriginalSceneChrome.label(paper,"可用道具",Rect2(8,7,218,22),15,Color("643019"));title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	item_button=OriginalSceneChrome.button(paper,"",Rect2(12,36,210,34),13);item_button.name="Potion";item_button.focus_mode=Control.FOCUS_NONE
	_style_button(item_button);item_button.alignment=HORIZONTAL_ALIGNMENT_LEFT
	item_button.icon=load(ShopRules.item("potion").icon);item_button.expand_icon=true;item_button.add_theme_constant_override("icon_max_width",24)
	item_button.pressed.connect(activate)
	description=OriginalSceneChrome.label(paper,"",Rect2(12,76,210,49),11,Color("643019"));description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var back:=OriginalSceneChrome.button(paper,"取消",Rect2(82,139,70,27),13);back.name="Cancel";back.focus_mode=Control.FOCUS_NONE
	_style_button(back)
	back.pressed.connect(func()->void:dismissed.emit())

func _style_button(button:Button)->void:
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("e9e1b9") if state=="disabled" else Color("e7c577") if state=="pressed" else Color("f5df96")
		style.border_color=Color("976c37");style.set_border_width_all(1);style.content_margin_left=6
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:button.add_theme_color_override(state,Color("643019"))
	button.add_theme_color_override("font_disabled_color",Color("8a806d"));button.add_theme_constant_override("outline_size",0)
	button.add_theme_color_override("font_shadow_color",Color.TRANSPARENT)

func present(count:int,hp:int,max_hp:int,healing:int)->void:
	submitted=false
	refresh_values(count,hp,max_hp,healing)
	show()

func refresh_values(count:int,hp:int,max_hp:int,healing:int)->void:
	quantity=count;current_hp=hp;maximum_hp=max_hp
	item_button.text="%s ×%d"%[ShopRules.item("potion").name,count]
	item_button.disabled=submitted or count<=0 or hp>=max_hp
	description.text="恢复%d点气血，最多不超过上限。\n当前气血：%d / %d"%[healing,hp,max_hp]
	if count<=0:description.text="背包中没有战斗可用的回春散。"
	elif hp>=max_hp:description.text+="\n气血已满，无需用药。"

func activate()->void:
	if not is_visible_in_tree() or submitted or quantity<=0 or current_hp>=maximum_hp or item_button.disabled:return
	submitted=true;item_button.disabled=true
	chosen.emit("potion")

func _unhandled_key_input(event:InputEvent)->void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	var viewport:=get_viewport()
	match event.keycode:
		KEY_1,KEY_ENTER,KEY_KP_ENTER:activate()
		KEY_ESCAPE:dismissed.emit()
		_:return
	viewport.set_input_as_handled()
