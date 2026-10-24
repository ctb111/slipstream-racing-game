shader_type spatial;
render_mode cull_disabled;

// Animals and birds of the Wildlife kit (scripts/world/wildlife.gd). All
// motion is baked in here: the script only writes an event time now and then.
// Mesh (normalised by assets/wildlife/bake/bake_animals.py): feet at the
// origin, head towards -Z. Per vertex CUSTOM0 = (head weight, leg weight,
// tail weight, leg phase 0..1 (diagonal pairs) / for flying birds: signed
// wing weight -1 left tip .. 1 right tip).
// Per instance INSTANCE_CUSTOM = (id 0..1, event time t0 (on the `now`
// clock, 0 = none), a, b); COLOR = tint (flying birds: plumage).
//   kind 0 grazer / 5 dog : a = run distance (m, the animal was moved to the
//                            end point and runs in from +Z), b = height step
//   kind 1 perched bird   : hidden from t0 on (its flying copy takes over)
//   kind 2 soaring bird   : origin = circle centre; a = radius, b = angular speed (rad/s, signed)
//   kind 3 fleeing bird   : flies off along -Z from t0 for FLEE_T s
//   kind 4 sitting cat    : -

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform bool has_tex = true;
uniform int kind = 0;
uniform float now = 0.0; // the kit's clock (s), set by the script
uniform vec3 size = vec3(0.6, 1.4, 2.4); // model extents (width, height, length)
uniform float graze = 1.0; // 0 never lowers the head .. 1 grazes a lot
uniform float tail_amp = 0.06;
uniform float tail_speed = 1.6;
uniform float run_speed = 9.0; // m/s while running in
uniform float stride = 0.35; // leg swing (m at the hoof)
uniform float gait_hz = 2.2;
uniform int paint = 0; // 0 texture, 1 red deer coat, 2 flying bird (COLOR + wing pattern)
uniform vec3 wing_col : source_color = vec3(0.5);
uniform float flap_hz = 3.2;
uniform float glide = 0.5; // share of the time spent gliding (soaring birds)
uniform float flip_fly = 1.0; // -1 if the flying mesh's head is at +Z

const float FLEE_T = 9.0;

varying vec3 mpos; // model position before animation (for painting)
varying float wing;

float hash(float x, float k) {
	return fract(sin(x * 91.3458 + k * 47.123) * 43758.5453);
}

vec3 rot_x(vec3 v, float a) {
	return vec3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a));
}

vec3 rot_y(vec3 v, float a) {
	return vec3(v.x * cos(a) + v.z * sin(a), v.y, -v.x * sin(a) + v.z * cos(a));
}

vec3 rot_z(vec3 v, float a) {
	return vec3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z);
}

// Wing beat for a flying bird mesh (wings along X).
vec3 flap(vec3 v, float w, float beat, float amp) {
	float aw = abs(w);
	v.y += pow(aw, 1.3) * amp * size.x * 0.5 * beat;
	v.x *= 1.0 - 0.08 * aw * max(beat, 0.0);
	return v;
}

void vertex() {
	mpos = VERTEX;
	wing = CUSTOM0.w;
	float id = INSTANCE_CUSTOM.r;
	float t0 = INSTANCE_CUSTOM.g;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float H = size.y;
	float L = size.z;
	float hw = CUSTOM0.x;
	float lw = CUSTOM0.y;
	float tw = CUSTOM0.z;
	float t = now + id * 97.0;
	if (kind == 0 || kind == 5) {
		float s = t0 > 0.0 ? (now - t0) * run_speed / max(INSTANCE_CUSTOM.b, 0.01) : 2.0;
		bool moving = s >= 0.0 && s < 1.0;
		if (moving) {
			float ph = (now - t0) * gait_hz * 6.2831;
			// Legs swing about the hip in diagonal pairs, hooves lift on the way forward.
			float sw = sin(ph + CUSTOM0.w * 6.2831);
			v.z += sw * stride * lw;
			v.y += max(-cos(ph + CUSTOM0.w * 6.2831), 0.0) * stride * 0.45 * lw;
			// Bounding body, head up.
			v.y += abs(sin(ph)) * H * 0.05;
			v = rot_x(v - vec3(0.0, H * 0.5, 0.0), sin(ph) * 0.05) + vec3(0.0, H * 0.5, 0.0);
			// Still behind its end point (the instance origin): run in along -Z.
			float rest = 1.0 - s;
			v.z += INSTANCE_CUSTOM.b * rest;
			v.y -= INSTANCE_CUSTOM.a * rest;
		} else if (kind == 0) {
			// Grazing: the head goes down for a while, comes up to look around.
			float g = smoothstep(0.1, 0.5, sin(t * 0.11 + id * 40.0) + 0.3) * graze;
			vec3 piv = vec3(0.0, H * 0.62, -L * 0.28);
			float a = -g * 0.95 + (1.0 - g) * sin(t * 0.4) * 0.08;
			v = mix(v, piv + rot_x(v - piv, a), hw);
			n = normalize(mix(n, rot_x(n, a), hw));
			// Chewing / ear flick, breathing.
			v.y += hw * sin(t * 5.0) * 0.006 * g;
			v.x *= 1.0 + sin(t * 1.3) * 0.012 * (1.0 - lw);
		} else {
			// Dog: sniffing now and then, panting, head turns.
			float sn = smoothstep(0.6, 0.9, sin(t * 0.23 + id * 30.0));
			vec3 piv = vec3(0.0, H * 0.7, -L * 0.3);
			v = mix(v, piv + rot_y(rot_x(v - piv, -sn * 0.7), sin(t * 0.31) * 0.35 * (1.0 - sn)), hw);
			v.y += (1.0 - lw) * sin(t * 9.0) * 0.004;
		}
		// Tail swish (dogs wag faster: tail_speed per species).
		float sw2 = sin(t * tail_speed + id * 7.0) * (kind == 5 ? 1.0 : smoothstep(-0.2, 0.6, sin(t * 0.37 + id * 3.0)));
		v.x += tw * sw2 * tail_amp;
	} else if (kind == 1) {
		if (t0 > 0.0 && now >= t0) {
			v = vec3(0.0); // flown away
		} else {
			// Jerky head turns and pecks; the tail flicks.
			float step_t = floor(t * 0.9);
			float turn = (hash(step_t, id) - 0.5) * 1.6;
			float peck = smoothstep(0.75, 0.95, hash(step_t, id + 3.0)) * max(sin(fract(t * 0.9) * 3.14159), 0.0);
			vec3 piv = vec3(0.0, H * 0.55, -L * 0.15);
			v = mix(v, piv + rot_x(rot_y(v - piv, turn), -peck * 1.1), hw);
			v.y += tw * sin(t * 3.0) * 0.01;
		}
	} else if (kind == 2 || kind == 3) {
		v.z *= flip_fly;
		v.x *= flip_fly;
		vec3 pos;
		vec3 fwd;
		float bank = 0.0;
		float beat;
		float amp = 0.55;
		if (kind == 2) {
			float r = INSTANCE_CUSTOM.b;
			float w = INSTANCE_CUSTOM.a;
			float th = now * w + id * 6.2831;
			pos = vec3(cos(th) * r, sin(now * 0.21 + id * 11.0) * r * 0.06, sin(th) * r);
			fwd = normalize(vec3(-sin(th), 0.0, cos(th)) * sign(w));
			bank = -sign(w) * 0.32;
			float gl = smoothstep(-0.2, 0.3, sin(now * 0.25 + id * 17.0) + glide * 2.0 - 1.0);
			beat = sin(t * flap_hz * 6.2831) * (1.0 - gl) + gl * 0.12;
			amp = mix(0.55, 0.2, gl);
		} else {
			float tt = now - t0;
			if (t0 <= 0.0 || tt < 0.0 || tt > FLEE_T) {
				v = vec3(0.0);
				pos = vec3(0.0, -1000.0, 0.0);
				fwd = vec3(0.0, 0.0, -1.0);
			} else {
				float wob = (hash(id, 9.0) - 0.5) * 2.0;
				pos = vec3(wob * tt * tt * 0.25, 2.2 * tt - 0.06 * tt * tt + 0.3, -(4.0 + 1.5 * tt) * tt);
				fwd = normalize(vec3(wob * tt * 0.5, 2.2 - 0.12 * tt, -(4.0 + 3.0 * tt)));
				bank = -wob * 0.3;
				v *= 1.0 - smoothstep(FLEE_T - 1.5, FLEE_T, tt);
			}
			beat = sin(t * flap_hz * 1.6 * 6.2831);
		}
		v = flap(v, CUSTOM0.w, beat, amp);
		v = rot_z(v, bank);
		n = rot_z(n, bank);
		// Pitch with the climb, then yaw to the heading (model -Z = forward).
		float pitch = asin(clamp(fwd.y, -0.9, 0.9));
		v = rot_x(v, pitch);
		float yaw = atan(-fwd.x, -fwd.z);
		v = rot_y(v, yaw);
		n = rot_y(rot_x(n, pitch), yaw);
		v += pos;
	} else if (kind == 4) {
		// Cat: the tail sweeps, the head turns to look around now and then.
		float look = (hash(floor(t * 0.15), id) - 0.5) * 1.4;
		vec3 piv = vec3(0.0, H * 0.7, -L * 0.1);
		v = mix(v, piv + rot_y(v - piv, look), hw);
		v.x += tw * sin(t * tail_speed) * tail_amp * smoothstep(-0.3, 0.5, sin(t * 0.2 + id * 9.0));
		v.x *= 1.0 + sin(t * 1.1) * 0.015 * (1.0 - tw);
	}
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 c;
	if (paint == 1) {
		// Red deer: warm brown, darker back and neck, pale belly and rump patch, grey-brown antlers.
		float h = mpos.y / size.y;
		float fz = clamp((size.z * 0.5 - mpos.z) / size.z, 0.0, 1.0); // 0 tail .. 1 nose
		c = vec3(0.30, 0.17, 0.085);
		c = mix(c, vec3(0.19, 0.11, 0.06), smoothstep(0.55, 0.75, h) * smoothstep(0.55, 0.8, fz));
		c = mix(c, vec3(0.55, 0.45, 0.33), smoothstep(0.47, 0.38, h) * smoothstep(0.25, 0.4, fz) * smoothstep(0.85, 0.6, fz) * step(0.25, h));
		c = mix(c, vec3(0.75, 0.68, 0.55), smoothstep(0.1, 0.03, fz) * step(0.45, h));
		c = mix(c, vec3(0.08, 0.07, 0.06), step(0.97, fz) * step(0.62, h));
		c = mix(c, vec3(0.45, 0.38, 0.3), step(0.8, h) * step(0.7, fz) * step(abs(mpos.x), size.x * 0.6));
		c *= mix(0.8, 1.0, smoothstep(0.0, 0.3, h)); // legs a bit darker
	} else if (paint == 2) {
		float aw = abs(wing);
		c = mix(COLOR.rgb, wing_col, smoothstep(0.15, 0.3, aw));
		c = mix(c, vec3(0.03), smoothstep(0.82, 0.92, aw) * step(0.5, COLOR.a)); // black wing tips (gulls)
	} else {
		c = has_tex ? texture(albedo_tex, UV).rgb : vec3(0.5);
		c *= COLOR.rgb;
	}
	ALBEDO = c;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	BACKLIGHT = paint == 2 ? c * 0.25 : vec3(0.0);
}
