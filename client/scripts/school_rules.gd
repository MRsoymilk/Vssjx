class_name SchoolRules
extends RefCounted
const UNJOINED := 3
const TARGETS := ["emei", "huajian", "kunlun"]
const NAMES := ["峨眉派", "花涧派", "昆仑派", "闲云野鹤"]
const MAPS := ["ai_004", "ai_021", "ai_032"]
static func map_id(school: int) -> String:
	return MAPS[school] if school >= 0 and school < MAPS.size() else ""
static func label(school: int) -> String:
	return NAMES[clampi(school,0,UNJOINED)]
static func index(target: String) -> int:
	return TARGETS.find(target)
