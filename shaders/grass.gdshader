shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Verge grass: crossed alpha cards cut from a photo atlas (grass clumps,
// flowers, weeds) in MultiMesh patches. UV = atlas UV, UV2 = (x across the
// card, 0 root .. 1 tip). Sways with a steady wind plus gusts rolling across
// the field; drier patches, wet darkening and snow on the tips.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wind_strength = 0.22;
uniform float gust_speed = 0.06;
uniform vec2 wind_dir = vec2(0.85, 0.35);
uniform vec3 tint = vec3(0.82, 0.88, 0.62); // linear multipliers
uniform vec3 dry_tint = vec3(1.15, 1.02, 0.72);
uniform float snow = 0.0;
uniform float wet = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float alpha_cut = 0.4;
uniform float fade_start = 55.0;
uniform float fade_end = 75.0;

varying float tip;
varying vec3 wpos;
varying float v_front;

void vertex() {
	float wind_strength_v = max(wind_strength, wx_wind * 0.6);
	tip = UV2.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w;
	float gust = texture(noise_tex, w.xz * 0.015 - wind_dir * TIME * gust_speed).r;
	// Gust fronts roll across the field as visible waves (wx_gust).
	v_front = wx_gust(w.xz, TIME);
	float sway = sin(TIME * 2.1 + w.x * 0.4 + w.z * 0.3) * 0.3 + (gust - 0.35) * 1.8 + v_front * 2.2;
	float flick = sin(TIME * 6.0 + w.x * 3.1 + w.z * 2.3) * 0.08;
	vec3 push = vec3(wind_dir.x, -0.25 * abs(sway), wind_dir.y) * (sway + flick) * wind_strength_v * tip * tip * 0.6;
	VERTEX += inverse(mat3(MODEL_MATRIX)) * push;
	// Light the cards like the ground they grow from, with a little lift at the tips.
	NORMAL = normalize(mix(NORMAL, inverse(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0), 0.75));
}

void fragment() {
	float wet_v = max(wet, wx_wet);
	float snow_v = max(snow, wx_snow);
	// Both sides of a card are lit like its front (the vertex normal points up).
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec4 t = texture(atlas, UV);
	// Mip-aware alpha so thin blades don't vanish in the distance, then thin
	// the far edge of the patch out smoothly instead of popping.
	vec2 sz = vec2(textureSize(atlas, 0));
	vec2 dx = dFdx(UV * sz);
	vec2 dy = dFdy(UV * sz);
	float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	ALPHA = t.a * (1.0 + lod * 0.35) * fade;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	float patch = texture(noise_tex, wpos.xz * 0.03).r;
	vec3 col = t.rgb * tint;
	col = mix(col, col * dry_tint, smoothstep(0.55, 0.8, patch) * 0.6);
	col *= mix(0.65, 1.0, smoothstep(0.0, 0.6, tip));
	col *= 1.0 + 0.14 * v_front * tip; // bent blades show their paler sides: the wave reads from afar
	col *= mix(1.0, 0.65, wet_v);
	col = mix(col * mix(1.0, 0.8, snow_v), vec3(0.86, 0.88, 0.92), snow_v * (0.35 + 0.6 * smoothstep(0.2, 0.8, tip)));
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.45, wet_v);
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.2 * tip;
	AO = mix(0.8, 1.0, tip);
	AO_LIGHT_AFFECT = 0.5;
}
