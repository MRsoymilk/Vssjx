extends PlatformStorageInterface

func exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func read_text(path: String, maximum_bytes: int = 1048576) -> PlatformResult:
	if maximum_bytes < 1:
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "INVALID_LIMIT", "读取大小限制无效。")
	if not exists(path):
		return PlatformResult.new(PlatformResult.Status.TEMPORARY_FAILURE, "NOT_FOUND", "本地文件不存在。")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _io_error("READ_FAILED", "无法读取本地文件。", FileAccess.get_open_error())
	if file.get_length() > maximum_bytes:
		file.close()
		return PlatformResult.new(PlatformResult.Status.INVALID_DATA, "TOO_LARGE", "本地文件超过大小限制，原文件已保留。")
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error != OK: return _io_error("READ_FAILED", "本地文件读取不完整。", error)
	return PlatformResult.success(bytes.get_string_from_utf8())

func write_text_atomic(path: String, text: String) -> PlatformResult:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _io_error("WRITE_FAILED", "无法写入本地文件。", FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _io_error("WRITE_FAILED", "本地文件写入失败，原文件已保留。", error)
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return _io_error("REPLACE_FAILED", "无法替换本地文件，原文件已保留。", error)
	# Flush/rename completed, not a promise of power-loss survival or backups.
	return PlatformResult.success({"written": true, "durability": "native_file", "bytes": text.to_utf8_buffer().size()})

func _io_error(code: String, message: String, error: Error) -> PlatformResult:
	var status := PlatformResult.Status.DENIED if error in [ERR_FILE_NO_PERMISSION, ERR_UNAUTHORIZED] else PlatformResult.Status.TEMPORARY_FAILURE
	return PlatformResult.new(status, code, message)
