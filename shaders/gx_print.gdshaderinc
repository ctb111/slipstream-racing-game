// Printed / painted surfaces of the gimmick pieces (graffiti walls, billboard
// posters, road signs, road paint): an albedo atlas on UV, with photographic
// relief from a tiling detail set on UV2 (metres). Vertex colour multiplies
// the albedo (rgb) and the coverage (a).
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail_nor : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_arm : filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.5; // repeats per metre on UV2
uniform float normal_strength = 0.8;
uniform float rough_base = 0.9;
uniform float rough_detail = 0.4; // how much the detail roughness modulates
uniform float metal = 0.0;
uniform float alpha_mul = 1.0;
uniform float wetness = 0.0;

void fragment() {
	vec4 a = texture(atlas, UV);
	vec2 d_uv = UV2 * detail_scale;
	vec3 arm = texture(detail_arm, d_uv).rgb;
	ALBEDO = a.rgb * COLOR.rgb * mix(1.0, arm.r, 0.5);
	ROUGHNESS = clamp(mix(rough_base, arm.g, rough_detail) - wetness * 0.55, 0.05, 1.0);
	METALLIC = metal;
	NORMAL_MAP = texture(detail_nor, d_uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
#ifdef GX_ALPHA
	ALPHA = clamp(a.a * COLOR.a * alpha_mul, 0.0, 1.0);
#endif
}
