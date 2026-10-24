shader_type spatial;
render_mode cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Road decals in one mesh. COLOR.g selects the kind: 0 = tyre mark strip
// (UV.x across 0..1, UV.y along 0..1), 0.5 = drain grate, 1 = manhole cover
// (UV 0..1 over the quad). COLOR.r = strength, COLOR.b = per-decal seed.
uniform sampler2D detail_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float wetness = 0.0;
#include "res://shaders/weather.gdshaderinc"
uniform float snow = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wetness_v = max(wetness, wx_wet);
	float snow_v = max(snow, wx_snow);
	vec4 n = texture(detail_tex, wpos.xz / 9.0 + COLOR.b * 7.0);
	vec3 col;
	float alpha;
	float rough;
	float metal = 0.0;
	if (COLOR.g < 0.25) {
		// Tyre mark: soft-edged, tread streaks, patchy, fading in and out.
		float across = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
		float tread = 0.75 + 0.25 * sin(UV.x * 31.0 + COLOR.b * 10.0);
		float along = smoothstep(0.0, 0.15, UV.y) * smoothstep(1.0, 0.75, UV.y);
		float patchy = smoothstep(0.05, 0.5, n.g * 0.7 + n.a * 0.5);
		alpha = COLOR.r * across * tread * along * patchy;
		col = vec3(0.012, 0.012, 0.013);
		rough = 0.7;
	} else {
		vec2 q = UV - 0.5;
		if (COLOR.g > 0.75) {
			// Round cast-iron manhole cover with a checker tread and a rim.
			float r = length(q) * 2.0;
			if (r > 1.0) {
				discard;
			}
			vec2 g = fract(q * 9.0);
			float studs = step(0.5, fract(floor(q.x * 9.0) * 0.5 + floor(q.y * 9.0) * 0.5 + 0.25));
			studs = mix(studs, 0.5, smoothstep(0.15, 0.4, max(fwidth(q.x * 9.0), fwidth(q.y * 9.0))));
			float rim = smoothstep(0.84, 0.88, r) * (1.0 - smoothstep(0.95, 1.0, r));
			float gap = smoothstep(0.8, 0.83, r) * (1.0 - smoothstep(0.85, 0.88, r));
			col = vec3(0.1, 0.095, 0.09) * (0.8 + 0.4 * studs * (1.0 - rim));
			col = mix(col, vec3(0.02), gap);
			col = mix(col, col * vec3(1.4, 1.05, 0.8), smoothstep(0.55, 0.8, n.r) * 0.6); // rust
			alpha = 1.0;
			rough = mix(0.75, 0.45, rim);
			metal = 0.4 * (1.0 - gap);
		} else {
			// Rectangular drain grate: iron frame, cross bars over a dark gully.
			vec2 d = 0.5 - abs(q);
			float frame = 1.0 - step(0.06, min(d.x, d.y));
			float by = UV.y * 9.0;
			float bw = max(fwidth(by), 1e-4);
			float bars = smoothstep(0.45 - bw, 0.45 + bw, fract(by));
			bars = mix(bars, 0.55, smoothstep(0.2, 0.5, bw)); // fade fine bars before they alias
			float solid = max(frame, bars);
			col = mix(vec3(0.01), vec3(0.11, 0.1, 0.095) * (0.8 + 0.4 * n.a), solid);
			col = mix(col, col * vec3(1.35, 1.0, 0.75), smoothstep(0.5, 0.8, n.r) * 0.5 * solid);
			alpha = 1.0;
			rough = mix(0.9, 0.6, solid);
			metal = 0.35 * solid;
		}
	}
	col *= mix(1.0, 0.65, wetness_v);
	rough = mix(rough, 0.12, wetness_v);
	alpha *= 1.0 - snow_v * 0.85;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.25;
}
