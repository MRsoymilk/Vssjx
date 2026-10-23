class_name EquipmentDetails
extends Control
## A stable item identity survives backpack sorting and authoritative refreshes.
signal back_requested
const Paper = preload("res://scripts/equipment_paper.gd")
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
var requirements: Label
var scroll: ScrollContainer
var content: VBoxContainer
var previous: Button
var next: Button
var page_label: Label
var back: Button
var _bound_character := ""

func select(entry: Dictionary) -> void:
	template_id=String(entry.get("id",""));instance_id=String(entry.get("instance_id",""));page=0
	if is_node_ready():refresh()

func _ready() -> void:
	z_index=24;size=Vector2(320,480);mouse_filter=Control.MOUSE_FILTER_STOP
	theme=preload("res://scenes/ui/shop_category_theme.tres")
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.35);shade.size=size;shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	paper=Paper.frame(self,Rect2(27,119,266,261),"装备详情");title=paper.get_node("Title")
	meta=OriginalSceneChrome.label(self,"",Rect2(41,151,238,16),11,Paper.INK)
	OriginalSceneChrome.panel(self,Rect2(41,168,238,1),Color("d3bc73"),Color("d3bc73"))
	scroll=ScrollContainer.new();scroll.position=Vector2(41,175);scroll.size=Vector2(238,122)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",5);scroll.add_child(content)
	requirements=OriginalSceneChrome.label(self,"",Rect2(41,304,238,24),10,Paper.INK)
	requirements.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	previous=OriginalSceneChrome.button(self,"◀",Rect2(113,328,27,20),12)
	next=OriginalSceneChrome.button(self,"▶",Rect2(181,328,27,20),12)
	for button in [previous,next]:
		button.add_theme_color_override("font_color",Paper.INK);button.add_theme_color_override("font_disabled_color",Color("b9a66b"))
		button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
	previous.pressed.connect(_turn_page.bind(-1));next.pressed.connect(_turn_page.bind(1))
	page_label=OriginalSceneChrome.label(self,"",Rect2(140,328,41,20),11,Paper.INK);page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	back=Paper.button(self,"返回",Rect2(204,349,76,23));back.name="Back";back.pressed.connect(func()->void:back_requested.emit())
	if online_model!=null:
		_bound_character=online_model.character_id
		online_model.changed.connect(refresh)
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
		if int(base[i])>0:rows.append({"label":"基础：","text":"%s +%d"%[names[i],int(base[i])]})
	for i in instance.get("affixes",[]).size():rows.append({"label":"附加%d："%[i+1],"text":LootRules.affix_text(instance.affixes[i])})
	if instance.get("affixes",[]).is_empty():rows.append({"label":"","text":"固定属性，无随机词条。" if instance.get("legacy",true) else "普通装备，无随机词条。","note":true})
	var result: Array=[]
	for i in range(0,rows.size(),6):result.append(rows.slice(i,i+6))
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
	if item.is_empty():
		title.text="装备详情";meta.text="该装备已不在背包中";requirements.text="返回背包选择其他装备。"
		pages=[[{"label":"","text":"装备可能已分解、丢弃或转移。","note":true}]]
	else:
		title.text=item.name;title.tooltip_text=item.name
		var quality:String=item.get("instance",{}).get("quality","legacy")
		meta.text="%s · %s · %s"%[SLOTS[item.slot],QUALITIES[quality],"已穿戴" if _worn(item) else "未装备"]
		if online_model!=null and not online_model.ready:meta.text+=" · 离线快照"
		var limits:Array[String]=["等级%d"%int(item.get("level",1))]
		if int(item.get("job",-1))>=0:limits.append(Game.JOBS[int(item.job)])
		if int(item.get("gender",-1))>=0:limits.append("男" if int(item.gender)==0 else "女")
		requirements.text="装备需求："+" · ".join(limits)
		pages=_make_pages(item)
	page=clampi(page,0,maxi(0,pages.size()-1));_show_page()

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

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
	var input_viewport:=get_viewport()
	if event.keycode==KEY_ESCAPE:back_requested.emit()
	elif event.keycode==KEY_LEFT:_turn_page(-1)
	elif event.keycode==KEY_RIGHT:_turn_page(1)
	else:return
	input_viewport.set_input_as_handled()
