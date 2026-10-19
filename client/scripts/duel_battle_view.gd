class_name DuelBattleView
extends OnlineBattleView
var channel: OnlineDuel
var adapter := DuelBattleModel.new()
var opponent: Dictionary = {}
var _last_packet := ""
var hero_name: Label
var enemy_name: Label
const HERO_NAME_HOME := Vector2(210,147)
const ENEMY_NAME_HOME := Vector2(4,138)

func _ready() -> void:
	super._ready()
	hero_name = OriginalSceneChrome.label(self,"",Rect2(HERO_NAME_HOME,Vector2(110,18)),11,Color("613e26"))
	enemy_name = OriginalSceneChrome.label(self,"",Rect2(ENEMY_NAME_HOME,Vector2(110,18)),11,Color("613e26"))
	for tag in [hero_name,enemy_name]: tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func present_duel(duel: OnlineDuel) -> void:
	channel = duel
	adapter.channel = duel
	var b: Dictionary = duel.state.battle
	var me: Dictionary = b.fighters[0] if b.fighters[0].id == duel.character_id else b.fighters[1]
	opponent = b.fighters[1] if b.fighters[0].id == duel.character_id else b.fighters[0]
	var c := {"id":me.id,"display_name":me.name,"job":me.job,"gender":me.gender,"school":me.school,"level":me.level,"hp":me.hp,"mp":me.mp}
	hero_name.text = me.name;enemy_name.text = opponent.name
	var action: String = b.last_action
	var mine: bool = b.last_actor == duel.character_id
	var combat_effects: Dictionary = me.effects.duplicate(true)
	combat_effects.last_skill = b.last_skill if mine else ""
	combat_effects.last_enemy_acted = not mine and action in ["attack", "skill"]
	var outcome: String = "active" if b.status == "active" else ("victory" if b.winner == duel.character_id else ("defeat" if b.winner != null else "fled"))
	adapter.state = {"character":c,"stats":me.stats,"potions":0,"skills":{"available":SkillRules.list_for(int(me.job),int(me.school),int(me.level)).map(func(s:Dictionary)->String:return s.id)},"battle":{"id":b.id,"revision":b.revision,"round":int(b.revision)/2+1,"hp":me.hp,"mp":me.mp,"enemy_hp":opponent.hp,"outcome":outcome,"skills":combat_effects,"skill_rules_version":1,"enemy":{"name":opponent.name,"level":opponent.level,"hp":opponent.stats.hp,"attack":opponent.stats.attack,"defense":opponent.stats.defense,"art":ShopRules.actor_key(int(opponent.job),int(opponent.gender),opponent.appearance)}}}
	adapter.last_action = action if mine else "duel_opponent"
	adapter.last_code = duel.last_code
	adapter.ready = duel.connected
	super.present(adapter)
	_hero_key = ShopRules.actor_key(int(me.job),int(me.gender),me.appearance)
	OriginalArt.apply_appearance(hero,_hero_key)
	var packet: String = b.id + ":" + b.revision
	if packet != _last_packet:
		_last_packet = packet
		countdown = maxf(0, (float(b.remaining_ms) - (Time.get_ticks_msec() - duel.received_at)) / 1000.0)
		if duel.my_turn() and animation_time <= 0: _open_menu()
	refresh()

func refresh() -> void:
	super.refresh()
	if channel == null or model == null: return
	buttons[3].disabled = true
	buttons[3].text = "道具禁用"
	buttons[5].text = "6 认输"
	buttons[5].disabled = not channel.connected or channel.pending() or not channel.active() or animation_time > 0
	if hero != null: _follow_level(hero_name,hero,$Hero,HERO_NAME_HOME)
	if enemy != null: _follow_level(enemy_name,enemy,$Enemy,ENEMY_NAME_HOME)
	$Hud/AutoButton.hide()
	if channel.active():
		$Hint.text = "连接中断，正在恢复决斗……" if not channel.connected else ("等待操作确认……" if channel.pending() else ("轮到你行动" if channel.my_turn() else "等待对方行动……"))
	else:
		$Hint.text = "切磋不消耗日常血蓝与物品，无胜负奖励。"

func toggle_auto() -> void: pass # Both participants choose their own actions.

func choose(action: String) -> void:
	if action == "potion": return
	if action == "flee" and channel != null and channel.connected and not channel.pending() and channel.active() and animation_time <= 0:
		action_requested.emit("flee");return
	super.choose(action)

func _hero_impact() -> void:
	if _hero_motion == null or _hero_motion.cancelled: return
	effects.play_action(model.last_action,int(model.state.character.job),channel.state.battle.last_skill,hero,enemy)
	if _enemy_took_damage and enemy.sprite_frames.has_animation("hurt"): enemy.play("hurt")
	_shown_hero_hp = int(model.state.battle.hp)
	_shown_enemy_hp = int(model.state.battle.enemy_hp)
	effects.play_reflection(int(opponent.job),int(opponent.school),int(opponent.level),opponent.effects,model.last_action=="skill" and int(model.state.character.job)==2,enemy,hero)

func _start_enemy_motion() -> void:
	_enemy_attack_delay = 0.0
	if not _should_enemy_act(): _start_death(); return
	var b: Dictionary = channel.state.battle
	var used := SkillRules.item(b.last_skill)
	var support: bool = b.last_action == "skill" and not used.is_empty() and int(used.damage_percent) == 0
	var animation: StringName = &"cast" if b.last_action == "skill" and enemy.sprite_frames.has_animation("cast") else &"attack"
	if support and not enemy.sprite_frames.has_animation("cast"): animation = &"idle"
	_enemy_motion = BattleActionPlayback.new()
	_enemy_motion.impact.connect(func() -> void:
		if _enemy_motion.cancelled: return
		effects.play_action(b.last_action,int(opponent.job),b.last_skill,enemy,hero)
		if int(model.state.battle.hp) < _shown_hero_hp and hero.sprite_frames.has_animation("hurt"): hero.play("hurt")
		_shown_hero_hp = int(model.state.battle.hp);_shown_enemy_hp = int(model.state.battle.enemy_hp)
	)
	_enemy_motion.completed.connect(func()->void:
		if not _enemy_motion.cancelled: _start_death()
	)
	_enemy_motion.start(enemy,OriginalArt.actor_info(model.state.battle.enemy.art),enemy.global_position if support else hero.global_position,animation,enemy if support else hero)
	move_callout.present_for(ShushanBattle.action_name(b.last_action,int(opponent.job),b.last_skill),enemy,_enemy_motion.duration)
	animation_time = _enemy_motion.duration
