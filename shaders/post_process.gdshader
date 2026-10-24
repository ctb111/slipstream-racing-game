shader_type canvas_item;
render_mode unshaded, blend_disabled;
// In-race lens and grade, one full-screen pass under the HUD (driven by
// CameraPost): rain on the lens -> radial speed blur + edge aberration ->
// sun glare -> colour grade -> vignette -> grain. Everything is subtle on
// purpose: it should read as a camera, not as an effect.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float aspect = 1.7778;

// Speed: radial blur towards the vanishing point, chromatic fringe at the edges.
uniform float blur_amount = 0.0; // 0..1
uniform int blur_taps = 6; // 0 = off
uniform vec2 blur_center = vec2(0.5, 0.5);
uniform float aberration = 0.0; // UV offset at the corners

// Grade (display space, after the engine's AgX tonemap).
uniform float curve = 0.15; // S-curve strength
uniform float saturation = 1.0;
uniform vec3 shadow_tint = vec3(-0.006, 0.0, 0.012);
uniform vec3 highlight_tint = vec3(0.014, 0.006, -0.01);
uniform float vignette = 0.28;
uniform float grain = 0.0;

// Sun glare: position in screen UV, overall strength (0 = off), light colour.
uniform vec2 sun_uv = vec2(0.5, -1.0);
uniform float sun_strength = 0.0;
uniform vec3 sun_color = vec3(1.0, 0.9, 0.75);
uniform float sun_onscreen = 0.0; // 1 = sample the frame to see if something hides the sun
// Sun shafts (golden hour, dawn): bright sky around the sun smeared radially
// away from it, so gaps between trunks and leaves become beams. 0 taps = off.
uniform float shaft_strength = 0.0;
uniform int shaft_taps = 0;
uniform float shaft_threshold = 0.8; // display-space luminance that counts as open sky

// Rain on the lens: coverage (0 = off) and how much the drops streak (speed).
uniform float rain = 0.0;
uniform float rain_streak = 0.0;

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

// Round beads that form and slowly evaporate. xy = refraction, z = coverage.
vec3 beads(vec2 uv, float scale, float t, float seed) {
	vec2 p = vec2(uv.x * aspect, uv.y) * scale;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	vec2 r = hash22(id + seed);
	if (r.y < 0.74) {
		return vec3(0.0);
	}
	float life = fract(t * (0.05 + r.x * 0.08) + r.y * 7.0);
	float rad = mix(0.1, 0.26, hash12(id + seed + 3.7)) * smoothstep(0.0, 0.04, life) * (1.0 - life * 0.55);
	vec2 d = f - (r - 0.5) * 0.45;
	d.y *= 1.0 + 0.25 * (1.0 - life); // a touch of sag
	float l = length(d);
	float m = smoothstep(rad, rad * 0.45, l); // soft edge: no dark ring
	return vec3(-d / max(rad, 0.001) * m / scale, m);
}

// Drops blown up the glass at speed: thin trails with a fat head.
vec3 streaks(vec2 uv, float t, float spd) {
	vec2 p = vec2(uv.x * aspect * 16.0, uv.y * 3.0 + t * (0.7 + spd * 2.2));
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	vec2 r = hash22(id * 1.37 + 11.0);
	if (r.x < 0.55) {
		return vec3(0.0);
	}
	float cx = (r.y - 0.5) * 0.6;
	float w = mix(0.07, 0.16, r.x);
	float along = f.y + 0.35; // 0 at the head (top), grows down the tail
	float body = smoothstep(w, w * 0.4, abs(f.x - cx)) * smoothstep(-0.02, 0.05, along) * (1.0 - smoothstep(0.1, 0.75, along));
	float head = smoothstep(w * 1.4, w * 0.7, length(vec2(f.x - cx, (along - 0.04) * 2.5)));
	float m = max(body * 0.55, head);
	return vec3(vec2(-(f.x - cx) / w, 0.3) * m * 0.004, m);
}

vec3 ghost(vec2 uv, vec2 p, float size, vec3 tint) {
	float d = length((uv - p) * vec2(aspect, 1.0));
	float disc = smoothstep(size, size * 0.6, d);
	float rim = smoothstep(size * 0.8, size, d) * disc;
	return tint * (disc * 0.6 + rim * 0.8);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float lens_mask = 0.0;

	// Rain on the lens bends the image behind each drop.
	if (rain > 0.0) {
		vec3 b = beads(uv, 9.0, TIME, 0.0) * (1.0 - rain_streak * 0.7);
		vec3 b2 = beads(uv, 17.0, TIME * 1.3, 5.0) * (1.0 - rain_streak);
		vec3 s = rain_streak > 0.02 ? streaks(uv, TIME, rain_streak) * rain_streak : vec3(0.0);
		vec3 drops = (b + b2 * 0.7 + s) * rain;
		uv += drops.xy * 0.45; // subtle bend (1.8 sampled ~20% of the screen away = black rims)
		lens_mask = clamp(drops.z, 0.0, 1.0);
	}

	vec2 to_c = blur_center - uv;
	float r = length((uv - 0.5) * vec2(aspect, 1.0)) / aspect * 2.0; // 0 centre .. ~1.15 corners
	vec3 col;
	if (aberration > 0.0) {
		vec2 ca = (uv - 0.5) * aberration * r * r;
		col = vec3(texture(screen_tex, uv + ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv - ca).b);
	} else {
		col = texture(screen_tex, uv).rgb;
	}

	// Radial speed blur: the edges smear towards the vanishing point, the
	// centre (where you look, and your car in chase view) stays sharp.
	if (blur_taps > 0 && blur_amount > 0.001) {
		float w = blur_amount * smoothstep(0.12, 0.7, length(to_c * vec2(aspect, 1.0)) / aspect * 2.0);
		if (w > 0.002) {
			vec3 acc = col;
			// 2x2 ordered offset: breaks up banding but keeps neighbouring
			// pixels' taps close together (cache friendly, unlike random jitter).
			vec2 q = mod(FRAGCOORD.xy, 2.0);
			float jitter = 0.25 + 0.5 * abs(q.x - q.y);
			for (int i = 1; i <= blur_taps; i++) {
				float k = (float(i) - jitter) / float(blur_taps);
				acc += texture(screen_tex, uv + to_c * k * 0.07 * w).rgb;
			}
			col = acc / float(blur_taps + 1);
		}
	}

	// Sun glare: halo, faint anamorphic streak, and a few muted ghosts on the
	// line through the frame centre. Hidden when something covers the sun.
	if (sun_strength > 0.001) {
		float vis = 1.0;
		if (sun_onscreen > 0.5) {
			vec2 px = 0.012 * vec2(1.0 / aspect, 1.0);
			vec3 s = texture(screen_tex, sun_uv).rgb + texture(screen_tex, sun_uv + px).rgb + texture(screen_tex, sun_uv - px).rgb
				+ texture(screen_tex, sun_uv + vec2(px.x, -px.y)).rgb + texture(screen_tex, sun_uv + vec2(-px.x, px.y)).rgb;
			vis = smoothstep(0.55, 0.85, dot(s / 5.0, vec3(0.2126, 0.7152, 0.0722)));
		}
		float str = sun_strength * vis;
		if (str > 0.001) {
			vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
			float dl = length(d);
			vec3 g = sun_color * (exp(-dl * 5.0) * 0.22 + exp(-dl * 22.0) * 0.4);
			g += sun_color * exp(-abs(d.y) * 110.0) * exp(-abs(d.x) * 3.0) * 0.1;
			vec2 axis = vec2(0.5) - sun_uv;
			vec3 gh = ghost(uv, sun_uv + axis * 0.7, 0.035, vec3(0.05, 0.06, 0.03));
			gh += ghost(uv, sun_uv + axis * 1.25, 0.07, vec3(0.05, 0.035, 0.02));
			gh += ghost(uv, sun_uv + axis * 1.6, 0.025, vec3(0.03, 0.045, 0.06));
			gh += ghost(uv, sun_uv + axis * 2.1, 0.11, vec3(0.025, 0.02, 0.035));
			g += gh * 1.8 * sun_color;
			col = col + g * str;
			col = mix(col, col + sun_color * 0.06, str * 0.5); // veiling glare lifts the blacks
		}
	}

	// Sun shafts: march from this pixel towards the sun, gathering the bright
	// (open sky) samples; trees and hills between break them into beams.
	if (shaft_taps > 0 && shaft_strength > 0.001) {
		vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
		float fall = exp(-length(d) * 2.0);
		if (fall > 0.08) { // within ~1.25 screen heights of the sun
			vec2 stp = (sun_uv - uv) * (0.75 / float(shaft_taps));
			float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
			vec2 p = uv + stp * ign;
			float acc = 0.0;
			float wsum = 0.0;
			float wt = 1.0;
			for (int i = 0; i < shaft_taps; i++) {
				vec2 q = clamp(p, vec2(0.001), vec2(0.999));
				float l = dot(texture(screen_tex, q).rgb, vec3(0.2126, 0.7152, 0.0722));
				float src = smoothstep(shaft_threshold, 1.0, l) * exp(-length((q - sun_uv) * vec2(aspect, 1.0)) * 3.5);
				acc += src * wt;
				wsum += wt;
				wt *= 0.94;
				p += stp;
			}
			float sh = acc / wsum * fall;
			// Beams show in the air in front of darker things, not over the bright sky.
			float own = dot(col, vec3(0.2126, 0.7152, 0.0722));
			col += sun_color * sh * shaft_strength * (1.0 - smoothstep(0.35, 0.95, own));
		}
	}

	// Drops catch a little light at their rims.
	col += lens_mask * 0.025;

	// Grade: gentle filmic S-curve, cool shadows, warm highlights.
	col = clamp(col, 0.0, 1.0);
	col = mix(col, col * col * (3.0 - 2.0 * col), curve);
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.45, lum)) + highlight_tint * smoothstep(0.45, 1.0, lum);
	col = mix(vec3(lum), col, saturation);

	float vd = length((SCREEN_UV - 0.5) * vec2(1.0, 0.8));
	col *= mix(1.0, smoothstep(0.95, 0.25, vd), vignette);

	if (grain > 0.0) {
		float n = hash12(FRAGCOORD.xy + fract(TIME * 7.13) * vec2(311.7, 183.3)) - 0.5;
		col += n * grain * (1.0 - lum * 0.6);
	}
	COLOR = vec4(col, 1.0);
}
