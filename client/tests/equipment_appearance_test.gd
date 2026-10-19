extends Node
const MAPPING := preload("res://scripts/admin/equipment_appearance.gd")
var checks := 0
var failures := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
func _ready() -> void:
	var player := Game.player.duplicate(true)
	for entry in ShopRules.catalog.items:
		if not ShopRules.is_equipment(entry): continue
		var report := MAPPING.describe(entry)
		check(not report["职业与性别对应"].is_empty(), "Every equipment item has applicable appearances: "+entry.id)
		for job in 3:
			for gender in 2:
				var value := MAPPING.variant(entry, job, gender)
				if not ShopRules.equipment_error(entry,job,gender).is_empty():
					check(value.is_empty(), "Job and gender restrictions preserved: "+entry.id)
					continue
				check(not value.is_empty() and OriginalArt.has_actor(value["装备后动画"]), "Uses supported runtime actor: "+entry.id)
				for path in value["部件贴图"].values(): check(ResourceLoader.exists(path), "Mapped part exists: "+path)
				if entry.slot not in ["weapon", "armor", "hat"]: check(value["装备后动画"] == value["装备前动画"], "Stat-only equipment has no invented appearance: "+entry.id)
	check(MAPPING.variant(ShopRules.item("original/iw28"),1,0)["装备后部件"]["武器"] == ["eck1"], "Recovered weapon uses reviewed eck1 mapping")
	check(MAPPING.variant(ShopRules.item("original/if2"),2,1)["装备后部件"]["衣服"] == ["wfs1","wfs1q","wfs1x"], "Original clothing uses runtime body mapping")
	check(MAPPING.variant(ShopRules.item("original/if1"),1,0)["装备后部件"]["头饰"] == ["mckt1"], "Headwear uses current runtime mapping even when visually unchanged")
	check(Game.player == player, "Read-only mapping never changes player equipment")
	print("EQUIPMENT APPEARANCE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
