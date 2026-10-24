shader_type spatial;
render_mode cull_disabled;

// Alpenpass ground (theme_alpine.gd swaps it onto the circuit's ground material,
// so the terrain, the far hills and the backdrop plane all use it):
// the usual two photo grass sets (as terrain.gdshader), plus
//  - mossy rock outcrops (Poly Haven aerial_rocks_02) on steep slopes,
//  - bare grey cliff (rock_08) where it is steeper still,
//  - scree (gray_rocks) above the tree line, snow caps (snow_02) on the peaks.
// Rock is projected on the two vertical planes (no stretching on cliffs).
// Extra samples only where the blend needs them (branches), to keep fps.
uniform sampler2D a_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D a_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cliff_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scree_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 0.28; // repeats per metre (grass)
uniform float rock_tile = 0.045; // repeats per metre (rock)
uniform vec3 tint = vec3(0.68, 0.9, 0.5);
uniform float tree_line = 230.0; // world y where meadow turns to scree
uniform float snow_line = 330.0; // world y where the snow caps start
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	float dry = smoothstep(0.55, 0.8, texture(noise_tex, wpos.xz * 0.006 + 0.37).r);
	col = mix(col, col * vec3(1.18, 1.08, 0.85), dry * 0.45);
	vec3 nmap = mix(texture(a_normal, uv1).rgb, texture(b_normal, uv1 * 0.8).rgb, m);

	vec3 n = normalize(wnrm);
	float h = wpos.y + (mid - 0.5) * 40.0;
	// Dark spruce cover on the lower slopes, seen from afar.
	float hill = smoothstep(30.0, 90.0, wpos.y) * (1.0 - smoothstep(tree_line - 40.0, tree_line, h));
	float forest = smoothstep(0.45, 0.72, texture(noise_tex, wpos.xz * 0.0011).r) * hill;
	col = mix(col, vec3(0.04, 0.065, 0.045), forest * 0.75);

	// Above the tree line: scree, then snow.
	float alp = smoothstep(tree_line - 25.0, tree_line + 25.0, h);
	if (alp > 0.001) {
		vec3 sc = texture(scree_albedo, wpos.xz * 0.06).rgb * vec3(0.95, 0.97, 1.0);
		col = mix(col, sc, alp * (0.55 + 0.45 * mid));
	}
	// Rock on steep ground: triplanar on the vertical planes, xz for the rest.
	float steep = 1.0 - smoothstep(0.62, 0.86, n.y);
	float cliff = 1.0 - smoothstep(0.42, 0.62, n.y);
	if (steep > 0.001) {
		vec3 w = abs(n);
		w = pow(w, vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec2 px = wpos.zy * rock_tile;
		vec2 pz = wpos.xy * rock_tile;
		vec2 py = wpos.xz * rock_tile;
		vec3 moss = texture(moss_albedo, px).rgb * w.x + texture(moss_albedo, pz).rgb * w.z + texture(moss_albedo, py).rgb * w.y;
		vec3 mn = texture(moss_normal, px).rgb * w.x + texture(moss_normal, pz).rgb * w.z + texture(moss_normal, py).rgb * w.y;
		vec3 rock = moss;
		vec3 rn = mn;
		if (cliff > 0.001) {
			vec3 cl = texture(cliff_albedo, px * 1.6).rgb * w.x + texture(cliff_albedo, pz * 1.6).rgb * w.z + texture(cliff_albedo, py * 1.6).rgb * w.y;
			float g = dot(cl, vec3(0.33));
			cl = mix(vec3(g), cl, 0.35) * vec3(1.0, 1.0, 1.04) * 1.15; // limestone grey
			vec3 cn = texture(cliff_normal, px * 1.6).rgb * w.x + texture(cliff_normal, pz * 1.6).rgb * w.z + texture(cliff_normal, py * 1.6).rgb * w.y;
			rock = mix(moss, cl, cliff);
			rn = mix(mn, cn, cliff);
		}
		col = mix(col, rock, steep);
		nmap = mix(nmap, rn, steep);
	}

	float rough = 0.95;
	col *= mix(1.0, 0.62, wetness_v);
	rough = mix(rough, 0.6, wetness_v);

	// Snow caps above the snow line (always), weather snow on flat ground.
	float flatness = smoothstep(0.5, 0.82, n.y);
	float drift = 0.75 + 0.25 * texture(noise_tex, wpos.xz * 0.02).r;
	float cap = smoothstep(snow_line - 30.0, snow_line + 30.0, h + drift * 30.0) * clamp(flatness + 0.35, 0.0, 1.0);
	float cover = max(snow_v * clamp(flatness * drift + 0.15, 0.0, 1.0), cap);
	if (cover > 0.001) {
		vec3 sn = texture(snow_albedo, wpos.xz * 0.08).rgb * 1.05;
		col = mix(col, sn, cover);
		rough = mix(rough, 0.7, cover);
	}

	ALBEDO = col;
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = (1.0 - forest * 0.8) * (1.0 - cover * 0.7);
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
