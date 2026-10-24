shader_type spatial;
render_mode cull_back;

// Photographic drop-in for set_props.gdshader (same mesh interface):
// COLOR = sRGB paint colour, UV2.x = 1 for printed atlas faces (at UV),
// UV2.y = gloss (0 matte .. 1 glass). The surface type is inferred per face
// from paint + gloss, and a CC0 PBR set (see assets/materials) adds the
// pattern, normals and roughness on top of the paint colour:
//   glossy (>= 0.3)             -> painted metal (bodywork, cabins, drums)
//   neutral bluish grey, matte  -> galvanised steel (poles, frames)
//   neutral warm grey, matte    -> concrete (blocks, aprons, bases)
//   brown, matte                -> weathered wood (sheds, crates, benches)
//   everything else, matte      -> canvas / fabric (awnings, marquees, flags)
// Mapping is planar in each face's own frame (world metres), weathering is
// grime noise, ground grime from the terrain heightmap, rain and snow.
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D grime : filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D concrete_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metal_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wood_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D canvas_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D canvas_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 concrete_mean = vec3(0.264, 0.235, 0.160);
uniform vec3 metal_mean = vec3(0.742, 0.707, 0.710);
uniform vec3 wood_mean = vec3(0.082, 0.058, 0.044);
uniform vec3 canvas_mean = vec3(0.107, 0.105, 0.107);
uniform float wetness = 0.0;
uniform float snow = 0.0;
#include "res://shaders/weather.gdshaderinc"
// Mats.bind_world names
uniform float wet = -1.0; // overrides wetness when set by Mats
uniform float has_height = 0.0;
uniform vec2 height_origin = vec2(0.0);
uniform float height_cell = 1.0;
uniform float height_n = 513.0;

varying vec3 wpos;
varying vec3 wnrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = normalize(wnrm);
	float curved = step(0.02, length(fwidth(n)));
	vec3 f = n;
	if (curved > 0.5) {
		vec3 a = abs(n);
		f = a.y > max(a.x, a.z) ? vec3(0.0, sign(n.y), 0.0) : (a.x > a.z ? vec3(sign(n.x), 0.0, 0.0) : vec3(0.0, 0.0, sign(n.z)));
	}
	vec3 t = abs(f.y) > 0.92 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), f));
	vec3 b = cross(f, t);
	vec2 m = vec2(dot(wpos, t), -dot(wpos, b));

	vec3 w = abs(wnrm);
	w /= (w.x + w.y + w.z);
	float g = texture(grime, wpos.zy * 0.23).r * w.x + texture(grime, wpos.xz * 0.23).r * w.y
		+ texture(grime, wpos.xy * 0.23).r * w.z;
	float gloss = UV2.y;
	float printed = UV2.x;
	float wv = max(wet >= 0.0 ? wet : wetness, wx_wet);

	vec3 paint = COLOR.rgb;
	float mx = max(paint.r, max(paint.g, paint.b));
	float mn = min(paint.r, min(paint.g, paint.b));
	float sat = (mx - mn) / max(mx, 0.001);
	vec3 base = to_linear(paint);
	vec3 col = base;
	vec3 tn = vec3(0.0, 0.0, 1.0);
	float rough = mix(0.86, 0.3, gloss);
	float metal = gloss * 0.3;
	float porous = 1.0 - gloss * 0.5;
	if (printed < 0.5 && gloss < 0.95) {
		if (gloss >= 0.3) {
			vec3 s = texture(metal_alb, m / 1.6).rgb;
			col = base * mix(vec3(1.0), s / metal_mean, 0.35);
			tn = texture(metal_nrm, m / 1.6).xyz * 2.0 - 1.0;
			tn.xy *= 0.3;
			rough = mix(0.45, 0.22, gloss) + (1.0 - s.g / metal_mean.g) * 0.15;
		} else if (sat < 0.1 && mx > 0.25) {
			vec3 s = texture(concrete_alb, m / 3.0).rgb;
			tn = texture(concrete_nrm, m / 3.0).xyz * 2.0 - 1.0;
			if (paint.b > paint.r) { // cool grey: galvanised steel
				col = base * mix(vec3(1.0), s / concrete_mean, 0.25);
				tn.xy *= 0.25;
				rough = 0.42 + (g - 0.5) * 0.25;
				metal = 0.75;
				porous = 0.3;
			} else {
				col = base * mix(vec3(1.0), s / concrete_mean, 0.8);
				rough = 0.9;
			}
		} else if (paint.r > paint.g && paint.g > paint.b && paint.r - paint.b > 0.08 && mx < 0.5) {
			vec3 s = texture(wood_alb, m / 2.0).rgb;
			col = base * mix(vec3(1.0), s / wood_mean, 0.7);
			tn = texture(wood_nrm, m / 2.0).xyz * 2.0 - 1.0;
			rough = 0.85;
		} else {
			vec3 s = texture(canvas_alb, m).rgb;
			col = base * mix(vec3(1.0), s / canvas_mean, 0.45);
			tn = texture(canvas_nrm, m).xyz * 2.0 - 1.0;
			tn.xy *= 0.6;
			rough = 0.92;
		}
	}
	col = mix(col, texture(atlas, UV).rgb, printed);
	col *= mix(0.78, 1.08, g) * mix(1.0, 0.92, gloss * (1.0 - g));
	rough += (g - 0.5) * 0.18;
	if (has_height > 0.5 && gloss < 0.95) {
		vec2 hv = ((wpos.xz - height_origin) / height_cell + 0.5) / height_n;
		float above = wpos.y - texture(height_tex, hv).r;
		float dirt = (1.0 - smoothstep(0.0, 0.7, above + (g - 0.5) * 0.5)) * 0.45;
		col = mix(col, col * vec3(0.52, 0.47, 0.4), dirt);
	}
	col *= mix(1.0, 0.68, wv * porous);
	rough = mix(rough, rough * 0.35, wv);
	float cap = max(snow, wx_snow) * smoothstep(0.45, 0.8, wnrm.y) * smoothstep(0.2, 0.5, g + 0.15);
	col = mix(col, vec3(0.85, 0.87, 0.91), cap);
	vec3 nw = normalize(t * tn.x + b * tn.y + n * max(tn.z, 0.05));
	nw = normalize(mix(nw, n, cap));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = clamp(mix(rough, 0.7, cap), 0.05, 1.0);
	METALLIC = metal * (1.0 - cap);
	SPECULAR = 0.5;
}
