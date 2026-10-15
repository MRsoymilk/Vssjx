class_name ChatEmotePicker
extends PanelContainer
signal chosen(token: String)
signal dismissed
const CATALOG: ChatEmoteCatalog = preload("res://scenes/ui/chat_emotes.tres")

func _ready() -> void:
	$Content/Header/Close.pressed.connect(func() -> void: hide(); dismissed.emit())
	for button in $Content/Grid.get_children():
		button.pressed.connect(func() -> void: chosen.emit(button.tooltip_text))
