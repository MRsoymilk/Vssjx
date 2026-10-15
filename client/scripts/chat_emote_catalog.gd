class_name ChatEmoteCatalog
extends Resource
## Only these local resources may become inline images. All other text stays literal.
@export var tokens: PackedStringArray
@export var textures: Array[Texture2D]
var _pattern := RegEx.create_from_string("\\[[^\\[\\]]+\\]")

func texture_for(token: String) -> Texture2D:
	var index := tokens.find(token)
	return textures[index] if index >= 0 and index < textures.size() else null

func segments(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cursor := 0
	for match_value in _pattern.search_all(text):
		var token := match_value.get_string()
		var texture := texture_for(token)
		if texture == null: continue
		if match_value.get_start() > cursor: result.append({"text": text.substr(cursor, match_value.get_start() - cursor)})
		result.append({"token": token, "texture": texture})
		cursor = match_value.get_end()
	if cursor < text.length(): result.append({"text": text.substr(cursor)})
	return result

func append_body(label: RichTextLabel, text: String) -> void:
	for part in segments(text):
		if part.has("texture"):
			label.add_image(part.texture, 14, 14, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), null, false, part.token, 0, 0, part.token)
		else: label.add_text(part.text)
