// Car body / wheel material with dirt, mud, dust, slush, snow and water on top.
// Included by car_dirt*.gdshader: double sided or not, with clearcoat (paint,
// DIRT_CLEARCOAT) or without, so only paint pays for the clearcoat lobe.
//
// The base part mirrors the StandardMaterial3D it replaces (CarDirt copies the
// values over), so a clean car renders exactly like before. The dirt part works
// in the mesh's own space, not UVs, so it lands the same way on every model:
// coverage masks from the car's shape (sills, wheel arches, the fan of spray
// behind each tyre, the rear panel, the nose, the roof) are eroded by a
// tileable noise (assets/textures/car_dirt/dirt_noise.png), projected on the
// dominant axis (plus the second axis for the soft blotch layer).
//
// Cost: two variants:
// the detailed one (cars near the camera) and DIRT_LIGHT (everyone else): the
// same dirt as smooth films, no textures. A big shader costs registers, and so
// GPU occupancy, even in branches it skips, so the light one has to be its own
// shader. In the detailed one, the detail fetches only happen where there is
// something thick enough to show.
//
// Per car state arrives as instance uniforms (set by CarDirt on each mesh), so
// every car of one model shares these materials.

// ---- base material (copied from the StandardMaterial3D) ----
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_albedo_tex = false;
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform bool use_metallic_tex = false;
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool use_roughness_tex = false;
uniform sampler2D texture_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool normal_enabled = false;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform bool ao_enabled = false;
uniform sampler2D texture_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float ao_light_affect = 0.0;
uniform float clearcoat = 0.0;
uniform float clearcoat_roughness = 0.5;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float specular = 0.5;

// ---- the car's shape (mesh space; nose towards -Z) ----
uniform int dirt_mode = 0; // 0 body, 1 tyre, 2 rim / brake
uniform float car_ground = 0.0; // y of the road under the tyres
uniform vec3 car_min = vec3(-0.9, 0.0, -2.2);
uniform vec3 car_max = vec3(0.9, 1.3, 2.2);
uniform vec2 hub_front = vec2(-1.2, 0.3); // (z, y)
uniform vec2 hub_rear = vec2(1.2, 0.3);
uniform float wheel_r = 0.31;
uniform vec3 cabin_min = vec3(0.0, 1e4, 0.0); // box spanned by the windows: inside it is interior
uniform vec3 cabin_max = vec3(0.0, 1e4, 0.0);
uniform sampler2D dirt_noise : hint_default_black, filter_linear_mipmap, repeat_enable;

// ---- per car state (CarDirt) ----
instance uniform vec4 dirt_a = vec4(0.0); // dust, mud, slush (packed snow), wet
instance uniform vec4 dirt_b = vec4(0.0); // snow on top, road grime, rain wash, seed

varying float v_haze; // soft noise for the thin films that cover the whole car (per vertex: free)

// Spray thrown back and up by a tyre: strongest in the arch lip and in a fan behind the hub.
float arch_fan(vec3 p, vec2 hub, float outer) {
	vec2 d = vec2(p.z - hub.x, p.y - hub.y) / wheel_r;
	float r = length(d);
	float behind = smoothstep(-0.4, 0.9, d.x);
	float fan = (1.0 - smoothstep(1.0, 3.4, r)) * mix(0.3, 1.0, behind) * (1.0 - smoothstep(0.2, 1.6, d.y));
	float lip = smoothstep(0.92, 1.08, r) * (1.0 - smoothstep(1.12, 1.55, r));
	return max(fan * outer, lip * (0.4 + 0.6 * outer));
}

// Coverage masks from the car's shape at mesh-space point p with normal n.
// ma: dust, grime, mud, slush. mb: snow-on-top, upward faces (beads), low body, spray fans.
// Per pixel: some models have huge flat triangles a per-vertex mask would
// smear into straight diagonal edges.
// `up`: how much the surface faces the sky (see fragment: guards against bad normals).
void shape_masks(vec3 p, vec3 n, float up, float vh, out vec4 ma, out vec4 mb) {
	if (dirt_mode == 0) {
		float H = max(car_max.y - car_ground, 0.5);
		// Low-frequency noise on the height: the top of the sill band is an irregular edge.
		float h = (p.y - car_ground) / H + (vh - 0.5) * 0.22;
		float zf = (p.z - car_min.z) / max(car_max.z - car_min.z, 1.0);
		float halfw = max(car_max.x - car_min.x, 1.0) * 0.5;
		float outer = smoothstep(0.55, 0.9, abs(p.x) / halfw);
		float low = 1.0 - smoothstep(0.08, 0.5, h);
		float lowest = 1.0 - smoothstep(0.05, 0.28, h);
		float fans = max(arch_fan(p, hub_front, outer), arch_fan(p, hub_rear, outer));
		float rear = smoothstep(0.8, 0.97, zf) * smoothstep(-0.2, 0.6, n.z) * (1.0 - smoothstep(0.35, 0.95, h));
		float nose = (1.0 - smoothstep(0.03, 0.16, zf)) * smoothstep(0.0, 0.7, -n.z) * (1.0 - smoothstep(0.25, 0.7, h));
		float under = smoothstep(-0.1, -0.7, n.y);
		float top = smoothstep(0.45, 0.85, up);
		float flat_top = smoothstep(0.62, 0.92, up);
		ma = vec4(
			max(max(low * 1.1, fans), max(rear, under)), // dust
			max(max(low, fans * 0.9), max(nose * 0.9, rear * 0.7)) + 0.12 * low, // road grime
			max(max(fans * 1.1, low * 0.7), max(nose * 0.5, rear * 0.55)) + under * 0.5, // mud
			max(max(fans * 0.85, lowest * 0.6), nose * lowest * 0.7) + under * 0.25); // slush
		mb = vec4(flat_top, (0.12 + 0.45 * top) * (1.0 - under), low, fans);
	} else {
		// Wheels: mesh space is centred on the hub, X is the axle.
		float rr = length(p.yz) / wheel_r;
		float tread = 1.0 - abs(n.x);
		float edge_r = smoothstep(0.55, 0.95, rr);
		bool tyre = dirt_mode == 1;
		float dm = tyre ? (0.35 + 0.45 * tread) : (0.2 + 0.7 * edge_r);
		ma = vec4(dm, dm, tyre ? (0.35 + 0.55 * tread) : edge_r * 0.8, tyre ? (0.15 + 0.55 * tread) : edge_r * 0.45);
		mb = vec4(0.0, 0.0, 1.0, 0.0);
	}
}

void vertex() {
	vec3 an = abs(NORMAL);
	vec3 sp = VERTEX + dirt_b.w * vec3(3.7, 1.9, 5.3);
	vec2 hv = an.x > max(an.y, an.z) ? sp.zy : (an.y > an.z ? sp.xz : sp.xy);
	v_haze = textureLod(dirt_noise, hv * 0.55, 0.0).r;
}

// Planar projection of a mesh-space vector onto axis a (0 = X face, 1 = top, 2 = Z face).
vec2 proj(vec3 v, int a) {
	return a == 0 ? v.zy : (a == 1 ? v.xz : v.xy);
}

// One fetch of the noise at scale s (tiles per metre / 28 cells per tile).
vec4 planar(vec2 uv, float s) {
	return texture(dirt_noise, uv * s);
}

// Height-bump from a scalar field (surface gradient, no tangents needed).
vec3 bump(vec3 n, vec3 vpos, float h) {
	vec3 dpdx = dFdx(vpos);
	vec3 dpdy = dFdy(vpos);
	vec3 r1 = cross(dpdy, n);
	vec3 r2 = cross(n, dpdx);
	float det = dot(dpdx, r1);
	vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	return normalize(abs(det) * n - g);
}

// Soft threshold of `field` against noise `edge`: grows from the mask core outwards.
float grow(float field, float edge, float soft) {
	return smoothstep(edge, edge + soft, field);
}

// The whole dirt state as smooth films from the shape masks and the per-vertex
// noise: no textures, few registers. All of it in the light variant (cars away
// from the camera); in the detailed one, where only thin films show.
void light_layers(vec4 ma, vec4 mb, float vh, float dust_amt, float mud_amt, float slush_amt, float wet,
		float top_snow, float grime_amt, inout vec3 col, inout float rough, inout float met, inout float cc) {
	float e = 1.0 - vh;
	// Upper body: thin films only in large soft patches, mostly clean paint.
	float hz = mix(smoothstep(0.4, 0.8, vh) * 0.8, 1.0, mb.z);
	float dust = max(dust_amt * 0.18 * (0.45 + 0.55 * vh) * hz, smoothstep(0.2, 1.0, dust_amt * ma.x * 1.25 - e * 0.35) * 0.62);
	vec3 dust_col = mix(vec3(0.279, 0.208, 0.126), vec3(0.218, 0.208, 0.190), clamp(slush_amt * 2.0, 0.0, 1.0));
	dust_col = mix(dust_col, dust_col * 0.55, wet);
	col = mix(col, dust_col, dust);
	rough = mix(rough, mix(0.88, 0.45, wet), dust);
	met = mix(met, 0.0, dust);
	cc *= 1.0 - dust * 0.85;
	float grime = max(grime_amt * 0.14 * (0.4 + 0.6 * vh) * hz, smoothstep(0.15, 1.0, grime_amt * (ma.y - 0.12) * 1.3 - e * 0.3) * 0.55);
	col = mix(col, vec3(0.106, 0.087, 0.061), grime * 0.85);
	rough = mix(rough, mix(0.7, 0.3, wet), grime);
	met = mix(met, 0.0, grime * 0.8);
	cc *= 1.0 - grime * 0.5;
	float mud = smoothstep(0.15, 1.0, mud_amt * ma.z * 1.25 - e * 0.35) * 0.85;
	col = mix(col, mix(vec3(0.148, 0.099, 0.056), vec3(0.076, 0.047, 0.023), wet), mud);
	rough = mix(rough, mix(0.88, 0.4, wet), mud);
	met = mix(met, 0.0, mud);
	cc *= 1.0 - mud * 0.85;
	float sl = smoothstep(0.3, 1.0, slush_amt * ma.w * 1.25 - e * 0.35) * 0.75;
	col = mix(col, vec3(0.237, 0.237, 0.237), sl);
	rough = mix(rough, 0.62, sl);
	met = mix(met, 0.0, sl);
	cc *= 1.0 - sl;
	float sn = smoothstep(0.25, 0.75, top_snow * mb.x * 1.25 - e * 0.5);
	col = mix(col, vec3(0.80, 0.83, 0.89) * mix(0.9, 1.0, vh), sn);
	rough = mix(rough, 0.75, sn);
	met = mix(met, 0.0, sn);
	cc *= 1.0 - sn;
	rough *= 1.0 - wet * 0.15 * (1.0 - sn);
}

void fragment() {
	vec2 base_uv = UV * uv1_scale.xy + uv1_offset.xy;
	vec3 col = albedo.rgb;
	if (use_albedo_tex) {
		col *= texture(texture_albedo, base_uv).rgb;
	}
	float met = metallic;
	if (use_metallic_tex) {
		met *= dot(texture(texture_metallic, base_uv), metallic_channel);
	}
	float rough = roughness;
	if (use_roughness_tex) {
		rough *= dot(texture(texture_roughness, base_uv), roughness_channel);
	}
	float cc = clearcoat;
	float ccr = clearcoat_roughness;
	float nmap = normal_enabled ? normal_scale : 0.0;

	float dust_amt = dirt_a.x;
	float mud_amt = dirt_a.y;
	float slush_amt = dirt_a.z;
	float wet = dirt_a.w;
	float top_snow = dirt_b.x;
	float grime_amt = dirt_b.y;
	float wash = dirt_b.z;
	// Back to mesh space (rigid transforms only: cars aren't scaled). NORMAL is
	// already flipped on back faces.
	mat3 to_mesh = transpose(mat3(MODEL_MATRIX));
	vec3 m_pos = to_mesh * ((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - MODEL_MATRIX[3].xyz);
	vec3 n = normalize(to_mesh * (mat3(INV_VIEW_MATRIX) * NORMAL));
	// Snow and beads sit on what faces the sky: the true facet must agree with the
	// shading normal (some models have upward normals on side panels).
	vec3 ng = cross(dFdx(m_pos), dFdy(m_pos));
	ng = ng / max(length(ng), 1e-12) * (dot(ng, n) < 0.0 ? -1.0 : 1.0);
	float up = min(n.y, ng.y);
	vec4 ma;
	vec4 mb;
	shape_masks(m_pos, n, up, v_haze, ma, mb);
	// Interior (seats, parcel shelf, dash seen through the glass): inside the
	// cabin box and below the roof. Stays clean.
	if (dirt_mode == 0) {
		vec3 cc_c = (cabin_min + cabin_max) * 0.5;
		vec3 cc_h = (cabin_max - cabin_min) * 0.5;
		float in_x = smoothstep(0.03, 0.09, cc_h.x - abs(m_pos.x - cc_c.x));
		float in_z = smoothstep(0.02, 0.08, cc_h.z - abs(m_pos.z - cc_c.z));
		float in_y = smoothstep(0.02, 0.06, cabin_max.y - m_pos.y);
		float ext = 1.0 - in_x * in_z * in_y;
		dust_amt *= ext;
		mud_amt *= ext;
		slush_amt *= ext;
		wet *= ext;
		top_snow *= ext;
		grime_amt *= ext;
	}
	vec3 n_out = NORMAL;
#ifdef DIRT_LIGHT
	light_layers(ma, mb, v_haze, dust_amt, mud_amt, slush_amt, wet, top_snow, grime_amt, col, rough, met, cc);
#else
	// Thin films over the whole car (dust haze, road-spray grime): cheap, per-vertex noise.
	float hz = mix(smoothstep(0.4, 0.8, v_haze) * 0.8, 1.0, mb.z); // upper body: patches only
	float haze = dust_amt * 0.18 * (0.45 + 0.55 * v_haze) * hz;
	float film = grime_amt * 0.14 * (0.4 + 0.6 * v_haze) * hz;
	// Anything thicker needs the per-pixel detail; most of the car usually doesn't.
	float need = max(max(dust_amt * ma.x, grime_amt * (ma.y - 0.12)), max(mud_amt * ma.z, slush_amt * ma.w));
	// Pixel footprint in metres: beads and bumps only where a pixel is smaller than them.
	float pix = length(fwidth(VERTEX));
	need = max(need, max(top_snow * mb.x, wet * mb.y * step(pix, 0.003)));
	float dist = length(VERTEX);
	if (need <= 0.015 || dist > 30.0) {
		light_layers(ma, mb, v_haze, dust_amt, mud_amt, slush_amt, wet, top_snow, grime_amt, col, rough, met, cc);
	} else {
		vec3 p = m_pos + dirt_b.w * vec3(3.7, 1.9, 5.3);
		// Fine detail fades out with distance so far cars don't shimmer.
		float near = 1.0 - smoothstep(12.0, 28.0, dist);
		float near_b = 1.0 - smoothstep(0.0012, 0.003, pix);
		float near_m = 1.0 - smoothstep(0.0015, 0.004, pix);
		float vertical = 1.0 - abs(n.y);

		// Dominant axis of the normal: the projection plane.
		vec3 an = abs(n);
		int a1 = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);
		vec2 uv = proj(p, a1);
		vec4 big = planar(uv, 0.55); // blotches ~1 m
		vec4 mid = planar(uv, 2.1); // splatter clusters, ~2 cm drops
		bool want_fine = near > 0.01 && max(max(mud_amt * ma.z, slush_amt * ma.w), dust_amt * ma.x) > 0.03;
		vec4 fine = want_fine ? planar(uv, 7.5) : vec4(0.5, 1.0, 0.5, 0.0); // droplets, grain
		float grain = mix(0.5, fine.b, near);
		// Vertical runs (rain wash, drips): the same noise stretched down the sides.
		vec2 st = a1 == 1 ? vec2(1.0) : vec2(1.0, 0.06);
		float runs = (wash + mud_amt + grime_amt > 0.01) ? smoothstep(0.38, 0.7, planar(uv * st, 1.0).b) : 0.5;
		// Water only runs in a few places: down from the arches, below the window
		// line (in patches), and on the sills. Elsewhere the paint stays even.
		float below_win = (1.0 - smoothstep(0.0, 0.35, cabin_min.y - m_pos.y)) * step(m_pos.y, cabin_min.y);
		float rz = max(max(mb.w * 0.9, below_win * smoothstep(0.35, 0.7, big.r)), mb.z * 0.6);

		float dust = haze, mud = 0.0, slush = 0.0, snow = 0.0, grime = film, bead = 0.0;
		float mud_h = 0.0;
		float mud_film = 0.0;
		float low = mb.z;
		float fans = mb.w;
		bool body = dirt_mode == 0;

		// Dust: a fine haze everywhere, thick low down, washed into streaks by rain.
		if (dust_amt > 0.001) {
			if (body) {
				float edge = (1.0 - big.r) * 0.7 + (mid.b - 0.5) * 0.2;
				float heavy = grow(dust_amt * ma.x * 1.25, edge, 0.8) * (0.72 + 0.28 * grain) * (0.8 + 0.2 * big.b);
				dust = max(haze, heavy * mix(1.0, mix(0.25, 1.15, runs), wash * vertical * rz) * 0.8);
			} else {
				dust = max(haze, grow(dust_amt * ma.x * 1.2, (1.0 - big.r) * 0.5 + (mid.b - 0.5) * 0.2, 0.7) * (0.6 + 0.4 * mid.r)
					* (dirt_mode == 1 ? 0.7 : 0.85));
			}
		}
		// Road grime: the wet spray film, low and on the nose.
		if (grime_amt > 0.001) {
			grime = max(film, grow(grime_amt * (ma.y - 0.12) * 1.3, (1.0 - big.b * 0.3 - big.r * 0.7) * 0.7, 0.6) * (0.6 + 0.4 * grain));
			grime *= body ? mix(1.0, mix(0.4, 1.1, runs), vertical * 0.7 * rz) : 0.8;
		}
		// Mud: a brown spray film low down, splatter drops that get denser towards
		// the wheels, and a thick cake only in the arch lips / right behind the tyres.
		if (mud_amt > 0.001) {
			float f = mud_amt * ma.z;
			if (body) {
				float rays = 0.5;
				if (fans > 0.01) {
					// The spray leaves the tyre in rays: streak the fans radially around the nearer hub.
					vec2 hub = abs(m_pos.z - hub_front.x) < abs(m_pos.z - hub_rear.x) ? hub_front : hub_rear;
					vec2 hd = vec2(m_pos.z - hub.x, m_pos.y - hub.y) / wheel_r;
					rays = smoothstep(0.2, 0.8, texture(dirt_noise, vec2(atan(hd.y, hd.x) * 0.7 + dirt_b.w, length(hd) * 0.04)).b);
				}
				mud_film = grow(f * 1.3, (1.0 - big.r) * 0.5 + (mid.b - 0.5) * 0.25, 0.8) * (0.6 + 0.3 * mid.r);
				mud_film *= mix(1.0, mix(0.7, 1.15, runs), vertical * rz) * mix(0.85, 1.1, rays * fans);
				float drop_size = f * 0.45 * smoothstep(0.35, 0.9, mid.a);
				float spots = smoothstep(1.0 - drop_size, 1.0 - drop_size + 0.06, 1.0 - mid.g);
				float fine_size = f * 0.55 * low * smoothstep(0.5, 0.9, fine.a) * near;
				float specks = smoothstep(1.0 - fine_size * 0.5, 1.0 - fine_size * 0.5 + 0.08, 1.0 - fine.g);
				float cake = grow(f + (big.r - 0.5) * 0.45 + (mid.r - 0.5) * 0.2, 0.9, 0.1);
				mud = clamp(max(cake, max(spots, specks * 0.85)), 0.0, 1.0);
				mud_h = (mud * (0.5 + 0.5 * big.b) + cake * mid.r) * 0.002;
			} else {
				mud_film = grow(f * 1.1, (1.0 - mid.r) * 0.6, 0.6) * 0.6;
				float cake = grow(f + (mid.r - 0.5) * 0.7 + (fine.b - 0.5) * 0.3, 0.8, 0.08);
				float ds = f * 0.6 * smoothstep(0.3, 0.8, mid.a);
				mud = max(cake, smoothstep(1.0 - ds, 1.0 - ds + 0.07, 1.0 - mid.g));
				mud_h = mud * 0.002;
			}
		}
		// Packed snow / slush: arch lips, right behind the tyres, the lowest sills;
		// a grey slush film around it.
		if (slush_amt > 0.001) {
			float sf = slush_amt * ma.w;
			if (body) {
				float s_cake = grow(sf + (big.b - 0.5) * 0.3 + (mid.r - 0.5) * 0.45 + (fine.b - 0.5) * 0.35 * near, 0.8, 0.12);
				float s_size = sf * 0.55 * smoothstep(0.3, 0.9, mid.a);
				slush = max(s_cake, smoothstep(1.0 - s_size, 1.0 - s_size + 0.07, 1.0 - mid.g));
				grime = max(grime, grow(slush_amt * max(low, fans) * 0.9, (1.0 - big.r) * 0.6, 0.7) * 0.55);
			} else {
				slush = max(grow(sf + (fine.r - 0.5) * 0.6 + (mid.r - 0.5) * 0.3, 0.62, 0.08),
					smoothstep(1.0 - sf * 0.5 * mid.a, 1.0 - sf * 0.5 * mid.a + 0.08, 1.0 - mid.g)) * 0.85;
				grime = max(grime, grow(slush_amt * ma.x, (1.0 - big.r) * 0.6, 0.6) * 0.5);
			}
		}
		// Snow resting on roof, bonnet and boot lid.
		if (top_snow > 0.001 && mb.x > 0.0) {
			snow = grow(top_snow * mb.x * 1.25, (1.0 - big.r) * 0.75 + (mid.b - 0.5) * 0.3, 0.22);
		}
		// Water beading on the clearcoat, bigger on the flat tops.
		if (body && near_b > 0.01 && wet > 0.01) {
			vec4 bd = planar(uv, 3.6);
			float bsize = wet * smoothstep(0.35, 0.9, bd.a) * mb.y;
			bead = smoothstep(1.0 - bsize, 1.0 - bsize + 0.1, 1.0 - bd.g) * near_b;
		}

		// ---- compose, bottom layer first ----
		// Dust: pale, matte, darker when damp. Grey on snow days (salt), tan otherwise.
		vec3 dust_col = mix(vec3(0.279, 0.208, 0.126), vec3(0.218, 0.208, 0.190), clamp(slush_amt * 2.0, 0.0, 1.0));
		dust_col *= mix(0.92, 1.06, big.b);
		dust_col = mix(dust_col, dust_col * 0.55, wet);
		col = mix(col, dust_col, dust);
		rough = mix(rough, mix(0.88, 0.45, wet), dust);
		met = mix(met, 0.0, dust);
		cc *= 1.0 - dust * 0.85;
		nmap *= 1.0 - dust * 0.6;

		vec3 grime_col = vec3(0.106, 0.087, 0.061) * mix(0.85, 1.15, fine.b);
		col = mix(col, grime_col, grime * 0.85);
		rough = mix(rough, mix(0.7, 0.3, wet), grime);
		met = mix(met, 0.0, grime * 0.8);
		cc *= 1.0 - grime * 0.5;

		vec3 film_col = mix(vec3(0.106, 0.071, 0.039), vec3(0.173, 0.126, 0.076), 1.0 - wet) * mix(0.8, 1.2, big.b);
		col = mix(col, film_col, mud_film);
		rough = mix(rough, mix(0.4, 0.85, 1.0 - wet), mud_film);
		met = mix(met, 0.0, mud_film);
		cc *= 1.0 - mud_film * 0.7;
		nmap *= 1.0 - mud_film * 0.5;

		// Mud: dark and glossy when wet, drying to a lighter crust at its thin edges.
		float dryness = (1.0 - wet) * (0.4 + 0.6 * (1.0 - smoothstep(0.3, 0.9, mud_amt)));
		vec3 mud_wet = vec3(0.056, 0.032, 0.015);
		vec3 mud_dry = vec3(0.190, 0.133, 0.076);
		float thin = 1.0 - smoothstep(0.4, 1.0, mud * (0.6 + 0.4 * big.b));
		vec3 mud_col = mix(mud_wet, mud_dry, clamp(dryness * (0.45 + 0.55 * thin), 0.0, 1.0)) * mix(0.8, 1.15, mid.b);
		col = mix(col, mud_col, mud);
		rough = mix(rough, mix(0.38, 0.92, dryness), mud);
		met = mix(met, 0.0, mud);
		cc *= 1.0 - mud;
		nmap *= 1.0 - mud;

		// Slush: road slush is mostly grey-brown; only its thickest lumps stay white.
		float dirty = clamp(0.65 + (1.0 - big.r) * 0.3 + (mid.b - 0.5) * 0.5 + mud_amt * 0.3 - slush * slush_amt * 0.35, 0.0, 1.0);
		vec3 slush_col = mix(vec3(0.70, 0.73, 0.78), vec3(0.22, 0.20, 0.18), dirty) * mix(0.85, 1.08, fine.r);
		col = mix(col, slush_col, slush);
		rough = mix(rough, 0.62, slush);
		met = mix(met, 0.0, slush);
		cc *= 1.0 - slush;
		nmap *= 1.0 - slush;

		// Fresh snow: bright, soft, a little uneven.
		col = mix(col, vec3(0.80, 0.83, 0.89) * mix(0.88, 1.0, big.b), snow);
		rough = mix(rough, 0.75, snow);
		met = mix(met, 0.0, snow);
		cc *= 1.0 - snow;
		nmap *= 1.0 - snow;

		// Water beads sit on top: glassy, tiny lenses.
		float bead_h = bead * (1.0 - mud) * (1.0 - snow) * 0.0007;
		col *= 1.0 - bead * 0.2;
		rough = mix(rough, 0.04, bead * 0.8);
		cc = max(cc, bead * 0.6);
		ccr = mix(ccr, 0.02, bead);
		// Everything just rained on is a touch glossier.
		rough = mix(rough, rough * 0.7, wet * 0.5 * (1.0 - snow));

		float hgt = (mud_h + slush * 0.003) * near_m + bead_h + snow * (big.r * 0.02 + mid.r * 0.004 * near_m);
		if (hgt > 0.00001) {
			n_out = bump(NORMAL, VERTEX, hgt);
		}
	}
#endif

	NORMAL = n_out;
	ALBEDO = col;
	METALLIC = met;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	SPECULAR = specular;
#ifdef DIRT_CLEARCOAT
	CLEARCOAT = cc;
	CLEARCOAT_ROUGHNESS = ccr;
#endif
#ifdef DIRT_NORMALMAP
	NORMAL_MAP = texture(texture_normal, base_uv).rgb;
	NORMAL_MAP_DEPTH = nmap;
#endif
#ifdef DIRT_AO
	AO = dot(texture(texture_ao, base_uv), ao_channel);
	AO_LIGHT_AFFECT = ao_light_affect;
#endif
}
