class_name TrackBuilder
extends RefCounted
## Generates a closed circuit from a list of control points:
## a smooth spline, the road ribbon, curbs on corners, and colliders.

const STEP := 2.0 # metres between road cross-sections
const CURB_WIDTH := 1.1
const CURB_MIN_RADIUS := 140.0 # corners tighter than this get curbs
static var GRAVEL_MAX := 12.0 # gravel trap depth on the outside of the tightest corners (0 on street circuits)
static var RAIL_GAP := 5.0 # grass between track edge and guardrail on straights
## Street circuit (def.street): no gravel traps, concrete Jersey barriers instead
## of guardrails (rail line at the usual minimum, kerb + 3 m). Set per build by configure().
static var STREET := false


static func configure(def: Dictionary) -> void:
	STREET = bool(def.get("street", false))
	GRAVEL_MAX = 0.0 if STREET else 12.0
	RAIL_GAP = 5.0 if not STREET else 3.0
const POST_SPACING := 4.0


static func make_curve(points: Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 0.5
	var n := points.size()
	for i in n + 1:
		var p: Vector3 = points[i % n]
		var prev: Vector3 = points[(i - 1 + n) % n]
		var nxt: Vector3 = points[(i + 1) % n]
		var handle := (nxt - prev) / 6.0 # Catmull-Rom through every point
		c.add_point(p, -handle, handle)
	return c


## mats: {road, curb, gravel, rail, post}. Kerb, gravel and verge get their own
## shader materials here (weather read from the road material).
static func build(parent: Node3D, curve: Curve3D, width: float, mats: Dictionary, terrain: Terrain = null) -> void:
	var length := curve.get_baked_length()
	var count := int(ceil(length / STEP))
	var centers: Array[Vector3] = []
	var rights: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var dists: Array[float] = []
	for i in count + 1:
		var d := minf(i * STEP, length)
		var off := fmod(d, length)
		var p := curve.sample_baked(off)
		var ahead := curve.sample_baked(fmod(off + 1.0, length))
		var behind := curve.sample_baked(fmod(off - 1.0 + length, length))
		var tangent := (ahead - behind).normalized()
		centers.append(p)
		var right := tangent.cross(Vector3.UP).normalized()
		rights.append(right)
		normals.append(right.cross(tangent).normalized())
		dists.append(d)
	_setup_materials(mats)

	# Road ribbon. Geometry (and so collision) is exactly the plain two-vertex
	# ribbon; per-vertex racing-line data drives the shader's rubber and skid marks.
	var wear := _line_wear(curve, width, dists, length)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	var lift := Vector3(0, 0.02, 0)
	for i in range(1, centers.size()):
		var a_l := centers[i - 1] - rights[i - 1] * half + lift
		var a_r := centers[i - 1] + rights[i - 1] * half + lift
		var b_l := centers[i] - rights[i] * half + lift
		var b_r := centers[i] + rights[i] * half + lift
		var va := dists[i - 1] / width
		var vb := dists[i] / width
		var wa: Color = wear[i - 1]
		var wb: Color = wear[i]
		for v in [[a_l, Vector2(0, va), wa, i], [b_r, Vector2(1, vb), wb, i], [a_r, Vector2(1, va), wa, i],
				[a_l, Vector2(0, va), wa, i], [b_l, Vector2(0, vb), wb, i], [b_r, Vector2(1, vb), wb, i]]:
			st.set_color(Color(v[2].r, v[2].g, v[2].b, 1.0))
			st.set_normal(normals[v[3]])
			st.set_uv(v[1])
			st.set_uv2(Vector2(v[2].a, 0.0))
			st.add_vertex(v[0])
	_add_body(parent, st, mats.road, "Road", 1.0, 0.0)

	_build_kerbs(parent, centers, rights, normals, dists, half, mats)
	_build_shoulder(parent, centers, rights, dists, half, mats, terrain)
	_build_runoff_and_barriers(parent, centers, rights, half, mats, terrain)


const TEX_DIR := "res://assets/road/"
const KERB_PROFILE: Array[Vector2] = [ # (metres out from the track edge, height above the road centre)
	Vector2(0.0, 0.02), Vector2(0.12, 0.032), Vector2(0.55, 0.048), Vector2(0.95, 0.06),
	Vector2(1.03, 0.056), Vector2(1.08, 0.04), Vector2(1.2, 0.0), Vector2(1.6, -0.12)] # outer edge ramps down to the grass
static var _detail_tex: Texture2D


static func detail_texture() -> Texture2D:
	if _detail_tex == null:
		_detail_tex = load(TEX_DIR + "road_noise.png")
	return _detail_tex


static func _setup_materials(mats: Dictionary) -> void:
	var wet := 0.0
	var snow := 0.0
	var road_alb: Texture2D = null
	var road_nor: Texture2D = null
	if mats.road is ShaderMaterial:
		var road: ShaderMaterial = mats.road
		wet = float(road.get_shader_parameter("wetness"))
		snow = float(road.get_shader_parameter("snow"))
		road_alb = road.get_shader_parameter("albedo_tex")
		road_nor = road.get_shader_parameter("normal_tex")
		# Extra maps for the road shader; it stays neutral (has_line = 0) if they're missing.
		var alb2: Texture2D = load(TEX_DIR + "asphalt_02/asphalt_02_diff_2k.jpg")
		var detail := detail_texture()
		road.set_shader_parameter("albedo2_tex", alb2 if alb2 else road_alb)
		road.set_shader_parameter("detail_tex", detail)
		road.set_shader_parameter("has_line", 1.0 if detail else 0.0)
	var kerb := ShaderMaterial.new()
	kerb.shader = load("res://shaders/road_kerb.gdshader")
	kerb.set_shader_parameter("albedo_tex", road_alb)
	kerb.set_shader_parameter("normal_tex", road_nor)
	kerb.set_shader_parameter("detail_tex", detail_texture())
	kerb.set_shader_parameter("kerb_width", CURB_WIDTH)
	var gravel := ShaderMaterial.new()
	gravel.shader = load("res://shaders/road_gravel.gdshader")
	gravel.set_shader_parameter("albedo_tex", WorldBuilder.tex("gravel_floor", "diff"))
	gravel.set_shader_parameter("normal_tex", WorldBuilder.tex("gravel_floor", "nor"))
	gravel.set_shader_parameter("rough_tex", WorldBuilder.tex("gravel_floor", "rough"))
	gravel.set_shader_parameter("albedo2_tex", load(TEX_DIR + "floor_pebbles_01/floor_pebbles_01_diff_2k.jpg"))
	gravel.set_shader_parameter("detail_tex", detail_texture())
	var verge := ShaderMaterial.new()
	verge.shader = load("res://shaders/road_shoulder.gdshader")
	var v := TEX_DIR + "gravelly_sand/gravelly_sand_%s_1k.jpg"
	verge.set_shader_parameter("dirt_tex", load(v % "diff"))
	verge.set_shader_parameter("dirt_normal", load(v % "nor"))
	verge.set_shader_parameter("detail_tex", detail_texture())
	verge.set_shader_parameter("width_m", SHOULDER_WIDTH)
	for m: ShaderMaterial in [kerb, gravel, verge]:
		m.set_shader_parameter("wetness", wet)
		m.set_shader_parameter("snow", snow)
	mats.curb = kerb
	mats.gravel = gravel
	mats.verge = verge


## Per ribbon sample: r = braking, g = corner exit, b = corner tightness,
## a = racing line position across the road (0..1).
static func _line_wear(curve: Curve3D, width: float, dists: Array[float], length: float) -> Array[Color]:
	var rl := RacingLine.new(curve, width)
	var n := rl.count()
	var out: Array[Color] = []
	for d in dists:
		var f := d / length * n
		var i := int(f) % n
		var t := f - floorf(f)
		var lat := lerpf(rl.lateral[i], rl.lateral[(i + 1) % n], t)
		var v_back := rl.speeds[(i - 5 + n) % n]
		var v_here := rl.speeds[i]
		var v_fwd := rl.speeds[(i + 5) % n]
		# Speed lost over the next ~10 m (braking) / gained over the last ~10 m (exit).
		var brake := clampf((v_here - v_fwd) / 2.2, 0.0, 1.0)
		var exit := clampf((v_here - v_back) / 2.5, 0.0, 1.0) * clampf((70.0 - v_here) / 30.0, 0.0, 1.0)
		var tight := clampf((60.0 - v_here) / 40.0, 0.0, 1.0)
		out.append(Color(brake, exit, tight, clampf(0.5 + lat / width, 0.0, 1.0)))
	# Smooth braking/exit so the streak zones fade in and out.
	var sm: Array[Color] = []
	var m := out.size()
	for i in m:
		var acc := Color(0, 0, 0, 0)
		for j in range(-4, 5):
			acc += out[clampi(i + j, 0, m - 1)]
		acc /= 9.0
		sm.append(Color(minf(acc.r * 1.4, 1.0), minf(acc.g * 1.4, 1.0), acc.b, out[i].a))
	return sm


## Kerbs on the edges of tight corners: raised, sloped strips with a rounded
## outer lip, ramped in and out at each end. Runs are cleaned of tiny gaps/stubs.
static func _build_kerbs(parent: Node3D, centers: Array[Vector3], rights: Array[Vector3], normals: Array[Vector3],
		dists: Array[float], half: float, mats: Dictionary) -> void:
	var n := centers.size()
	var on := PackedByteArray()
	on.resize(n)
	for i in range(1, n - 1):
		var t0 := (centers[i] - centers[i - 1]).normalized()
		var t1 := (centers[i + 1] - centers[i]).normalized()
		var angle := t0.angle_to(t1)
		on[i] = 1 if angle > 0.0001 and STEP / angle <= CURB_MIN_RADIUS else 0
	# Close gaps up to 3 samples, then drop runs shorter than 4 samples.
	for i in n:
		if on[i] == 0 and i > 0 and on[i - 1] == 1:
			for g in range(1, 4):
				if i + g < n and on[i + g] == 1:
					for k in range(i, i + g):
						on[k] = 1
					break
	var i0 := 0
	while i0 < n:
		if on[i0] == 0:
			i0 += 1
			continue
		var i1 := i0
		while i1 + 1 < n and on[i1 + 1] == 1:
			i1 += 1
		if i1 - i0 < 3:
			for k in range(i0, i1 + 1):
				on[k] = 0
		i0 = i1 + 1
	# Ramp factor: 0 at a run's ends, 1 two samples in.
	var ramp := PackedFloat32Array()
	ramp.resize(n)
	for i in n:
		if on[i] == 0:
			continue
		var to_start := 0
		while i - to_start - 1 >= 0 and on[i - to_start - 1] == 1 and to_start < 2:
			to_start += 1
		var to_end := 0
		while i + to_end + 1 < n and on[i + to_end + 1] == 1 and to_end < 2:
			to_end += 1
		ramp[i] = minf(to_start, to_end) / 2.0

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pc := KERB_PROFILE.size()
	for side: float in [-1.0, 1.0]:
		for i in range(1, n):
			if on[i] == 0 or on[i - 1] == 0:
				continue
			var ring := []
			for s in [i - 1, i]:
				var pts := []
				for j in pc:
					var pr := KERB_PROFILE[j]
					var h := pr.y if pr.y < 0.0 else lerpf(0.02, pr.y, ramp[s])
					pts.append(centers[s] + rights[s] * side * (half + pr.x) + Vector3.UP * h)
				ring.append(pts)
			for j in pc - 1:
				var u0 := KERB_PROFILE[j].x / CURB_WIDTH
				var u1 := KERB_PROFILE[j + 1].x / CURB_WIDTH
				var nrm := _profile_normal(rights[i] * side, normals[i], KERB_PROFILE[j], KERB_PROFILE[j + 1])
				var a: Vector3 = ring[0][j]
				var b: Vector3 = ring[0][j + 1]
				var c: Vector3 = ring[1][j + 1]
				var d: Vector3 = ring[1][j]
				var ua := Vector2(u0, dists[i - 1])
				var ub := Vector2(u1, dists[i - 1])
				var uc := Vector2(u1, dists[i])
				var ud := Vector2(u0, dists[i])
				_quad(st, a, b, c, d, ua, ub, uc, ud, Color.WHITE, nrm)
	_add_body(parent, st, mats.curb, "Curbs", 0.95, 0.0)


static func _profile_normal(out_dir: Vector3, up: Vector3, p0: Vector2, p1: Vector2) -> Vector3:
	var slope := (p1.y - p0.y) / maxf(p1.x - p0.x, 0.001)
	return (up - out_dir * slope).normalized()


const SHOULDER_WIDTH := 1.6

## Visual-only dirt verge from under the road edge down to the grass, fading out.
static func _build_shoulder(parent: Node3D, centers: Array[Vector3], rights: Array[Vector3], dists: Array[float],
		half: float, mats: Dictionary, terrain: Terrain) -> void:
	var prof := [-0.2, 0.0, 0.35, 0.8, 1.2, SHOULDER_WIDTH]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := centers.size()
	for side: float in [-1.0, 1.0]:
		var prev := []
		for i in n:
			var ring := []
			# On the inside of a tight corner the offset edge would run backwards and
			# fold the strip over the road (very visible once snow turns it white):
			# hold such points where they were, so the strip pinches instead.
			var tan := centers[(i + 1) % n] - centers[(i - 1 + n) % n]
			tan.y = 0.0
			tan = tan.normalized()
			for j in prof.size():
				var x: float = prof[j]
				var p := centers[i] + rights[i] * side * (half + x)
				if i > 0:
					var last: Vector3 = prev[j]
					if Vector2(p.x - last.x, p.z - last.z).dot(Vector2(tan.x, tan.z)) < 0.05:
						p.x = last.x
						p.z = last.z
				var ground := (terrain.height_at(p.x, p.z) if terrain else centers[i].y - 0.12) + 0.035
				var road_y := centers[i].y + 0.012
				var t := smoothstep(0.0, SHOULDER_WIDTH, maxf(x, 0.0))
				p.y = lerpf(road_y, maxf(ground, road_y - 0.3), t)
				ring.append(p)
			if i > 0:
				for j in prof.size() - 1:
					var a: Vector3 = prev[j]
					var b: Vector3 = prev[j + 1]
					var c: Vector3 = ring[j + 1]
					var d: Vector3 = ring[j]
					var ua := Vector2(prof[j], dists[i - 1])
					var ub := Vector2(prof[j + 1], dists[i - 1])
					var uc := Vector2(prof[j + 1], dists[i])
					var ud := Vector2(prof[j], dists[i])
					_quad(st, a, b, c, d, ua, ub, uc, ud, Color.WHITE, Vector3.UP)
			prev = ring
	# Solid, not just painted: the strip is the ramp from the grass (a little
	# below the road) back up onto the tarmac, so a wheel never meets a ledge.
	_add_body(parent, st, mats.verge, "Verge", 0.78, 0.02)
	var verge := parent.get_node_or_null("Verge")
	if verge:
		for c in verge.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, col: Color, normal := Vector3.UP,
		u2a := Vector2.ZERO, u2b := Vector2.ZERO, u2c := Vector2.ZERO, u2d := Vector2.ZERO) -> void:
	# Godot treats clockwise (seen from the front) as front-facing; flip the order
	# when needed so the front always faces up (matters for double-sided shading).
	var order := [[a, ua, u2a], [c, uc, u2c], [b, ub, u2b], [a, ua, u2a], [d, ud, u2d], [c, uc, u2c]]
	if (b - a).cross(c - a).y < 0.0:
		order = [[a, ua, u2a], [b, ub, u2b], [c, uc, u2c], [a, ua, u2a], [c, uc, u2c], [d, ud, u2d]]
	for v in order:
		st.set_color(col)
		st.set_normal(normal)
		st.set_uv(v[1])
		st.set_uv2(v[2])
		st.add_vertex(v[0])


static func _add_body(parent: Node3D, st: SurfaceTool, mat: Material, node_name: String, grip: float, drag: float) -> void:
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = node_name
	body.set_meta("grip", grip)
	body.set_meta("drag", drag)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)


## Signed corner strength per sample: >0 turning left, <0 turning right,
## magnitude 0..1 (1 = tight hairpin). Smoothed so run-off areas blend in.
static func _corner_factors(centers: Array[Vector3]) -> Array[float]:
	var n := centers.size()
	var raw: Array[float] = []
	raw.resize(n)
	for i in n:
		var a := centers[(i - 4 + n) % n]
		var b := centers[i]
		var c := centers[(i + 4) % n]
		var t0 := (b - a).normalized()
		var t1 := (c - b).normalized()
		var angle := t0.signed_angle_to(t1, Vector3.UP)
		var radius := (a.distance_to(b) + b.distance_to(c)) * 0.5 / maxf(absf(angle), 0.0001)
		raw[i] = signf(angle) * clampf(inverse_lerp(260.0, 40.0, radius), 0.0, 1.0)
	var out: Array[float] = []
	out.resize(n)
	var k := 18 # samples each way (~36 m) so traps start before and end after the corner
	for i in n:
		var best := 0.0
		for j in range(-k, k + 1):
			var v: float = raw[(i + j + n) % n] * (1.0 - absf(j) / float(k + 1))
			if absf(v) > absf(best):
				best = v
		out[i] = best
	return out


static func _build_runoff_and_barriers(parent: Node3D, centers: Array[Vector3], rights: Array[Vector3], half: float, mats: Dictionary, terrain: Terrain = null) -> void:
	var corner := _corner_factors(centers)
	var n := centers.size()
	var inner_edge := half + CURB_WIDTH
	var gravel := SurfaceTool.new() # visual: lipped trap + scattered apron
	gravel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rail_lines := {1.0: [], -1.0: []}
	var last_ring := {1.0: null, -1.0: null} # previous gravel cross-section per side
	# (metres from the inner edge as a fraction of depth or absolute, height, UV2.x)
	for i in n:
		for side: float in [1.0, -1.0]:
			# Outside of a left turn is the right side (+1).
			var outside := corner[i] * side > 0.0
			var depth := GRAVEL_MAX * absf(corner[i]) if outside else 0.0
			var rp := centers[i] + rights[i] * side * (inner_edge + maxf(RAIL_GAP, depth + 3.0))
			if terrain:
				rp.y = terrain.height_at(rp.x, rp.z) # rails stand on the ground
				if rp.y < centers[i].y - 3.0: # over a gorge / under-bridge dip: stay at deck level
					rp.y = centers[i].y - 0.1
			rail_lines[side].append(rp)
			if i == 0:
				continue
			var prev_outside := corner[i - 1] * side > 0.0
			var prev_depth := GRAVEL_MAX * absf(corner[i - 1]) if prev_outside else 0.0
			if depth < 0.3 and prev_depth < 0.3:
				last_ring[side] = null
				continue
			var ra: Array = last_ring[side] if last_ring[side] != null else _gravel_ring(centers[i - 1], rights[i - 1], side, inner_edge, prev_depth, terrain)
			var rb := _gravel_ring(centers[i], rights[i], side, inner_edge, depth, terrain)
			# Where corners change direction a deep trap's outer edge can run backwards
			# and fold across the road (a white sheet in snow): hold those points.
			var tan := centers[i] - centers[i - 1]
			for j in rb.size():
				var pa: Vector3 = ra[j][0]
				var pb: Vector3 = rb[j][0]
				if Vector2(pb.x - pa.x, pb.z - pa.z).dot(Vector2(tan.x, tan.z)) < 0.05:
					rb[j][0] = Vector3(pa.x, pb.y, pa.z)
			last_ring[side] = rb
			var da := float(i - 1) * STEP
			var db := float(i) * STEP
			for j in ra.size() - 1:
				var pa: Array = ra[j]
				var pb: Array = ra[j + 1]
				var pc: Array = rb[j + 1]
				var pd: Array = rb[j]
				_quad(gravel, pa[0], pb[0], pc[0], pd[0], Vector2(pa[1], da), Vector2(pb[1], da),
					Vector2(pc[1], db), Vector2(pd[1], db), Color.WHITE, Vector3.UP,
					Vector2(pa[2], 0), Vector2(pb[2], 0), Vector2(pc[2], 0), Vector2(pd[2], 0))
	var gmesh := gravel.commit()
	if gmesh.get_surface_count() > 0:
		var body := StaticBody3D.new()
		body.name = "Gravel"
		body.set_meta("grip", 0.62)
		body.set_meta("drag", 0.07)
		var mi := MeshInstance3D.new()
		mi.mesh = gmesh
		mi.material_override = mats.gravel
		body.add_child(mi)
		# Collide with the real trap shape: sloped lips at both edges, so a car
		# can climb out onto the grass or back onto the track (a flat sheet at
		# road height left a step down to the grass).
		var shape := gmesh.create_trimesh_shape()
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		parent.add_child(body)
	for side in rail_lines:
		_build_rail(parent, rail_lines[side], side, mats)


## Cross-section of a gravel trap at one sample: [position, metres from inner edge, UV2.x].
## Sloped inner lip, flat bed, then a lip down to the grass and a scattered apron.
static func _gravel_ring(c: Vector3, r: Vector3, side: float, inner: float, depth: float, terrain: Terrain) -> Array:
	var d := maxf(depth, 0.01)
	var apron := 1.8 * clampf(depth / 3.0, 0.0, 1.0)
	var bed := c.y + 0.03
	var out := []
	for e in [[-0.15, -0.05, 0.0], [0.35, 0.0, 0.0], [d * 0.5, 0.01, 0.0], [d, 0.0, 0.0],
			[d + 0.9, -1.0, 0.0], [d + maxf(apron, 1.2), -1.0, 0.0]]:
		var x: float = e[0]
		var p := c + r * side * (inner + x)
		var ground := (terrain.height_at(p.x, p.z) if terrain else c.y - 0.12) + 0.03
		p.y = ground if e[1] < -0.5 else bed + e[1]
		if e[1] < -0.5:
			p.y = minf(p.y, bed)
		out.append([p, x, x / d if x <= d else 1.0 + (x - d) / maxf(apron, 0.01) + 0.001])
	return out


## Galvanised W-beam guardrail on posts, with a simple wall collider.
static func _build_rail(parent: Node3D, line: Array, side: float, mats: Dictionary) -> void:
	# Cross-section of the beam: (outward offset, height)
	var profile: Array[Vector2] = [Vector2(0.0, 0.42), Vector2(0.06, 0.5), Vector2(0.0, 0.58),
		Vector2(0.06, 0.66), Vector2(0.0, 0.74)]
	if STREET: # Jersey barrier (New Jersey profile), solid concrete
		profile = [Vector2(0.0, -0.1), Vector2(0.0, 0.08), Vector2(0.16, 0.33), Vector2(0.22, 0.95),
			Vector2(0.38, 0.95), Vector2(0.44, 0.33), Vector2(0.6, 0.08), Vector2(0.6, -0.1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := PackedVector3Array()
	var posts: Array[Transform3D] = []
	var since_post := POST_SPACING
	var n := line.size()
	for i in n:
		var p: Vector3 = line[i]
		var q: Vector3 = line[(i + 1) % n]
		var seg := q - p
		var seg_len := seg.length()
		if seg_len < 0.01:
			continue
		var fwd := seg / seg_len
		var out_p := fwd.cross(Vector3.UP) * side # away from the track
		var nxt: Vector3 = line[(i + 2) % n]
		var fwd_q := (nxt - q).normalized()
		var out_q := fwd_q.cross(Vector3.UP) * side
		for j in profile.size() - 1:
			var a := p + out_p * profile[j].x + Vector3.UP * profile[j].y
			var b := p + out_p * profile[j + 1].x + Vector3.UP * profile[j + 1].y
			var c := q + out_q * profile[j + 1].x + Vector3.UP * profile[j + 1].y
			var d := q + out_q * profile[j].x + Vector3.UP * profile[j].y
			for v in [a, b, c, a, c, d]:
				st.add_vertex(v)
		for v in [p, p + Vector3.UP, q + Vector3.UP, p, q + Vector3.UP, q]:
			wall.append(v)
		since_post += seg_len
		if since_post >= POST_SPACING and not STREET:
			since_post = 0.0
			posts.append(Transform3D(Basis.looking_at(fwd, Vector3.UP), p + out_p * 0.12 + Vector3.UP * 0.35))
	st.generate_normals()

	var body := StaticBody3D.new()
	body.name = "Guardrail"
	var slick := PhysicsMaterial.new()
	slick.friction = 0.05
	slick.bounce = 0.0
	body.physics_material_override = slick
	body.set_meta("grip", 0.3)
	body.set_meta("drag", 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Mats.mat("concrete_tint", Color(0.86, 0.86, 0.84)) if STREET else mats.rail
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(wall)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.1, 0.7, 0.14)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post_mesh
	mm.instance_count = posts.size()
	for i in posts.size():
		mm.set_instance_transform(i, posts[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mats.post
	parent.add_child(mmi)
