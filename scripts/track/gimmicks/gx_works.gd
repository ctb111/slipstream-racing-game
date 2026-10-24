class_name GxWorks
extends RefCounted
## Roadworks beside the track: a row of traffic cones and water-filled barriers
## with blinking amber lamps, a "BAUSTELLE" sign, temporary mesh fencing on
## concrete feet, a parked excavator (or road roller), a site cabin, a gravel
## heap, concrete pipes, cement bags on pallets and a lighting tower.
##
##   GxWorks.place(c, Gx.frame(c, 1100.0, Gx.LEFT, 3.0), {width = 40})
##
## width: metres along the track (default 40). machine: "excavator" (default)
## | "roller" | "both". Frame from Gx.frame: -z faces the road; the cones stand
## at z = 0.6 (keep lateral >= 3 so they are beyond the rail line on straights
## when lateral >= 6.5; with less they sit between rail and kerb, which is fine
## on a straight without a rail). Depth ~16 m. Lamps blink (shader, no lights).

static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var W := float(opts.get("width", 40.0))
	var machine := str(opts.get("machine", "excavator"))
	var holder := Node3D.new()
	holder.name = "GxWorks"
	c.add_child(holder)
	var rng := Gx.rng(c, "works%d" % int(xf.origin.x * 5.0 + xf.origin.z))
	var g := GxGeo.new(xf)
	var labels: Array = []
	var gy := func(x: float, z: float) -> float:
		var w := xf * Vector3(x, 0, z)
		return Gx.ground(c, w) - xf.origin.y
	var body := StaticBody3D.new()
	body.name = "GxWorksCol"
	holder.add_child(body)
	var ob := xf.basis.orthonormalized()
	var col := func(cen: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(ob, xf * cen)
		body.add_child(cs)
	# compacted gravel ground for the site
	g.col = Color(0.7, 0.66, 0.6)
	for i in int(W / 10.0):
		var x := -W * 0.5 + 5.0 + i * 10.0
		g.box("concrete_tint", Vector3(x, gy.call(x, 9.0) - 0.42, 9.0), Vector3(10.05, 0.9, 15.0))
	# cones along the front, every 2.5 m
	var nc := int(W / 2.5)
	for i in nc + 1:
		var x := -W * 0.5 + i * W / nc
		_cone(g, Vector3(x, gy.call(x, 0.6), 0.6))
	# water-filled barriers (red/white) with blinking lamps, behind the cones
	var nb := int(W / 2.0)
	for i in nb:
		var x := -W * 0.5 + 1.0 + i * 2.0
		var y: float = gy.call(x, 2.0)
		g.col = Color(0.75, 0.1, 0.06) if i % 2 == 0 else Color(0.9, 0.9, 0.88)
		g.extrude_xf("painted_metal", PackedVector2Array([Vector2(-0.25, 0.0), Vector2(0.25, 0.0), Vector2(0.22, 0.25), Vector2(0.1, 0.95), Vector2(-0.1, 0.95), Vector2(-0.22, 0.25)]),
			-0.97, 0.97, Transform3D(Basis(), Vector3(x, y, 2.0)), 0.04)
		if i % 2 == 0:
			g.col = Color(0.1, 0.1, 0.1)
			g.bar("steel", Vector3(x, y + 0.95, 2.0), Vector3(x, y + 1.15, 2.0), 0.015, 4)
			g.col = Color(rng.randf(), 0, 0) # blink phase
			g.box("amber_flash", Vector3(x, y + 1.24, 2.0), Vector3(0.2, 0.2, 0.08), 0.03)
	col.call(Vector3(0, gy.call(0.0, 2.0) + 0.5, 2.0), Vector3(W, 1.0, 0.5))
	# sign: yellow "BAUSTELLE" board on a stand
	var sx := -W * 0.5 - 1.5
	var sy: float = gy.call(sx, 1.5)
	g.col = Color(0.2, 0.2, 0.2)
	for s: float in [-0.7, 0.7]:
		g.bar("steel", Vector3(sx + s, sy, 1.5), Vector3(sx + s, sy + 2.4, 1.5), 0.03, 5)
	g.col = Color(0.95, 0.75, 0.05)
	g.box("painted_metal", Vector3(sx, sy + 1.9, 1.48), Vector3(1.8, 1.0, 0.03), 0.01)
	labels.append(["BAUSTELLE", Transform3D(Basis(Vector3.UP, PI), Vector3(sx, sy + 2.05, 1.46)), 150.0, 38, Color(0.05, 0.05, 0.05)])
	labels.append(["Ausfahrt  ⟶", Transform3D(Basis(Vector3.UP, PI), Vector3(sx, sy + 1.7, 1.46)), 120.0, 24, Color(0.05, 0.05, 0.05)])
	g.col = Color(rng.randf(), 0, 0)
	g.box("amber_flash", Vector3(sx, sy + 2.55, 1.5), Vector3(0.22, 0.22, 0.1), 0.03)
	# temporary fence (mesh panels on concrete feet) along the back
	var nf := int(W / 3.5)
	for i in nf:
		var x0 := -W * 0.5 + i * 3.5
		var x1 := x0 + 3.45
		var y0: float = gy.call(x0, 15.5)
		var y1: float = gy.call(x1, 15.5)
		g.col = Color(0.6, 0.6, 0.58)
		g.box("concrete", Vector3(x0, y0 + 0.07, 15.5), Vector3(0.65, 0.14, 0.22), 0.02)
		g.tube("steel", [Vector3(x0 + 0.05, y0 + 0.1, 15.5), Vector3(x0 + 0.05, y0 + 2.0, 15.5), Vector3(x1 - 0.05, y1 + 2.0, 15.5), Vector3(x1 - 0.05, y1 + 0.1, 15.5)], 0.02, 5, false)
		g.col = Color(1, 1, 1)
		g.quad("fence_wire", Vector3(x0 + 0.05, y0 + 0.12, 15.5), Vector3(x1 - 0.05, y1 + 0.12, 15.5), Vector3(x1 - 0.05, y1 + 1.98, 15.5), Vector3(x0 + 0.05, y0 + 1.98, 15.5))
	# machines
	var mx := rng.randf_range(-W * 0.2, W * 0.1)
	if machine == "excavator" or machine == "both":
		_excavator(g, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5) + PI * 0.5), Vector3(mx, gy.call(mx, 8.0), 8.0)), rng)
		col.call(Vector3(mx, gy.call(mx, 8.0) + 1.5, 8.0), Vector3(4.5, 3.0, 4.5))
	if machine == "roller" or machine == "both":
		var rx := mx + (9.0 if machine == "both" else 0.0)
		_roller(g, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(rx, gy.call(rx, 6.5), 6.5)))
		col.call(Vector3(rx, gy.call(rx, 6.5) + 1.2, 6.5), Vector3(4.6, 2.4, 2.2))
	# site cabin (portakabin) at one end
	var cx := W * 0.5 - 5.0
	var cy: float = gy.call(cx, 11.5)
	GxProps.container(g, Transform3D(Basis(), Vector3(cx, cy + 0.25, 11.5)), false, Color(0.88, 0.88, 0.85), 0.25)
	g.col = Color(0.45, 0.5, 0.52)
	for wx: float in [-1.6, 1.0]:
		g.box("glass", Vector3(cx + wx, cy + 1.75, 11.5 - 1.25), Vector3(1.1, 0.8, 0.04))
	g.col = Color(0.3, 0.32, 0.35)
	g.box("painted_metal", Vector3(cx + 2.3, cy + 1.3, 11.5 - 1.25), Vector3(0.9, 2.0, 0.05))
	g.col = Color(0.5, 0.5, 0.5)
	for k in 3:
		g.box("steel", Vector3(cx + 2.3, cy + 0.08 + k * 0.08, 11.5 - 1.55 - (2 - k) * 0.25), Vector3(1.0, 0.04, 0.25)) # steps
	g.col = Color(0.3, 0.3, 0.3)
	for e: float in [-2.6, 2.6]:
		g.box("concrete", Vector3(cx + e, cy + 0.12, 11.5), Vector3(0.5, 0.3, 2.4))
	col.call(Vector3(cx, cy + 1.5, 11.5), Vector3(6.1, 3.0, 2.5))
	# gravel heap, concrete pipes, cement bags on pallets
	var hx := -W * 0.5 + 6.0
	var hy: float = gy.call(hx, 10.0)
	var heap := PackedVector2Array()
	for k in 9:
		var t := float(k) / 8.0
		heap.append(Vector2(4.0 * (1.0 - t) + 0.01, 2.2 * (1.0 - (1.0 - t) * (1.0 - t)) + (0.0 if k == 0 else 0.0)))
	g.col = Color(0.78, 0.74, 0.68)
	g.lathe("rock", Vector3(hx, hy - 0.1, 10.0), heap, 18)
	g.col = Color(0.75, 0.74, 0.7)
	for k in 3:
		var pz := 5.5 + k * 1.45
		var px := hx + 6.0
		g.tube("concrete", [Vector3(px - 1.2, gy.call(px, pz) + 0.7, pz), Vector3(px + 1.2, gy.call(px, pz) + 0.7, pz)], 0.7, 14, true)
		g.col = Color(0.3, 0.3, 0.3)
		for e: float in [-1.21, 1.21]: # dark bore on the end caps
			g.box("concrete", Vector3(px + e, gy.call(px, pz) + 0.7, pz), Vector3(0.01, 0.8, 0.8), 0.0, Basis(Vector3.RIGHT, PI * 0.25))
		g.col = Color(0.75, 0.74, 0.7)
	var bags: Array = []
	for k in 2:
		var bx := cx - 5.0 - k * 1.5
		var by: float = gy.call(bx, 13.0)
		GxProps.pallet(g, Vector3(bx, by, 13.0), PI * 0.5, "wood")
		for l in 4:
			for m in 2:
				bags.append(Transform3D(ob * Basis(Vector3.UP, PI * 0.5 * (l % 2)) * Basis(Vector3.RIGHT, -PI * 0.5), xf * Vector3(bx + (m - 0.5) * 0.4 * (1 - l % 2), by + 0.24 + l * 0.18, 13.0 + (m - 0.5) * 0.4 * (l % 2))))
	# lighting tower: mast + 4 lamp heads (emissive; no real light)
	var lx := -W * 0.5 + 12.0
	var ly: float = gy.call(lx, 13.0)
	g.col = Color(0.9, 0.7, 0.08)
	g.box("painted_metal", Vector3(lx, ly + 0.7, 13.0), Vector3(2.2, 1.2, 1.3), 0.06)
	g.col = Color(0.5, 0.5, 0.5)
	g.bar("steel", Vector3(lx, ly + 1.3, 13.0), Vector3(lx, ly + 8.0, 13.0), 0.08, 8)
	g.box("steel", Vector3(lx, ly + 8.1, 13.0), Vector3(1.6, 0.1, 0.1))
	for k in 4:
		var hxk := lx - 0.6 + (k % 2) * 1.2
		var hyk := ly + 8.4 + floorf(k / 2.0) * 0.55
		g.col = Color(0.15, 0.15, 0.15)
		g.box("painted_metal", Vector3(hxk, hyk, 13.0), Vector3(0.5, 0.42, 0.22), 0.03, Basis(Vector3.RIGHT, 0.4))
		g.col = Color(1, 1, 1)
		g.box("emit" if Car.night else "emit_dim", Vector3(hxk, hyk - 0.03, 12.88), Vector3(0.42, 0.32, 0.02), 0.0, Basis(Vector3.RIGHT, 0.4))
	GxProps.commit(g, holder, "GxWorks", 700.0, true)
	GxProps.scatter(holder, "cement_bag", bags, 120.0)
	var bar_xf: Array = []
	for k in 3:
		var bx := -W * 0.5 + 18.0 + k * 1.6
		bar_xf.append(Transform3D(ob, xf * Vector3(bx, gy.call(bx, 14.2), 14.2)))
	GxProps.scatter(holder, "concrete_road_barrier", bar_xf, 200.0)
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
	for k in 3:
		Gx.reserve(c, xf * Vector3(-W * 0.33 + k * W * 0.33, 0, 9.0), maxf(W * 0.25, 9.0))


static func _cone(g: GxGeo, p: Vector3) -> void:
	# 75 cm cone: black base, orange body with two white reflective bands
	g.col = Color(0.05, 0.05, 0.05)
	g.box("rubber", p + Vector3(0, 0.02, 0), Vector3(0.4, 0.04, 0.4), 0.03)
	var bands := [[0.04, 0.17, Color(0.95, 0.35, 0.03)], [0.17, 0.27, Color(0.9, 0.9, 0.88)], [0.27, 0.42, Color(0.95, 0.35, 0.03)],
		[0.42, 0.52, Color(0.9, 0.9, 0.88)], [0.52, 0.75, Color(0.95, 0.35, 0.03)]]
	for b: Array in bands:
		var y0: float = b[0]
		var y1: float = b[1]
		g.col = b[2]
		g.lathe("painted_metal", p, PackedVector2Array([Vector2(0.15 - y0 * 0.17, y0), Vector2(0.15 - y1 * 0.17, y1)]), 10)
	g.col = Color(0.95, 0.35, 0.03)
	g.lathe("painted_metal", p, PackedVector2Array([Vector2(0.024, 0.75), Vector2(0.001, 0.76)]), 10)


## Tracked excavator (~9 m with arm folded forward), nose (arm) to local +x.
static func _excavator(g: GxGeo, xf: Transform3D, rng: RandomNumberGenerator) -> void:
	var b := xf.basis
	var o := xf.origin
	var P := func(v: Vector3) -> Vector3: return o + b * v
	var paint := Color(0.9, 0.65, 0.07)
	var prev := g.col
	# tracks: stadium profile extruded, with pads
	for s: float in [-1.0, 1.0]:
		g.col = Color(0.08, 0.08, 0.08)
		var prof := PackedVector2Array()
		for k in 8:
			var a := PI * 0.5 + PI * k / 7.0
			prof.append(Vector2(-1.55 + cos(a) * 0.45, 0.45 + sin(a) * 0.45))
		for k in 8:
			var a := -PI * 0.5 + PI * k / 7.0
			prof.append(Vector2(1.55 + cos(a) * 0.45, 0.45 + sin(a) * 0.45))
		var m := Transform3D(b * Basis(Vector3.UP, PI * 0.5), o + b * Vector3(0, 0, s * 1.15))
		g.extrude_xf("rubber", prof, -0.3, 0.3, m) # profile (z,y) = (along, up), extruded across
		g.col = Color(0.25, 0.25, 0.25)
		for k in 14:
			var px := -1.8 + k * 0.28
			g.box("steel", P.call(Vector3(px, 0.02, s * 1.15)), Vector3(0.12, 0.05, 0.62))
		g.col = paint * 0.6
		g.box("painted_metal", P.call(Vector3(0, 0.5, s * 1.15)), Vector3(3.0, 0.35, 0.5), 0.05)
	# undercarriage + slew ring
	g.col = Color(0.2, 0.2, 0.2)
	g.box("steel", P.call(Vector3(0, 0.7, 0)), Vector3(2.0, 0.4, 1.8), 0.05)
	g.lathe("steel", P.call(Vector3(0, 0.9, 0)), PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.9, 0.2)]), 16)
	# upper house + counterweight + cab
	g.col = paint
	g.box("painted_metal", P.call(Vector3(-0.4, 1.55, 0.2)), Vector3(2.9, 1.1, 2.3), 0.1)
	g.box("painted_metal", P.call(Vector3(-1.75, 1.45, 0.2)), Vector3(0.6, 1.0, 2.35), 0.25)
	g.col = Color(0.12, 0.12, 0.12)
	g.box("painted_metal", P.call(Vector3(-0.6, 2.12, 0.6)), Vector3(1.4, 0.06, 1.0)) # engine grille
	g.col = paint
	g.box("painted_metal", P.call(Vector3(0.55, 2.6, -0.6)), Vector3(1.1, 1.6, 0.95), 0.06) # cab shell
	g.col = Color(0.4, 0.45, 0.47)
	g.box("glass", P.call(Vector3(0.62, 2.75, -0.6)), Vector3(1.0, 1.2, 0.97))
	g.col = Color(0.15, 0.15, 0.15)
	g.bar("steel", P.call(Vector3(-0.9, 2.1, 1.0)), P.call(Vector3(-0.9, 2.7, 1.0)), 0.06) # exhaust
	# boom (two segments), stick, bucket: folded forward and down
	var lift := rng.randf_range(0.3, 0.6)
	var root := Vector3(0.9, 1.9, 0.25)
	var elbow := root + Vector3(cos(lift) * 3.2, sin(lift) * 3.2, 0)
	var wrist := elbow + Vector3(1.4, -2.6, 0)
	g.col = paint
	var knee := root + (elbow - root) * 0.55 + Vector3(0, 0.3, 0)
	_arm(g, P.call(root), P.call(knee), 0.42, 0.55)
	_arm(g, P.call(knee), P.call(elbow), 0.38, 0.5)
	_arm(g, P.call(elbow), P.call(wrist), 0.28, 0.4)
	# hydraulic rams: dark barrel + chrome rod
	for r: Array in [[root + Vector3(0.35, -0.45, 0.0), knee + Vector3(-0.2, -0.35, 0)], [knee + Vector3(0.1, 0.35, 0), elbow + Vector3(-0.35, 0.3, 0)],
			[elbow + Vector3(0.2, 0.25, 0), wrist + Vector3(0.35, 0.5, 0)]]:
		var a0: Vector3 = r[0]
		var a1: Vector3 = r[1]
		var mid := a0.lerp(a1, 0.55)
		g.col = paint * 0.8
		g.bar("painted_metal", P.call(a0), P.call(mid), 0.09, 8)
		g.col = Color(0.85, 0.86, 0.88)
		g.bar("steel", P.call(mid), P.call(a1), 0.05, 8)
	# handrails on the house, mirror
	g.col = Color(0.15, 0.15, 0.15)
	g.tube("steel", [P.call(Vector3(-1.6, 2.1, 1.3)), P.call(Vector3(-1.6, 2.6, 1.3)), P.call(Vector3(0.6, 2.6, 1.3)), P.call(Vector3(0.6, 2.1, 1.3))], 0.025, 5, false)
	g.bar("steel", P.call(Vector3(1.1, 3.2, -1.1)), P.call(Vector3(1.3, 3.0, -1.25)), 0.015, 4)
	# track rollers
	for s: float in [-1.0, 1.0]:
		for k in 5:
			g.col = Color(0.18, 0.18, 0.18)
			g.tube("steel", [P.call(Vector3(-1.2 + k * 0.6, 0.25, s * 1.15 - 0.33)), P.call(Vector3(-1.2 + k * 0.6, 0.25, s * 1.15 + 0.33))], 0.13, 8, true)
	g.col = Color(0.25, 0.22, 0.2)
	var bk := wrist + Vector3(0.1, -0.1, 0)
	g.box("rusty_metal", P.call(bk + Vector3(0.25, -0.15, 0)), Vector3(0.8, 0.6, 1.0), 0.08, b * Basis(Vector3.BACK, -0.6))
	for k in 5:
		g.box("steel", P.call(bk + Vector3(0.62, -0.5, -0.4 + k * 0.2)), Vector3(0.2, 0.08, 0.08), 0.0, b)
	g.col = prev


## Boom section between two points: chamfered box with side plates.
static func _arm(g: GxGeo, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var x := d / l
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	g.box("painted_metal", (a + b) * 0.5, Vector3(l + h * 0.4, h, w), minf(w, h) * 0.22, Basis(x, y, z))
	var prev := g.col
	g.col = prev * 0.85
	for s: float in [-1.0, 1.0]: # pin bosses at both ends
		g.tube("steel", [a + z * (s * w * 0.5), a + z * (s * (w * 0.5 + 0.05))], h * 0.32, 10, true)
		g.tube("steel", [b + z * (s * w * 0.5), b + z * (s * (w * 0.5 + 0.05))], h * 0.32, 10, true)
	g.col = prev


## Single-drum road roller (~4.5 m), drum to local +x.
static func _roller(g: GxGeo, xf: Transform3D) -> void:
	var b := xf.basis
	var o := xf.origin
	var P := func(v: Vector3) -> Vector3: return o + b * v
	var paint := Color(0.92, 0.75, 0.1)
	var ax := b * Vector3(0, 0, 1)
	g.col = Color(0.35, 0.35, 0.35)
	g.tube("steel", [P.call(Vector3(1.45, 0.75, -1.05)), P.call(Vector3(1.45, 0.75, 1.05))], 0.75, 18, true)
	g.col = paint
	g.box("painted_metal", P.call(Vector3(1.45, 1.0, 0)), Vector3(1.0, 0.9, 2.3), 0.08) # drum frame
	g.box("painted_metal", P.call(Vector3(-0.8, 1.15, 0)), Vector3(2.4, 1.2, 1.9), 0.12) # engine body
	for s: float in [-1.0, 1.0]:
		GxProps._wheel(g, P.call(Vector3(-0.9, 0.6, s * 0.95)), ax, 0.6, 0.5, "", Color(0.6, 0.5, 0.1))
	g.col = Color(0.12, 0.12, 0.12)
	for px: float in [-0.2, 0.9]:
		for pz: float in [-0.8, 0.8]:
			g.box("painted_metal", P.call(Vector3(px, 2.35, pz)), Vector3(0.06, 1.2, 0.06))
	g.col = paint
	g.box("painted_metal", P.call(Vector3(0.35, 2.98, 0)), Vector3(1.4, 0.08, 1.8), 0.03)
	g.col = Color(0.08, 0.08, 0.08)
	g.box("rubber", P.call(Vector3(0.1, 1.9, 0)), Vector3(0.45, 0.12, 0.5), 0.03)
