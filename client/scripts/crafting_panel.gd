class_name CraftingPanel
extends Control
signal back_requested
signal changed
var online_model:OnlinePve
var selected_id:=""
var status:Label
var materials:Label
var details:Label
var affix:OptionButton
var focus:OptionButton
var upgrade:Button
var reroll:Button
var salvage:Button
var confirmation:=""
var busy:=false
var refreshing:=false
const INK:=Color("654518")
const SLOTS:={"weapon":"武器","pendant":"腰佩","armor":"衣服","wrist":"手腕","belt":"腰带","pants":"裤子","boots":"鞋子","ring":"戒指","necklace":"项链","hat":"帽子"}
func _ready()->void:
	z_index=2;size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP
	var paper:=Panel.new();paper.position=Vector2(8,61);paper.size=Vector2(304,363)
	var style:=StyleBoxFlat.new();style.bg_color=Color("fff0ba");style.border_color=Color("906329");style.set_border_width_all(3);paper.add_theme_stylebox_override("panel",style);add_child(paper)
	OriginalSceneChrome.label(self,"装备养成 · 不爆装／不重抽整件",Rect2(16,69,288,24),14,INK)
	materials=OriginalSceneChrome.label(self,"",Rect2(16,97,288,24),11,INK)
	var scroll:=ScrollContainer.new();scroll.position=Vector2(16,126);scroll.size=Vector2(288,111);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	details=OriginalSceneChrome.label(scroll,"",Rect2(0,0,272,111),11,INK);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=272;details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	affix=OptionButton.new();affix.name="Affix";affix.position=Vector2(16,244);affix.size=Vector2(288,25);affix.add_theme_font_size_override("font_size",11);add_child(affix);affix.item_selected.connect(func(_i:int)->void:confirmation="")
	reroll=OriginalSceneChrome.button(self,"洗炼选中词条",Rect2(16,277,140,26),11);reroll.name="Reroll";reroll.pressed.connect(_action.bind("gear_reroll"))
	upgrade=OriginalSceneChrome.button(self,"强化+1",Rect2(164,277,140,26),11);upgrade.name="Upgrade";upgrade.pressed.connect(_action.bind("gear_upgrade"))
	salvage=OriginalSceneChrome.button(self,"分解此装备",Rect2(16,311,140,26),11);salvage.name="Salvage";salvage.pressed.connect(_action.bind("gear_salvage"))
	focus=OptionButton.new();focus.name="Focus";focus.position=Vector2(164,311);focus.size=Vector2(140,26);focus.add_theme_font_size_override("font_size",11);add_child(focus)
	focus.add_item("掉落：随缘")
	for slot in ShopRules.SLOTS:focus.add_item("掉落："+SLOTS[slot])
	focus.item_selected.connect(_focus_selected)
	var back:=OriginalSceneChrome.button(self,"返回装备",Rect2(16,350,288,27),12);back.pressed.connect(func()->void:back_requested.emit())
	for control in [reroll,upgrade,salvage,back,focus,affix]:
		var normal:=StyleBoxFlat.new();normal.bg_color=Color("f6ce76");normal.border_color=Color("906329");normal.set_border_width_all(1)
		var disabled:=normal.duplicate();disabled.bg_color=Color("d8cda6")
		for key in ["normal","hover","pressed"]:control.add_theme_stylebox_override(key,normal)
		control.add_theme_stylebox_override("disabled",disabled)
		for key in ["font_color","font_hover_color","font_pressed_color"]:control.add_theme_color_override(key,INK)
		control.add_theme_color_override("font_disabled_color",Color("8e7949"))
	status=OriginalSceneChrome.label(self,"付费养成或分解需再次点击确认。",Rect2(16,383,288,34),10,INK);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if online_model!=null:online_model.changed.connect(_online_changed)
	refresh()
func _state()->Dictionary:return Game.player.get("loot_state",{}) if online_model==null else online_model.state.get("loot",{}).get("state",{})
func _character()->Dictionary:return Game.player if online_model==null else online_model.state.get("character",{})
func _item()->Dictionary:
	for item in _state().get("items",[]):
		if item.id==selected_id:return item
	return {}
func _locked()->bool:return busy or (Game.storage_busy or Game.local_battle_active() if online_model==null else not online_model.ready or online_model.pending() or online_model.active() or online_model.state.get("loot",{}).get("progression_sha256")!=ProgressionRules.catalog_hash) or _character().get("corpse") is Dictionary
func refresh()->void:
	refreshing=true
	var state:=_state();var item:=_item();var locked:=_locked();var selected:=affix.selected
	materials.text="铜钱%d · 炼材%d · 精华%d"%[int(_character().get("gold",0)),int(state.get("scrap",0)),int(state.get("essence",0))]
	focus.select(ShopRules.SLOTS.find(state.get("focus",""))+1);focus.disabled=locked or state.is_empty()
	affix.clear();upgrade.disabled=true;reroll.disabled=true;salvage.disabled=true
	if item.is_empty():details.text="请在装备列表选中一件，再打开养成。\n定向掉落：80%优先选定部位。\n每8场普通遭遇保底装备；15级以上每8个首领保底流派装备。";refreshing=false;return
	details.text=LootRules.describe(item)
	for i in item.affixes.size():affix.add_item("词条%d：%s"%[i+1,LootRules.affix_text(item.affixes[i])])
	if not item.affixes.is_empty():affix.select(int(item.reroll_index) if item.get("reroll_index")!=null else clampi(selected,0,item.affixes.size()-1))
	affix.disabled=locked or item.get("reroll_index")!=null or item.affixes.is_empty()
	for action in ["gear_upgrade","gear_reroll"]:
		var quote:=ProgressionRules.quote(item,action);var button:Button=upgrade if action=="gear_upgrade" else reroll
		button.disabled=locked or quote.has("error")
		if quote.has("cost"):
			var cost:Array=quote.cost;details.text+="\n%s：%d铜／%d炼材／%d精华"%["强化+1" if action=="gear_upgrade" else "洗炼",cost[0],cost[1],cost[2]]
			button.text=("强化+1" if action=="gear_upgrade" else "洗炼")+" · %d铜"%int(cost[0])
			button.disabled=button.disabled or int(_character().gold)<int(cost[0]) or int(state.scrap)<int(cost[1]) or int(state.essence)<int(cost[2])
		else:details.text+="\n"+OnlinePve.error_text(quote.error)
	salvage.disabled=locked or item.legacy or item.equipped
	if not item.legacy:details.text+="\n分解：%d炼材／%d精华，保留外观解锁。"%[ProgressionRules.rules.salvage_scrap[item.quality],ProgressionRules.rules.salvage_essence[item.quality]]
	refreshing=false
func _online_changed()->void:
	confirmation="";refresh();changed.emit()
	if not online_model.last_code.is_empty():status.text=OnlinePve.error_text(online_model.last_code)
func _focus_selected(index:int)->void:
	if refreshing or _locked():return
	confirmation="";_submit("gear_focus","any" if index==0 else ShopRules.SLOTS[index-1],1)
func _action(action:String)->void:
	if _locked() or _item().is_empty():return
	var button:Button={"gear_upgrade":upgrade,"gear_reroll":reroll,"gear_salvage":salvage}[action]
	if button.disabled:return
	var key:="%s:%d"%[action,affix.selected]
	if confirmation!=key:
		confirmation=key
		if action=="gear_salvage":status.text="再次点击确认分解，装备将永久消失。"
		else:
			var cost:Array=ProgressionRules.quote(_item(),action).cost
			status.text="再次确认：%d铜／%d炼材／%d精华；洗炼锁定所选词条。"%cost
		return
	confirmation="";_submit(action,selected_id,affix.selected+1 if action=="gear_reroll" else 1)
func _submit(action:String,target:String,count:int)->void:
	if online_model!=null:
		status.text="正在等待服务端确认……" if online_model.submit(action,target,[],count) else "当前不能提交，请等待同步。";return
	busy=true;refresh()
	var result:=await Game.loot_command(action,target,count)
	if not is_inside_tree():return
	busy=false;refresh();status.text="已保存，材料与装备同步生效。" if result.ok else result.message;changed.emit()
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:back_requested.emit();get_viewport().set_input_as_handled()
