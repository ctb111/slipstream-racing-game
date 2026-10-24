class_name GxPylons
extends RefCounted
## A high-voltage transmission line striding across the landscape: galvanised
## lattice towers (four tapering angle-iron legs, X bracing on every face,
## three cross-arms, an earth-wire peak), porcelain insulator strings and
## sagging conductors that swing over the circuit.
##
##   GxPylons.line(c, Vector3(-150, 0, -60), Vector3(650, 0, 40), {spacing = 120.0})
##
## Towers that would land near the road are slid along the line until they
## are well clear (road edge + 14 m). Everything is merged: one mesh for the
## steel, one for the insulators, one for the wires; one collider per tower leg
## group. Wires clear the road by far more than 5.5 m.
## opts: spacing (m, 120), height (m, 36), sag (m, 6), vis (m, 1400), seed.

const STEEL := "steel"
const INSUL := "painted_metal"


static func line(c: Node3D, a: Vector3, b: Vector3, opts := {}) -> void:
	var spacing: float = opts.get("spacing", 120.0)
	var h: float = opts.get("height", 36.0)
	var sag: float = opts.get("sag", 6.0)
	var d := b - a
	d.y = 0.0
	var total := d.length()
	var dir := d / total
	# tower stations, nudged clear of the road
	var stations: Array[Vector3] = []
	var s := 0.0
	while s <= total + 0.1:
		var placed := false
		for nudge: float in [0.0, 12.0, -12.0, 24.0, -24.0, 36.0, -36.0, 48.0, -48.0]:
			var p := a + dir * (s + nudge)
			if Gx.clear_of_road(c, p, 14.0):
				p.y = _foot(c, p, dir)
				stations.append(p)
				placed = true
				break
		if not placed:
			push_warning("GxPylons: no clear spot near %s" % str(a + dir * s))
		s += spacing
	if stations.size() < 2:
		return
	var steel := GxGeo.new()
	var wires := GxGeo.new()
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP).normalized())
	var tips: Array = [] # per tower: attachment points in world space
	for p in stations:
		var xf := Transform3D(basis, p)
		steel.xf = xf
		tips.append(_tower(steel, h))
		Gx.reserve(c, p, 9.0)
	# conductors between neighbouring towers
	wires.xf = Transform3D.IDENTITY
	for i in stations.size() - 1:
		var ta: Array = tips[i]
		var tb: Array = tips[i + 1]
		for k in ta.size():
			var p0: Vector3 = stations[i] + basis * ta[k]
			var p1: Vector3 = stations[i + 1] + basis * tb[k]
			var pts := []
			var n := 18
			var sg := sag * (0.55 if k == ta.size() - 1 else 1.0) # earth wire is tighter
			for j in n + 1:
				var t := float(j) / n
				pts.append(p0.lerp(p1, t) - Vector3.UP * sg * 4.0 * t * (1.0 - t))
			wires.col = Color(0.32, 0.33, 0.34)
			wires.tube(STEEL, pts, 0.045 if k < ta.size() - 1 else 0.03, 4, false)
	steel.cast_shadows(STEEL)
	steel.commit(c, "GxPylons", float(opts.get("vis", 1400.0)), false)
	wires.commit(c, "GxPylonWires", float(opts.get("vis", 1400.0)) * 0.6, false)


## Lowest ground under the four feet, so no leg floats.
static func _foot(c: Node3D, p: Vector3, dir: Vector3) -> float:
	var side := dir.cross(Vector3.UP).normalized()
	var y := INF
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			y = minf(y, Gx.ground(c, p + dir * 4.2 * sx + side * 4.2 * sz))
	return y - 0.3


## One tower in the GxGeo's local frame (x along the line). Returns the six
## conductor attachment points + the earth-wire peak (local).
static func _tower(g: GxGeo, h: float) -> Array:
	var levels := [0.0, 0.3, 0.52, 0.66, 0.76, 0.82, 0.9, 1.0] # fractions of the body height
	var body := h * 0.88
	var hw := func(y: float) -> float: # half-width of the legs at height y
		var f := y / body
		if f < 0.72:
			return lerpf(4.2, 1.35, pow(f / 0.72, 0.8))
		return lerpf(1.35, 1.0, (f - 0.72) / 0.28)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	g.col = Color(0.78, 0.8, 0.8)
	# concrete foundations (chimneys) under each leg
	for cn: Vector2 in corners:
		g.col = Color(0.75, 0.74, 0.7)
		g.box("concrete", Vector3(cn.x * 4.2, 0.25, cn.y * 4.2), Vector3(1.1, 1.0, 1.1), 0.08)
	g.col = Color(0.8, 0.82, 0.82)
	var ys: Array[float] = []
	for f: float in levels:
		ys.append(body * f)
	# legs
	for cn: Vector2 in corners:
		for i in ys.size() - 1:
			var y0 := ys[i]
			var y1 := ys[i + 1]
			var w0: float = hw.call(y0)
			var w1: float = hw.call(y1)
			g.beam(STEEL, Vector3(cn.x * w0, y0, cn.y * w0), Vector3(cn.x * w1, y1, cn.y * w1), 0.22 if i < 3 else 0.17)
	# bracing on the four faces: horizontals + X diagonals
	for f in 4:
		var c0: Vector2 = corners[f]
		var c1: Vector2 = corners[(f + 1) % 4]
		for i in ys.size() - 1:
			var y0 := ys[i]
			var y1 := ys[i + 1]
			var w0: float = hw.call(y0)
			var w1: float = hw.call(y1)
			var a0 := Vector3(c0.x * w0, y0, c0.y * w0)
			var b0 := Vector3(c1.x * w0, y0, c1.y * w0)
			var a1 := Vector3(c0.x * w1, y1, c0.y * w1)
			var b1 := Vector3(c1.x * w1, y1, c1.y * w1)
			if i > 0:
				g.beam(STEEL, a0, b0, 0.09)
			# big lower panels get a double lattice (K bracing) so it never looks crude
			if i < 2:
				var m0 := a0.lerp(b0, 0.5)
				var m1 := a1.lerp(b1, 0.5)
				var mid := (m0 + m1) * 0.5
				g.beam(STEEL, a0, mid, 0.07)
				g.beam(STEEL, b0, mid, 0.07)
				g.beam(STEEL, mid, a1, 0.07)
				g.beam(STEEL, mid, b1, 0.07)
				g.beam(STEEL, a0.lerp(a1, 0.5), b0.lerp(b1, 0.5), 0.06)
			else:
				g.beam(STEEL, a0, b1, 0.07)
				g.beam(STEEL, b0, a1, 0.07)
	# plan bracing at the waist
	var yw := ys[4]
	var ww: float = hw.call(yw)
	g.beam(STEEL, Vector3(-ww, yw, -ww), Vector3(ww, yw, ww), 0.07)
	g.beam(STEEL, Vector3(ww, yw, -ww), Vector3(-ww, yw, ww), 0.07)
	# anti-climb guard ring + a small plate
	var yg := 3.2
	var wg: float = hw.call(yg)
	for f in 4:
		var c0: Vector2 = corners[f]
		var c1: Vector2 = corners[(f + 1) % 4]
		g.beam(STEEL, Vector3(c0.x * wg, yg, c0.y * wg), Vector3(c1.x * wg, yg, c1.y * wg), 0.08)
		g.beam(STEEL, Vector3(c0.x * wg, yg + 0.6, c0.y * wg), Vector3(c1.x * wg, yg + 0.6, c1.y * wg), 0.05)
	# cross-arms (along local z), three levels, longest at the bottom
	var attach := []
	var arms := [[ys[4] + 0.2, 7.2], [ys[5] + 2.6, 6.2], [ys[6] + 2.4, 5.4]]
	for arm: Array in arms:
		var y: float = arm[0]
		var L: float = arm[1]
		var w: float = hw.call(minf(y, body))
		for sz: float in [-1.0, 1.0]:
			var root_top := Vector3(0, y + 1.1, sz * w)
			var tip := Vector3(0, y + 0.15, sz * L)
			for sx: float in [-1.0, 1.0]:
				var rb := Vector3(sx * w, y, sz * w)
				var rt := Vector3(sx * w * 0.6, y + 1.1, sz * w)
				g.beam(STEEL, rb, tip, 0.11) # bottom chords
				g.beam(STEEL, rt, tip, 0.08) # top ties
				# web of the arm
				for k in 3:
					var t0 := (k + 0.5) / 3.5
					var bp := rb.lerp(tip, t0)
					var tp := rt.lerp(tip, t0 + 0.12)
					g.beam(STEEL, bp, tp, 0.05)
			g.beam(STEEL, Vector3(-w, y, sz * w).lerp(tip, 0.5), Vector3(w, y, sz * w).lerp(tip, 0.5), 0.05)
			# insulator string: steel link + porcelain discs
			var top := tip + Vector3(0, -0.15, 0)
			var bot := top + Vector3(0, -3.2, 0)
			g.bar(STEEL, top, top + Vector3(0, -0.35, 0), 0.03, 4)
			var prof := PackedVector2Array()
			var discs := 12
			var span := 2.6
			for k in discs:
				var y0 := -0.35 - span * k / discs
				prof.append(Vector2(0.05, y0))
				prof.append(Vector2(0.15, y0 - 0.06))
				prof.append(Vector2(0.13, y0 - 0.1))
				prof.append(Vector2(0.05, y0 - 0.12))
			prof.reverse() # lathe wants the profile bottom-up for outward normals
			g.col = Color(0.42, 0.24, 0.16) # brown glazed porcelain
			g.lathe(INSUL, top, prof, 8)
			g.col = Color(0.8, 0.82, 0.82)
			g.bar(STEEL, top + Vector3(0, -0.35 - span, 0), bot, 0.04, 4)
			attach.append(bot)
	# earth-wire peak
	var yp := ys[7]
	var wp: float = hw.call(yp)
	var peak := Vector3(0, h, 0)
	for cn: Vector2 in corners:
		g.beam(STEEL, Vector3(cn.x * wp, yp, cn.y * wp), peak, 0.1)
	attach.append(peak)
	# collision: the four leg bases
	for cn: Vector2 in corners:
		g.collide(Vector3(cn.x * 3.9, 2.0, cn.y * 3.9), Vector3(0.9, 4.0, 0.9))
	return attach
