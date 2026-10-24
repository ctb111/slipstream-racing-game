shader_type spatial;
render_mode cull_disabled;
// Windsock (Atmosphere): a tapered CylinderMesh (capless) bent into shape here.
// Its node sits at the top of the pole, unrotated. Hangs limp in calm air,
// streams out downwind (WX_DIR) as the wind and passing gust fronts rise, and
// flutters along its length. Orange and white bands.
#include "res://shaders/weather.gdshaderinc"

uniform float sock_length = 1.6;
uniform float wind = 0.3;

void vertex() {
	float s = clamp(0.5 - VERTEX.y / sock_length, 0.0, 1.0); // 0 at the mouth .. 1 at the tail
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float ws = max(wind, wx_wind);
	float g = wx_gust(root.xz, TIME);
	float lift = clamp(0.12 + 1.2 * ws + 0.6 * g, 0.0, 1.0);
	vec3 dw = vec3(WX_DIR.x, 0.0, WX_DIR.y);
	float sway = sin(TIME * (1.3 + ws * 2.0)) * 0.25 * (1.0 - lift * 0.5);
	vec3 side0 = normalize(cross(dw, vec3(0.0, 1.0, 0.0)));
	vec3 d = normalize(dw + side0 * sway);
	vec3 axis = normalize(mix(vec3(0.0, -1.0, 0.0), d, lift * (1.0 - 0.3 * s * (1.0 - lift))));
	vec3 p1 = normalize(cross(axis, vec3(0.0, 1.0, 0.0) + side0 * 0.01));
	vec3 p2 = cross(axis, p1);
	float flutter = sin(TIME * (9.0 + 8.0 * ws) - s * 9.0) * 0.06 * s * (0.3 + lift);
	vec2 r = VERTEX.xz;
	VERTEX = axis * s * sock_length + p1 * (r.x + flutter) + p2 * (r.y + flutter * 0.5);
	NORMAL = normalize(p1 * r.x + p2 * r.y + vec3(0.0001));
}

void fragment() {
	float bw2 = max(fwidth(UV.y * 2.5), 1e-4);
	float band = smoothstep(0.5 - bw2, 0.5 + bw2, fract(UV.y * 2.5));
	vec3 orange = vec3(0.85, 0.22, 0.03);
	ALBEDO = mix(orange, vec3(0.85), band) * (FRONT_FACING ? 1.0 : 0.6);
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.25);
}
