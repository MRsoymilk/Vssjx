class_name EquipmentDetails
extends Control
## A stable item identity survives backpack sorting and authoritative refreshes.
signal back_requested
signal changed
const Paper = preload("res://scripts/equipment_paper.gd")
const Comparison = preload("res://scripts/equipment_comparison.gd")
const SLOTS := {"weapon":"武器","pendant":"腰佩","armor":"衣服","wrist":"手腕","belt":"腰带","pants":"裤子","boots":"鞋子","ring":"戒指","necklace":"项链","hat":"帽子"}
const QUALITIES := {"legacy":"固定","white":"普通","blue":"魔法","yellow":"稀有","orange":"传奇","green":"套装"}
var online_model: OnlinePve
var template_id := ""
var instance_id := ""
var item: Dictionary = {}
var pages: Array = []
var page := 0
var paper: Panel
var title: Label
var meta: Label
var score_label: Label
var score_change: Label
var requirements: Label
var scroll: ScrollContainer
var content: VBoxContainer
var previous: Button
var next: Button
var page_label: Label
var back: Button
var _bound_character := ""
var detail_view: Control
var comparison_view: Control
var compare_button: Button
var craft_button: Button
var compare_craft: Button
var equip_button: Button
var comparison_scroll: ScrollContainer
var comparison_content: VBoxContainer
var comparison_hint: Label
var current_name: Label
var selected_name: Label
var current_icon: TextureRect
var selected_icon: TextureRect
var comparison_rows: Array=[]
var comparing := false
var crafting: CraftingPanel
var busy := false
var operation_message := ""
var _pending_equip := false

func select(entry: Dictionary) -> void:
	template_id=String(entry.get("id",""));instance_id=String(entry.get("instance_id",""));page=0
	if is_node_ready():refresh()

func _ready() -> void:
	z_index=24;size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP
	theme=preload("res://scenes/ui/shop_category_theme.tres")
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.35);shade.size=size;shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	detail_view=Control.new();detail_view.size=size;detail_view.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(detail_view)
	paper=Paper.frame(detail_view,Rect2(27,99,266,308),"装备信息");title=paper.get_node("Title")
	meta=OriginalSceneChrome.label(detail_view,"",Rect2(41,131,238,16),11,Paper.INK)
	OriginalSceneChrome.panel(detail_view,Rect2(41,151,238,26),Color("f3e3a0"),Color("d3bc73"))
	OriginalSceneChrome.label(detail_view,"装备评分：",Rect2(49,154,76,20),12,Paper.INK)
	score_label=OriginalSceneChrome.label(detail_view,"—",Rect2(126,152,72,24),16,Paper.RED);score_label.name="EquipmentScore"
	score_label.tooltip_text=LootRules.SCORE_HINT;score_label.mouse_filter=Control.MOUSE_FILTER_PASS
	score_change=OriginalSceneChrome.label(detail_view,"",Rect2(198,155,73,18),10,Paper.INK);score_change.name="ScoreChange"
	score_change.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;score_change.mouse_filter=Control.MOUSE_FILTER_PASS
	scroll=ScrollContainer.new();scroll.position=Vector2(41,185);scroll.size=Vector2(238,144)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;detail_view.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",5);scroll.add_child(content)
	requirements=OriginalSceneChrome.label(detail_view,"",Rect2(41,331,238,24),10,Paper.INK)
	requirements.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	previous=OriginalSceneChrome.button(detail_view,"◀",Rect2(113,359,27,20),12)
	next=OriginalSceneChrome.button(detail_view,"▶",Rect2(181,359,27,20),12)
	for button in [previous,next]:
		button.add_theme_color_override("font_color",Paper.INK);button.add_theme_color_override("font_disabled_color",Color("b9a66b"))
		button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
	previous.pressed.connect(_turn_page.bind(-1));next.pressed.connect(_turn_page.bind(1))
	page_label=OriginalSceneChrome.label(detail_view,"",Rect2(140,359,41,20),11,Paper.INK);page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	compare_button=Paper.button(detail_view,"装备对比",Rect2(39,382,77,23));compare_button.name="Compare";compare_button.pressed.connect(show_comparison)
	craft_button=Paper.button(detail_view,"前往洗练",Rect2(122,382,77,23));craft_button.name="Crafting";craft_button.pressed.connect(open_crafting)
	back=Paper.button(detail_view,"返回",Rect2(205,382,75,23));back.name="Back";back.pressed.connect(func()->void:back_requested.emit())
	_build_comparison()
	if online_model!=null:
		_bound_character=online_model.character_id
		online_model.changed.connect(_online_changed)
	refresh()

func _character() -> Dictionary:
	return Game.player if online_model==null else online_model.state.get("character",{})

func _loot() -> Dictionary:
	return Game.player.get("loot_state",{}) if online_model==null else online_model.state.get("loot",{}).get("state",{})

func _gear() -> Dictionary:
	if online_model==null:return ShopRules.local_state(Game.player)
	return online_model.state.get("shop",{"weapon":online_model.state.get("equipment",{}).get("weapon"),"owned":["sword"] if online_model.state.get("equipment",{}).get("weapon_owned",false) else []})

func _resolve() -> Dictionary:
	if online_model!=null and online_model.character_id!=_bound_character:return {}
	if not instance_id.is_empty():
		for value in _loot().get("items",[]):
			if value.id==instance_id:return LootRules.bag_item(value)
		return {}
	return ShopRules.bag_item(template_id,int(_character().get("job",0))) if _gear().get("owned",[]).has(template_id) else {}

func _worn(entry: Dictionary) -> bool:
	if entry.is_empty():return false
	return entry.instance.equipped if entry.has("instance_id") else ShopRules.equipped_id(_gear(),entry.slot)==entry.id

func _base(entry: Dictionary) -> Array:
	return LootRules.base(entry.instance) if entry.has("instance_id") else [int(entry.get("attack",0)),int(entry.get("defense",0)),0,0]

func _attack_name() -> String:
	return "法术攻击" if int(_character().get("job",0))==2 else "物理攻击"

func _make_pages(entry: Dictionary) -> Array:
	var rows: Array=[]
	var instance: Dictionary=entry.get("instance",{})
	if not instance.is_empty() and not instance.legacy:rows.append({"label":"强化：","text":"%d / 6"%int(instance.upgrade)})
	var base:=_base(entry);var names:=[_attack_name(),"双防","气血","灵力"]
	for i in base.size():
		if int(base[i])>0:rows.append({"label":"基础属性：","text":"%s +%d"%[names[i],int(base[i])]})
	for i in instance.get("affixes",[]).size():rows.append({"label":"追加%d："%[i+1],"text":LootRules.affix_text(instance.affixes[i])})
	if instance.get("affixes",[]).is_empty():rows.append({"label":"","text":"固定属性，无随机词条。" if instance.get("legacy",true) else "普通装备，无随机词条。","note":true})
	var result: Array=[]
	for i in range(0,rows.size(),7):result.append(rows.slice(i,i+7))
	if not instance.is_empty() and not instance.legacy:
		var extra: Array=[]
		if instance.get("legendary")!=null or instance.get("set_id")!=null:
			var legend: bool=instance.get("legendary")!=null
			var build:Dictionary=BuildRules.rules.items[BuildRules.index(instance.legendary if legend else instance.set_id)]
			extra.append({"label":"传奇：" if legend else "套装：","text":build.legend_name if legend else build.name})
			if not legend:extra.append({"label":"2件：","text":BuildRules.two_text(build)})
			extra.append({"label":"特效：" if legend else "4件：","text":build.description})
		extra.append({"label":"洗练：","text":"%d / %d"%[int(instance.get("rerolls",0)),int(ProgressionRules.rules.max_rerolls)]})
		extra.append({"label":"","text":"已锁定第%d条，仅此词条可洗练。"%[int(instance.reroll_index)+1] if instance.get("reroll_index")!=null else "首次洗练后锁定所选词条。","note":true})
		result.append(extra)
	return result

func refresh() -> void:
	if not is_node_ready():return
	item=_resolve();pages=[]
	score_label.text="—";score_change.text="";score_change.tooltip_text=""
	if item.is_empty():
		title.text="装备详情";meta.text="该装备已不在背包中";requirements.text="返回背包选择其他装备。"
		pages=[[{"label":"","text":"装备可能已分解、丢弃或转移。","note":true}]]
	else:
		title.text=item.name;title.tooltip_text=item.name
		var quality:String=item.get("instance",{}).get("quality","legacy")
		meta.text="%s · %s · %s"%[SLOTS[item.slot],QUALITIES[quality],"已穿戴" if _worn(item) else "未装备"]
		if item.has("instance_id"):meta.text+=" · 已绑" if item.instance.get("bound",true) else " · 未绑"
		if online_model!=null and not online_model.ready:meta.text+=" · 离线快照"
		var rating:=LootRules.entry_score(item);score_label.text=str(rating)
		var current:=_current_item();var delta:=rating-LootRules.entry_score(current)
		score_change.text="已穿戴" if _worn(item) else "空槽" if current.is_empty() else ("↑ +%d"%delta if delta>0 else "↓ %d"%delta if delta<0 else "持平")
		score_change.add_theme_color_override("font_color",Paper.GREEN if delta>0 else Paper.RED if delta<0 else Paper.INK)
		score_change.tooltip_text="与当前同部位装备比较。\n"+LootRules.SCORE_HINT
		var limits:Array[String]=["等级%d"%int(item.get("level",1))]
		if int(item.get("job",-1))>=0:limits.append(Game.JOBS[int(item.job)])
		if int(item.get("gender",-1))>=0:limits.append("男" if int(item.gender)==0 else "女")
		requirements.text="装备需求："+" · ".join(limits)
		pages=_make_pages(item)
	page=clampi(page,0,maxi(0,pages.size()-1));_show_page()
	compare_button.disabled=item.is_empty()
	var craft_error:=_craft_error()
	for button in [craft_button,compare_craft]:button.disabled=not craft_error.is_empty();button.tooltip_text=craft_error
	_refresh_comparison()
	detail_view.visible=not comparing and not is_instance_valid(crafting)
	comparison_view.visible=comparing and not is_instance_valid(crafting)

func _show_page() -> void:
	for child in content.get_children():content.remove_child(child);child.queue_free()
	for row in pages[page]:
		var label:=RichTextLabel.new();label.fit_content=true;label.scroll_active=false
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.custom_minimum_size=Vector2(222,16)
		label.add_theme_font_size_override("normal_font_size",12)
		content.add_child(label)
		label.push_color(Paper.INK);label.add_text(row.label);label.pop()
		label.push_color(Paper.INK if row.get("note",false) else Paper.GREEN);label.add_text(row.text);label.pop()
	scroll.scroll_vertical=0
	page_label.text="%d / %d"%[page+1,pages.size()]
	previous.disabled=page==0;next.disabled=page+1>=pages.size()

func _turn_page(step: int) -> void:
	page=clampi(page+step,0,pages.size()-1);_show_page()

func _build_comparison() -> void:
	comparison_view=Control.new();comparison_view.size=size;comparison_view.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(comparison_view)
	Paper.frame(comparison_view,Rect2(18,102,284,296),"装 备 对 比")
	var caption:=OriginalSceneChrome.label(comparison_view,"对比当前已穿戴的同部位装备",Rect2(32,134,256,17),10,Paper.INK);caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	for i in 2:
		var x:=32+i*127
		OriginalSceneChrome.panel(comparison_view,Rect2(x,155,121,42),Color("efe8ae" if i==0 else "fff3be"),Color("d4b86a"))
		var icon:=TextureRect.new();icon.position=Vector2(x+5,166);icon.size=Vector2(20,20)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;comparison_view.add_child(icon)
		OriginalSceneChrome.label(comparison_view,"当前穿戴" if i==0 else "背包选中",Rect2(x+30,157,87,14),9,Paper.INK)
		var label:=OriginalSceneChrome.label(comparison_view,"",Rect2(x+30,172,87,20),11,Paper.INK)
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;label.clip_text=true;label.mouse_filter=Control.MOUSE_FILTER_PASS
		if i==0:current_name=label;current_icon=icon
		else:selected_name=label;selected_icon=icon
	OriginalSceneChrome.label(comparison_view,"属性",Rect2(37,204,90,17),11,Paper.INK)
	OriginalSceneChrome.label(comparison_view,"当前",Rect2(147,204,35,17),11,Paper.INK)
	OriginalSceneChrome.label(comparison_view,"选中",Rect2(222,204,35,17),11,Paper.INK)
	comparison_scroll=ScrollContainer.new();comparison_scroll.position=Vector2(32,225);comparison_scroll.size=Vector2(256,109)
	comparison_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;comparison_view.add_child(comparison_scroll)
	comparison_content=VBoxContainer.new();comparison_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	comparison_content.add_theme_constant_override("separation",1);comparison_scroll.add_child(comparison_content)
	comparison_hint=OriginalSceneChrome.label(comparison_view,"",Rect2(32,339,256,24),10,Paper.INK);comparison_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	equip_button=Paper.button(comparison_view,"装备此件",Rect2(32,365,81,23));equip_button.name="Equip";equip_button.pressed.connect(equip_selected)
	compare_craft=Paper.button(comparison_view,"前往洗练",Rect2(119,365,81,23));compare_craft.pressed.connect(open_crafting)
	Paper.button(comparison_view,"返回详情",Rect2(206,365,81,23)).pressed.connect(show_details)

func _current_item() -> Dictionary:
	if item.is_empty():return {}
	var worn:=LootRules.equipped(_loot(),item.slot)
	if not worn.is_empty() and not worn.legacy:return LootRules.bag_item(worn)
	var id:Variant=ShopRules.equipped_id(_gear(),item.slot)
	return {} if id==null else ShopRules.bag_item(id,int(_character().get("job",0)))

func _refresh_comparison() -> void:
	var current:=_current_item()
	current_name.text=current.get("name","未穿戴");selected_name.text=item.get("name","装备已移除")
	for label in [current_name,selected_name]:label.tooltip_text=label.text
	current_icon.texture=null if current.is_empty() else load(current.icon)
	selected_icon.texture=null if item.is_empty() else load(item.icon)
	for child in comparison_content.get_children():comparison_content.remove_child(child);child.queue_free()
	comparison_rows=[] if item.is_empty() else Comparison.rows(current,item,int(_character().get("job",0)))
	for row in comparison_rows:
		var line:=Control.new();line.custom_minimum_size=Vector2(246,20);comparison_content.add_child(line)
		if comparison_content.get_child_count()%2:OriginalSceneChrome.panel(line,Rect2(0,0,246,20),Color("f3ecaf"),Color("f3ecaf"))
		OriginalSceneChrome.label(line,row.label,Rect2(5,1,92,18),11,Paper.INK)
		var left:=OriginalSceneChrome.label(line,Comparison.format_value(row.kind,row.current),Rect2(98,1,54,18),11,Paper.INK);left.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		var color:Color=Paper.GREEN if row.delta>0 else Paper.RED if row.delta<0 else Paper.INK
		var right:=OriginalSceneChrome.label(line,Comparison.format_value(row.kind,row.selected),Rect2(160,1,68,18),11,color);right.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		OriginalSceneChrome.label(line,"↑" if row.delta>0 else "↓" if row.delta<0 else "—",Rect2(230,1,16,18),11,color)
		line.tooltip_text=row.label+"："+row.change;line.mouse_filter=Control.MOUSE_FILTER_PASS
	var specials:=[Comparison.special(current),Comparison.special(item)]
	for i in 2:
		if specials[i].is_empty():continue
		var label:=OriginalSceneChrome.label(comparison_content,("当前特效：" if i==0 else "选中特效：")+specials[i],Rect2(0,0,246,20),11,Paper.INK)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.custom_minimum_size.x=246;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var error:=_equip_error()
	equip_button.disabled=not error.is_empty();equip_button.tooltip_text=error
	equip_button.text="已穿戴" if _worn(item) else "装备此件"
	comparison_hint.text=operation_message if not operation_message.is_empty() else ("装备已移除，请返回背包。" if item.is_empty() else "评分供同部位参考，绿升红降。特效另列。")

func show_comparison() -> void:
	if _resolve().is_empty():refresh();return
	comparing=true;operation_message="";comparison_scroll.scroll_vertical=0;refresh()

func show_details() -> void:
	comparing=false;operation_message="";refresh()

func _lock_reason() -> String:
	if busy:return "正在保存装备……"
	if online_model!=null:
		if not online_model.ready:return "连接中断，等待装备同步。"
		if online_model.pending():return "正在等待服务器确认……"
		if online_model.active():return OnlinePve.error_text("BATTLE_ACTIVE")
	else:
		if Game.storage_busy:return "正在保存，请稍候。"
		if Game.local_battle_active():return OnlinePve.error_text("BATTLE_ACTIVE")
	if _character().get("corpse") is Dictionary:return OnlinePve.error_text("SOUL_STATE")
	return ""

func _equip_error() -> String:
	var locked:=_lock_reason()
	if not locked.is_empty():return locked
	if item.is_empty():return "该装备已不在背包中。"
	if _worn(item):return "此件装备已穿戴。"
	var restriction:=LootRules.equip_error(item.instance,int(_character().get("job",0)),int(_character().get("gender",0))) if item.has("instance") else ShopRules.equipment_error(item,int(_character().get("job",0)),int(_character().get("gender",0)))
	if not restriction.is_empty():return OnlinePve.error_text(restriction)
	if item.has("instance_id") and int(item.level)>int(_character().get("level",1)):return OnlinePve.error_text("EQUIPMENT_LEVEL_REQUIRED")
	return ""

func _craft_error() -> String:
	var locked:=_lock_reason()
	if not locked.is_empty():return locked
	if item.is_empty():return "该装备已不在背包中。"
	if not item.has("instance_id") or item.instance.legacy:return OnlinePve.error_text("LEGACY_CRAFT_LOCKED")
	if online_model!=null and online_model.state.get("loot",{}).get("progression_sha256")!=ProgressionRules.catalog_hash:return "养成配置尚未同步。"
	var quote:=ProgressionRules.quote(item.instance,"gear_reroll")
	return OnlinePve.error_text(quote.error) if quote.has("error") else ""

func equip_selected() -> void:
	item=_resolve()
	var error:=_equip_error()
	if not error.is_empty():operation_message=error;refresh();return
	var action:="gear_equip" if item.has("instance_id") else "equip"
	var id:String=item.get("instance_id",item.id)
	if online_model!=null:
		_pending_equip=true
		if not online_model.submit(action,id):_pending_equip=false;operation_message="暂时不能装备，请等待同步。"
		refresh();return
	busy=true;operation_message="正在保存装备……";refresh()
	var result:PlatformResult=await Game.loot_command(action,id) if item.has("instance_id") else await Game.shop_command(action,id)
	if not is_inside_tree():return
	busy=false;operation_message="装备已保存。" if result.ok else result.message;refresh();changed.emit()

func _online_changed() -> void:
	if _pending_equip:
		operation_message="正在等待服务器确认……" if online_model.pending() else ("装备已更新。" if online_model.last_code.is_empty() else OnlinePve.error_text(online_model.last_code))
		if not online_model.pending():_pending_equip=false
	refresh()

func open_crafting() -> void:
	if is_instance_valid(crafting):return
	item=_resolve()
	var error:=_craft_error()
	if not error.is_empty():operation_message=error;refresh();return
	crafting=load("res://scripts/crafting_panel.gd").new();crafting.name="CraftingPanel"
	crafting.online_model=online_model;crafting.selected_id=instance_id;crafting.from_details=true
	add_child(crafting);set_process_unhandled_key_input(false)
	crafting.changed.connect(func()->void:refresh();changed.emit())
	crafting.back_requested.connect(_close_crafting)
	refresh()

func _close_crafting() -> void:
	remove_child(crafting);crafting.queue_free();crafting=null
	set_process_unhandled_key_input(true);show_details();changed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_instance_valid(crafting) or not event is InputEventKey or not event.pressed or event.echo:return
	var input_viewport:=get_viewport()
	if event.keycode==KEY_ESCAPE:
		if comparing:show_details()
		else:back_requested.emit()
	elif not comparing and event.keycode==KEY_LEFT:_turn_page(-1)
	elif not comparing and event.keycode==KEY_RIGHT:_turn_page(1)
	else:return
	input_viewport.set_input_as_handled()
