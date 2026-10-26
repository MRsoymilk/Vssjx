class_name EconomyPanel
extends Control
signal dismissed
var model:OnlineEconomy
var online_model:OnlinePve
var section:="browse"
var rows:VBoxContainer
var scroll:ScrollContainer
var notice:Label
var confirmation:Panel
var confirm_text:Label
var confirm_action:=""
var confirm_values:Dictionary={}
var refresh_due:=false
var sell_item:OptionButton
var starting:SpinBox
var buyout:SpinBox
var hours:OptionButton
var draft_trade:=""
var draft_items:Dictionary={}
var draft_gold:=-1
const INK:=Color("654518")
func _ready()->void:
	size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP;z_index=20
	theme=preload("res://scenes/ui/shop_category_theme.tres").duplicate(true)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.6);shade.size=size;add_child(shade)
	preload("res://scripts/equipment_paper.gd").frame(self,Rect2(8,27,304,426),"拍卖行 · 铜钱交易")
	for i in 5:
		var key:String=["browse","sell","mine","deliveries","direct"][i]
		var tab:=button(["拍卖","上架","我的","领取","当面"][i],self);tab.position=Vector2(17+i*58,67);tab.size=Vector2(56,30);tab.pressed.connect(_tab.bind(key))
	scroll=ScrollContainer.new();scroll.position=Vector2(18,104);scroll.size=Vector2(284,270);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	scroll.get_v_scroll_bar().custom_minimum_size.x=24
	for state in ["scroll","grabber","grabber_highlight","grabber_pressed"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("8b632c") if state=="scroll" else Color("dfbd63");style.content_margin_left=12;style.content_margin_right=12
		scroll.get_v_scroll_bar().add_theme_stylebox_override(state,style)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	notice=OriginalSceneChrome.label(self,"仅未绑定装备可交易，首次穿戴后永久绑定。",Rect2(18,379,284,36),10,INK);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var refresh:=button("刷新",self);refresh.position=Vector2(20,418);refresh.size=Vector2(80,28);refresh.pressed.connect(func()->void:model.fetch())
	var back:=button("返回",self);back.position=Vector2(220,418);back.size=Vector2(80,28);back.pressed.connect(func()->void:dismissed.emit())
	confirmation=OriginalSceneChrome.panel(self,Rect2(20,141,280,196),Color("fff1b8"),Color("8d6223"));confirmation.z_index=10;confirmation.mouse_filter=Control.MOUSE_FILTER_STOP
	confirm_text=OriginalSceneChrome.label(confirmation,"",Rect2(12,10,256,126),12,INK);confirm_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var yes:=button("确认",confirmation);yes.position=Vector2(12,151);yes.size=Vector2(112,32);yes.pressed.connect(func()->void:confirmation.hide();if not model.submit(confirm_action,confirm_values):notice.text="请等待当前操作完成。")
	var no:=button("取消",confirmation);no.position=Vector2(156,151);no.size=Vector2(112,32);no.pressed.connect(func()->void:confirmation.hide())
	confirmation.hide()
	if model==null:model=OnlineEconomy.new();model.bind_model(online_model)
	model.changed.connect(func()->void:refresh_due=true);model.message.connect(func(text:String)->void:notice.text=text)
	model.fetch();render()
func _process(_delta:float)->void:
	model.tick()
	if refresh_due and not confirmation.visible:
		var focus:=get_viewport().gui_get_focus_owner()
		if focus is LineEdit and is_ancestor_of(focus):return
		refresh_due=false;render()
func _exit_tree()->void:
	if model!=null:model.detach()
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit and is_ancestor_of(focus):Platform.context.text_input.release_focus(focus)
func button(text:String,parent:Node)->Button:
	var b:=Button.new();b.text=text;b.custom_minimum_size=Vector2(0,30);b.add_theme_font_size_override("font_size",11);parent.add_child(b);preload("res://scripts/equipment_paper.gd").skin_button(b)
	var inset:Panel=b.get_node("PaperInset");inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);inset.offset_left=2;inset.offset_top=2;inset.offset_right=-2;inset.offset_bottom=-2
	return b
func label(text:String)->Label:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.custom_minimum_size.x=250;l.add_theme_color_override("font_color",INK);l.add_theme_font_size_override("font_size",11);rows.add_child(l);return l
func spinner(value:int)->SpinBox:
	var s:=SpinBox.new();s.min_value=1;s.max_value=1000000000;s.step=1;s.value=value;s.update_on_text_changed=true;s.custom_minimum_size=Vector2(250,32);s.add_theme_font_size_override("font_size",11);rows.add_child(s);s.get_line_edit().add_theme_font_size_override("font_size",11);s.get_line_edit().focus_entered.connect(func()->void:Platform.context.text_input.request_focus(s.get_line_edit()));return s
func _tab(key:String)->void:
	section=key;model.filters.scope="mine" if key=="mine" else "browse";model.filters.page=0;model.fetch();render()
func confirm(action:String,values:Dictionary,text:String)->void:
	if model.pending():notice.text="前一笔操作待确认，请稍候。";return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit and is_ancestor_of(focus):Platform.context.text_input.release_focus(focus)
	confirm_action=action;confirm_values=values.duplicate(true);confirm_text.text=text;confirmation.show()
func render()->void:
	if not is_node_ready():return
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	if section=="direct":_trade();return
	if section=="sell":_sell();return
	if section=="deliveries":
		label("成交、退款和退回的装备在此领取；满包可入暂存，空间全满时保留在此。")
		for delivery in model.state.get("deliveries",[]):
			label(LootRules.describe(delivery.item) if delivery.item!=null else "铜钱 ×%d"%int(delivery.gold))
			button("领取",rows).pressed.connect(func()->void:confirm("claim",{"target":delivery.id},"确认领取该装备或铜钱？\n物品编号："+delivery.id.right(8)))
		return
	_filters()
	for listing in model.state.get("listings",[]):
		label(LootRules.describe(listing.item))
		label("卖家：%s\n当前%d铜 · 一口价%d铜\n%s · 剩余%d分钟"%[listing.seller_name,int(listing.bid) if int(listing.bid)>0 else int(listing.starting_price),int(listing.buyout),{"open":"拍卖中","sold":"已成交","cancelled":"已撤回","expired":"已到期"}[listing.status],maxi(0,int(listing.expires_ms)-int(model.state.server_time_ms))/60000])
		if listing.status!="open":continue
		if listing.seller==model.character_id:
			var cancel:=button("下架（无出价时）",rows);cancel.disabled=listing.bidder!=null
			cancel.pressed.connect(func()->void:confirm("cancel",{"target":listing.id,"revision":int(listing.revision)},"确认下架？装备将退回“领取”页。"));continue
		var amount:=spinner(int(listing.starting_price) if int(listing.bid)==0 else mini(int(listing.buyout),int(listing.bid)+maxi(1,ceili(int(listing.bid)*0.05))))
		button("出价",rows).pressed.connect(func()->void:confirm("bid",{"target":listing.id,"revision":int(listing.revision),"amount":int(amount.value)},"对%s出价%d铜？\n编号%s\n铜钱托管，被超价后退款到“领取”页。"%[ShopRules.item(listing.item.template).name,int(amount.value),listing.item.id.right(8)]))
		button("一口价购买",rows).pressed.connect(func()->void:confirm("buy",{"target":listing.id,"revision":int(listing.revision)},"以%d铜购买%s？\n编号%s\n成交后到“领取”页领取，不绑定。"%[int(listing.buyout),ShopRules.item(listing.item.template).name,listing.item.id.right(8)]))
	var pager:=HBoxContainer.new();rows.add_child(pager)
	var previous:=button("上一页",pager);previous.disabled=int(model.filters.page)==0;previous.pressed.connect(func()->void:model.filters.page-=1;model.fetch())
	var next:=button("下一页",pager);next.disabled=not model.state.get("more",false);next.pressed.connect(func()->void:model.filters.page+=1;model.fetch())
func _filters()->void:
	var selectors:=HBoxContainer.new();rows.add_child(selectors)
	for key in ["job","slot","quality"]:
		var picker:=OptionButton.new();picker.custom_minimum_size=Vector2(78,30);picker.add_theme_font_size_override("font_size",10);picker.fit_to_longest_item=false;selectors.add_child(picker)
		var values:Array=[-1,0,1,2] if key=="job" else ([""]+ShopRules.SLOTS if key=="slot" else ["","white","blue","yellow","orange","green"])
		for value in values:picker.add_item(("全部职业" if int(value)==-1 else Game.JOBS[int(value)]) if key=="job" else ({"":"全部部位"}.get(value,CraftingPanel.SLOTS.get(value,value)) if key=="slot" else {"":"全部品质","white":"普通","blue":"魔法","yellow":"稀有","orange":"传奇","green":"套装"}[value]))
		picker.select(values.find(model.filters[key]));picker.item_selected.connect(func(index:int)->void:model.filters[key]=values[index];model.filters.page=0;model.fetch())
func _sell()->void:
	label("托管未绑定装备，最多20件；出价后不能撤回。\n加价5%（至少1铜），无手续费。")
	sell_item=OptionButton.new();sell_item.custom_minimum_size=Vector2(250,32);sell_item.fit_to_longest_item=false;rows.add_child(sell_item)
	var items:Array=online_model.state.get("loot",{}).get("state",{}).get("items",[]).filter(func(item:Dictionary)->bool:return LootRules.tradable(item))
	for item in items:sell_item.add_item("%s · Lv.%d · %s"%[ShopRules.item(item.template).name,int(item.level),item.id.right(8)])
	if items.is_empty():label("背包没有可上架的未绑定装备。");return
	var description:=label(LootRules.describe(items[0]));sell_item.item_selected.connect(func(index:int)->void:description.text=LootRules.describe(items[index]))
	label("起拍价（铜钱）");starting=spinner(1);label("一口价（铜钱）");buyout=spinner(100)
	hours=OptionButton.new();hours.custom_minimum_size=Vector2(250,32);rows.add_child(hours)
	for h in [6,12,24]:hours.add_item("上架%d小时"%h)
	button("确认上架",rows).pressed.connect(func()->void:
		var item:Dictionary=items[sell_item.selected]
		confirm("list",{"target":item.id,"amount":int(starting.value),"buyout":int(buyout.value),"hours":[6,12,24][hours.selected]},"上架%s？\n编号%s\n起拍%d铜 · 一口价%d铜\n装备将离开背包并由拍卖行托管。"%[ShopRules.item(item.template).name,item.id.right(8),int(starting.value),int(buyout.value)])
	)
func _trade()->void:
	var trade:Variant=model.state.get("trade")
	if trade==null or trade.status not in ["pending","active"]:
		if trade!=null:label({"completed":"交易已完成，请到“领取”页取回收到的物资。","cancelled":"交易已取消，托管物资已退回“领取”页。","expired":"交易已到期，托管物资已退回“领取”页。"}.get(trade.status,""))
		label("当面交易：双方须在线、同图2格内停下。\n只可交易未绑定装备与铜钱；10分钟未完成自动退回。")
		var name:=LineEdit.new();name.placeholder_text="对方完整角色名";name.max_length=12;name.custom_minimum_size=Vector2(250,32);name.add_theme_font_size_override("font_size",11);rows.add_child(name);name.focus_entered.connect(func()->void:Platform.context.text_input.request_focus(name))
		button("邀请交易",rows).pressed.connect(func()->void:Platform.context.text_input.release_focus(name);confirm("trade_invite",{"name":name.text},"邀请%s进行当面交易？"%name.text));return
	var own:=0 if trade.sender==model.character_id else 1
	label("%s ↔ %s\n剩余%d分钟"%[trade.sender_name,trade.recipient_name,maxi(0,int(trade.expires_ms)-int(model.state.server_time_ms))/60000])
	var reference:Dictionary={"target":trade.id,"revision":int(trade.revision)}
	if trade.status=="pending":
		label("等待对方接受邀请。" if own==0 else "对方邀请你交易。接受后可放入装备或铜钱。")
		if own==1:button("接受交易",rows).pressed.connect(func()->void:confirm("trade_accept",reference,"确认与%s开始交易？"%trade.sender_name))
	else:
		for side in 2:
			var offer:Dictionary=trade.offers[side]
			label(("你的报价" if side==own else "对方报价")+" · %d铜 · "%int(offer.gold)+("已最终确认" if offer.confirmed else ("已锁定" if offer.locked else "可修改")))
			for item in offer.items:label(LootRules.describe(item))
		var mine:Dictionary=trade.offers[own]
		if draft_trade!=trade.id:draft_trade=trade.id;draft_items={};draft_gold=-1
		label("修改你的报价（最多6件，修改会清除双方锁定和确认）：")
		var items:Array=online_model.state.get("loot",{}).get("state",{}).get("items",[]).filter(func(item:Dictionary)->bool:return LootRules.tradable(item))+mine.items
		for item in items:
			var select:=CheckBox.new();select.text="%s · %s"%[ShopRules.item(item.template).name,item.id.right(8)];select.custom_minimum_size=Vector2(250,30);select.add_theme_font_size_override("font_size",11);select.button_pressed=draft_items.get(item.id,mine.items.any(func(old:Dictionary)->bool:return old.id==item.id));rows.add_child(select)
			select.add_theme_color_override("font_color",INK);select.add_theme_color_override("font_pressed_color",INK);select.tooltip_text=LootRules.describe(item)
			select.toggled.connect(func(on:bool)->void:draft_items[item.id]=on)
		label("提供铜钱（0表示不提供）：")
		var gold:=spinner(1);gold.min_value=0;gold.value=int(mine.gold) if draft_gold<0 else draft_gold;gold.value_changed.connect(func(value:float)->void:draft_gold=int(value))
		button("保存新报价",rows).pressed.connect(func()->void:
			var chosen:Array=[]
			for item in items:
				if draft_items.get(item.id,mine.items.any(func(old:Dictionary)->bool:return old.id==item.id)):chosen.append(item.id)
			var values:=reference.duplicate(true);values.items=chosen;values.amount=int(gold.value)
			confirm("trade_offer",values,"托管%d件装备及%d铜？\n这会取消双方先前的锁定和确认。"%[chosen.size(),int(gold.value)]);draft_gold=-1;draft_items={}
		)
		var lock_button:=button("锁定当前报价",rows);lock_button.disabled=mine.locked;lock_button.pressed.connect(func()->void:confirm("trade_lock",reference,"确认锁定当前报价？\n最终交换前仍需双方再次确认。"))
		var final:=button("最终确认交换",rows);final.disabled=not trade.offers.all(func(offer:Dictionary)->bool:return offer.locked) or mine.confirmed
		final.pressed.connect(func()->void:confirm("trade_confirm",reference,"已核对双方装备编号、词条和铜钱？\n你出%d铜，对方出%d铜。\n双方最终确认后交换不可撤回，物资进入“领取”页。"%[int(mine.gold),int(trade.offers[1-own].gold)]))
	button("取消交易／退回物资",rows).pressed.connect(func()->void:confirm("trade_cancel",reference,"确认取消？双方托管物资将原样退回各自“领取”页。"))
