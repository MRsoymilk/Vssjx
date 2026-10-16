extends PlatformTextInputInterface
## Use Godot controls first; Web HTML bridging requires separate measured need.

func request_focus(field: LineEdit, select_all: bool = false) -> PlatformResult:
	if not _available(field): return _unavailable()
	if field.focus_mode == Control.FOCUS_NONE:
		return PlatformResult.new(PlatformResult.Status.DENIED, "FOCUS_DISABLED", "当前控件不接受焦点。")
	field.grab_focus()
	if not field.has_focus():
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "FOCUS_FAILED", "暂时无法聚焦输入框，请重试。")
	if select_all: field.select_all()
	return PlatformResult.success()

func release_focus(field: LineEdit) -> PlatformResult:
	if not is_instance_valid(field) or not field.is_inside_tree() or field.is_queued_for_deletion(): return _unavailable()
	# Preserve the control's own focus-exit/IME behavior; do not force apply_ime.
	field.release_focus()
	return PlatformResult.success()

func check_submission(fields: Array) -> PlatformResult:
	if fields.is_empty(): return _unavailable()
	for field in fields:
		if not field is LineEdit or not _available(field): return _unavailable()
		if _is_composing(field):
			return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "INPUT_COMPOSING", "请先确认输入法候选文字，再提交。")
	# Read-only fields can belong to a retry or account-selection form. Business
	# validation/locking stays with the caller, not with this environment port.
	return PlatformResult.success()

func _is_composing(field: LineEdit) -> bool:
	return field.has_ime_text()

func _available(field: LineEdit) -> bool:
	return is_instance_valid(field) and field.is_inside_tree() and not field.is_queued_for_deletion() and field.is_visible_in_tree()

func _unavailable() -> PlatformResult:
	return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INPUT_UNAVAILABLE", "输入框当前不可用。")
