// Shared body of pbr_triplanar(_2s).gdshader — photographic PBR sets on
// procedural, UV-less geometry. Used through scripts/world/materials.gd (Mats).
//
// Mapping: every flat face gets a planar projection in its OWN frame (u along
// the face horizontally, v up the face / slope), so bricks, planks and roof
// tiles stay upright and unblended on rotated buildings and roof pitches.
// Floors (|n.y| > 0.92) project from above. Curved surfaces (normals varying
// across the pixel) snap to the dominant world axis instead.
//
// Colour: COLOR (sRGB vertex colour, white when absent) x `tint`. In detail
// mode the texture is divided by its mean colour so it only adds pattern and
// variation on top of the vertex / tint colour (tintable plaster, roofs, paint).
// Weathering: large-scale dirt variation, rain streaks on walls, grime near
// the ground (from the terrain heightmap), rain darkening, snow on top faces.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable; // AO, rough, metal
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : hint_default_black, filter_linear, repeat_disable;

uniform float tile_m = 2.0; // metres per texture repeat
uniform vec4 tint : source_color = vec4(1.0);
uniform float detail = 0.0; // 1 = texture only modulates the tint
uniform vec3 mean = vec3(0.5); // mean linear colour of albedo_tex (detail mode)
uniform float contrast = 1.0;
uniform float bright = 1.0;
uniform float rough_mul = 1.0;
uniform float rough_add = 0.0;
uniform float metal_mul = 0.0;
uniform float metal_add = 0.0;
uniform float normal_strength = 1.0;
uniform float ao_strength = 1.0;
uniform float variation = 0.12; // large-scale dirt / fading
uniform float streaks = 0.25; // rain run-off on vertical faces
uniform float grime_h = 0.8; // metres of ground grime
uniform float grime = 0.5;
uniform float porosity = 1.0; // how much rain darkens it
uniform float wet = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;
uniform float has_height = 0.0;
uniform vec2 height_origin = vec2(0.0);
uniform float height_cell = 1.0;
uniform float height_n = 513.0;

varying vec3 wpos;
varying vec3 wnrm;

vec3 srgb_to_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	float wet_v = max(wet, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec3 n = normalize(wnrm) * (FRONT_FACING ? 1.0 : -1.0);
	// Projection frame: the face itself, or the dominant axis on curved parts.
	float curved = step(0.02, length(fwidth(n)));
	vec3 f = n;
	if (curved > 0.5) {
		vec3 a = abs(n);
		f = a.y > max(a.x, a.z) ? vec3(0.0, sign(n.y), 0.0) : (a.x > a.z ? vec3(sign(n.x), 0.0, 0.0) : vec3(0.0, 0.0, sign(n.z)));
	}
	vec3 t = abs(f.y) > 0.92 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), f));
	vec3 b = cross(f, t);
	vec2 m = vec2(dot(wpos, t), -dot(wpos, b)); // metres, v down the image
	vec2 uv = m / tile_m;

	vec3 tex = texture(albedo_tex, uv).rgb;
	vec3 arm = texture(arm_tex, uv).rgb;
	vec3 tn = texture(normal_tex, uv).xyz * 2.0 - 1.0;
	tn.xy *= normal_strength;

	vec3 base = srgb_to_lin(COLOR.rgb) * tint.rgb;
	vec3 col = detail > 0.5 ? base * mix(vec3(1.0), tex / max(mean, vec3(0.01)), contrast) : tex * base * bright;

	// Weathering, all in world metres.
	float g = texture(noise_tex, m * 0.045 + vec2(wpos.y * 0.01)).r;
	col *= mix(1.0 - variation, 1.0 + variation * 0.6, g);
	float wall = 1.0 - smoothstep(0.35, 0.8, abs(n.y));
	float s = texture(noise_tex, vec2(m.x * 0.6, m.y * 0.018)).r;
	float streak = smoothstep(0.5, 0.85, s) * streaks * wall;
	col *= 1.0 - streak * 0.4;
	float rough = clamp(arm.g * rough_mul + rough_add + streak * 0.1, 0.03, 1.0);
	if (has_height > 0.5) {
		vec2 hv = ((wpos.xz - height_origin) / height_cell + 0.5) / height_n;
		float above = wpos.y - texture(height_tex, hv).r;
		float dirt = (1.0 - smoothstep(0.0, grime_h, above + (g - 0.5) * grime_h * 0.8)) * grime;
		col = mix(col, col * vec3(0.5, 0.46, 0.4), dirt);
		rough = mix(rough, min(rough + 0.15, 1.0), dirt);
	}
	float metal = clamp(arm.b * metal_mul + metal_add, 0.0, 1.0);
	col *= mix(1.0, 0.6, wet_v * porosity);
	rough = mix(rough, rough * 0.35, wet_v);
	float cap = snow_v * smoothstep(0.45, 0.8, n.y) * smoothstep(0.25, 0.55, g + 0.12);
	col = mix(col, vec3(0.82, 0.84, 0.88), cap);

	vec3 nw = normalize(t * tn.x + b * tn.y + n * max(tn.z, 0.05));
	nw = normalize(mix(nw, n, cap));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.75, cap);
	METALLIC = metal * (1.0 - cap);
	AO = mix(1.0, arm.r, ao_strength);
	AO_LIGHT_AFFECT = 0.25;
}
