extends RefCounted
signal changed
signal message(text: String)
signal send_requested(payload: Dictionary)
var character_id:=""
var state:Dictionary={"team":null,"incoming":[]}
var request:Dictionary={}
var inflight:=false
var next_poll:=0
var received_at:=0
var server_time:=0
var supported:=true
const ROUND_ERRORS:={"TEAM_COMMAND_LOCKED":"本轮指令已锁定，等待全员提交。","TEAM_PLAYBACK_ACTIVE":"正在逐个执行行动，请等待下一轮指令窗口。","TEAM_ROUND_EXPIRED":"本轮30秒已结束，未提交者自动防御。","TEAM_NOT_PARTICIPATING":"你已倒下或未参战，不能提交本轮指令。","SOUL_STATE":"灵魂状态，请先寻回自己的尸体。"}
const ERRORS:={"TEAM_MEMBER_REQUIRED":"队长负责带队，无需跟随。","TEAM_NOT_READY":"在线跟随队员尚未准备，请停稳后在队伍窗口准备。","TEAM_NOT_TOGETHER":"请参战队员在同一地图、队长附近集合并停稳。","TEAM_LEADER_REQUIRED":"只能由队长进行此操作。","TEAM_LEADER_MUST_TRANSFER":"请先移交队长，或解散队伍。","TEAM_PLAYER_OFFLINE":"队友已离线，请等待重连或调整队伍。","TEAM_BUSY":"有队员正在单人战斗或决斗中。","TEAM_FULL":"队伍最多5人。","TEAM_NEEDS_MEMBERS":"至少两人组队才能共同战斗。","TEAM_BATTLE_ACTIVE":"正在组队战斗，不能更改队伍。","TEAM_NOT_YOUR_TURN":"请等待当前队友行动。","INVALID_BATTLE_TARGET":"目标已倒下，请重新选择。","TEAM_INVITE_EXPIRED":"邀请已过期或已被处理。","TEAM_INVITE_PENDING":"已发送邀请，请等待对方确认。","TEAM_INVITE_COOLDOWN":"对方已拒绝，请5分钟后再邀请。","ALREADY_IN_TEAM":"你或对方已加入队伍。","MONSTER_RESPAWNING":"有队员的怪物尚未刷新，请稍候。","RESIDENT_TOO_FAR":"请队长靠近怪物。","QUEST_REQUIRED":"有队员尚未领取入门任务，请先找清微道人。","STALE_BATTLE":"战场已更新，请重新选择指令。","NO_ACTIVE_BATTLE":"战斗已经结束。","NOT_IN_TEAM":"尚未加入队伍。","MP_INSUFFICIENT":"灵力不足。","NO_POTION":"没有回春散。","HP_FULL":"气血已满。","NOT_FOUND":"服务尚未支持组队，需要更新游戏服务。","RATE_LIMITED":"操作过快，请稍候。","SESSION_REPLACED":"当前角色已在另一会话进入游戏。"}
func bind_character(id:String)->void:
	character_id=id;request={};inflight=false;next_poll=0;state={"team":null,"incoming":[]}
	var saved:Dictionary=OnlineAccount.pending_team
	if saved.get("server")==OnlineAccount.server_address and saved.get("session")==OnlineAccount.login_session_id and saved.get("request",{}).get("character_id")==id:request=saved.request.duplicate(true)
func party()->Dictionary:return state.team if state.get("team") is Dictionary else {}
func battle()->Dictionary:return party().get("battle",{}) if party().get("battle") is Dictionary else {}
func active()->bool:return battle().get("outcome")=="active"
func pending()->bool:return not request.is_empty() and request.action!="snapshot"
func my_turn()->bool:
	if not active():return false
	var b:=battle()
	if not b.has("commands"):return b.fighters[int(b.turn)].id==character_id
	var now:=server_time+Time.get_ticks_msec()-received_at
	if now<int(b.selection_starts_ms) or now>=int(b.deadline_ms) or b.commands.has(character_id):return false
	for f in b.fighters:
		if f.id==character_id:return f.hp>0
	return false
func submit(action:String,target:String="",skill:String="",ready:Variant=null)->bool:
	if pending() or inflight:return false
	if action not in ["follow","create","invite","accept","reject","cancel","leave","kick","transfer","disband","ready","challenge","attack","skill","guard","potion","flee"]:return false
	var bytes:=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16:return false
	bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;var hex:=bytes.hex_encode()
	request={"character_id":character_id,"action":action,"operation_id":"%s-%s-%s-%s-%s"%[hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]}
	if not target.is_empty():request.target=target
	if not skill.is_empty():request.skill=skill
	if ready is bool:request.ready=ready
	if action in ["attack","skill","guard","potion","flee"]:
		if not active():request={};return false
		if action!="flee" and not my_turn():request={};return false
		request.battle_id=battle().id;request.expected_revision=int(battle().revision)
	OnlineAccount.pending_team={"server":OnlineAccount.server_address,"session":OnlineAccount.login_session_id,"request":request.duplicate(true)}
	next_poll=0;supported=true;changed.emit();return true
func refresh()->void:
	if not pending() and not inflight:request={"character_id":character_id,"action":"snapshot"};next_poll=0;supported=true
func tick(available:bool)->void:
	if not available or inflight or not supported or Time.get_ticks_msec()<next_poll:return
	if request.is_empty():request={"character_id":character_id,"action":"snapshot"}
	inflight=true;next_poll=Time.get_ticks_msec()+2000;send_requested.emit(request.duplicate(true))
func receive(result:Dictionary)->bool:
	if not inflight:return false
	inflight=false
	if result.get("version")!="team-v1" or not valid(result):
		var code:String=result.get("code","INVALID_RESPONSE")
		if pending() and code not in ["INVALID_REQUEST","INVALID_TEAM_TARGET","FORBIDDEN","UNAUTHORIZED","IDEMPOTENCY_CONFLICT","NOT_FOUND"]:message.emit("操作结果未确认，将按原编号重试。")
		else:
			if code=="NOT_FOUND":supported=false
			request={};OnlineAccount.pending_team={};message.emit(ERRORS.get(code,"组队请求失败，请刷新后重试。"))
		next_poll=Time.get_ticks_msec()+5000;changed.emit();return false
	var wrote:=pending()
	state=result.state.duplicate(true);server_time=int(result.server_time_ms);received_at=Time.get_ticks_msec()
	if wrote:OnlineAccount.pending_team={}
	request={};next_poll=received_at+(1000 if active() else 5000)
	if not result.ok:message.emit(ROUND_ERRORS.get(result.code,ERRORS.get(result.code,"组队操作未完成。")))
	elif wrote:message.emit("队伍状态已更新。")
	changed.emit();return true
func valid(v:Dictionary)->bool:
	if v.get("character_id")!=character_id or v.get("operation_id")!=request.get("operation_id") or not v.get("ok") is bool or not v.get("code") is String or not v.get("replayed") is bool or not OnlinePve.integer(v.get("server_time_ms"),0,253402300799999):return false
	var s:Variant=v.get("state")
	if not s is Dictionary or not s.has("team") or not s.get("incoming") is Array or s.incoming.size()>10:return false
	for offer in s.incoming:
		if not offer is Dictionary or not OnlineWorldClient._uuid(offer.get("id")) or not OnlineAccount.valid_nickname(offer.get("name","")) or not OnlinePve.integer(offer.get("remaining_ms"),0,60000):return false
	var p:Variant=s.team
	if p==null:return true
	if not p is Dictionary or not OnlineWorldClient._uuid(p.get("id")) or not p.get("leader") is bool or not p.get("members") is Array or p.members.is_empty() or p.members.size()>5 or not p.has("battle") or not p.get("outgoing") is Array or p.outgoing.size()>10:return false
	if p.has("battle_active") and not p.battle_active is bool:return false
	var ids:={};var leaders:=0
	for m in p.members:
		if not preload("res://scripts/network/online_social.gd").person(m) or ids.has(m.id) or not m.get("ready") is bool or not m.get("following",true) is bool or not m.get("leader") is bool or not SharedWorldMap.exists(m.get("map_id")):return false
		ids[m.id]=true
		if m.leader:leaders+=1
	if leaders!=1 or not ids.has(character_id):return false
	for offer in p.outgoing:
		if not offer is Dictionary or not OnlineWorldClient._uuid(offer.get("id")) or not OnlineAccount.valid_nickname(offer.get("name","")):return false
	var b:Variant=p.battle
	if b==null:return true
	if not b is Dictionary or not OnlineWorldClient._uuid(b.get("id")) or b.get("outcome") not in ["active","victory","defeat","fled"] or not b.get("fighters") is Array or b.fighters.is_empty() or b.fighters.size()>5 or not b.get("enemies") is Array or b.enemies.is_empty() or b.enemies.size()>5 or not b.get("events") is Array or b.events.size()>40 or not b.get("lines") is Array:return false
	if not OnlinePve.integer(b.get("turn"),0,b.fighters.size()-1) or not OnlinePve.integer(b.get("revision"),0,1000) or not OnlinePve.integer(b.get("round"),1,61) or not OnlinePve.integer(b.get("deadline_ms"),0,253402300799999):return false
	var fighters:={}
	for f in b.fighters:
		if not f is Dictionary or not OnlineWorldClient._uuid(f.get("id")) or fighters.has(f.id) or not OnlineAccount.valid_nickname(f.get("name","")) or not OnlinePve.integer(f.get("job"),0,2) or not OnlinePve.integer(f.get("gender"),0,1) or not OnlinePve.integer(f.get("school"),0,3) or not OnlinePve.integer(f.get("level"),1,60) or not f.get("stats") is Dictionary or not SkillRules.valid_state(f.get("effects",{})) or not f.get("appearance") is Array or f.appearance.size()!=3:return false
		fighters[f.id]=true
		if not valid_look(f.appearance):return false
		for stat in ["hp","mp","attack","defense"]:
			if not OnlinePve.integer(f.stats.get(stat),0,100000):return false
		if not OnlinePve.integer(f.get("hp"),0,int(f.stats.hp)) or not OnlinePve.integer(f.get("mp"),0,int(f.stats.mp)) or not OnlinePve.integer(f.get("potions"),0,999):return false
		if b.outcome=="active" and not ids.has(f.id):return false
	if not fighters.has(character_id):return false
	if b.has("commands"):
		if not b.commands is Dictionary or b.commands.size()>b.fighters.size() or not OnlinePve.integer(b.get("round_revision"),0,int(b.revision)) or not OnlinePve.integer(b.get("events_revision"),0,int(b.revision)) or not OnlinePve.integer(b.get("selection_starts_ms"),0,int(b.deadline_ms)) or int(b.deadline_ms)-int(b.selection_starts_ms)!=30000:return false
		for id in b.commands:
			var intent:Variant=b.commands[id]
			if not fighters.has(id) or not intent is Dictionary or intent.get("action") not in ["attack","skill","guard","potion"]:return false
			if intent.get("target")!=null and (not intent.target is String or intent.target not in ["m0","m1","m2","m3","m4"]):return false
			if intent.action=="skill":
				if not intent.get("skill") is String or not SkillRules.item(intent.skill).get("active",false):return false
			elif intent.get("skill")!=null:return false
	var enemies:={}
	for e in b.enemies:
		if not e is Dictionary or not e.get("slot") is String or e.slot not in ["m0","m1","m2","m3","m4"] or enemies.has(e.slot) or not e.get("definition") is Dictionary or not e.definition.get("art") is String:return false
		var d:Dictionary=e.definition
		var original:Dictionary=AIWorld.resident(d.get("id",""))
		if original.is_empty():
			if not OnlinePopulation.ARTS.values().has(d.art) or d.get("kind")=="npc":return false
		elif original.art!=d.art:return false
		for k in ["hp","attack","defense","level"]:
			if not OnlinePve.integer(d.get(k),0,100000):return false
		if not OnlinePve.integer(e.get("hp"),0,int(d.hp)):return false
		enemies[e.slot]=true
	for event in b.events:
		if event is Dictionary and event.has("critical") and not event.critical is bool:return false
		if not event is Dictionary or not (fighters.has(event.get("actor")) or enemies.has(event.get("actor"))) or not (fighters.has(event.get("target")) or enemies.has(event.get("target"))) or event.get("action") not in ["attack","skill","potion","guard"] or not event.get("skill") is String or not OnlinePve.integer(event.get("damage"),0,100000) or not OnlinePve.integer(event.get("healed"),0,100000):return false
	return true

static func valid_look(look:Array)->bool:
	if look.size()!=3:return false
	var limits:Array=[0,0,0]
	for item in ShopRules.catalog.items:
		if item.slot=="weapon":limits[0]=maxi(int(limits[0]),int(item.visual))
		elif item.slot=="armor":limits[1]=maxi(int(limits[1]),int(item.visual))
		elif item.slot=="hat":limits[2]=maxi(int(limits[2]),int(item.get("head_visual",0)))
	for i in 3:
		if not OnlinePve.integer(look[i],0,int(limits[i])):return false
	return true
