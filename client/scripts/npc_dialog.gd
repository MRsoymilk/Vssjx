class_name OriginalNpcDialog
extends Control
## Paper NPC option list follows the supplied gameplay video's reference frame 11.
signal action_requested(action: String, target: String)
signal dismissed
var target := ""
var model: OnlinePve
var approaching := false
@onready var quest_button: Button = $Paper/Quest
@onready var restore_button: Button = $Paper/Restore
@onready var hint: Label = $Paper/Hint

func _ready() -> void:
	$Dismiss.pressed.connect(dismiss)
	quest_button.pressed.connect(func() -> void:
		if quest_button.disabled or model == null: return
		action_requested.emit("accept" if int(model.state.character.quest_stage) == 0 else "claim", target)
	)
	restore_button.pressed.connect(func() -> void:
		if not restore_button.disabled: action_requested.emit("restore", target)
	)

func present(id: String, resident: Dictionary, pve: OnlinePve) -> void:
	target = id
	model = pve
	approaching = false
	$Paper/Name.text = resident.name
	$Paper/Greeting.text = "小友，山中妖物惊扰行人。"
	show()
	refresh()

func refresh() -> void:
	if model == null or model.state.is_empty(): return
	var stage := int(model.state.character.quest_stage)
	quest_button.text = ["! 山林试炼（接受）", "[已接] 山林试炼（%d/3）" % int(model.state.progress.kills), "! 山林试炼（完成）", "[完成] 山林试炼"][stage]
	var locked := not model.ready or model.pending() or model.active() or approaching
	quest_button.disabled = locked or stage in [1, 3]
	var full := int(model.state.character.hp) == int(model.state.stats.hp) and int(model.state.character.mp) == int(model.state.stats.mp)
	restore_button.disabled = locked or full
	hint.text = "点击任务项接受或完成任务。" if stage in [0, 2] else ("击败山狼后，回来完成试炼。" if stage == 1 else "试炼已完成。")
	if not model.ready: hint.text = "连接中断，正在同步任务结果……"
	elif approaching: hint.text = "正在与道人交谈……"
	elif model.pending():
		var action: String = OnlineAccount.pending_pve.command.action
		hint.text = {"accept":"正在接受任务……", "claim":"正在完成任务……", "restore":"正在恢复元气……"}.get(action, "正在等待回复……")
	elif model.last_action in ["accept", "claim", "restore"] and not model.last_code.is_empty(): hint.text = OnlinePve.error_text(model.last_code)

func dismiss() -> void:
	hide()
	dismissed.emit()
