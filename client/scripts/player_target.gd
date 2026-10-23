class_name PlayerTarget
extends Control
## First click selects; only the second, deliberate HUD click exposes actions.
signal action_requested(action:String)
signal actions_opened
const Chrome=preload("res://scripts/social_chrome.gd")
var selected:=""
var card:Button
var portrait:TextureRect
var caption:Label
var hp_bar:ProgressBar
var mp_bar:ProgressBar
var hp_text:Label
var mp_text:Label
var actions:Panel
var buttons:Dictionary={}
var _portrait_code:=-1

func _ready()->void:
	mouse_filter=MOUSE_FILTER_IGNORE;z_index=8
	card=Button.new();card.name="TargetCard";card.position=Vector2(182,32);card.size=Vector2(134,65);card.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("263b4b");style.border_color=Color("ffe69b") if state!="normal" else Color("b97a24");style.set_border_width_all(1);card.add_theme_stylebox_override(state,style)
	add_child(card)
	caption=OriginalSceneChrome.label(card,"",Rect2(5,2,124,16),10,Color("fff0ae"));caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.clip_text=true
	portrait=TextureRect.new();portrait.position=Vector2(4,20);portrait.size=Vector2(38,38);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.mouse_filter=MOUSE_FILTER_IGNORE;portrait.texture_filter=TEXTURE_FILTER_NEAREST;card.add_child(portrait)
	hp_bar=OriginalSceneChrome.progress(card,Rect2(46,22,82,15),Color("c84535"))
	mp_bar=OriginalSceneChrome.progress(card,Rect2(46,41,82,15),Color("438ddd"))
	hp_text=OriginalSceneChrome.label(card,"气血 —",Rect2(46,21,82,16),8,Color.WHITE);hp_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	mp_text=OriginalSceneChrome.label(card,"灵力 —",Rect2(46,40,82,16),8,Color.WHITE);mp_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for label in [hp_text,mp_text]:label.add_theme_constant_override("outline_size",1);label.add_theme_color_override("font_outline_color",Color("182821"))
	actions=OriginalSceneChrome.panel(self,Rect2(182,101,134,178),Color("263b4b"),Color("b97a24"));actions.mouse_filter=MOUSE_FILTER_STOP;actions.name="TargetActions"
	var entries:=[["profile","查看信息"],["friend","加为好友"],["team","邀请组队"],["duel","邀请切磋"],["clear","取消选中"]]
	for i in entries.size():
		var action:String=entries[i][0]
		var button:=Chrome.placed_button(actions,entries[i][1],Rect2(5,5+i*34,124,32));buttons[action]=button
		button.pressed.connect(func()->void:actions.hide();action_requested.emit(action))
	card.pressed.connect(func()->void:
		actions.visible=not actions.visible
		if actions.visible:actions_opened.emit()
	)
	actions.hide();hide()

func display(id:String,entity:Dictionary,profile:Dictionary,code:String="")->void:
	if selected!=id:actions.hide()
	selected=id
	if id.is_empty():hide();return
	caption.text=String(entity.get("display_name","玩家"))
	if not profile.is_empty():caption.text+=" · Lv.%d"%int(profile.level)
	var portrait_code:=clampi(int(entity.get("job",0)),0,2)*2+clampi(int(entity.get("gender",0)),0,1)
	if portrait_code!=_portrait_code:
		_portrait_code=portrait_code;portrait.texture=load("res://assets/ui/create_portrait_%d.png"%portrait_code)
	var vitals:Dictionary=profile.get("vitals",{})
	for key in ["hp","mp"]:
		var bar:=hp_bar if key=="hp" else mp_bar
		var label:=hp_text if key=="hp" else mp_text
		var maximum:=int(profile.get("combat",{}).get(key,0))
		bar.max_value=maxi(1,maximum);bar.value=int(vitals.get(key,0))
		label.text=("血 " if key=="hp" else "蓝 ")+("%d/%d"%[int(vitals[key]),maximum] if vitals.has(key) else "—")
	card.tooltip_text="点击头像展开操作。血蓝约每3秒同步，不影响移动。"
	if not code.is_empty():card.tooltip_text+="\n读取失败，显示上次数据，稍后重试。"
	elif vitals.is_empty():card.tooltip_text+="\n当前血蓝未获取；旧服务未提供时不会显示虚构满值。"

func close_actions()->void:actions.hide()
