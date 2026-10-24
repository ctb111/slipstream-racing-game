shader_type spatial;
render_mode cull_disabled;

// Gravel trap. UV.x: metres from the trap's inner edge, UV.y: metres along the lap,
// UV2.x: 0 at the inner edge .. 1 at the trap's outer edge, > 1 on the scattered apron.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // coarser pebbles, blended by noise
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile_m = 2.6;
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(float x) {
	return fract(sin(x * 91.7) * 43758.5453);
}

// Pairs of tyre grooves from cars that ran wide, one chance per 26 m of trap.
float grooves(vec2 m) {
	float cell = floor(m.y / 26.0);
	float h = hash(cell);
	float s = m.y - cell * 26.0 - 2.0 * hash(cell + 0.5);
	float centre = s * (0.18 + 0.4 * hash(cell + 0.21)) - 0.5;
	float along = smoothstep(0.0, 2.0, s) * smoothstep(20.0, 8.0, s);
	float pair = smoothstep(0.24, 0.07, abs(abs(m.x - centre) - 0.76));
	return pair * along * step(h, 0.55);
}

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec2 guv = wpos.xz / tile_m;
	vec2 guv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * wpos.xz / (tile_m * 2.7);
	vec4 alb = texture(albedo_tex, guv);
	vec3 alb2 = texture(albedo2_tex, guv2).rgb;
	vec4 n = texture(detail_tex, wpos.xz / 40.0);
	vec3 col = mix(alb.rgb, alb2 * 1.1, smoothstep(0.45, 0.7, n.g) * 0.6) * (0.62 + 0.3 * n.r);
	float groove = grooves(UV);
	col = mix(col, col * 0.55, groove);
	// Stones kicked onto the grass: the apron thins out into single pebbles.
	float apron = max(UV2.x - 1.0, 0.0);
	float lum = dot(alb.rgb, vec3(0.333));
	float keep = lum + n.a * 0.5 - apron * 0.9;
	if (UV2.x > 1.0 && keep < 0.42) {
		discard;
	}
	// Tarmac dust near the inner edge.
	col = mix(col, col * 0.8, smoothstep(0.8, 0.0, UV.x) * 0.5);
	float rough = texture(rough_tex, guv).r;
	col *= mix(1.0, 0.62, wetness_v);
	rough = mix(rough, 0.35, wetness_v);
	float cover = snow_v * clamp(0.75 + 0.35 * n.g - groove * 0.4, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.88, 0.92) * (0.9 + 0.1 * lum), cover);
	rough = mix(rough, 0.8, cover);
	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, guv).rgb;
	NORMAL_MAP_DEPTH = (1.0 - groove * 0.5) * (1.0 - cover * 0.7) * 1.3;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
