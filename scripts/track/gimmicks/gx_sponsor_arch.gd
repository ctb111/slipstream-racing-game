class_name GxSponsorArch
extends RefCounted
## Sponsor structures over the road.
##   GxSponsorArch.place(c, Gx.road_frame(c, 50.0), {kind = "gantry", brand = "helios"})
##   GxSponsorArch.place(c, Gx.road_frame(c, 900.0), {kind = "inflatable", brand = "marzelli"})
## opts:
##   kind     "gantry": aluminium box-truss gantry, sponsor boards both faces,
##            amber LED timing clock on top, vertical banners on the towers
##            "inflatable": soft bulging inflatable arch with the brand printed
##            along the curve, blowers, ballast, guy ropes
##   brand    helios | valter | kronen | nordlicht | marzelli | aurel | falke | start | rallye
##   brand2   second brand for the gantry's back face / tower banners
##   clock    false: no timing clock (gantry)
## Clearance >= 5.8 m over road + kerb; feet outside road + kerb + 1.5 m, with collision.

const BRANDS := {
	helios = {arch = "a_helios", board = "b_helios", a = Color(0.93, 0.47, 0.1), b = Color(0.95, 0.92, 0.84)},
	valter = {arch = "a_valter", board = "b_valter", a = Color(0.1, 0.14, 0.33), b = Color(0.7, 0.12, 0.1)},
	kronen = {arch = "a_kronen", board = "b_kronen", a = Color(0.07, 0.07, 0.07), b = Color(0.95, 0.74, 0.18)},
	nordlicht = {arch = "b_nordlicht", board = "b_nordlicht", a = Color(0.08, 0.25, 0.16), b = Color(0.78, 0.65, 0.3)},
	marzelli = {arch = "b_marzelli", board = "b_marzelli", a = Color(0.42, 0.07, 0.08), b = Color(0.93, 0.88, 0.78)},
	aurel = {arch = "b_aurel", board = "b_aurel", a = Color(0.05, 0.05, 0.05), b = Color(0.8, 0.66, 0.36)},
	falke = {arch = "b_falke", board = "b_falke", a = Color(0.36, 0.2, 0.1), b = Color(0.95, 0.88, 0.72)},
	start = {arch = "a_start", board = "b_rallye", a = Color(0.78, 0.1, 0.08), b = Color(0.95, 0.95, 0.92)},
	rallye = {arch = "b_rallye", board = "b_rallye", a = Color(0.78, 0.1, 0.08), b = Color(0.1, 0.1, 0.1)},
}
const ALU := Color(0.8, 0.82, 0.84)
const ROWS := 6 ## girth subdivisions of the printed band on the inflatable

static var _led: StandardMaterial3D


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	if opts.get("kind", "gantry") == "inflatable":
		_inflatable(c, xf, opts)
	else:
		_gantry(c, xf, opts)


static func _brand(opts: Dictionary, key := "brand", fallback := "helios") -> Dictionary:
	return BRANDS.get(str(opts.get(key, fallback)), BRANDS.helios)


static func _road_top(c: Node3D, xf: Transform3D, half_x: float, half_z: float) -> float:
	var top := 0.0
	for x: float in [-half_x, 0.0, half_x]:
		for z: float in [-half_z, 0.0, half_z]:
			top = maxf(top, Gx.curve(c).get_closest_point(xf * Vector3(x, 0, z)).y - xf.origin.y)
	return top


static func _ground(c: Node3D, xf: Transform3D, x: float, z: float) -> float:
	return Gx.ground(c, xf * Vector3(x, 0, z)) - xf.origin.y


# ---------------------------------------------------------------- truss gantry

## Square box truss between local points a and b (chords + zig-zag lacing on 4 faces).
static func _truss(g: GxGeo, a: Vector3, b: Vector3, w: float, side_hint := Vector3.UP) -> void:
	var d := b - a
	var l := d.length()
	var x := d / l
	var y := side_hint - x * side_hint.dot(x)
	if y.length() < 0.1:
		y = Vector3.RIGHT - x * x.x
	y = y.normalized()
	var z := x.cross(y).normalized()
	var h := w * 0.5
	var corners := [y * h + z * h, y * h - z * h, -y * h - z * h, -y * h + z * h]
	for cc: Vector3 in corners:
		g.tube("steel", [a + cc, b + cc], 0.024, 6, true)
	var n := maxi(int(l / w), 1)
	for f in 4:
		var c0: Vector3 = corners[f]
		var c1: Vector3 = corners[(f + 1) % 4]
		for k in n:
			var p0 := a + x * (l * k / n)
			var p1 := a + x * (l * (k + 1) / n)
			if k % 2 == 0:
				g.tube("steel", [p0 + c0, p1 + c1], 0.011, 4, false)
			else:
				g.tube("steel", [p0 + c1, p1 + c0], 0.011, 4, false)


static func _gantry(c: Node3D, xf: Transform3D, opts: Dictionary) -> void:
	var g := GxGeo.new(xf)
	var br := _brand(opts)
	var br2 := _brand(opts, "brand2", str(opts.get("brand", "helios")))
	var hw := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5
	var tw := 0.76
	var zt := hw + tw * 0.5 + 0.1 # tower axis
	var top := _road_top(c, xf, 1.0, hw)
	var yb := top + 6.1 # truss bottom
	var yt := yb + tw
	g.col = ALU
	for s: float in [-1.0, 1.0]:
		var gy := _ground(c, xf, 0, s * zt)
		var base := Vector3(0, gy + 0.32, s * zt)
		_truss(g, base, Vector3(0, yt + 0.5, s * zt), tw, Vector3.RIGHT)
		# base plate, ballast blocks, sandbags
		g.col = Color(0.35, 0.36, 0.37)
		g.box("painted_metal", base - Vector3(0, 0.02, 0), Vector3(1.4, 0.04, 1.4), 0.005)
		g.col = Color(0.85, 0.84, 0.8)
		for bx: float in [-1.0, 1.0]:
			g.box("concrete", Vector3(bx * 1.25, gy + 0.3, s * zt), Vector3(1.0, 0.65, 1.6), 0.06)
			g.collide(Vector3(bx * 1.25, gy + 0.3, s * zt), Vector3(1.0, 0.65, 1.6))
		g.collide(Vector3(0, (gy + yt) * 0.5, s * zt), Vector3(tw, yt - gy, tw))
		g.col = Color(0.55, 0.5, 0.38)
		for k in 3:
			g.box("canvas", Vector3(-1.25 + k * 1.25, gy + 0.68 + (0.0 if k != 1 else -0.33), s * (zt + 0.95)), Vector3(0.7, 0.2, 0.42), 0.08,
				Basis(Vector3.UP, 0.3 * k - 0.3))
		g.col = ALU
		# vertical banner on the road-facing tower faces (text runs up)
		for f: float in [-1.0, 1.0]:
			var key: String = br.board if f < 0.0 else br2.board
			g.sign(Vector3(f * (tw * 0.5 + 0.04), gy + 0.9 + 2.25, s * zt), Vector3(f, 0, 0), 4.5, 0.56, key, Vector3(0, 0, -s))
	# top truss + corner blocks
	g.col = ALU
	_truss(g, Vector3(0, yb + tw * 0.5, -zt - tw * 0.5), Vector3(0, yb + tw * 0.5, zt + tw * 0.5), tw, Vector3.UP)
	# header boards on both faces (frame + print), hung below the truss as well
	for f: float in [-1.0, 1.0]:
		var key: String = br.board if f < 0.0 else br2.board
		var bw := (zt - 0.6) * 2.0
		g.col = Color(0.12, 0.12, 0.13)
		g.box("painted_metal", Vector3(f * (tw * 0.5 + 0.05), yb + tw * 0.5, 0), Vector3(0.06, 1.42, bw + 0.12), 0.01)
		# two boards side by side: brand + brand2
		g.sign(Vector3(f * (tw * 0.5 + 0.086), yb + tw * 0.5, f * -(bw * 0.25)), Vector3(f, 0, 0), bw * 0.5 - 0.1, 1.3, key)
		g.sign(Vector3(f * (tw * 0.5 + 0.086), yb + tw * 0.5, f * (bw * 0.25)), Vector3(f, 0, 0), bw * 0.5 - 0.1, 1.3, br2.board if key == br.board else br.board)
	var led: Node = null
	if opts.get("clock", true):
		led = _clock(c, g, Vector3(0, yt + 0.62, 0))
	var root := g.commit(c, "GxGantry", 900.0)
	if led:
		led.reparent(root)
	GxGeo.ab(root, xf * Vector3(-40.0, 1.4, 0.0), xf * Vector3(0, 6.0, 0))
	Gx.reserve(c, xf.origin, zt + 3.0)


## Amber LED race clock on top of the truss (both faces).
static func _clock(c: Node3D, g: GxGeo, p: Vector3) -> Node:
	g.col = Color(0.06, 0.06, 0.065)
	g.box("painted_metal", p, Vector3(0.45, 1.05, 3.6), 0.02)
	g.col = Color(0.2, 0.2, 0.2)
	g.box("painted_metal", p - Vector3(0, 0.62, 0), Vector3(0.3, 0.2, 2.6))
	if _led == null:
		_led = StandardMaterial3D.new()
		_led.albedo_color = Color(1.0, 0.55, 0.1)
		_led.emission_enabled = true
		_led.emission = Color(1.0, 0.5, 0.08)
		_led.emission_energy_multiplier = 2.5
		_led.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var text := "0:04:37"
	const SEG := {
		"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}
	var cw := 0.38
	var chh := 0.7
	var total := 0.0
	for ch in text:
		total += cw * (0.45 if ch == ":" else 1.0)
	for f: float in [-1.0, 1.0]:
		var d := -f # text runs towards the viewer's right
		var zc := -total * 0.5 * d
		for ch in text:
			var w := cw * (0.45 if ch == ":" else 1.0)
			var cz := zc + w * 0.5 * d
			var segs := []
			if ch == ":":
				segs = [[0.0, 0.16, 0.06, 0.06], [0.0, -0.16, 0.06, 0.06]]
			else:
				var on: String = SEG.get(ch, "")
				var hx := 0.14
				var hy := chh * 0.5 - 0.03
				var t := 0.045
				var defs := {a = [0.0, hy, hx, t], g = [0.0, 0.0, hx, t], d = [0.0, -hy, hx, t],
					f = [-hx, hy * 0.5, t, hy * 0.5], b = [hx, hy * 0.5, t, hy * 0.5], e = [-hx, -hy * 0.5, t, hy * 0.5], c = [hx, -hy * 0.5, t, hy * 0.5]}
				for sname in on:
					segs.append(defs[sname])
			for sg: Array in segs:
				var zz: float = cz + sg[0] * d
				var yy: float = p.y + sg[1]
				var x := p.x + f * 0.231
				var hz: float = sg[2] - 0.012
				var hy2: float = sg[3] - 0.012
				var v := [Vector3(x, yy + hy2, zz - hz), Vector3(x, yy + hy2, zz + hz), Vector3(x, yy - hy2, zz + hz), Vector3(x, yy - hy2, zz - hz)]
				st.set_normal(g.xf.basis * Vector3(f, 0, 0))
				var order := [0, 1, 2, 0, 2, 3] if f < 0.0 else [0, 2, 1, 0, 3, 2]
				for k: int in order:
					st.add_vertex(g.xf * v[k])
			zc += w * d
	var mi := Gx.add_mesh(c, st, _led, "GxGantryClock", 600.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- inflatable

static func _inflatable(c: Node3D, xf: Transform3D, opts: Dictionary) -> void:
	var g := GxGeo.new(xf)
	var br := _brand(opts)
	var hw := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5
	var r := 0.95 # tube radius
	var R := hw + r + 0.25 # leg axis
	var top := _road_top(c, xf, 1.5, hw)
	var gl := _ground(c, xf, 0, -R)
	var gr := _ground(c, xf, 0, R)
	var yb := minf(gl, gr) - 0.2
	var crown := maxf(top + 5.9 + r + 2.3, yb + R * 0.9) # inner surface well above 5.5 m over the kerbs
	var H := crown - yb
	# axis curve: ellipse-ish, slightly flattened shoulders (superellipse)
	var N := 104
	var pts := []
	var radii := []
	var cells := 13
	for i in N + 1:
		var t := PI * float(i) / N
		var ct := cos(t)
		var st := sin(t)
		var z := R * signf(ct) * pow(absf(ct), 0.85)
		var y := yb + H * pow(maxf(st, 0.0), 0.8) # sin(PI) is a tiny negative: pow would give NaN
		pts.append(Vector3(0, y, z))
		var phase := absf(sin(t * cells))
		radii.append(r * (0.86 + 0.14 * pow(phase, 0.45))) # bulging chambers, pinched at the seams
	g.col = br.a
	g.gloss = 0.12
	g.tube("props", pts, r, 16, true, radii)
	g.gloss = 0.0
	# printed brand band following the curve, both faces
	var key: String = br.arch
	var reg: Array = TracksideUV.SIGNS.get(key, [0, 0, 0.01, 0.01, 6.0])
	var band_h := 1.25 if float(reg[4]) >= 7.5 else 1.65 # short (6:1) headers get a taller band
	var arc_len := band_h * float(reg[4])
	_print_band(g, pts, radii, arc_len, band_h * 0.5, reg, -1.0)
	_print_band(g, pts, radii, arc_len, band_h * 0.5, reg, 1.0)
	# contrasting cuffs where the legs meet the feet, inflated base pillows
	for s: float in [-1.0, 1.0]:
		var foot := Vector3(0, yb + 0.35, s * R)
		var gy := _ground(c, xf, 0, s * R)
		g.col = br.b
		g.tube("props", [Vector3(0, gy + 0.55, s * R), Vector3(0, gy + 1.5, s * R)], r * 1.04, 16, false)
		g.col = br.a * 0.8
		g.box("props", Vector3(0, gy + 0.3, s * R), Vector3(2.4, 0.6, 2.4), 0.26)
		g.collide(Vector3(0, gy + 1.5, s * R), Vector3(2.4, 3.0, 2.2))
		# blower: drum with grille and a sock into the base
		g.col = Color(0.15, 0.15, 0.16)
		var bp := Vector3(1.9, gy, s * (R + 0.9))
		g.lathe("painted_metal", bp, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.32, 0.02), Vector2(0.34, 0.15), Vector2(0.34, 0.5), Vector2(0.28, 0.55), Vector2(0.0, 0.56)]), 14)
		g.col = Color(0.3, 0.3, 0.3)
		g.tube("canvas", [bp + Vector3(-0.2, 0.3, 0), bp + Vector3(-0.8, 0.25, 0), Vector3(1.1, gy + 0.35, s * R)], 0.17, 8)
		# water ballast tanks
		g.col = Color(0.9, 0.9, 0.88)
		for k: float in [-1.0, 1.0]:
			g.box("props", Vector3(k * 1.6, gy + 0.3, s * (R - 0.2)), Vector3(0.9, 0.6, 0.7), 0.12)
		# guy ropes to pegs (outside the road)
		g.col = Color(0.85, 0.85, 0.82)
		var t_att := 0.2 if s > 0.0 else PI - 0.2
		var ai := int(t_att / PI * N)
		var att: Vector3 = pts[ai]
		for k: float in [-1.0, 1.0]:
			var peg := Vector3(k * 4.5, _ground(c, xf, k * 4.5, s * (R + 2.5)), s * (R + 2.5))
			g.tube("props", [att + Vector3(k * r * 0.8, 0, 0), peg + Vector3(0, 0.1, 0)], 0.012, 4, false)
			g.col = Color(0.8, 0.3, 0.1)
			g.box("props", peg, Vector3(0.05, 0.3, 0.05))
			g.col = Color(0.85, 0.85, 0.82)
	var root := g.commit(c, "GxInflatable", 800.0)
	GxGeo.ab(root, xf * Vector3(-40.0, 1.4, 0.0), xf * Vector3(0, 6.0, 0))
	Gx.reserve(c, xf.origin, R + 5.0)


## Brand print following the tube's centre curve on face f (-1 = facing
## approaching cars, +1 = the other side), centred on the crown.
static func _print_band(g: GxGeo, pts: Array, radii: Array, arc_len: float, half_h: float, reg: Array, f: float) -> void:
	# arc-length parameterisation
	var acc := [0.0]
	for i in range(1, pts.size()):
		acc.append(acc[i - 1] + (pts[i] - pts[i - 1]).length())
	var total: float = acc[acc.size() - 1]
	var s0 := total * 0.5 - arc_len * 0.5
	var s1 := total * 0.5 + arc_len * 0.5
	var rg := Rect2(reg[0], reg[1], reg[2], reg[3])
	var a := g._arr("props")
	var prev := []
	for i in pts.size():
		if acc[i] < s0 - 0.01 or acc[i] > s1 + 0.01:
			continue
		var t: Vector3 = pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		t = t.normalized()
		var outward := Vector3(1, 0, 0).cross(t).normalized() # in the arch plane, away from the centre
		if outward.y < 0.0 and absf(outward.y) > 0.01:
			outward = -outward
		var rad: float = radii[i] * 1.03
		var u: float = (acc[i] - s0) / (s1 - s0)
		if f < 0.0: # the viewer facing +x reads from -z to +z, i.e. against the curve direction
			u = 1.0 - u
		var uu := rg.position.x + rg.size.x * clampf(u, 0.0, 1.0)
		var ang := half_h / rad
		var row := [] # girth samples: [pos, normal, uv]
		for k in ROWS + 1:
			var ga := lerpf(ang, -ang, float(k) / ROWS)
			var nrm := Vector3(f, 0, 0) * cos(ga) + outward * sin(ga)
			row.append([pts[i] + nrm * rad, nrm, Vector2(uu, lerpf(rg.position.y, rg.end.y, float(k) / ROWS))])
		if not prev.is_empty():
			for k in ROWS:
				var q := [prev[k], row[k], row[k + 1], prev[k + 1]]
				var fn: Vector3 = (q[1][0] - q[0][0]).cross(q[2][0] - q[0][0])
				var order := [0, 2, 1, 0, 3, 2] if fn.dot(q[0][1]) > 0.0 else [0, 1, 2, 0, 2, 3]
				for o: int in order:
					a[0].append(g.xf * q[o][0])
					a[1].append((g.xf.basis * q[o][1]).normalized())
					a[2].append(Color.WHITE)
					a[3].append(q[o][2])
					a[4].append(Vector2(1.0, 0.0))
		prev = row
