class_name PlatformResult
extends RefCounted
## Operation outcome, not a capability flag. Never put credentials in errors.

enum Status { SUCCESS, UNSUPPORTED, DENIED, TEMPORARY_FAILURE, CANCELLED, INVALID_DATA }

var status: Status
var code: String
var message: String
var value: Variant
var ok: bool:
	get: return status == Status.SUCCESS

func _init(result_status: Status, result_code: String, explanation: String = "", data: Variant = null) -> void:
	status = result_status
	code = result_code
	message = explanation
	value = data

static func success(data: Variant = null) -> PlatformResult:
	return PlatformResult.new(Status.SUCCESS, "OK", "", data)

static func unsupported() -> PlatformResult:
	return PlatformResult.new(Status.UNSUPPORTED, "UNSUPPORTED", "当前平台尚不支持此操作。")
