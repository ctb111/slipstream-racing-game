class_name Mats
extends RefCounted
## Shared library of photographic PBR materials for procedural buildings and
## props (CC0 sets in assets/materials, see CREDITS_materials.txt).
##
##   Mats.mat("concrete")                  # cached, double-sided
##   Mats.mat("plaster", Color(0.9, 0.8, 0.6))   # fixed tint (x vertex colour)
##   Mats.mat("brick", Color.WHITE, false)  # single-sided (cull back)
##   Mats.bind_world(terrain, weather.preset)    # ground grime + rain/snow, once per track
##
## Everything is world-space mapped (no UVs needed) and multiplies by the mesh
## vertex colour (white when the mesh has none), so merged vertex-coloured
## props keep their colour variety. One shader (two cull variants) for all of
## them, one material instance per (type, tint, sides).

const DIR := "res://assets/materials/%s/%s_%s.jpg"

## type: [texture set, metres per repeat, detail (tintable), extra params]
## Texture means (linear) are measured from the diffuse maps, for detail mode.
const TYPES := {
	concrete = ["concrete", 3.0, false, {bright = 1.4, rough_add = 0.05, streaks = 0.45, grime = 0.6}],
	concrete_tint = ["concrete", 3.0, true, {contrast = 0.8, streaks = 0.45, grime = 0.6}],
	plaster = ["plaster", 3.0, true, {contrast = 0.9, normal_strength = 0.5, streaks = 0.45, grime = 0.6, variation = 0.16}],
	stone = ["stone", 4.0, false, {bright = 1.6, streaks = 0.35, grime = 0.6, porosity = 0.3}], # Poly Haven large_sandstone_blocks (gx bridges)
	brick = ["brick", 1.4, false, {bright = 1.35, streaks = 0.2, grime = 0.5}],
	roof_tiles = ["roof_tiles", 2.2, true, {contrast = 0.75, streaks = 0.1, grime = 0.0, variation = 0.18}],
	slate = ["slate", 2.4, true, {contrast = 0.9, streaks = 0.1, grime = 0.0, variation = 0.12}],
	corrugated = ["corrugated", 2.4, true, {contrast = 0.7, metal_mul = 0.6, rough_mul = 0.9, streaks = 0.5, grime = 0.45, porosity = 0.4}],
	rusty_metal = ["rusty_metal", 2.0, false, {metal_mul = 1.0, streaks = 0.3, grime = 0.4, porosity = 0.4}],
	painted_metal = ["painted_metal", 1.6, true, {contrast = 0.25, normal_strength = 0.15, rough_mul = 0.5, rough_add = 0.35, streaks = 0.25, grime = 0.35, porosity = 0.3}],
	steel = ["steel", 1.2, false, {bright = 4.5, metal_add = 0.85, rough_mul = 0.85, streaks = 0.55, grime = 0.3, porosity = 0.25, variation = 0.18}],
	wood = ["wood", 2.0, false, {bright = 2.2, streaks = 0.3, grime = 0.55}],
	painted_wood = ["wood", 2.0, true, {contrast = 0.55, streaks = 0.3, grime = 0.5}],
	canvas = ["canvas", 1.0, true, {contrast = 0.6, streaks = 0.2, grime = 0.3, normal_strength = 0.6}],
	rubber = ["rubber", 0.8, true, {contrast = 0.5, rough_add = 0.1, streaks = 0.0, grime = 0.2, porosity = 0.3}],
	kerb = ["concrete", 2.0, true, {contrast = 0.35, rough_mul = 0.8, streaks = 0.0, grime = 0.35, normal_strength = 0.6, variation = 0.08}],
}
const MEANS := {
	brick = Vector3(0.152, 0.097, 0.081), canvas = Vector3(0.107, 0.105, 0.107),
	concrete = Vector3(0.264, 0.235, 0.160), corrugated = Vector3(0.099, 0.097, 0.082),
	painted_metal = Vector3(0.742, 0.707, 0.710), plaster = Vector3(0.405, 0.364, 0.349),
	roof_tiles = Vector3(0.307, 0.085, 0.026), rubber = Vector3(0.023, 0.025, 0.031),
	rusty_metal = Vector3(0.411, 0.287, 0.136), slate = Vector3(0.168, 0.162, 0.143),
	steel = Vector3(0.116, 0.120, 0.121), wood = Vector3(0.082, 0.058, 0.044),
}

static var _cache := {}
static var _shaders: Array[Shader] = []
static var _noise: NoiseTexture2D
static var _world := {} ## shader params shared by every material (weather, heightmap)


## A cached material of `type` (see TYPES, or "glass"). `tint` multiplies the
## vertex colour; `two_sided` disables back-face culling.
static func mat(type: String, tint := Color.WHITE, two_sided := true) -> Material:
	var key := "%s|%s|%d" % [type, tint.to_html(), int(two_sided)]
	if _cache.has(key):
		return _cache[key]
	var m: Material
	if type == "glass":
		m = _glass(tint, two_sided)
	else:
		m = _make(type, tint, two_sided)
	_cache[key] = m
	return m


## Per-track: bake the terrain heights for ground grime and set the weather on
## every Mats material (existing and future). `terrain` may be null.
static func bind_world(terrain: Object, preset: Dictionary) -> void: # terrain: Terrain (untyped keeps Mats standalone)
	_world = {wet = float(preset.get("wet", 0.0)), snow = float(preset.get("snow", 0.0)), has_height = 0.0}
	var heights: PackedFloat32Array = terrain.get("heights") if terrain else PackedFloat32Array()
	var side := int(sqrt(float(heights.size())))
	if side > 1 and side * side == heights.size():
		var img := Image.create_from_data(side, side, false, Image.FORMAT_RF, heights.to_byte_array())
		_world.height_tex = ImageTexture.create_from_image(img)
		_world.height_origin = terrain.get("origin")
		_world.height_cell = float(terrain.get("cell"))
		_world.height_n = float(side)
		_world.has_height = 1.0
	for m: Material in _cache.values():
		_apply_world(m)


## Photographic version of the set-dressing prop material (same mesh interface
## as shaders/set_props.gdshader; surface type inferred from paint + gloss).
static func props(atlas: Texture2D, grime_tex: Texture2D, preset: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pbr_props.gdshader")
	m.set_shader_parameter("atlas", atlas)
	m.set_shader_parameter("grime", grime_tex)
	m.set_shader_parameter("wetness", float(preset.get("wet", 0.0)))
	m.set_shader_parameter("snow", float(preset.get("snow", 0.0)))
	for pair: Array in [["concrete", "concrete"], ["metal", "painted_metal"], ["wood", "wood"], ["canvas", "canvas"]]:
		m.set_shader_parameter(pair[0] + "_alb", tex(pair[1], "diff"))
		m.set_shader_parameter(pair[0] + "_nrm", tex(pair[1], "nor_gl"))
		m.set_shader_parameter(pair[0] + "_mean", MEANS[pair[1]])
	_apply_world(m)
	return m


static func _shader(two_sided: bool) -> Shader:
	if _shaders.is_empty():
		_shaders = [load("res://shaders/pbr_triplanar.gdshader"), load("res://shaders/pbr_triplanar_2s.gdshader")]
	return _shaders[int(two_sided)]


static func noise() -> NoiseTexture2D:
	if _noise == null:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.035
		nz.fractal_octaves = 4
		nz.seed = 1234
		_noise = NoiseTexture2D.new()
		_noise.noise = nz
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
	return _noise


static func tex(set_name: String, kind: String) -> Texture2D:
	return load(DIR % [set_name, set_name, kind])


static func _make(type: String, tint: Color, two_sided: bool) -> ShaderMaterial:
	var def: Array = TYPES.get(type, TYPES.concrete)
	var set_name: String = def[0]
	var m := ShaderMaterial.new()
	m.shader = _shader(two_sided)
	m.set_shader_parameter("albedo_tex", tex(set_name, "diff"))
	m.set_shader_parameter("normal_tex", tex(set_name, "nor_gl"))
	m.set_shader_parameter("arm_tex", tex(set_name, "arm"))
	m.set_shader_parameter("noise_tex", noise())
	m.set_shader_parameter("tile_m", def[1])
	m.set_shader_parameter("detail", 1.0 if def[2] else 0.0)
	m.set_shader_parameter("mean", MEANS.get(set_name, Vector3(0.5, 0.5, 0.5)))
	m.set_shader_parameter("tint", tint)
	var extra: Dictionary = def[3]
	for k: String in extra:
		m.set_shader_parameter(k, extra[k])
	_apply_world(m)
	return m


static func _apply_world(m: Material) -> void:
	if _world.is_empty():
		return
	if m is ShaderMaterial:
		for k: String in _world:
			(m as ShaderMaterial).set_shader_parameter(k, _world[k])
	elif m is StandardMaterial3D:
		var s := m as StandardMaterial3D
		s.roughness = lerpf(0.06, 0.02, float(_world.wet))


static func _glass(tint: Color, two_sided: bool) -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.albedo_color = Color(0.1, 0.12, 0.14) * tint
	g.vertex_color_use_as_albedo = true
	g.vertex_color_is_srgb = true
	g.roughness = 0.06
	g.metallic = 0.3
	g.metallic_specular = 1.0
	if two_sided:
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
	return g
