extends RefCounted
## Remove small fragments clipped from neighbouring atlas cells, before fitting icons.

static func remove_border_fragments(image: Image) -> int:
	var width := image.get_width()
	var height := image.get_height()
	var visited := PackedByteArray()
	visited.resize(width * height)
	var components: Array = []
	var largest := 0
	for y in height:
		for x in width:
			var start := y * width + x
			if visited[start] or image.get_pixel(x, y).a == 0:
				continue
			var pixels := PackedInt32Array([start])
			visited[start] = 1
			var cursor := 0
			var touches_border := false
			while cursor < pixels.size():
				var position := pixels[cursor]
				cursor += 1
				var px := position % width
				var py := position / width
				touches_border = touches_border or px == 0 or py == 0 or px == width - 1 or py == height - 1
				# Diagonally connected pixels belong to the same pixel-art part.
				for ny in range(maxi(0, py - 1), mini(height, py + 2)):
					for nx in range(maxi(0, px - 1), mini(width, px + 2)):
						var neighbour := ny * width + nx
						if not visited[neighbour] and image.get_pixel(nx, ny).a > 0:
							visited[neighbour] = 1
							pixels.append(neighbour)
			largest = maxi(largest, pixels.size())
			components.append({"pixels": pixels, "border": touches_border})
	var removed := 0
	for component in components:
		# Preserve main silhouettes, paired items and all interior details.
		if not component.border or component.pixels.size() * 10 >= largest:
			continue
		for position in component.pixels:
			image.set_pixel(position % width, position / width, Color.TRANSPARENT)
		removed += component.pixels.size()
	return removed
