shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
void fragment() {
    vec4 source = texture(screen_texture, SCREEN_UV);
    float gray = dot(source.rgb, vec3(0.299, 0.587, 0.114));
    COLOR = vec4(vec3(gray * 0.9), 1.0);
}
