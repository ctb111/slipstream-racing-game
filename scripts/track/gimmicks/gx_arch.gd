class_name GxArch
extends RefCounted
## Old masonry over or under the road.
##   GxArch.place(c, Gx.road_frame(c, 800.0), {kind = "gate"})      # town gate the road passes under
##   GxArch.place(c, Gx.road_frame(c, 1500.0), {kind = "bridge", stream = true})  # road crosses OVER
## opts (gate):
##   material  "stone" (ashlar) | "brick" (brick body, stone dressings) | "plaster" (ochre render, stone dressings)
##   tower     true: clock tower storey with a tiled hipped roof (default); false: crenellated parapet
##   walls     length of the town walls either side (default 12 m, 0 = none)
##   plaque    TracksideUV.SIGNS key over the arch (default "p_town")
## opts (bridge):
##   length    bridge length along the track (default 40 m); arches (default 3)
##   stream    true: water and bank stones under the arches where the ground is low
##   lamps     true: Victorian lamp posts (Poly Haven street_lamp_01) on the parapets
## The road is untouched: the bridge's parapets, spandrels and arches are built
## around the existing track surface where the terrain dips.

const LAMP := "res://assets/gimmicks/street_lamp_01/street_lamp_01.gltf"
const STONE := Color(0.95, 0.93, 0.9)
const DRESS := Color(1.0, 0.98, 0.95)


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	if opts.get("kind", "gate") == "bridge":
		_bridge(c, xf, opts)
	else:
		_gate(c, xf, opts)


static func _ground(c: Node3D, xf: Transform3D, x: float, z: float) -> float:
	return Gx.ground(c, xf * Vector3(x, 0, z)) - xf.origin.y


# ---------------------------------------------------------------- town gate

static func _gate(c: Node3D, xf: Transform3D, opts: Dictionary) -> void:
	var g := GxGeo.new(xf)
	var mat: String = opts.get("material", "stone")
	var body := mat if mat != "plaster" else "plaster"
	var dress := "stone"
	var hw := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5
	var a := hw + 0.3 # arch radius = half opening
	var D := 7.0 # depth along the road
	var hd := D * 0.5
	var pier := 3.6
	var zo := a + pier
	var top := 0.0
	for x: float in [-hd, 0.0, hd]:
		top = maxf(top, Gx.curve(c).get_closest_point(xf * Vector3(x, 0, 0)).y - xf.origin.y)
	# 5.5 m clear over road + kerb: at |z| = road+kerb the intrados must still be high enough
	var zk := Gx.half_width() + TrackBuilder.CURB_WIDTH
	var ys := top + 5.9 - sqrt(a * a - zk * zk)
	ys = maxf(ys, top + 1.2)
	var crown := ys + a
	var yt := crown + 2.2
	var yg := INF
	for x: float in [-hd, hd]:
		for z: float in [-zo, -a, a, zo]:
			yg = minf(yg, _ground(c, xf, x, z))
	yg -= 0.6
	var body_col := STONE
	if mat == "brick":
		body_col = Color(0.95, 0.88, 0.85)
	elif mat == "plaster":
		body_col = Color(0.93, 0.78, 0.55)
	# piers (full height, give the jambs), with collision
	g.col = body_col
	for s: float in [-1.0, 1.0]:
		var zc := s * (a + zo) * 0.5
		g.box(body, Vector3(0, (yg + yt) * 0.5, zc), Vector3(D, yt - yg, zo - a))
		g.collide(Vector3(0, (yg + yt) * 0.5, zc), Vector3(D, yt - yg, zo - a))
	# spandrel faces + barrel vault soffit, smooth semicircle
	var N := 28
	for i in N:
		var t0 := PI * i / N
		var t1 := PI * (i + 1) / N
		var p0 := Vector2(a * cos(t0), ys + a * sin(t0))
		var p1 := Vector2(a * cos(t1), ys + a * sin(t1))
		# front (+x) and back (-x)
		g.quad_n(body, Vector3(hd, p0.y, p0.x), Vector3(hd, p1.y, p1.x), Vector3(hd, yt, p1.x), Vector3(hd, yt, p0.x), Vector3.RIGHT)
		g.quad_n(body, Vector3(-hd, p1.y, p1.x), Vector3(-hd, p0.y, p0.x), Vector3(-hd, yt, p0.x), Vector3(-hd, yt, p1.x), Vector3.LEFT)
		g.col = body_col * 0.78 # soot / damp under the vault
		var tm := (t0 + t1) * 0.5
		g.quad_n(dress, Vector3(-hd, p0.y, p0.x), Vector3(hd, p0.y, p0.x), Vector3(hd, p1.y, p1.x), Vector3(-hd, p1.y, p1.x), Vector3(0, -sin(tm), -cos(tm)))
		g.col = body_col
	g.quad_n(body, Vector3(-hd, yt, -a), Vector3(-hd, yt, a), Vector3(hd, yt, a), Vector3(hd, yt, -a), Vector3.UP)
	# voussoirs, proud of both faces, keystone larger
	g.col = DRESS
	var nv := 19
	for s: float in [-1.0, 1.0]:
		for i in nv:
			var t0 := PI * i / nv + 0.006
			var t1 := PI * (i + 1) / nv - 0.006
			var key := i == nv / 2
			var r1 := a + (1.35 if key else (0.95 if i % 2 == 0 else 0.8))
			var proud := 0.22 if key else 0.12
			_voussoir(g, dress, s * hd, s * (hd + proud), ys, a, r1, t0, t1)
		# impost blocks and a plinth
		for zs: float in [-1.0, 1.0]:
			g.box(dress, Vector3(s * (hd + 0.06), ys - 0.2, zs * (a + 0.55)), Vector3(0.3, 0.4, 1.3), 0.04)
			g.box(dress, Vector3(s * (hd + 0.08), yg + 0.9, zs * (a + zo) * 0.5), Vector3(0.36, 1.1, zo - a + 0.1), 0.05)
			# quoins up the outer corners
			var q := int((yt - yg - 1.6) / 0.62)
			for k in q:
				var y := yg + 1.6 + k * 0.62 + 0.3
				var w := 0.9 if k % 2 == 0 else 0.55
				g.box(dress, Vector3(s * (hd + 0.04), y, zs * (zo - w * 0.5 + 0.04)), Vector3(0.16, 0.56, w), 0.03)
	# inner jamb plinths
	for zs: float in [-1.0, 1.0]:
		g.box(dress, Vector3(0, yg + 0.9, zs * (a + 0.06)), Vector3(D + 0.1, 1.1, 0.24), 0.05)
	# cornice (two stepped courses) all round
	for k in 2:
		var o := 0.14 + k * 0.14
		g.box(dress, Vector3(0, yt - 0.1 + k * 0.22, 0), Vector3(D + o * 2.0, 0.22, zo * 2.0 + o * 2.0), 0.04)
	var yc := yt + 0.34
	var walls: float = float(opts.get("walls", 12.0))
	# side town walls with merlons
	g.col = body_col * 0.96
	for s: float in [-1.0, 1.0]:
		if walls <= 0.0:
			break
		var z0 := s * zo
		var z1 := s * (zo + walls)
		var gw := minf(_ground(c, xf, 0, z1), _ground(c, xf, 0, z0)) - 0.6
		var wt := yt - 2.4
		g.box(body, Vector3(0, (gw + wt) * 0.5, (z0 + z1) * 0.5), Vector3(2.2, wt - gw, walls))
		g.collide(Vector3(0, (gw + wt) * 0.5, (z0 + z1) * 0.5), Vector3(2.2, wt - gw, walls))
		g.box(dress, Vector3(0, wt + 0.1, (z0 + z1) * 0.5), Vector3(2.5, 0.2, walls), 0.04)
		var nm := int(walls / 1.5)
		for k in nm:
			var z := z0 + s * (k + 0.5) * walls / nm
			for xs: float in [-1.0, 1.0]:
				g.box(body, Vector3(xs * 0.85, wt + 0.75, z), Vector3(0.5, 1.1, 0.85), 0.03)
		# buttress at the far end, stepping down
		g.box(body, Vector3(0, (gw + wt - 1.0) * 0.5, z1 + s * 0.6), Vector3(3.0, wt - 1.0 - gw, 1.2), 0.08)
	g.col = body_col
	if opts.get("tower", true):
		var tz := a * 0.72
		var tt := yc + 5.2
		g.box(body, Vector3(0, (yc + tt) * 0.5, 0), Vector3(D - 0.8, tt - yc, tz * 2.0))
		g.col = DRESS
		g.box(dress, Vector3(0, tt + 0.12, 0), Vector3(D - 0.3, 0.24, tz * 2.0 + 0.5), 0.04)
		for s: float in [-1.0, 1.0]:
			var fx := s * ((D - 0.8) * 0.5)
			# arched windows: dark recess with stone surround
			for wz: float in [-tz * 0.55, tz * 0.55]:
				g.col = Color(0.12, 0.11, 0.1)
				g.box("props", Vector3(fx, yc + 2.9, wz), Vector3(0.08, 1.7, 0.85))
				g.col = DRESS
				g.box(dress, Vector3(fx + s * 0.05, yc + 1.95, wz), Vector3(0.12, 0.16, 1.15), 0.02)
				_voussoir_ring(g, dress, fx, fx + s * 0.08, yc + 3.75, 0.43, 0.68, 7)
			# clock face
			g.col = Color(0.92, 0.9, 0.84)
			_clock(g, Vector3(fx, yc + 2.95, 0), s)
		# hipped roof, tiled, with eaves overhang
		var ex := (D - 0.8) * 0.5 + 0.55
		var ez := tz + 0.55
		var ridge := tt + 0.24 + minf(ex, ez) * 1.15
		var rz := maxf(ez - ex, 0.3)
		var e := tt + 0.2
		g.col = Color(0.66, 0.34, 0.24)
		g.quad_n("roof_tiles", Vector3(ex, e, -ez), Vector3(ex, e, ez), Vector3(0, ridge, rz), Vector3(0, ridge, -rz), Vector3(1, 1, 0))
		g.quad_n("roof_tiles", Vector3(-ex, e, ez), Vector3(-ex, e, -ez), Vector3(0, ridge, -rz), Vector3(0, ridge, rz), Vector3(-1, 1, 0))
		g.tri_f("roof_tiles", Vector3(ex, e, ez), Vector3(-ex, e, ez), Vector3(0, ridge, rz), Vector3(0, 1, 1))
		g.tri_f("roof_tiles", Vector3(-ex, e, -ez), Vector3(ex, e, -ez), Vector3(0, ridge, -rz), Vector3(0, 1, -1))
		g.col = Color(0.4, 0.38, 0.36)
		g.quad_n("roof_tiles", Vector3(ex, e, -ez), Vector3(ex, e, ez), Vector3(-ex, e, ez), Vector3(-ex, e, -ez), Vector3.DOWN)
		g.col = Color(0.5, 0.47, 0.45)
		g.lathe("painted_metal", Vector3(0, ridge - 0.1, -rz), PackedVector2Array([Vector2(0.08, 0), Vector2(0.06, 0.6), Vector2(0.15, 0.7), Vector2(0.01, 1.3)]), 8)
		g.lathe("painted_metal", Vector3(0, ridge - 0.1, rz), PackedVector2Array([Vector2(0.08, 0), Vector2(0.06, 0.6), Vector2(0.15, 0.7), Vector2(0.01, 1.3)]), 8)
		g.bar("painted_metal", Vector3(0, ridge + 0.02, -rz), Vector3(0, ridge + 0.02, rz), 0.09, 6)
	else:
		var nm := int(zo * 2.0 / 1.6)
		for k in nm:
			var z := -zo + (k + 0.5) * zo * 2.0 / nm
			for xs: float in [-1.0, 1.0]:
				g.box(body, Vector3(xs * (hd - 0.3), yc + 0.6, z), Vector3(0.6, 1.2, 0.95), 0.03)
	# plaque above the keystone
	var plaque: String = opts.get("plaque", "p_town")
	if plaque != "":
		for s: float in [-1.0, 1.0]:
			g.sign(Vector3(s * (hd + 0.02), crown + 1.65 if crown + 1.65 < yt - 0.45 else yt - 0.45, 0), Vector3(s, 0, 0), 3.2, 0.0, plaque)
	var root := g.commit(c, "GxArchGate", 1000.0)
	GxGeo.ab(root, xf * Vector3(-45.0, 1.4, 0.0), xf * Vector3(0, 6.0, 0))
	Gx.reserve(c, xf.origin, zo + walls + 3.0)


## One voussoir (wedge stone) of an arch on a face: front at x = xa (wall face),
## proud face at xb; inner radius r0, outer r1, angles t0..t1, spring height ys.
static func _voussoir(g: GxGeo, mat: String, xa: float, xb: float, ys: float, r0: float, r1: float, t0: float, t1: float) -> void:
	var p := [Vector2(r0 * cos(t0), ys + r0 * sin(t0)), Vector2(r0 * cos(t1), ys + r0 * sin(t1)),
		Vector2(r1 * cos(t1), ys + r1 * sin(t1)), Vector2(r1 * cos(t0), ys + r1 * sin(t0))]
	var f := signf(xb - xa)
	var xm := xb - 0.03 * f
	var mid: Vector2 = (p[0] + p[1] + p[2] + p[3]) * 0.25
	var ins := []
	for v: Vector2 in p:
		ins.append(v + (mid - v).normalized() * 0.035)
	var V := func(v: Vector2, x: float) -> Vector3: return Vector3(x, v.y, v.x)
	g.quad_n(mat, V.call(ins[0], xb), V.call(ins[1], xb), V.call(ins[2], xb), V.call(ins[3], xb), Vector3(f, 0, 0))
	for i in 4:
		var u: Vector2 = p[i]
		var v: Vector2 = p[(i + 1) % 4]
		var em: Vector2 = (u + v) * 0.5 - mid
		var n := Vector3(0, em.y, em.x).normalized()
		g.quad_n(mat, V.call(u, xa), V.call(u, xm), V.call(v, xm), V.call(v, xa), n)
		g.quad_n(mat, V.call(u, xm), V.call(ins[i], xb), V.call(ins[(i + 1) % 4], xb), V.call(v, xm), (n + Vector3(f, 0, 0)).normalized())


static func _voussoir_ring(g: GxGeo, mat: String, xa: float, xb: float, ys: float, r0: float, r1: float, n: int) -> void:
	for i in n:
		_voussoir(g, mat, xa, xb, ys, r0, r1, PI * i / n + 0.01, PI * (i + 1) / n - 0.01)


static func _clock(g: GxGeo, p: Vector3, s: float) -> void:
	var n := 24
	g.col = Color(0.9, 0.88, 0.8)
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var c0 := p + Vector3(s * 0.06, 0, 0)
		var v0 := c0 + Vector3(0, sin(a0), cos(a0)) * 0.95
		var v1 := c0 + Vector3(0, sin(a1), cos(a1)) * 0.95
		g.tri_f("props", c0, v0, v1, Vector3(s, 0, 0))
	g.col = Color(0.08, 0.08, 0.08)
	for i in 12:
		var a := TAU * i / 12.0
		g.box("props", p + Vector3(s * 0.08, sin(a) * 0.8, cos(a) * 0.8), Vector3(0.02, 0.14 if i % 3 == 0 else 0.07, 0.05), 0.0, Basis(Vector3.RIGHT, -a))
	g.box("props", p + Vector3(s * 0.1, 0.25, 0.1), Vector3(0.02, 0.55, 0.06), 0.0, Basis(Vector3.RIGHT, -0.4))
	g.box("props", p + Vector3(s * 0.11, -0.05, 0.3), Vector3(0.02, 0.07, 0.65), 0.0, Basis(Vector3.RIGHT, 0.5))
	g.col = DRESS
	_voussoir_ring(g, "stone", p.x, p.x + s * 0.1, p.y, 0.95, 1.2, 12)
	g.box("stone", p + Vector3(s * 0.05, -1.08, 0), Vector3(0.14, 0.22, 2.5), 0.03)


# ---------------------------------------------------------------- stone bridge (road over)

static func _bridge(c: Node3D, xf: Transform3D, opts: Dictionary) -> void:
	var cv := Gx.curve(c)
	var lap := cv.get_baked_length()
	var along0 := fposmod(cv.get_closest_offset(xf.origin) - float(c.get("start_offset")), lap)
	var L: float = float(opts.get("length", 40.0))
	var na: int = int(opts.get("arches", 3))
	var g := GxGeo.new(Transform3D.IDENTITY) # world space: follows the road
	var pz := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5 # parapet inner face
	var tw := 0.5 # parapet thickness
	var oz := pz + tw # spandrel face
	var step := 1.0
	var n := int(L / step)
	# frames along the bridge
	var fr: Array[Transform3D] = []
	for i in n + 1:
		fr.append(Gx.road_frame(c, along0 - L * 0.5 + i * step))
	# arch layout along s (0..L): spans and pier widths
	var pierw := 2.2
	var spans: Array[float] = []
	var total := 0.0
	for k in na:
		var sp := 10.0 if (k == na / 2) else 7.5
		spans.append(sp)
		total += sp
	total += pierw * (na - 1)
	var s0 := (L - total) * 0.5
	var arches := [] # [s_centre, half_span]
	var s := s0
	for k in na:
		arches.append([s + spans[k] * 0.5, spans[k] * 0.5])
		s += spans[k] + pierw
	# ground along each face; arch geometry per arch (segmental if shallow)
	var gmin := INF
	var deck_min := INF
	for i in n + 1:
		for side: float in [-1.0, 1.0]:
			gmin = minf(gmin, Gx.ground(c, fr[i] * Vector3(0, 0, side * oz)))
		deck_min = minf(deck_min, fr[i].origin.y)
	for ar: Array in arches:
		var lo := INF
		var hi := -INF
		for i in n + 1:
			if absf(i * step - ar[0]) <= ar[1]:
				for side: float in [-1.0, 1.0]:
					lo = minf(lo, Gx.ground(c, fr[i] * Vector3(0, 0, side * oz)))
				hi = maxf(hi, fr[i].origin.y)
		var spring := lo - 0.4
		var rise := minf(ar[1], hi - 1.0 - spring)
		rise = maxf(rise, 0.0)
		var R: float = (ar[1] * ar[1] + rise * rise) / (2.0 * maxf(rise, 0.01))
		ar.append(spring + rise - R) # centre y
		ar.append(R)
		ar.append(rise > 0.8)
	var intr := func(si: float) -> float: # intrados height at s (or -INF outside arches)
		for ar: Array in arches:
			if ar[4] and absf(si - ar[0]) < ar[1]:
				return ar[2] + sqrt(maxf(ar[3] * ar[3] - (si - ar[0]) * (si - ar[0]), 0.0))
		return -INF
	g.col = STONE
	for i in n:
		var fa := fr[i]
		var fb := fr[i + 1]
		var sa := i * step
		var sb := (i + 1) * step
		for side: float in [-1.0, 1.0]:
			var za := fa * Vector3(0, 0, side * oz)
			var zb := fb * Vector3(0, 0, side * oz)
			var ia := fa * Vector3(0, 0, side * pz)
			var ib := fb * Vector3(0, 0, side * pz)
			var cap := 1.0
			# parapet: outer face (spandrel continues), inner face, coping
			var bot_a := maxf(intr.call(sa), Gx.ground(c, za) - 0.6)
			var bot_b := maxf(intr.call(sb), Gx.ground(c, zb) - 0.6)
			var ta := fa.origin.y + cap
			var tb := fb.origin.y + cap
			var up := Vector3.UP
			var outn := fa.basis.z * side
			g.quad_n("stone", Vector3(za.x, bot_a, za.z), Vector3(zb.x, bot_b, zb.z), Vector3(zb.x, tb, zb.z), Vector3(za.x, ta, za.z), outn)
			g.quad_n("stone", Vector3(ib.x, fb.origin.y - 0.2, ib.z), Vector3(ia.x, fa.origin.y - 0.2, ia.z), Vector3(ia.x, ta, ia.z), Vector3(ib.x, tb, ib.z), -outn)
			# coping stones (one block per metre, chamfered, slight random tilt)
			var mid := (za + zb + ia + ib) * 0.25
			var yaw := fa.basis
			g.col = DRESS * (0.94 + 0.06 * sin(i * 7.3 + side))
			g.box("stone", Vector3(mid.x, (ta + tb) * 0.5 + 0.09, mid.z), Vector3(step + 0.01, 0.18, tw + 0.16), 0.035, yaw)
			g.col = STONE
			g.collide(Vector3(mid.x, (ta + tb) * 0.5 - 0.5, mid.z), Vector3(step, 1.2, tw), yaw)
			# verge / footway paving between kerb and parapet
			var ka := fa * Vector3(0, 0, side * (Gx.half_width() + TrackBuilder.CURB_WIDTH))
			var kb := fb * Vector3(0, 0, side * (Gx.half_width() + TrackBuilder.CURB_WIDTH))
			g.col = Color(0.8, 0.78, 0.74)
			g.quad_n("stone", Vector3(ka.x, fa.origin.y + 0.04, ka.z), Vector3(kb.x, fb.origin.y + 0.04, kb.z), Vector3(ib.x, fb.origin.y + 0.04, ib.z), Vector3(ia.x, fa.origin.y + 0.04, ia.z), Vector3.UP)
			g.col = STONE
			# string course along the spandrel just below the parapet
			var sc := fa.origin.y - 0.35
			g.box("stone", Vector3((za.x + zb.x) * 0.5, sc, (za.z + zb.z) * 0.5) + fa.basis.z * side * 0.1, Vector3(step + 0.01, 0.22, 0.25), 0.03, yaw)
		# barrel vault under the arch
		var ya: float = intr.call(sa)
		var yb: float = intr.call(sb)
		if ya > -INF and yb > -INF:
			var l0 := fa * Vector3(0, 0, -oz)
			var r0 := fa * Vector3(0, 0, oz)
			var l1 := fb * Vector3(0, 0, -oz)
			var r1 := fb * Vector3(0, 0, oz)
			g.col = STONE * 0.7
			g.quad_n("stone", Vector3(l1.x, yb, l1.z), Vector3(r1.x, yb, r1.z), Vector3(r0.x, ya, r0.z), Vector3(l0.x, ya, l0.z), Vector3.DOWN)
			g.col = STONE
	# voussoir rings and cutwater piers
	g.col = DRESS
	for ar: Array in arches:
		if not ar[4]:
			continue
		var half_ang := asin(clampf(ar[1] / ar[3], 0.0, 1.0))
		var nv := 15
		for k in nv:
			var a0 := -half_ang + 2.0 * half_ang * k / nv
			var a1 := -half_ang + 2.0 * half_ang * (k + 1) / nv
			for side: float in [-1.0, 1.0]:
				_vous_world(g, c, fr, step, side, oz, ar, a0 + 0.006, a1 - 0.006, 0.75 if k % 2 == 0 else 0.6)
	for k in na - 1:
		var sp: float = arches[k][0] + arches[k][1] + pierw * 0.5
		var fi := clampi(int(sp / step), 0, n)
		var f := fr[fi]
		var ar: Array = arches[k]
		var top_y: float = maxf(ar[2] + sqrt(maxf(ar[3] * ar[3] - ar[1] * ar[1], 0.0)), gmin + 0.5)
		for side: float in [-1.0, 1.0]:
			var base := f * Vector3(0, 0, side * (oz + 0.0))
			var gy := Gx.ground(c, base) - 0.6
			var tip := f * Vector3(0, 0, side * (oz + 1.8))
			var l := f * Vector3(-pierw * 0.5, 0, side * oz)
			var r := f * Vector3(pierw * 0.5, 0, side * oz)
			# cutwater: triangular prism from ground to just under the spring + capping
			var ytop := top_y + 0.2
			g.col = STONE
			for e: Array in [[l, tip], [tip, r]]:
				var p0: Vector3 = e[0]
				var p1: Vector3 = e[1]
				var em := (p0 + p1) * 0.5 - f * Vector3(0, 0, side * oz)
				em.y = 0.0
				g.quad_n("stone", Vector3(p0.x, gy, p0.z), Vector3(p1.x, gy, p1.z), Vector3(p1.x, ytop, p1.z), Vector3(p0.x, ytop, p0.z), em)
			var apex := tip + Vector3(0, ytop + 1.0 - tip.y, 0) - f.basis.z * side * 1.4
			g.col = DRESS
			var cn := f * Vector3(0, 0, side * (oz + 0.9))
			g.tri_f("stone", Vector3(l.x, ytop, l.z), Vector3(tip.x, ytop, tip.z), apex, (Vector3(l.x, ytop, l.z) + Vector3(tip.x, ytop, tip.z)) * 0.5 - Vector3(cn.x, ytop, cn.z) + Vector3.UP)
			g.tri_f("stone", Vector3(tip.x, ytop, tip.z), Vector3(r.x, ytop, r.z), apex, (Vector3(r.x, ytop, r.z) + Vector3(tip.x, ytop, tip.z)) * 0.5 - Vector3(cn.x, ytop, cn.z) + Vector3.UP)
	# water + bank stones under the arches where the ground is low
	var stream: Node = null
	if opts.get("stream", false):
		stream = _stream(c, g, fr, arches, step, oz)
	var root := g.commit(c, "GxArchBridge", 1000.0)
	if opts.get("lamps", true):
		_lamps(root, fr, pz + tw * 0.5, n)
	if stream:
		stream.reparent(root)
	GxGeo.ab(root, fr[0] * Vector3(-30.0, 1.4, 0.0), fr[n / 2].origin + Vector3.UP * 2.0)
	Gx.reserve(c, fr[n / 2].origin, L * 0.5 + 6.0)


## Voussoir on a world-space bridge face: angles measured from the arch's vertical.
static func _vous_world(g: GxGeo, _c: Node3D, fr: Array[Transform3D], step: float, side: float, oz: float, ar: Array, a0: float, a1: float, depth: float) -> void:
	var pts := []
	for a: float in [a0, a1]:
		for r: float in [ar[3], ar[3] + depth]:
			var si: float = ar[0] + r * sin(a)
			var y: float = ar[2] + r * cos(a)
			var fi := clampi(int(round(si / step)), 0, fr.size() - 1)
			var f: Transform3D = fr[fi]
			var w := f * Vector3(si - fi * step, 0, side * oz)
			pts.append(Vector3(w.x, y, w.z))
	# pts: a0 inner, a0 outer, a1 inner, a1 outer; extrude out by 0.12
	var f: Transform3D = fr[clampi(int(ar[0] / step), 0, fr.size() - 1)]
	var o: Vector3 = f.basis.z * side * 0.12
	var i0: Vector3 = pts[0]
	var o0: Vector3 = pts[1]
	var i1: Vector3 = pts[2]
	var o1: Vector3 = pts[3]
	var on := o.normalized()
	var mid := (i0 + o0 + i1 + o1) * 0.25
	g.quad_n("stone", i0 + o, i1 + o, o1 + o, o0 + o, on)
	for e: Array in [[i0, i1], [i1, o1], [o1, o0], [o0, i0]]:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		g.quad_n("stone", a, b, b + o, a + o, (a + b) * 0.5 - mid)


static func _stream(c: Node3D, g: GxGeo, fr: Array[Transform3D], arches: Array, step: float, oz: float) -> Node:
	var ar: Array = arches[arches.size() / 2]
	if not ar[4]:
		return null
	var fi := clampi(int(ar[0] / step), 0, fr.size() - 1)
	var f: Transform3D = fr[fi]
	var low := INF
	for side: float in [-1.0, 1.0]:
		low = minf(low, Gx.ground(c, f * Vector3(0, 0, side * oz)))
	var wy := low + 0.25
	var hw: float = ar[1] - 0.6
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.09, 0.12, 0.1)
	wm.roughness = 0.04
	wm.metallic = 0.15
	wm.metallic_specular = 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(f.origin))
	var zs := []
	for k in 31:
		zs.append(-36.0 + k * 2.4)
	for k in zs.size() - 1:
		var za: float = zs[k]
		var zb: float = zs[k + 1]
		var ga := Gx.ground(c, f * Vector3(0, 0, za))
		var gb := Gx.ground(c, f * Vector3(0, 0, zb))
		if minf(ga, gb) > wy + 0.4:
			continue
		var w0 := hw * (0.75 + 0.25 * sin(za * 0.21))
		var w1 := hw * (0.75 + 0.25 * sin(zb * 0.21))
		var p := [f * Vector3(-w0, 0, za), f * Vector3(w0, 0, za), f * Vector3(w1, 0, zb), f * Vector3(-w1, 0, zb)]
		for q: Vector3 in p:
			q.y = wy
		var v := []
		for q: Vector3 in p:
			v.append(Vector3(q.x, wy, q.z))
		st.set_normal(Vector3.UP)
		for idx: int in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(v[idx])
		# bank stones
		g.col = Color(0.75, 0.72, 0.68)
		for e: float in [-1.0, 1.0]:
			for r in 2:
				var pz := za + rng.randf() * 2.4
				var px := e * (w0 + rng.randf_range(-0.2, 0.6))
				var bp := f * Vector3(px, 0, pz)
				var sz := Vector3(rng.randf_range(0.4, 1.0), rng.randf_range(0.3, 0.6), rng.randf_range(0.4, 0.9))
				g.box("stone", Vector3(bp.x, wy + sz.y * 0.2, bp.z), sz, 0.12, Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.2, 0.2)))
	g.col = STONE
	var mi := Gx.add_mesh(c, st, wm, "GxArchStream", 500.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _lamps(c: Node3D, fr: Array[Transform3D], lat: float, n: int) -> void:
	if not ResourceLoader.exists(LAMP):
		return
	var scene: PackedScene = load(LAMP)
	var picks := [[n / 6, 1.0], [n / 2, -1.0], [n * 5 / 6, 1.0]]
	for p: Array in picks:
		var f: Transform3D = fr[p[0]]
		var lamp: Node3D = scene.instantiate()
		lamp.name = "GxArchLamp"
		var pos := f * Vector3(0, 0, p[1] * lat)
		lamp.transform = Transform3D(f.basis.orthonormalized(), pos + Vector3(0, 1.18, 0)).scaled_local(Vector3.ONE * 1.05)
		c.add_child(lamp)
		for mi in lamp.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(mi as MeshInstance3D).visibility_range_end = 220.0
			(mi as MeshInstance3D).visibility_range_end_margin = 30.0
			(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
