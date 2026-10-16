class_name PlatformTextInputInterface
extends RefCounted
## Focus and composition only. Never inspect, retain or log field contents.

func request_focus(_field: LineEdit, _select_all: bool = false) -> PlatformResult:
	return PlatformResult.unsupported()

func release_focus(_field: LineEdit) -> PlatformResult:
	return PlatformResult.unsupported()

func check_submission(_fields: Array) -> PlatformResult:
	return PlatformResult.unsupported()
