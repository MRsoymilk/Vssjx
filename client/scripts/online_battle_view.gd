class_name OnlineBattleView
extends Control
## Reference battle HUD; all outcomes and inventory come from OnlinePve.
signal action_requested(action: String)
signal skill_requested(id:String)
signal dismissed
signal settings_requested
var model: OnlinePve
var hero: AnimatedSprite2D
var enemy: AnimatedSprite2D
var battle_id := ""
var revision := ""
var animation_time := 0.0
var _previous_enemy_hp := -1
var _enemy_attack_delay := 0.0
var _hero_motion: BattleActionPlayback
var _enemy_motion: BattleActionPlayback
var _hero_death: BattleDeathPlayback
var _enemy_death: BattleDeathPlayback
var _hero_key := ""
var _shown_hero_hp := 0
var _shown_enemy_hp := 0
var _enemy_took_damage := false
var countdown := 30.0
var automatic := false
var auto_time := 0.0
var selected_enemy := false
var choice_action := ""
var buttons: Array[Button] = []
var skill_picker:SkillPicker
var move_callout:BattleMoveCallout
var effects:BattleEffects
@onready var _hero_level_home: Vector2 = $Hud/Level.position
@onready var _enemy_level_home: Vector2 = $EnemyLevel.position
const ACTIONS := ["attack", "skill", "guard", "potion", "inspect", "flee"]

func _ready() -> void:
	effects=BattleEffects.new();$Hud/EffectsLayer.add_child(effects)
	skill_picker=SkillPicker.new();add_child(skill_picker);skill_picker.position.y=-28;skill_picker.hide()
	skill_picker.dismissed.connect(_open_menu)
	skill_picker.chosen.connect(func(id:String)->void:
		if model==null or not model.ready or model.pending() or animation_time>0:return
		skill_picker.hide();$Hud/ActionMenu.hide()
		if model.state.has("skills"):skill_requested.emit(id)
		else:action_requested.emit("skill")
	)
	move_callout=preload("res://scenes/ui/battle_move_callout.tscn").instantiate();add_child(move_callout)
	for index in 6:
		var button: Button = get_node("Hud/ActionMenu/BattleButtons%d" % index)
		buttons.append(button)
		button.pressed.connect(choose.bind(ACTIONS[index]))
		button.mouse_entered.connect(_highlight.bind(index))
	$Hud/HeroHit.pressed.connect(func() -> void: selected_enemy = false; _open_menu())
	$Hud/EnemyHit.pressed.connect(func() -> void: selected_enemy = true; _open_menu())
	$Hud/AutoButton.pressed.connect(toggle_auto)
	$Choice/Use.pressed.connect(func() -> void: _send(choice_action))
	$Choice/Cancel.pressed.connect(_open_menu)
	$Inspect/Close.pressed.connect(_open_menu)
	$Result/Return.pressed.connect(return_to_map)
	$Result.manual_clock = true
	$Result.finished.connect(return_to_map)
	_highlight(0)

func _highlight(index: int) -> void:
	$Hud/ActionMenu/Cursor.position.y = 13.0 + index * 31.0
	for i in buttons.size():
		buttons[i].add_theme_stylebox_override("normal", buttons[i].get_theme_stylebox("hover") if i == index else StyleBoxEmpty.new())

func present(pve: OnlinePve) -> void:
	model = pve
	if not model.state.get("battle") is Dictionary: return
	var b: Dictionary = model.state.battle
	var c: Dictionary = model.state.character
	if battle_id != b.id:
		_cancel_motion()
		battle_id = b.id
		revision = ""
		_previous_enemy_hp = -1
		_enemy_attack_delay = 0.0
		animation_time = 0.0
		_shown_hero_hp = int(b.hp)
		_shown_enemy_hp = int(b.enemy_hp)
		automatic = false
		countdown = 30.0
		$Choice.hide()
		skill_picker.hide()
		$Inspect.hide()
		$Result.reset()
		$Hud/ActionMenu.show()
		if hero != null: hero.queue_free()
		if enemy != null: enemy.queue_free()
		var key: String = (["mzs", "mck", "mfs"] if int(c.gender) == 0 else ["wzs", "wck", "wfs"])[int(c.job)]
		_hero_key = ShopRules.actor_key(int(c.job),int(c.gender),ShopRules.appearance(model.state.shop)) if model.state.has("shop") else "hero/" + key
		hero = OriginalArt.battle_actor(_hero_key)
		$Hero.add_child(hero)
		enemy = OriginalArt.battle_actor(b.enemy.art)
		enemy.scale.x = -1
		$Enemy.add_child(enemy)
		_highlight(0)
	if revision != b.revision:
		countdown = 30.0
		auto_time = 0.0
		if not revision.is_empty() and model.last_code.is_empty():
			_cancel_motion()
			_enemy_took_damage = _previous_enemy_hp > int(b.enemy_hp)
			if int(b.get("skill_rules_version",0))==1:_enemy_took_damage=int(b.skills.last_damage)>0
			if model.last_action in ["attack", "skill"]:
				var used_id:String=b.get("skills",{}).get("last_skill","")
				var used:=SkillRules.item(used_id)
				var support:=not used.is_empty() and int(used.damage_percent)==0
				var animation:StringName=&"cast" if model.last_action=="skill" and hero.sprite_frames.has_animation("cast") else &"attack"
				if support:animation=&"cast" if hero.sprite_frames.has_animation("cast") else &"idle"
				_hero_motion = BattleActionPlayback.new()
				_hero_motion.impact.connect(_hero_impact)
				_hero_motion.completed.connect(func() -> void:
					if not _hero_motion.cancelled: _start_enemy_motion()
				)
				_hero_motion.start(hero, OriginalArt.actor_info(_hero_key), hero.global_position if support else enemy.global_position, animation, hero if support else enemy)
				move_callout.present_for(ShushanBattle.action_name(model.last_action,int(c.job),used_id),hero,_hero_motion.duration)
				_enemy_attack_delay = _hero_motion.duration if _should_enemy_act() else 0.0
				animation_time = _hero_motion.duration + (_action_duration(enemy, &"attack") if _should_enemy_act() else 0.0)
			elif _should_enemy_act():
				_start_enemy_motion()
			$Hud/ActionMenu.hide()
	revision = b.revision
	if animation_time <= 0: _start_death()
	_previous_enemy_hp = int(b.enemy_hp)
	if model.ready and not model.pending() and not model.last_code.is_empty() and model.active(): _open_menu()
	$Hud/Level.text = str(int(c.level))
	$EnemyLevel.text = str(int(b.enemy.level))
	$Hud/BattleHeroHp.max_value = model.state.stats.hp
	$Hud/BattleHeroHp.value = _shown_hero_hp
	$Hud/BattleHeroMp.max_value = model.state.stats.mp
	$Hud/BattleHeroMp.value = c.mp
	$Hud/BattleEnemyHp.max_value = b.enemy.hp
	$Hud/BattleEnemyHp.value = _shown_enemy_hp
	$Hud/BattleHeroHp.tooltip_text = "%s  气血 %d/%d" % [c.display_name, int(c.hp), int(model.state.stats.hp)]
	$Hud/BattleEnemyHp.tooltip_text = "%s  气血 %d/%d" % [b.enemy.name, int(b.enemy_hp), int(b.enemy.hp)]
	show()
	refresh()

func _cancel_motion() -> void:
	if is_instance_valid(effects):effects.clear()
	if is_instance_valid(move_callout):move_callout.clear()
	if _hero_death != null: _hero_death.cancel()
	_hero_death = null
	if _enemy_death != null: _enemy_death.cancel()
	_enemy_death = null
	if _hero_motion != null: _hero_motion.cancel()
	if _enemy_motion != null: _enemy_motion.cancel()
	_hero_motion = null
	_enemy_motion = null
	_enemy_attack_delay = 0.0
	animation_time = 0.0

func _hero_impact() -> void:
	if _hero_motion == null or _hero_motion.cancelled: return
	effects.play_action(model.last_action,int(model.state.character.job),String(model.state.battle.get("skills",{}).get("last_skill","")),hero,enemy)
	_shown_enemy_hp = int(model.state.battle.enemy_hp)+int(model.state.battle.get("skills",{}).get("last_reflected",0))
	if _enemy_took_damage and enemy.sprite_frames.has_animation("hurt"): enemy.play("hurt")
	$Hud/BattleEnemyHp.value = _shown_enemy_hp

func _start_enemy_motion() -> void:
	_enemy_attack_delay = 0.0
	if not _should_enemy_act():
		_start_death()
		return
	_enemy_motion = BattleActionPlayback.new()
	_enemy_motion.completed.connect(func() -> void:
		if not _enemy_motion.cancelled: _start_death())
	_enemy_motion.impact.connect(func() -> void:
		if _enemy_motion.cancelled: return
		var took_damage := int(model.state.battle.hp) < _shown_hero_hp
		_shown_hero_hp = int(model.state.battle.hp)
		_shown_enemy_hp = int(model.state.battle.enemy_hp)
		var character:Dictionary=model.state.character
		effects.play_reflection(int(character.job),int(character.school),int(character.level),model.state.battle.get("skills",{}),false,hero,enemy)
		if took_damage and hero.sprite_frames.has_animation("hurt"): hero.play("hurt")
		$Hud/BattleHeroHp.value = _shown_hero_hp
		$Hud/BattleEnemyHp.value = _shown_enemy_hp
	)
	_enemy_motion.start(enemy, OriginalArt.actor_info(model.state.battle.enemy.art), hero.global_position, &"attack", hero)
	animation_time = _enemy_motion.duration

func _start_death() -> void:
	if model == null or not model.ready or not model.state.get("battle") is Dictionary: return
	var b: Dictionary = model.state.battle
	if b.outcome == "defeat" and int(b.hp) == 0 and _hero_death == null:
		_hero_death = BattleDeathPlayback.new()
		_hero_death.start(hero)
		animation_time += _hero_death.remaining()
	elif b.outcome == "victory" and int(b.enemy_hp) == 0 and _enemy_death == null:
		_enemy_death = BattleDeathPlayback.new()
		_enemy_death.start(enemy)
		animation_time += _enemy_death.remaining()

func _should_enemy_act() -> bool:
	if model == null or not model.ready or not model.state.get("battle") is Dictionary: return false
	if int(model.state.battle.get("skill_rules_version",0))==1:return model.state.battle.skills.last_enemy_acted
	var outcome: String = model.state.battle.outcome
	return outcome in ["active", "defeat"] or (outcome == "victory" and model.last_action == "guard") or (outcome == "fled" and model.last_action != "flee")

func _exit_tree() -> void:
	_cancel_motion()

func _action_duration(actor: AnimatedSprite2D, action: StringName) -> float:
	var frames := actor.sprite_frames
	var duration := 0.0
	for index in frames.get_frame_count(action):
		duration += frames.get_frame_duration(action, index) / frames.get_animation_speed(action)
	return duration

func _follow_level(label: Control, actor: Node2D, station: Node2D, home: Vector2) -> void:
	if not is_instance_valid(actor): return
	# Keep the authored station offset, but follow the ANI actor's actual travel.
	# Convert into the label parent's space: HUD offsets/scaling and mirrored
	# monster sprites must not move, resize or reverse the text independently.
	var parent_canvas := label.get_parent() as CanvasItem
	var to_parent := parent_canvas.get_global_transform_with_canvas().affine_inverse()
	var current := to_parent * actor.get_global_transform_with_canvas().origin
	var resting := to_parent * station.get_global_transform_with_canvas().origin
	label.position = home + current - resting

func refresh() -> void:
	if model == null or not model.state.get("battle") is Dictionary: return
	_follow_level($Hud/Level, hero, $Hero, _hero_level_home)
	_follow_level($EnemyLevel, enemy, $Enemy, _enemy_level_home)
	if model.ready and animation_time <= 0:
		_shown_hero_hp = int(model.state.battle.hp)
		_shown_enemy_hp = int(model.state.battle.enemy_hp)
	$Hud/BattleHeroHp.value = _shown_hero_hp
	$Hud/BattleEnemyHp.value = _shown_enemy_hp
	var locked := not model.ready or model.pending() or animation_time > 0
	skill_picker.locked = locked or not model.active()
	for button in buttons: button.disabled = locked or not model.active()
	if not locked and model.active():
		buttons[1].disabled = not SkillPicker.has_usable(int(model.state.character.job),int(model.state.character.school),int(model.state.character.level),int(model.state.battle.mp),model.state.get("skills",{}).get("available",[]),not model.state.has("skills"))
		buttons[3].disabled = int(model.state.potions) == 0 or int(model.state.battle.hp) >= int(model.state.stats.hp)
	$Choice/Use.disabled = locked
	$Hud/AutoButton.disabled = not model.ready or not model.active()
	$Hud/AutoButton.visible = model.active()
	$Hud/AutoButton.text = "0键手动战斗" if automatic else "0键自动战斗"
	$Result.paused = locked
	$Result/Return.disabled = model.active() or locked or not $Result.can_return()
	if not model.ready:
		automatic = false
		$Hint.text = "连接中断，正在恢复战斗……"
	elif model.pending(): $Hint.text = "等待回合结果……"
	elif not model.active():
		automatic = false
		$Hint.text = ""
		$Hud/ActionMenu.hide()
		$Choice.hide()
		skill_picker.hide()
		$Inspect.hide()
		var outcome: String = model.state.battle.outcome
		if animation_time <= 0:
			$Result.present(outcome,{"victory":"战斗结束，你获得了胜利。", "defeat":"战斗结束，你战败了。", "fled":"战斗结束，你撤离了战场。"}.get(outcome,"战斗结束"))
		else: $Result.hide()
	else: $Hint.text = SkillRules.status_text(model.state.battle.get("skills",{}))
	var hero_attacking := _hero_motion != null and _hero_motion.active and _hero_motion.action == &"attack"
	$Hud/BattleHeroHp.visible = not hero_attacking and _hero_death == null
	$Hud/BattleHeroMp.visible = not hero_attacking and _hero_death == null
	$Hud/Level.visible = _hero_death == null
	$Hero/Ring.visible = not hero_attacking and _hero_death == null
	$Hud/BattleEnemyHp.visible = (_enemy_motion == null or not _enemy_motion.active) and _enemy_death == null
	$EnemyLevel.visible = _enemy_death == null
	$Countdown.visible = model.active()
	$Countdown.value = str(maxi(0, ceili(countdown)))
	$Countdown.queue_redraw()

func choose(action: String) -> void:
	if model == null or not model.ready or not model.active() or model.pending() or animation_time > 0: return
	if action=="skill":
		$Hud/ActionMenu.hide();$Inspect.hide();$Choice.hide()
		var c:Dictionary=model.state.character
		skill_picker.present(int(c.job),int(c.school),int(c.level),int(model.state.battle.mp),model.state.get("skills",{}).get("available",[]),not model.state.has("skills"))
		return
	if action == "potion":
		choice_action = action
		$Hud/ActionMenu.hide()
		$Inspect.hide()
		$Choice/Use.text = "回春散 ×%d" % int(model.state.potions)
		$Choice.show()
	elif action == "inspect":
		$Hud/ActionMenu.hide()
		$Choice.hide()
		var b: Dictionary = model.state.battle
		var c: Dictionary = model.state.character
		$Inspect/NameValue.text = b.enemy.name if selected_enemy else c.display_name
		$Inspect/Hp.text = "气血：%d/%d" % [int(b.enemy_hp), int(b.enemy.hp)] if selected_enemy else "气血：%d/%d" % [int(c.hp), int(model.state.stats.hp)]
		$Inspect/Secondary.text = "攻击：%d" % int(b.enemy.attack) if selected_enemy else "灵力：%d/%d" % [int(c.mp), int(model.state.stats.mp)]
		$Inspect/Tertiary.text = "防御：%d" % int(b.enemy.defense) if selected_enemy else "回春散：%d" % int(model.state.potions)
		$Inspect.show()
	else: _send(action)

func _send(action: String) -> void:
	if model == null or not model.ready or not model.active() or model.pending() or animation_time > 0: return
	$Choice.hide()
	$Inspect.hide()
	$Hud/ActionMenu.hide()
	action_requested.emit(action)
	refresh()

func _open_menu() -> void:
	if model == null or not model.active(): return
	skill_picker.hide()
	$Choice.hide()
	$Inspect.hide()
	$Hud/ActionMenu.show()

func toggle_auto() -> void:
	if model == null or not model.active() or not model.ready: return
	automatic = not automatic
	auto_time = 0.0
	$Hud/ActionMenu.visible = not automatic
	$Choice.hide()
	skill_picker.hide()
	$Inspect.hide()
	refresh()

func return_to_map() -> void:
	if not visible or model == null or model.active() or model.pending() or not model.ready or animation_time > 0 or not $Result.can_return(): return
	_cancel_motion()
	$Result.hide()
	hide()
	dismissed.emit()

func _process(delta: float) -> void:
	if is_instance_valid(move_callout):move_callout.update_anchor()
	var was_animating := animation_time > 0
	if not visible or model == null: return
	if not model.ready:
		_cancel_motion()
	else:
		var remaining_delta := delta
		if _hero_motion != null and _hero_motion.active:
			var player_delta := minf(remaining_delta, _hero_motion.remaining())
			_hero_motion.advance(player_delta)
			remaining_delta -= player_delta
		if _enemy_motion != null and _enemy_motion.active:
			if not _should_enemy_act(): _enemy_motion.cancel()
			else:
				var enemy_delta := minf(remaining_delta, _enemy_motion.remaining())
				_enemy_motion.advance(enemy_delta)
				remaining_delta -= enemy_delta
		if _hero_death != null: _hero_death.advance(remaining_delta)
		if _enemy_death != null: _enemy_death.advance(remaining_delta)
		_enemy_attack_delay = _hero_motion.remaining() if _hero_motion != null and _should_enemy_act() else 0.0
		animation_time = (_hero_motion.remaining() if _hero_motion != null else 0.0) + (_enemy_motion.remaining() if _enemy_motion != null else 0.0)
		if _hero_death != null: animation_time += _hero_death.remaining()
		if _enemy_death != null: animation_time += _enemy_death.remaining()
	if was_animating and animation_time == 0 and model.active() and not automatic: _open_menu()
	if model.ready and model.active() and not model.pending() and animation_time == 0:
		countdown = maxf(0.0, countdown - delta)
		auto_time += delta
		if automatic and auto_time >= 1.4: _send("attack")
		elif countdown == 0: _send("guard")
	refresh()
	if $Result.visible and not was_animating:
		$Result.advance(delta)

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if skill_picker.visible: return
	if model == null: return
	match event.keycode:
		KEY_0, KEY_KP_0: toggle_auto()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if $Choice.visible:
				if event.keycode == KEY_1: _send(choice_action)
			else: choose(ACTIONS[event.keycode - KEY_1])
		KEY_ESCAPE:
			if $Inspect.visible or $Choice.visible or skill_picker.visible: _open_menu()
			elif not model.active(): return_to_map()
			else: settings_requested.emit()
		_: return
	get_viewport().set_input_as_handled()
