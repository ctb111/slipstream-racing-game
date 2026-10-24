shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
// Dust hanging in the air (Atmosphere): tiny specks that are nearly invisible
// until you look towards a low sun, when they light up like in a sunbeam.

uniform vec3 sun_color : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 sun_dir = vec3(0.0, 0.1, -1.0);
uniform float strength = 1.0;

void vertex() {
	// Camera-facing billboard, keep the particle's scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float disc = smoothstep(1.0, 0.0, dot(c, c));
	vec3 ray = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	float fwd = pow(max(dot(ray, normalize(sun_dir)), 0.0), 5.0);
	float dist_fade = smoothstep(1.0, 3.0, -VERTEX.z) * (1.0 - smoothstep(14.0, 24.0, -VERTEX.z));
	ALBEDO = sun_color * disc * dist_fade * strength * (0.03 + fwd * 1.4) * COLOR.a;
}
