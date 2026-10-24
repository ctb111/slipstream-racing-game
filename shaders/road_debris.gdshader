shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Bits blown across the road in gusts (Atmosphere): camera-facing spinning
// sprites; COLOR.a picks the shape (leaf, paper scrap, dust puff).

void vertex() {
	// Billboard keeping the particle's scale and its spin (particle rotation about Z).
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float sc = length(MODEL_MATRIX[0].xyz);
	float a = INSTANCE_CUSTOM.x; // rotation (radians) from the process material
	mat4 spin = mat4(vec4(cos(a), -sin(a), 0, 0), vec4(sin(a), cos(a), 0, 0), vec4(0, 0, 1, 0), vec4(0, 0, 0, 1));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb * spin * mat4(vec4(sc, 0, 0, 0), vec4(0, sc, 0, 0), vec4(0, 0, sc, 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float kind = COLOR.a;
	float m;
	if (kind > 0.66) { // paper scrap
		m = step(abs(p.x), 0.7) * step(abs(p.y), 0.55 + 0.1 * sin(p.x * 9.0));
	} else { // leaf
		float w = (1.0 - p.y * p.y) * 0.6;
		m = step(abs(p.x), w);
	}
	if (m < 0.5) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = COLOR.rgb * 0.5;
}
