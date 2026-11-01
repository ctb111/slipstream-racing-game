class_name Wildlife
extends Node3D
## Animals, birds and pets: realistic scanned/sculpted models (Objaverse /
## Sketchfab CC-BY, see assets/wildlife/CREDITS_wildlife.txt), normalised by
## assets/wildlife/bake/bake_animals.py, drawn as MultiMeshes with all motion
## in shaders/wildlife.gdshader (grazing, tails, pecking, gaits, wing beats,
## soaring circles, flights).
##
## Usage (one node per circuit; scripts/world/wildlife_builder.gd does the
## placement for every track):
##   var w := Wildlife.make(circuit)          # or Wildlife.of(circuit) to reuse it
##   w.add("cow_red", xf)                      # feet at xf.origin, head to -Z
##   w.perch("crow", xf)                       # flies off when a car comes close
##   w.add_reactive("deer", xf, away_dir)      # bolts away from passing cars
##   w.chase_dog(xf, along_dir)                # farm dog running along the fence
##   w.soar("gull", centre, radius, speed)     # circling in the sky
##   w.finish()                                # builds the multimeshes (after all adds)
## Species: SPECIES keys. Logic (cars nearby -> events) runs 5 times a second;
## the shaders read the event times from INSTANCE_CUSTOM and the `now` clock.

enum Kind { GRAZER, PERCHED, SOARING, FLEEING, CAT, DOG }

## file: assets/wildlife/models/<file>_{hi,lo}.glb; near: hi -> lo (m);
## far: lo drawn up to (m); belly: share of the height below which legs swing.
const SPECIES := {
	cow_red = {file = "cow_red", kind = Kind.GRAZER, near = 45.0, far = 420.0, shadow = true, belly = 0.48,
		p = {graze = 1.0, tail_amp = 0.12, tail_speed = 1.4, stride = 0.3, gait_hz = 1.6, run_speed = 4.0}},
	cow_holstein = {file = "cow_holstein", kind = Kind.GRAZER, near = 45.0, far = 420.0, shadow = true, belly = 0.48,
		p = {graze = 1.0, tail_amp = 0.12, tail_speed = 1.4, stride = 0.3, gait_hz = 1.6, run_speed = 4.0}},
	sheep = {file = "sheep", kind = Kind.GRAZER, near = 30.0, far = 300.0, shadow = false, belly = 0.42,
		p = {graze = 1.0, tail_amp = 0.04, tail_speed = 3.0, stride = 0.18, gait_hz = 3.0, run_speed = 5.0}},
	horse = {file = "horse", kind = Kind.GRAZER, near = 50.0, far = 450.0, shadow = true, belly = 0.5,
		p = {graze = 0.8, tail_amp = 0.14, tail_speed = 1.1, stride = 0.45, gait_hz = 1.9, run_speed = 8.0}},
	deer = {file = "deer", kind = Kind.GRAZER, near = 45.0, far = 380.0, shadow = true, belly = 0.5,
		p = {graze = 0.7, tail_amp = 0.03, tail_speed = 2.0, stride = 0.42, gait_hz = 2.6, run_speed = 11.0, paint = 1}},
	dog_lab = {file = "dog_lab", kind = Kind.DOG, near = 22.0, far = 140.0, shadow = false, belly = 0.5,
		p = {tail_amp = 0.09, tail_speed = 11.0, stride = 0.16, gait_hz = 3.4, run_speed = 8.5}},
	dog_shepherd = {file = "dog_shepherd", kind = Kind.DOG, near = 22.0, far = 140.0, shadow = false, belly = 0.5,
		p = {tail_amp = 0.07, tail_speed = 8.0, stride = 0.18, gait_hz = 3.2, run_speed = 9.0}},
	cat_ginger = {file = "cat_ginger", kind = Kind.CAT, near = 16.0, far = 90.0, shadow = false, belly = 0.3,
		p = {tail_amp = 0.06, tail_speed = 1.1}},
	crow = {file = "crow", kind = Kind.PERCHED, near = 14.0, far = 110.0, shadow = false, belly = 0.3, p = {}},
	pigeon = {file = "pigeon", kind = Kind.PERCHED, near = 12.0, far = 90.0, shadow = false, belly = 0.3, p = {}},
	gull = {file = "gull", kind = Kind.PERCHED, near = 16.0, far = 130.0, shadow = false, belly = 0.3, p = {}},
}
## Flying plumage per bird: [body (COLOR), wings, black tips (COLOR.a), wingspan m, flap Hz, glide share].
const PLUMAGE := {
	crow = [Color(0.035, 0.035, 0.04), Color(0.03, 0.03, 0.035), 0.0, 0.95, 3.6, 0.35],
	pigeon = [Color(0.42, 0.44, 0.48), Color(0.36, 0.38, 0.42), 0.0, 0.65, 5.5, 0.15],
	gull = [Color(0.92, 0.92, 0.9), Color(0.62, 0.64, 0.66), 1.0, 1.35, 2.6, 0.6],
	raptor = [Color(0.3, 0.2, 0.12), Color(0.24, 0.16, 0.1), 0.0, 1.3, 2.2, 0.92],
	rook = [Color(0.05, 0.05, 0.055), Color(0.04, 0.04, 0.045), 0.0, 0.85, 3.8, 0.25],
}
const LOGIC_DT := 0.2
const CELL := 80.0
## Perched birds take off when a car passes this close (m), deer bolt at BOLT_R.
const FLEE_R := 15.0
const BOLT_R := 42.0
const CHASE_R := 30.0

static var _mesh_cache := {}

var clock := 0.0
var circuit: Node3D
var terrain: Terrain
var _items := {} ## species -> {xfs: Array[Transform3D], cus: Array[Color], cols: Array[Color]}
var _soar := {} ## plumage -> same
var _mats: Array[ShaderMaterial] = []
## Reactive animals: [type, species, index, pos, state, t_next, dir]
var _react: Array = []
var _react_grid := {}
## species -> Array of MMIs holding instance i (all LODs / the flee copy): [mmi, local index] per instance
var _slots := {}
var _flee_slots := {}
var _cars: Array = []
var _car_t := 0.0
var _logic_t := 0.0
var _rng := RandomNumberGenerator.new()
var _owl: AudioStreamPlayer
var _owl_t := 12.0
var stats := {instances = 0, multimeshes = 0}
var events := {perch = 0, bolt = 0, chase = 0, land = 0}
var _dbg := OS.get_cmdline_user_args().has("--debug-wildlife")
var _dbg_t := 0.0


## The circuit's Wildlife node, created on first use.
static func of(c: Node3D) -> Wildlife:
	var w := c.get_node_or_null("Wildlife") as Wildlife
	if w == null:
		w = make(c)
	return w


static func make(c: Node3D) -> Wildlife:
	var w := Wildlife.new()
	w.name = "Wildlife"
	w.circuit = c
	w.terrain = c.get_meta("terrain", null)
	w._rng.seed = hash(c.name) ^ 0x5eed
	c.add_child(w)
	return w


## A static (non-reactive) animal at `xf` (feet; head to -Z). `custom.r` is
## its identity hash (random when < 0).
func add(species: String, xf: Transform3D, tint := Color.WHITE, ev_a := 0.0, ev_b := 0.0) -> int:
	if not _items.has(species):
		_items[species] = {xfs = [], cus = [], cols = []}
	var it: Dictionary = _items[species]
	it.xfs.append(xf)
	it.cus.append(Color(_rng.randf(), 0.0, ev_a, ev_b))
	it.cols.append(tint)
	return it.xfs.size() - 1


## A bird sitting on a rail, roof or the ground; it flies off from passing cars.
func perch(species: String, xf: Transform3D) -> void:
	var i := add(species, xf)
	_track(["perch", species, i, xf.origin, 0, 0.0, Vector3.ZERO])


## A grazer that bolts along `away` (horizontal) when a car comes close.
func add_reactive(species: String, xf: Transform3D, away: Vector3) -> void:
	var i := add(species, xf)
	_track(["bolt", species, i, xf.origin, 0, 0.0, away])


## A dog that runs along `along` (and back next time) as cars pass.
func chase_dog(species: String, xf: Transform3D, along: Vector3) -> void:
	var i := add(species, xf)
	_track(["chase", species, i, xf.origin, 0, 0.0, along])


## A bird circling `centre` at `radius` m, `speed` rad/s (sign = direction).
func soar(plumage: String, centre: Vector3, radius: float, speed: float) -> void:
	if not _soar.has(plumage):
		_soar[plumage] = {xfs = [], cus = [], cols = []}
	var it: Dictionary = _soar[plumage]
	it.xfs.append(Transform3D(Basis(), centre))
	it.cus.append(Color(_rng.randf(), 0.0, speed, radius))
	var p: Array = PLUMAGE[plumage]
	it.cols.append(Color(p[0].r, p[0].g, p[0].b, p[2]))


## A loose flock: `n` birds on overlapping circles around `centre`.
func flock(plumage: String, centre: Vector3, n: int, radius: float, speed: float) -> void:
	for k in n:
		var c := centre + Vector3(_rng.randf_range(-1, 1) * radius * 0.2, _rng.randf_range(-3.0, 3.0), _rng.randf_range(-1, 1) * radius * 0.2)
		soar(plumage, c, radius * _rng.randf_range(0.8, 1.15), speed * _rng.randf_range(0.9, 1.1))


func _track(r: Array) -> void:
	_react.append(r)
	var k := Vector2i(floori(r[3].x / CELL), floori(r[3].z / CELL))
	if not _react_grid.has(k):
		_react_grid[k] = []
	_react_grid[k].append(_react.size() - 1)


## Builds the multimeshes. Call once, after all adds.
func finish() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if OS.get_cmdline_user_args().has("--debug-wildlife"):
		for species: String in _items:
			var it: Dictionary = _items[species]
			print("wildlife %s x%d, e.g. at %s facing %s" % [species, it.xfs.size(), it.xfs[0].origin, -it.xfs[0].basis.z])
		for pl: String in _soar:
			print("wildlife soaring %s x%d, e.g. round %s" % [pl, _soar[pl].xfs.size(), _soar[pl].xfs[0].origin])
	for species: String in _items:
		var sp: Dictionary = SPECIES[species]
		var it: Dictionary = _items[species]
		_slots[species] = []
		_slots[species].resize(it.xfs.size())
		var groups := _group(it.xfs)
		var kind: int = sp.kind
		for cell: Vector2i in groups:
			var idx: Array = groups[cell]
			for lod in ["hi", "lo"]:
				var mesh := _mesh(species, lod)
				var r0: float = 0.0 if lod == "hi" else sp.near
				var r1: float = sp.near if lod == "hi" else sp.far
				var mmi := _mmi(mesh, it, idx, r0, r1, 6.0 if kind == Kind.GRAZER else 2.0)
				if lod == "hi" and sp.shadow:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				for j in idx.size():
					if _slots[species][idx[j]] == null:
						_slots[species][idx[j]] = []
					_slots[species][idx[j]].append([mmi, j])
			if kind == Kind.PERCHED:
				# The same birds in flight, hidden until they take off.
				var p: Array = PLUMAGE.get(species, PLUMAGE.crow)
				var fly := {xfs = [], cus = [], cols = []}
				for j in idx:
					fly.xfs.append(it.xfs[j])
					fly.cus.append(it.cus[j])
					fly.cols.append(Color(p[0].r, p[0].g, p[0].b, p[2]))
				var all: Array = range(idx.size())
				var mmi := _mmi(_fly_mesh(species, Kind.FLEEING), fly, all, 0.0, 260.0, 0.0)
				mmi.custom_aabb = AABB(mmi.custom_aabb.position - Vector3(170, 5, 170), mmi.custom_aabb.size + Vector3(340, 130, 340))
				mmi.visible = false # no draw call until one of them takes off
				if not _flee_slots.has(species):
					_flee_slots[species] = []
					_flee_slots[species].resize(it.xfs.size())
				for j in idx.size():
					_flee_slots[species][idx[j]] = [mmi, j]
	for plumage: String in _soar:
		var it: Dictionary = _soar[plumage]
		var all: Array = range(it.xfs.size())
		var groups := _group(it.xfs)
		for cell: Vector2i in groups:
			var mmi := _mmi(_fly_mesh(plumage, Kind.SOARING), it, groups[cell], 0.0, 700.0, 0.0)
			var rmax := 0.0
			for j: int in groups[cell]:
				rmax = maxf(rmax, it.cus[j].a)
			mmi.custom_aabb = mmi.custom_aabb.grow(rmax + 4.0)
	_items.clear()
	_soar.clear()
	set_process(true)


## Instance indices grouped into CELL m squares.
func _group(xfs: Array) -> Dictionary:
	var g := {}
	for i in xfs.size():
		var o: Vector3 = xfs[i].origin
		var k := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not g.has(k):
			g[k] = []
		g[k].append(i)
	return g


func _mmi(mesh: ArrayMesh, it: Dictionary, idx: Array, r0: float, r1: float, margin: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = idx.size()
	var box := AABB()
	for j in idx.size():
		var i: int = idx[j]
		var xf: Transform3D = it.xfs[i]
		mm.set_instance_transform(j, xf)
		mm.set_instance_color(j, it.cols[i])
		mm.set_instance_custom_data(j, it.cus[i])
		box = AABB(xf.origin, Vector3.ZERO) if j == 0 else box.expand(xf.origin)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Room for the animal itself and for a run to its end point.
	mmi.custom_aabb = box.grow(4.0 + margin * 5.0)
	mmi.visibility_range_begin = maxf(r0 - margin * 0.0, 0.0)
	mmi.visibility_range_begin_margin = 2.0 if r0 > 0.0 else 0.0
	# The range is measured to the cell's AABB centre: a far tier adds the
	# cell's half-diagonal so animals at its near edge are not cut early.
	mmi.visibility_range_end = r1 + (Vector2(box.size.x, box.size.z).length() * 0.5 if r0 > 0.0 else 0.0)
	mmi.visibility_range_end_margin = 2.0
	add_child(mmi)
	stats.instances += idx.size()
	stats.multimeshes += 1
	return mmi


## The species' mesh with animation weights in CUSTOM0 and wildlife materials.
func _mesh(species: String, lod: String) -> ArrayMesh:
	var key := species + "_" + lod
	if _mesh_cache.has(key):
		var cached: ArrayMesh = _mesh_cache[key]
		_register(cached)
		return cached
	var sp: Dictionary = SPECIES[species]
	var src := _load_glb("res://assets/wildlife/models/%s_%s.glb" % [sp.file, lod])
	var out := _weighted(src, sp.kind, sp.belly, sp.p)
	_mesh_cache[key] = out
	_register(out)
	return out


func _fly_mesh(plumage: String, kind: int) -> ArrayMesh:
	var key := "fly_%s_%d" % [plumage, kind]
	if _mesh_cache.has(key):
		_register(_mesh_cache[key])
		return _mesh_cache[key]
	var p: Array = PLUMAGE.get(plumage, PLUMAGE.crow)
	var src := _load_glb("res://assets/wildlife/models/bird_fly_hi.glb")
	var out := _weighted(src, kind, 0.3, {paint = 2, wing_col = p[1], flap_hz = p[4], glide = p[5]}, p[3])
	_mesh_cache[key] = out
	_register(out)
	return out


func _register(m: ArrayMesh) -> void:
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s) as ShaderMaterial
		if mat and not _mats.has(mat):
			_mats.append(mat)


static func _load_glb(path: String) -> ArrayMesh:
	var ps := load(path) as PackedScene
	if ps == null:
		push_warning("Wildlife: missing " + path)
		return null
	var root := ps.instantiate()
	var mi: MeshInstance3D = root if root is MeshInstance3D else root.find_children("*", "MeshInstance3D", true, false)[0]
	var m := mi.mesh as ArrayMesh
	# Materials may live on the instance (surface overrides) or on the mesh.
	var out := ArrayMesh.new()
	var xf := mi.transform
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		if xf != Transform3D.IDENTITY:
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for k in vs.size():
				vs[k] = xf * vs[k]
			arr[Mesh.ARRAY_VERTEX] = vs
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := mi.get_surface_override_material(s)
		out.surface_set_material(s, mat if mat else m.surface_get_material(s))
	root.free()
	return out


## Copy of `src` with CUSTOM0 = (head, legs, tail, leg phase | signed wing) and
## a wildlife ShaderMaterial per surface (same albedo texture). `span` rescales
## a flying bird to that wingspan.
static func _weighted(src: ArrayMesh, kind: int, belly: float, params: Dictionary, span := 0.0) -> ArrayMesh:
	var box := AABB()
	for s in src.get_surface_count():
		var vs: PackedVector3Array = src.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for k in vs.size():
			box = AABB(vs[k], Vector3.ZERO) if (s == 0 and k == 0) else box.expand(vs[k])
	var k_scale := 1.0
	if span > 0.0:
		k_scale = span / box.size.x
	var size := box.size * k_scale
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cu := PackedFloat32Array()
		cu.resize(vs.size() * 4)
		for k in vs.size():
			var v := vs[k]
			if span > 0.0:
				v = Vector3(v.x - box.get_center().x, v.y - box.get_center().y, v.z - box.get_center().z) * k_scale
				vs[k] = v
			var fz := clampf((box.end.z - v.z) / box.size.z, 0.0, 1.0) # 0 tail .. 1 nose
			var h := clampf(v.y / maxf(size.y, 0.01), 0.0, 1.0)
			var hw := 0.0
			var lw := 0.0
			var tw := 0.0
			var ph := 0.0
			match kind:
				Kind.GRAZER, Kind.DOG:
					hw = smoothstep(0.68, 0.82, fz) * smoothstep(0.42, 0.6, h)
					lw = clampf((belly - h) / belly, 0.0, 1.0)
					tw = smoothstep(0.08, 0.0, fz) * smoothstep(0.1, 0.35, h)
					var front := fz > 0.5
					var left := v.x < box.get_center().x
					ph = 0.5 if front != left else 0.0
				Kind.PERCHED:
					hw = smoothstep(0.62, 0.78, fz) * smoothstep(0.45, 0.65, h)
					tw = smoothstep(0.25, 0.0, fz)
				Kind.CAT:
					hw = smoothstep(0.6, 0.74, h)
					tw = smoothstep(0.45, 0.05, fz) * smoothstep(0.25, 0.05, h)
				_:
					var half := size.x * 0.5
					var aw := clampf((absf(v.x) / half - 0.12) / 0.88, 0.0, 1.0)
					ph = aw * signf(v.x)
			cu[k * 4] = hw
			cu[k * 4 + 1] = lw
			cu[k * 4 + 2] = tw
			cu[k * 4 + 3] = ph
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_CUSTOM0] = cu
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {},
			Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/wildlife.gdshader")
		var sm := src.surface_get_material(s) as BaseMaterial3D
		var tex: Texture2D = sm.albedo_texture if sm else null
		mat.set_shader_parameter("has_tex", tex != null)
		if tex:
			mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("kind", kind)
		mat.set_shader_parameter("size", Vector3(size.x, size.y, size.z))
		for p: String in params:
			mat.set_shader_parameter(p, params[p])
		out.surface_set_material(s, mat)
	return out


func _process(dt: float) -> void:
	clock += dt
	if clock > 3000.0: # keep float precision in the shaders
		_rebase(2000.0)
	for m in _mats:
		m.set_shader_parameter("now", clock)
	_logic_t -= dt
	if _logic_t > 0.0:
		return
	_logic_t = LOGIC_DT
	_car_t -= LOGIC_DT
	if _car_t <= 0.0:
		_car_t = 3.0
		_cars.clear()
		var root := get_tree().current_scene
		if root and "entries" in root: # the race: its entries hold every car
			for e in root.entries:
				if e.car:
					_cars.append(e.car)
		elif root:
			for n in root.find_children("*", "RigidBody3D", true, false):
				if n is Car:
					_cars.append(n)
	if _owl:
		_owl_t -= LOGIC_DT
		if _owl_t <= 0.0:
			_owl_t = _rng.randf_range(18.0, 45.0)
			_owl.pitch_scale = _rng.randf_range(0.94, 1.06)
			_owl.volume_db = _rng.randf_range(-20.0, -13.0)
			_owl.play()
	var lt := Time.get_ticks_usec()
	_logic()
	if _dbg:
		_dbg_t += LOGIC_DT
		if _dbg_t > 5.0:
			_dbg_t = 0.0
			print("wildlife t=%.0f cars=%d events %s, logic %d us" % [clock, _cars.size(), events, Time.get_ticks_usec() - lt])


func _logic() -> void:
	if _react.is_empty():
		return
	for c in _cars:
		if not is_instance_valid(c):
			continue
		var car := c as RigidBody3D
		var p := car.global_position
		var vel := car.linear_velocity
		if vel.length() < 4.0:
			continue
		var cx := floori(p.x / CELL)
		var cz := floori(p.z / CELL)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var lst = _react_grid.get(Vector2i(cx + dx, cz + dz))
				if lst == null:
					continue
				for ri: int in lst:
					var r: Array = _react[ri]
					var d: float = (r[3] as Vector3).distance_to(p)
					if r[4] != 0:
						continue
					match r[0]:
						"perch":
							if d < FLEE_R:
								_flee(r, p)
						"bolt":
							if d < BOLT_R:
								_bolt(r)
						"chase":
							if d < CHASE_R and clock > r[5]:
								_chase(r, vel)
	# Birds come back once the road is quiet.
	for r: Array in _react:
		if r[0] == "perch" and r[4] == 1 and clock > r[5]:
			_land(r)


func _set_custom(species: String, i: int, cu: Color, xf = null) -> void:
	for s: Array in _slots[species][i]:
		var mm := (s[0] as MultiMeshInstance3D).multimesh
		mm.set_instance_custom_data(s[1], cu)
		if xf != null:
			mm.set_instance_transform(s[1], xf)


func _custom(species: String, i: int) -> Color:
	var s: Array = _slots[species][i][0]
	return (s[0] as MultiMeshInstance3D).multimesh.get_instance_custom_data(s[1])


func _flee(r: Array, car_pos: Vector3) -> void:
	var sp: String = r[1]
	var t0 := clock + _rng.randf_range(0.0, 0.5)
	var cu := _custom(sp, r[2])
	cu.g = t0
	_set_custom(sp, r[2], cu)
	var fs: Array = _flee_slots[sp][r[2]]
	var away: Vector3 = (r[3] as Vector3) - car_pos
	away.y = 0.0
	away = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9)) if away.length() > 0.1 else Vector3.FORWARD
	(fs[0] as MultiMeshInstance3D).visible = true
	var mm := (fs[0] as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(fs[1], Transform3D(Basis.looking_at(away, Vector3.UP), r[3]))
	mm.set_instance_custom_data(fs[1], cu)
	r[4] = 1
	r[5] = clock + _rng.randf_range(35.0, 80.0)
	events.perch += 1


func _land(r: Array) -> void:
	for c in _cars:
		if is_instance_valid(c) and (c as Node3D).global_position.distance_to(r[3]) < 60.0:
			r[5] = clock + 10.0
			return
	var cu := _custom(r[1], r[2])
	cu.g = 0.0
	_set_custom(r[1], r[2], cu)
	var fs: Array = _flee_slots[r[1]][r[2]]
	(fs[0] as MultiMeshInstance3D).multimesh.set_instance_custom_data(fs[1], cu)
	r[4] = 0
	events.land += 1


func _bolt(r: Array) -> void:
	var away: Vector3 = r[6]
	var dist := _rng.randf_range(22.0, 34.0)
	var start: Vector3 = r[3]
	var end := start + away.rotated(Vector3.UP, _rng.randf_range(-0.35, 0.35)) * dist
	end.y = terrain.surface_at(end.x, end.z) if terrain else start.y
	var dir := (end - start)
	dir.y = 0.0
	var cu := _custom(r[1], r[2])
	cu.g = clock + _rng.randf_range(0.0, 0.6)
	cu.b = dist
	cu.a = end.y - start.y
	var xf := Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), end)
	_set_custom(r[1], r[2], cu, xf)
	r[3] = end
	r[4] = 1 # stays where it ran to
	events.bolt += 1


func _chase(r: Array, car_vel: Vector3) -> void:
	var along: Vector3 = r[6]
	if car_vel.dot(along) < 0.0:
		along = -along
	var dist := _rng.randf_range(10.0, 16.0)
	var start: Vector3 = r[3]
	var end := start + along * dist
	if (r.size() > 7):
		# Stay on its stretch of fence: turn back past the ends.
		var home: Vector3 = r[7]
		if end.distance_to(home) > 18.0:
			along = -along
			end = start + along * dist
	else:
		r.append(start)
	end.y = terrain.surface_at(end.x, end.z) if terrain else start.y
	var cu := _custom(r[1], r[2])
	cu.g = clock
	cu.b = dist
	cu.a = end.y - start.y
	_set_custom(r[1], r[2], cu, Transform3D(Basis.looking_at(along, Vector3.UP), end))
	r[3] = end
	r[5] = clock + dist / 9.0 + 2.5
	events.chase += 1


## Shifts every event time back so the clock stays small.
func _rebase(by: float) -> void:
	clock -= by
	for r: Array in _react:
		r[5] -= by
		var cu := _custom(r[1], r[2])
		if cu.g > 0.0:
			cu.g = maxf(cu.g - by, 0.001)
			_set_custom(r[1], r[2], cu)
			if _flee_slots.has(r[1]):
				var fs: Array = _flee_slots[r[1]][r[2]]
				(fs[0] as MultiMeshInstance3D).multimesh.set_instance_custom_data(fs[1], cu)


## Night: no animals to see, a tawny owl calls now and then.
func owl_calls() -> void:
	_owl = AudioStreamPlayer.new()
	_owl.stream = _owl_hoot()
	_owl.bus = "Master"
	add_child(_owl)
	set_process(true)


## Tawny owl: "hoo ... hu-hu-hoooo" (synthesised; no samples in the project).
static func _owl_hoot() -> AudioStreamWAV:
	var rate := 22050
	var notes := [[0.0, 0.55, 1.0], [1.45, 0.14, 0.7], [1.66, 0.14, 0.75], [1.88, 0.95, 1.0]]
	var total := 3.0
	var n := int(total * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		for no: Array in notes:
			var a: float = no[0]
			var d: float = no[1]
			if t >= a and t < a + d:
				var u := (t - a) / d
				var env := smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.55, u)
				var f := 560.0 - 60.0 * u + 9.0 * sin(t * 38.0) * u
				ph += TAU * f / rate
				s = (sin(ph) + 0.18 * sin(ph * 2.0) + 0.05 * sin(ph * 3.0)) * env * float(no[2])
		var v := int(clampf(s * 0.5, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
