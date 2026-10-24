shader_type spatial;
render_mode cull_disabled;

// Cloth-like flag motion without a simulation. UV2.x = 0 at the pole .. 1 at the
// free end, UV2.y = 0 at the top edge .. 1 at the bottom edge. All flags share
// one merged mesh, so each flag's own data rides in the vertex colour:
// COLOR.rg = direction from the pole (x, z mapped to 0..1), COLOR.b = phase.
// - gravity: in light wind the free end droops and the cloth hangs in folds
// - travelling waves roll from the pole to the tip, growing along the length
// - gusts vary strength over time; the tip flicks fastest
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float wind = 0.5; // 0 calm .. 1 storm
#include "res://shaders/weather.gdshaderinc"
uniform float flag_length = 2.4;

void vertex() {
	float wind_v = max(wind, wx_wind);
	float x = UV2.x;
	float y = UV2.y;
	vec3 dir = normalize(vec3(COLOR.r * 2.0 - 1.0, 0.0, COLOR.g * 2.0 - 1.0));
	vec3 side = normalize(cross(dir, vec3(0.0, 1.0, 0.0)));
	float phase = COLOR.b * 6.2831;
	// Own slow swell plus the travelling gust fronts (flags along a straight
	// stream out one after another as a front passes).
	vec2 wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float gust = 0.45 + 0.35 * sin(TIME * 0.7 + phase) * sin(TIME * 0.23 + phase * 2.0) + 0.7 * wx_gust(wxz, TIME);
	float w = clamp(wind_v * gust, 0.05, 1.2);
	float speed = mix(3.0, 9.0, w);
	float amp = mix(0.1, 0.28, w) * x;
	// Two travelling waves + a fast flutter near the tip.
	float wave = sin(x * 7.0 - TIME * speed + phase) * amp
		+ sin(x * 13.0 - TIME * speed * 1.7 + y * 2.0 + phase) * amp * 0.35
		+ sin(TIME * 23.0 + x * 20.0 + phase) * 0.03 * x * x * w;
	// In calm air the cloth sags towards the pole and hangs down.
	float slack = 1.0 - smoothstep(0.1, 0.8, w);
	vec3 disp = side * wave;
	disp.y -= slack * x * x * flag_length * 0.55;
	disp -= dir * slack * x * flag_length * 0.35;
	VERTEX += disp;
	// Lighting follows the folds.
	NORMAL = normalize(side + dir * cos(x * 7.0 - TIME * speed + phase) * amp * 3.0);
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = ALBEDO * 0.35; // light shines through the cloth
}
