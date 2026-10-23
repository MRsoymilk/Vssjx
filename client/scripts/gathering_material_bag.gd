class_name GatheringMaterialBag
extends Control
signal dismissed
const Chrome=preload("res://scripts/social_chrome.gd")
var online_model:OnlinePve
var rows:Label
var confirmation:Panel
func _ready()->void:
	z_index=30;mouse_filter=MOUSE_FILTER_STOP;size=Vector2(320,480)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.6);shade.size=size;add_child(shade)
	var paper:=Chrome.frame(self,Rect2(24,82,272,306),"采集材料袋")
	rows=OriginalSceneChrome.label(paper,"",Rect2(18,46,236,176),15,Chrome.INK)
	OriginalSceneChrome.label(paper,"独立材料袋 · 每种最多999份\n矿石与草药分别堆叠，不占装备格。",Rect2(14,225,244,39),11,Chrome.INK)
	var discard:=Chrome.placed_button(paper,"丢弃材料",Rect2(14,266,110,30));discard.pressed.connect(_discard)
	var back:=Chrome.placed_button(paper,"返回背包",Rect2(148,266,110,30));back.pressed.connect(func()->void:dismissed.emit())
	if online_model!=null:online_model.changed.connect(refresh)
	refresh()
func refresh()->void:
	var materials:Dictionary=Game.player.get("gathering",{}).get("materials",{}) if online_model==null else online_model.state.get("gathering",{}).get("materials",{})
	var lines:=PackedStringArray()
	for id in GatheringRules.MATERIALS:lines.append("%s　× %d\n"%[GatheringRules.MATERIALS[id],int(materials.get(id,0))])
	rows.text="\n".join(lines)
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
			yes.disabled=true
			var result:=await Game.discard_gathering(id,count)
			if not result.ok:yes.disabled=false;return
		confirmation.queue_free();confirmation=null;refresh()
	)
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:dismissed.emit();get_viewport().set_input_as_handled()
