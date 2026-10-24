shader_type spatial;
render_mode cull_back;

// One photo window / door / shopfront from the FacadeKit atlas on a quad
// (FacadeKit.add_unit). Alpha-scissored at the photo's edge; glass glows at
// night with `lit`.
uniform sampler2D atlas_alb : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float lit = 0.0;
#include "res://shaders/weather.gdshaderinc"

varying float seed;

void vertex() {
	TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = vec3(0.0, 1.0, 0.0);
	vec3 o = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = fract(sin(dot(floor(o.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 a = texture(atlas_alb, UV);
	vec2 msk = texture(atlas_mask, UV).rg;
	ALBEDO = a.rgb * mix(1.0, 0.7, wx_wet * 0.6);
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(atlas_nor, UV).rgb;
	ROUGHNESS = msk.g * mix(1.0, 0.5, wx_wet * 0.6);
	EMISSION = vec3(1.0, 0.72, 0.4) * lit * msk.r * step(0.35, seed);
}
