class_name DuelInvitation
extends Control
signal invite_requested(id: String)
signal reply_requested(action: String)
var channel: OnlineDuel
var selected := ""
var selected_name := ""
var panel: Panel
var caption: Label
var confirm: Button
var reject: Button
const Chrome = preload("res://scripts/social_chrome.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 25
	panel = Chrome.frame(self,Rect2(4,100,218,112),"切磋邀请")
	caption = OriginalSceneChrome.label(panel,"",Rect2(14,36,190,32),12,Chrome.INK)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm = Chrome.placed_button(panel,"确认",Rect2(14,74,84,30))
	reject = Chrome.placed_button(panel,"拒绝",Rect2(120,74,84,30))
	confirm.pressed.connect(func()->void:
		if channel == null: return
		if channel.state.get("incoming") is Dictionary: reply_requested.emit("accept")
		elif not selected.is_empty(): invite_requested.emit(selected)
	)
	reject.pressed.connect(func()->void:
		if channel != null and channel.state.get("incoming") is Dictionary: reply_requested.emit("reject")
		elif channel != null and channel.state.get("outgoing") is Dictionary: reply_requested.emit("cancel")
		else: selected="";hide()
	)
	hide()

func select_player(id: String, display_name: String) -> void:
	selected = id;selected_name = display_name;refresh()

func refresh() -> void:
	if channel == null or not channel.enabled or not channel.connected or channel.active(): hide();return
	var incoming: Variant = channel.state.get("incoming")
	var outgoing: Variant = channel.state.get("outgoing")
	if incoming is Dictionary:
		caption.text = "玩家%s 邀请决斗" % incoming.from_name
		confirm.text = "确认";reject.text = "拒绝"
		confirm.disabled = channel.pending();reject.disabled = channel.pending()
	elif outgoing is Dictionary:
		selected = ""
		caption.text = "已邀请%s，等待对方确认" % outgoing.to_name
		confirm.text = "等待中";reject.text = "取消"
		confirm.disabled = true;reject.disabled = channel.pending()
	elif not selected.is_empty():
		var wait := ceili(channel.cooldown_ms(selected) / 1000.0)
		caption.text = "玩家%s%s" % [selected_name," · 冷却%d秒" % wait if wait > 0 else ""]
		confirm.text = "邀请决斗";reject.text = "取消"
		confirm.disabled = wait > 0 or channel.pending();reject.disabled = false
	else: hide();return
	show()

func _process(_delta: float) -> void:
	if channel != null: refresh()
