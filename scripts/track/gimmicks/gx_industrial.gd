class_name GxIndustrial
extends RefCounted
## Industrial yard beside the track: stacked shipping containers in varied
## liveries, fuel tanks in a bund, a tower crane further back, chain-link fence
## with signage along the road side, a loading dock with a trailer backed in.
##
##   GxIndustrial.place(c, Gx.frame(c, 900.0, Gx.LEFT, 8.0), {kind = "yard"})
##
## kind: "yard" (everything, default), "containers", "tanks", "dock".
## width: metres along the track (default 70), depth: away from it (default 45).
## crane: false to skip the tower crane; fence: false to skip the fence.
## Frame from Gx.frame: x along the track, +z away from the road, -z faces it.
## The fence sits at z = 0.5; keep `lateral` >= 4 so it clears the rails.

const LIVERIES := [
	[Color(0.12, 0.36, 0.6), "NORDLINE"], [Color(0.55, 0.16, 0.1), "HANSA CARGO"],
	[Color(0.15, 0.4, 0.22), "EVERHAVEN"], [Color(0.6, 0.6, 0.58), "TRAMONTA"],
	[Color(0.85, 0.42, 0.08), "CAPRA"], [Color(0.1, 0.45, 0.5), "OCEANIC"],
	[Color(0.45, 0.12, 0.12), "KRONEN"], [Color(0.75, 0.72, 0.66), "MERIDA LINES"],
	[Color(0.2, 0.22, 0.3), "VALTER"], [Color(0.55, 0.4, 0.15), "BALTWAVE"],
]


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind: String = str(opts.get("kind", "yard"))
	var W := float(opts.get("width", 70.0))
	var D := float(opts.get("depth", 45.0))
	var holder := Node3D.new()
	holder.name = "GxIndustrial_" + kind
	c.add_child(holder)
	var rng := Gx.rng(c, "industrial%d" % int(xf.origin.x * 3.0 + xf.origin.z * 5.0))
	var g := GxGeo.new(xf)
	var labels: Array = []
	var gy := func(x: float, z: float) -> float:
		var w := xf * Vector3(x, 0, z)
		return Gx.ground(c, w) - xf.origin.y
	# concrete hard-standing so the yard is not on grass
	g.col = Color(0.75, 0.74, 0.7)
	var nx := int(W / 10.0)
	var nz := int(D / 10.0)
	for i in nx:
		for j in nz:
			var x := -W * 0.5 + (i + 0.5) * W / nx
			var z := 1.5 + (j + 0.5) * (D - 1.5) / nz
			var y: float = gy.call(x, z)
			g.box("concrete", Vector3(x, y - 0.25, z), Vector3(W / nx + 0.05, 0.6, (D - 1.5) / nz + 0.05))
	var x_cursor := -W * 0.5 + 3.0
	var parts: Array = []
	match kind:
		"containers":
			parts = ["containers"]
		"tanks":
			parts = ["tanks"]
		"dock":
			parts = ["dock"]
		_:
			parts = ["containers", "tanks", "dock"]
	var share := (W - 6.0) / parts.size()
	var body := StaticBody3D.new()
	body.name = "GxIndustrialCol"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.2
	body.physics_material_override = pm
	holder.add_child(body)
	var ob := xf.basis.orthonormalized()
	var col := func(cen: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(ob, xf * cen)
		body.add_child(cs)
	for part: String in parts:
		var x0 := x_cursor
		var x1 := x_cursor + share
		match part:
			"containers":
				_containers(g, rng, x0, x1, 5.0, D - 3.0, gy, labels, col)
			"tanks":
				_tanks(g, rng, x0, x1, 6.0, D - 3.0, gy, col)
			"dock":
				_dock(g, rng, x0, x1, 6.0, D - 3.0, gy, labels, col)
		x_cursor = x1
	if opts.get("fence", true):
		_fence(c, holder, g, xf, W, gy, rng, labels)
	if opts.get("crane", true):
		_tower_crane(g, Vector3(rng.randf_range(-W * 0.3, W * 0.3), 0, D + 12.0), gy, rng)
	GxProps.commit(g, holder, "GxInd", 1500.0, true)
	for lb: Array in labels:
		var l := Label3D.new()
		l.text = lb[0]
		l.font_size = int(lb[3])
		l.pixel_size = 0.01
		l.modulate = lb[4]
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		var t: Transform3D = lb[1]
		l.transform = Transform3D((xf.basis * t.basis).orthonormalized(), xf * t.origin)
		l.visibility_range_end = float(lb[2])
		holder.add_child(l)
	for i in 4:
		Gx.reserve(c, xf * Vector3(-W * 0.5 + W * (i + 0.5) / 4.0, 0, D * 0.5), maxf(W / 4.0, D * 0.6))


# ---------------------------------------------------------------- containers
static func _containers(g: GxGeo, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, gy: Callable, labels: Array, col: Callable) -> void:
	var z := z0 + 1.4
	while z < z1 - 1.4:
		var x := x0 + 0.5
		while x < x1 - 6.5:
			var long := rng.randf() < 0.55 and x + 12.4 < x1
			var L := 12.19 if long else 6.06
			var stack := rng.randi_range(1, 3) if z > z0 + 3.0 else rng.randi_range(1, 2)
			var y: float = gy.call(x + L * 0.5, z)
			for k in stack:
				var lv: Array = LIVERIES[rng.randi() % LIVERIES.size()]
				var paint: Color = lv[0] * rng.randf_range(0.85, 1.08)
				var yaw := rng.randf_range(-0.012, 0.012)
				var cx := x + L * 0.5 + rng.randf_range(-0.08, 0.08)
				GxProps.container(g, Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, y + k * 2.6, z)), long, paint, rng.randf_range(0.12, 0.5))
				if rng.randf() < 0.75: # livery name on the road-facing side, off-centre, faded
					var lx := cx + L * rng.randf_range(-0.18, 0.12)
					var fade := rng.randf_range(0.55, 0.85)
					labels.append([lv[1], Transform3D(Basis(Vector3.UP, PI), Vector3(lx, y + k * 2.6 + 1.55, z - 1.265)), 260.0,
						72 if long else 52, Color(0.84, 0.82, 0.76, fade).lerp(Color(0.6, 0.55, 0.48, fade), rng.randf() * 0.4)])
			col.call(Vector3(x + L * 0.5, y + stack * 1.3, z), Vector3(L, stack * 2.6, 2.44))
			x += L + rng.randf_range(0.3, 1.2)
		z += 2.44 + (rng.randf_range(0.3, 0.6) if rng.randf() < 0.6 else 4.0) # aisles for the straddle carriers


# ---------------------------------------------------------------- fuel tanks
static func _tanks(g: GxGeo, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, gy: Callable, col: Callable) -> void:
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var bw := (x1 - x0) * 0.46
	var bd := (z1 - z0) * 0.46
	var y0: float = gy.call(cx, cz)
	# bund wall
	g.col = Color(0.78, 0.77, 0.73)
	for s: float in [-1.0, 1.0]:
		g.box("concrete", Vector3(cx, y0 + 0.4, cz + s * bd), Vector3(bw * 2.0, 1.6, 0.35), 0.03)
		g.box("concrete", Vector3(cx + s * bw, y0 + 0.4, cz), Vector3(0.35, 1.6, bd * 2.0), 0.03)
	var n := 2 if bw < 14.0 else 3
	var r := minf(bw / n - 1.2, bd - 2.0)
	r = clampf(r, 3.0, 8.0)
	for i in n:
		var tx := cx - bw + (2.0 * bw) * (i + 0.5) / n
		var tz := cz + rng.randf_range(-1.0, 1.0)
		var h := rng.randf_range(7.0, 11.0)
		g.col = Color(0.86, 0.86, 0.84) if i % 2 == 0 else Color(0.72, 0.74, 0.72)
		var prof := PackedVector2Array([Vector2(r, -0.6), Vector2(r, h), Vector2(r * 0.97, h + 0.25), Vector2(r * 0.6, h + 0.9), Vector2(0.01, h + 1.25)])
		g.lathe("painted_metal", Vector3(tx, y0, tz), prof, 28)
		# weld seams (rings)
		g.col = g.col * 0.86
		for k in range(1, int(h / 2.0)):
			g.lathe("painted_metal", Vector3(tx, y0, tz), PackedVector2Array([Vector2(r + 0.02, k * 2.0 - 0.03), Vector2(r + 0.02, k * 2.0 + 0.03)]), 28)
		# roof handrail ring + spiral stair stringer
		g.col = Color(0.85, 0.7, 0.15)
		var ring := []
		for k in 21:
			var a := TAU * k / 20.0
			ring.append(Vector3(tx + cos(a) * r * 0.62, y0 + h + 1.9, tz + sin(a) * r * 0.62))
		g.tube("painted_metal", ring, 0.035, 5, false)
		for k in 8:
			var a2 := TAU * k / 8.0
			var rp := Vector3(tx + cos(a2) * r * 0.62, 0, tz + sin(a2) * r * 0.62)
			g.bar("painted_metal", rp + Vector3(0, y0 + h + 0.82, 0), rp + Vector3(0, y0 + h + 1.9, 0), 0.025, 4)
		var spiral := []
		for k in 25:
			var a := -PI * 0.5 + k / 24.0 * PI * 0.9
			spiral.append(Vector3(tx + cos(a) * (r + 0.6), y0 + 0.2 + h * k / 24.0, tz + sin(a) * (r + 0.6)))
		g.tube("painted_metal", spiral, 0.05, 5, false)
		var spiral2 := []
		for p: Vector3 in spiral:
			spiral2.append(p + Vector3(0, 1.0, 0) + (p - Vector3(tx, p.y, tz)).normalized() * 0.5)
		g.tube("painted_metal", spiral2, 0.03, 5, false)
		# pipe from the base to the manifold at the bund wall
		g.col = Color(0.3, 0.32, 0.3)
		g.tube("steel", [Vector3(tx, y0 + 0.8, tz - r), Vector3(tx, y0 + 0.8, cz - bd + 1.0), Vector3(tx, y0 + 1.8, cz - bd + 0.3), Vector3(tx, y0 + 1.8, cz - bd - 1.5)], 0.18, 10)
		col.call(Vector3(tx, y0 + h * 0.5, tz), Vector3(r * 1.7, h, r * 1.7))
	# manifold pipe rack along the front
	g.col = Color(0.35, 0.37, 0.35)
	g.tube("steel", [Vector3(cx - bw, y0 + 1.8, cz - bd - 1.5), Vector3(cx + bw, y0 + 1.8, cz - bd - 1.5)], 0.22, 10)
	for k in int(bw):
		var px := cx - bw + k * 2.0
		g.box("steel", Vector3(px, y0 + 0.85, cz - bd - 1.5), Vector3(0.15, 1.7, 0.15))
	col.call(Vector3(cx, y0 + 0.4, cz - bd), Vector3(bw * 2.0, 1.6, 0.4))


# ------------------------------------------------------------- loading dock
static func _dock(g: GxGeo, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, gy: Callable, labels: Array, col: Callable) -> void:
	var bx := (x0 + x1) * 0.5
	var bwid := x1 - x0 - 2.0
	var bz := z0 + 18.0 # front face of the building (faces the road)
	var depth := minf(z1 - bz, 22.0)
	var y0: float = gy.call(bx, bz)
	var h := 8.0
	var dock_h := 1.2
	var clad := Color(0.7, 0.71, 0.7)
	# building
	g.col = Color(0.75, 0.75, 0.72)
	g.box("concrete", Vector3(bx, y0 + dock_h * 0.5 - 0.5, bz + depth * 0.5), Vector3(bwid, dock_h + 1.0, depth))
	g.col = clad
	g.box("corrugated", Vector3(bx, y0 + dock_h + h * 0.5, bz + depth * 0.5 + 0.0), Vector3(bwid, h, depth))
	g.col = Color(0.35, 0.36, 0.38)
	g.box("painted_metal", Vector3(bx, y0 + dock_h + h + 0.2, bz + depth * 0.5), Vector3(bwid + 0.3, 0.4, depth + 0.3), 0.03)
	col.call(Vector3(bx, y0 + (h + dock_h) * 0.5, bz + depth * 0.5), Vector3(bwid, h + dock_h, depth))
	labels.append([["LOGISTIK NORD", "KRONEN SPEDITION", "HANSA CARGO", "VALTER TRANSPORT"][rng.randi() % 4],
		Transform3D(Basis(Vector3.UP, PI), Vector3(bx, y0 + dock_h + h - 1.2, bz - 0.08)), 600.0, 220, Color(0.15, 0.2, 0.4)])
	# dock doors with seals, bumpers, lamps; a trailer at one of them
	var nd := maxi(2, int(bwid / 4.5))
	var trailer_at := rng.randi() % nd
	for i in nd:
		var dx := bx - bwid * 0.5 + (i + 0.5) * bwid / nd
		g.col = Color(0.05, 0.05, 0.05)
		g.box("rubber", Vector3(dx, y0 + dock_h + 1.6, bz - 0.25), Vector3(3.4, 3.4, 0.5), 0.05) # seal
		g.col = Color(0.72, 0.74, 0.76)
		var open := rng.randf() < 0.4
		g.box("corrugated", Vector3(dx, y0 + dock_h + (2.7 if open else 1.5), bz - 0.52), Vector3(2.8, 0.4 if open else 3.0, 0.06)) # roller shutter
		if open:
			g.col = Color(0.02, 0.02, 0.02)
			g.box("rubber", Vector3(dx, y0 + dock_h + 1.25, bz - 0.5), Vector3(2.8, 2.5, 0.02))
		g.col = Color(0.08, 0.08, 0.08)
		for s: float in [-1.0, 1.0]:
			g.box("rubber", Vector3(dx + s * 1.1, y0 + dock_h - 0.25, bz - 0.12), Vector3(0.25, 0.45, 0.24), 0.04) # bumpers
		g.col = Color(0.9, 0.7, 0.05)
		g.box("painted_metal", Vector3(dx, y0 + dock_h - 0.02, bz - 0.6), Vector3(2.2, 0.04, 1.2)) # leveller lip
		if i == trailer_at:
			_trailer(g, Vector3(dx, gy.call(dx, bz - 8.0), bz - 7.8), rng)
	# canopy over the docks
	g.col = Color(0.4, 0.41, 0.42)
	g.box("painted_metal", Vector3(bx, y0 + dock_h + 4.4, bz - 1.5), Vector3(bwid, 0.25, 3.0), 0.03)


static func _trailer(g: GxGeo, back: Vector3, rng: RandomNumberGenerator) -> void:
	# box semi-trailer, 13.6 m, rear against the dock (local -z = towards road)
	var L := 13.6
	var cz := back.z - 0.0
	var paint := Color(0.85, 0.85, 0.83) if rng.randf() < 0.6 else Color(0.2, 0.3, 0.55)
	var rot := Basis(Vector3.UP, PI * 0.5) # trailer x along local z
	g.col = paint
	g.box("painted_metal", Vector3(back.x, back.y + 2.65, cz), Vector3(2.55, 2.75, L), 0.04)
	g.col = Color(0.15, 0.15, 0.15)
	g.box("steel", Vector3(back.x, back.y + 1.15, cz), Vector3(1.0, 0.3, L - 0.4))
	for k in 3: # tri-axle at the rear (+z, at the dock)
		var az := cz + L * 0.5 - 1.6 - k * 1.35
		for s: float in [-1.0, 1.0]:
			GxProps._wheel(g, Vector3(back.x + s * 0.95, back.y + 0.52, az), Vector3(1, 0, 0), 0.52, 0.55, "", Color(0.6, 0.6, 0.6))
	g.col = Color(0.5, 0.5, 0.5)
	for s: float in [-1.0, 1.0]: # landing legs
		g.box("steel", Vector3(back.x + s * 0.8, back.y + 0.65, cz - L * 0.5 + 3.0), Vector3(0.12, 1.3, 0.12))
	g.col = Color(0.75, 0.1, 0.05)
	g.box("painted_metal", Vector3(back.x, back.y + 0.9, cz + L * 0.5 - 0.1), Vector3(2.5, 0.15, 0.1)) # rear bar


# ----------------------------------------------------------------- fence
static func _fence(c: Node3D, holder: Node3D, g: GxGeo, xf: Transform3D, W: float, gy: Callable, rng: RandomNumberGenerator, labels: Array) -> void:
	# galvanised posts every 3 m, top and bottom rails, chain-link mesh (Poly Haven wire texture)
	var n := int(W / 3.0)
	var prev := Vector3.ZERO
	for i in n + 1:
		var x := -W * 0.5 + i * W / n
		var y: float = gy.call(x, 0.5)
		var p := Vector3(x, y, 0.5)
		g.col = Color(0.66, 0.68, 0.67)
		g.bar("steel", p - Vector3(0, 0.3, 0), p + Vector3(0, 2.45, 0), 0.03, 6)
		if i > 0:
			g.bar("steel", prev + Vector3(0, 2.4, 0), p + Vector3(0, 2.4, 0), 0.02, 5)
			g.bar("steel", prev + Vector3(0, 0.08, 0), p + Vector3(0, 0.08, 0), 0.012, 4)
			g.col = Color(1, 1, 1)
			g.quad("fence_wire", prev + Vector3(0, 0.05, 0.01), p + Vector3(0, 0.05, 0.01), p + Vector3(0, 2.4, 0.01), prev + Vector3(0, 2.4, 0.01))
		prev = p
	# signs on the fence
	var signs := [["PRIVATGELÄNDE", "Betreten verboten"], ["ACHTUNG", "Gabelstaplerverkehr"], ["NO ENTRY", "Authorised personnel only"], ["RAUCHEN VERBOTEN", "Feuergefahr"]]
	var nsg := maxi(2, int(W / 25.0))
	for i in nsg:
		var x := -W * 0.5 + (i + 0.5) * W / nsg + rng.randf_range(-3.0, 3.0)
		var y: float = gy.call(x, 0.5) + 1.45
		var sg: Array = signs[rng.randi() % signs.size()]
		var red := i % 2 == 0
		g.col = Color(0.92, 0.92, 0.9)
		g.box("painted_metal", Vector3(x, y, 0.42), Vector3(1.2, 0.8, 0.02))
		g.col = Color(0.7, 0.08, 0.06) if red else Color(0.9, 0.7, 0.05)
		g.box("painted_metal", Vector3(x, y + 0.28, 0.405), Vector3(1.16, 0.22, 0.01))
		labels.append([sg[0], Transform3D(Basis(Vector3.UP, PI), Vector3(x, y + 0.28, 0.398)), 120.0, 30, Color(1, 1, 1) if red else Color(0.05, 0.05, 0.05)])
		labels.append([sg[1], Transform3D(Basis(Vector3.UP, PI), Vector3(x, y - 0.08, 0.408)), 90.0, 18, Color(0.08, 0.08, 0.08)])
	# gate posts with a sliding gate pushed aside
	g.col = Color(0.85, 0.66, 0.08)
	for s: float in [-1.0, 1.0]:
		g.box("painted_metal", Vector3(s * W * 0.5, gy.call(s * W * 0.5, 0.5) + 1.3, 0.5), Vector3(0.2, 2.8, 0.2), 0.02)


# ------------------------------------------------------------- tower crane
static func _tower_crane(g: GxGeo, base: Vector3, gy: Callable, rng: RandomNumberGenerator) -> void:
	var y0: float = gy.call(base.x, base.z)
	var mast_h := rng.randf_range(38.0, 50.0)
	var m := 1.0 # half width of the lattice mast
	var paint := Color(0.88, 0.7, 0.08) if rng.randf() < 0.6 else Color(0.75, 0.15, 0.1)
	var o := Vector3(base.x, y0, base.z)
	g.col = Color(0.7, 0.7, 0.68)
	g.box("concrete", o + Vector3(0, 0.3, 0), Vector3(6.0, 1.2, 6.0), 0.05)
	g.col = paint
	var corners := [Vector3(-m, 0, -m), Vector3(m, 0, -m), Vector3(m, 0, m), Vector3(-m, 0, m)]
	for cr: Vector3 in corners:
		g.box("painted_metal", o + cr + Vector3(0, mast_h * 0.5, 0), Vector3(0.18, mast_h, 0.18))
	var seg := 2.5
	for k in int(mast_h / seg):
		var ya := k * seg
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			g.beam("painted_metal", o + a + Vector3(0, ya, 0), o + b + Vector3(0, ya + seg, 0), 0.07)
			g.beam("painted_metal", o + a + Vector3(0, ya, 0), o + b + Vector3(0, ya, 0), 0.07)
	# slewing unit, cab, jib (towards -z = over the yard, angled), counter-jib, A-frame
	var top := o + Vector3(0, mast_h, 0)
	var yaw := rng.randf_range(-1.2, 1.2) + PI * 0.5
	var jd := Vector3(cos(yaw), 0, -sin(yaw))
	var side := jd.cross(Vector3.UP).normalized()
	g.col = Color(0.25, 0.25, 0.25)
	g.box("painted_metal", top + Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 2.4), 0.05)
	g.col = Color(0.9, 0.9, 0.88)
	g.box("painted_metal", top + jd * 1.6 + side * 1.6 + Vector3(0, 1.4, 0), Vector3(1.8, 2.0, 1.6), 0.08) # cab
	var jib_len := rng.randf_range(40.0, 55.0)
	var cj := 14.0
	g.col = paint
	var jt := top + Vector3(0, 1.4, 0)
	# triangular lattice jib: two bottom chords + top chord
	var pts_b1 := [jt + side * 0.7, jt + side * 0.7 + jd * jib_len]
	var pts_b2 := [jt - side * 0.7, jt - side * 0.7 + jd * jib_len]
	var pts_t := [jt + Vector3(0, 1.4, 0), jt + Vector3(0, 0.6, 0) + jd * jib_len]
	g.beam("painted_metal", pts_b1[0], pts_b1[1], 0.14)
	g.beam("painted_metal", pts_b2[0], pts_b2[1], 0.14)
	g.beam("painted_metal", pts_t[0], pts_t[1], 0.12)
	var nj := int(jib_len / 2.5)
	for k in nj:
		var f0 := float(k) / nj
		var f1 := float(k + 1) / nj
		var b1a: Vector3 = pts_b1[0].lerp(pts_b1[1], f0)
		var b2a: Vector3 = pts_b2[0].lerp(pts_b2[1], f0)
		var ta: Vector3 = pts_t[0].lerp(pts_t[1], f0)
		var b1b: Vector3 = pts_b1[0].lerp(pts_b1[1], f1)
		var b2b: Vector3 = pts_b2[0].lerp(pts_b2[1], f1)
		g.beam("painted_metal", b1a, tb(pts_t, f1), 0.05)
		g.beam("painted_metal", b2a, tb(pts_t, f1), 0.05)
		g.beam("painted_metal", b1a, b2a, 0.05)
		g.beam("painted_metal", ta, b1b, 0.05)
		g.beam("painted_metal", ta, b2b, 0.05)
	# counter-jib with concrete blocks
	g.beam("painted_metal", jt + side * 0.7, jt + side * 0.7 - jd * cj, 0.14)
	g.beam("painted_metal", jt - side * 0.7, jt - side * 0.7 - jd * cj, 0.14)
	for k in int(cj / 2.0):
		g.beam("painted_metal", jt + side * 0.7 - jd * (k * 2.0), jt - side * 0.7 - jd * (k * 2.0 + 2.0), 0.05)
	g.col = Color(0.6, 0.6, 0.58)
	g.box("concrete", jt - jd * (cj - 1.8) + Vector3(0, -0.6, 0), Vector3(2.2, 2.4, 2.0), 0.05, Basis(Vector3.UP, yaw))
	# A-frame and pendants
	g.col = paint
	var apex := jt + Vector3(0, 7.0, 0)
	g.beam("painted_metal", jt + side * 0.7, apex, 0.12)
	g.beam("painted_metal", jt - side * 0.7, apex, 0.12)
	g.col = Color(0.2, 0.2, 0.2)
	g.bar("steel", apex, jt + Vector3(0, 0.8, 0) + jd * jib_len * 0.7, 0.03, 4)
	g.bar("steel", apex, jt - jd * cj, 0.03, 4)
	# trolley + hook line
	var tp := jt + jd * jib_len * rng.randf_range(0.35, 0.8)
	g.box("painted_metal", tp, Vector3(1.2, 0.4, 1.2))
	var hook_y := rng.randf_range(8.0, mast_h - 6.0)
	g.bar("steel", tp, Vector3(tp.x, o.y + hook_y, tp.z), 0.02, 3)
	g.col = Color(0.9, 0.7, 0.05)
	g.box("painted_metal", Vector3(tp.x, o.y + hook_y - 0.4, tp.z), Vector3(0.6, 0.8, 0.4), 0.05)


static func tb(pts: Array, f: float) -> Vector3:
	return (pts[0] as Vector3).lerp(pts[1], f)
