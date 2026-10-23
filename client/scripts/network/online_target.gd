class_name OnlineTarget
extends RefCounted
## Read-only inspection; never touches social/team operation outboxes.
signal changed
signal send_requested(payload:Dictionary)
const RULES=preload("res://scripts/network/online_social.gd")
var character_id:=""
var selected:=""
var profile:Dictionary={}
var request:Dictionary={}
var inflight:=false
var next_poll:=0
var last_code:=""
var received_at:=0

func select(id:String)->void:
	if selected==id:return
	selected=id;profile={};last_code="";received_at=0;next_poll=0;changed.emit()

func clear()->void:select("")

func tick(available:bool)->void:
	if not available or selected.is_empty() or inflight or Time.get_ticks_msec()<next_poll:return
	request={"character_id":character_id,"action":"profile","target":selected}
	inflight=true;send_requested.emit(request.duplicate(true))

func receive(result:Dictionary)->bool:
	if not inflight:return false
	inflight=false
	var target:=String(request.target)
	var rules:=RULES.new();rules.character_id=character_id;rules.request=request
	var accepted:bool=result.get("version")=="social-v1" and rules.valid(result)
	request={}
	if target!=selected:
		next_poll=0;return false
	last_code=String(result.get("code","INVALID_RESPONSE")) if not accepted or not result.ok else ""
	if not accepted and last_code=="OK":last_code="INVALID_RESPONSE"
	if accepted and result.ok and result.profile is Dictionary:
		profile=result.profile.duplicate(true);received_at=Time.get_ticks_msec()
	next_poll=Time.get_ticks_msec()+(3000 if last_code.is_empty() else 5000)
	changed.emit();return accepted
