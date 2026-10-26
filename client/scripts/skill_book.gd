class_name SkillBook
extends Control
## Native eba0..ed16: compact name/rank list above a separate description.
var items:Array=[]
var level:=1
var balanced:=false
var selected_index:=0
var proficiency:Dictionary={}
@onready var rows:VBoxContainer=$SkillCatalog/Rows
@onready var detail:Label=$Description

func present(player:Dictionary,martial:bool)->void:
	level=int(player.level)
	proficiency=player.get("skill_proficiency",{}).duplicate(true)
	balanced=player.get("balance_revision",0)==1
	items=SkillRules.list_for(int(player.job),int(player.school),level,true).filter(func(s:Dictionary)->bool:return bool(s.active)==martial)
	var unlocked:=items.filter(func(skill:Dictionary)->bool:return level>=int(skill.unlock_level)).size()
	$Provenance.text="%d级 · 已解锁%d项 · 门派不限"%[level,unlocked]
	$Coverage.hide()
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	for index in items.size():
		var skill:Dictionary=items[index]
		var row:=Button.new();row.custom_minimum_size=Vector2(0,28);row.alignment=HORIZONTAL_ALIGNMENT_LEFT;row.clip_text=true
		for state in ["normal","hover","pressed","focus"]:row.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var name_label:=Label.new();name_label.name="Name";name_label.text=skill.name;name_label.position=Vector2(6,3);name_label.size=Vector2(190,22);name_label.add_theme_font_size_override("font_size",14);name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(name_label)
		var rank:=Label.new();rank.name="Rank";rank.text=("%d/15"%SkillProficiency.level(proficiency,skill.id)) if skill.active and level>=int(skill.unlock_level) else "—/—";rank.position=Vector2(211,3);rank.size=Vector2(61,22);rank.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;rank.add_theme_font_size_override("font_size",13);rank.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(rank)
		rows.add_child(row);row.pressed.connect(select_skill.bind(index))
	$Label0.visible=items.is_empty()
	if not items.is_empty():
		var first_unlocked:=items.find_custom(func(s:Dictionary)->bool:return level>=int(s.unlock_level))
		select_skill(maxi(0,first_unlocked))
	else:detail.text="";$SkillName.text=""

func select_skill(index:int)->void:
	if items.is_empty():return
	selected_index=clampi(index,0,items.size()-1)
	var skill:Dictionary=items[selected_index]
	$SkillName.text=skill.name
	detail.text=SkillRules.description(skill,balanced)
	if skill.active and level>=int(skill.unlock_level):
		var rank:=SkillProficiency.level(proficiency,skill.id)
		detail.text+=" · 技能%d级 · %s"%[rank,"基础特效" if rank<6 or not BattleEffects.binding(skill.id).has("stages") else "%d阶段特效"%SkillProficiency.stage(rank)]
		detail.text+="\n熟练度已满" if rank==15 else "\n熟练度%d/20 · 施放升级"%(int(proficiency.get(skill.id,0))%20)
	if balanced and skill.active:
		if SkillBalance.kind(skill)=="dot":detail.text+=" · 首击80%＋每轮30%，共3次"
		elif skill.target=="all_enemies":detail.text+=" · 群攻总倍率最多240%"
		elif SkillBalance.kind(skill)=="control":detail.text+=" · 65%概率控制1轮，之后保护2轮"
		elif int(skill.damage_percent)>0:detail.text+=" · 威力160%"
	if balanced and skill.active:detail.text+="\n消耗最大灵力%d%% · 冷却%d轮"%[int(SkillBalance.rules.cost_bp[SkillBalance.kind(skill)])/100,SkillBalance.cooldown(skill)]
	elif int(skill.mp_cost)>0:detail.text+="\n（消耗灵力%d）"%int(skill.mp_cost)
	detail.text+="\n%d级解锁"%int(skill.unlock_level) if level<int(skill.unlock_level) else ("\n已生效" if not skill.active else "\n已解锁 · %d级可用"%int(skill.unlock_level))
	for i in rows.get_child_count():
		var row:Button=rows.get_child(i)
		var selected:=i==selected_index
		var bg:=StyleBoxFlat.new();bg.bg_color=Color("a33d2f") if selected else Color.TRANSPARENT
		for state in ["normal","hover","pressed","focus","disabled"]:row.add_theme_stylebox_override(state,bg)
		var locked:bool=level<int(items[i].unlock_level)
		var color:Color=(Color("e5c59d") if selected else Color("79674b")) if locked else (Color("fff10d") if selected else Color("402718"))
		for child in row.get_children():child.add_theme_color_override("font_color",color)
	_reveal_selected.call_deferred()

func _reveal_selected()->void:
	# Newly populated rows need container layout before their final positions exist.
	if not is_inside_tree():return
	var scene_tree:=get_tree()
	await scene_tree.process_frame
	if not is_inside_tree():return
	await scene_tree.process_frame
	if not is_inside_tree() or rows.get_child_count()==0:return
	$SkillCatalog.ensure_control_visible(rows.get_child(selected_index))

func _unhandled_key_input(event:InputEvent)->void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:return
	if event.keycode in [KEY_UP,KEY_DOWN]:
		select_skill(selected_index+(-1 if event.keycode==KEY_UP else 1))
		get_viewport().set_input_as_handled()
