class_name DuelBattleModel
extends OnlinePve
var channel: OnlineDuel
func pending() -> bool:
	return channel.pending() or (channel.active() and not channel.my_turn())
