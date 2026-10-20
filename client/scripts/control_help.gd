class_name ControlHelp
extends Control
signal dismissed
var online_mode:=false
var body:RichTextLabel
func _ready()->void:
	z_index=40
	var shade:=ColorRect.new();shade.size=Vector2(320,480);shade.color=Color(0.03,0.05,0.04,0.3);add_child(shade)
	var panel:Panel=preload("res://scripts/social_chrome.gd").frame(self,Rect2(12,48,296,384),"帮助")
	panel.name="Panel"
	body=RichTextLabel.new();body.name="Body";body.position=Vector2(16,44);body.size=Vector2(264,280)
	body.add_theme_font_size_override("normal_font_size",12);body.add_theme_color_override("default_color",Color("654518"))
	body.selection_enabled=true;body.scroll_active=true
	body.text=("当前为联机模式，以下指令仅在 local 使用。\n\n" if online_mode else "")+LocalWorldChat.control_help_text()
	panel.add_child(body)
	var back:Button=preload("res://scripts/social_chrome.gd").placed_button(panel,"返回",Rect2(112,342,72,28))
	back.name="Back";back.pressed.connect(func()->void:dismissed.emit())
func _unhandled_key_input(event:InputEvent)->void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		get_viewport().set_input_as_handled();dismissed.emit()
