// Rain drops / snow flakes on the inside view of a windscreen (Cockpit).
// Drawn on a quad just inside the glass. Only where the scene behind is well
// beyond the glass (the world outside): pillars, frame and dash stay dry.
// Drops gather over time, run up the glass at speed, and two wipers clear
// what they sweep (same cycle as Cockpit._wipe_pos).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec2 glass_size = vec2(1.3, 0.6); // metres
uniform vec2 wiper_a = vec2(0.22, -0.07); // pivots in UV (0,0 bottom-left)
uniform vec2 wiper_b = vec2(0.7, -0.07);
uniform float wiper_len = 0.55; // metres
uniform float wipe_dir = 1.0; // -1: mirrored wipers (park left, sweep clockwise)
uniform float wipe_time = 0.0;
uniform float wiping = 0.0;
uniform float idle = 0.0; // seconds the wipers have been parked
uniform float rain = 0.0; // 0..1
uniform float snow = 0.0; // 0..1
uniform float speed = 0.0; // 0..1 (~150 km/h)

const float PERIOD = 1.25;
const float SWEEP = 1.0;
const float ANGLE = 1.9;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Seconds since a wiper blade last passed point p (metres, glass space).
float wiped_age(vec2 p, vec2 pivot_uv) {
	vec2 pivot = (pivot_uv - 0.5) * glass_size;
	vec2 d = p - pivot;
	float r = length(d);
	if (r > wiper_len * 1.02 || r < wiper_len * 0.12) {
		return 1e4;
	}
	float a = atan(d.y, d.x * wipe_dir);
	float s = a / ANGLE; // 0 at the parked blade .. 1 at full sweep
	if (s < -0.02 || s > 1.0) {
		return 1e4;
	}
	s = clamp(s, 0.0, 1.0);
	// Blade position: 0.5 - 0.5 cos(2 pi c / SWEEP) for c < SWEEP.
	float c1 = SWEEP / 6.2831853 * acos(1.0 - 2.0 * s); // going out
	float c2 = SWEEP - c1; // coming back
	float c = mod(wipe_time, PERIOD);
	float age;
	if (c >= c2) {
		age = c - c2;
	} else if (c >= c1) {
		age = c - c1;
	} else {
		age = c + PERIOD - c2;
	}
	if (wipe_time < c1) {
		return 1e4; // not reached yet since the wipers started
	}
	return age + idle;
}

// One layer of round drops. xy = refraction offset, z = coverage.
vec3 drops(vec2 p, float cell, float age, float t, float seed, float fill) {
	vec2 q = p / cell;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 r = hash22(id + seed);
	float appear = hash12(id + seed + 7.1);
	if (r.y < 0.62) {
		return vec3(0.0);
	}
	// Each drop lands some time after the last wipe (sooner in heavy rain).
	float land = appear * fill;
	if (age < land) {
		return vec3(0.0);
	}
	float grow = smoothstep(0.0, 0.35, age - land);
	float life = fract(t * (0.03 + r.x * 0.05) + r.y * 5.0); // evaporate / merge away
	float rad = mix(0.08, 0.22, hash12(id + seed + 3.7)) * grow * smoothstep(1.0, 0.85, life);
	vec2 d = f - (r - 0.5) * 0.4;
	d.y *= 1.15; // gravity sag
	float l = length(d);
	float m = smoothstep(rad, rad * 0.7, l);
	return vec3(-d / max(rad, 0.001) * m, m);
}

// Streams pushed up the glass by the airflow.
vec3 runs(vec2 p, float t, float spd, float age) {
	vec2 q = vec2(p.x * 38.0, p.y * 7.0 - t * (1.0 + spd * 5.0));
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 r = hash22(id * 1.37 + 11.0);
	if (r.x < 0.6 || age < r.y * 1.2) {
		return vec3(0.0);
	}
	float cx = (r.y - 0.5) * 0.5;
	float w = mix(0.08, 0.18, r.x);
	float along = 0.35 - f.y; // head at the top of the cell, tail trailing down
	float body = smoothstep(w, w * 0.4, abs(f.x - cx)) * smoothstep(-0.02, 0.05, along) * (1.0 - smoothstep(0.1, 0.8, along));
	float head = smoothstep(w * 1.4, w * 0.6, length(vec2(f.x - cx, (along - 0.04) * 2.5)));
	float m = max(body * 0.5, head);
	return vec3(-(f.x - cx) / w, -0.3, m * m);
}

// Snow flakes: soft irregular blobs that stick, then melt.
float flakes(vec2 p, float cell, float age, float t, float seed, float fill) {
	vec2 q = p / cell;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	vec2 r = hash22(id + seed);
	if (r.y < 0.78) {
		return 0.0;
	}
	float land = hash12(id + seed + 7.1) * fill;
	if (age < land) {
		return 0.0;
	}
	float life = fract(t * (0.04 + r.x * 0.04) + r.y * 5.0);
	float rad = mix(0.07, 0.2, hash12(id + seed + 3.7)) * (1.0 - life * 0.7);
	vec2 d = f - (r - 0.5) * 0.4;
	float ang = atan(d.y, d.x);
	float wob = 1.0 + 0.1 * sin(ang * 3.0 + r.x * 20.0) + 0.06 * sin(ang * 5.0 + r.y * 13.0);
	float l = length(d) / wob;
	return smoothstep(rad, rad * 0.2, l) * (1.0 - life * 0.6);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * glass_size; // metres, y up the glass

	// Dry wherever the glass isn't what we look through (pillar, frame, dash).
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -wp.z / wp.w;
	float my_z = -VERTEX.z;
	float through = smoothstep(0.3, 0.6, scene_z - my_z);

	float age = 1e4;
	if (wipe_time > 0.0) {
		age = min(wiped_age(p, wiper_a), wiped_age(p, wiper_b));
	}
	float t = TIME;
	vec4 col = vec4(0.0);
	if (rain > 0.01) {
		float fill = 3.5 / max(rain, 0.1); // seconds to re-cover a wiped patch
		// At speed the air clears the small beads and drives streams upward.
		float calm = 1.0 - speed * 0.75;
		vec3 a = drops(p, 0.035, age, t, 0.0, fill) * calm;
		vec3 b = drops(p + 0.37, 0.018, age, t * 1.3, 5.0, fill * 0.7) * (calm * 0.8 + 0.2);
		vec3 s = speed > 0.05 ? runs(p, t, speed, age) * smoothstep(0.05, 0.5, speed) : vec3(0.0);
		float cover = clamp(max(max(a.z, b.z * 0.9), s.z * 0.8), 0.0, 1.0) * through * 0.75;
		vec2 bend = (a.xy * a.z + b.xy * b.z * 0.6 + s.xy * s.z * 0.5);
		// A drop is a tiny fisheye: it shows a shrunken, upside-down view, so its
		// lower half catches the (brighter) sky above and its top the road.
		vec2 uv2 = clamp(SCREEN_UV + vec2(bend.x * 0.012, -bend.y * 0.045), vec2(0.0), vec2(1.0));
		vec3 seen = textureLod(screen_tex, uv2, 1.5).rgb;
		// Drops read by their dark edge and a bright spot of sky caught on top.
		float rim = smoothstep(0.3, 0.85, length(bend)) * 0.75;
		float glint = pow(clamp(dot(normalize(vec2(-0.4, 0.9)), bend), 0.0, 1.0), 5.0);
		vec3 sky = textureLod(screen_tex, vec2(SCREEN_UV.x, SCREEN_UV.y * 0.4), 4.0).rgb;
		vec3 dc = seen * (1.0 - rim * 0.6) + sky * glint * 0.35;
		// A fine mist of tiny beads everywhere the blades haven't just been.
		vec3 m = drops(p + 0.11, 0.008, age, t * 0.7, 13.0, fill * 0.5);
		float mist = m.z * 0.12 * calm * through;
		col = vec4(mix(dc, seen * 0.85 + vec3(0.03), mist * (1.0 - cover)), max(cover, mist) * min(rain * 1.5, 1.0));
	}
	if (snow > 0.01) {
		float fill = 8.0 / max(snow, 0.1);
		float slide = t * speed * 0.35; // flakes creep up the glass at speed
		float f = flakes(p + vec2(0.0, -slide), 0.05, age, t, 2.0, fill);
		f = max(f, flakes(p + vec2(0.21, -slide * 1.3), 0.028, age, t * 1.4, 9.0, fill * 0.8) * 0.8);
		f *= through * min(snow * 1.4, 1.0) * 0.7;
		vec3 seen = textureLod(screen_tex, SCREEN_UV, 3.0).rgb;
		vec3 sc = mix(seen, vec3(0.78, 0.8, 0.84) * (0.35 + dot(seen, vec3(0.33)) * 0.8), 0.75);
		col.rgb = mix(col.rgb, sc, f);
		col.a = max(col.a, f * 0.92);
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
}
