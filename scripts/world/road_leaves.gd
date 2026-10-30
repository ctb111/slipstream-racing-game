class_name RoadLeaves
extends Node3D
## Fallen leaves on the tarmac where the forest comes close to the road,
## drifted against the edges and thin on the racing line, kicked up and tumbled
## by every passing car (shaders/road_leaves.gdshader). One mesh, one draw call.
## Built once the circuit is complete (the forest and racing line exist then).
## None on snow; wet leaves stay put. Debug: `-- --noleaves`.

const MAX_CARS := 8
const PER_METRE := [1.2, 2.5, 3.5, 4.5] ## leaves per metre of fully wooded road, per quality
const COLOURS := [
	Color(0.32, 0.13, 0.035), Color(0.45, 0.2, 0.04), Color(0.55, 0.36, 0.06),
	Color(0.22, 0.14, 0.06), Color(0.26, 0.22, 0.07), Color(0.4, 0.1, 0.03),
]

var _circuit: Node3D
var _road_width := 12.0
var _mat: ShaderMaterial
const CHUNK := 120.0 # m of road per mesh (fewer draw calls; shrunk leaves cost only vertices)
const FADE_END := 110.0 # leaves have shrunk to nothing here (shader)
var _cars: Array = []
var _scan_t := 0.0
var _p := PackedVector4Array()
var _v := PackedVector4Array()


static func build(parent: Node3D, _curve: Curve3D, road_width: float, preset: Dictionary) -> void:
	if float(preset.get("snow", 0.0)) > 0.5 or OS.get_cmdline_user_args().has("--noleaves"):
		return
	if not parent.has_signal("build_progress"):
		return
	var n := RoadLeaves.new()
	n.name = "RoadLeaves"
	n._circuit = parent
	n._road_width = road_width
	n.set_meta("wet", float(preset.get("wet", 0.0)))
	parent.add_child(n)
	parent.build_progress.connect(n._on_progress)
	n.set_process(false)


func _on_progress(f: float, _label: String) -> void:
	if f < 1.0 or _mat != null:
		return
	_build_mesh()


func _build_mesh() -> void:
	var curve: Curve3D = _circuit.get("curve")
	var line = _circuit.get("line")
	var trunks := _circuit.get_node_or_null("TreeTrunks")
	if curve == null or trunks == null:
		return
	# Trunk positions in a 25 m grid.
	const G := 25.0
	var grid := {}
	for c in trunks.get_children():
		var p: Vector3 = (c as Node3D).position
		var k := Vector2i(floori(p.x / G), floori(p.z / G))
		grid[k] = int(grid.get(k, 0)) + 1
	var length := curve.get_baked_length()
	var half := _road_width * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(length))
	var per_m: float = PER_METRE[clampi(Game.quality, 0, 3)]
	var d = _circuit.get("def")
	var autumn: bool = d is Dictionary and str(d.get("theme", "")) == "autumn"
	if autumn: # herbstwald: a dense, orange carpet
		per_m *= 2.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	var step := 2.0
	var s := 0.0
	# Chunks of ~CHUNK m of road (Godot culls by the AABB centre: one mesh for
	# the whole lap switched on and off as a whole). The shader shrinks leaves
	# away before the chunk's range ends, so nothing pops.
	var chunks: Array[ArrayMesh] = []
	var chunk_from := 0.0
	var in_chunk := 0
	while s < length:
		if s - chunk_from >= CHUNK:
			if in_chunk > 0:
				chunks.append(st.commit())
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
			chunk_from = s
			in_chunk = 0
		var p := curve.sample_baked(s)
		# Trees within ~60 m: the 5x5 cells around (the forest keeps ~30 m off the road).
		var ck := Vector2i(floori(p.x / G), floori(p.z / G))
		var trees := 0
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				trees += int(grid.get(ck + Vector2i(dx, dz), 0))
		var density := smoothstep(4.0, 28.0, float(trees))
		if autumn:
			density = maxf(density, 0.35)
		var n := int(round(density * per_m * step + rng.randf() - 0.5))
		if n > 0:
			var ahead := curve.sample_baked(fmod(s + 1.0, length))
			var fwd := (ahead - p).normalized()
			var right := fwd.cross(Vector3.UP).normalized()
			var line_lat := 0.0
			if line is RacingLine:
				var rl: RacingLine = line
				line_lat = rl.lateral[int(s / length * rl.count()) % rl.count()]
			for _i in n:
				# Mostly drifted against the edges, a few scattered across.
				var lat: float
				if rng.randf() < 0.75:
					var side := -1.0 if rng.randf() < 0.5 else 1.0
					lat = side * (half - 0.15 - absf(rng.randfn(0.0, 1.0)) * 0.9)
				else:
					lat = rng.randf_range(-half + 0.3, half - 0.3)
					if absf(lat - line_lat) < 1.6 and rng.randf() < 0.8:
						continue # the racing line is swept clean
				var c := p + fwd * rng.randf_range(0.0, step) + right * lat + Vector3.UP * 0.036
				_leaf(st, c, rng)
				count += 1
				in_chunk += 1
		s += step
	if in_chunk > 0:
		chunks.append(st.commit())
	if count == 0:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/road_leaves.gdshader")
	_mat.set_shader_parameter("wetness", float(get_meta("wet", 0.0)))
	_mat.set_shader_parameter("fade_end", FADE_END)
	for mesh in chunks:
		var mi := MeshInstance3D.new()
		mi.name = "Leaves"
		mi.mesh = mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := mesh.get_aabb()
		mi.visibility_range_end = FADE_END + box.size.length() * 0.5 + 5.0
		add_child(mi)
	_p.resize(MAX_CARS)
	_v.resize(MAX_CARS)
	set_process(true)
	if OS.get_cmdline_user_args().has("--debug-leaves"):
		print("RoadLeaves: %d leaves" % count)


func _leaf(st: SurfaceTool, c: Vector3, rng: RandomNumberGenerator) -> void:
	var size := rng.randf_range(0.07, 0.14)
	var a := rng.randf() * TAU
	var u := Vector3(cos(a), 0, sin(a)) * size * 0.55
	var v := Vector3(-sin(a), 0, cos(a)) * size
	var col: Color = COLOURS[rng.randi() % COLOURS.size()] * rng.randf_range(0.8, 1.15)
	col.a = rng.randf()
	var tilt := Vector3.UP * rng.randf_range(-0.01, 0.01)
	var corners := [-u - v, u - v, u + v + tilt, -u + v + tilt]
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for k in [0, 2, 1, 0, 3, 2]:
		var o: Vector3 = corners[k]
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(o.x, o.z))
		st.add_vertex(c + o)


func _process(dt: float) -> void:
	_scan_t -= dt
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_cars = []
		var root := get_tree().current_scene
		if root and "entries" in root: # the race: its entries hold every car
			for e in root.entries:
				if e.car:
					_cars.append(e.car)
		elif root:
			for n in root.find_children("*", "RigidBody3D", true, false):
				if n is Car:
					_cars.append(n)
	var cam := get_viewport().get_camera_3d()
	var i := 0
	for c in _cars:
		if i >= MAX_CARS:
			break
		if not is_instance_valid(c):
			continue
		var car := c as RigidBody3D
		if cam and car.global_position.distance_squared_to(cam.global_position) > 200.0 * 200.0:
			continue
		var p := car.global_position
		var v := car.linear_velocity
		_p[i] = Vector4(p.x, p.y, p.z, 1.0)
		_v[i] = Vector4(v.x, v.y, v.z, 0.0)
		i += 1
	for k in range(i, MAX_CARS):
		_p[k] = Vector4.ZERO
	_mat.set_shader_parameter("cars_p", _p)
	_mat.set_shader_parameter("cars_v", _v)
