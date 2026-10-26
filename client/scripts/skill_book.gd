class_name SkillBook
extends Control
## Native skill list with separate effect, availability and training sections.
var items:Array=[]
var level:=1
var balanced:=false
var selected_index:=0
var proficiency:Dictionary={}
@onready var rows:VBoxContainer=$SkillCatalog/Rows
@onready var detail:Label=$DescriptionScroll/Description

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
		var name_label:=Label.new();name_label.name="Name";name_label.text=skill.name;name_label.position=Vector2(6,3);name_label.size=Vector2(178,22);name_label.add_theme_font_size_override("font_size",14);name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(name_label)
		var rank:=Label.new();rank.name="Rank";rank.text=("%d/15"%SkillProficiency.level(proficiency,skill.id) if skill.active else "被动") if level>=int(skill.unlock_level) else "%d级解锁"%int(skill.unlock_level);rank.position=Vector2(190,3);rank.size=Vector2(82,22);rank.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;rank.add_theme_font_size_override("font_size",13 if skill.active and level>=int(skill.unlock_level) else 11);rank.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(rank)
		rows.add_child(row);row.pressed.connect(select_skill.bind(index))
	$Label0.visible=items.is_empty()
	$Label0.text="暂无可用武功" if martial else "此职业暂无心法"
	if not items.is_empty():
		var first_unlocked:=items.find_custom(func(s:Dictionary)->bool:return level>=int(s.unlock_level))
		select_skill(maxi(0,first_unlocked))
	else:
		for label in [detail,$SkillName,$SkillRank,$Availability,$CombatMeta,$Training]:label.text=""
		$TrainingProgress.hide();$GrowthHint.text="此职业暂无心法" if not martial else "暂无可用武功"

func select_skill(index:int)->void:
	if items.is_empty():return
	selected_index=clampi(index,0,items.size()-1)
	var skill:Dictionary=items[selected_index]
	$SkillName.text=skill.name
	var unlocked:=level>=int(skill.unlock_level)
	var rank:=SkillProficiency.level(proficiency,skill.id)
	var stage_text:="基础特效" if rank<6 or not BattleEffects.binding(skill.id).has("stages") else "%d阶段特效"%SkillProficiency.stage(rank)
	$SkillRank.text=("技能%d/15"%rank if skill.active else "被动") if unlocked else "未解锁"
	$Availability.text=("已解锁 · 角色%d级可用 · %s"%[int(skill.unlock_level),stage_text] if skill.active else "已生效 · 角色%d级可用"%int(skill.unlock_level)) if unlocked else "角色%d级解锁 · 当前%d级"%[int(skill.unlock_level),level]
	$DescriptionScroll.scroll_vertical=0
	detail.text=SkillRules.description(skill,balanced)
	if String(skill.id).begins_with("legacy_"):
		detail.text="单体攻击"+("，恢复%d点气血"%int(skill.legacy_heal) if int(skill.legacy_heal)>0 else "")
	if not skill.active and skill.effect in ["reflect_physical","reflect_magic"]:
		detail.text="%s反伤：自动反弹自身攻击力的%d%%伤害。"%["物理" if skill.effect=="reflect_physical" else "法术",int(skill.value)]
	if balanced and skill.active:
		if SkillBalance.kind(skill)=="dot":detail.text+=" · 首击80%＋每轮30%，共3次"
		elif skill.target=="all_enemies":detail.text+=" · 群攻总倍率最多240%"
		elif SkillBalance.kind(skill)=="control":detail.text+=" · 65%概率控制1轮，之后保护2轮"
		elif int(skill.damage_percent)>0:detail.text+=" · 威力160%"
	$CombatMeta.text=("消耗灵力%d点 · 冷却%d轮"%[SkillBalance.cost(skill,{}),SkillBalance.cooldown(skill)] if balanced else "消耗灵力%d点"%SkillBalance.cost(skill,{})) if skill.active else "自动生效 · 不消耗灵力"
	$TrainingProgress.visible=skill.active and unlocked
	if not unlocked:
		$Training.text="解锁后施放技能可提升熟练度" if skill.active else "达到等级后自动生效"
		$GrowthHint.text="达到角色等级后自动解锁"
	elif not skill.active:
		$Training.text="被动心法，无需主动施放";$GrowthHint.text="心法解锁后自动生效"
	else:
		var per_level:=int(SkillProficiency.rules.casts_per_level)
		var progress:=int(proficiency.get(skill.id,0))%per_level
		$TrainingProgress.max_value=per_level
		$TrainingProgress.value=per_level if rank==15 else progress
		$Training.text="熟练度已满 · 已达15级" if rank==15 else "熟练度 %d/%d · 再施放%d次升级"%[progress,per_level,per_level-progress]
		$GrowthHint.text="已达技能最高等级" if rank==15 else "每%d次有效施放，技能自动升1级"%per_level
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
