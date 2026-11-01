shader_type spatial;
render_mode cull_disabled;

// Baked human figures (PeopleKit / assets/people). Per vertex CUSTOM0 =
// (region, arm weight, arm side 1 = left, region mean luminance; for the flag
// cloth: CUSTOM0.z = 0 top .. 1 bottom, .w = 1 + 0 at the stick .. 1 at the free end). Regions: 0 keep texture, 1 top, 2 bottom,
// 3 skin, 4 hair, 5 shoes, 6 hat, 7 flag cloth, 8 prop (stick).
// Per instance: COLOR = top (overalls for crew, flag for marshals), sRGB;
// INSTANCE_CUSTOM.r = phase / identity hash, .g = excitement (wave for
// marshals), .b = marshal overall tint (0 white, 1 orange).

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
// 0 stand, 1 cheer, 2 clap, 3 flag, 4 seated, 5 camera
uniform int motion = 0;
// 0 spectator, 1 crew (COLOR = overalls), 2 marshal
uniform int role = 0;
uniform vec3 pivot = vec3(0.2, 1.45, 0.0);
// Ambient wind 0 calm .. 1 storm (marshal flags; they also fly from being waved).
uniform float wind = 0.35;
#include "res://shaders/weather.gdshaderinc"
#include "res://shaders/crowd_react.gdshaderinc"

varying flat float region;
varying float lum_mean;
varying flat vec3 c_top;
varying flat vec3 c_bottom;
varying flat vec3 c_skin;
varying flat vec3 c_hair;
varying flat vec3 c_hat;
varying flat vec3 c_shoes;
varying flat vec3 c_flag;
varying flat float keep_bottom;
varying flat float chequer; // 1: the finish marshal (INSTANCE_CUSTOM.a) showing the chequered flag
varying vec2 cloth;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash(float x, float k) {
	return fract(sin(x * 91.3458 + k * 47.123) * 43758.5453);
}

vec3 pick4(float h, vec3 a, vec3 b, vec3 c, vec3 d) {
	return h < 0.25 ? a : (h < 0.5 ? b : (h < 0.75 ? c : d));
}

vec3 rot_z(vec3 v, float a) {
	return vec3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z);
}

void vertex() {
	float wind_v = max(wind, wx_wind);
	region = CUSTOM0.x;
	lum_mean = CUSTOM0.w;
	float id = INSTANCE_CUSTOM.r;
	float cheer = INSTANCE_CUSTOM.g;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	// Live reaction (CrowdReact): amplitudes only; the tempo stays tied to the
	// static excitement, or a changing rate would make TIME * rate jump.
	float react = crowd_hype(wp) * (0.65 + 0.35 * hash(id, 6.0));
	float amp = max(cheer, react);
	float h1 = hash(id, 1.0), h2 = hash(id, 2.0), h3 = hash(id, 3.0), h4 = hash(id, 4.0), h5 = hash(id, 5.0);

	// Wardrobe (sRGB, converted once per vertex).
	vec3 top = mix(vec3(dot(COLOR.rgb, vec3(0.3, 0.59, 0.11))), COLOR.rgb, 0.85);
	vec3 bottom = h1 < 0.5
		? pick4(h1 * 2.0, vec3(0.16, 0.2, 0.3), vec3(0.2, 0.26, 0.4), vec3(0.12, 0.12, 0.13), vec3(0.3, 0.3, 0.31))
		: pick4(h1 * 2.0 - 1.0, vec3(0.5, 0.44, 0.32), vec3(0.3, 0.22, 0.15), vec3(0.14, 0.16, 0.22), vec3(0.62, 0.58, 0.5));
	// Skin: multiplier on the skin texture (mostly fair, some tanned / darker).
	vec3 skin = h2 < 0.5
		? pick4(h2 * 2.0, vec3(1.0), vec3(1.06, 1.03, 1.02), vec3(0.94, 0.9, 0.86), vec3(1.0, 0.96, 0.94))
		: pick4(h2 * 2.0 - 1.0, vec3(0.86, 0.78, 0.7), vec3(0.72, 0.6, 0.5), vec3(0.97, 0.93, 0.9), vec3(0.5, 0.4, 0.33));
	vec3 hair = pick4(h3, vec3(0.1, 0.075, 0.06), vec3(0.28, 0.18, 0.11), vec3(0.6, 0.5, 0.33), vec3(0.18, 0.12, 0.08));
	if (h5 > 0.85) hair = vec3(0.55, 0.54, 0.52);
	vec3 hat = pick4(h4, vec3(0.33, 0.3, 0.26), vec3(0.14, 0.14, 0.15), vec3(0.45, 0.38, 0.28), vec3(0.2, 0.22, 0.3));
	vec3 shoes = h5 < 0.6 ? vec3(0.07, 0.06, 0.055) : (h5 < 0.85 ? vec3(0.28, 0.17, 0.1) : vec3(0.8, 0.8, 0.78));
	if (role == 1) {
		bottom = top * 0.85;
	} else if (role == 2) {
		top = mix(vec3(0.85, 0.84, 0.8), vec3(0.85, 0.3, 0.05), INSTANCE_CUSTOM.b);
		bottom = top * 0.85;
		hat = top;
	}
	chequer = 0.0;
	cloth = vec2(CUSTOM0.w - 1.0, CUSTOM0.z);
	c_top = to_linear(top);
	c_bottom = to_linear(bottom);
	c_skin = skin;
	keep_bottom = (role == 0 && h1 < 0.45) ? 1.0 : 0.0; // original jeans / skirt
	c_hair = to_linear(hair);
	c_hat = to_linear(hat);
	c_shoes = to_linear(shoes);
	vec3 flag = COLOR.rgb;
	float wave_m = cheer;
	if (role == 2) {
		// Yellow-flag marshals hold the flag still until there is an incident
		// in their sector; then every marshal there waves yellow, hard.
		bool yellow = flag.r > 0.6 && flag.b < 0.3;
		float idle = yellow ? min(cheer, 0.12) : cheer;
		float y = marshal_yellow(wp);
		if (INSTANCE_CUSTOM.a > 0.5) {
			chequer = 1.0;
			idle = 0.0;
			y = marshal_chequer.w;
		} else if (y > 0.5) {
			flag = vec3(0.9, 0.72, 0.08);
		}
		wave_m = mix(idle, 1.0, y);
	}
	c_flag = to_linear(flag);

	vec3 v = VERTEX;
	vec3 n = NORMAL;
	float t = TIME * (2.5 + cheer * 4.0) + id * 6.2831;
	float arm = CUSTOM0.y;
	float side = CUSTOM0.z * 2.0 - 1.0;
	if (motion == 1) {
		// Fists pumping, a little out of step between the arms; jumps.
		v.y += arm * sin(t + side * 1.2) * 0.09 * (0.3 + amp);
		v.x += arm * side * cos(t) * 0.03 * (1.0 + react);
		v.y += max(sin(t * 0.5), 0.0) * 0.09 * amp + max(sin(t), 0.0) * 0.07 * react;
	} else if (motion == 2) {
		// Hands clap together in front of the chest.
		float c = 0.5 + 0.5 * sin(t * 2.0);
		v.x += arm * side * c * 0.06;
		v.y += max(sin(t * 0.37), 0.0) * 0.03 * cheer + max(sin(t * 0.9), 0.0) * 0.07 * react;
	} else if (motion == 3) {
		float wave = wave_m;
		float tf = TIME * 6.0 + id * 6.2831;
		float a = (-0.15 + sin(tf) * 0.7 * wave) * clamp(arm * 1.6, 0.0, 1.0);
		if (region > 6.5 && region < 7.5) {
			// Cloth (same approach as flag.gdshader): x from the stick, y down.
			float x = CUSTOM0.w - 1.0;
			float y = CUSTOM0.z;
			float ph = id * 6.2831;
			float swing = abs(cos(tf)) * wave; // the stick's speed makes the airflow
			float gust = 0.6 + 0.4 * sin(TIME * 0.8 + ph) * sin(TIME * 0.31 + ph * 2.0);
			float w = clamp(wind_v * gust + swing * 0.9, 0.05, 1.2);
			float speed = mix(3.0, 10.0, w);
			float amp = mix(0.05, 0.12, w) * x;
			float k1 = x * 7.5 - TIME * speed + ph;
			float wz = sin(k1) * amp
				+ sin(x * 14.0 - TIME * speed * 1.7 + y * 2.2 + ph) * amp * 0.35
				+ sin(TIME * 24.0 + x * 20.0 + ph) * 0.015 * x * x * w;
			v.z += wz;
			// Slack cloth hangs from the stick; flying cloth stays out.
			float slack = 1.0 - smoothstep(0.15, 0.8, w);
			v.y -= slack * x * x * 0.45;
			v.x -= slack * x * 0.22;
			n = normalize(vec3(-cos(k1) * amp * 7.5, 0.0, 1.0));
			// The free end lags behind the swinging stick.
			a -= cos(tf) * 0.7 * wave * 0.35 * x;
		}
		v = pivot + rot_z(v - pivot, a);
		n = rot_z(n, a);
	} else if (motion == 4) {
		v.z -= sin(TIME * 0.6 + id * 20.0) * 0.02 * v.y;
		v.y += arm * max(sin(t), 0.0) * 0.08 * amp;
	} else if (motion == 0) {
		// Standing fans bob on their toes as the cars that matter come by.
		v.y += max(sin(t * 1.3), 0.0) * 0.06 * react;
	}
	// Weight shifting / idle sway around the feet.
	v.x += v.y * sin(TIME * 0.6 + id * 17.0) * 0.012;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec4 texa = texture(atlas, UV);
	vec3 tex = texa.rgb;
	// Keep only the folds and shading of the source texture on recoloured parts.
	float d = clamp(dot(tex, vec3(0.2126, 0.7152, 0.0722)) / max(to_linear(vec3(lum_mean)).r, 0.02), 0.35, 1.7);
	float dc = mix(1.0, d, 0.55);
	vec3 c = tex;
	float rough = 0.85;
	if (region < 0.5) {
		c = tex;
		rough = 0.4;
	} else if (region < 1.5) {
		c = c_top * dc;
	} else if (region < 2.5) {
		c = keep_bottom > 0.5 ? tex : c_bottom * dc;
	} else if (region < 3.5) {
		c = tex * c_skin;
		rough = 0.6;
	} else if (region < 4.5) {
		c = c_hair * mix(1.0, d, 0.5);
		rough = 0.55;
	} else if (region < 5.5) {
		c = c_shoes * dc;
		rough = 0.5;
	} else if (region < 6.5) {
		c = c_hat * dc;
	} else if (region < 7.5) {
		c = c_flag;
		if (chequer > 0.5) {
			vec2 q = floor(cloth * vec2(6.0, 4.0));
			c = mod(q.x + q.y, 2.0) < 0.5 ? vec3(0.02) : vec3(0.75);
		}
		rough = 0.8;
		BACKLIGHT = c * 0.35; // light shines through the cloth
	} else {
		c = vec3(0.04, 0.035, 0.03);
	}
	ALBEDO = c;
	ALPHA = (region > 3.5 && region < 4.5) ? texa.a : 1.0;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
}
