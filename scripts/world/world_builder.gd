class_name WorldBuilder
extends RefCounted
## Everything around the track: photographic sky + matching sun, textured
## ground, distant hills, and forests of card-based photo trees (Vegetation).

const HDRI := "res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr"
## Where the sun sits in that HDRI (found by scanning for the brightest pixel).
const HDRI_SUN_U := 0.5947
const HDRI_SUN_ELEVATION := 48.0
const TEX := "res://assets/textures/%s/%s_%s_2k.jpg"


static func tex(id: String, kind: String) -> Texture2D:
	return load(TEX % [id, id, kind])


## Direction *towards* the sun, matching Godot's panorama mapping.
static func sun_direction() -> Vector3:
	var phi := TAU * HDRI_SUN_U
	var e := deg_to_rad(HDRI_SUN_ELEVATION)
	return Vector3(sin(phi) * cos(e), sin(e), -cos(phi) * cos(e)).normalized()


static func build_environment(parent: Node3D) -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load(HDRI)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_512

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = false # ~12 fps on an M1; candidate for a "High" preset
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.03
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.82)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	# Mild, natural grade: nothing candy-coloured.
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.basis = Basis.looking_at(-sun_direction(), Vector3.UP)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)


static func terrain_material(noise: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain.gdshader")
	m.set_shader_parameter("a_albedo", tex("grass_ground", "diff"))
	m.set_shader_parameter("a_normal", tex("grass_ground", "nor"))
	m.set_shader_parameter("b_albedo", tex("sparse_grass", "diff"))
	m.set_shader_parameter("b_normal", tex("sparse_grass", "nor"))
	m.set_shader_parameter("noise_tex", noise)
	return m


static func build_ground(parent: Node3D, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.set_meta("grip", 0.55)
	body.set_meta("drag", 0.06)
	body.position.y = -120.0 # far backdrop only; the terrain heightmap is the real ground
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	cs.position.y = 0.0 # safety net only (body is already far below)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	mi.mesh = plane
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)


## A ring of rolling hills and distant mountains so the horizon isn't a flat line.
static func build_hills(parent: Node3D, centre: Vector3, inner: float, mat: Material) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.frequency = 0.0012
	noise.fractal_octaves = 5
	var outer := inner * 4.5
	var seg := 160
	var rings := 48
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[PackedVector3Array] = []
	for r in rings + 1:
		var t := float(r) / rings
		var radius := lerpf(inner, outer, t * t)
		var row := PackedVector3Array()
		for s in seg + 1:
			var a := TAU * s / seg
			var p := centre + Vector3(cos(a), 0, sin(a)) * radius
			# Rises soon behind the terrain's own ridges: close, layered horizons.
			var rise := smoothstep(inner * 0.95, inner * 1.35, radius)
			var n := noise.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			var mountains := smoothstep(inner * 1.8, outer, radius) * 460.0
			p.y = rise * (40.0 + n * 170.0 + n * n * mountains) - 1.0
			row.append(p)
		grid.append(row)
	for r in rings:
		for s in seg:
			var a := grid[r][s]
			var b := grid[r][s + 1]
			var c := grid[r + 1][s + 1]
			var d := grid[r + 1][s]
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Hills"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------------------------------------------------------------- trees

## Wind-swaying material for vertex-coloured plants (theme trees, vines). The
## forest reads its wind strength and noise texture from it too.
static func foliage_material(noise: Texture2D, wind: float, height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("wind_strength", wind)
	m.set_shader_parameter("gust_speed", 0.05 + wind * 0.08)
	m.set_shader_parameter("height_scale", height)
	return m


## Species mix per track: [spruce, pine, beech, oak, birch] weights.
const FOREST_MIX := {
	"kiefernring": [0.25, 0.55, 0.06, 0.04, 0.1],
	"schneekopf": [0.8, 0.12, 0.0, 0.0, 0.08],
	"brackenmoor": [0.35, 0.1, 0.2, 0.2, 0.15],
	"coast": [0.05, 0.6, 0.1, 0.25, 0.0],
	"autodromo": [0.1, 0.45, 0.15, 0.3, 0.0],
	"town": [0.35, 0.15, 0.25, 0.15, 0.1],
	"autumn": [0.32, 0.12, 0.25, 0.17, 0.14], # broadleaf stands for the colour (autumn foliage in veg_tree)
	"alpine": [0.72, 0.16, 0.0, 0.0, 0.12], # spruce forest, a few pines and birches (Alpenpass)
	"mediterranean": [0.0, 0.85, 0.0, 0.15, 0.0], # Aleppo pines and holm oaks (theme adds stone pines, olives, maquis)
}
## Forest LOD cell (m): near MultiMeshes and far merged meshes per cell, far
## meshes merged again per 3x3 cells further out (see build_forest).
const FOREST_CELL := 100.0
const WALL_GRID := 10.0 ## GxCorridor.GRID
## Deep-forest trees dropped per corridor wall tree (the wall hides most of them).
const WALL_TRADE := 2.5
const DEFAULT_MIX := [0.55, 0.15, 0.13, 0.07, 0.1]
## Age classes per species: variant heights in metres (instances are scaled a
## further 0.85..1.15) and how common each is. Forest edges get the younger
## trees, the interior of dense stands the old ones.
const TREE_AGES := [
	[[4.5, 8.0, 13.5, 19.0, 24.5], [0.13, 0.17, 0.25, 0.27, 0.18]], # spruce
	[[5.0, 9.0, 14.5, 19.5, 24.0], [0.12, 0.16, 0.24, 0.28, 0.2]], # pine
	[[5.5, 10.5, 16.0, 22.0], [0.14, 0.22, 0.34, 0.3]], # beech
	[[5.0, 10.0, 15.0, 20.0], [0.14, 0.22, 0.34, 0.3]], # oak
	[[6.0, 11.5, 17.0], [0.25, 0.4, 0.35]], # birch
]


## Scatters `count` trees (spruce, pine, beech, oak, birch; mix per track) in
## patches over `area`, `keep_clear` metres off `avoid`. `exclusions`:
## [[centre, radius], ...] kept free of trees (buildings, grandstands).
static func build_forest(parent: Node3D, avoid: Curve3D, keep_clear: float, area: Rect2, count: int, exclusions: Array = [], terrain: Terrain = null, snow := 0.0, wind_mat: Material = null) -> void:
	if OS.has_environment("VEG_OFF") or OS.has_environment("FOREST_OFF"): # perf A/B: VEG_OFF=1 skips forest + grass
		return
	var t0 := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var density := FastNoiseLite.new()
	density.seed = 7
	density.frequency = 0.006
	var stands := FastNoiseLite.new() # where the broadleaf stands are
	stands.seed = 31
	stands.frequency = 0.004
	var wind := 0.3
	var noise: Texture2D = null
	if wind_mat is ShaderMaterial:
		wind = float((wind_mat as ShaderMaterial).get_shader_parameter("wind_strength"))
		noise = (wind_mat as ShaderMaterial).get_shader_parameter("noise_tex")
	var wet := 0.0
	var w = parent.get("weather")
	if w is Weather:
		wet = float((w as Weather).preset.get("wet", 0.0))
	var def = parent.get("def")
	var mix: Array = DEFAULT_MIX
	if def is Dictionary:
		mix = FOREST_MIX.get(def.get("id", ""), FOREST_MIX.get(def.get("theme", ""), DEFAULT_MIX))
	var mats: Array[ShaderMaterial] = [
		Vegetation.conifer_material(noise, wind, snow, wet),
		Vegetation.broadleaf_material(noise, wind * 1.15, snow * 0.7, wet),
	]
	mats[1].set_meta("wind_mul", 1.15)
	if def is Dictionary and def.get("theme", "") == "autumn":
		mats[1].set_shader_parameter("autumn", 1.0)
	mats[1].set_meta("snow_mul", 0.7)
	# Variants: [near mesh, far mesh, material index, height]; by_species[sp] =
	# variant index per age class.
	var variants: Array = []
	var by_species: Array = [[], [], [], [], []]
	for sp in 5:
		if mix[sp] <= 0.0 and sp != Vegetation.Species.SPRUCE:
			continue
		var ages: Array = TREE_AGES[sp][0]
		for ai in ages.size():
			var h: float = ages[ai]
			var hh := h * rng.randf_range(0.93, 1.07)
			# Baked Sapling models (tools/trees); autumn swaps beech for maple.
			var lods: Array = Vegetation.forest_model(sp, ai, def.get("theme", "") == "autumn" if def is Dictionary else false)
			if not lods.is_empty():
				hh = h
			else:
				match sp:
					Vegetation.Species.SPRUCE:
						lods = Vegetation.spruce(rng, hh)
					Vegetation.Species.PINE:
						lods = Vegetation.pine(rng, hh)
					_:
						lods = Vegetation.broadleaf(rng, hh, sp)
			by_species[sp].append(variants.size())
			variants.append([lods[0], lods[1], 0 if sp <= Vegetation.Species.PINE else 1, hh])
	var conifer_w: float = mix[0] + mix[1]
	var broad_w: float = mix[2] + mix[3] + mix[4]

	# Undergrowth: dense leaf-mass bushes ride the same LOD chain as the trees
	# (near MultiMesh -> merged far meshes out to the horizon). Baked models only.
	if not Vegetation.model("beech_0").is_empty():
		for k in 3:
			var bm := Vegetation.bush_dense(rng, 1.0, k)
			by_species.append([variants.size()]) # by_species[5..7] = bush kinds
			variants.append([bm, bm, 1, 1.4])
	# Trees grouped into FOREST_CELL cells (see the LOD chain below).
	var cells := {}
	var colliders := StaticBody3D.new()
	colliders.name = "TreeTrunks" # added once filled: far cheaper than growing a live body
	var trunk_shapes: Array[CylinderShape3D] = []
	for rad in [0.18, 0.3, 0.45]:
		var cyl := CylinderShape3D.new()
		cyl.radius = rad
		cyl.height = 4.0
		trunk_shapes.append(cyl)
	var near_track := Vegetation.near_curve_grid(avoid, keep_clear, 20.0)
	var zones := Vegetation.zone_grid(exclusions, 20.0)
	var placed := 0
	var tries := 0
	var belt_on := false
	var belt_len := avoid.get_baked_length()
	if def is Dictionary:
		var wall := [0] # corridor tree-wall trees placed (gx_corridor.gd): taken off the deep forest below
		belt_on = _edge_belt(def, avoid, keep_clear, terrain, zones, mix, by_species, variants, cells, colliders, trunk_shapes, rng,
			parent.get_meta("corridor_trees", {}), wall)
		count = maxi(count - int(wall[0] * WALL_TRADE), count / 3)
	while placed < count and tries < count * 20:
		tries += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
		# A third of the trees go into the band you actually see from the road (out to
		# ~170 m behind the edge), where the stands are also allowed to be thicker:
		# the forest closes in around the track instead of thinning across the map.
		var band := belt_on and rng.randf() < 0.3
		if band:
			var bo := rng.randf() * belt_len
			var bc := avoid.sample_baked(bo)
			var bt := (avoid.sample_baked(fmod(bo + 2.0, belt_len)) - bc).normalized()
			var lat := keep_clear + pow(rng.randf(), 1.5) * 150.0
			p = bc + bt.cross(Vector3.UP).normalized() * lat * (1.0 if rng.randf() < 0.5 else -1.0)
			p.y = 0.0
			if not area.has_point(Vector2(p.x, p.z)):
				continue
		# Forest patches with sparse trees in between.
		var d := density.get_noise_2d(p.x, p.z) * 0.5 + 0.5
		if rng.randf() > smoothstep(0.35, 0.65, d) * 0.95 + (0.15 if band else 0.03):
			continue
		if near_track.has(Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))):
			var near := avoid.get_closest_point(p)
			if Vector2(p.x - near.x, p.z - near.z).length() < keep_clear:
				continue
		if terrain:
			p.y = terrain.surface_at(p.x, p.z) - 0.2
		if Vegetation.in_zone(zones, p, 20.0):
			continue
		# Pick a species: broadleaf trees cluster in stands, mostly along forest edges.
		var st_n := stands.get_noise_2d(p.x, p.z) * 0.5 + 0.5
		var bw := broad_w * (0.3 + 1.8 * smoothstep(0.45, 0.7, st_n)) * (1.4 - d * 0.6)
		var sp := 0
		if rng.randf() * (conifer_w + bw) < bw:
			var x := rng.randf() * broad_w
			sp = 2 if x < mix[2] else (3 if x < mix[2] + mix[3] else 4)
		else:
			sp = 0 if rng.randf() * conifer_w < mix[0] else 1
		if by_species[sp].is_empty():
			sp = 0
		# Age class: young trees at the edges and in clearings, old in the interior.
		var weights: Array = TREE_AGES[sp][1]
		var edge := clampf((d - 0.5) * 3.0, -1.0, 1.0) # -1 sparse edge .. 1 dense interior
		var tot := 0.0
		var ws: Array[float] = []
		for i in weights.size():
			var bias := lerpf(-1.0, 1.0, float(i) / (weights.size() - 1))
			ws.append(float(weights[i]) * maxf(0.15, 1.0 + edge * bias * 0.7))
			tot += ws[i]
		var pick := rng.randf() * tot
		var age := 0
		while age < ws.size() - 1 and pick > ws[age]:
			pick -= ws[age]
			age += 1
		var vi: int = by_species[sp][age]
		var s := rng.randf_range(0.85, 1.15)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.93, 1.08), s)), p)
		var key := Vector2i(floori(p.x / FOREST_CELL), floori(p.z / FOREST_CELL))
		if not cells.has(key):
			cells[key] = []
			for v in variants.size():
				cells[key].append([])
		cells[key][vi].append(xf)
		if OS.has_environment("VEG_DEBUG") and placed % 40 == 0:
			var rp := avoid.get_closest_point(p)
			if Vector2(p.x - rp.x, p.z - rp.z).length() < keep_clear + 14.0:
				print("tree sp=%d age=%d at %s road %s" % [sp, age, p, rp])
		# Trunks you can hit; saplings are left to the cars.
		var th: float = variants[vi][3] * s
		if th > 6.5:
			var cs := CollisionShape3D.new()
			cs.shape = trunk_shapes[0 if th < 11.0 else (1 if th < 19.0 else 2)]
			cs.position = p + Vector3.UP * 2.0
			colliders.add_child(cs)
		placed += 1

	parent.add_child(colliders)
	# Full trees with shadows up close (one MultiMesh per variant and cell);
	# far away every tree of a cell is merged into one static mesh per
	# material (the far LOD grown from the same skeleton, same wind): two draw
	# calls per cell.
	var far_mats: Array[Material] = []
	for m in mats:
		var fm: ShaderMaterial = m.duplicate()
		fm.set_shader_parameter("merged", true)
		fm.set_shader_parameter("normal_depth", 0.0) # merged far meshes carry no tangents
		for key in ["wind_mul", "snow_mul"]:
			if m.has_meta(key):
				fm.set_meta(key, m.get_meta(key))
		Vegetation._materials.append(weakref(fm))
		far_mats.append(fm)
	var near_end: float = [160.0, 200.0, 300.0, 340.0][Game.quality] # full trees (wind, shadows) out to here
	var far_arrays: Array = variants.map(func(v: Array) -> Array: return (v[1] as ArrayMesh).surface_get_arrays(0))
	var far_flags := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var tris := [0, 0]
	# LOD chain (Godot HLOD, visibility_parent): a child is drawn only while its
	# parent is hidden because the camera is nearer than the parent's range
	# begin. near MultiMeshes (+ shadow proxies) -> far mesh of their 100 m cell
	# (begin near_end) -> far mesh of the 300 m super cell (begin near_end + 250,
	# more than any cell centre is from its super cell's). Each level swaps with
	# the next in the same frame: no gap, no double draw, no alpha crossfade
	# (a FADE_SELF fade is alpha blending); the nearest far-mesh tree is
	# >= near_end - 71 m, about the shadow distance.
	var supers := {} # super key -> [merged arrays per material, far cell meshes per material]
	for key in cells:
		var merged: Array = [null, null]
		var near_nodes: Array = [[], []]
		for v in variants.size():
			var xforms: Array = cells[key][v]
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = variants[v][0]
			mm.instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
			tris[0] += xforms.size() * (variants[v][0] as ArrayMesh).surface_get_array_len(0) / 3
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mats[variants[v][2]]
			mmi.name = "ForestNear"
			# Shadows come from the far LOD of the same trees (same skeleton,
			# a fifth of the cards): the four shadow splits are where the
			# forest's cost was.
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			var mi: int = variants[v][2]
			near_nodes[mi].append(mmi)
			if merged[mi] == null:
				merged[mi] = _empty_arrays()
			_append_instances(merged[mi], far_arrays[v], xforms)
		for mi in merged.size():
			if merged[mi] == null:
				continue
			tris[1] += (merged[mi][Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var far := MeshInstance3D.new()
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged[mi], [], {}, far_flags)
			far.mesh = am
			far.material_override = far_mats[mi]
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.name = "ForestFar"
			far.visibility_range_begin = near_end
			far.visibility_range_begin_margin = 8.0 # hysteresis (no fade)
			# Wind bends the trees a couple of metres: don't cull them early.
			far.extra_cull_margin = 4.0
			parent.add_child(far)
			# The near trees' shadows: the cell's merged far-LOD mesh (the same
			# geometry the per-variant shadow MultiMeshes drew, swaying with
			# far_mats), one draw call per shadow split instead of one per variant.
			var sh := MeshInstance3D.new()
			sh.name = "ForestShadow"
			sh.mesh = am
			sh.material_override = far_mats[mi]
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			sh.extra_cull_margin = 4.0
			parent.add_child(sh)
			near_nodes[mi].append(sh)
			for n: Node3D in near_nodes[mi]:
				n.visibility_parent = n.get_path_to(far)
			var skey := Vector2i(floori(key.x / 3.0), floori(key.y / 3.0))
			if not supers.has(skey):
				supers[skey] = [[null, null], [[], []]]
			var sup: Array = supers[skey]
			if sup[0][mi] == null:
				sup[0][mi] = _empty_arrays()
			var dst: Array = sup[0][mi]
			for a in Mesh.ARRAY_MAX:
				if dst[a] != null and merged[mi][a] != null:
					var arr = dst[a] # packed arrays are values: append to a local, store it back
					arr.append_array(merged[mi][a])
					dst[a] = arr
			sup[1][mi].append(far)
	for skey in supers:
		var sup: Array = supers[skey]
		for mi in 2:
			if sup[0][mi] == null:
				continue
			var far := MeshInstance3D.new()
			far.name = "ForestFarSuper"
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sup[0][mi], [], {}, far_flags)
			far.mesh = am
			far.material_override = far_mats[mi]
			far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			far.visibility_range_begin = near_end + 250.0
			far.visibility_range_begin_margin = 10.0
			far.visibility_range_end = 1100.0
			far.visibility_range_end_margin = 100.0
			far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # far out: a soft edge
			far.extra_cull_margin = 4.0
			parent.add_child(far)
			for n: Node3D in sup[1][mi]:
				n.visibility_parent = n.get_path_to(far)
	if OS.has_environment("VEG_DEBUG"):
		print("forest: %d trees, %d variants, near %d / far %d tris total, in %d ms" % [placed, variants.size(), tris[0], tris[1], Time.get_ticks_msec() - t0])
		for v: Array in variants:
			print("  h=%.1f near=%d far=%d tris" % [v[3], (v[0] as ArrayMesh).surface_get_array_len(0) / 3, (v[1] as ArrayMesh).surface_get_array_len(0) / 3])

## Forest edge: the main scatter keeps `keep_clear` (~30 m) off the road, which
## left a strip of open grass behind the guardrail. This fills it: a ragged belt
## of young and middle-aged trees from just behind the guardrail / run-off out to
## the forest, with leaf-mass bushes and saplings in front of them, so the forest
## wall starts right behind the barrier. Natural tracks only (no street/town/
## harbour/coast/alpine), never inside run-off, exclusion zones or another
## stretch of road.
static func _edge_belt(def: Dictionary, avoid: Curve3D, keep_clear: float, terrain: Terrain, zones: Dictionary, mix: Array,
		by_species: Array, variants: Array, cells: Dictionary, colliders: StaticBody3D, trunk_shapes: Array, rng: RandomNumberGenerator,
		wall: Dictionary = {}, wall_out: Array = [0]) -> bool:
	if OS.get_cmdline_user_args().has("--trees_old") or OS.has_environment("BELT_OFF") or by_species.size() < 8:
		return false
	var base: bool = not (def.get("street", false) or def.get("theme", "") in ["town", "harbour", "coast"])
	if not base and wall.is_empty():
		return false
	var gaps := FastNoiseLite.new() # clearings and thicker patches along the belt
	gaps.seed = 99
	gaps.frequency = 0.02
	var length := avoid.get_baked_length()
	var step := 2.0
	var n := int(length / step)
	var centers: Array[Vector3] = []
	for i in n:
		centers.append(avoid.sample_baked(i * length / n))
	var corner := TrackBuilder._corner_factors(centers)
	var half := TrackDefs.ROAD_WIDTH * 0.5
	var conifer_w: float = mix[0] + mix[1]
	var broad_w: float = mix[2] + mix[3] + mix[4]
	var med: bool = def.get("theme", "") == "mediterranean" # maquis: more scrub, fewer trees
	var n_trees := 0
	var n_bush := 0
	for i in n:
		var p0 := centers[i]
		var t := (centers[(i + 1) % n] - centers[(i - 1 + n) % n]).normalized()
		var right := t.cross(Vector3.UP).normalized()
		for side: float in [-1.0, 1.0]:
			var c := corner[i]
			var depth := TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0
			var rail := half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)
			var g := gaps.get_noise_2d(p0.x + side * 50.0, p0.z) * 0.5 + 0.5 # 0 clearing .. 1 thicket
			# [kind, lateral]: kind 0 tree, 1 bush
			var items: Array = []
			if base and rng.randf() < (0.14 if med else 0.24) * smoothstep(0.15, 0.5, g):
				items.append([0, rng.randf_range(rail + 5.5, keep_clear + 4.0)])
			if base and rng.randf() < (0.75 if med else 0.6) * smoothstep(0.05, 0.35, g):
				items.append([1, rail + 2.5 + pow(rng.randf(), 1.6) * 13.0])
			# Corridor tree wall (gx_corridor.gd): a close front row of middle-aged
			# trees, a taller row behind, undergrowth at their feet.
			var wb := 0.0
			if not wall.is_empty():
				var wp := p0 + right * side * (rail + 13.0)
				wb = float(wall.get(Vector2i(floori(wp.x / WALL_GRID), floori(wp.z / WALL_GRID)), 0.0)) * (0.7 + 0.3 * g)
			if wb > 0.0:
				if rng.randf() < 0.32 * wb:
					items.append([2, rng.randf_range(rail + 6.0, rail + 13.0)])
				if rng.randf() < 0.2 * wb:
					items.append([3, rng.randf_range(rail + 13.0, rail + 34.0)])
				if rng.randf() < 0.22 * wb:
					items.append([1, rng.randf_range(rail + 3.5, rail + 9.0)])
			for it: Array in items:
				var lat: float = it[1]
				var p := p0 + right * side * lat + t * rng.randf_range(-1.0, 1.0)
				var near := avoid.get_closest_point(p)
				if Vector2(p.x - near.x, p.z - near.z).length() < lat - 0.6:
					continue # another stretch of road is closer
				if Vegetation.in_zone(zones, p, 20.0):
					continue
				if terrain:
					p.y = terrain.surface_at(p.x, p.z) - 0.2
					# Nothing grows on rock cuttings (steeper than ~45 degrees).
					var gx := terrain.surface_at(p.x + 1.5, p.z) - terrain.surface_at(p.x - 1.5, p.z)
					var gz := terrain.surface_at(p.x, p.z + 1.5) - terrain.surface_at(p.x, p.z - 1.5)
					if gx * gx + gz * gz > 9.0:
						continue
				var vi: int
				var s := rng.randf_range(0.8, 1.2)
				if it[0] == 1:
					vi = by_species[5 + rng.randi() % 3][0]
					s = rng.randf_range(0.7, 1.5) * (1.0 + clampf((lat - rail) / 16.0, 0.0, 1.0) * 0.5)
					p.y += 0.1
					n_bush += 1
				else:
					var sp := 0
					if rng.randf() * (conifer_w + broad_w * 1.3) < broad_w * 1.3: # edges are where the broadleaf grow
						var x := rng.randf() * broad_w
						sp = 2 if x < mix[2] else (3 if x < mix[2] + mix[3] else 4)
					else:
						sp = 0 if rng.randf() * conifer_w < mix[0] else 1
					if (by_species[sp] as Array).is_empty():
						sp = 0
					var ages: Array = by_species[sp]
					# young at the barrier, middle-aged towards the forest
					var f := clampf((lat - rail) / maxf(keep_clear - rail, 1.0), 0.0, 1.0)
					var age := clampi(int(f * 1.6 + rng.randf() * 1.3), 0, mini(2, ages.size() - 1))
					if it[0] >= 2: # wall rows: tall enough to close the view
						age = clampi(int(it[0]) - 1 + rng.randi() % 2, 0, ages.size() - 1)
						wall_out[0] += 1
					vi = ages[age]
					n_trees += 1
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.1), s)), p)
				var key := Vector2i(floori(p.x / FOREST_CELL), floori(p.z / FOREST_CELL))
				if not cells.has(key):
					cells[key] = []
					for v in variants.size():
						cells[key].append([])
				cells[key][vi].append(xf)
				var th: float = variants[vi][3] * s
				if th > 6.5:
					var cs := CollisionShape3D.new()
					cs.shape = trunk_shapes[0 if th < 11.0 else 1]
					cs.position = p + Vector3.UP * 2.0
					colliders.add_child(cs)
	if OS.has_environment("VEG_DEBUG"):
		print("forest edge belt: %d trees, %d bushes" % [n_trees, n_bush])
	return true


static func _empty_arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	a[Mesh.ARRAY_COLOR] = PackedColorArray()
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	a[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	a[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array()
	return a


## Appends one copy of mesh arrays `src` per transform to `dst` (all native
## packed-array ops, so thousands of trees merge in milliseconds). CUSTOM0
## carries each tree's root and scale for the wind shader.
static func _append_instances(dst: Array, src: Array, xforms: Array) -> void:
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var n := verts.size()
	assert(src[Mesh.ARRAY_INDEX] == null, "far meshes are built unindexed")
	for xf: Transform3D in xforms:
		dst[Mesh.ARRAY_VERTEX].append_array(xf * verts)
		dst[Mesh.ARRAY_NORMAL].append_array(Transform3D(xf.basis.orthonormalized(), Vector3.ZERO) * norms)
		dst[Mesh.ARRAY_COLOR].append_array(src[Mesh.ARRAY_COLOR])
		dst[Mesh.ARRAY_TEX_UV].append_array(src[Mesh.ARRAY_TEX_UV])
		dst[Mesh.ARRAY_TEX_UV2].append_array(src[Mesh.ARRAY_TEX_UV2])
		var c := PackedFloat32Array([xf.origin.x, xf.origin.y, xf.origin.z, xf.basis.y.length()])
		while c.size() < n * 4:
			c.append_array(c)
		c.resize(n * 4)
		dst[Mesh.ARRAY_CUSTOM0].append_array(c)
