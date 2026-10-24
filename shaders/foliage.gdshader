shader_type spatial;
render_mode cull_disabled;

#include "res://shaders/weather.gdshaderinc"

// Vertex-coloured trees and bushes that sway in the wind: the whole tree leans
// with the gusts (more towards the top), branch tips flutter on top of that.
uniform float wind_strength = 0.35;
uniform float gust_speed = 0.05;
uniform vec2 wind_dir = vec2(0.85, 0.35);
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float height_scale = 12.0; // typical plant height for the bend curve
uniform vec3 backlight_col = vec3(0.04, 0.06, 0.02);

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = clamp(VERTEX.y / height_scale, 0.0, 1.5);
	float gust = texture(noise_tex, root.xz * 0.004 - wind_dir * TIME * gust_speed).r;
	float sway = sin(TIME * 0.9 + root.x * 0.05 + root.z * 0.07) * 0.35 + (gust - 0.4) * 1.3;
	float flutter = sin(TIME * 4.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + root.x) * 0.06 * h;
	float ws = max(wind_strength, wx_wind);
	vec3 push = vec3(wind_dir.x, 0.0, wind_dir.y) * (sway * h * h * ws + flutter * (0.5 + ws));
	VERTEX += inverse(mat3(MODEL_MATRIX)) * push * height_scale * 0.1;
}

void fragment() {
	// Vertex colours are authored in sRGB.
	vec3 c = COLOR.rgb;
	ALBEDO = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
	ROUGHNESS = 0.92;
	BACKLIGHT = backlight_col;
}
