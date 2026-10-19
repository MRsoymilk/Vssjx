class_name WorldSpriteHit
extends RefCounted
## Click visible artwork, not the large transparent rectangle around an actor.
const CACHE_LIMIT := 64
static var _images: Dictionary = {}

static func hit(sprite: AnimatedSprite2D, point: Vector2) -> bool:
	if not is_instance_valid(sprite) or not sprite.is_visible_in_tree() or sprite.sprite_frames == null:
		return false
	var texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if texture == null: return false
	var id := texture.get_instance_id()
	if not _images.has(id):
		if _images.size() >= CACHE_LIMIT: _images.erase(_images.keys()[0])
		var decoded := texture.get_image()
		if decoded != null and decoded.is_compressed(): decoded.decompress()
		_images[id] = decoded
	var image: Image = _images[id]
	if image == null or image.is_empty(): return false
	var pixel := sprite.to_local(point) - sprite.offset
	if sprite.centered: pixel += texture.get_size() * 0.5
	if sprite.flip_h: pixel.x = texture.get_width() - pixel.x
	if sprite.flip_v: pixel.y = texture.get_height() - pixel.y
	# Packed native frames can expose only their cropped image; the drawn
	# texture still includes its original transparent margins.
	if texture is AtlasTexture and image.get_size() != Vector2i(texture.get_size()):
		pixel -= texture.margin.position
	var center := Vector2i(floori(pixel.x), floori(pixel.y))
	# Two source pixels of tolerance help touch input without stealing ground clicks.
	for y in range(maxi(0, center.y - 2), mini(image.get_height(), center.y + 3)):
		for x in range(maxi(0, center.x - 2), mini(image.get_width(), center.x + 3)):
			if image.get_pixel(x, y).a >= 0.2: return true
	return false
