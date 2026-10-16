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

func check_layer_restore(nested: bool) -> void:
	var stage := Node2D.new()
	add_child(stage)
	var field := Node2D.new()
	stage.add_child(field)
	var receiver := OriginalArt.actor("monster/langw")
	var attacker := OriginalArt.actor("hero/wck")
	var front: Node = receiver
	var back: Node = attacker
	if nested:
		front = Node2D.new()
		back = Node2D.new()
		front.add_child(receiver)
		back.add_child(attacker)
	stage.add_child(back)
	stage.add_child(front)
	var hud := Control.new()
	stage.add_child(hud)
	var order := stage.get_children()
	var playback := BattleActionPlayback.new()
	playback.start(attacker, OriginalArt.actor_info("hero/wck"), receiver.global_position, &"attack", receiver)
	check(back.get_index() > front.get_index() and hud.get_index() > back.get_index(), "Native attacker moves ahead of defender while HUD stays above: nested=" + str(nested))
	playback.cancel()
	check(stage.get_children() == order, "Cancellation restores every sibling index: nested=" + str(nested))
	playback.start(attacker, OriginalArt.actor_info("hero/wck"), receiver.global_position, &"attack", receiver)
	playback.advance(10)
	check(back.get_index() > front.get_index() and hud.get_index() > back.get_index(), "Native completion retains acting-side order until the next action: nested=" + str(nested))
	stage.free()

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
		var battle_actor := OriginalArt.battle_actor(key)
		add_child(battle_actor)
		var metadata := OriginalArt.actor_info(key)
		var base_x := float(metadata.origin[0])
		check(battle_actor.offset.x == base_x + float(metadata.native_battle.pose_x.idle[0]), "Battle idle restores the native anchor: " + key)
		battle_actor.play("hurt")
		battle_actor.pause()
		for frame in battle_actor.sprite_frames.get_frame_count("hurt"):
			battle_actor.set_frame_and_progress(frame, 0.0)
			check(battle_actor.position == Vector2.ZERO and battle_actor.offset.x == base_x + float(metadata.native_battle.pose_x.hurt[frame]), "Source recoil changes the pose without moving its logical station: " + key + "/" + str(frame))
		battle_actor.play("idle")
		check(battle_actor.offset.x == base_x + float(metadata.native_battle.pose_x.idle[0]), "Hurt completion restores the native ready pose: " + key)
		battle_actor.queue_free()
	check_layer_restore(false)
	check_layer_restore(true)
	check(Game.player == saved, "Motion presentation does not modify rules or player data")
	print("NATIVE BATTLE MOTION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
