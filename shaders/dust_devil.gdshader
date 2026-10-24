shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Dust devil (Atmosphere): ~30 soft puffs whirling up a leaning, widening
// column. Each quad's UV2 = (height 0..1, phase); the whirl is all here.
// `life` 0..1..0 fades the whole thing in and out.

uniform float life = 0.0;
uniform float height = 16.0;
uniform vec3 dust_color : source_color = vec3(0.62, 0.52, 0.4);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);

varying float v_h;

void vertex() {
	float h = fract(UV2.x + TIME * 0.12); // puffs rise and recycle
	float ang = UV2.y * 6.2831 + TIME * (4.5 - h * 2.0);
	float r = 0.4 + h * h * 3.5;
	vec3 lean = vec3(sin(TIME * 0.6 + h * 2.0), 0.0, cos(TIME * 0.45 + h * 1.7)) * h * 2.0;
	vec3 centre = vec3(cos(ang) * r, h * height, sin(ang) * r) + lean;
	float size = 0.8 + h * 3.0;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec2 corner = UV * 2.0 - 1.0;
	VERTEX = centre + (right * corner.x - up * corner.y) * size;
	v_h = h;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float soft = smoothstep(1.0, 0.1, dot(p, p));
	float a = soft * life * 0.16 * smoothstep(0.0, 0.08, v_h) * (1.0 - smoothstep(0.6, 1.0, v_h));
	ALBEDO = dust_color * (0.8 + 0.3 * sun_color);
	ALPHA = a;
}
