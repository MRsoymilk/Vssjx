class_name AIWorld
extends RefCounted
## Synthetic content is deliberately outside original_world.json and tutorial state.
const PATH := "res://assets/data/ai-world-v1.json"
static var maps: Dictionary = {}
static var quests: Dictionary = {}
static var residents: Dictionary = {}
static var catalog_hash := ""
static var monster_count := 0
static var map_monster_limit := 0

static func prepare() -> void:
	if not maps.is_empty(): return
	var raw := FileAccess.get_file_as_string(PATH).replace("\r\n", "\n")
	catalog_hash = raw.sha256_text()
	var catalog: Dictionary = JSON.parse_string(raw)
	for entry in catalog.maps:
		maps[entry.map_id] = entry
		var count: int=entry.residents.filter(func(r: Dictionary)->bool:return r.kind!="npc").size()
		monster_count += count
		map_monster_limit = maxi(map_monster_limit,count)
		for q in entry.quests: quests[q.id] = q
		for r in entry.residents: residents[r.id] = r

static func map_data(id: String) -> Dictionary:
	if not id.begins_with("ai_"): return {}
	prepare()
	return maps.get(id, {})

static func quest(id: String) -> Dictionary:
	if not id.begins_with("ai_"): return {}
	prepare()
	return quests.get(id, {})

static func resident(id: String) -> Dictionary:
	if not id.begins_with("ai_"): return {}
	prepare()
	return residents.get(id, {})

static func local_map_id() -> String:
	return String(Game.player.get("ai_map", "")) if not String(Game.player.get("ai_map", "")).is_empty() else ("qingyun_trail" if int(Game.player.get("zone", 0)) == 0 else "ancient_ruins")

static func station(id: String) -> Vector2i:
	var m := map_data(id)
	if not m.is_empty(): return Vector2i(m.portal.cell[0],m.portal.cell[1])
	return Vector2i(3, 16) if id=="qingyun_trail" else Vector2i(12,16)

static func progress() -> Dictionary:
	if not Game.player.has("ai_progress"): Game.player.ai_progress = {"completed": [], "active": {}, "respawns": {}}
	return Game.player.ai_progress

static func ready_to_claim(id: String, state: Dictionary) -> bool:
	if not state.get("active", {}).has(id): return false
	var q := quest(id)
	for i in q.objectives.size():
		if int(state.active[id][i]) < int(q.objectives[i].count): return false
	return true

static func status(id: String, state: Dictionary, level: int) -> String:
	var q := quest(id)
	if id in state.get("completed", []): return "已完成"
	if state.get("active", {}).has(id): return "可交付" if ready_to_claim(id, state) else "进行中"
	if level < int(q.min_level): return "%d级可接" % int(q.min_level)
	if not q.prerequisite.is_empty() and not q.prerequisite in state.get("completed", []): return "完成前章后可接"
	return "可接取"

static func npc_options(id: String, state: Dictionary, level: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var fallback: Dictionary = {}
	var publisher := false
	for q in map_data(id.left(6)).get("quests",[]):
		if q.giver!=id:continue
		publisher=true
		var value := status(q.id,state,level)
		if value=="已完成":continue
		var action := "ai_claim" if value=="可交付" else "ai_accept"
		var label := "! %s（%s）" % [q.name,"完成" if value=="可交付" else "接受"]
		var disabled := value not in ["可接取","可交付"]
		if disabled:
			label="%s（%s）" % [q.name,value]
			if value=="进行中":
				var counts: Array=state.active[q.id]
				var done := 0;var total := 0
				for i in q.objectives.size():done+=int(counts[i]);total+=int(q.objectives[i].count)
				label="[已接] %s（%d/%d）" % [q.name,done,total]
		var option := {"text":label,"action":action,"target":q.id,"disabled":disabled,"marker":2 if value=="可交付" else (0 if value=="可接取" else -1)}
		if value in ["可接取","可交付","进行中"]:
			options.append(option);break
		if fallback.is_empty():fallback=option
	if options.is_empty() and not fallback.is_empty():options.append(fallback)
	elif options.is_empty() and publisher:options.append({"text":"[完成] 此地支线","action":"","target":"","disabled":true,"marker":-1})
	for qid in state.get("active",{}):
		var q := quest(qid)
		if q.is_empty():continue
		var counts: Array=state.active[qid]
		for i in q.objectives.size():
			var goal: Dictionary=q.objectives[i]
			if goal.kind!="interact" or goal.target!=id or int(counts[i])>=int(goal.count):continue
			var ordered := true
			for j in i:
				if int(counts[j])<int(q.objectives[j].count):ordered=false
			options.append({"text":"! %s（完成）" % goal.text if ordered else "%s（先完成前项目标）" % goal.text,"action":"ai_interact","target":id,"disabled":not ordered,"marker":2 if ordered else -1})
	return options

static func npc_marker(id: String, state: Dictionary, level: int) -> Dictionary:
	var stage := -1;var hint := ""
	for option in npc_options(id,state,level):
		if int(option.marker)==2:return {"stage":2,"hint":"可完成任务目标" if option.action=="ai_interact" else "任务可完成，领取奖励"}
		if int(option.marker)==0:stage=0;hint="可接受任务"
	return {"stage":stage,"hint":hint}

static func quest_hint(map_id: String, state: Dictionary, level: int) -> String:
	var m := map_data(map_id)
	if m.is_empty(): return ""
	for id in state.get("active", {}):
		var q := quest(id)
		if q.map_id != map_id: continue
		if ready_to_claim(id,state): return "AI支线 · %s已完成，请向发布人复命。" % q.name
		for i in q.objectives.size():
			if int(state.active[id][i]) < int(q.objectives[i].count):
				return "AI支线 · %s　%s %d/%d" % [q.name,q.objectives[i].text,int(state.active[id][i]),int(q.objectives[i].count)]
	for q in m.quests:
		if status(q.id,state,level)=="可接取": return "AI支线 · 拜访%s，领受「%s」。" % [resident(q.giver).name,q.name]
	return "AI生成场景 · 可在任务页查看此地支线，或由驿石继续探索。"

static func event(kind: String, target: String) -> bool:
	var state := progress()
	var changed := false
	for id in state.active:
		var goals: Array = quest(id).objectives
		for i in goals.size():
			var goal: Dictionary = goals[i]
			if goal.kind != kind or goal.target != target or int(state.active[id][i]) >= int(goal.count): continue
			var previous_done := true
			if kind == "interact":
				for j in i:
					if int(state.active[id][j]) < int(goals[j].count): previous_done = false
			if previous_done:
				state.active[id][i] = int(state.active[id][i]) + 1
				changed = true
	return changed

static func apply_local(action: String, target: String) -> String:
	if action not in ["ai_travel", "ai_accept", "ai_claim", "ai_restore", "ai_interact"]: return "未知操作。"
	if action in ["ai_accept", "ai_claim"] and quest(target).is_empty(): return "未知任务。"
	if action == "ai_restore" and not target.ends_with("_guide"): return "请找巡山发布人调息。"
	var state := progress()
	var map_id := local_map_id()
	var point := station(map_id)
	if action != "ai_travel":
		var r := resident(String(quest(target).get("giver", target)))
		if r.is_empty() or not map_id == String(r.id).left(6): return "目标不属于当前地图。"
		point = Vector2i(r.cell[0], r.cell[1])
	var current := Vector2i(Game.player.cell[0], Game.player.cell[1])
	var gate := SharedWorldMap.exit_at(map_id,current) if action=="ai_travel" else {}
	var at_exit: bool = not gate.is_empty() and gate.target_map==target
	if not at_exit and absi(current.x-point.x)+absi(current.y-point.y)>2: return "请先靠近目标。"
	if action == "ai_travel":
		if (target != "qingyun_trail" and map_data(target).is_empty()) or target == map_id: return "请选择其他目的地。"
		Game.player.ai_map = target if not map_data(target).is_empty() else ""
		Game.player.zone = 1 if target == "ancient_ruins" else 0
		Game.player.cell = SharedWorldMap.load_data(target).spawn.duplicate()
		return ""
	if action == "ai_restore": Game.restore(); return ""
	if action == "ai_interact": return "" if event("interact", target) else "先接取任务，并按目标顺序调查。"
	var q := quest(target)
	var value := status(target, state, int(Game.player.level))
	if action == "ai_accept":
		if value != "可接取": return value
		if state.active.size() >= 3: return "最多同时接取三个AI生成任务。"
		var counts := []
		for _goal in q.objectives: counts.append(0)
		state.active[target] = counts
	elif action == "ai_claim":
		if not ready_to_claim(target, state): return "任务尚未完成，或奖励已领取。"
		state.active.erase(target)
		state.completed.append(target)
		Game.add_rewards(int(q.gold), int(q.xp))
	return ""

static func valid_progress(value: Variant, network: bool = false) -> bool:
	if not value is Dictionary or not value.get("completed") is Array or not value.get("active") is Dictionary or not value.get("respawns") is Dictionary: return false
	prepare()
	if value.completed.size() > (3 if network else 642) or value.active.size() > 3 or value.respawns.size() > (map_monster_limit if network else monster_count): return false
	var seen := {}
	for id in value.completed:
		if not id is String or quest(id).is_empty() or seen.has(id): return false
		seen[id] = true
	for id in value.active:
		if not id is String or quest(id).is_empty() or seen.has(id) or not value.active[id] is Array: return false
		var goals: Array = quest(id).objectives
		if value.active[id].size() != goals.size(): return false
		for i in goals.size():
			if not ShopRules._integer(value.active[id][i], 0, int(goals[i].count)): return false
	for id in value.respawns:
		if not id is String or resident(id).is_empty() or resident(id).kind == "npc" or not ShopRules._integer(value.respawns[id], 0, 253402300799999): return false
	if network:
		prepare()
		if value.get("version") != "ai-world-v1" or value.get("catalog_sha256") != catalog_hash or not ShopRules._integer(value.get("completed_count"), 0, 642): return false
	return true
