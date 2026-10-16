extends Node2D
var checks := 0
var failures := 0
var impacts := 0
var completions := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	var saved := Game.player.duplicate(true)
	for key in ["hero/mzs", "hero/mck", "hero/mfs", "hero/wzs", "hero/wck", "hero/wfs", "monster/langw", "monster/xt1", "monster/hs1", "monster/nt1"]:
		for side in [1.0, -1.0]:
			var actor := OriginalArt.actor(key)
			add_child(actor)
			actor.position = Vector2(270 if side > 0 else 50, 270)
			actor.scale = Vector2(side * 1.2, 1.2)
			var home := actor.position
			var target := Vector2(50 if side > 0 else 270, 270)
			var info := OriginalArt.actor_info(key)
			var playback := BattleActionPlayback.new()
			impacts = 0
			completions = 0
			playback.impact.connect(func() -> void: impacts += 1)
			playback.completed.connect(func() -> void: completions += 1)
			playback.start(actor, info, target)
			check(actor.position != home and actor.animation == "attack", "Native target basis starts the full attack: " + key)
			check(impacts == 0 and playback.impact_time > 0, "No damage is announced at action start")
			playback.advance(playback.impact_time - 0.001)
			check(impacts == 0, "No early impact before the native event mask")
			playback.advance(0.0011)
			check(impacts == 1 and playback.impacted, "Native event fires exactly on its step")
			var step := int(info.native_battle.impact_steps.attack[0])
			var expected: float = target.x + float(info.native_battle.attack_x[step]) * actor.scale.x
			check(is_equal_approx(actor.global_position.x, expected), "Actual actor follows the source center at impact")
			check(absf(actor.position.x - target.x) < absf(home.x - target.x) * 0.6, "Attack reaches the target instead of retreating")
			check(signf(actor.scale.x) == side and not actor.flip_h, "The attack keeps side and facing")
			playback.advance(10)
			check(not playback.active and actor.position == home and actor.animation == "idle", "Complete source action restores the exact original station")
			check(impacts == 1 and completions == 1, "One reconstructed damage result despite native multihit masks")
			playback.start(actor, info, target)
			playback.cancel()
			check(playback.cancelled and not playback.impacted and actor.position == home, "Cancellation restores home without resolving damage")
			actor.queue_free()
	check(Game.player == saved, "Motion presentation does not modify rules or player data")
	print("NATIVE BATTLE MOTION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
