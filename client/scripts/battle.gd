class_name ShushanBattle
extends RefCounted

var enemy: Dictionary
var enemy_hp: int
var hp: int
var mp: int
var potions: int
const MAX_ROUNDS := 30
const SKILL_NAMES := ["破山诀", "御剑诀", "摄灵诀"]
var round_number := 0
## select -> player -> enemy -> settlement -> select/finished.
var phase := "select"
var pending_command := ""
var pending_skill := ""
var selected_skill := ""
var skills:Dictionary={}
var guarding := false
var finished := false
var victory := false
var escaped := false
var committed := false
var save_result: PlatformResult
var rng := RandomNumberGenerator.new()
var frozen_stats:Dictionary={}

static func action_name(command: String, job: int, skill_id:String="") -> String:
	if command == "skill": return String(SkillRules.item(skill_id).name) if not skill_id.is_empty() and not SkillRules.item(skill_id).is_empty() else SKILL_NAMES[clampi(job, 0, 2)]
	if command == "attack": return ["锤击", "剑击", "杖击"][clampi(job, 0, 2)]
	return String({"guard": "凝神防御", "potion": "回春散", "flee": "撤退"}.get(command, ""))

func _init(opponent: Dictionary) -> void:
	enemy = opponent.duplicate(true)
	if Game.player.get("balance_revision",0)==1:enemy=ProgressionRules.monster(SkillBalance.monster(enemy))
	enemy_hp = int(enemy.hp)
	hp = int(Game.player.hp)
	mp = int(Game.player.mp)
	potions = int(Game.player.potions)
	frozen_stats=Game.stats().duplicate(true)
	skills=SkillRules.new_state(int(Game.player.job),int(Game.player.school),int(Game.player.level),int(enemy.get("level",1)))
	SkillRules.activate(skills,frozen_stats)
	selected_skill=SkillRules.default_id(int(Game.player.job),int(Game.player.school),int(Game.player.level))
	rng.randomize()

func begin_action(command: String, skill_id:String="") -> Dictionary:
	if Game.is_soul():return {"ok":false,"lines":[OnlinePve.error_text("SOUL_STATE")]}
	if finished:
		return {"ok": false, "lines": ["战斗已经结束"]}
	if phase != "select":
		return {"ok": false, "lines": ["本回合正在结算，请等待。"]}
	if command not in ["attack", "skill", "potion", "guard", "flee"]:
		return {"ok": false, "lines": ["未知行动"]}
	if command=="skill":
		if skill_id.is_empty():skill_id="legacy_%d"%int(Game.player.job)
		var code:=SkillRules.check(skill_id,int(Game.player.job),int(Game.player.school),int(Game.player.level))
		if not code.is_empty():return {"ok":false,"lines":[OnlinePve.error_text(code)]}
		if SkillRules.remaining(skills,skill_id)>0:return {"ok":false,"lines":["技能尚在冷却。"]}
		var cost:=SkillBalance.cost(SkillRules.item(skill_id),frozen_stats)
		if mp<cost:return {"ok":false,"lines":["灵力不足，需要 %d 点灵力。"%cost]}
	if command == "potion":
		if potions <= 0:
			return {"ok": false, "lines": ["背包里没有回春散了。"]}
		if hp >= int(Game.stats().hp):
			return {"ok": false, "lines": ["生命已满，无需用药。"]}
	pending_command = command
	pending_skill=skill_id if command=="skill" else ""
	SkillRules.reset_turn(skills)
	guarding = false
	round_number += 1
	phase = "player"
	return {"ok": true, "lines": ["第 %d 回合开始。" % round_number]}

func resolve_player() -> Dictionary:
	if phase != "player": return {"ok": false, "lines": []}
	var values := frozen_stats
	skills.erase("last_missed")
	var lines: Array[String] = []
	var damage := 0
	match pending_command:
		"attack":
			mp=mini(int(values.mp),mp+SkillBalance.recovery(values,"basic_restore_bp"))
			var magical:bool=int(Game.player.job)==2 and values.has("balance")
			damage = CharacterAttributeRules.direct_damage(CharacterAttributeRules.power(values,int(Game.player.job),magical),int(enemy.defense),10000,rng.randi_range(-2,2))
			damage=CharacterAttributeRules.critical_at(values,magical,skills,damage,rng.randi_range(0,9999))
			if SkillBalance.revised(values) and rng.randi_range(0,9999)>=CharacterAttributeRules.hit_chance(values,{},magical):damage=0;skills.last_critical=false;skills.last_missed=true
			if damage>0:skills.enemy_sleep=0
			lines.append("你%s出击，造成 %d 点伤害。" % [["挥锤", "挥剑", "挥杖"][int(Game.player.job)], damage])
		"skill":
			var skill:=SkillRules.item(pending_skill)
			if SkillBalance.revised(values) and int(skill.damage_percent)>0 and skill.target in ["enemy","all_enemies"] and rng.randi_range(0,9999)>=CharacterAttributeRules.hit_chance(values,{},int(Game.player.job)==2):
				mp=SkillRules.miss(skill,skills,values,mp);lines.append("法招未能命中，未施加目标状态。")
			else:
				var cast:=SkillRules.cast(skill,skills,CharacterAttributeRules.power(values,int(Game.player.job),int(Game.player.job)==2),hp,mp,int(enemy.defense),rng.randi_range(0,99))
				hp=int(cast.hp);mp=int(cast.mp);damage=CharacterAttributeRules.critical_at(values,int(Game.player.job)==2,skills,int(cast.damage),rng.randi_range(0,9999))
			lines.append("你施展%s%s"%[action_name("skill",int(Game.player.job),pending_skill),"，造成 %d 点伤害。"%damage if damage>0 else "。"])
		"potion":
			potions -= 1
			var healed := mini(SkillBalance.potion(values), int(values.hp) - hp)
			hp += healed
			lines.append("服用回春散，恢复 %d 点生命。" % healed)
		"guard":
			guarding = true
			var recovery:=SkillBalance.recovery(values,"guard_restore_bp",5)
			mp = mini(int(values.mp), mp + recovery)
			lines.append("你凝神防御，恢复 %d 点灵力。"%recovery)
		"flee":
			finished = true
			escaped = true
			phase = "settlement"
			return {"ok": true, "lines": ["你撤回了安全地带。"], "damage": 0}
	var direct_damage:=mini(enemy_hp,damage)
	var after:=SkillRules.after_player(skills,hp,int(values.hp))
	hp=int(after.hp)
	if int(after.damage)>0:lines.append("持续效果造成 %d 点伤害。"%int(after.damage))
	if int(skills.last_healed)>0:lines.append("恢复 %d 点气血。"%int(skills.last_healed))
	damage+=int(after.damage)
	skills.last_damage=mini(enemy_hp,damage)
	enemy_hp = maxi(0, enemy_hp - damage)
	if enemy_hp == 0:
		finished = true
		victory = true
		lines.append("%s被击败了！" % enemy.name)
	phase = "settlement" if finished else "enemy"
	return {"ok": true, "lines": lines, "damage": damage,"direct_damage":direct_damage}

func resolve_enemy() -> Dictionary:
	if phase != "enemy": return {"ok": false, "lines": []}
	var values := frozen_stats
	var lines: Array[String] = []
	if int(skills.enemy_sleep)>0:
		phase="settlement"
		return {"ok":true,"lines":["%s处于睡眠，无法行动。"%enemy.name],"incoming":0,"reflected":0}
	var magical:=values.has("balance") and SkillBalance.monster_magical(enemy,round_number,int(skills.enemy_mp),int(skills.enemy_silence)>0)
	if magical:skills.enemy_mp=int(skills.enemy_mp)-10;lines.append("%s施展法术。"%enemy.name)
	if skills.has("balance"):skills.balance.last_enemy_magical=magical
	if values.has("balance") and (round_number+1)%int(SkillBalance.rules.cast_period)==0:lines.append("妖物正在蓄势，下轮留意防御或封印。")
	var incoming := CharacterAttributeRules.incoming(int(enemy.attack),int(enemy.get("level",1)),values,magical,rng.randi_range(-2,2))
	var landed:=rng.randi_range(0,9999)<CharacterAttributeRules.hit_chance({},values,magical)
	skills.last_enemy_missed=not landed
	if guarding: incoming = maxi(1, incoming / 2)
	var hit:=SkillRules.enemy_hit(skills,incoming,int(values.attack),magical) if landed else Vector2i.ZERO
	incoming=hit.x;skills.last_enemy_acted=true
	hp = maxi(0, hp - incoming)
	lines.append("%s行动，你受到 %d 点伤害。" % [enemy.name, incoming])
	var reflected := hit.y
	if landed and int(Game.player.job) == 0 and guarding:
		reflected+=6
	reflected=mini(enemy_hp,reflected);enemy_hp=maxi(0,enemy_hp-reflected)
	skills.last_incoming=incoming;skills.last_reflected=reflected
	if reflected>0:lines.append("反伤造成 %d 点伤害。"%reflected)
	if hp == 0:
		finished = true
		lines.append("你力竭倒下，灵魂将从本地图复活点醒来。")
	elif enemy_hp == 0:
		finished = true
		victory = true
		lines.append("%s被击败了！" % enemy.name)
	phase = "settlement"
	return {"ok": true, "lines": lines, "incoming": incoming, "reflected": reflected}

func finish_round() -> Dictionary:
	if phase != "settlement": return {"ok": false, "lines": []}
	var lines: Array[String] = []
	var after:=SkillRules.end_balance_round(skills,hp,int(frozen_stats.hp)) if pending_command!="flee" else {"damage":0,"hp":hp};hp=int(after.hp)
	if int(after.damage)>0:enemy_hp=maxi(0,enemy_hp-int(after.damage));lines.append("回合末持续伤害%d点。"%int(after.damage))
	if enemy_hp==0:finished=true;victory=hp>0
	if hp==0:finished=true;victory=false
	if round_number >= MAX_ROUNDS and not finished:
		finished = true
		escaped = true
		lines.append("三十回合已过，战斗结束。")
	phase = "finished" if finished else "select"
	SkillRules.end_turn(skills)
	pending_command = ""
	guarding = false
	return {"ok": true, "lines": lines,"dot_damage":int(after.damage)}

## Synchronous adapter for rule tests; the game UI resolves each stage separately.
func action(command: String) -> Dictionary:
	var start := begin_action(command)
	if not start.ok: return start
	var lines: Array = start.lines.duplicate()
	var player_result := resolve_player()
	lines.append_array(player_result.lines)
	if phase == "enemy": lines.append_array(resolve_enemy().lines)
	lines.append_array(finish_round().lines)
	return {"ok": true, "lines": lines, "damage": player_result.damage}

func commit() -> bool:
	if committed or not finished or phase != "finished": return false
	committed = true
	Game.player.hp = hp
	Game.player.mp = mp
	Game.player.potions = potions
	var leveled := false
	if victory:
		leveled = Game.finish_enemy(enemy)
		loot_message=Game.award_loot([enemy],rng.randi())
	elif not escaped:
		Game.become_soul()
	save_result = await Game.save_game()
	return leveled

var loot_message:=""
