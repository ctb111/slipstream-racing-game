shader_type spatial;
render_mode cull_back;

// Rendered walls with PHOTO windows, doors and shopfronts (FacadeKit atlas,
// real photos, never drawn procedurally). Each unit is placed per bay and
// storey at its real size (scaled down uniformly when a bay is too narrow,
// never stretched); between them the plaster texture shows, tinted by the
// vertex colour. UV is in metres (x along the face from the viewer's left,
// y above the street); UV2 packs the layout:
//   UV2.x = face width + 1000 * style (0 house, 1 shop, 2 blank, 3 farmhouse, 4 brick block)
//   UV2.y = wall height + 100 * variant (0..9)
uniform sampler2D wall_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wall_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D atlas_alb : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D block_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D block_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D block_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 cell_size[19]; // metres, FacadeKit.SIZES
uniform int region = 0; // 0 north (German town), 1 south (Mediterranean shutters)
uniform float lit = 0.0; // dusk / night: some windows glow
uniform float wet = 0.0;
#include "res://shaders/weather.gdshaderinc"

// FacadeKit.CELLS indices per region.
const int WIN_N[3] = int[](1, 0, 2);
const int WIN_S[4] = int[](4, 5, 3, 6);
const int WIN_FARM[3] = int[](2, 4, 5);
const int DOOR_N[6] = int[](8, 9, 11, 10, 14, 7);
const int DOOR_S[3] = int[](12, 9, 10);
const float PADF = 16.0 / 512.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Walls are vertical: tangent along the face (UV.x), binormal up (UV.y).
	TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL));
	BINORMAL = vec3(0.0, 1.0, 0.0);
}

// Photo unit `cell` occupying [lo, lo + sz] (metres) on the face: returns
// rgba (a = coverage) and writes normal/mask. Gradients come from the
// continuous metre coordinate so mips don't seam at bay boundaries.
vec4 unit(int cell, vec2 m, vec2 dmx, vec2 dmy, vec2 lo, vec2 sz, out vec3 nrm, out vec2 msk) {
	vec2 l = (m - lo) / sz;
	nrm = vec3(0.5, 0.5, 1.0);
	msk = vec2(0.0, 0.9);
	if (l.x < 0.0 || l.y < 0.0 || l.x > 1.0 || l.y > 1.0) {
		return vec4(0.0);
	}
	vec2 cxy = vec2(float(cell % 4), float(cell / 4));
	vec2 inner = vec2(l.x, 1.0 - l.y) * (1.0 - 2.0 * PADF) + PADF;
	vec2 uv = (cxy + inner) * vec2(0.25, 0.2);
	vec2 k = (1.0 - 2.0 * PADF) * vec2(0.25, 0.2) / sz;
	vec2 dx = dmx * k * vec2(1.0, -1.0);
	vec2 dy = dmy * k * vec2(1.0, -1.0);
	nrm = textureGrad(atlas_nor, uv, dx, dy).rgb;
	msk = textureGrad(atlas_mask, uv, dx, dy).rg;
	return textureGrad(atlas_alb, uv, dx, dy);
}

void fragment() {
	float wet_v = max(wet, wx_wet * 0.6);
	vec2 m = UV;
	vec2 dmx = dFdx(m);
	vec2 dmy = dFdy(m);
	float face_w = mod(UV2.x, 1000.0);
	int style = int(floor(UV2.x / 1000.0 + 0.001));
	float wall_h = mod(UV2.y, 100.0);
	int variant = int(floor(UV2.y / 100.0 + 0.001));

	vec3 tint = COLOR.rgb;
	vec3 plaster = texture(wall_albedo, m * 0.28).rgb;
	vec3 col = plaster * tint * 1.25;
	vec3 nmap = texture(wall_normal, m * 0.28).rgb;
	float rough = 0.92;
	vec3 emit = vec3(0.0);

	if (style == 4) {
		// Brick block (ambientCG Facade018A): one 2048 tile = 6 bays x 6 storeys.
		vec2 bu = vec2(m.x, -m.y) / 21.0;
		col = texture(block_alb, bu).rgb * mix(vec3(1.0), tint, 0.35);
		nmap = texture(block_nor, bu).rgb;
		vec2 bm = texture(block_mask, bu).rg;
		rough = bm.g;
		vec2 win = floor(bu * 6.0);
		float hw = hash21(win + float(variant) * 3.1);
		float on = step(0.72, hw);
		emit = mix(vec3(1.0, 0.7, 0.4), vec3(0.8, 0.87, 1.0), step(0.93, hw)) * bm.r * lit * on * (0.35 + 0.5 * fract(hw * 37.0));
	} else {
		// Grime towards the ground (soft, no hard plinth line).
		col *= mix(0.74, 1.0, smoothstep(-0.2, 1.4, m.y));
	}

	if (style < 2 || style == 3) {
		bool south = region == 1;
		bool farm = style == 3;
		int win = farm ? WIN_FARM[variant % 3] : (south ? WIN_S[variant % 4] : WIN_N[variant % 3]);
		int door = south ? DOOR_S[(variant * 7 + 1) % 3] : DOOR_N[(variant * 5 + 2) % 6];
		vec2 wsz = cell_size[win];
		float bay_target = farm ? 3.4 : (south ? 3.1 : 2.8);
		float bays = max(1.0, floor(face_w / max(bay_target, wsz.x + 0.5)));
		float bay_w = face_w / bays;
		float bay = clamp(floor(m.x / bay_w), 0.0, bays - 1.0);
		float bx0 = bay * bay_w;
		float ground_h = style == 1 ? 3.7 : 3.3;
		float floor_h = 3.0 + float(variant % 2) * 0.2;
		float s = min(1.0, min((bay_w - 0.45) / wsz.x, (floor_h - 0.75) / wsz.y));
		vec2 usz = wsz * max(s, 0.0);
		vec4 u = vec4(0.0);
		vec3 un = vec3(0.5, 0.5, 1.0);
		vec2 um = vec2(0.0, 0.9);
		float seed = 0.0;
		bool enough = face_w > 1.6 && s > 0.45;
		if (enough && m.y < ground_h) {
			seed = hash21(vec2(bay, 0.0) + float(variant));
			float shop_x0 = 0.0;
			float shop_x1 = 0.0;
			if (style == 1 && face_w > 4.2) {
				int shop = south ? (variant % 2 == 0 ? 15 : 18) : (variant % 3 == 0 ? 13 : (variant % 3 == 1 ? 16 : 17));
				vec2 ssz = cell_size[shop];
				ssz *= min(1.0, min((face_w - 1.0) / ssz.x, (ground_h - 0.5) / ssz.y));
				shop_x0 = (face_w - ssz.x) * 0.5;
				shop_x1 = shop_x0 + ssz.x;
				u = unit(shop, m, dmx, dmy, vec2(shop_x0, 0.15), ssz, un, um);
			}
			if (u.a <= 0.0) {
				float door_bay = style == 1 ? -1.0 : mod(float(variant), bays);
				if (bay == door_bay) {
					vec2 dsz = cell_size[door];
					dsz *= min(1.0, min((bay_w - 0.3) / dsz.x, (ground_h - 0.3) / dsz.y));
					u = unit(door, m, dmx, dmy, vec2(bx0 + (bay_w - dsz.x) * 0.5, 0.0), dsz, un, um);
				} else {
					vec2 lo = vec2(bx0 + (bay_w - usz.x) * 0.5, max(0.9, ground_h - 0.45 - usz.y));
					bool clear = style != 1 || lo.x + usz.x < shop_x0 - 0.2 || lo.x > shop_x1 + 0.2;
					if (clear && (!farm || mod(bay + float(variant), 2.0) < 1.0)) {
						u = unit(win, m, dmx, dmy, lo, usz, un, um);
					}
				}
			}
		} else if (enough) {
			float fl = floor((m.y - ground_h) / floor_h);
			float base = ground_h + fl * floor_h;
			vec2 lo = vec2(bx0 + (bay_w - usz.x) * 0.5, base + 0.85);
			if (lo.y + usz.y + 0.3 < wall_h) {
				u = unit(win, m, dmx, dmy, lo, usz, un, um);
			}
			seed = hash21(vec2(bay, fl + 1.0) + float(variant) * 7.0);
		}
		float a = u.a;
		col = mix(col, u.rgb, a);
		nmap = mix(nmap, un, a);
		rough = mix(rough, um.g, a);
		float glass = um.r * a;
		if (lit > 0.0 && seed > 0.66) {
			// About a third of the windows lit, each its own: mostly warm lamps at
			// varied levels, some pale/cool, the odd TV flicker. Unlit glass keeps the photo.
			float k = fract(seed * 13.7);
			vec3 wc = k < 0.55 ? vec3(1.0, 0.68, 0.36) : (k < 0.8 ? vec3(1.0, 0.86, 0.66) : (k < 0.93 ? vec3(0.78, 0.86, 1.0)
				: vec3(0.5, 0.62, 1.0) * (0.75 + 0.25 * sin(TIME * 7.0 + seed * 50.0))));
			float lvl = 0.3 + 0.7 * fract(seed * 71.3);
			emit = wc * lit * lvl * glass;
			col = mix(col, col * 0.55, glass * lit);
		}
	}
	col *= mix(1.0, 0.7, wet_v);
	ALBEDO = col;
	NORMAL_MAP = nmap;
	ROUGHNESS = mix(rough, rough * 0.5, wet_v);
	METALLIC = 0.0;
	EMISSION = emit;
}
