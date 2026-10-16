class_name PlatformTextInputInterface
extends RefCounted
## Native focus/composition; Web may mirror a live field to an ephemeral DOM input.
## Never persist, log or expose field contents through config or platform results.

func attach(_owner: Node) -> void:
	pass

func request_focus(_field: LineEdit, _select_all: bool = false) -> PlatformResult:
	return PlatformResult.unsupported()

func release_focus(_field: LineEdit) -> PlatformResult:
	return PlatformResult.unsupported()

func check_submission(_fields: Array) -> PlatformResult:
	return PlatformResult.unsupported()
