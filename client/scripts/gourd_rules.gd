class_name GourdRules
extends RefCounted
## Catalog capacities are shared with Rust; saves contain only remaining supply and the switch.
const HP:="supply/hp_gourd"
const MP:="supply/mp_gourd"
const IDS:=[HP,MP]
const ACTIONS:=["gourd_enable","gourd_disable","gourd_refill_hp","gourd_refill_mp"]

static func valid(value:Variant,gear:Dictionary)->bool:
	if not value is Dictionary or value.size()>2:return false
	for id in value:
		if id not in IDS or id not in gear.get("owned",[]):return false
		var s:Variant=value[id]
		if not s is Dictionary or s.size()!=2 or not s.get("enabled") is bool or not ShopRules._integer(s.get("remaining"),0,int(ShopRules.item(id).capacity)):return false
	for id in IDS:
		if id in gear.get("owned",[]) and (not value.has(id) or ShopRules.quantity(gear,id)!=1):return false
	return true

static func supply(player:Dictionary,limits:Dictionary,blocked:bool)->bool:
	if blocked or player.get("corpse") is Dictionary or int(player.get("hp",0))<=0:return false
	var changed:=false
	for id in IDS:
		var s:Dictionary=player.get("gourds",{}).get(id,{})
		if s.is_empty() or not s.enabled:continue
		var resource:String=ShopRules.item(id).resource
		var amount:=mini(maxi(0,int(limits[resource])-int(player[resource])),int(s.remaining))
		player[resource]=int(player[resource])+amount;s.remaining=int(s.remaining)-amount
		changed=changed or amount>0
	return changed

static func refill_id(action:String)->String:
	return HP if action=="gourd_refill_hp" else MP if action=="gourd_refill_mp" else ""

static func npc_error(target:String,map_id:String,cell:Vector2i)->String:
	var point:=Vector2i(10,13)
	if target=="qingwei":
		if map_id!="qingyun_trail":return "GOURD_NPC_REQUIRED"
	else:
		var resident:=AIWorld.resident(target)
		if not target.ends_with("_guide") or not target.begins_with(map_id) or resident.get("kind")!="npc":return "GOURD_NPC_REQUIRED"
		point=Vector2i(resident.cell[0],resident.cell[1])
	return "RESIDENT_TOO_FAR" if absi(point.x-cell.x)+absi(point.y-cell.y)>2 else ""

static func apply_local(player:Dictionary,action:String,target:String)->String:
	var id:=refill_id(action)
	var refill:=not id.is_empty()
	if refill:
		var map_id:String=player.get("ai_map","")
		if map_id.is_empty():map_id="qingyun_trail" if int(player.zone)==0 else "ancient_ruins"
		var error:=npc_error(target,map_id,Vector2i(player.cell[0],player.cell[1]))
		if not error.is_empty():return error
	else:id=target
	var s:Dictionary=player.get("gourds",{}).get(id,{})
	if s.is_empty():return "GOURD_NOT_OWNED"
	if refill:
		var capacity:=int(ShopRules.item(id).capacity)
		if int(s.remaining)==capacity:return "GOURD_FULL"
		s.remaining=capacity
	else:s.enabled=action=="gourd_enable"
	return ""

static func status(id:String,gourds:Dictionary)->String:
	var s:Dictionary=gourds.get(id,{})
	if s.is_empty():return "未购买"
	return "%d/%d · 自动%s"%[int(s.remaining),int(ShopRules.item(id).capacity),"开" if s.enabled else "关"]
