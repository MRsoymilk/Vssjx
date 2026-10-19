extends SceneTree

const Cleanup := preload("res://../tools/equipment_icon_cleanup.gd")

func _init() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(5, 10, 8, 16), Color.WHITE)
	image.fill_rect(Rect2i(18, 10, 8, 16), Color.WHITE)
	# A neighbouring cell's clipped foot must not alter the fitted bounds.
	image.fill_rect(Rect2i(12, 0, 5, 1), Color.WHITE)
	# Preserve a small interior decoration and diagonal pixel connections.
	image.set_pixel(15, 15, Color.WHITE)
	image.set_pixel(4, 9, Color.WHITE)
	assert(Cleanup.remove_border_fragments(image) == 5)
	assert(image.get_used_rect() == Rect2i(4, 9, 22, 17))
	assert(image.get_pixel(15, 15).a == 1)
	assert(image.get_pixel(18, 10).a == 1)
	assert(Cleanup.remove_border_fragments(image) == 0, "Cleanup must be repeatable")
	var border_item := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	border_item.fill_rect(Rect2i(0, 0, 4, 8), Color.WHITE)
	assert(Cleanup.remove_border_fragments(border_item) == 0, "Keep main artwork even at cell edges")
	print("Equipment icon cleanup: paired parts, details, border clipping and repeatability passed")
	quit()
