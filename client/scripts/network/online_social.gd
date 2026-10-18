extends RefCounted
## The account transport owns tokens; this model only sees allowlisted social JSON.
signal changed
signal message(text: String)
signal send_requested(payload: Dictionary)
const READS := ["snapshot","profile","find","guild_browse"]
const WRITES := ["friend_request","friend_accept","friend_reject","friend_remove","guild_create","guild_apply","guild_cancel","guild_approve","guild_reject","guild_kick","guild_transfer","guild_leave","guild_disband","guild_announce"]
const ERRORS := {"PLAYER_NOT_FOUND":"未找到该角色。","SELF_TARGET":"不能对自己进行此操作。","FRIEND_LIMIT":"你或对方的好友和申请数量已达100。","REQUEST_PENDING":"已有好友申请，请在申请页处理。","ALREADY_FRIENDS":"已经是好友。","FRIEND_COOLDOWN":"对方已拒绝，请在5分钟后再申请。","REQUEST_NOT_FOUND":"申请已处理或已取消，请刷新。","FORBIDDEN":"你无权进行此操作。","INVALID_NAME":"名称需为2–12个汉字、字母、数字或下划线。","GUILD_NAME_TAKEN":"帮派名称已被使用。","ALREADY_IN_GUILD":"角色已加入帮派。","GUILD_NOT_FOUND":"该帮派已不存在。","GUILD_FULL":"帮派已满50人。","APPLICATION_LIMIT":"申请数量已达上限。","ALREADY_APPLIED":"已经申请，等待帮主审批。","NOT_IN_GUILD":"尚未加入帮派。","LEADER_REQUIRED":"只有帮主可以进行此操作。","LEADER_MUST_TRANSFER":"帮主请先移交帮主或解散帮派。","MEMBER_NOT_FOUND":"对方已不在本帮。","INVALID_TEXT":"公告最多120字，不能含换行或控制字符。","RATE_LIMITED":"操作过快，请稍后重试。","NOT_FOUND":"当前服务器尚未支持好友和帮派。","UNAUTHORIZED":"登录已失效，请重新登录。","IDEMPOTENCY_CONFLICT":"操作编号冲突，请刷新后重试。"}
var character_id := ""
var state: Dictionary = {}
var profile: Dictionary = {}
var request: Dictionary = {}
var queued_read: Dictionary = {}
var inflight := false
var sent_at := 0
var next_poll := 0
var last_code := ""
var supported := true

func bind_character(id: String) -> void:
	character_id=id;state={};profile={};request={};queued_read={};inflight=false;last_code="";supported=true
	var saved: Dictionary = OnlineAccount.pending_social
	if saved.get("server")==OnlineAccount.server_address and saved.get("session")==OnlineAccount.login_session_id and saved.get("request",{}).get("character_id")==id:
		request=saved.request.duplicate(true)
	next_poll=Time.get_ticks_msec()

func pending() -> bool: return not request.is_empty() and request.action not in READS

func fetch(action: String="snapshot", target: String="", name: String="") -> bool:
	if action not in READS or pending(): return false
	var next: Dictionary={"character_id":character_id,"action":action}
	if not target.is_empty(): next.target=target
	if not name.is_empty(): next.name=name
	if inflight:queued_read=next;return true
	request=next
	supported=true
	next_poll=0
	return true

func submit(action: String, target: String="", name: String="", text: String="") -> bool:
	if action not in WRITES or not request.is_empty() or inflight: return false
	var bytes:=Crypto.new().generate_random_bytes(16)
	if bytes.size()!=16: return false
	bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
	var hex:=bytes.hex_encode()
	request={"character_id":character_id,"action":action,"operation_id":"%s-%s-%s-%s-%s"%[hex.substr(0,8),hex.substr(8,4),hex.substr(12,4),hex.substr(16,4),hex.substr(20,12)]}
	if not target.is_empty(): request.target=target
	if not name.is_empty(): request.name=name
	if not text.is_empty() or action=="guild_announce": request.text=text
	OnlineAccount.pending_social={"server":OnlineAccount.server_address,"session":OnlineAccount.login_session_id,"request":request.duplicate(true)}
	last_code="";next_poll=0;changed.emit()
	return true

func tick(transport_available: bool, poll: bool=true) -> void:
	if not transport_available or character_id.is_empty() or inflight or not supported: return
	var now:=Time.get_ticks_msec()
	if request.is_empty() and poll and now>=next_poll: fetch()
	if request.is_empty() or now<next_poll: return
	inflight=true;sent_at=now;next_poll=now+15000
	send_requested.emit(request.duplicate(true))

func receive(result: Dictionary) -> bool:
	if not inflight: return false
	inflight=false
	if result.get("version")!="social-v1" or not valid(result):
		last_code=String(result.get("code","INVALID_RESPONSE"))
		if last_code=="NOT_FOUND" and not pending():supported=false
		if pending() and last_code not in ["INVALID_REQUEST","FORBIDDEN","UNAUTHORIZED","IDEMPOTENCY_CONFLICT"]:
			message.emit("社交操作结果未确认，将使用原编号重试。")
		else:
			request=queued_read.duplicate(true);queued_read={};OnlineAccount.pending_social={}
			if not request.is_empty():next_poll=0
			message.emit(ERRORS.get(last_code,"社交请求失败，请稍后刷新。"))
		changed.emit();return false
	state=result.state.duplicate(true)
	if request.action in ["profile","find"] and (queued_read.is_empty() or queued_read.action not in ["profile","find"]): profile=result.profile.duplicate(true) if result.profile is Dictionary else {}
	last_code=result.code
	if not result.ok: message.emit(ERRORS.get(last_code,"操作未完成，请刷新后重试。"))
	elif pending(): message.emit("操作已保存。")
	else:message.emit("")
	if pending(): OnlineAccount.pending_social={}
	request=queued_read.duplicate(true);queued_read={};next_poll=0 if not request.is_empty() else Time.get_ticks_msec()+15000;changed.emit()
	return true

static func person(v: Variant) -> bool:
	return v is Dictionary and OnlineWorldClient._uuid(v.get("id")) and OnlineAccount.valid_nickname(v.get("display_name","")) and OnlinePve.integer(v.get("job"),0,2) and OnlinePve.integer(v.get("gender"),0,1) and OnlinePve.integer(v.get("level"),1,60) and v.get("online") is bool

static func people(v: Variant, limit: int) -> bool:
	if not v is Array or v.size()>limit: return false
	var ids:={}
	for p in v:
		if not person(p) or ids.has(p.id): return false
		ids[p.id]=true
	return true

func valid(v: Dictionary) -> bool:
	if v.get("character_id")!=character_id or not v.get("ok") is bool or not v.get("code") is String or not v.get("replayed") is bool or not v.has("profile"): return false
	if v.ok!=(v.code=="OK"):return false
	if v.get("operation_id")!=request.get("operation_id"): return false
	var s: Variant=v.get("state")
	if not s is Dictionary or not s.has("guild"): return false
	for key in ["friends","incoming","outgoing"]:
		if not people(s.get(key),100): return false
	if not s.get("guilds") is Array or s.guilds.size()>100: return false
	for g in s.guilds:
		if not g is Dictionary or not OnlineWorldClient._uuid(g.get("id")) or not OnlineAccount.valid_nickname(g.get("name","")) or not g.get("announcement") is String or g.announcement.length()>120 or not OnlinePve.integer(g.get("members"),1,50) or not g.get("applied") is bool: return false
	var guild: Variant=s.get("guild")
	if guild!=null:
		if not guild is Dictionary or not OnlineWorldClient._uuid(guild.get("id")) or not OnlineAccount.valid_nickname(guild.get("name","")) or guild.get("role") not in ["leader","member"] or not guild.get("announcement") is String or guild.announcement.length()>120 or not people(guild.get("members"),50) or not people(guild.get("applications"),100): return false
		var leaders:=0;var own:=false
		for m in guild.members:
			if m.get("role") not in ["leader","member"]: return false
			if m.role=="leader": leaders+=1
			if m.id==character_id: own=m.role==guild.role
		if leaders!=1 or not own: return false
	var p: Variant=v.get("profile")
	if p!=null:
		if not person(p) or not OnlinePve.integer(p.get("school"),0,3) or not p.get("combat") is Dictionary or not p.get("equipment") is Dictionary or not p.get("appearance") is Array or p.appearance.size()!=3: return false
		for i in 3:
			if not OnlinePve.integer(p.appearance[i],0,[27,11,9][i]): return false
		for key in ["hp","mp","physical_attack","magic_attack","physical_defense","magic_defense","physical_crit","magic_crit","physical_hit","magic_hit","physical_evasion","magic_evasion","damage_reduction"]:
			if not OnlinePve.integer(p.combat.get(key),0,100000): return false
		for slot in ShopRules.SLOTS:
			if not p.equipment.has(slot): return false
			var item: Variant=p.equipment[slot]
			if item!=null and (not item is String or ShopRules.item(item).get("slot")!=slot): return false
		if request.action=="profile" and p.id!=request.get("target"): return false
		if p.get("guild")!=null:
			var g: Variant=p.guild
			if not g is Dictionary or not OnlineWorldClient._uuid(g.get("id")) or not OnlineAccount.valid_nickname(g.get("name","")) or g.get("role") not in ["leader","member"]: return false
	return true
