shader_type spatial;
render_mode cull_disabled;

// Coastal-circuit copy of terrain.gdshader: the same grass, plus beach sand
// at the waterline and rock on the cliffs (triplanar, so steep faces don't smear).
// Two photographic grass sets blended by large-scale noise, each sampled at two
// rotated scales so tiling isn't visible. Hills get darker forest patches.
uniform sampler2D a_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float tile = 0.28; // repeats per metre
uniform vec3 tint = vec3(0.68, 0.9, 0.5); // pull the dry scans towards summer green
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float sea_level = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec2 uv1 = wpos.xz * tile;
	vec2 uv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * wpos.xz * tile * 0.31;
	float big = texture(noise_tex, wpos.xz * 0.0025).r;
	float mid = texture(noise_tex, wpos.xz * 0.018).r;
	float m = smoothstep(0.38, 0.62, big);

	vec3 a = mix(texture(a_albedo, uv1).rgb, texture(a_albedo, uv2).rgb, 0.5);
	vec3 b = mix(texture(b_albedo, uv1 * 0.8).rgb, texture(b_albedo, uv2 * 1.3).rgb, 0.5);
	vec3 col = mix(a, b, m) * tint * (0.82 + 0.36 * mid);
	// Patches of drier grass so fields aren't one flat colour.
	float dry = smoothstep(0.55, 0.8, texture(noise_tex, wpos.xz * 0.006 + 0.37).r);
	col = mix(col, col * vec3(1.25, 1.1, 0.8), dry * 0.6);

	// Forest cover on hills, seen from far away.
	// Hills: greener with height, soft-edged forest cover seen from far away.
	float hill = smoothstep(4.0, 40.0, wpos.y);
	col = mix(col, col * vec3(0.75, 0.95, 0.7), hill * 0.6);
	float forest = smoothstep(0.42, 0.72, texture(noise_tex, wpos.xz * 0.0009).r) * hill;
	col = mix(col, vec3(0.05, 0.075, 0.045), forest * 0.7);

	// Beach and cliffs.
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float steep = 1.0 - smoothstep(0.62, 0.86, wn.y);
	vec3 bw = pow(abs(wn), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	float rs = 0.11;
	vec3 rock = texture(rock_albedo, wpos.zy * rs).rgb * bw.x + texture(rock_albedo, wpos.xz * rs).rgb * bw.y + texture(rock_albedo, wpos.xy * rs).rgb * bw.z;
	vec3 rock_n = texture(rock_normal, wpos.zy * rs).rgb * bw.x + texture(rock_normal, wpos.xz * rs).rgb * bw.y + texture(rock_normal, wpos.xy * rs).rgb * bw.z;
	rock = mix(vec3(dot(rock, vec3(0.33))), rock, 0.45) * vec3(0.9, 0.9, 0.88);
	vec3 sand = mix(texture(sand_albedo, wpos.xz * 0.12).rgb, texture(sand_albedo, uv2 * 0.4).rgb, 0.5) * vec3(1.08, 1.02, 0.92);
	float h = wpos.y - sea_level;
	float beach = 1.0 - smoothstep(1.8, 3.4 + mid * 1.5, h);
	float damp = 1.0 - smoothstep(-0.2, 0.6, h);
	float rocky = clamp(steep * smoothstep(-6.0, -1.0, h) + steep * 0.8, 0.0, 1.0) * (1.0 - forest);
	col = mix(col, sand * mix(1.0, 0.62, damp), beach);
	col = mix(col, rock, rocky);
	col = mix(col, col * vec3(0.55, 0.62, 0.6), 1.0 - smoothstep(-5.0, -0.5, h)); // seabed
	float rough = 0.96;
	col *= mix(1.0, 0.62, wetness_v);
	rough = mix(rough, 0.6, wetness_v);

	// Snow lies on flat ground and thins out on steep slopes.
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float flatness = smoothstep(0.55, 0.85, world_n.y);
	float drift = 0.75 + 0.25 * texture(noise_tex, wpos.xz * 0.02).r;
	float cover = snow_v * clamp(flatness * drift + 0.15, 0.0, 1.0);
	col = mix(col, vec3(0.88, 0.9, 0.94) * (0.92 + 0.08 * mid), cover);
	rough = mix(rough, 0.75, cover);

	ALBEDO = col;
	NORMAL_MAP = mix(mix(mix(texture(a_normal, uv1).rgb, texture(b_normal, uv1 * 0.8).rgb, m), texture(sand_normal, wpos.xz * 0.12).rgb, beach), rock_n, rocky);
	NORMAL_MAP_DEPTH = max(1.0 - forest, rocky * 1.5) * (1.0 - cover * 0.8);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
