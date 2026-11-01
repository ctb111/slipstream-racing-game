class_name Circuit
extends Node3D
## One complete circuit: sky/lighting, ground, road + run-off + barriers,
## trackside props, hills, forest, and the racing line used by bots.

var def: Dictionary
var curve: Curve3D
var line: RacingLine
var start_offset := 0.0
var noise_tex: NoiseTexture2D
var terrain: Terrain
var weather: Weather

## Set dressing, theme-specific scenery and ambient sound, if present.
const EXTRA_BUILDERS := [
	"res://scripts/track/set_dressing.gd",
	"res://scripts/track/themes.gd",
	"res://scripts/world/ambience.gd",
	"res://scripts/world/crowd_react.gd",
	"res://scripts/track/road_decals.gd",
	"res://scripts/track/night_lights.gd",
	"res://scripts/world/atmosphere.gd",
	"res://scripts/world/road_leaves.gd",
	"res://scripts/track/gimmicks/gimmicks.gd", # per-track set pieces (Gx kit)
	"res://scripts/world/wildlife_builder.gd", # animals, birds, pets (last: needs the crowds)
]


## Loading progress: emitted before each build step with 0..1 and a label.
signal build_progress(fraction: float, label: String)
## When true, build() yields a frame between steps so a loading screen can draw.
var async_build := false
var _step_t := 0
var _step_label := ""
var _step_w := 0.0
## Rough share of the build time per step (windowed, M1), for the progress bar;
## unlisted steps count 0.5.
const STEP_WEIGHT := {"Terrain": 4.0, "Tarmac and barriers": 2.0, "Trackside": 5.0, "Scenery": 9.0,
	"Set Dressing": 1.5, "Themes": 6.0, "Grass": 1.0, "Forest": 1.0}
const WEIGHT_TOTAL := 36.0
var load_times := {} ## label -> ms, for --loadprof


## Marks the start of a build step: records the previous step's time, reports
## progress and (async builds) lets a frame render. Always `await` it.
func _step(label: String) -> void:
	var now := Time.get_ticks_usec()
	if _step_label != "":
		load_times[_step_label] = (now - _step_t) / 1000.0
	if _step_label != "":
		_step_w += STEP_WEIGHT.get(_step_label, 0.5)
	_step_label = label
	build_progress.emit(clampf(_step_w / WEIGHT_TOTAL, 0.0, 0.99), label)
	if async_build and is_inside_tree():
		await get_tree().process_frame
		await get_tree().process_frame
	_step_t = Time.get_ticks_usec()


func build(track_def: Dictionary) -> void:
	def = track_def
	TrackBuilder.configure(def) # street circuits: no gravel, concrete barriers
	await _step("Sky and weather")
	noise_tex = _make_noise()
	var kind: int = def.get("weather", Weather.Kind.CLEAR)
	if Game.weather_override >= 0:
		kind = Game.weather_override
	# `kind` is a Weather condition: 0..3 day kinds, 4..6 their night variants.
	# 7/8 = changeable: lamps are built and switched on/off as the sky darkens.
	Car.headlights = kind != Weather.Kind.CLEAR
	Car.night = Weather.cond_night(kind)
	Car.lamps_on = true
	var timeline: Dictionary = Game.weather_timeline if Weather.cond_changeable(kind) else {}
	weather = Weather.create(self, kind, false, timeline)
	await _step("Ground")
	var ground_mat := WorldBuilder.terrain_material(noise_tex)
	ground_mat.set_shader_parameter("wetness", weather.preset.wet)
	ground_mat.set_shader_parameter("snow", weather.preset.snow)
	WorldBuilder.build_ground(self, ground_mat)
	var bounds2 := Rect2(Vector2(def.points[0].x, def.points[0].z), Vector2.ZERO)
	for p in def.points:
		bounds2 = bounds2.expand(Vector2(p.x, p.z))
	# Hills first, then the track laid onto them, then the ground shaped to the road.
	await _step("Terrain")
	terrain = Terrain.new(bounds2, 460.0, def.get("hills", 16.0), hash(def.id))
	terrain.peaks = def.get("peaks", [])
	terrain.configure(def) # banks, ridges, designed profile (Terrain.STYLE / def.terrain)
	if def.get("fixed_heights", false): # the points carry the real profile; the land follows it
		terrain.set_base(def.points, def.get("land_bumps", []))
		curve = TrackBuilder.make_curve(def.points)
	else:
		curve = TrackBuilder.make_curve(terrain.elevate(def.points))
	terrain.carve(curve, TrackDefs.ROAD_WIDTH)
	if def.has("terrain_shaper"): # per-track landforms (river channel, rock cut), before anything sits on the ground
		load(def.terrain_shaper).shape(terrain, curve, def)
	terrain.build_nodes(self, ground_mat, 0.6, 0.035) # grass: slower, but never a bog
	set_meta("terrain", terrain)
	await _step("Tarmac and barriers")
	TrackBuilder.build(self, curve, TrackDefs.ROAD_WIDTH, _track_materials(), terrain)
	var start: Vector3 = def.start
	start_offset = curve.get_closest_offset(Vector3(start.x, terrain.height_at(start.x, start.z), start.z))
	await _step("Trackside")
	# Trackside props are optional so the game still runs without them.
	if ResourceLoader.exists("res://scripts/track/track_props.gd"):
		var props = load("res://scripts/track/track_props.gd")
		props.build(self, _rotated_curve(), TrackDefs.ROAD_WIDTH, noise_tex)

	var lap_curve := _rotated_curve()
	await _step("Scenery")
	Scenery.build(self, lap_curve, TrackDefs.ROAD_WIDTH, weather.preset)
	# Optional add-on builders, each owned by its own file: they get the circuit
	# node, a curve starting at the start line, the road width and the weather.
	for path in EXTRA_BUILDERS:
		if ResourceLoader.exists(path):
			await _step(path.get_file().get_basename().capitalize())
			var builder = load(path)
			builder.build(self, lap_curve, TrackDefs.ROAD_WIDTH, weather.preset)
	await _step("Grass")
	Grass.build(self, curve, terrain, TrackDefs.ROAD_WIDTH, weather.preset, noise_tex)
	var bounds := AABB(def.points[0], Vector3.ZERO)
	for p in def.points:
		bounds = bounds.expand(p)
	var centre := bounds.get_center()
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5
	await _step("Hills")
	WorldBuilder.build_hills(self, centre, radius + 450.0, ground_mat)
	var area := Rect2(bounds.position.x - 320.0, bounds.position.z - 320.0, bounds.size.x + 640.0, bounds.size.z + 640.0)
	var tree_count := int(clampf(area.get_area() / 700.0, 1200.0, 3200.0))
	var wind := 0.9 if weather.kind == Weather.Kind.STORM else (0.45 if weather.kind == Weather.Kind.SNOW else 0.3)
	set_meta("wind", wind)
	PeopleKit.set_wind(wind)
	await _step("Forest")
	WorldBuilder.build_forest(self, curve, TrackDefs.ROAD_WIDTH * 0.5 + 24.0, area, tree_count, get_meta("no_trees", []),
		terrain, weather.preset.snow, WorldBuilder.foliage_material(noise_tex, wind, 12.0))
	# Bots corner and brake to the conditions.
	var g: float = weather.preset.road_grip
	await _step("Racing line")
	line = RacingLine.new(curve, TrackDefs.ROAD_WIDTH, g * RacingLine.AI_LAT_G, RacingLine.AI_BRAKE * g)
	line.built_grip = g # bots rescale to Car.weather_road_grip as the weather changes
	await _step("")
	build_progress.emit(1.0, "")


## Props expect offset 0 to be the start/finish line.
func _rotated_curve() -> Curve3D:
	var pts: Array = []
	var n := 400
	var length := curve.get_baked_length()
	for i in n:
		pts.append(curve.sample_baked(fposmod(start_offset + i * length / n, length)))
	var c := Curve3D.new()
	c.bake_interval = 0.5
	for i in n + 1:
		var p: Vector3 = pts[i % n]
		var handle: Vector3 = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]) / 6.0
		c.add_point(p, -handle, handle)
	return c


## Grid slot 0 is pole. Two staggered columns behind the start line.
func grid_transform(slot: int) -> Transform3D:
	var back := 12.0 + slot * 8.0
	var lateral := -2.8 if slot % 2 == 0 else 2.8
	return line.transform_at(start_offset - back, lateral)


func _make_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	return t


func _track_materials() -> Dictionary:
	var road := ShaderMaterial.new()
	road.shader = load("res://shaders/road.gdshader")
	road.set_shader_parameter("albedo_tex", WorldBuilder.tex("asphalt_track", "diff"))
	road.set_shader_parameter("normal_tex", WorldBuilder.tex("asphalt_track", "nor"))
	road.set_shader_parameter("rough_tex", WorldBuilder.tex("asphalt_track", "rough"))
	road.set_shader_parameter("noise_tex", noise_tex)
	road.set_shader_parameter("road_width", TrackDefs.ROAD_WIDTH)
	road.set_shader_parameter("wetness", weather.preset.wet)
	road.set_shader_parameter("snow", weather.preset.snow)

	# Shared PBR library: ground grime from the carved terrain, weather on all of it.
	Mats.bind_world(terrain, weather.preset)
	var curb := StandardMaterial3D.new()
	curb.vertex_color_use_as_albedo = true
	curb.vertex_color_is_srgb = true
	curb.roughness = 0.55
	curb.cull_mode = BaseMaterial3D.CULL_DISABLED

	var gravel := StandardMaterial3D.new()
	gravel.albedo_texture = WorldBuilder.tex("gravel_floor", "diff")
	gravel.normal_enabled = true
	gravel.normal_texture = WorldBuilder.tex("gravel_floor", "nor")
	gravel.roughness_texture = WorldBuilder.tex("gravel_floor", "rough")
	gravel.uv1_triplanar = true
	gravel.uv1_world_triplanar = true
	gravel.uv1_scale = Vector3(0.35, 0.35, 0.35)
	gravel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	gravel.cull_mode = BaseMaterial3D.CULL_DISABLED
	if weather.preset.snow > 0.0:
		gravel.albedo_color = Color(2.2, 2.25, 2.35) # snowed over (texture is dark, so over-brighten)
		gravel.roughness = 0.8
	elif weather.preset.wet > 0.0:
		gravel.albedo_color = Color(0.6, 0.6, 0.62)
		gravel.roughness = 0.45

	var rail := Mats.mat("steel") # galvanised, streaked
	var post := Mats.mat("steel", Color(0.72, 0.72, 0.72), false)
	return {road = road, curb = curb, gravel = gravel, rail = rail, post = post}
