shader_type canvas_item;

// Swap only the original blue flag palette; keep its outline, highlights and alpha.
void fragment() {
	if (COLOR.b > COLOR.r + 0.15 && COLOR.b > COLOR.g + 0.02) {
		if (COLOR.g > 0.9) COLOR.rgb = vec3(255.0, 242.0, 164.0) / 255.0;
		else if (COLOR.g > 0.8) COLOR.rgb = vec3(255.0, 222.0, 106.0) / 255.0;
		else if (COLOR.g > 0.6) COLOR.rgb = vec3(246.0, 193.0, 57.0) / 255.0;
		else if (COLOR.g > 0.42) COLOR.rgb = vec3(222.0, 151.0, 41.0) / 255.0;
		else COLOR.rgb = vec3(172.0, 112.0, 32.0) / 255.0;
	}
}
