shader_type spatial;
render_mode cull_disabled;
// Fallen leaves on the tarmac (RoadLeaves). One mesh of small flat quads; the
// leaf outline is drawn here (no texture). Cars kick them up: each car's
// position and velocity (cars_p / cars_v, up to 8) lifts and tumbles leaves in
// a short wake behind it, then they settle again. Wet leaves stick down.
// UV2 = corner offset from the leaf centre (m), COLOR.rgb = tint, COLOR.a = seed.
#include "res://shaders/weather.gdshaderinc"

uniform vec4 cars_p[8]; // xyz position, w = 1 if used
uniform vec4 cars_v[8]; // xyz velocity
uniform float wetness = 0.0;
uniform float fade_end = 110.0; // leaves shrink away over the last 45 m (no pop at the range end)

varying float v_seed;
varying float v_lift;

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

void vertex() {
	v_seed = COLOR.a;
	vec3 centre = VERTEX - vec3(UV2.x, 0.0, UV2.y);
	vec3 wc = (MODEL_MATRIX * vec4(centre, 1.0)).xyz;
	vec3 off = vec3(UV2.x, 0.0, UV2.y);
	off *= 1.0 - smoothstep(fade_end - 45.0, fade_end, length(wc - CAMERA_POSITION_WORLD));
	VERTEX = centre + off;
	float stick = 1.0 - 0.8 * max(wetness, wx_wet);
	float lift = 0.0;
	vec3 push = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (cars_p[i].w < 0.5) {
			continue;
		}
		vec3 v = cars_v[i].xyz;
		float spd = length(v);
		if (spd < 6.0) {
			continue;
		}
		vec3 vd = v / spd;
		vec3 rel = wc - cars_p[i].xyz;
		float along = dot(rel, vd);
		float lat = length(rel - vd * along);
		if (along > 2.5 || along < -24.0 || lat > 3.6) {
			continue;
		}
		// Peak just behind the car, dying away in the wake.
		float wake = smoothstep(2.5, 0.0, along) * exp(min(along, 0.0) / (3.0 + spd * 0.1));
		float k = wake * smoothstep(3.6, 1.0, lat) * smoothstep(6.0, 30.0, spd) * stick;
		k *= 0.5 + v_seed;
		lift = max(lift, k);
		vec3 side = normalize(vec3(rel.x - vd.x * along, 0.0, rel.z - vd.z * along) + vec3(0.001));
		push += (vd * 0.35 * (-min(along, 0.0)) * 0.25 + side * 0.8) * k;
	}
	// Gust fronts make the dry ones hop and shuffle downwind a little.
	float gw = wx_gust(wc.xz, TIME) * smoothstep(0.15, 0.6, wx_wind) * stick * step(0.55, v_seed);
	lift = max(lift, gw * 0.3 * v_seed);
	push += vec3(WX_DIR.x, 0.0, WX_DIR.y) * gw * 0.25;
	if (lift > 0.001) {
		// Tumble: spin in the plane and flip about the leaf's own axis.
		float t = TIME * (14.0 + v_seed * 20.0) + v_seed * 50.0;
		off.xz = rot(lift * 6.0 * (v_seed - 0.5) + t * 0.4 * lift) * off.xz;
		off.y = off.x * sin(t) * lift * 1.5;
		off.x *= mix(1.0, cos(t), min(lift * 1.5, 1.0));
		VERTEX = centre + off + vec3(0.0, lift * (0.35 + 0.9 * v_seed), 0.0) + push; // the mesh sits at the origin, unrotated
	}
	v_lift = lift;
}

void fragment() {
	// Leaf outline: a pointed oval with a stem, a midrib and a little bite.
	vec2 p = UV * 2.0 - 1.0;
	float w = (1.0 - p.y * p.y) * mix(0.55, 0.8, fract(v_seed * 7.3)) * (0.85 + 0.15 * sin(p.y * 9.0 + v_seed * 20.0));
	float leaf = step(abs(p.x), w) * step(p.y, 0.95);
	float stem = step(abs(p.x), 0.04) * step(0.85, p.y);
	if (max(leaf, stem) < 0.5) {
		discard;
	}
	float rib = smoothstep(0.06, 0.0, abs(p.x)) * 0.25;
	float veins = smoothstep(0.08, 0.0, abs(fract((p.y + abs(p.x) * 0.8) * 4.0) - 0.5) - 0.42) * 0.12 * step(abs(p.x), w * 0.85);
	vec3 col = COLOR.rgb * (1.0 - rib - veins) * (0.85 + 0.3 * fract(v_seed * 13.1) * (1.0 - abs(p.x)));
	float wet = max(wetness, wx_wet);
	col *= mix(1.0, 0.5, wet);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.25, wet);
	SPECULAR = 0.35;
	BACKLIGHT = col * 0.6; // thin leaves glow against a low sun when tossed up
}
