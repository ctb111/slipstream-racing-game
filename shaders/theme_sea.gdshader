shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

// Open sea for the coastal circuit: two drifting ripple layers plus a long
// swell in the normals, colour from turquoise shallows to deep blue by the
// real water depth, and breaking foam where it meets the shore.
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D foam_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;
uniform vec3 shallow : source_color = vec3(0.14, 0.42, 0.42);
uniform vec3 deep : source_color = vec3(0.015, 0.075, 0.13);
uniform vec3 foam_col : source_color = vec3(0.86, 0.9, 0.9);
uniform float choppiness = 0.55;
uniform float clarity = 5.0; // metres over which the water turns deep

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.035;
	vec3 n1 = texture(ripple_a, uv + TIME * vec2(0.010, 0.006)).rgb;
	vec3 n2 = texture(ripple_b, uv * 2.7 - TIME * vec2(0.008, 0.015)).rgb;
	vec3 n3 = texture(ripple_a, wpos.xz * 0.004 + TIME * vec2(0.002, 0.001)).rgb; // swell
	vec3 nm = normalize(mix(mix(n1, n2, 0.45), n3, 0.35));

	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	float scene_z = -view.z / view.w;
	float water_z = -VERTEX.z;
	float thick = max(scene_z - water_z, 0.0);
	// View-path thickness to vertical depth, roughly.
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float vdepth = thick * clamp(abs(dot(VIEW, up_view)), 0.15, 1.0);

	float t = 1.0 - exp(-vdepth / clarity);
	vec3 col = mix(shallow, deep, t);
	// Foam: a ragged band at the waterline that pulses like breaking waves.
	float fn = texture(foam_noise, wpos.xz * 0.08 + TIME * vec2(0.02, 0.013)).r;
	float fn2 = texture(foam_noise, wpos.xz * 0.21 - TIME * 0.03).r;
	float band = 1.0 - smoothstep(0.0, 0.7 + fn * 0.9, vdepth);
	float surge = 0.6 + 0.4 * sin(TIME * 0.9 + wpos.x * 0.05 + wpos.z * 0.03 + fn * 4.0);
	float foam = smoothstep(0.45, 0.85, band * surge * (0.45 + fn2 * 0.8)) * 0.85;
	// Sparse whitecaps far out.
	float caps = smoothstep(0.78, 0.9, fn * fn2 * 1.9) * t * choppiness;
	foam = max(foam, caps * 0.7);

	ALBEDO = mix(col, foam_col, foam);
	ALPHA = clamp(mix(0.55, 1.0, smoothstep(0.0, 2.5, vdepth)) + foam, 0.0, 1.0);
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = choppiness * (1.0 - foam * 0.7);
	ROUGHNESS = mix(0.03 + choppiness * 0.08, 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
