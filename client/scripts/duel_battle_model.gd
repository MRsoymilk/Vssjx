class_name DuelBattleModel
extends OnlinePve
var channel: OnlineDuel
var playing := false
func pending() -> bool:
	return playing or channel.pending() or (channel.active() and not channel.can_decide())
