shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Glare around a street lamp or floodlight: a camera-facing quad with a soft
// radial falloff, pulled a little towards the camera so it isn't cut by the
// lamp housing. Stronger in rain and snow (set from the weather).
uniform vec3 color = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.5;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX.z += 0.6;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = exp(-d * d * 7.0) * 0.8 + exp(-d * 18.0) * 0.6;
	a *= smoothstep(1.0, 0.8, d);
	// Close up the glare shrinks away (the eye is inside it).
	float dist = length(VERTEX);
	a *= smoothstep(3.0, 12.0, dist);
	ALBEDO = color * strength * a;
}
