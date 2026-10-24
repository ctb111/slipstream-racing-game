shader_type spatial;
render_mode cull_disabled;

// Used circuit tarmac. UV.x: 0 = left edge, 1 = right edge. UV.y: distance / road width.
// Per-vertex data from TrackBuilder: UV2.x = racing line position across the road (0..1),
// COLOR.r = braking zone strength, COLOR.g = corner-exit (traction) strength,
// COLOR.b = corner tightness. Samples: 4 photo textures + 3 detail noise + 2 weather noise.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D albedo2_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // second asphalt, breaks the tiling
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
// RGBA detail noise: r = large blotches, g = medium fbm, b = cellular edges (cracks), a = fine grain
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float road_width = 12.0;
uniform float tile_metres = 3.5;
uniform vec3 paint = vec3(0.78, 0.78, 0.75);
uniform float wetness = 0.0; // 0 dry .. 1 soaked: darker, glossy, puddles
uniform float snow = 0.0; // 0 none .. 1 snowed-in edges, slushy racing line
uniform float base_tone = 0.85; // darken the fairly light scan towards used circuit tarmac
uniform float has_line = 0.0; // 1 when UV2/COLOR carry racing-line data
#include "res://shaders/weather.gdshaderinc"

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 1 inside an axis-aligned rectangle, with a thin seam band at the border.
vec2 rect_mask(vec2 p, vec2 lo, vec2 hi, float seam) {
	vec2 d = min(p - lo, hi - p);
	float m = min(d.x, d.y);
	return vec2(step(0.0, m), step(0.0, m) * (1.0 - step(seam, m)));
}

void fragment() {
	float w = road_width;
	vec2 metres = vec2(UV.x, UV.y) * w; // x across (0..w), y along the lap
	vec2 tuv = metres / tile_metres;
	vec2 tuv2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * metres / 5.3;

	vec4 n1 = mix(vec4(0.5), texture(detail_tex, metres / 110.0), has_line); // neutral if not set up
	vec4 n2 = mix(vec4(0.5), texture(detail_tex, metres / 26.0 + (n1.gr - 0.5) * 0.25), has_line);
	vec4 n3 = mix(vec4(0.5), texture(detail_tex, vec2(metres.x / 3.1, metres.y / 90.0)), has_line); // stretched along the road

	// Two asphalt scans blended by large noise, plus broad tonal variation.
	vec3 a = texture(albedo_tex, tuv).rgb;
	vec3 b = texture(albedo2_tex, tuv2).rgb;
	// Match the second scan's brightness to the first so only texture changes, not tone.
	b *= dot(vec3(0.34), a) / max(dot(vec3(0.34), b), 0.02) * 0.5 + 0.62;
	float ab = smoothstep(0.35, 0.7, n1.r) * has_line;
	vec3 col = mix(a, b, ab * 0.45) * (0.72 + 0.2 * n1.g) * base_tone;
	float rough = texture(rough_tex, tuv).r;
	float nm_depth = 1.0;

	float edge_m = min(UV.x, 1.0 - UV.x) * w;
	float line_u = mix(0.5 + 0.14 * sin(UV.y * 0.09), UV2.x, has_line);
	float d_line = abs(UV.x - line_u) * w; // metres from the racing line
	float brake = COLOR.r * has_line;
	float traction = COLOR.g * has_line;

	// Rubbered-in racing line: a wide dark band with the two tyre lanes darkest.
	float rubber = smoothstep(2.3, 0.4, d_line) * (0.75 + 0.25 * n3.g);
	float lanes = smoothstep(0.55, 0.12, abs(d_line - 0.78)) * (0.6 + 0.4 * n3.a);
	col *= 1.0 - 0.34 * rubber - 0.18 * lanes;
	// Rubber fills the aggregate: smoother, faintly polished (glints in a low sun).
	rough = mix(rough, rough * 0.72, rubber);
	nm_depth *= 1.0 - 0.35 * rubber - 0.2 * lanes;
	// Off line: marbles and dust, a touch lighter.
	col *= 1.0 + 0.07 * smoothstep(3.0, 5.0, d_line) * n2.g;

	// Braking zones and corner exits: dense streaky rubber.
	float streak = smoothstep(0.45, 0.78, n3.a) * smoothstep(1.7, 0.4, abs(d_line - 0.78));
	float skid = streak * (brake * 0.9 + traction * 0.6) + smoothstep(2.8, 0.3, d_line) * brake * 0.25;
	col *= 1.0 - 0.45 * clamp(skid, 0.0, 1.0);

	// Resurfaced full-width strips and rectangular repair patches with sealed seams.
	float cell_l = floor(metres.y / 47.0);
	float hl = hash(vec2(cell_l, 3.7));
	float y0 = cell_l * 47.0 + 6.0 + hl * 20.0;
	vec2 strip = rect_mask(metres, vec2(-1.0, y0), vec2(w + 1.0, y0 + 3.0 + 9.0 * fract(hl * 7.3)), 0.06) * step(hl, 0.14);
	vec2 cell = floor(vec2(metres.x / 4.0, metres.y / 13.0));
	float hp = hash(cell);
	vec2 c0 = cell * vec2(4.0, 13.0);
	vec2 lo = c0 + vec2(0.3 + 1.2 * fract(hp * 13.1), 1.0 + 4.0 * fract(hp * 5.7));
	vec2 hi = lo + vec2(1.2 + 1.6 * fract(hp * 3.3), 1.5 + 5.0 * fract(hp * 9.1));
	vec2 rp = rect_mask(metres, lo, min(hi, c0 + vec2(4.0, 13.0)), 0.05) * step(hp, 0.1);
	float patch_in = max(rp.x, strip.x);
	float seam = max(rp.y, strip.y);
	col = mix(col, col * vec3(0.72, 0.72, 0.74) * (0.9 + 0.2 * n2.a), patch_in * 0.85);
	rough = mix(rough, 0.72, patch_in * 0.5);
	nm_depth *= 1.0 - 0.35 * patch_in;

	// Cracks (thin, dark) in aged regions; tar snakes (sealed cracks, glossy black) elsewhere.
	float cedge = n2.b;
	float aged = smoothstep(0.6, 0.75, n1.g) * (1.0 - patch_in);
	float crack = smoothstep(0.035, 0.008, cedge) * aged;
	float sealed = smoothstep(0.4, 0.3, n1.g) * smoothstep(0.55, 0.7, n1.r) * (1.0 - patch_in);
	float tar = smoothstep(0.04, 0.018, cedge) * sealed;
	// Longitudinal paving joint down the middle, sealed with tar.
	float joint_x = w * 0.5 + (n1.g - 0.5) * 0.9;
	tar = max(tar, smoothstep(0.03, 0.012, abs(metres.x - joint_x)) * step(0.5, n1.r) * step(0.3, n2.g));
	tar = max(tar, seam);
	col = mix(col, col * 0.35, crack);
	col = mix(col, vec3(0.018, 0.018, 0.02), tar * 0.9);
	// Sealant: near-black bitumen, only a little smoother than the asphalt. It
	// must never mirror the sky (bright squiggles at grazing angles).
	rough = mix(rough, max(rough * 0.8, 0.55), tar);
	nm_depth *= 1.0 - 0.3 * tar;

	// Oil and fluid stains, mostly near the racing line.
	float cell_o = floor(metres.y / 23.0);
	float ho = hash(vec2(cell_o, 9.1));
	vec2 oc = vec2((line_u + (fract(ho * 17.3) - 0.5) * 0.35) * w, cell_o * 23.0 + 11.5 + (fract(ho * 3.9) - 0.5) * 16.0);
	float orad = 0.35 + 0.8 * fract(ho * 29.7);
	float oil = smoothstep(orad, orad * 0.35, length((metres - oc) * vec2(1.0, 0.7)) + (n2.a - 0.5) * 0.4) * step(ho, 0.45);
	col = mix(col, col * vec3(0.55, 0.53, 0.5), oil * 0.8);
	rough = mix(rough, 0.35, oil * 0.6);

	// Dusty, dirty edges with grass seeds and grit washed onto the tarmac.
	float dust = smoothstep(0.75, 0.0, edge_m + (n2.g - 0.5) * 0.5);
	col = mix(col, vec3(0.3, 0.28, 0.23) * (0.8 + 0.4 * n2.a), dust * 0.4);
	float seeds = step(0.72, n2.a) * smoothstep(0.7, 0.05, edge_m);
	col = mix(col, vec3(0.3, 0.3, 0.16), seeds * 0.5);
	rough = mix(rough, 0.95, dust * 0.6);

	// Worn, dirty white edge lines with flaking and gaps; tyres wear them where the line runs wide.
	float lx = min(UV.x, 1.0 - UV.x) * w;
	float lw = max(fwidth(lx), 1e-4);
	float line = smoothstep(0.2 - lw, 0.2 + lw, lx) * (1.0 - smoothstep(0.4 - lw, 0.4 + lw, lx)); // anti-aliased
	float flake = smoothstep(0.25, 0.55, n2.a + n1.g * 0.35);
	float gaps = smoothstep(0.18, 0.3, n1.r * 0.5 + n3.g * 0.5);
	float run_over = smoothstep(1.8, 0.4, abs(lx - min(line_u, 1.0 - line_u) * w)) * 0.6;
	float coverage = line * flake * gaps * (1.0 - run_over) * (1.0 - tar);
	vec3 paint_col = paint * (0.82 + 0.18 * n2.g) * mix(vec3(1.0), vec3(0.85, 0.82, 0.74), dust + rubber * 0.5);
	col = mix(col, paint_col, coverage);
	rough = mix(rough, 0.55, coverage);
	nm_depth *= 1.0 - coverage * 0.7;

	// Wet: soaked asphalt goes dark and glossy; puddles collect in the low patches
	// once the surface is really soaked. The racing line dries out first.
	float wet_v = max(wetness, mix(wx_wet_line, wx_wet, smoothstep(1.2, 3.5, d_line)));
	float snow_v = max(snow, wx_snow);
	float out_rough = rough;
	if (wet_v > 0.0) {
		float puddle = smoothstep(0.58, 0.66, texture(noise_tex, metres * 0.02 + 0.3).r) * smoothstep(1.2, 3.0, edge_m);
		puddle = max(puddle, patch_in * smoothstep(0.5, 0.7, n2.g) * 0.8); // repairs sit slightly low
		puddle *= smoothstep(0.45, 0.9, wet_v); // standing water only builds up on a soaked track
		col *= mix(1.0, 0.55, wet_v);
		out_rough = mix(out_rough, mix(0.22 - 0.1 * rubber, 0.03, puddle), wet_v);
		nm_depth *= mix(1.0, 0.25 + 0.75 * (1.0 - puddle), wet_v);
	}

	// Snow: banked up at the edges, patchy slush, cleared in the tyre tracks of the line.
	if (snow_v > 0.0) {
		float edge_snow = smoothstep(2.9, 0.5, edge_m);
		float cleared = smoothstep(0.9, 0.2, abs(d_line - 0.78));
		float slush = smoothstep(0.45, 0.75, texture(noise_tex, metres * 0.05).r) * (1.0 - cleared);
		float snow_mask = clamp(max(edge_snow * (1.0 - cleared * 0.5), slush * 0.7), 0.0, 1.0) * snow_v;
		col = mix(col, vec3(0.86, 0.88, 0.92) * (0.9 + 0.1 * slush), snow_mask);
		out_rough = mix(out_rough, 0.8, snow_mask);
	}

	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, tuv).rgb;
	NORMAL_MAP_DEPTH = nm_depth;
	ROUGHNESS = out_rough;
	SPECULAR = mix(0.4, 0.6, wet_v) * (1.0 - 0.6 * tar * (1.0 - wet_v));
}
