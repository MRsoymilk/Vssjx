class_name PlatformSystemActionsInterface
extends Node
## Only environment actions. Saving/settlement must happen in the caller first.

func request_exit() -> PlatformResult:
	return PlatformResult.unsupported()
