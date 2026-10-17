class_name NpcQuestMarker
extends TextureRect
## Original teach1 identifies a yellow exclamation mark for available quests.
## Reuse that indicator for a claimable reward; do not invent an unseen icon.
var quest_stage := -1

func set_stage(stage: int) -> void:
	if stage == quest_stage: return
	quest_stage = stage
	visible = stage in [0, 2]
	tooltip_text = "可接受任务" if stage == 0 else ("任务可完成，领取奖励" if stage == 2 else "")
