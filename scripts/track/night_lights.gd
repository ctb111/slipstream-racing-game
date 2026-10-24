class_name NightLights
extends RefCounted
## Trackside lighting for night races (only built when the weather preset has
## `night`): floodlight masts on the circuits (mostly at corners, so the
## straights between stay dark and the headlights matter), wrought-iron
## lanterns along the streets of the town, sodium road lamps on the coast, and
## a lit start area (gantry, pit lane, garages, grandstand roof).
##
## Cost: every lamp is one shadowless SpotLight that fades out and is culled
## beyond a short distance, so only the dozen or so around the camera are in
## the clustered light list. Poles, glowing heads and the halos around them are
## three MultiMeshes per lamp type (a handful of draw calls for the whole lap).

const STEP := 2.0

## Per lamp type: pole height, colour, light range / angle / energy, fade
## distance, spacing on straights / in corners (m), halo size.
const TYPES := {
	mast = {height = 13.5, color = Color(1.0, 0.9, 0.74), range = 55.0, angle = 55.0, energy = 16.0,
		fade = 140.0, straight = 150.0, corner = 62.0, halo = 3.4, head_energy = 4.0},
	lantern = {height = 4.3, color = Color(1.0, 0.7, 0.4), range = 20.0, angle = 76.0, energy = 7.0,
		fade = 75.0, straight = 24.0, corner = 22.0, halo = 1.5, head_energy = 3.0},
	cobra = {height = 8.5, color = Color(1.0, 0.55, 0.2), range = 30.0, angle = 70.0, energy = 12.0,
		fade = 110.0, straight = 46.0, corner = 40.0, halo = 2.4, head_energy = 3.5},
}

var parent: Node3D
var terrain: Terrain
var preset: Dictionary
var def: Dictionary
var half := 6.0
var centers: Array[Vector3] = []
var tangents: Array[Vector3] = []
var rights: Array[Vector3] = []
var corner: Array[float] = []
var n := 0
var no_trees: Array = []
var _grid := {}
var _root: Node3D
var _poles := {} ## type -> Array[Transform3D]
var _heads := {}
var _halos := {}
var lamps := 0


static func build(p_parent: Node3D, curve: Curve3D, road_width: float, p_preset: Dictionary) -> void:
	if float(p_preset.get("night", 0.0)) <= 0.0:
		return
	var s := NightLights.new()
	s.parent = p_parent
	s.terrain = p_parent.get_meta("terrain", null)
	s.preset = p_preset
	s.half = road_width * 0.5
	var d: Variant = p_parent.get("def")
	s.def = d if d is Dictionary else {}
	s.no_trees = p_parent.get_meta("no_trees", [])
	s._run(curve)


func _run(curve: Curve3D) -> void:
	var t0 := Time.get_ticks_msec()
	_sample(curve)
	_root = Node3D.new()
	_root.name = "NightLights"
	parent.add_child(_root)
	var theme: String = def.get("theme", "")
	match theme:
		"town":
			_line_lamps("lantern", 0.8, 0.0) # both sides, alternating, just behind the rail
		"coast":
			_line_lamps("cobra", 1.2, _sea_side())
		"harbour": # city street lamps every ~24 m, alternating sides, light pools on the tarmac
			_city_lamps()
		"mediterranean": # lanterns in the village street, sodium lamps on the sea side elsewhere
			var vill := _village_mask()
			_line_lamps("lantern", 0.8, 0.0, vill)
			var rest := PackedByteArray()
			rest.resize(n)
			for k in n:
				rest[k] = 1 - vill[k]
			_line_lamps("cobra", 1.2, _sea_side(), rest)
		_:
			_line_lamps("mast", 2.6, 0.0)
	if theme != "town":
		_start_area()
	_flush()
	parent.set_meta("no_trees", no_trees)
	if OS.get_cmdline_user_args().has("--debug-dressing"):
		print("night lights: %d lamps in %d ms" % [lamps, Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- track sampling

func _sample(curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var t := (curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))).normalized()
		centers.append(p)
		tangents.append(t)
		rights.append(t.cross(Vector3.UP).normalized())
		var key := Vector2i(floori(p.x / 30.0), floori(p.z / 30.0))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)
	corner = TrackBuilder._corner_factors(centers)


func _i(k: int) -> int:
	return posmod(k, n)


func rail_dist(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	var depth := TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0
	return half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)


func _gy(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


## Behind the rails of every nearby stretch of track (not in a trap or on a road).
func _road_clear(p: Vector3, margin: float) -> bool:
	var cx := floori(p.x / 30.0)
	var cz := floori(p.z / 30.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for k: int in _grid.get(Vector2i(cx + dx, cz + dz), []):
				var d := Vector3(p.x - centers[k].x, 0.0, p.z - centers[k].z)
				if d.length() < rail_dist(k, signf(d.dot(rights[k]))) + margin:
					return false
	return true


## Clear of props registered by the other builders (the town-wide zone aside).
func _props_clear(p: Vector3, r: float, ignore_over := INF) -> bool:
	for z in no_trees:
		if float(z[1]) > ignore_over:
			continue
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(z[1]) + r:
			return false
	return true


## Coast: +1 / -1 = the side of the road away from the sea (0 = no preference).
func _sea_side() -> float:
	var sea: Vector2 = (def.get("sea", Vector2(-1, 0)) as Vector2).normalized()
	var k := n / 4
	return -signf(Vector2(rights[k].x, rights[k].z).dot(sea))


# ---------------------------------------------------------------- placement

## Lamps along the whole lap, `back` metres behind the rail; closer together
## in corners (masts on the outside), alternating sides on straights.
## `only_side` != 0 keeps them all on one side (the coast road's landward side).
## Samples between the def's `village` [from, to] anchors (nearest points), as 1s.
func _village_mask() -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(n)
	var ends: Array = def.get("village", [])
	if ends.size() < 2:
		return m
	var idx: Array[int] = []
	for e: Vector3 in ends:
		var best := INF
		var bi := 0
		for i in n:
			var d := Vector2(centers[i].x - e.x, centers[i].z - e.z).length_squared()
			if d < best:
				best = d
				bi = i
		idx.append(bi)
	var i := idx[0]
	while i != idx[1]:
		m[i] = 1
		i = (i + 1) % n
	return m


func _line_lamps(type: String, back: float, only_side: float, mask := PackedByteArray()) -> void:
	var cfg: Dictionary = TYPES[type]
	var since := 1e9
	var alt := 1.0
	var town := type == "lantern"
	var i := 0
	while i < n:
		var c: float = corner[i]
		var spacing: float = lerpf(cfg.straight, cfg.corner, clampf(absf(c) * 1.6, 0.0, 1.0))
		if type == "mast" and absf(c) < 0.12 and not _near_start(i, 70):
			spacing = cfg.straight * 1.6 # long straights stay dark between pools
		since += STEP
		if not mask.is_empty() and mask[i] == 0:
			i += 1
			continue
		if since >= spacing:
			var side := alt
			if only_side != 0.0:
				side = only_side
			elif type == "mast" and absf(c) > 0.15:
				side = signf(c) # the outside of the corner
			var lat := rail_dist(i, side) + back
			var p := centers[i] + rights[i] * side * lat
			p.y = _gy(p)
			var ok := _road_clear(p, back * 0.5) and _props_clear(p, 1.5, 100.0 if town else 30.0)
			if town:
				ok = _road_clear(p, 0.3) # house fronts start 1.5 m behind the rail
			if ok:
				_lamp(type, p, centers[i] + rights[i] * side * minf(lat * 0.35, half * 0.6))
				since = 0.0
				alt = -alt
		i += 1


func _near_start(i: int, samples: int) -> bool:
	return i < samples or i > n - samples


## A pole at `base`, its head over / facing `target` on the road.
## Street circuit in a city (Hafenstadt): sodium lamps on the pavement every
## ~34 m, sides alternating, each with a soft additive light pool decal on the
## road (cheap: one MultiMesh) on top of its real (distance-culled) spot light.
var _pools: Array = []
func _city_lamps() -> void:
	var since := 1e9
	var alt := 1.0
	for i in n:
		since += STEP
		if since < 34.0:
			continue
		var lat := rail_dist(i, alt) + 1.0
		var p := centers[i] + rights[i] * alt * lat
		p.y = _gy(p)
		if not (_road_clear(p, 0.5) and _props_clear(p, 1.5, 30.0)):
			continue
		_lamp("cobra", p, centers[i] + rights[i] * alt * minf(lat * 0.35, half * 0.6))
		var pc := centers[i] + rights[i] * alt * (half * 0.4) + Vector3.UP * 0.05
		_pools.append(Transform3D(Basis.looking_at(tangents[i], Vector3.UP), pc)) # long axis along the road
		since = 0.0
		alt = -alt


func _lamp(type: String, base: Vector3, target: Vector3) -> void:
	var cfg: Dictionary = TYPES[type]
	var h: float = cfg.height
	var face := Vector3(target.x - base.x, 0.0, target.z - base.z).normalized()
	var basis := Basis.looking_at(face, Vector3.UP) # -Z towards the road
	var reach := {mast = 0.5, lantern = 0.55, cobra = 1.9}[type] as float
	var head := base + Vector3.UP * h + face * reach
	_add(_poles, type, Transform3D(basis, base))
	_add(_heads, type, Transform3D(basis, base))
	_add(_halos, type, Transform3D(Basis(), head - Vector3.UP * 0.15))
	var aim := target
	if type != "mast":
		aim = head + face * (h * 0.35) + Vector3.DOWN * h # mostly straight down, a little towards the road
	_light(head - Vector3.UP * 0.2, aim, cfg)
	no_trees.append([base, 2.5])
	lamps += 1


func _light(pos: Vector3, aim: Vector3, cfg: Dictionary) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	var dir := (aim - pos).normalized()
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	l.basis = Basis.looking_at(dir, up)
	l.light_color = cfg.color
	l.light_energy = cfg.energy
	l.spot_range = cfg.range
	l.spot_angle = cfg.angle
	l.spot_attenuation = 1.1
	l.spot_angle_attenuation = 1.6
	l.light_specular = 0.8
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = float(cfg.fade)
	l.distance_fade_length = 35.0
	_root.add_child(l)
	return l


## Start/finish: floodlit grid under the gantry, pit lane lights along the
## garages, lamps under the grandstand roof (same layout maths as TrackProps).
func _start_area() -> void:
	var back := _straight_extent(0, -1, 75)
	var fwd := _straight_extent(0, 1, 40)
	var warm := Color(1.0, 0.9, 0.74)
	# Gantry: two lamps on the beam light the front rows.
	var d := maxf(rail_dist(0, 1.0), rail_dist(0, -1.0)) + 0.8
	for side: float in [-1.0, 1.0]:
		var p := centers[0] + rights[0] * side * (d - 1.2) + Vector3.UP * 6.4
		var l := _light(p, centers[_i(-8)] + rights[0] * side * 2.0, {color = warm, energy = 6.0, range = 34.0, angle = 50.0, fade = 220.0})
		l.spot_angle_attenuation = 1.0
		_add(_heads, "strip", Transform3D(Basis.looking_at(tangents[0], Vector3.UP).scaled(Vector3(2.6, 0.12, 0.3)), p + Vector3.UP * 0.1))
	if back + fwd < 20:
		return
	var i0 := -back + 2
	var i1 := fwd - 2
	var mid := (i0 + i1) / 2
	var length := (i1 - i0) * STEP
	var t := tangents[_i(mid)]
	var r := rights[_i(mid)]
	var along_basis := Basis.looking_at(t, Vector3.UP)
	# Pit garages: lamps above the doors shine down on the pit lane.
	var pd := rail_dist(mid, 1.0) + 14.0
	var depth := 12.0
	var count := clampi(int(length / 22.0), 2, 8)
	for k in count:
		var z := (k + 0.5) / count - 0.5
		var c := centers[_i(mid)] + r * (pd - depth * 0.5 - 0.4) + t * z * length
		c.y = _gy(c) + 6.6
		_light(c, c - r * 6.0 + Vector3.DOWN * 6.6, {color = Color(0.92, 0.95, 1.0), energy = 4.0, range = 16.0, angle = 70.0, fade = 200.0})
		_add(_heads, "strip", Transform3D(along_basis.scaled(Vector3(0.25, 0.1, length / count * 0.7)), c + r * 0.15 + Vector3.UP * 0.25))
	# Grandstand: strip lights under the roof edge and lamps lighting the terraces.
	var gd := rail_dist(mid, -1.0) + 5.0
	var glen := minf(length * 0.8, 110.0)
	var roof_y := 9 * 1.1 + 3.2
	for k in 3:
		var z := (k + 0.5) / 3.0 - 0.5
		var c := centers[_i(mid)] - r * (gd + 0.6) + t * z * glen
		c.y = _gy(c) + roof_y
		_light(c, c - r * 4.5 + Vector3.DOWN * 8.0, {color = warm, energy = 3.5, range = 20.0, angle = 70.0, fade = 220.0})
	var sc := centers[_i(mid)] - r * (gd - 0.2)
	sc.y = _gy(sc) + roof_y + 0.05
	_add(_heads, "strip", Transform3D(along_basis.scaled(Vector3(0.18, 0.08, glen * 0.96)), sc))


func _straight_extent(i: int, dir: int, max_samples: int) -> int:
	var k := 0
	while k < max_samples and absf(corner[_i(i + k * dir)]) < 0.1:
		k += 1
	return k


func _add(dict: Dictionary, type: String, xf: Transform3D) -> void:
	if not dict.has(type):
		dict[type] = []
	dict[type].append(xf)


# ---------------------------------------------------------------- meshes

func _flush() -> void:
	var pole_mat := Mats.mat("painted_metal", Color(0.2, 0.21, 0.22))
	for type: String in _poles:
		_multimesh(_pole_mesh(type), _poles[type], pole_mat, 900.0, true)
	for type: String in _heads:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/set_lamp.gdshader")
		var cfg: Dictionary = TYPES.get(type, {color = Color(1.0, 0.95, 0.85), head_energy = 5.0})
		mat.set_shader_parameter("energy", cfg.head_energy)
		_multimesh(_head_mesh(type, cfg.color), _heads[type], mat, 1400.0, false)
	var haze := 1.0 + float(preset.get("wet", 0.0)) * 1.2 + float(preset.get("snow", 0.0)) * 1.5
	for type: String in _halos:
		var cfg: Dictionary = TYPES[type]
		var hm := ShaderMaterial.new()
		hm.shader = load("res://shaders/lamp_halo.gdshader")
		hm.set_shader_parameter("color", Vector3(cfg.color.r, cfg.color.g, cfg.color.b))
		hm.set_shader_parameter("strength", 0.55 * haze)
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(cfg.halo) * (1.0 + (haze - 1.0) * 0.4)
		_multimesh(q, _halos[type], hm, 1400.0, false)


	if not _pools.is_empty():
		var pm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;\nuniform vec3 color = vec3(1.0, 0.6, 0.28);\nuniform float strength = 0.3;\nvoid fragment() {\n\tfloat d = length(UV - 0.5) * 2.0;\n\tALBEDO = color * strength * pow(max(1.0 - d, 0.0), 1.7);\n}\n"
		pm.shader = sh
		pm.set_shader_parameter("strength", 0.3 * (1.0 + float(preset.get("wet", 0.0)) * 0.6))
		var plane := PlaneMesh.new()
		plane.size = Vector2(15.0, 38.0) # overlapping pools along the road: no black gaps on the racing line
		_multimesh(plane, _pools, pm, 350.0, false)


func _multimesh(mesh: Mesh, xfs: Array, mat: Material, vis: float, shadow: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis
	_root.add_child(mmi)


func _pole_mesh(type: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = TYPES[type].height
	match type:
		"mast": # lattice-free steel mast, cross bar with three lamp housings
			_cyl(st, Vector3(0, 0, 0), 0.2, 0.13, h, 8)
			_boxv(st, Vector3(0, h, -0.25), Vector3(2.8, 0.14, 0.14))
			for k in 3:
				_boxv(st, Vector3(-1.0 + k * 1.0, h + 0.1, -0.5), Vector3(0.62, 0.5, 0.32), Basis(Vector3.RIGHT, -0.5))
		"lantern": # iron post, a short bracket and a four-sided lantern
			_cyl(st, Vector3(0, 0, 0), 0.11, 0.05, h - 0.2, 8)
			_cyl(st, Vector3(0, 0, 0), 0.16, 0.14, 0.6, 8)
			_boxv(st, Vector3(0, h - 0.25, -0.28), Vector3(0.05, 0.05, 0.6))
			_boxv(st, Vector3(0, h + 0.28, -0.55), Vector3(0.42, 0.06, 0.42))
			_boxv(st, Vector3(0, h - 0.28, -0.55), Vector3(0.3, 0.06, 0.3))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_boxv(st, Vector3(sx * 0.16, h, -0.55 + sz * 0.16), Vector3(0.03, 0.56, 0.03))
		"cobra": # tapered pole with an arm out over the verge
			_cyl(st, Vector3(0, 0, 0), 0.14, 0.08, h, 8)
			_boxv(st, Vector3(0, h + 0.05, -0.95), Vector3(0.08, 0.08, 1.9))
			_boxv(st, Vector3(0, h + 0.02, -1.95), Vector3(0.36, 0.14, 0.75))
	st.generate_normals()
	return st.commit()


## Glowing parts only (unshaded, bloom gives the glare).
func _head_mesh(type: String, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = TYPES.get(type, {height = 0.0}).height
	match type:
		"mast":
			for k in 3:
				var b := Basis(Vector3.RIGHT, -0.5)
				_boxv(st, Vector3(-1.0 + k * 1.0, h + 0.1, -0.5) + b * Vector3(0, 0, -0.17), Vector3(0.52, 0.4, 0.02), b)
		"lantern":
			_boxv(st, Vector3(0, h, -0.55), Vector3(0.29, 0.5, 0.29))
		"cobra":
			_boxv(st, Vector3(0, h - 0.07, -1.95), Vector3(0.3, 0.02, 0.62))
		_: # strip: unit box scaled by the instance transform
			_boxv(st, Vector3.ZERO, Vector3.ONE)
	# set_lamp.gdshader: COLOR = light colour, UV = (0, 0) = steady (no blinking).
	var arr := st.commit_to_arrays()
	var count := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray()
	cols.resize(count)
	cols.fill(col)
	var uvs := PackedVector2Array()
	uvs.resize(count)
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _boxv(st: SurfaceTool, c: Vector3, size: Vector3, rot := Basis()) -> void:
	var b := BoxMesh.new()
	b.size = size
	st.append_from(b, 0, Transform3D(rot, c))


func _cyl(st: SurfaceTool, base: Vector3, r0: float, r1: float, h: float, segs: int) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	st.append_from(c, 0, Transform3D(Basis(), base + Vector3.UP * h * 0.5))
