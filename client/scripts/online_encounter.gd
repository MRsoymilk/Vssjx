class_name OnlineEncounter
extends Control
signal action_requested(action: String, target: String)
signal dismissed
var target := ""
var action := ""
var approaching := false
var pve: OnlinePve

func _ready() -> void:
	$Panel/Primary.pressed.connect(func() -> void: action_requested.emit(action, target))
	$Panel/Restore.pressed.connect(func() -> void: action_requested.emit("restore", target))
	$Panel/Close.pressed.connect(func() -> void:
		hide()
		dismissed.emit()
	)

func present(id: String, resident: Dictionary, model: OnlinePve) -> void:
	target = id
	pve = model
	approaching = false
	$Panel/Title.text = resident.name
	show()
	refresh()

func refresh() -> void:
	if pve == null: return
	var npc := target == "qingwei"
	var stage := int(pve.state.get("character", {}).get("quest_stage", 0))
	action = ("claim" if stage == 2 else "accept") if npc else "challenge"
	$Panel/Primary.text = ("领取奖励" if stage == 2 else "领受试炼") if npc else "迎战"
	$Panel/Restore.visible = npc
	$Panel/Primary.visible = true
	if npc and stage in [1, 3]: $Panel/Primary.text = "山狼 %d / 3" % int(pve.state.get("progress", {}).get("kills", 0)) if stage == 1 else "试炼完成"
	$Panel/Primary.disabled = not pve.ready or pve.pending() or approaching or (npc and stage in [1, 3])
	$Panel/Restore.disabled = not pve.ready or pve.pending() or approaching
	var body := pve.quest_text() if npc else "山林之中，妖兽出没。\n准备好便可迎战。\n靠近后开始遭遇战，胜利后获得铜钱与修为。"
	if approaching: body = "正在靠近……\n抵达后自动交互。"
	elif not pve.ready: body = "正在连接服务器，同步角色进度……"
	elif pve.pending(): body = "正在处理，请稍候……\n若连接中断，重连后会确认处理结果。"
	$Panel/Body.text = body
