class_name OnlineEconomy
extends RefCounted
signal changed
signal message(text:String)
var pve:OnlinePve
var character_id:=""
var state:Dictionary={}
var request:Dictionary={}
var filters:Dictionary={"scope":"browse","slot":"","quality":"","job":-1,"page":0}
var inflight:=false
var next_poll:=0
const ERRORS:={"EQUIPMENT_BOUND":"该装备已绑定或正在穿戴，不能交易。","AUCTION_CLOSED":"拍卖已成交或到期，请刷新。","AUCTION_HAS_BIDS":"已有出价，不能撤回拍卖。","STALE_AUCTION":"价格已变化，请刷新后重新确认。","BID_TOO_LOW":"出价不足，最低加价5%（至少1铜）。","AUCTION_SELF_BUY":"不能购买自己的拍品。","INVALID_AUCTION_PRICE":"起拍价须为1～10亿，一口价不得低于起拍价。","AUCTION_LIMIT":"最多同时上架20件。","DELIVERY_UNAVAILABLE":"该物品已领取或不属于你。","GOLD_LIMIT":"铜钱达到上限，请先腾出余额。","RANDOM_DROPS_ONLY":"装备全池随机掉落，不支持定向。","CHARACTER_HAS_ESCROW":"请先处理拍卖和待领取物品再删除角色。"}
func bind_model(model:OnlinePve)->void:
	pve=model;character_id=model.character_id
	var saved:Dictionary=OnlineAccount.pending_economy
	if saved.get("server")==OnlineAccount.server_address and saved.get("session")==OnlineAccount.login_session_id and saved.get("request",{}).get("character_id")==character_id:request=saved.request.duplicate(true)
	OnlineAccount.completed.connect(_completed)
func pending()->bool:return not request.is_empty() and request.get("action")!="snapshot"
func detach()->void:
	if OnlineAccount.completed.is_connected(_completed):OnlineAccount.completed.disconnect(_completed)
func fetch()->void:
	if not request.is_empty() or inflight:return
	request=filters.duplicate(true);request.character_id=character_id;request.action="snapshot";next_poll=0
func submit(action:String,values:Dictionary)->bool:
	if not request.is_empty() or inflight or pve.pending() or pve.active():return false
	request=filters.duplicate(true);request.merge(values,true);request.character_id=character_id;request.action=action;request.operation_id=LootRules.uuid()
	OnlineAccount.pending_economy={"server":OnlineAccount.server_address,"session":OnlineAccount.login_session_id,"request":request.duplicate(true)};next_poll=0;changed.emit();return true
func tick()->void:
	if OnlineAccount.busy or inflight or not pve.ready:return
	if Time.get_ticks_msec()<next_poll:return
	if request.is_empty():fetch()
	inflight=true;OnlineAccount.economy_request(request.duplicate(true))
func _completed(action:String,result:Dictionary)->void:
	if action!="economy" or not inflight:return
	inflight=false;next_poll=Time.get_ticks_msec()+5000
	if not valid(result) or not pve.receive({"type":"pve.state","state":result.get("state",{})}):
		var code:String=result.get("code","INVALID_RESPONSE")
		if code in ["UNAUTHORIZED","FORBIDDEN","IDEMPOTENCY_CONFLICT","INVALID_REQUEST","NOT_FOUND"]:
			request={};OnlineAccount.pending_economy={}
		message.emit("交易结果待确认，将按原编号重试。" if pending() else OnlinePve.error_text(code));changed.emit();return
	state=result.market.duplicate(true);request={};OnlineAccount.pending_economy={}
	message.emit("操作已保存；货款、退款和装备在“领取”页。" if result.ok else ERRORS.get(result.code,OnlinePve.error_text(result.code)));changed.emit()
func valid(v:Dictionary)->bool:
	if v.get("character_id")!=character_id or v.get("operation_id")!=request.get("operation_id") or not v.get("ok") is bool or not v.get("code") is String or not v.get("replayed") is bool:return false
	var s:Variant=v.get("market")
	if not s is Dictionary or s.get("version")!=1 or not s.get("listings") is Array or s.listings.size()>20 or not s.get("deliveries") is Array or s.deliveries.size()>50 or not s.get("more") is bool or not OnlinePve.integer(s.get("page"),0,10000):return false
	for listing in s.listings:
		if not listing is Dictionary or not OnlineWorldClient._uuid(listing.get("id")) or not OnlineWorldClient._uuid(listing.get("seller")) or not listing.get("seller_name") is String or not listing.get("revision") is String or not listing.revision.is_valid_int() or int(listing.revision)<1 or listing.get("status") not in ["open","sold","cancelled","expired"]:return false
		if not LootRules.valid_item(listing.get("item"),0,0) or not LootRules.tradable(listing.item):return false
		for key in ["starting_price","buyout","bid"]:
			if not OnlinePve.integer(listing.get(key),0,1000000000):return false
		if listing.starting_price<1 or listing.buyout<listing.starting_price or listing.bid>listing.buyout or (listing.get("bidder")!=null and not OnlineWorldClient._uuid(listing.bidder)):return false
	for delivery in s.deliveries:
		if not delivery is Dictionary or not OnlineWorldClient._uuid(delivery.get("id")) or not OnlinePve.integer(delivery.get("gold"),0,1000000000) or not delivery.get("reason") is String:return false
		if delivery.get("item")!=null and not LootRules.valid_item(delivery.item,0,0):return false
		if (delivery.get("item")!=null)==(int(delivery.gold)>0):return false
	return true
