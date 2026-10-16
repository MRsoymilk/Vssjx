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
var guarding := false
var finished := false
var victory := false
var escaped := false
var committed := false
var save_result: PlatformResult
var rng := RandomNumberGenerator.new()

static func action_name(command: String, job: int) -> String:
	if command == "skill": return SKILL_NAMES[clampi(job, 0, 2)]
	if command == "attack": return ["锤击", "剑击", "杖击"][clampi(job, 0, 2)]
	return String({"guard": "凝神防御", "potion": "回春散", "flee": "撤退"}.get(command, ""))

func _init(opponent: Dictionary) -> void:
	enemy = opponent.duplicate(true)
	enemy_hp = int(enemy.hp)
	hp = int(Game.player.hp)
	mp = int(Game.player.mp)
	potions = int(Game.player.potions)
	rng.randomize()

func begin_action(command: String) -> Dictionary:
	if finished:
		return {"ok": false, "lines": ["战斗已经结束"]}
	if phase != "select":
		return {"ok": false, "lines": ["本回合正在结算，请等待。"]}
	if command not in ["attack", "skill", "potion", "guard", "flee"]:
		return {"ok": false, "lines": ["未知行动"]}
	if command == "skill" and mp < 9:
		return {"ok": false, "lines": ["灵力不足，需要 9 点灵力。"]}
	if command == "potion":
		if potions <= 0:
			return {"ok": false, "lines": ["背包里没有回春散了。"]}
		if hp >= int(Game.stats().hp):
			return {"ok": false, "lines": ["生命已满，无需用药。"]}
	pending_command = command
	guarding = false
	round_number += 1
	phase = "player"
	return {"ok": true, "lines": ["第 %d 回合开始。" % round_number]}

func resolve_player() -> Dictionary:
	if phase != "player": return {"ok": false, "lines": []}
	var values := Game.stats()
	var lines: Array[String] = []
	var damage := 0
	match pending_command:
		"attack":
			damage = maxi(1, int(values.attack) - int(enemy.defense) + rng.randi_range(-2, 2))
			lines.append("你%s出击，造成 %d 点伤害。" % [["挥锤", "挥剑", "挥杖"][int(Game.player.job)], damage])
		"skill":
			mp -= 9
			damage = maxi(1, int(float(values.attack) * 1.8) - int(enemy.defense))
			lines.append("你施展%s，造成 %d 点伤害。" % [action_name("skill", int(Game.player.job)), damage])
			if int(Game.player.job) == 2:
				hp = mini(int(values.hp), hp + 16)
				lines.append("摄灵恢复了 16 点生命。")
		"potion":
			potions -= 1
			var healed := mini(45, int(values.hp) - hp)
			hp += healed
			lines.append("服用回春散，恢复 %d 点生命。" % healed)
		"guard":
			guarding = true
			mp = mini(int(values.mp), mp + 5)
			lines.append("你凝神防御，恢复 5 点灵力。")
		"flee":
			finished = true
			escaped = true
			phase = "settlement"
			return {"ok": true, "lines": ["你撤回了安全地带。"], "damage": 0}
	enemy_hp = maxi(0, enemy_hp - damage)
	if enemy_hp == 0:
		finished = true
		victory = true
		lines.append("%s被击败了！" % enemy.name)
	phase = "settlement" if finished else "enemy"
	return {"ok": true, "lines": lines, "damage": damage}

func resolve_enemy() -> Dictionary:
	if phase != "enemy": return {"ok": false, "lines": []}
	var values := Game.stats()
	var lines: Array[String] = []
	var incoming := maxi(1, int(enemy.attack) - int(values.defense) + rng.randi_range(-2, 2))
	if guarding: incoming = maxi(1, incoming / 2)
	hp = maxi(0, hp - incoming)
	lines.append("%s行动，你受到 %d 点伤害。" % [enemy.name, incoming])
	var reflected := 0
	if int(Game.player.job) == 0 and guarding:
		reflected = mini(6, enemy_hp)
		enemy_hp = maxi(0, enemy_hp - reflected)
		lines.append("力士反震，造成 %d 点伤害。" % reflected)
	if hp == 0:
		finished = true
		lines.append("你力竭倒下，被道人送回山门。")
	elif enemy_hp == 0:
		finished = true
		victory = true
		lines.append("%s被击败了！" % enemy.name)
	phase = "settlement"
	return {"ok": true, "lines": lines, "incoming": incoming, "reflected": reflected}

func finish_round() -> Dictionary:
	if phase != "settlement": return {"ok": false, "lines": []}
	var lines: Array[String] = []
	if round_number >= MAX_ROUNDS and not finished:
		finished = true
		escaped = true
		lines.append("三十回合已过，战斗结束。")
	phase = "finished" if finished else "select"
	pending_command = ""
	guarding = false
	return {"ok": true, "lines": lines}

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
	elif not escaped:
		Game.restore()
		Game.player.zone = 0
		Game.player.cell = [Game.START_CELL.x, Game.START_CELL.y]
	save_result = await Game.save_game()
	return leveled
