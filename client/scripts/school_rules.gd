class_name SchoolRules
extends RefCounted
const UNJOINED := 3
const TARGETS := ["emei", "huajian", "kunlun"]
const NAMES := ["峨眉派", "花涧派", "昆仑派", "闲云野鹤"]
static func label(school: int) -> String:
	return NAMES[clampi(school,0,UNJOINED)]
static func index(target: String) -> int:
	return TARGETS.find(target)
