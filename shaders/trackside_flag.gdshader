shader_type spatial;
render_mode cull_disabled, shadows_disabled;

// Fans' flags on poles (TracksideKit): a subdivided quad in the XY plane, x = 0 at
// the pole .. 1.5 m at the free end, y = 0 bottom .. 1 m top. INSTANCE_CUSTOM =
// atlas rect (x, y, w, h) of the flag design; the wave grows towards the free end.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float wind = 0.4;
#include "res://shaders/weather.gdshaderinc"

void vertex() {
	float free_end = clamp(VERTEX.x / 1.5, 0.0, 1.0);
	vec3 o = MODEL_MATRIX[3].xyz;
	float ph = o.x * 0.37 + o.z * 0.23;
	float wd = max(wind, wx_wind);
	float sp = mix(3.0, 7.0, wd);
	float w = sin(TIME * sp + VERTEX.x * 2.6 + ph) * 0.16 + sin(TIME * sp * 1.7 + VERTEX.x * 4.1 + VERTEX.y * 2.0 + ph) * 0.06;
	float gust = wx_gust(o.xz, TIME);
	VERTEX.z += w * free_end * mix(0.6, 1.6, wd) * (0.6 + 0.8 * gust);
	VERTEX.y -= free_end * free_end * mix(0.25, 0.05, wd); // droops when calm
	NORMAL = normalize(vec3(-cos(TIME * sp + VERTEX.x * 2.6 + ph) * 0.4 * free_end, 0.0, 1.0));
	UV = INSTANCE_CUSTOM.xy + vec2(UV.x, UV.y) * INSTANCE_CUSTOM.zw;
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
