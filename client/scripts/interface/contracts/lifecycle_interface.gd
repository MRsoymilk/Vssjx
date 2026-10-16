class_name PlatformLifecycleInterface
extends Node
## Reports environment changes only; no saving, login, reconnect or gameplay.
signal changed(event: String)

var focused := true
var suspended := false

func snapshot() -> Dictionary:
	return {"focused": focused, "suspended": suspended}
