shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, specular_disabled;

// Looping smoke puffs (TracksideKit): flare smoke, campfire smoke. A MultiMesh of
// 1 m quads; each instance sits at its emitter (identity basis) and the shader
// lifts, drifts, grows and fades it over its life, then it starts again.
// COLOR = smoke colour (alpha = density); INSTANCE_CUSTOM = (phase 0..1,
// size scale, glow 0..1 at the source for flares, life scale).
uniform float rise = 1.1;
uniform float life = 6.0;
uniform vec3 wind_dir = vec3(0.8, 0.0, 0.35);
uniform float wind = 0.5;
#include "res://shaders/weather.gdshaderinc"
uniform sampler2D puff_noise : filter_linear_mipmap, repeat_enable;

varying float age;
varying vec4 tint;
varying float glow;
varying float seed;

void vertex() {
	float ph = INSTANCE_CUSTOM.r;
	float lf = life * max(INSTANCE_CUSTOM.a, 0.2);
	float t = fract(TIME / lf + ph);
	age = t;
	tint = COLOR;
	glow = INSTANCE_CUSTOM.b;
	seed = ph * 17.0 + float(INSTANCE_ID) * 0.37;
	float tl = t * lf;
	vec3 jitter = vec3(sin(seed * 7.1), 0.0, cos(seed * 5.3)) * 0.6 * t;
	float wnd = max(wind, wx_wind * 1.6);
	vec3 wdir = vec3(WX_DIR.x, 0.0, WX_DIR.y);
	vec3 drift = vec3(0.0, rise * tl * (1.0 - 0.25 * t), 0.0) + wdir * (0.5 + 3.0 * wnd) * tl * t * 0.5 + jitter;
	float size = mix(0.35, 2.6, sqrt(t)) * INSTANCE_CUSTOM.g;
	vec3 c = (MODELVIEW_MATRIX * vec4(drift, 1.0)).xyz;
	float a = seed * 3.0 + t * 0.8;
	vec2 q = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * VERTEX.xy;
	VERTEX = c + vec3(q * size, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float n = texture(puff_noise, UV * 0.6 + vec2(seed, seed * 0.7)).r;
	float d = length(uv) + (n - 0.5) * 0.7;
	float a = smoothstep(1.0, 0.25, d);
	a *= smoothstep(0.0, 0.06, age) * (1.0 - age) * (1.0 - age);
	ALBEDO = tint.rgb * mix(0.85, 1.05, n);
	ALPHA = clamp(a * tint.a, 0.0, 1.0);
	EMISSION = tint.rgb * glow * pow(1.0 - age, 6.0) * 3.0;
	ROUGHNESS = 1.0;
	// soften against the ground and hide when nearly faded
	ALPHA *= smoothstep(0.0, 0.6, length(VERTEX) - 0.5);
}
