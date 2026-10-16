class_name RememberedLogin
extends RefCounted
## Opt-in credentials, separate from connection preferences and player saves.
## The random key lives on this device too; this is not an OS credential vault.
var path: String
var last_error := ""

func _init(storage_path: String = "") -> void:
	if not is_supported(): return
	path = storage_path if not storage_path.is_empty() else ServerConnectionSettings.new().settings_path + ".login"

static func is_supported() -> bool:
	# Even a mistakenly injected native context cannot enable browser file access.
	return not OS.has_feature("web") and Platform.is_available() and Platform.context.runtime_config.allows_remembered_login()

func _allowed() -> bool:
	if is_supported() and not path.is_empty(): return true
	last_error = "当前平台不保存账号密码，请重新输入。"
	return false

func load_saved(server: String) -> Dictionary:
	last_error = ""
	if not _allowed(): return {}
	if not FileAccess.file_exists(path): return {}
	var key := FileAccess.get_file_as_bytes(path + ".key") if FileAccess.file_exists(path + ".key") else PackedByteArray()
	if key.size() != 32:
		last_error = "无法读取记住的账号，请重新输入。"
		return {}
	var config := ConfigFile.new()
	if config.load_encrypted(path, key) != OK:
		last_error = "无法读取记住的账号，请重新输入。"
		return {}
	var target := ServerConnectionSettings.normalize(server)
	if not target.ok or target.address == "local" or config.get_value("login", "server", "") != target.address: return {}
	var username: Variant = config.get_value("login", "username", "")
	var password: Variant = config.get_value("login", "password", "")
	if not username is String or not password is String or username.is_empty() or username.length() > 32 or password.is_empty() or password.length() > 128: return {}
	return {"username": username, "password": password}

func remember(server: String, username: String, password: String) -> bool:
	last_error = ""
	if not _allowed(): return false
	var target := ServerConnectionSettings.normalize(server)
	if not target.ok or target.address == "local" or not OnlineAccount.secure_credentials_target(target.address): return false
	var key := PackedByteArray()
	if FileAccess.file_exists(path + ".key"): key = FileAccess.get_file_as_bytes(path + ".key")
	if key.size() != 32:
		key = Crypto.new().generate_random_bytes(32)
		var file := FileAccess.open(path + ".key", FileAccess.WRITE)
		if file == null: return _failed()
		file.store_buffer(key)
		var error := file.get_error()
		file.close()
		if error != OK: return _failed()
	var config := ConfigFile.new()
	config.set_value("login", "server", target.address)
	config.set_value("login", "username", username)
	config.set_value("login", "password", password)
	var error := config.save_encrypted(path + ".tmp", key)
	if error == OK: error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK: return _failed()
	return true

func forget() -> bool:
	last_error = ""
	if not _allowed(): return false
	for file in [path, path + ".tmp", path + ".key"]:
		if FileAccess.file_exists(file) and DirAccess.remove_absolute(file) != OK: return _failed()
	return true

func _failed() -> bool:
	last_error = "记住的账号保存或清除失败，请检查本地目录权限。"
	return false
