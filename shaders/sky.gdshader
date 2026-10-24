shader_type sky;
// Clouds are computed at quarter resolution (a smooth sky needs no more) and
// the full-res pass just composites them; the radiance cubemap (reflections,
// ambient) gets a cheap single-octave version.
render_mode use_quarter_res_pass;

// Photographic sky (HDRI) with a moving procedural cloud deck on top.
uniform sampler2D panorama : source_color, filter_linear;
uniform float panorama_energy = 1.0;
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform float coverage = 0.45; // 0 = clear .. 1 = solid overcast
uniform float softness = 0.2; // edge fuzziness
uniform float cloud_scale = 0.55;
uniform vec2 wind = vec2(0.006, 0.0025); // drift per second, in noise space
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.45, 0.48, 0.55);
uniform float cloud_brightness = 1.4; // HDR level of lit cloud tops
uniform float cloud_opacity = 0.95;
uniform float flash = 0.0; // lightning
// The deck is a layer this far above the world (not at infinity), so clouds
// slowly slide overhead as the car drives.
uniform float cloud_height = 1400.0;
// Changeable weather (WeatherCycle): crossfade to an overcast panorama, and a
// script-integrated cloud offset so a changing wind never makes clouds jump.
uniform sampler2D panorama_b : source_color, filter_linear;
uniform float panorama_b_energy = 1.0;
uniform float pano_mix = 0.0;
uniform vec2 cloud_drift = vec2(0.0);
// Night (Weather._night_sky): the HDRI's photographed moon is clipped (it would
// bloom into a blob) and replaced by a crisp disc and halo; procedural stars.
// All zero by day, so day skies skip this entirely.
uniform float panorama_clamp = 1e6;
uniform float star_strength = 0.0;
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float moon_size = 0.0; // angular radius in radians, 0 = no moon
uniform vec3 moon_color : source_color = vec3(0.85, 0.9, 1.0);
uniform float moon_energy = 6.0;
// Distant ranges on the horizon (Weather): two layers of ridgelines, the far
// one tall and hazy, the near one low and darker, so the horizon has depth
// behind the hills ring. Colour comes from the sky behind them (aerial
// perspective), so they suit every time of day. 0 = off.
uniform float ridge_strength = 0.0;
uniform float ridge_height = 1.0; // scales the elevation of both layers
uniform float ridge_snow = 0.0; // snow on the far peaks
uniform float ridge_seed = 0.0;
// Grade the photographed sky (dawn: rose at the horizon, cool blue above).
uniform vec3 tint_low : source_color = vec3(1.0);
uniform vec3 tint_high : source_color = vec3(1.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// One layer of stars: a sparse point in some cells of a grid on the sphere.
float star_layer(vec3 dir, float cells, float density) {
	vec3 g = dir * cells;
	vec3 c = floor(g);
	float h = hash13(c);
	if (h > density) return 0.0;
	vec3 pos = c + 0.25 + 0.5 * vec3(hash13(c + 7.1), hash13(c + 3.7), hash13(c + 1.3));
	float d = length(g - pos);
	float mag = pow(hash13(c + 9.2), 6.0) * 5.0 + 0.25; // a few bright, many faint
	float twinkle = 0.75 + 0.25 * sin(TIME * (2.0 + h * 40.0) + h * 90.0);
	return mag * twinkle * smoothstep(0.14, 0.0, d);
}

// Stars (full-res view only) and the moon, added to the panorama under the clouds.
vec3 night_sky(vec3 base, vec3 dir, bool cubemap) {
	if (star_strength > 0.0 && !cubemap && dir.y > -0.02) {
		float fade = smoothstep(-0.02, 0.25, dir.y); // horizon haze swallows them
		float s = star_layer(dir, 220.0, 0.16) + star_layer(dir, 420.0, 0.1) * 0.6;
		vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.78), hash13(floor(dir * 220.0) + 4.0));
		base += tint * s * star_strength * fade;
	}
	if (moon_size > 0.0) {
		vec3 md = normalize(moon_dir);
		float ang = acos(clamp(dot(dir, md), -1.0, 1.0));
		base += moon_color * moon_energy * (0.012 * exp(-ang * 9.0) + 0.06 * exp(-ang * 60.0));
		if (!cubemap && ang < moon_size * 1.2) {
			vec3 mt = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
			vec3 mb = cross(mt, md);
			vec2 uv = vec2(dot(dir - md, mt), dot(dir - md, mb)) / moon_size; // -1..1 over the disc
			float disc = smoothstep(1.0, 0.94, length(uv));
			float maria = texture(cloud_noise, uv * 0.18 + 0.3).r;
			float albedo = mix(0.55, 1.0, smoothstep(0.35, 0.65, maria));
			float limb = sqrt(max(1.0 - dot(uv, uv), 0.0)) * 0.35 + 0.65;
			base = mix(base, moon_color * moon_energy * albedo * limb, disc);
		}
	}
	return base;
}

// All octaves drift the same way (slightly different speeds so the shapes
// evolve): coherent weather, not boiling.
float clouds(vec2 p, vec2 t) {
	return texture(cloud_noise, p * 0.22 + t).r * 0.55
		+ texture(cloud_noise, p * 0.61 + t * 1.15).r * 0.3
		+ texture(cloud_noise, p * 1.9 + t * 1.3).r * 0.15;
}

vec4 cloud_layer(vec3 dir, bool cheap) {
	vec2 p = (dir.xz / (dir.y + 0.1) + POSITION.xz / cloud_height) * cloud_scale;
	vec2 t = wind * TIME + cloud_drift;
	float n = cheap ? texture(cloud_noise, p * 0.22 + t).r : clouds(p, t);
	float lo = 1.0 - coverage;
	float density = smoothstep(lo - softness, lo + softness, n);
	float lit = 0.55 - density * 0.25;
	if (!cheap) {
		// Denser towards the sun side = darker underside (cheap self-shadowing).
		vec2 to_sun = LIGHT0_ENABLED ? normalize(LIGHT0_DIRECTION.xz + vec2(0.0001)) : vec2(0.7, 0.7);
		float n_sun = clouds(p + to_sun * 0.05, t);
		lit = clamp(0.65 - (n_sun - n) * 5.0 - density * 0.25, 0.0, 1.0);
	}
	float sun_glow = LIGHT0_ENABLED ? pow(max(dot(dir, LIGHT0_DIRECTION), 0.0), 6.0) : 0.0;
	vec3 col = mix(cloud_shadow, cloud_lit, lit) * cloud_brightness * (1.0 + sun_glow * 1.2);
	float a = density * cloud_opacity * smoothstep(0.0, 0.2, dir.y);
	return vec4(col, a);
}

// Ridgeline elevation (radians-ish, on dir.y) around the horizon; noise read
// along a circle so it wraps seamlessly.
float ridge(vec2 az, float r, float seed) {
	vec2 c = az * r + vec2(seed, seed * 0.61);
	float n = textureLod(cloud_noise, c, 0.0).r * 0.6 + textureLod(cloud_noise, c * 3.1 + 0.37, 0.0).r * 0.28
		+ textureLod(cloud_noise, c * 9.7 + 0.71, 0.0).r * 0.12;
	return n;
}

// Mountains over the sky colour `col` (seen through `base`'s air).
vec3 ranges(vec3 col, vec3 base, vec3 dir) {
	if (dir.y > 0.09 * ridge_height || dir.y < -0.05) return col;
	vec2 az = normalize(dir.xz + vec2(1e-5));
	float hf = ridge(az, 0.42, ridge_seed);
	hf = 0.004 + 0.075 * ridge_height * pow(smoothstep(0.3, 0.85, hf), 1.6);
	float hn = ridge(az, 1.1, ridge_seed + 0.53);
	hn = 0.002 + 0.03 * ridge_height * smoothstep(0.25, 0.8, hn);
	float aa = 0.0012;
	float mf = smoothstep(hf + aa, hf - aa, dir.y);
	float mn = smoothstep(hn + aa, hn - aa, dir.y);
	// Far range: haze of the sky, slightly darker and bluer; snow near the tops.
	base /= max(1.0, max(base.r, max(base.g, base.b)) / 1.5); // the sun's glare stops at the ridge
	vec3 haze = base * vec3(0.8, 0.84, 0.95);
	float lum = dot(base, vec3(0.3, 0.55, 0.15));
	float cap = ridge_snow * smoothstep(hf - 0.035 * ridge_height, hf - 0.008, dir.y) * smoothstep(0.03, 0.06, hf);
	vec3 far_c = mix(haze, vec3(lum * 1.05) * vec3(0.98, 0.99, 1.04), cap * 0.8);
	vec3 near_c = base * vec3(0.6, 0.64, 0.74);
	col = mix(col, far_c, mf * ridge_strength * 0.85);
	col = mix(col, near_c, mn * ridge_strength);
	return col;
}

void sky() {
	vec3 dir = EYEDIR;
	if (AT_QUARTER_RES_PASS) {
		COLOR = vec3(0.0);
		ALPHA = 0.0;
		if (dir.y > 0.0) {
			vec4 c = cloud_layer(dir, false);
			COLOR = c.rgb;
			ALPHA = c.a;
		}
	} else {
		vec3 base = min(texture(panorama, SKY_COORDS).rgb, vec3(panorama_clamp)) * panorama_energy;
		base *= mix(tint_low, tint_high, smoothstep(0.0, 0.45, dir.y));
		if (pano_mix > 0.0) {
			base = mix(base, texture(panorama_b, SKY_COORDS).rgb * panorama_b_energy, pano_mix);
		}
		if (star_strength > 0.0 || moon_size > 0.0) {
			base = night_sky(base, dir, AT_CUBEMAP_PASS);
		}
		vec4 c = vec4(0.0);
		if (AT_CUBEMAP_PASS) {
			if (dir.y > 0.0) {
				c = cloud_layer(dir, true);
			}
		} else {
			c = QUARTER_RES_COLOR;
		}
		vec3 sky_c = mix(base, c.rgb, c.a);
		if (ridge_strength > 0.0) {
			sky_c = ranges(sky_c, base, dir);
		}
		COLOR = sky_c * (1.0 + flash * 3.0);
	}
}
