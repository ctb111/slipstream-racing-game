shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// Fake light shaft of a headlamp: brightest at the lamp, fading along the
// beam and towards the cone's silhouette; soft where it meets the road or a
// car in front (depth fade), and faded out when seen from inside or head-on.
uniform float strength = 0.05;
uniform vec3 color = vec3(1.0, 0.94, 0.82);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

void fragment() {
	float along = UV.y; // 1 at the lamp, 0 at the tip
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(facing, 3.0); // fades well before the silhouette: no hard wedge edges
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -vpos.z / vpos.w;
	float soft = clamp((scene_z - (-VERTEX.z)) / 3.0, 0.0, 1.0);
	float near_fade = clamp((-VERTEX.z - 0.6) / 2.5, 0.0, 1.0);
	float a = strength * along * along * edge * soft * near_fade;
	ALBEDO = color * a;
}
