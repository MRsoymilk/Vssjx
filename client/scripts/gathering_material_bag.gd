class_name GatheringMaterialBag
extends Control
signal dismissed
const Chrome=preload("res://scripts/social_chrome.gd")
var online_model:OnlinePve
var rows:Label
var confirmation:Panel
var stock:Label
var recipe_picker:OptionButton
var batches:SpinBox
var recipe_details:Label
var status:Label
var craft:Button
var discard:Button
var saving:=false
func _ready()->void:
	z_index=30;mouse_filter=MOUSE_FILTER_STOP;size=Vector2(320,480)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.6);shade.size=size;add_child(shade)
	var paper:=Chrome.frame(self,Rect2(20,40,280,400),"采集材料与加工")
	rows=OriginalSceneChrome.label(paper,"",Rect2(18,42,244,80),14,Chrome.INK)
	stock=OriginalSceneChrome.label(paper,"",Rect2(14,126,252,22),12,Chrome.INK)
	OriginalSceneChrome.label(paper,"材料每种最多999份，不占装备格。\n炼材用于强化／重铸，回春散放入背包。",Rect2(14,153,252,36),11,Chrome.INK)
	recipe_picker=OptionButton.new();recipe_picker.position=Vector2(14,197);recipe_picker.size=Vector2(252,30);recipe_picker.add_theme_font_size_override("font_size",13);paper.add_child(recipe_picker)
	for entry in GatheringRules.recipes.recipes:recipe_picker.add_item(entry.name)
	recipe_picker.item_selected.connect(func(_index:int)->void:status.text="";refresh())
	batches=SpinBox.new();batches.position=Vector2(14,235);batches.size=Vector2(75,30);batches.min_value=1;batches.max_value=int(GatheringRules.recipes.batch_limit);paper.add_child(batches)
	batches.value_changed.connect(func(_value:float)->void:status.text="";refresh())
	craft=Chrome.placed_button(paper,"加工",Rect2(98,235,168,30));craft.pressed.connect(_craft)
	recipe_details=OriginalSceneChrome.label(paper,"",Rect2(14,275,252,37),12,Chrome.INK);recipe_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status=OriginalSceneChrome.label(paper,"",Rect2(14,316,252,36),11,Chrome.INK);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	discard=Chrome.placed_button(paper,"丢弃材料",Rect2(14,358,110,30));discard.pressed.connect(_discard)
	var back:=Chrome.placed_button(paper,"返回背包",Rect2(156,358,110,30));back.pressed.connect(func()->void:
		if not saving:dismissed.emit()
	)
	if online_model!=null:
		online_model.changed.connect(refresh)
		online_model.message.connect(func(text:String)->void:
			if online_model.last_action in ["gather_craft","gather_discard"]:status.text=text
		)
	refresh()
func refresh()->void:
	var materials:Dictionary=Game.player.get("gathering",{}).get("materials",{}) if online_model==null else online_model.state.get("gathering",{}).get("materials",{})
	var lines:=PackedStringArray()
	for id in GatheringRules.MATERIALS:lines.append("%s　× %d"%[GatheringRules.MATERIALS[id],int(materials.get(id,0))])
	rows.text="\n".join(lines)
	var player:Dictionary=Game.player if online_model==null else online_model.state
	var loot:Dictionary=player.get("loot_state",{}) if online_model==null else player.get("loot",{}).get("state",{})
	var potions:=int(player.get("potions",0));var scrap:=int(loot.get("scrap",0))
	stock.text="炼材 ×%d　回春散 ×%d / 99"%[scrap,potions]
	var entry:Dictionary=GatheringRules.recipes.recipes[recipe_picker.selected];var count:=int(batches.value)
	recipe_details.text=GatheringRules.recipe_text(entry.id,count)
	craft.text="加工 %d 份"%count
	var gear:Dictionary=ShopRules.local_state(player) if online_model==null else player.get("shop",{"owned":[]})
	var error:=GatheringRules.craft_error(entry.id,count,materials,scrap,potions,ShopRules.bag_slots(gear,potions)+LootRules.extra_bag(loot))
	var busy:bool=(saving or Game.storage_busy or Game.local_combat!=null or Game.is_soul()) if online_model==null else (not online_model.ready or online_model.pending() or online_model.active() or online_model.is_soul())
	var compatible:bool=online_model==null or player.get("gathering",{}).get("recipes_sha256")==GatheringRules.recipes_hash
	craft.disabled=busy or not compatible or not error.is_empty()
	discard.disabled=busy or materials.is_empty()
	recipe_picker.disabled=busy;batches.editable=not busy
	craft.tooltip_text=OnlinePve.error_text(error) if not error.is_empty() else ""
	if not compatible:recipe_details.text="加工配方版本不一致，请更新客户端或服务器。"
	elif not error.is_empty():recipe_details.text+="\n"+OnlinePve.error_text(error)
func _craft()->void:
	if saving or craft.disabled:return
	var id:String=GatheringRules.recipes.recipes[recipe_picker.selected].id;var count:=int(batches.value)
	if online_model!=null:
		if online_model.submit("gather_craft",id,[],count):status.text="正在加工……"
	else:
		saving=true;refresh()
		var result:=await Game.craft_gathering(id,count)
		saving=false;status.text="加工完成："+GatheringRules.recipe_text(id,count) if result.ok else result.message
	refresh()
func _discard()->void:
	if is_instance_valid(confirmation):return
	var values:Dictionary=Game.player.get("gathering",{}).get("materials",{}) if online_model==null else online_model.state.get("gathering",{}).get("materials",{})
	confirmation=Chrome.frame(self,Rect2(30,160,260,174),"确认丢弃材料")
	var pick:=OptionButton.new();pick.position=Vector2(16,42);pick.size=Vector2(228,30);confirmation.add_child(pick)
	var ids:Array=[]
	for id in GatheringRules.MATERIALS:
		if int(values.get(id,0))>0:ids.append(id);pick.add_item("%s ×%d"%[GatheringRules.MATERIALS[id],int(values[id])])
	var amount:=SpinBox.new();amount.position=Vector2(16,80);amount.size=Vector2(228,30);amount.min_value=1;amount.max_value=int(values.get(ids[0],1)) if not ids.is_empty() else 1;confirmation.add_child(amount)
	pick.item_selected.connect(func(index:int)->void:amount.max_value=int(values[ids[index]]))
	var yes:=Chrome.placed_button(confirmation,"确认丢弃",Rect2(16,130,100,30));yes.disabled=ids.is_empty()
	var no:=Chrome.placed_button(confirmation,"取消",Rect2(144,130,100,30));no.pressed.connect(func()->void:confirmation.queue_free();confirmation=null)
	yes.pressed.connect(func()->void:
		var id:String=ids[pick.selected];var count:=int(amount.value)
		if online_model!=null:
			if not online_model.submit("gather_discard",id,[],count):return
		else:
			yes.disabled=true;no.disabled=true;saving=true
			var result:=await Game.discard_gathering(id,count)
			saving=false
			if not result.ok:yes.disabled=false;no.disabled=false;status.text=result.message;return
		confirmation.queue_free();confirmation=null;refresh()
	)
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if not saving:dismissed.emit()
		get_viewport().set_input_as_handled()
