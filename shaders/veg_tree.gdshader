shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/weather.gdshaderinc"

// Procedural trees and bushes (Vegetation): photo foliage atlas with alpha
// cut-out + tiling bark in one surface.
// Vertex data: COLOR.r = flutter weight, COLOR.g = ambient occlusion,
// COLOR.b = 0 foliage / 0.5 bark column 0 / 1 bark column 1, COLOR.a = branch
// weight (0 trunk .. 1 branch tip); UV2.x = branch phase, UV2.y = tree height.
// Far LOD (`merged`): every tree of a cell baked into one mesh in world space,
// CUSTOM0 = (tree root xyz, instance scale).
//
// Wind, from slow to fast:
//  1. trunk sway: the whole tree bends downwind with the square of its height
//     fraction, at a natural rate that is slower for taller trees, plus a
//     sideways figure-of-eight component;
//  2. gusts: a noise field sweeping across the forest along the wind scales the
//     lean and the swing, so gust fronts visibly roll through the stands;
//  3. branch bob: each branch (own phase) bounces and is dragged downwind by
//     its weight squared;
//  4. flutter: needles/leaves shiver along their normals.

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D leaf_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
// Dense leaf-mass atlas of the baked tree models (tools/trees): their foliage
// UVs are shifted by +2 in u (u > 1.5 = sample clump_tex at UV - (2, 0)).
uniform sampler2D clump_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D clump_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wind_strength = 0.3; // 0 calm, 0.3 breezy, 0.9 storm
uniform float gust_speed = 0.05;
uniform vec2 wind_dir = vec2(0.85, 0.35);
uniform float branch_amp = 0.5; // metres at a branch tip in a full gust
uniform float flutter_amp = 1.0;
uniform bool merged = false;
uniform vec3 tint = vec3(1.0); // linear multipliers
uniform float tint_variation = 0.18;
uniform vec3 bark_tint = vec3(1.0);
uniform float snow = 0.0;
uniform float wet = 0.0;
uniform float alpha_cut = 0.45;
uniform float translucency = 0.35;
uniform float normal_depth = 1.0;
// Autumn (0 summer .. 1 full autumn): per-tree yellow/orange/red/brown foliage,
// a few still green, some trees half bare (leaf cards punched with holes).
uniform float autumn = 0.0;

varying float v_bark;
varying float v_barkcol;
varying float v_ao;
varying vec3 v_var;
varying vec3 v_wnormal;
varying vec3 v_wpos;
varying vec2 v_aut;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 root;
	float sc;
	if (merged) {
		root = CUSTOM0.xyz;
		sc = CUSTOM0.w;
	} else {
		root = MODEL_MATRIX[3].xyz;
		sc = length(MODEL_MATRIX[1].xyz);
	}
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = normalize(mat3(MODEL_MATRIX) * NORMAL);
	float H = max(UV2.y * sc, 1.0);
	float above = max(wpos.y - root.y, 0.0);
	float hf = clamp(above / H, 0.0, 1.25);
	vec2 wd = normalize(wind_dir);
	vec2 cross_dir = vec2(-wd.y, wd.x);
	// Live weather (changeable conditions) never goes below the build-time preset.
	float ws = max(wind_strength, wx_wind);
	float gspeed = max(gust_speed, 0.03 + ws * 0.07);
	float t = TIME;
	float rh = hash(root.xz);

	// Gust field rolling downwind across the forest.
	vec2 guv = root.xz * 0.0035 - wd * t * gspeed;
	float g = texture(noise_tex, guv).r * 0.65 + texture(noise_tex, guv * 2.7 + vec2(0.37, 0.61) - wd * t * gspeed * 1.4).r * 0.35;
	float gust = smoothstep(0.32, 0.72, g);

	// 1+2. Trunk: steady lean + swing at the tree's natural rate.
	float w0 = 3.4 / sqrt(H);
	float swing = sin(t * w0 + rh * 6.283) * (0.3 + 0.7 * gust) + sin(t * w0 * 2.13 + rh * 17.0) * 0.2;
	float wsm = max(ws, 0.16); // gentle floor: trees never freeze on calm days
	float along = ws * (0.3 + 1.2 * gust) + wsm * swing * 0.9;
	float across = ws * sin(t * w0 * 0.77 + rh * 11.0) * (0.12 + 0.3 * gust);
	// Storms bend whole trees hard; calm days still breathe a little.
	float k = H * 0.022 * (0.6 + ws * 2.2);
	vec2 off = (wd * along + cross_dir * across) * k * hf * hf;
	vec3 disp = vec3(off.x, -dot(off, off) * 0.5 / max(above, 0.5), off.y);

	// 3. Branches bob (up/down and downwind), each on its own phase.
	float bw = COLOR.a * COLOR.a;
	float bph = UV2.x * 6.283 + rh * 5.0;
	float bob = sin(t * (1.7 + UV2.x * 1.3) * (0.8 + ws * 0.9) + bph) * 0.75 + sin(t * 4.3 + bph * 2.3) * 0.25 * ws;
	float bscale = branch_amp * clamp(H / 14.0, 0.35, 1.2) * wsm * (0.3 + 0.7 * gust) * (0.5 + ws * 1.3);
	disp += (vec3(0.0, bob * 0.7, 0.0) + vec3(wd.x, 0.0, wd.y) * (0.55 + 0.45 * bob)) * bw * bscale;

	// 4. Leaves/needles flutter.
	float fph = dot(wpos, vec3(1.9, 1.1, 1.5)) + rh * 20.0;
	float ff = 6.0 + ws * 9.0;
	float fl = sin(t * ff + fph) * 0.6 + sin(t * ff * 1.63 + fph * 1.7) * 0.4;
	disp += (wn * 0.7 + vec3(wd.x, 0.3, wd.y) * 0.5) * fl * COLOR.r * flutter_amp * (0.02 + wsm * 0.08 * (0.4 + gust));

	// Back to model space; instance bases are rotation x per-axis scale, so the
	// inverse is each column divided by its squared length.
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += vec3(dot(m[0], disp) / dot(m[0], m[0]), dot(m[1], disp) / dot(m[1], m[1]), dot(m[2], disp) / dot(m[2], m[2]));

	v_bark = step(0.25, COLOR.b);
	v_barkcol = step(0.75, COLOR.b);
	v_ao = COLOR.g;
	float r = hash(floor(root.xz * 0.7));
	float r2 = hash(floor(root.zx * 1.3) + 7.0);
	v_var = vec3(1.0 + (r - 0.5) * tint_variation * 1.4, 1.0 + (r2 - 0.5) * tint_variation, 1.0 + (r - 0.5) * tint_variation * 0.6) * (1.0 - (r2 - 0.5) * tint_variation);
	v_wnormal = wn;
	v_wpos = wpos + disp;
	v_aut = vec2(hash(root.xz * 0.37 + 3.1), hash(root.zx * 0.91 + 9.2));
}

void fragment() {
	float wet_v = max(wet, wx_wet);
	float snow_v = max(snow, wx_snow * 0.85);
	vec3 col;
	float rough;
	if (v_bark > 0.5) {
		vec2 buv = vec2((fract(UV.x) + v_barkcol) * 0.5, UV.y);
		vec2 g = UV * vec2(0.5, 1.0);
		col = textureGrad(bark_tex, buv, dFdx(g), dFdy(g)).rgb * bark_tint;
		NORMAL_MAP = textureGrad(bark_normal, buv, dFdx(g), dFdy(g)).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
		rough = 0.9;
		ALPHA = 1.0;
	} else {
		// Foliage cards carry rounded crown normals: light both sides the same.
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;
		}
		bool cl = UV.x > 1.5;
		vec2 fuv = cl ? UV - vec2(2.0, 0.0) : UV;
		vec2 gx = dFdx(fuv);
		vec2 gy = dFdy(fuv);
		vec4 t = cl ? textureGrad(clump_tex, fuv, gx, gy) : textureGrad(leaf_tex, fuv, gx, gy);
		// Keep thin needles/leaves from fading out in the smaller mips.
		vec2 sz = vec2(cl ? textureSize(clump_tex, 0) : textureSize(leaf_tex, 0));
		vec2 dx = gx * sz;
		vec2 dy = gy * sz;
		float lod = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
		ALPHA = t.a * (1.0 + lod * 0.3);
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
		// Alpha to coverage on the cut edge (with MSAA): soft leaf outlines, no jaggies.
		ALPHA_ANTIALIASING_EDGE = 0.25;
		ALPHA_TEXTURE_COORDINATE = fuv * sz;
		col = t.rgb * tint * v_var;
		if (autumn > 0.0) {
			float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
			float lv = texture(noise_tex, v_wpos.xz * 0.11 + v_wpos.y * 0.07).r;
			float h = fract(v_aut.x + (lv - 0.5) * 0.35); // a crown drifts through neighbouring hues
			vec3 aut = h < 0.3 ? mix(vec3(0.95, 0.66, 0.1), vec3(0.98, 0.42, 0.05), h / 0.3) // yellow -> orange
				: h < 0.55 ? mix(vec3(0.98, 0.42, 0.05), vec3(0.72, 0.12, 0.04), (h - 0.3) / 0.25) // orange -> red
				: h < 0.92 ? mix(vec3(0.62, 0.3, 0.07), vec3(0.95, 0.75, 0.15), (h - 0.55) / 0.37) // rust -> birch yellow
				: mix(vec3(0.85, 0.55, 0.12), vec3(0.45, 0.48, 0.12), (h - 0.92) / 0.08); // a few still turning
			col = mix(col, aut * (lum * 1.5 + 0.03) * v_var, autumn);
			// Some trees are half bare: punch holes in their leaf cards.
			float bare = autumn * smoothstep(0.5, 1.0, v_aut.y) * 0.8;
			float holes = texture(noise_tex, v_wpos.xz * 0.23 + vec2(v_wpos.y * 0.19)).r;
			ALPHA *= step(bare, holes * 1.15 - 0.08);
		}
		NORMAL_MAP = cl ? textureGrad(clump_normal, fuv, gx, gy).rgb : textureGrad(leaf_normal, fuv, gx, gy).rgb;
		NORMAL_MAP_DEPTH = 0.6 * normal_depth;
		rough = 0.85;
		// Light through the leaves (strongest on the sunlit outer shell).
		BACKLIGHT = col * translucency * (0.6 + 0.6 * v_ao) * (1.0 - wet_v * 0.5);
		// Sunlit outer leaves a touch lighter and warmer, deep inside darker.
		col *= mix(vec3(0.55, 0.58, 0.6), vec3(1.08, 1.06, 0.98), smoothstep(0.25, 1.0, v_ao));
	}
	if (v_bark > 0.5) {
		col *= mix(0.5, 1.0, v_ao);
	}
	// Wet: darker, glossier.
	col *= mix(1.0, 0.62, wet_v);
	rough = mix(rough, 0.45, wet_v);
	// Snow settles on the upward-facing parts.
	float n = texture(noise_tex, v_wpos.xz * 0.35 + v_wpos.y * 0.2).r;
	float up = v_wnormal.y;
	float s = snow_v * smoothstep(0.1, 0.55, up * 0.8 + (n - 0.5) * 0.7 + (v_bark > 0.5 ? -0.25 : 0.2));
	col = mix(col, vec3(0.86, 0.88, 0.92), s * 0.92);
	rough = mix(rough, 0.7, s);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
