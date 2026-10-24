class_name GxSkiLift
extends Node3D
## A fixed-grip double chairlift (Doppelsessellift) climbing the mountain and
## swinging OVER the circuit: tubular steel towers with sheave trains, a
## concrete-and-timber valley and summit station with the bullwheels under a
## snow-loaded steel canopy, and two-seater chairs that really move (up one
## side, down the other, round the bullwheels) with a gentle swing.
##
##   GxSkiLift.line(c, Vector3(-260, 0, 40), Vector3(-40, 0, -330), {})
##
## Towers are slid along the line until they are off the road (edge + 8 m);
## where the line crosses the road the towers are made tall enough that the
## chairs clear the tarmac by >= 7 m. Chairs: one MultiMesh, moved by this
## node's _process (cheap: ~40 transforms). Steel, stations and cable are
## merged meshes (GxGeo). opts: speed (m/s, 2.3), chairs (spacing m, 22),
## tower_gap (m, 55), vis (m, 1200).

const GAUGE := 2.4 ## half distance between the up and down cable
const DROP := 2.6 ## grip to seat height
var path: PackedVector3Array ## closed loop of the hauling cable (world)
var cum: PackedFloat32Array
var total := 0.0
var speed := 2.3
var mm: MultiMesh
var _t := 0.0


static func line(c: Node3D, a: Vector3, b: Vector3, opts := {}) -> void:
	var d := b - a
	d.y = 0.0
	var total_len := d.length()
	var dir := d / total_len
	var side := dir.cross(Vector3.UP).normalized() # right of uphill
	var gap: float = opts.get("tower_gap", 55.0)
	# ---- tower stations along the line (stations at both ends) ----
	var stations: Array = [] # [pos on ground, cable height above that ground]
	var n := int(ceil(total_len / gap))
	for i in n + 1:
		var want := total_len * i / n
		var p := a + dir * want
		if i > 0 and i < n:
			for nudge: float in [0.0, 8.0, -8.0, 16.0, -16.0, 24.0, -24.0]:
				var q := a + dir * (want + nudge)
				if Gx.clear_of_road(c, q, 8.0) and Gx.clear_of_road(c, q + side * GAUGE, 8.0) and Gx.clear_of_road(c, q - side * GAUGE, 8.0):
					p = q
					break
		p.y = Gx.ground(c, p)
		stations.append([p, 9.0 if i > 0 and i < n else 5.2])
	# raise towers either side of every road crossing so chairs clear the road
	var road_y := func(p: Vector3) -> float:
		return Gx.curve(c).get_closest_point(p).y
	for i in stations.size() - 1:
		var p0: Vector3 = stations[i][0]
		var p1: Vector3 = stations[i + 1][0]
		for k in 41:
			var t := k / 40.0
			var q := p0.lerp(p1, t)
			if Gx.clear_of_road(c, q, 2.0) and Gx.clear_of_road(c, q + side * GAUGE, 2.0) and Gx.clear_of_road(c, q - side * GAUGE, 2.0):
				continue
			var cy := lerpf(p0.y + stations[i][1], p1.y + stations[i + 1][1], t) - 1.0 * 4.0 * t * (1.0 - t)
			var need: float = road_y.call(q) + 7.0 + DROP + 0.5
			if cy < need:
				var lift := need - cy + 0.5
				if i > 0:
					stations[i][1] = float(stations[i][1]) + lift
				if i + 1 < stations.size() - 1:
					stations[i + 1][1] = float(stations[i + 1][1]) + lift
	var g := GxGeo.new()
	var cable := GxGeo.new()
	var tops: Array[Vector3] = []
	for i in stations.size():
		var p: Vector3 = stations[i][0]
		var h: float = stations[i][1]
		tops.append(p + Vector3.UP * h)
		var xf := Transform3D(Basis(side, Vector3.UP, -dir), p) # x across the line, -z uphill
		g.xf = xf
		if i == 0 or i == stations.size() - 1:
			_station(g, h, i == 0)
			Gx.reserve(c, p, 14.0)
		else:
			_tower(g, h)
			Gx.reserve(c, p, 5.0)
	# ---- hauling-cable loop: up on the right, round the top wheel, down on the left ----
	var loop := PackedVector3Array()
	for i in tops.size() - 1:
		for k in 12:
			var t := k / 12.0
			loop.append(tops[i].lerp(tops[i + 1], t) - Vector3.UP * 0.8 * 4.0 * t * (1.0 - t) + side * GAUGE)
	for k in 9: # top bullwheel
		var ang := PI * k / 8.0
		loop.append(tops[-1] + side * GAUGE * cos(ang) + dir * GAUGE * sin(ang))
	for i in range(tops.size() - 1, 0, -1):
		for k in 12:
			var t := k / 12.0
			loop.append(tops[i].lerp(tops[i - 1], t) - Vector3.UP * 0.8 * 4.0 * t * (1.0 - t) - side * GAUGE)
	for k in 9: # bottom bullwheel
		var ang := PI + PI * k / 8.0
		loop.append(tops[0] + side * GAUGE * cos(ang) + dir * GAUGE * sin(ang))
	var closed := Array(loop)
	closed.append(loop[0])
	cable.col = Color(0.28, 0.29, 0.3)
	cable.tube("steel", closed, 0.03, 4, false)
	var vis: float = opts.get("vis", 1200.0)
	g.cast_shadows("steel")
	g.commit(c, "GxSkiLift", vis, false)
	cable.commit(c, "GxSkiLiftCable", vis * 0.6, false)
	# ---- the moving chairs ----
	var node = load("res://scripts/track/gimmicks/gx_skilift.gd").new()
	node.name = "GxSkiLiftChairs"
	node.speed = opts.get("speed", 2.3)
	node.path = loop
	node._measure()
	var count := int(node.total / float(opts.get("chairs", 22.0)))
	node.mm = MultiMesh.new()
	node.mm.transform_format = MultiMesh.TRANSFORM_3D
	node.mm.mesh = _chair_mesh(c)
	node.mm.instance_count = count
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = node.mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 700.0
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var bb := AABB(loop[0], Vector3.ZERO)
	for q in loop:
		bb = bb.expand(q)
	mi.custom_aabb = AABB(bb.position - Vector3(4, 5, 4), bb.size + Vector3(8, 8, 8))
	node.add_child(mi)
	if OS.get_cmdline_user_args().has("--gxdump"):
		print("GXLIFT chairs=%d total=%.0f surfaces=%d aabb=%s" % [count, node.total, node.mm.mesh.get_surface_count(), node.mm.mesh.get_aabb()])
	c.add_child(node)
	node._update()


func _measure() -> void:
	cum = PackedFloat32Array([0.0])
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		cum.append(cum[-1] + a.distance_to(b))
	total = cum[-1]


func _sample(d: float) -> Array:
	d = fposmod(d, total)
	var lo := 0
	var hi := path.size()
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if cum[m] <= d:
			lo = m
		else:
			hi = m
	var a := path[lo]
	var b := path[(lo + 1) % path.size()]
	var t := (d - cum[lo]) / maxf(cum[lo + 1] - cum[lo], 0.001)
	return [a.lerp(b, t), (b - a).normalized()]


func _physics_process(dt: float) -> void:
	_t += dt
	_update()


func _update() -> void:
	var n := mm.instance_count
	for i in n:
		var d := _t * speed + total * i / n
		var s := _sample(d)
		var p: Vector3 = s[0]
		var fwd: Vector3 = s[1]
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var swing := sin(_t * 1.3 + i * 1.7) * 0.06
		var bs := Basis(Vector3.UP.cross(fwd).normalized(), Vector3.UP, -fwd) # chair faces along travel... seat looks forward
		bs = bs.rotated(bs.x, swing)
		mm.set_instance_transform(i, Transform3D(bs, p))


## One chair (origin = cable grip, hanging down -y, facing -z = direction of travel).
static func _chair_mesh(c: Node3D) -> ArrayMesh:
	var g := GxGeo.new()
	g.col = Color(0.72, 0.74, 0.76)
	# grip + hanger
	g.box("steel", Vector3(0, -0.12, 0), Vector3(0.18, 0.24, 0.5), 0.03)
	g.tube("steel", [Vector3(0, -0.2, 0), Vector3(0, -1.9, 0), Vector3(0, -2.25, 0.18), Vector3(0, -2.35, 0.45)], 0.045, 6)
	# seat frame bar across
	g.tube("steel", [Vector3(-0.62, -2.35, 0.45), Vector3(0.62, -2.35, 0.45)], 0.04, 6)
	# seat (padded, dark blue) and back
	g.col = Color(0.09, 0.14, 0.3)
	g.box("painted_metal", Vector3(0, -2.45, 0.12), Vector3(1.24, 0.09, 0.5), 0.03)
	g.box("painted_metal", Vector3(0, -2.08, 0.4), Vector3(1.24, 0.62, 0.07), 0.025, Basis(Vector3.RIGHT, -0.18))
	g.col = Color(0.72, 0.74, 0.76)
	# armrests + safety bar with footrest
	for sx: float in [-0.64, 0.64]:
		g.tube("steel", [Vector3(sx, -2.4, 0.42), Vector3(sx, -2.15, 0.35), Vector3(sx, -2.15, -0.05)], 0.025, 5)
	g.tube("steel", [Vector3(-0.64, -1.62, 0.35), Vector3(-0.64, -1.7, -0.35), Vector3(0.64, -1.7, -0.35), Vector3(0.64, -1.62, 0.35)], 0.025, 5)
	g.tube("steel", [Vector3(0, -1.7, -0.35), Vector3(0, -2.6, -0.42), Vector3(0, -2.85, -0.3)], 0.025, 5)
	g.box("steel", Vector3(0, -2.86, -0.22), Vector3(0.7, 0.03, 0.22))
	# snow on the seat
	g.col = Color(0.92, 0.94, 0.97)
	g.box("plaster", Vector3(0, -2.39, 0.12), Vector3(1.1, 0.04, 0.42), 0.02)
	# GxGeo commits to nodes; build the arrays by hand into one mesh
	var holder := Node3D.new()
	var root: Node = g.commit(holder, "chair", 0.0, false)
	var am := ArrayMesh.new()
	for mi: Node in root.get_children():
		if mi is MeshInstance3D:
			var m: Mesh = (mi as MeshInstance3D).mesh
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
			am.surface_set_material(am.get_surface_count() - 1, (mi as MeshInstance3D).material_override)
	holder.free()
	return am


## A line tower in the GxGeo's frame (x across the line, -z uphill): tapered
## tube, crossbeam, sheave trains on both sides, maintenance ladder + platform.
static func _tower(g: GxGeo, h: float) -> void:
	g.col = Color(0.74, 0.76, 0.78)
	g.box("concrete", Vector3(0, 0.1, 0), Vector3(1.8, 0.8, 1.8), 0.08)
	g.tube("steel", [Vector3(0, 0.4, 0), Vector3(0, h - 0.6, 0)], 0.3, 10, true, [0.36, 0.26])
	# crossbeam (box section) with the two sheave trains
	g.box("painted_metal", Vector3(0, h - 0.3, 0), Vector3(GAUGE * 2.0 + 1.0, 0.45, 0.45), 0.04)
	for sx: float in [-GAUGE, GAUGE]:
		g.col = Color(0.62, 0.64, 0.66)
		g.box("steel", Vector3(sx, h - 0.05, 0), Vector3(0.18, 0.18, 3.0), 0.03) # rocker beam
		for k in 4:
			var z := -1.2 + k * 0.8
			g.tube("rubber", [Vector3(sx - 0.07, h + 0.12, z), Vector3(sx + 0.07, h + 0.12, z)], 0.2, 10)
		g.col = Color(0.74, 0.76, 0.78)
	# ladder up the tube + top platform with railing
	for sx: float in [-0.22, 0.22]:
		g.bar("steel", Vector3(sx, 1.2, 0.42), Vector3(sx, h - 0.6, 0.32), 0.02, 4)
	var rungs := int((h - 1.8) / 0.4)
	for k in rungs:
		var y := 1.4 + k * 0.4
		var z := lerpf(0.42, 0.32, (y - 1.2) / (h - 1.8))
		g.bar("steel", Vector3(-0.22, y, z), Vector3(0.22, y, z), 0.015, 4)
	g.box("steel", Vector3(0, h - 0.62, 0.55), Vector3(GAUGE * 2.0, 0.05, 0.6))
	g.bar("steel", Vector3(-GAUGE, h + 0.4, 0.85), Vector3(GAUGE, h + 0.4, 0.85), 0.025, 4)
	# snow cap on the crossbeam
	g.col = Color(0.93, 0.95, 0.98)
	g.box("plaster", Vector3(0, h - 0.04, 0), Vector3(GAUGE * 2.0 + 0.9, 0.1, 0.42), 0.04)
	g.collide(Vector3(0, h * 0.5, 0), Vector3(0.8, h, 0.8))


## Valley (bottom) or summit station: concrete deck, bullwheel under a steel
## canopy with a snow-loaded roof, operator cabin with lit windows.
static func _station(g: GxGeo, h: float, bottom: bool) -> void:
	var up := -1.0 if bottom else 1.0 # towards the line
	g.col = Color(0.8, 0.79, 0.76)
	g.box("concrete", Vector3(0, 0.5, 0), Vector3(9.0, 1.2, 9.0), 0.1)
	# four steel columns + canopy
	for sx: float in [-3.8, 3.8]:
		for sz: float in [-3.6, 3.6]:
			g.col = Color(0.34, 0.12, 0.1)
			g.box("painted_metal", Vector3(sx, 1.1 + h * 0.5, sz), Vector3(0.3, h + 0.6, 0.3), 0.03)
	g.box("painted_metal", Vector3(0, h + 1.6, 0), Vector3(8.4, 0.5, 8.0), 0.05)
	g.col = Color(0.45, 0.46, 0.47)
	g.box("corrugated", Vector3(0, h + 2.1, 0), Vector3(9.6, 0.3, 9.2), 0.05, Basis(Vector3.RIGHT, 0.06))
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(0, h + 2.45, 0), Vector3(9.4, 0.35, 9.0), 0.15, Basis(Vector3.RIGHT, 0.06)) # snow load
	# bullwheel (horizontal) on its drive housing
	g.col = Color(0.7, 0.72, 0.74)
	g.box("painted_metal", Vector3(0, h + 0.6, 0), Vector3(1.4, 1.6, 1.4), 0.08)
	var rim := PackedVector2Array([Vector2(GAUGE - 0.12, -0.18), Vector2(GAUGE + 0.08, -0.12), Vector2(GAUGE + 0.08, 0.12), Vector2(GAUGE - 0.12, 0.18)])
	g.col = Color(0.18, 0.2, 0.22)
	g.lathe("steel", Vector3(0, h, 0), rim, 28)
	g.col = Color(0.7, 0.72, 0.74)
	for k in 6:
		var a := TAU * k / 6.0
		g.beam("steel", Vector3(0, h, 0), Vector3(cos(a) * (GAUGE - 0.1), h, sin(a) * (GAUGE - 0.1)), 0.12)
	# loading ramp / boards
	g.col = Color(0.55, 0.42, 0.3)
	g.box("wood", Vector3(0, 1.2, up * 2.5), Vector3(5.5, 0.15, 3.0), 0.03)
	# operator cabin beside it: timber with big windows
	var cx := -6.8
	g.col = Color(0.62, 0.48, 0.34)
	g.box("wood", Vector3(cx, 2.4, 0), Vector3(3.2, 3.2, 3.6), 0.05)
	g.col = Color(0.15, 0.17, 0.2)
	g.box("glass", Vector3(cx + 1.62, 2.8, 0), Vector3(0.05, 1.3, 2.6))
	g.box("glass", Vector3(cx, 2.8, up * 1.82), Vector3(2.4, 1.3, 0.05))
	g.col = Color(0.3, 0.3, 0.32)
	g.box("corrugated", Vector3(cx, 4.15, 0), Vector3(3.8, 0.2, 4.2), 0.03)
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(cx, 4.38, 0), Vector3(3.7, 0.28, 4.1), 0.12)
	g.collide(Vector3(0, 0.5, 0), Vector3(9.0, 1.2, 9.0))
	g.collide(Vector3(cx, 2.4, 0), Vector3(3.2, 3.2, 3.6))
