class_name PlatformContext
extends RefCounted
## Static capability snapshot is copied on access; dynamic state lives in ports.

var _target: String
var _storage: PlatformStorageInterface
var _config: PlatformRuntimeConfigInterface
var _display: PlatformDisplayInterface
var _lifecycle: PlatformLifecycleInterface
var _resource_loader: PlatformResourceLoaderInterface
var _text_input: PlatformTextInputInterface
var _system_actions: PlatformSystemActionsInterface

var target: String:
	get: return _target
var storage: PlatformStorageInterface:
	get: return _storage
var runtime_config: PlatformRuntimeConfigInterface:
	get: return _config
var display: PlatformDisplayInterface:
	get: return _display
var lifecycle: PlatformLifecycleInterface:
	get: return _lifecycle
var resource_loader: PlatformResourceLoaderInterface:
	get: return _resource_loader
var text_input: PlatformTextInputInterface:
	get: return _text_input
var system_actions: PlatformSystemActionsInterface:
	get: return _system_actions

func _init(kind: String, storage_port: PlatformStorageInterface, config_port: PlatformRuntimeConfigInterface,
		display_port: PlatformDisplayInterface, lifecycle_port: PlatformLifecycleInterface,
		resource_port: PlatformResourceLoaderInterface, text_port: PlatformTextInputInterface,
		system_port: PlatformSystemActionsInterface) -> void:
	_target = kind
	_storage = storage_port
	_config = config_port
	_display = display_port
	_lifecycle = lifecycle_port
	_resource_loader = resource_port
	_text_input = text_port
	_system_actions = system_port

func capabilities() -> Dictionary:
	return {"native_file_storage": true, "synchronous_storage": true,
		"display_coordinates": true, "lifecycle_events": true, "resource_preparation": true,
		"godot_text_input": true, "exit_application": true, "web_runtime": false}
