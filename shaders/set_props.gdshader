shader_type spatial;

// Set dressing: vertex-coloured merged props. COLOR is sRGB paint colour,
// UV2.x = 1 for printed faces (sampled from the text atlas at UV),
// UV2.y = gloss (0 matte wood/canvas .. 1 painted metal / glass).
// World-space grime breaks up flat colours; rain darkens and slicks,
// snow settles on anything facing up.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grime : filter_linear_mipmap, repeat_enable;
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec3 w = abs(wnrm);
	w /= (w.x + w.y + w.z);
	float g = texture(grime, wpos.zy * 0.23).r * w.x + texture(grime, wpos.xz * 0.23).r * w.y
		+ texture(grime, wpos.xy * 0.23).r * w.z;
	float gloss = UV2.y;
	vec3 col = mix(to_linear(COLOR.rgb), texture(atlas, UV).rgb, UV2.x);
	col *= mix(0.74, 1.1, g) * mix(1.0, 0.9, gloss * (1.0 - g));
	float rough = mix(0.86, 0.3, gloss) + (g - 0.5) * 0.18;
	col *= mix(1.0, 0.7, wetness_v * (1.0 - gloss * 0.5));
	rough = mix(rough, rough * 0.35, wetness_v);
	float cap = snow_v * smoothstep(0.45, 0.8, wnrm.y) * smoothstep(0.2, 0.5, g + 0.15);
	col = mix(col, vec3(0.85, 0.87, 0.91), cap);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(rough, 0.7, cap), 0.05, 1.0);
	METALLIC = gloss * 0.3 * (1.0 - cap);
	SPECULAR = 0.5;
}
