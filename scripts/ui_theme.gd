class_name OriginalUITheme
extends RefCounted
## Functional page colors confirmed by the user's gameplay video and screenshots.
const COLORS := {
	"scene": {"name": "常规/战斗", "main": "4c80b9", "edge": "80a6d1", "deep": "294d74", "body": "42a5d1", "slot": "226f9b", "bright": "61c8ef"},
	"bag": {"name": "背包", "main": "008b76", "edge": "58d8a4", "deep": "006c58", "body": "05bb91", "slot": "007e68", "bright": "24e6a8"},
	"attributes": {"name": "人物属性", "main": "ff6e55", "edge": "ffd990", "deep": "b53021", "body": "ff7e65", "slot": "c83c25", "bright": "f7d963"},
	"reward": {"name": "奖励", "main": "ad3927", "edge": "e99865", "deep": "74271e", "body": "ff7e65", "slot": "963a2d", "bright": "f58c63"},
	"forge": {"name": "合成", "main": "e9a63b", "edge": "ffd67b", "deep": "a26320", "body": "f7cd78", "slot": "bc863f", "bright": "ffe9a3"}
}

static func palette(page: String = "scene") -> Dictionary:
	var result: Dictionary = COLORS.get(page, COLORS.scene).duplicate()
	for key in ["main", "edge", "deep", "body", "slot", "bright"]: result[key] = Color(result[key])
	return result
