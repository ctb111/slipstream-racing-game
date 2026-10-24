shader_type spatial;

// Lake: dark, glossy water with two layers of drifting ripples.
uniform sampler2D ripple_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ripple_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.03, 0.07, 0.08);
uniform float choppiness = 0.5;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.05;
	vec3 n1 = texture(ripple_a, uv + TIME * vec2(0.012, 0.007)).rgb;
	vec3 n2 = texture(ripple_b, uv * 2.3 - TIME * vec2(0.01, 0.018)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = choppiness;
	ALBEDO = deep;
	ROUGHNESS = 0.04 + choppiness * 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
