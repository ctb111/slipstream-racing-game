class_name Scenery
extends RefCounted
## Life around the circuit: cheering spectator groups with tents and parked
## cars, villages with houses, barns and a church, a windmill on a hill, a
## lake, and a hot-air balloon. Everything sits on the terrain and keeps the
## forest out of its way (via the parent's "no_trees" list).

const STEP := 2.0

var parent: Node3D
var terrain: Terrain
var preset: Dictionary
var half := 6.0
var rng := RandomNumberGenerator.new()
var centers: Array[Vector3] = []
var rights: Array[Vector3] = []
var tangents: Array[Vector3] = []
var corner: Array[float] = []
var n := 0
var no_trees: Array = []
var tools := {}
var mats := {}


static func build(p_parent: Node3D, curve: Curve3D, road_width: float, weather_preset: Dictionary) -> void:
	var s := Scenery.new()
	s.parent = p_parent
	s.terrain = p_parent.get_meta("terrain", null)
	s.preset = weather_preset
	s.half = road_width * 0.5
	s.rng.seed = hash(curve.get_baked_length())
	s.no_trees = p_parent.get_meta("no_trees", [])
	s._run(curve)


func _run(curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var t := (curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))).normalized()
		centers.append(p)
		tangents.append(t)
		rights.append(t.cross(Vector3.UP).normalized())
	corner = TrackBuilder._corner_factors(centers)
	_materials()
	_spectators()
	_villages()
	_windmill()
	_lake()
	_balloon()
	for key in tools:
		var mi := MeshInstance3D.new()
		mi.name = "Scenery_" + key
		mi.mesh = tools[key].commit()
		mi.material_override = mats[key]
		parent.add_child(mi)
	parent.set_meta("no_trees", no_trees)


# ---------------------------------------------------------------- helpers

func _ground(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


func _track_dist(p: Vector3) -> float:
	var best := INF
	for k in range(0, n, 3):
		var c := centers[k]
		best = minf(best, Vector2(c.x - p.x, c.z - p.z).length())
	return best


func _clear(p: Vector3, r: float) -> bool:
	for z in no_trees:
		if p.distance_to(z[0]) < z[1] + r:
			return false
	return true


func _vc_mat(rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _materials() -> void:
	# Photographic PBR (Mats): textures tinted by the existing vertex colours.
	mats.building = Mats.mat("plaster")
	mats.roof = Mats.mat("roof_tiles")
	mats.glass = Mats.mat("glass")
	mats.photo = FacadeKit.unit_material(0.8 if float(preset.get("night", 0.0)) > 0.0 else 0.0) # photo windows / doors
	for key in mats:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st


## Append a primitive with a flat vertex colour to one of the merged meshes.
func _add(key: String, mesh: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
	var arr := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st: SurfaceTool = tools[key]
	for k in idx:
		st.set_color(col)
		st.set_normal((xf.basis * norms[k]).normalized())
		st.add_vertex(xf * verts[k])


func _box(key: String, c: Vector3, size: Vector3, basis: Basis, col: Color) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(key, b, Transform3D(basis, c), col)


## Gabled roof: a triangular prism along the local Z axis.
func _roof(c: Vector3, w: float, l: float, h: float, basis: Basis, col: Color) -> void:
	var p := PrismMesh.new()
	p.size = Vector3(w, h, l)
	_add("roof", p, Transform3D(basis, c), col)


# ---------------------------------------------------------------- spectators

func _spectators() -> void:
	var people_xf: Array[Transform3D] = []
	var people_col: Array[Color] = []
	var people_custom: Array[Color] = []
	var cars_xf: Array[Transform3D] = []
	var cars_col: Array[Color] = []
	var brollies: Array[Transform3D] = []
	var snow: bool = preset.snow > 0.0
	var storm: bool = preset.wet > 0.5
	var clothes := [Color(0.15, 0.22, 0.42), Color(0.62, 0.1, 0.08), Color(0.78, 0.62, 0.12), Color(0.12, 0.3, 0.16),
		Color(0.08, 0.08, 0.09), Color(0.45, 0.3, 0.16), Color(0.25, 0.4, 0.55), Color(0.7, 0.68, 0.62),
		Color(0.55, 0.2, 0.35), Color(0.8, 0.4, 0.1)]
	if snow:
		clothes = [Color(0.6, 0.1, 0.08), Color(0.1, 0.18, 0.4), Color(0.12, 0.12, 0.12), Color(0.8, 0.6, 0.1),
			Color(0.1, 0.35, 0.3), Color(0.5, 0.5, 0.52), Color(0.4, 0.05, 0.25)]
	var paint := [Color(0.5, 0.06, 0.05), Color(0.8, 0.78, 0.72), Color(0.1, 0.12, 0.2), Color(0.35, 0.36, 0.33),
		Color(0.12, 0.25, 0.14), Color(0.6, 0.45, 0.12), Color(0.08, 0.08, 0.08)]

	# One group per real corner, at the apex on the outside, behind the barrier.
	var groups := 0
	var in_corner := false
	var entry := 0
	for i in n:
		var c: float = absf(corner[i])
		if not in_corner and c > 0.4:
			in_corner = true
			entry = i
		elif in_corner and c < 0.3:
			in_corner = false
			var apex := (entry + i) / 2
			var outside := 1.0 if corner[apex] > 0.0 else -1.0
			var gravel := TrackBuilder.GRAVEL_MAX * absf(corner[apex])
			var rail := half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, gravel + 3.0)
			# Big crowd right behind the barrier on the outside...
			_spectator_group(apex, outside, rail + 1.6, rng.randi_range(60, 110), clothes, people_xf, people_col, people_custom, brollies, storm, 28.0)
			_car_park(apex, outside, rail + 16.0, paint, cars_xf, cars_col)
			# ...a smaller one on the inside, behind the kerbs and bales...
			_spectator_group(apex + 6, -outside, half + TrackBuilder.CURB_WIDTH + TrackBuilder.RAIL_GAP + 2.5, rng.randi_range(20, 40), clothes, people_xf, people_col, people_custom, brollies, storm, 18.0)
			# ...photographers crouched at the exit, and at some corners a TV tower.
			_photographers(i + 4, outside, rail + 0.8, people_xf, people_col, people_custom)
			if groups % 2 == 0:
				_camera_tower(apex - 10, outside, rail + 6.0, people_xf, people_col, people_custom)
			if groups % 3 == 1:
				_food_stall(apex, outside, rail + 11.0)
			groups += 1
	# Groups along the straights every ~150 m, alternating sides.
	var i := 40
	var side := 1.0
	while i < n - 20:
		if absf(corner[i]) < 0.15:
			_spectator_group(i, side, half + TrackBuilder.CURB_WIDTH + TrackBuilder.RAIL_GAP + 2.0, rng.randi_range(12, 30), clothes, people_xf, people_col, people_custom, brollies, storm, 16.0)
			side = -side
		i += 75
	_fences_and_poles()

	if OS.get_cmdline_user_args().has("--debug-scenery"):
		print("spectators: %d in %d corner groups, first at %s" % [people_xf.size(), groups, people_xf[0].origin if people_xf.size() > 0 else Vector3.ZERO])
	_crowd_multimesh(people_xf, people_col, people_custom)
	_parked_cars(cars_xf, cars_col)
	if not brollies.is_empty():
		_umbrellas(brollies)


func _spectator_group(i: int, side: float, back: float, count: int, clothes: Array,
		xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color], brollies: Array[Transform3D], storm: bool, spread := 26.0) -> void:
	i = posmod(i, n)
	if float(preset.get("night", 0.0)) > 0.0:
		count = int(count * 0.55) # night race: the die-hards stay out by the track
	var t := tangents[i]
	var r := rights[i]
	# Other systems (crowd sound) want to know where people are.
	var spots: Array = parent.get_meta("crowd_spots", [])
	var spot := centers[i] + r * side * (back + 3.0)
	spot.y = _ground(spot)
	spots.append([spot, count])
	parent.set_meta("crowd_spots", spots)
	var face := Basis.looking_at(-r * side, Vector3.UP) # looking at the track
	# Spectator tape on thin posts in front of them.
	var tape_from := centers[i] + r * side * (back - 0.8) - t * spread * 0.55
	var posts := int(spread * 1.1 / 4.0) + 1
	for k in posts:
		var post := tape_from + t * k * 4.0
		post.y = _ground(post)
		_box("building", post + Vector3.UP * 0.5, Vector3(0.05, 1.0, 0.05), face, Color(0.8, 0.8, 0.78))
		if k < posts - 1:
			var mid := post + t * 2.0 + Vector3.UP * 0.9
			mid.y = _ground(mid) + 0.9
			_box("building", mid, Vector3(4.0, 0.05, 0.01), Basis.looking_at(r, Vector3.UP), Color(0.8, 0.2, 0.08) if k % 2 == 0 else Color(0.9, 0.9, 0.88))
	for k in count:
		# Front rows pack along the tape, the rest fill in behind.
		var depth := rng.randf_range(0.0, 1.0)
		var p := centers[i] + r * side * (back + depth * depth * 8.0) + t * rng.randf_range(-spread * 0.5, spread * 0.5)
		p.y = _ground(p)
		var s := rng.randf_range(0.92, 1.08)
		var xf := Transform3D(face.rotated(Vector3.UP, rng.randf_range(-0.4, 0.4)).scaled(Vector3(s, s, s)), p)
		xfs.append(xf)
		cols.append(clothes[rng.randi() % clothes.size()])
		custom.append(Color(rng.randf(), rng.randf_range(0.3, 1.0) if rng.randf() < 0.75 else 0.0, 0, 0))
		if storm and rng.randf() < 0.35:
			brollies.append(Transform3D(Basis(), p + Vector3.UP * 2.05))
	# A marquee tent behind the crowd.
	var tent := centers[i] + r * side * (back + 11.0)
	tent.y = _ground(tent)
	var tb := Basis.looking_at(t, Vector3.UP)
	var stripe: Color = [Color(0.8, 0.78, 0.72), Color(0.2, 0.3, 0.5), Color(0.55, 0.1, 0.08)][rng.randi() % 3]
	for dx: float in [-2.4, 2.4]:
		for dz: float in [-2.4, 2.4]:
			_box("building", tent + tb * Vector3(dx, 1.2, dz), Vector3(0.08, 2.4, 0.08), tb, Color(0.6, 0.6, 0.6))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 3.6
	cone.height = 1.4
	cone.radial_segments = 4
	cone.rings = 1
	_add("roof", cone, Transform3D(tb.rotated(Vector3.UP, PI * 0.25), tent + Vector3.UP * 3.1), stripe)
	no_trees.append([centers[i] + r * side * (back + 8.0), 22.0])


func _crowd_multimesh(xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color]) -> void:
	if xfs.is_empty():
		return
	# Realistic baked figures (PeopleKit): pose from the excitement in custom.g,
	# near/far LOD swapped per 10 m chunk as the camera moves.
	parent.add_child(PeopleKit.crowd("Spectators", PeopleKit.Role.SPECTATOR, xfs, cols, custom))


## A standing spectator mesh (kept for callers that want a single figure mesh;
## the crowd itself is built by PeopleKit).
func _person_mesh() -> ArrayMesh:
	return PeopleKit.mesh("man_jacket", PeopleKit.Pose.STAND)


func _umbrellas(xfs: Array[Transform3D]) -> void:
	var dome := SphereMesh.new()
	dome.radius = 0.6
	dome.height = 0.45
	dome.is_hemisphere = true
	dome.radial_segments = 10
	dome.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = dome
	mm.instance_count = xfs.size()
	var cols := [Color(0.05, 0.05, 0.06), Color(0.15, 0.2, 0.4), Color(0.5, 0.08, 0.06), Color(0.2, 0.3, 0.2)]
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, cols[k % cols.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = Mats.mat("canvas") # umbrella fabric, instance colour
	parent.add_child(mmi)


## Photographers crouched low right behind the barrier with long lenses.
func _photographers(i: int, side: float, back: float, xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color]) -> void:
	i = posmod(i, n)
	var face := Basis.looking_at(-rights[i] * side - tangents[i] * 0.6, Vector3.UP)
	for k in rng.randi_range(2, 3):
		var p := centers[i] + rights[i] * side * (back + rng.randf_range(0.0, 1.0)) + tangents[i] * (k * 2.2)
		p.y = _ground(p) - 0.55 # crouching: the lower body sinks behind the rail
		xfs.append(Transform3D(face, p))
		cols.append([Color(0.2, 0.25, 0.2), Color(0.1, 0.1, 0.12), Color(0.45, 0.4, 0.3)][k % 3])
		custom.append(Color(rng.randf(), 0.0, 0, 0))
		var lens := CylinderMesh.new()
		lens.top_radius = 0.06
		lens.bottom_radius = 0.07
		lens.height = 0.45
		lens.radial_segments = 8
		lens.rings = 1
		_add("building", lens, Transform3D(face * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3.UP * 1.5 + face * Vector3(0, 0, -0.3)), Color(0.05, 0.05, 0.05))


## Scaffold camera tower with a cameraman on top.
func _camera_tower(i: int, side: float, back: float, xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color]) -> void:
	i = posmod(i, n)
	var base := centers[i] + rights[i] * side * back
	base.y = _ground(base)
	var basis := Basis.looking_at(-rights[i] * side, Vector3.UP)
	var h := 5.0
	var steel := Color(0.55, 0.56, 0.57)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_box("building", base + basis * Vector3(dx, h * 0.5, dz), Vector3(0.08, h, 0.08), basis, steel)
	for y in [1.5, 3.2]:
		for k in 4:
			var face := basis.rotated(Vector3.UP, k * PI * 0.5)
			_box("building", base + Vector3.UP * y + face * Vector3(0, 0, 1.0), Vector3(2.0, 0.05, 0.05), face, steel)
	_box("building", base + Vector3.UP * h, Vector3(2.4, 0.12, 2.4), basis, Color(0.35, 0.3, 0.22))
	for k in 4:
		var face := basis.rotated(Vector3.UP, k * PI * 0.5)
		_box("building", base + Vector3.UP * (h + 0.55) + face * Vector3(0, 0, 1.2), Vector3(2.4, 0.05, 0.05), face, steel)
	var man := base + Vector3.UP * (h + 0.06)
	xfs.append(Transform3D(basis, man))
	cols.append(Color(0.12, 0.14, 0.2))
	custom.append(Color(0.3, 0.0, 0, 0))
	_box("building", man + Vector3.UP * 1.45 + basis * Vector3(0.3, 0, -0.35), Vector3(0.3, 0.35, 0.6), basis, Color(0.08, 0.08, 0.09))
	_box("building", man + Vector3.UP * 1.0 + basis * Vector3(0.3, 0, -0.35), Vector3(0.06, 0.9, 0.06), basis, Color(0.1, 0.1, 0.1))
	no_trees.append([base, 6.0])


## Food / drinks stall with a striped awning and a hand-painted sign.
func _food_stall(i: int, side: float, back: float) -> void:
	i = posmod(i, n)
	var p := centers[i] + rights[i] * side * back + tangents[i] * 20.0
	p.y = _ground(p)
	var basis := Basis.looking_at(-rights[i] * side, Vector3.UP)
	_box("building", p + Vector3.UP * 1.1, Vector3(4.0, 2.2, 2.4), basis, Color(0.72, 0.68, 0.6))
	_box("building", p + Vector3.UP * 1.05 + basis * Vector3(0, 0, -1.25), Vector3(3.6, 0.1, 0.5), basis, Color(0.4, 0.28, 0.16)) # counter
	for k in 6:
		var stripe := Color(0.62, 0.1, 0.08) if k % 2 == 0 else Color(0.9, 0.88, 0.82)
		_box("roof", p + Vector3.UP * 2.45 + basis * Vector3(-1.66 + k * 0.66, 0, -1.6), Vector3(0.66, 0.06, 1.3), basis.rotated(basis.x, -0.25), stripe)
	_box("building", p + Vector3.UP * 2.75 + basis * Vector3(0, 0, -1.22), Vector3(3.0, 0.5, 0.06), basis, Color(0.15, 0.2, 0.15))
	no_trees.append([p, 6.0])


## Wooden post-and-rail farm fences and a line of telegraph poles with wires.
func _fences_and_poles() -> void:
	var wood := Color(0.36, 0.28, 0.2)
	var side := 1.0
	var i := 10
	while i < n - 60:
		if absf(corner[i]) < 0.2 and rng.randf() < 0.55:
			var dist := half + rng.randf_range(26.0, 40.0)
			for k in range(0, 40, 2):
				var a := centers[posmod(i + k, n)] + rights[posmod(i + k, n)] * side * dist
				var b := centers[posmod(i + k + 2, n)] + rights[posmod(i + k + 2, n)] * side * dist
				a.y = _ground(a)
				b.y = _ground(b)
				_box("building", a + Vector3.UP * 0.6, Vector3(0.14, 1.2, 0.14), Basis(), wood)
				var basis := Basis.looking_at((b - a).normalized(), Vector3.UP)
				for y: float in [0.45, 0.95]:
					_box("building", (a + b) * 0.5 + Vector3.UP * y, Vector3(0.06, 0.1, a.distance_to(b)), basis, wood)
		i += 60
		side = -side
	# Telegraph poles along one side of the lap, with sagging wires.
	var prev := Vector3.INF
	var pole_side := 1.0 if rng.randf() < 0.5 else -1.0
	for k in range(0, n, 18):
		var p := centers[k] + rights[k] * pole_side * (half + 46.0)
		p.y = _ground(p)
		if not _clear(p, 3.0):
			prev = Vector3.INF
			continue
		_box("building", p + Vector3.UP * 4.5, Vector3(0.22, 9.0, 0.22), Basis(), Color(0.3, 0.23, 0.17))
		_box("building", p + Vector3.UP * 8.4, Vector3(1.6, 0.12, 0.12), Basis.looking_at(tangents[k], Vector3.UP) * Basis(Vector3.UP, PI * 0.5), Color(0.3, 0.23, 0.17))
		if prev != Vector3.INF and prev.distance_to(p) < 60.0:
			for off: float in [-0.7, 0.7]:
				var dir := (p - prev).normalized()
				var lateral := dir.cross(Vector3.UP).normalized() * off
				var a := prev + Vector3.UP * 8.45 + lateral
				var b := p + Vector3.UP * 8.45 + lateral
				for s in 4: # sagging catenary in four pieces
					var t0 := s / 4.0
					var t1 := (s + 1) / 4.0
					var p0 := a.lerp(b, t0) + Vector3.DOWN * sin(t0 * PI) * 0.7
					var p1 := a.lerp(b, t1) + Vector3.DOWN * sin(t1 * PI) * 0.7
					_box("building", (p0 + p1) * 0.5, Vector3(0.025, 0.025, p0.distance_to(p1)), Basis.looking_at((p1 - p0).normalized(), Vector3.UP), Color(0.1, 0.1, 0.1))
		prev = p


# ---------------------------------------------------------------- parked cars

func _car_park(i: int, side: float, back: float, paint: Array, xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var t := tangents[i]
	var r := rights[i]
	for k in rng.randi_range(4, 8):
		var p := centers[i] + r * side * (back + (k % 2) * 6.0) + t * (k / 2 - 2) * 3.2
		p.y = _ground(p)
		var basis := Basis.looking_at(-r * side if k % 3 else r * side, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.15, 0.15))
		var camper := rng.randf() < 0.2
		xfs.append(Transform3D(basis.scaled(Vector3(1.15, 1.6, 1.3) if camper else Vector3.ONE), p))
		cols.append(Color(0.82, 0.8, 0.72) if camper else paint[rng.randi() % paint.size()])


## Period saloons / vans: one mesh, body coloured per instance, dark glass and tyres.
func _parked_cars(xfs: Array[Transform3D], cols: Array[Color]) -> void:
	if xfs.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(1.7, 0.62, 4.3), Vector3(0, 0.6, 0), Color.WHITE],
		[Vector3(1.5, 0.5, 2.2), Vector3(0, 1.15, 0.2), Color(0.08, 0.09, 0.1)],
		[Vector3(1.52, 0.06, 2.1), Vector3(0, 1.42, 0.2), Color.WHITE],
	]
	for p in parts:
		var b := BoxMesh.new()
		b.size = p[0]
		var arr := b.get_mesh_arrays()
		for k in arr[Mesh.ARRAY_INDEX]:
			st.set_color(p[2])
			st.set_normal(arr[Mesh.ARRAY_NORMAL][k])
			st.add_vertex(arr[Mesh.ARRAY_VERTEX][k] + p[1])
	var wheel := CylinderMesh.new()
	wheel.top_radius = 0.32
	wheel.bottom_radius = 0.32
	wheel.height = 0.22
	wheel.radial_segments = 10
	wheel.rings = 1
	var warr := wheel.get_mesh_arrays()
	for x: float in [-0.8, 0.8]:
		for z: float in [-1.35, 1.35]:
			var xf := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.32, z))
			for k in warr[Mesh.ARRAY_INDEX]:
				st.set_color(Color(0.03, 0.03, 0.03))
				st.set_normal(xf.basis * warr[Mesh.ARRAY_NORMAL][k])
				st.add_vertex(xf * warr[Mesh.ARRAY_VERTEX][k])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ParkedCars"
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.metallic = 0.3
	m.roughness = 0.4
	m.clearcoat_enabled = true # painted metal bodies
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.15
	mmi.material_override = m
	mmi.custom_aabb = AABB(Vector3(-3000, -200, -3000), Vector3(6000, 600, 6000))
	parent.add_child(mmi)


# ---------------------------------------------------------------- villages

func _villages() -> void:
	var made := 0
	for attempt in 60:
		if made >= 2:
			break
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var site := centers[i] + rights[i] * side * rng.randf_range(110.0, 180.0)
		site.y = _ground(site)
		if _track_dist(site) < 95.0 or not _clear(site, 60.0):
			continue
		_village(site, made == 0)
		no_trees.append([site, 70.0])
		made += 1


func _village(site: Vector3, with_church: bool) -> void:
	var walls := [Color(0.86, 0.83, 0.76), Color(0.8, 0.74, 0.62), Color(0.72, 0.7, 0.66), Color(0.88, 0.86, 0.82)]
	var roofs := [Color(0.42, 0.16, 0.1), Color(0.3, 0.14, 0.1), Color(0.2, 0.21, 0.23), Color(0.36, 0.22, 0.14)]
	if preset.snow > 0.0:
		roofs = [Color(0.88, 0.9, 0.93)]
	var street := rng.randf() * TAU
	for k in rng.randi_range(7, 11):
		var along := (k - 5) * 13.0
		var side := 1.0 if k % 2 == 0 else -1.0
		var dir := Vector3(cos(street), 0, sin(street))
		var p := site + dir * along + dir.cross(Vector3.UP) * side * rng.randf_range(10.0, 16.0)
		var basis := Basis(Vector3.UP, -street + (PI * 0.5 if side > 0 else -PI * 0.5) + rng.randf_range(-0.15, 0.15))
		if rng.randf() < 0.2:
			_barn(p, basis)
		else:
			_house(p, basis, walls[rng.randi() % walls.size()], roofs[rng.randi() % roofs.size()])
	if with_church:
		_church(site + Vector3(cos(street + 1.6), 0, sin(street + 1.6)) * 26.0, Basis(Vector3.UP, -street), roofs[0])


func _house(p: Vector3, basis: Basis, wall: Color, roof: Color) -> void:
	var w := rng.randf_range(7.0, 10.0)
	var l := rng.randf_range(9.0, 13.0)
	var h := rng.randf_range(4.0, 6.5)
	var base := _ground(p) - 1.5 # walls run into the slope
	var c := Vector3(p.x, base + (h + 1.5) * 0.5, p.z)
	_box("building", c, Vector3(w, h + 1.5, l), basis, wall)
	var top := base + h + 1.5
	_roof(Vector3(p.x, top + 1.6, p.z), w + 0.8, l + 0.8, 3.2, basis, roof)
	_box("building", Vector3(p.x, top + 2.2, p.z) + basis * Vector3(w * 0.25, 0, l * 0.3), Vector3(0.7, 2.2, 0.7), basis, Color(0.45, 0.3, 0.25))
	# Photo windows (FacadeKit atlas) and a door on both long sides.
	var win: int = [1, 2, 4, 5][rng.randi() % 4]
	for side: float in [-1.0, 1.0]:
		var out := basis * Vector3(side, 0, 0)
		var right := (-out).cross(Vector3.UP).normalized()
		for k in 3:
			var z := (k - 1) * l * 0.3
			var wall_p := Vector3(p.x, 0, p.z) + basis * Vector3(side * (w * 0.5 + 0.03), 0, z)
			for wy: float in [top - h * 0.45, top - h * 0.82]:
				if wy - 0.7 > top - h + 0.4:
					FacadeKit.add_unit(tools.photo, Vector3(wall_p.x, wy - 0.65, wall_p.z), right, win, 1.3)
	var door_out := basis * Vector3.RIGHT
	var door_p := Vector3(p.x, top - h, p.z) + basis * Vector3(w * 0.5 + 0.04, 0, l * 0.42)
	FacadeKit.add_unit(tools.photo, door_p, (-door_out).cross(Vector3.UP).normalized(), [9, 11, 8][rng.randi() % 3], 2.3)


func _barn(p: Vector3, basis: Basis) -> void:
	var base := _ground(p) - 1.5
	var c := Vector3(p.x, base + 4.25, p.z)
	var wood := Color(0.38, 0.2, 0.13) if rng.randf() < 0.6 else Color(0.3, 0.26, 0.2)
	_box("building", c, Vector3(11.0, 8.5, 18.0), basis, wood)
	_roof(Vector3(p.x, base + 8.5 + 2.2, p.z), 12.0, 19.0, 4.4, basis, Color(0.24, 0.24, 0.25) if preset.snow == 0.0 else Color(0.88, 0.9, 0.93))
	_box("building", Vector3(p.x, base + 3.5, p.z) + basis * Vector3(0, 0, 9.03), Vector3(4.5, 5.0, 0.05), basis, Color(0.2, 0.12, 0.08))


func _church(p: Vector3, basis: Basis, roof: Color) -> void:
	var base := _ground(p) - 1.5
	var wall := Color(0.84, 0.82, 0.77)
	_box("building", Vector3(p.x, base + 5.5, p.z), Vector3(10.0, 11.0, 20.0), basis, wall)
	_roof(Vector3(p.x, base + 11.0 + 2.5, p.z), 11.0, 21.0, 5.0, basis, roof)
	var tower := Vector3(p.x, 0, p.z) + basis * Vector3(0, 0, -12.5)
	_box("building", Vector3(tower.x, base + 11.0, tower.z), Vector3(5.5, 22.0, 5.5), basis, wall)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.05
	spire.bottom_radius = 3.4
	spire.height = 10.0
	spire.radial_segments = 4
	spire.rings = 1
	_add("roof", spire, Transform3D(basis.rotated(Vector3.UP, PI * 0.25), Vector3(tower.x, base + 27.0, tower.z)), Color(0.2, 0.26, 0.24))
	for k in 4:
		var face := basis.rotated(Vector3.UP, k * PI * 0.5)
		_box("glass", Vector3(tower.x, base + 18.0, tower.z) + face * Vector3(0, 0, 2.77), Vector3(1.2, 2.4, 0.05), face, Color(0.08, 0.08, 0.09))


# ---------------------------------------------------------------- windmill, lake, balloon

func _windmill() -> void:
	# The highest ground a little way off the track, so it shows on the skyline.
	var best := Vector3.ZERO
	var best_h := -INF
	for k in 40:
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := centers[i] + rights[i] * side * rng.randf_range(90.0, 220.0)
		p.y = _ground(p)
		if p.y > best_h and _track_dist(p) > 80.0 and _clear(p, 25.0):
			best_h = p.y
			best = p
	if best_h == -INF:
		return
	var tower := CylinderMesh.new()
	tower.top_radius = 2.2
	tower.bottom_radius = 3.4
	tower.height = 16.0
	tower.radial_segments = 8
	tower.rings = 1
	_add("building", tower, Transform3D(Basis(), best + Vector3.UP * 7.5), Color(0.86, 0.84, 0.8))
	var cap := SphereMesh.new()
	cap.radius = 2.6
	cap.height = 3.2
	cap.is_hemisphere = true
	cap.radial_segments = 10
	cap.rings = 3
	_add("roof", cap, Transform3D(Basis(), best + Vector3.UP * 15.4), Color(0.3, 0.18, 0.12))
	var facing := Basis(Vector3.UP, rng.randf() * TAU)
	var hub := Spinner.new()
	hub.spin_speed = 0.9 if preset.wet > 0.5 else 0.5
	hub.transform = Transform3D(facing, best + Vector3.UP * 15.5 + facing * Vector3(0, 0, 2.8))
	parent.add_child(hub)
	var sail_mat := StandardMaterial3D.new()
	sail_mat.albedo_color = Color(2.4, 2.35, 2.2) # canvas texture is dark grey
	sail_mat.albedo_texture = Mats.tex("canvas", "diff")
	sail_mat.normal_enabled = true
	sail_mat.normal_texture = Mats.tex("canvas", "nor_gl")
	sail_mat.uv1_scale = Vector3(1.5, 10.0, 1.0)
	sail_mat.roughness = 0.9
	sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 4:
		var arm := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.6, 10.0, 0.12)
		arm.mesh = b
		arm.material_override = sail_mat
		arm.transform = Transform3D(Basis(Vector3.BACK, k * PI * 0.5), Vector3.ZERO) * Transform3D(Basis(), Vector3(0.6, 5.3, 0))
		hub.add_child(arm)
	no_trees.append([best, 18.0])


func _lake() -> void:
	if terrain == null or preset.snow > 0.0:
		return # a frozen lake would just look like snow
	var best := Vector3.ZERO
	var best_h := INF
	for k in 60:
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := centers[i] + rights[i] * side * rng.randf_range(120.0, 260.0)
		p.y = _ground(p)
		if p.y < best_h and _track_dist(p) > 115.0 and _clear(p, 40.0):
			best_h = p.y
			best = p
	if best_h == INF:
		return
	var level := best_h + 2.5
	# Don't flood the track: keep the water well below any nearby road.
	for c in centers:
		if Vector2(c.x - best.x, c.z - best.z).length() < 170.0 and c.y < level + 1.5:
			level = c.y - 1.5
	if level < best_h + 0.5:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = plane
	mi.position = Vector3(best.x, level, best.z)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	for key in ["ripple_a", "ripple_b"]:
		var nt := NoiseTexture2D.new()
		var nz := FastNoiseLite.new()
		nz.seed = rng.randi()
		nz.frequency = 0.03
		nt.noise = nz
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 4.0
		nt.generate_mipmaps = true
		mat.set_shader_parameter(key, nt)
	mat.set_shader_parameter("choppiness", 0.9 if preset.wet > 0.5 else 0.45)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	no_trees.append([best, 60.0])


func _balloon() -> void:
	if preset.wet > 0.5:
		return # nobody flies in a thunderstorm
	var c := Vector3.ZERO
	for p in centers:
		c += p
	c /= centers.size()
	var b := Spinner.new()
	b.name = "Balloon"
	b.position = c + Vector3.UP * 170.0
	b.drift_radius = 220.0
	b.drift_speed = 0.012
	b.bob = 6.0
	parent.add_child(b)
	var envelope := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 9.0
	s.height = 21.0
	s.radial_segments = 16
	s.rings = 10
	envelope.mesh = s
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float gore = step(0.5, fract(atan(lp.z, lp.x) / 6.2831 * 8.0));
	vec3 a = vec3(0.62, 0.12, 0.08);
	vec3 b = vec3(0.9, 0.78, 0.35);
	ALBEDO = mix(a, b, gore);
	ROUGHNESS = 0.7;
}
"""
	m.shader = sh
	envelope.material_override = m
	envelope.position.y = 12.0
	b.add_child(envelope)
	var basket := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.2, 1.6)
	basket.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.8, 1.6, 1.3) # wicker-ish weathered wood
	bmat.albedo_texture = Mats.tex("wood", "diff")
	bmat.normal_enabled = true
	bmat.normal_texture = Mats.tex("wood", "nor_gl")
	bmat.uv1_scale = Vector3(2.0, 2.0, 2.0)
	bmat.roughness = 0.9
	basket.material_override = bmat
	b.add_child(basket)
