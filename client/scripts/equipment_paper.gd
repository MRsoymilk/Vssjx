extends RefCounted
## Shared original-style paper for equipment details and progression.
const INK := Color("705124")
const GREEN := Color("4e883b")
const RED := Color("b14435")
const PAPER := Color("faf4b5")
const EDGE := Color("80551e")
const GOLD := Color("ead14a")
const BLUE := Color("79acd0")

static func frame(parent: Node, rect: Rect2, caption: String) -> Panel:
	var panel := OriginalSceneChrome.panel(parent, rect, PAPER, EDGE)
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_border_width_all(2)
	style.shadow_color=Color(0,0,0,0.3);style.shadow_size=3;style.shadow_offset=Vector2(2,3)
	OriginalSceneChrome.panel(panel,Rect2(2,2,rect.size.x-4,rect.size.y-4),Color.TRANSPARENT,GOLD)
	OriginalSceneChrome.panel(panel,Rect2(4,4,rect.size.x-8,20),BLUE,BLUE)
	var title:=OriginalSceneChrome.label(panel,caption,Rect2(9,4,rect.size.x-18,20),14,Color("fff450"))
	title.name="Title";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.clip_text=true
	title.mouse_filter=Control.MOUSE_FILTER_PASS
	title.add_theme_color_override("font_outline_color",Color("4f613e"));title.add_theme_constant_override("outline_size",1)
	for index in 4:
		var corner:=TextureRect.new();corner.texture=preload("res://assets/ui/bag_corner.png")
		corner.size=Vector2(8,8);corner.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		corner.position=Vector2(rect.size.x-8 if index%2 else 0,rect.size.y-8 if index>=2 else 0)
		corner.flip_h=index%2==1;corner.flip_v=index>=2;corner.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_child(corner)
	return panel

static func button(parent: Node, caption: String, rect: Rect2) -> Button:
	var result:=OriginalSceneChrome.button(parent,caption,rect,12)
	skin_button(result)
	return result

static func skin_button(button: Button) -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color("d8c78d") if state=="disabled" else Color("ac772a" if state=="pressed" else "b98a3d")
		style.border_color=Color("a48b54") if state=="disabled" else EDGE
		style.set_border_width_all(1);style.set_content_margin_all(2)
		button.add_theme_stylebox_override(state,style)
	for state in ["font_color","font_hover_color","font_pressed_color"]:button.add_theme_color_override(state,Color("fff5b4"))
	button.add_theme_color_override("font_disabled_color",Color("8f7c50"))
	button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	if not button.has_node("PaperInset"):
		var inset:=OriginalSceneChrome.panel(button,Rect2(Vector2(2,2),button.size-Vector2(4,4)),Color.TRANSPARENT,Color("fff1aa"))
		inset.name="PaperInset"
