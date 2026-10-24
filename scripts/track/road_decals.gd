class_name RoadDecals
extends RefCounted
## Tyre marks and road furniture laid on the tarmac, all in one mesh (one draw
## call): lock-up and trail-braking marks into the braking zones, wheelspin
## marks out of slow corners, and drain grates / manhole covers along the
## start-finish straight. Positioned on the circuit's own centreline so the
## marks agree with the rubbered line painted by the road shader.

const LIFT := 0.032 ## the road ribbon sits at +0.02
const MARK_W := 0.22
const TRACK_W := 1.52 ## distance between left and right tyre marks
const STEP := 1.0


static func build(parent: Node3D, curve: Curve3D, road_width: float, preset: Dictionary) -> void:
	var base: Curve3D = curve
	var start := 0.0
	var own = parent.get("curve")
	if own is Curve3D:
		base = own
		start = float(parent.get("start_offset"))
	var length := base.get_baked_length()
	var half := road_width * 0.5
	var line := RacingLine.new(base, road_width)
	var n := line.count()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(int(length * 10.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Braking zones: runs of samples where the line's target speed drops fast.
	var brake := PackedFloat32Array()
	brake.resize(n)
	for i in n:
		brake[i] = line.speeds[i] - line.speeds[(i + 5) % n]
	var i := 0
	var guard := 0
	while guard < n:
		guard += 1
		if brake[i % n] < 1.0:
			i += 1
			continue
		var j := i
		while brake[j % n] >= 0.6 and j - i < n:
			j += 1
		var zone_start := line.offset_of(i % n)
		var zone_len := (j - i) * length / n
		guard += j - i
		i = j + 1
		if zone_len < 10.0:
			continue
		for _k in rng.randi_range(2, 5):
			var s0 := zone_start + rng.randf_range(0.0, zone_len * 0.6)
			var mlen := rng.randf_range(12.0, minf(40.0, zone_len + 10.0))
			var lat0 := rng.randf_range(-1.3, 1.3)
			var wob := rng.randf_range(0.0, 0.18)
			var both := rng.randf() > 0.3
			var strength := rng.randf_range(0.6, 0.95)
			for side: float in ([-1.0, 1.0] if both else [-1.0 if rng.randf() < 0.5 else 1.0]):
				_mark(st, base, line, s0, mlen, lat0 + side * TRACK_W * 0.5, wob, 0.0, half, strength, rng.randf())
	# Corner exits: slowest points, marks drifting towards the outside.
	for k in n:
		var v := line.speeds[k]
		if v > 32.0 or v > line.speeds[(k - 1 + n) % n] or v > line.speeds[(k + 1) % n]:
			continue # local minima of speed only (apexes of slow corners)
		for _m in rng.randi_range(1, 3):
			var s0 := line.offset_of(k) + rng.randf_range(0.0, 10.0)
			var lat_here := line.lateral[k]
			var drift := -signf(lat_here) * rng.randf_range(0.8, 2.2) # apex is inside, exit runs out
			var strength := rng.randf_range(0.45, 0.8)
			var lat0 := rng.randf_range(-0.6, 0.6)
			for side: float in [-1.0, 1.0]:
				_mark(st, base, line, s0, rng.randf_range(10.0, 24.0), lat0 + side * TRACK_W * 0.5, 0.05, drift, half, strength, rng.randf())

	# Road furniture along the start-finish straight: drain grates by the edge,
	# a few manhole covers just past the line, clear of the grid.
	for k in 12:
		var off := start - 150.0 + k * 26.0
		var side := -1.0 if k % 2 == 0 else 1.0
		_fixture(st, base, off, side * (half - 0.75), Vector2(0.45, 0.95), 0.5, rng.randf())
	for k in 3:
		var off := start + 35.0 + k * 55.0 + rng.randf_range(-8.0, 8.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		_fixture(st, base, off, side * (half - 1.6), Vector2(0.75, 0.75), 1.0, rng.randf())

	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road_decal.gdshader")
	mat.set_shader_parameter("detail_tex", TrackBuilder.detail_texture())
	mat.set_shader_parameter("wetness", float(preset.get("wet", 0.0)))
	mat.set_shader_parameter("snow", float(preset.get("snow", 0.0)))
	var mi := MeshInstance3D.new()
	mi.name = "RoadDecals"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## One tyre mark: a strip following the lap from `s0` for `mlen` metres at a
## lateral offset from the racing line, with a lock-up wobble and a sideways drift.
static func _mark(st: SurfaceTool, curve: Curve3D, line: RacingLine, s0: float, mlen: float, lat: float,
		wobble: float, drift: float, half: float, strength: float, seed_v: float) -> void:
	var length := curve.get_baked_length()
	var steps := int(mlen / STEP)
	var prev := []
	for k in steps + 1:
		var t := float(k) / steps
		var off := fposmod(s0 + k * STEP, length)
		var idx := int(off / length * line.count()) % line.count()
		var l := line.lateral[idx] + lat + sin(t * 9.0 + seed_v * 20.0) * wobble + drift * t * t
		l = clampf(l, -half + 0.5, half - 0.5)
		var f := _frame(curve, off, length)
		var c: Vector3 = f[0] + f[1] * l + Vector3.UP * LIFT
		var ring := [c - f[1] * MARK_W * 0.5, c + f[1] * MARK_W * 0.5, t]
		if k > 0:
			var col := Color(strength, 0.0, seed_v)
			_quad(st, prev[0], prev[1], ring[1], ring[0], Vector2(0, prev[2]), Vector2(1, prev[2]),
				Vector2(1, t), Vector2(0, t), col)
		prev = ring


static func _fixture(st: SurfaceTool, curve: Curve3D, off: float, lat: float, size: Vector2, kind: float, seed_v: float) -> void:
	var length := curve.get_baked_length()
	var f := _frame(curve, fposmod(off, length), length)
	var c: Vector3 = f[0] + f[1] * lat + Vector3.UP * (LIFT + 0.002)
	var r: Vector3 = f[1] * size.x * 0.5
	var fw: Vector3 = f[2] * size.y * 0.5
	_quad(st, c - r - fw, c + r - fw, c + r + fw, c - r + fw, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
		Color(1.0, kind, seed_v))


## [centre, right, forward] on the centreline at a lap offset.
static func _frame(curve: Curve3D, off: float, length: float) -> Array:
	var p := curve.sample_baked(off)
	var ahead := curve.sample_baked(fmod(off + 1.0, length))
	var behind := curve.sample_baked(fmod(off - 1.0 + length, length))
	var fwd := (ahead - behind).normalized()
	return [p, fwd.cross(Vector3.UP).normalized(), fwd]


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color) -> void:
	var order := [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]
	if (b - a).cross(c - a).y < 0.0:
		order = [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]
	for v in order:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.set_uv(v[1])
		st.add_vertex(v[0])
