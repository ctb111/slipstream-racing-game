// Car window glass with rain, water film, dust, mud specks and snow.
// Included by car_glass.gdshader (double sided) and car_glass_cull.gdshader.
//
// Base part mirrors the StandardMaterial3D it replaces. Rain: round beads that
// land and evaporate, plus running drops with a wet trail. The running drops
// have two fixed layers, one sliding down with gravity and one blown back by
// the airflow, and speed cross-fades between them. On the windscreen the
// airflow layer climbs the glass at speed. Dust and mud keep off two wiper arcs
// on the windscreen. Snow piles along the bottom of the windscreen, frosts the
// window corners and lies on glass that faces up.

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metallic = 0.0;
uniform float roughness = 0.0;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float specular = 0.5;

uniform float car_ground = 0.0;
uniform vec3 car_min = vec3(-0.9, 0.0, -2.2);
uniform vec3 car_max = vec3(0.9, 1.3, 2.2);
uniform vec3 ws_min = vec3(-0.6, 0.8, -0.8); // windscreen bounds (mesh space)
uniform vec3 ws_max = vec3(0.6, 1.2, -0.3);
uniform vec3 glass_min = vec3(-0.9, 0.7, -0.8); // all glass on this surface
uniform vec3 glass_max = vec3(0.9, 1.3, 1.5);
uniform sampler2D dirt_noise : hint_default_black, filter_linear_mipmap, repeat_enable;

instance uniform vec4 dirt_a = vec4(0.0); // dust, mud, slush, wet
instance uniform vec4 dirt_b = vec4(0.0); // snow on top, road grime, rain wash, seed
instance uniform vec4 dirt_c = vec4(0.0); // speed 0..1, rain falling 0..1, snowing 0..1, time offset

varying vec3 v_pos;
varying vec3 v_nrm;

void vertex() {
	v_pos = VERTEX;
	v_nrm = NORMAL;
}

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

// Beads that land, sit and evaporate. q in metres. Returns (offset.xy, coverage).
vec3 beads(vec2 q, float cells, float t, float amount, float rain) {
	vec2 g = q * cells;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	vec2 rnd = hash22(id);
	vec2 c = (rnd - 0.5) * 0.6;
	float life = fract(t * (0.08 + 0.12 * rnd.x) + rnd.y);
	float env = smoothstep(0.0, 0.03, life) * (1.0 - smoothstep(0.55, 1.0, life));
	float r = (0.1 + 0.3 * hash12(id + 7.13)) * mix(1.0, env, rain);
	r *= step(hash12(id + 3.31), amount);
	vec2 o = (f - c) / max(r, 1e-4);
	float d2 = dot(o, o);
	return vec3(o, (1.0 - smoothstep(0.7, 1.0, d2)) * step(0.001, r));
}

// Drops running along +y of q (metres) at `speed` m/s, each with a wet trail.
// Returns (offset.xy, head coverage, trail coverage).
vec4 runners(vec2 q, float t, float speed, float amount) {
	const vec2 CELL = vec2(0.045, 0.22);
	float colx = floor(q.x / CELL.x);
	float rc = hash12(vec2(colx, 4.7));
	float y = q.y - t * speed * (0.6 + 0.8 * rc) - rc * 7.0;
	vec2 id = vec2(colx, floor(y / CELL.y));
	float rr = hash12(id + 1.7);
	float on = step(rr, amount * 0.65);
	vec2 local = vec2(q.x - (colx + 0.5) * CELL.x, y - (id.y + 0.5) * CELL.y);
	local.x -= (hash12(id + 9.1) - 0.5) * CELL.x * 0.5;
	local.x += sin(y * 23.0 + rc * 6.0) * 0.003; // wobble along the path
	float R = 0.0035 + 0.003 * rr;
	vec2 o = local / vec2(R, R * 1.25);
	float head = (1.0 - smoothstep(0.6, 1.0, dot(o, o))) * on;
	float behind = -local.y;
	float trail = (1.0 - smoothstep(R * 0.25, R * 0.55, abs(local.x))) * step(0.0, behind)
		* (1.0 - smoothstep(0.0, CELL.y * 0.8, behind)) * on;
	// The trail breaks into tiny left-behind beads.
	trail *= smoothstep(0.2, 0.6, sin(behind * 900.0 + rr * 30.0) * 0.5 + 0.5);
	return vec4(o, head, trail * 0.8);
}

void fragment() {
	vec2 base_uv = UV * uv1_scale.xy + uv1_offset.xy;
	vec4 at = texture(texture_albedo, base_uv);
	vec3 col = albedo.rgb * at.rgb;
	float alpha = albedo.a * at.a;
	float met = metallic * dot(texture(texture_metallic, base_uv), metallic_channel);
	float rough = roughness * dot(texture(texture_roughness, base_uv), roughness_channel);
	vec3 n_view = NORMAL;

	float dust_amt = dirt_a.x;
	float mud_amt = dirt_a.y;
	float slush_amt = dirt_a.z;
	float wet = dirt_a.w;
	float top_snow = dirt_b.x;
	float grime_amt = dirt_b.y;
	float speed01 = dirt_c.x;
	float rain = dirt_c.y;
	float snowing = dirt_c.z;

	if (dust_amt + mud_amt + slush_amt + wet + top_snow + grime_amt + rain + snowing > 0.002) {
		vec3 p = v_pos;
		vec3 n = normalize(v_nrm);
		if (!FRONT_FACING) {
			n = -n;
		}
		float t = TIME + dirt_c.w;
		float near = 1.0 - smoothstep(0.0025, 0.006, length(fwidth(v_pos))); // drops need pixels smaller than them
		// Which window: windscreen faces forward/up, rear glass backward, side glass sideways.
		float front = smoothstep(0.25, 0.6, -n.z);
		float rearg = smoothstep(0.25, 0.6, n.z);
		float side = smoothstep(0.5, 0.8, abs(n.x)) * (1.0 - front) * (1.0 - rearg);
		float up = smoothstep(0.35, 0.8, n.y);

		// Stable planar coords on the glass (dominant axis).
		vec3 an = abs(n);
		vec2 pq = an.x > max(an.y, an.z) ? p.zy : (an.y > an.z ? p.xz : p.xy);
		vec4 nz = texture(dirt_noise, pq * 1.7 + dirt_b.w * 3.1);
		vec4 nzf = texture(dirt_noise, pq * 6.0 + dirt_b.w * 1.7);

		// Frames for running drops: down the glass (gravity) and back along the car (air).
		vec3 g = vec3(0.0, -1.0, 0.0);
		vec3 Tg = g - n * dot(g, n);
		Tg = length(Tg) > 0.05 ? normalize(Tg) : vec3(0.0, 0.0, 1.0);
		vec3 air = vec3(0.0, 0.0, 1.0);
		vec3 Ta = air - n * dot(air, n);
		Ta = length(Ta) > 0.05 ? normalize(Ta) : Tg;
		vec3 Bg = cross(n, Tg);
		vec3 Ba = cross(n, Ta);
		float blow = smoothstep(0.12, 0.5, speed01) * (1.0 - rearg * 0.8);

		// ---- rain / melting flakes ----
		vec3 bn = vec3(0.0);
		vec2 drop_o = vec2(0.0);
		float water = 0.0;
		float trailw = 0.0;
		float flakes = 0.0;
		if (wet + rain + snowing > 0.01 && near > 0.01) {
			vec3 b1 = beads(pq + vec2(dirt_b.w * 13.0, 0.0), 42.0, t, clamp(max(wet, snowing) * 0.8, 0.0, 0.85), max(rain, snowing));
			vec3 b2 = beads(pq * 1.7 + vec2(3.3, 1.1), 42.0, t * 1.3, clamp(max(wet, snowing) * 0.6, 0.0, 0.7), max(rain, snowing));
			float cover = max(b1.z, b2.z * 0.8);
			vec2 bo = b1.z > b2.z ? b1.xy : b2.xy;
			// Drops blown about / running only while it rains (and less on the sheltered rear glass).
			float run_amt = rain * mix(1.0, 0.45, rearg) * (1.0 - snowing);
			vec4 rg = runners(vec2(dot(p, Bg), dot(p, Tg)), t, 0.12 + 0.1 * rain, run_amt * (1.0 - blow));
			vec4 ra = runners(vec2(dot(p, Ba), dot(p, Ta)) + vec2(0.017, 0.0), t, 0.4 + speed01 * 2.6, run_amt * blow * 1.2);
			float heads = max(rg.z, ra.z);
			trailw = max(rg.w, ra.w);
			// At speed on the windscreen most beads get blown away.
			cover *= 1.0 - blow * front * 0.7;
			vec3 frame_b = rg.z > ra.z ? Bg : Ba;
			vec3 frame_t = rg.z > ra.z ? Tg : Ta;
			vec2 ho = rg.z > ra.z ? rg.xy : ra.xy;
			water = max(cover, heads);
			if (snowing > 0.3) {
				// Flakes: small white specks that melt from the edge in.
				flakes = cover * smoothstep(0.3, 0.8, snowing);
				water = heads;
			}
			vec2 o = heads > cover ? ho : bo;
			drop_o = o;
			vec3 fb = heads > cover ? frame_b : cross(n, abs(n.y) > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0));
			vec3 ft = heads > cover ? frame_t : cross(fb, n);
			bn = (fb * o.x + ft * o.y) * 1.1 * water;
			water *= near;
			trailw *= near;
		}

		// ---- dust / grime / mud film ----
		float gh = max(glass_max.y - glass_min.y, 0.2);
		float gy = (p.y - glass_min.y) / gh;
		// Wiper arcs on the windscreen.
		float wsw = max(ws_max.x - ws_min.x, 0.4);
		float wsh = length(vec2(ws_max.y - ws_min.y, ws_max.z - ws_min.z));
		vec3 piv1 = vec3(ws_min.x + wsw * 0.22, ws_min.y, ws_min.z);
		vec3 piv2 = vec3(ws_min.x + wsw * 0.66, ws_min.y, ws_min.z);
		float wr = wsh * 0.92;
		float d1 = length(p - piv1), d2 = length(p - piv2);
		float wiped = max((1.0 - smoothstep(wr - 0.02, wr + 0.01, d1)) * smoothstep(0.05, 0.1, d1),
			(1.0 - smoothstep(wr - 0.02, wr + 0.01, d2)) * smoothstep(0.05, 0.1, d2)) * front;

		float lowg = 1.0 - smoothstep(0.0, 0.55, gy);
		// Side glass stays fairly clean (a haze low down); the rear window collects the most.
		float dm = (0.12 + 0.45 * lowg) * (1.0 - side * 0.8) * (1.0 - front * 0.3) + rearg * 0.35;
		float dust = smoothstep((1.0 - nz.r) * 0.7, (1.0 - nz.r) * 0.7 + 0.7, dust_amt * dm); // a smooth film: grain on glass reads as noise
		dust *= 0.6 * (1.0 - wiped * 0.9);
		float grime = smoothstep((1.0 - nz.r) * 0.8, (1.0 - nz.r) * 0.8 + 0.6, grime_amt * (0.3 + 0.7 * lowg + front * 0.4))
			* 0.5 * (1.0 - wiped * 0.85);
		float msize = mud_amt * (0.5 * lowg * lowg + front * 0.2) * smoothstep(0.55, 0.9, nzf.a);
		float mud = smoothstep(1.0 - msize * 0.5, 1.0 - msize * 0.5 + 0.08, 1.0 - nzf.g) * near * (1.0 - wiped * 0.7);

		// ---- snow ----
		float pile = front * (1.0 - smoothstep(0.03, 0.09 + 0.06 * nz.r, p.y - ws_min.y)) * max(slush_amt, top_snow);
		float frost = snowing * (1.0 - smoothstep(0.0, 0.3 + 0.2 * nz.r, min(gy, 1.0 - gy) * 2.0 + nzf.b * 0.2)) * (1.0 - wiped) * 0.8;
		float lying = smoothstep((1.0 - nz.r) * 0.7, (1.0 - nz.r) * 0.7 + 0.15, top_snow * up * 1.2);
		float snow = clamp(max(max(pile * 1.4, lying), frost * 0.7), 0.0, 1.0);

		// ---- compose ----
		vec3 dust_col = mix(vec3(0.279, 0.208, 0.126), vec3(0.218, 0.208, 0.190), clamp(slush_amt * 2.0, 0.0, 1.0)) * mix(1.0, 0.6, wet);
		col = mix(col, dust_col, dust);
		alpha = mix(alpha, 0.95, dust);
		rough = mix(rough, 0.8, dust);
		met = mix(met, 0.0, dust);
		col = mix(col, vec3(0.106, 0.087, 0.061), grime);
		alpha = mix(alpha, 0.9, grime);
		rough = mix(rough, 0.5, grime);
		col = mix(col, vec3(0.029, 0.015, 0.008), mud);
		alpha = mix(alpha, 1.0, mud);
		rough = mix(rough, 0.35, mud);
		met = mix(met, 0.0, mud);
		col = mix(col, vec3(0.832, 0.852, 0.914), snow);
		alpha = mix(alpha, 0.97, snow);
		rough = mix(rough, 0.7, snow);
		met = mix(met, 0.0, snow);

		// Water: lenses that catch the light, a faint film everywhere that got rained on.
		float lens = max(water, trailw * 0.6) * (1.0 - snow) * (1.0 - mud);
		// A drop is a little lens: it shows the bright sky above flipped, so it is
		// lit at the bottom, with a dark meniscus ring at its edge.
		float r2 = dot(drop_o, drop_o);
		float ring = smoothstep(0.45, 0.9, r2) * water;
		float glow = (1.0 - smoothstep(0.1, 0.8, r2)) * clamp(0.35 - drop_o.y * 0.65, 0.0, 1.0) * water;
		col = mix(col, vec3(0.16, 0.17, 0.18), glow * 0.8);
		col = mix(col, col * 0.35, ring * 0.7);
		col = mix(col, col * 0.8 + vec3(0.02), trailw * 0.5);
		alpha = mix(alpha, max(alpha, 0.55), lens);
		rough = mix(rough, 0.02, lens);
		met = mix(met, 0.0, lens);
		rough = mix(rough, rough + 0.06, wet * (1.0 - lens) * (1.0 - snow));
		float fl = flakes * (1.0 - snow);
		col = mix(col, vec3(0.873, 0.893, 0.935), fl);
		alpha = mix(alpha, 0.95, fl);
		rough = mix(rough, 0.6, fl);
		if (lens > 0.01) {
			vec3 nob = normalize(n - bn * lens);
			n_view = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(nob, 0.0)).xyz);
		}
	}

	NORMAL = n_view;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
	METALLIC = met;
	ROUGHNESS = clamp(rough, 0.0, 1.0);
	SPECULAR = specular;
}
