shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Exhaust backfire: a short tongue of flame out of the tailpipe (CarFx).
// The quad is a cylindrical billboard around its local +Z (the flame's
// axis), so it reads from the side and from behind. UV.y 1 = pipe, 0 = tip.

instance uniform float flame = 0.0; // 0..1 brightness / length of this flash
instance uniform float seed = 0.0;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - origin);
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 0.05 ? side / sl : normalize(MODEL_MATRIX[0].xyz);
	float len = length(MODEL_MATRIX[2].xyz) * (0.45 + 0.55 * flame);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 world = origin + side * VERTEX.x * wid + axis * (VERTEX.y + 0.5) * len;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	float y = 1.0 - UV.y; // 0 at the pipe .. 1 at the tip
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * 37.0 + seed * 13.0;
	// Flickering, slightly wavy tongue that narrows to the tip.
	float wob = sin(y * 9.0 - t) * 0.12 * y + (hash(floor(t) + seed) - 0.5) * 0.15 * y;
	float w = mix(0.75, 0.05, pow(y, 0.8));
	float body = smoothstep(w, w * 0.3, abs(x + wob));
	body *= smoothstep(0.0, 0.06, y) * smoothstep(1.0, 0.55, y);
	// Hot core near the pipe: blue-white, then yellow-orange, red at the tip.
	vec3 hot = vec3(0.85, 0.8, 1.0);
	vec3 mid = vec3(1.0, 0.55, 0.15);
	vec3 tip = vec3(0.9, 0.18, 0.03);
	vec3 col = mix(hot, mid, smoothstep(0.0, 0.12, y));
	col = mix(col, tip, smoothstep(0.35, 0.9, y));
	float core = smoothstep(0.35, 0.0, abs(x)) * smoothstep(0.4, 0.05, y);
	ALBEDO = (col * body + hot * core * 0.35) * flame * 1.7;
}
