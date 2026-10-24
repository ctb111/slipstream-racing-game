shader_type spatial;
render_mode cull_disabled;

// FIA-style painted kerb. UV.x: 0 at the track edge .. 1 at the outer rounded lip
// (>1 on the drop to the verge). UV.y: distance along the lap in metres.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable; // asphalt/concrete grain
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 colour_a = vec3(0.56, 0.055, 0.045);
uniform vec3 colour_b = vec3(0.8, 0.8, 0.77);
uniform float stripe_m = 1.25;
uniform float kerb_width = 1.1;
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec2 m = vec2(UV.x * kerb_width, UV.y);
	vec3 grain = texture(albedo_tex, m / 2.5).rgb;
	vec4 n = texture(detail_tex, m / vec2(6.0, 40.0));
	vec4 f = texture(detail_tex, m / 3.0 + 0.37);
	// Anti-aliased stripes: a hard step() made the red/white kerbs shimmer and
	// crawl at distance. Fade to the average colour once a stripe is sub-pixel.
	float sy = UV.y / (stripe_m * 2.0);
	float sw = max(fwidth(sy), 1e-4);
	float tri = abs(fract(sy) - 0.5) * 2.0; // 0 at stripe centre .. 1 at the joint
	float stripe = smoothstep(0.5 - sw * 2.0, 0.5 + sw * 2.0, 1.0 - tri);
	stripe = mix(stripe, 0.5, smoothstep(0.15, 0.4, sw));
	vec3 paint = mix(colour_a, colour_b, stripe);
	// Paint over concrete: faded, flaking at the stripe joints, grain showing through.
	float g = dot(grain, vec3(0.333));
	vec3 col = paint * (0.72 + 0.6 * g) * (0.88 + 0.2 * n.g);
	float flake = smoothstep(0.78, 0.9, f.a) * (0.5 + 0.5 * smoothstep(0.08, 0.0, abs(fract(UV.y / stripe_m) - 0.5) - 0.44));
	col = mix(col, grain * 0.9, flake);
	// Rubber: tyre marks strongest on the inner half where cars run over it.
	float tyre = smoothstep(0.55, 0.85, n.a * 0.6 + texture(detail_tex, vec2(m.x / 1.3, m.y / 25.0)).a * 0.6) * smoothstep(0.85, 0.2, UV.x);
	col = mix(col, vec3(0.03), tyre * 0.75);
	col *= 1.0 - 0.25 * smoothstep(0.45, 0.0, UV.x) * n.r; // general grime at the inner edge
	// Dust and grass bits on the outer lip; the drop is dirty concrete.
	float outer = smoothstep(0.7, 1.05, UV.x + (n.g - 0.5) * 0.2);
	col = mix(col, vec3(0.33, 0.3, 0.24) * (0.8 + 0.4 * f.a), outer * 0.6);
	col = mix(col, grain * vec3(0.55, 0.52, 0.46), step(1.0, UV.x));
	float rough = mix(0.5, 0.8, flake + outer * 0.5);
	rough = mix(rough, 0.35, tyre * 0.5);

	col *= mix(1.0, 0.6, wetness_v);
	rough = mix(rough, 0.12, wetness_v);
	float cover = snow_v * clamp(smoothstep(0.35, 0.95, n.r + UV.x * 0.4) + 0.2, 0.0, 1.0);
	col = mix(col, vec3(0.86, 0.88, 0.92), cover);
	rough = mix(rough, 0.8, cover);

	ALBEDO = col;
	NORMAL_MAP = texture(normal_tex, m / 2.5).rgb;
	NORMAL_MAP_DEPTH = 0.45 + flake * 0.5;
	ROUGHNESS = rough;
	SPECULAR = 0.45;
}
