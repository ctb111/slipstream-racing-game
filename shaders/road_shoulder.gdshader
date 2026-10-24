shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_opaque;

// Dirt/grit verge between the tarmac (or kerb) and the grass. UV.x: metres from
// the road edge, UV.y: metres along the lap. Fades into the terrain outwards.
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float width_m = 1.6;
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec2 duv = wpos.xz / 2.2;
	vec3 dirt = texture(dirt_tex, duv).rgb;
	vec4 n = texture(detail_tex, vec2(UV.x / 4.0, UV.y / 30.0));
	// Desaturate the sandy scan towards grey track grit, darker near the tarmac.
	float lum = dot(dirt, vec3(0.3, 0.55, 0.15));
	vec3 col = mix(vec3(lum), dirt, 0.55) * vec3(0.95, 0.93, 0.86) * (0.75 + 0.35 * n.g);
	col *= mix(0.72, 1.0, smoothstep(0.0, 0.6, UV.x));
	// Grass creeping in: greenish tufts that grow towards the outer edge.
	float tuft = smoothstep(0.45, 0.75, n.a + UV.x / width_m * 0.45 - 0.2);
	col = mix(col, vec3(0.14, 0.18, 0.07) * (0.8 + 0.5 * n.r), tuft * 0.55);
	float edge = UV.x / width_m + (n.r - 0.5) * 0.55 + (n.a - 0.5) * 0.25;
	float alpha = 1.0 - smoothstep(0.45, 0.95, edge);
	alpha *= smoothstep(-0.2, 0.0, UV.x) ;
	float rough = 0.95;
	col *= mix(1.0, 0.55, wetness_v);
	rough = mix(rough, 0.45, wetness_v);
	col = mix(col, vec3(0.87, 0.89, 0.93), snow_v * 0.92);
	rough = mix(rough, 0.8, snow_v);
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	NORMAL_MAP = texture(dirt_normal, duv).rgb;
	NORMAL_MAP_DEPTH = 0.8 * (1.0 - snow_v * 0.8);
	ROUGHNESS = rough;
	SPECULAR = 0.3;
}
