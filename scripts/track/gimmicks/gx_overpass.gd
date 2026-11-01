class_name GxOverpass
extends RefCounted
## A bridge crossing OVER the circuit on concrete piers.
##   GxOverpass.place(c, Gx.road_frame(c, 1200.0), {kind = "road"})
## opts:
##   kind      "road" (precast concrete I-girder road bridge, lamp posts, approach ramps)
##             "rail" (riveted steel plate-girder railway bridge, ballast, sleepers, catenary masts)
##             "footbridge" (steel Warren-truss footbridge with stair flights down both sides)
##   span      half distance between the piers' inner faces (default: road + kerb + 1.5 m + 1 m)
##   side      side-span length beyond each pier (default 12 m road / 8 rail / 3 footbridge)
##   banner    TracksideUV.SIGNS key hung on both fascias (e.g. "b_valter"); "" = none
##   paint     Color of painted steel (rail girders, truss, lamp posts)
##   ramps     false = no approach ramps (road kind); lamps = false: no lamp posts
##   train     true = moving train across the rail bridge (default: true for rail)
## Clearance >= 5.8 m above the highest road point under the deck; piers outside
## road + kerb + 1.5 m, with collision. Trees are kept clear.

const CLEAR := 5.8
const CONC := Color(0.93, 0.92, 0.89)
const CONC_DARK := Color(0.72, 0.71, 0.69)
const ASPHALT := Color(0.26, 0.26, 0.27)


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind: String = opts.get("kind", "road")
	var g := GxGeo.new(xf)
	var hw := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5 # nothing solid inside this
	var W: float = {road = 9.0, rail = 5.6, footbridge = 3.0}.get(kind, 9.0) # deck width (along the track)
	var zp: float = float(opts.get("span", hw + 1.0)) + 0.6 # pier centre
	var side: float = float(opts.get("side", {road = 12.0, rail = 8.0, footbridge = 3.0}.get(kind, 10.0)))
	var ze := zp + side # deck end / abutment
	# highest road point under the deck footprint
	var top := 0.0
	for x: float in [-W * 0.5 - 1.0, 0.0, W * 0.5 + 1.0]:
		for z: float in [-hw, 0.0, hw]:
			var p := xf * Vector3(x, 0, z)
			top = maxf(top, Gx.curve(c).get_closest_point(p).y - xf.origin.y)
	var soffit := top + CLEAR
	match kind:
		"rail":
			_rail(c, g, xf, W, zp, ze, soffit, opts)
		"footbridge":
			_foot(c, g, xf, W, zp, ze, soffit, opts)
		_:
			_road(c, g, xf, W, zp, ze, soffit, opts)
	var root := g.commit(c, "GxOverpass", 900.0)
	GxGeo.ab(root, xf * Vector3(-45.0, 1.4, 0.0), xf * Vector3(0, 5.0, 0))
	Gx.reserve(c, xf.origin, ze + 6.0)


# ---------------------------------------------------------------- helpers

## Sub-frame whose +x runs along local +z (across the road): extrusions span the road.
static func _across() -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)), Vector3.ZERO)


static func _rect(cx: float, cy: float, hx: float, hy: float, e := 0.0) -> PackedVector2Array:
	var p := GxGeo.chamfer_rect(hx, hy, e) if e > 0.0 else PackedVector2Array([Vector2(-hx, -hy), Vector2(hx, -hy), Vector2(hx, hy), Vector2(-hx, hy)])
	for i in p.size():
		p[i] += Vector2(cx, cy)
	return p


static func _ground(c: Node3D, xf: Transform3D, x: float, z: float) -> float:
	return Gx.ground(c, xf * Vector3(x, 0, z)) - xf.origin.y


## Lowest ground over a footprint (local x range, z range).
static func _ground_min(c: Node3D, xf: Transform3D, x0: float, x1: float, z0: float, z1: float) -> float:
	var m := INF
	for x in [x0, (x0 + x1) * 0.5, x1]:
		for z in [z0, (z0 + z1) * 0.5, z1]:
			m = minf(m, _ground(c, xf, x, z))
	return m


## Galvanised railing along local z at x, from z0 to z1, base height y.
static func _railing(g: GxGeo, x: float, z0: float, z1: float, y: float, h := 1.1, infill := false) -> void:
	var n := maxi(int(absf(z1 - z0) / 2.0), 1)
	for i in n + 1:
		var z := lerpf(z0, z1, float(i) / n)
		g.box("steel", Vector3(x, y + h * 0.5, z), Vector3(0.07, h, 0.07))
		g.box("steel", Vector3(x, y + 0.03, z), Vector3(0.16, 0.06, 0.16)) # base plate
	g.tube("steel", [Vector3(x, y + h, z0), Vector3(x, y + h, z1)], 0.045, 8)
	for f: float in ([0.35, 0.68] if not infill else [0.12, 0.9]):
		g.box("steel", Vector3(x, y + h * f, (z0 + z1) * 0.5), Vector3(0.04, 0.05, absf(z1 - z0)))
	if infill:
		var bars := int(absf(z1 - z0) / 0.14)
		for i in bars:
			var z := lerpf(z0, z1, (i + 0.5) / bars)
			g.box("steel", Vector3(x, y + h * 0.51, z), Vector3(0.018, h * 0.78, 0.018))


## Highway lamp post standing at local p, arm reaching towards `dir` (local).
static func _lamp(g: GxGeo, p: Vector3, dir: Vector3, h := 7.5) -> void:
	var old := g.col
	g.col = Color(0.55, 0.57, 0.58)
	g.box("painted_metal", p + Vector3(0, 0.04, 0), Vector3(0.36, 0.08, 0.36), 0.01)
	g.lathe("painted_metal", p, PackedVector2Array([Vector2(0.15, 0.0), Vector2(0.14, 0.6), Vector2(0.105, 0.68), Vector2(0.075, h)]), 10)
	var top := p + Vector3(0, h, 0)
	var arm := [top - Vector3(0, 0.3, 0), top + Vector3(0, 0.15, 0) + dir * 0.35, top + Vector3(0, 0.38, 0) + dir * 1.0, top + Vector3(0, 0.45, 0) + dir * 1.8]
	g.tube("painted_metal", arm, 0.05, 8)
	var head := top + Vector3(0, 0.38, 0) + dir * 2.15
	var yaw := Basis(Vector3.UP, atan2(dir.x, dir.z))
	g.col = Color(0.42, 0.43, 0.44)
	g.box("painted_metal", head, Vector3(0.34, 0.14, 0.78), 0.05, yaw)
	g.col = Color(1.0, 0.95, 0.8)
	g.box("glass", head - Vector3(0, 0.075, 0), Vector3(0.26, 0.02, 0.6), 0.0, yaw)
	g.col = old


# ---------------------------------------------------------------- road bridge

static func _road(c: Node3D, g: GxGeo, xf: Transform3D, W: float, zp: float, ze: float, soffit: float, opts: Dictionary) -> void:
	var A := _across()
	var gd := 1.05 # girder depth
	var slab_y := soffit + gd
	var deck := slab_y + 0.25
	var hx := W * 0.5
	g.col = CONC
	# slab, edge beams (fascia with drip chamfer) and the parapet upstands
	g.extrude_xf("concrete", _rect(0, slab_y + 0.125, hx - 0.3, 0.125), -ze, ze, A)
	for s: float in [-1.0, 1.0]:
		var fascia := PackedVector2Array([Vector2(-0.3, -0.62), Vector2(0.22, -0.62), Vector2(0.3, -0.5), Vector2(0.3, 0.55),
			Vector2(0.24, 0.62), Vector2(-0.3, 0.62)])
		for i in fascia.size():
			fascia[i] = Vector2(fascia[i].x * s + s * (hx - 0.3), fascia[i].y + slab_y + 0.08)
		if s < 0.0:
			fascia.reverse()
		g.extrude_xf("concrete", fascia, -ze, ze, A)
	# precast I-girders
	g.col = CONC_DARK
	for gx: float in [-2.9, -1.0, 1.0, 2.9]:
		var parts := [_rect(gx, soffit + 0.1, 0.32, 0.1, 0.03), _rect(gx, soffit + gd * 0.5, 0.09, gd * 0.5 - 0.15),
			_rect(gx, soffit + gd - 0.08, 0.42, 0.08, 0.02)]
		g.extrude_parts("concrete", parts, -ze + 0.4, ze - 0.4, A)
	# surfacing: asphalt carriageway + raised footways
	g.col = ASPHALT
	g.extrude_xf("rubber", _rect(0, deck - 0.05, hx - 1.6, 0.05), -ze, ze, A)
	g.col = CONC
	for s: float in [-1.0, 1.0]:
		g.extrude_xf("concrete", _rect(s * (hx - 0.95), deck + 0.05, 0.65, 0.15, 0.02), -ze, ze, A)
		_railing(g, s * (hx - 0.12), -ze, ze, slab_y + 0.7, 1.05)
	# white edge lines on the bridge road
	g.col = Color(0.85, 0.85, 0.82)
	for s: float in [-1.0, 1.0]:
		g.extrude_xf("rubber", _rect(s * (hx - 1.75), deck + 0.003, 0.06, 0.004), -ze, ze, A)
	# piers: two chamfered columns on a footing, hammerhead crosshead, bearings
	for s: float in [-1.0, 1.0]:
		var z := s * zp
		var gmin := _ground_min(c, xf, -hx, hx, z - 1.0, z + 1.0)
		g.col = CONC
		g.box("concrete", Vector3(0, soffit - 0.55, z), Vector3(W - 0.6, 0.9, 1.5), 0.08)
		g.col = CONC_DARK
		for gx: float in [-2.9, -1.0, 1.0, 2.9]:
			g.box("rubber", Vector3(gx, soffit - 0.06, z), Vector3(0.5, 0.12, 0.5)) # elastomeric bearings
		g.col = CONC
		for px: float in [-2.2, 2.2]:
			var y0 := gmin - 0.8
			var y1 := soffit - 1.0
			g.box("concrete", Vector3(px, (y0 + y1) * 0.5, z), Vector3(1.1, y1 - y0, 1.1), 0.14)
			g.collide(Vector3(px, (y0 + y1) * 0.5, z), Vector3(1.1, y1 - y0, 1.1))
		g.col = CONC_DARK
		g.box("concrete", Vector3(0, gmin + 0.1, z), Vector3(W - 0.4, 0.6, 2.4), 0.06) # footing just showing
		if opts.get("graffiti", true):
			var h: int = absi(hash(str(xf.origin)) + int(s))
			_spray(c, xf, Vector3(2.2 * s, gmin + 2.4, z - s * 0.555), Vector3(0, 0, -s), Vector2(1.0, 1.6), {tag = h % 2 == 0})
	# abutments + approach ramps (retained earth, concrete walls)
	var ramps: bool = opts.get("ramps", true)
	for s: float in [-1.0, 1.0]:
		var z := s * ze
		var gmin := _ground_min(c, xf, -hx - 0.6, hx + 0.6, z - 1.0, z + 1.0)
		g.col = CONC
		var y0 := gmin - 1.0
		g.box("concrete", Vector3(0, (y0 + deck) * 0.5, z + s * 0.7), Vector3(W + 1.2, deck - y0, 1.4), 0.05)
		g.collide(Vector3(0, (y0 + deck) * 0.5, z + s * 0.7), Vector3(W + 1.2, deck - y0, 1.4))
		if opts.get("graffiti", true):
			_spray(c, xf, Vector3(-s * 1.0, gmin + 2.4, z - 0.001 * s), Vector3(0, 0, -s), Vector2(6.0, 2.6), {})
		var h := deck - _ground(c, xf, 0.0, z + s * 4.0)
		if not ramps or h < 0.8:
			continue
		_ramp(c, g, xf, hx, z, s, deck, h, clampf(h * 3.2, 8.0, 40.0), "rubber", ASPHALT)
	# lamps, staggered, arms over the carriageway
	if opts.get("lamps", true):
		for s: float in [-1.0, 1.0]:
			for zz: float in [-ze * 0.55, ze * 0.55]:
				if signf(zz) == s:
					_lamp(g, Vector3(s * (hx - 0.55), deck + 0.2, zz), Vector3(-s, 0, 0))
	_banner(g, opts, hx + 0.32, slab_y + 0.08)


## Photo graffiti (gxart's GxGraffiti) on a wall at local p with outward normal n.
static func _spray(c: Node3D, xf: Transform3D, p: Vector3, n: Vector3, size: Vector2, opts: Dictionary) -> void:
	const GRAF := "res://scripts/track/gimmicks/gx_graffiti.gd"
	if not ResourceLoader.exists(GRAF):
		return
	var zax := -n.normalized()
	var xax := Vector3.UP.cross(zax).normalized()
	load(GRAF).spray(c, xf * Transform3D(Basis(xax, Vector3.UP, zax), p), size, opts)


static func _banner(g: GxGeo, opts: Dictionary, x: float, y: float) -> void:
	var key: String = opts.get("banner", "")
	if key == "":
		return
	for s: float in [-1.0, 1.0]:
		g.sign(Vector3(s * (x + 0.005), y, 0), Vector3(s, 0, 0), 9.6, 1.2, key)


# ---------------------------------------------------------------- railway bridge

static func _rail(c: Node3D, g: GxGeo, xf: Transform3D, W: float, zp: float, ze: float, soffit: float, opts: Dictionary) -> void:
	var A := _across()
	var paint: Color = opts.get("paint", Color(0.28, 0.33, 0.3))
	var gd := 1.9
	var hx := W * 0.5
	var top := soffit + gd
	# two riveted plate girders: web, flanges, angle stiffeners
	g.col = paint
	for s: float in [-1.0, 1.0]:
		var x := s * (hx - 0.25)
		g.extrude_parts("painted_metal", [_rect(x, soffit + gd * 0.5, 0.025, gd * 0.5 - 0.04), _rect(x, soffit + 0.02, 0.26, 0.025),
			_rect(x, top - 0.02, 0.26, 0.025)], -ze, ze, A)
		var n := int(ze * 2.0 / 1.4)
		for k in n + 1:
			var z := -ze + k * ze * 2.0 / n
			for f: float in [-1.0, 1.0]:
				g.box("painted_metal", Vector3(x + f * 0.07, soffit + gd * 0.5, z), Vector3(0.1, gd - 0.1, 0.06))
		# rust bleeding along the bottom flange
		g.col = Color(1, 1, 1)
		g.extrude_xf("rusty_metal", _rect(x, soffit + 0.065, 0.2, 0.02), -ze, ze, A)
		g.col = paint
	# cross girders + trough with ballast, sleepers and rails
	g.col = paint * 0.8
	g.extrude_xf("painted_metal", _rect(0, top - 0.75, hx - 0.3, 0.06), -ze, ze, A)
	g.col = Color(0.55, 0.5, 0.45)
	g.extrude_xf("concrete", PackedVector2Array([Vector2(-hx + 0.32, top - 0.7), Vector2(hx - 0.32, top - 0.7), Vector2(hx - 0.32, top - 0.3),
		Vector2(1.6, top - 0.12), Vector2(-1.6, top - 0.12), Vector2(-hx + 0.32, top - 0.3)]), -ze, ze, A)
	g.col = Color(0.36, 0.3, 0.25)
	var ns := int(ze * 2.0 / 0.65)
	for k in ns:
		g.box("wood", Vector3(0, top - 0.06, -ze + (k + 0.5) * ze * 2.0 / ns), Vector3(2.5, 0.14, 0.24), 0.01)
	g.col = Color.WHITE
	for rx: float in [-0.72, 0.72]:
		g.extrude_parts("steel", [_rect(rx, top + 0.02, 0.07, 0.012), _rect(rx, top + 0.08, 0.012, 0.05), _rect(rx, top + 0.14, 0.035, 0.018)], -ze, ze, A)
	# walkway handrail on the girder tops
	for s: float in [-1.0, 1.0]:
		_railing(g, s * (hx - 0.25), -ze, ze, top, 1.0)
	# catenary masts (H-section) with cantilever arms at both ends
	g.col = Color(0.5, 0.52, 0.5)
	for s: float in [-1.0, 1.0]:
		var z := s * (ze - 1.2)
		var mx := hx + 0.45
		g.extrude_parts("painted_metal", [_rect(0, 0, 0.1, 0.012), _rect(-0.09, 0, 0.012, 0.1), _rect(0.09, 0, 0.012, 0.1)], top - 1.0, top + 6.2,
			Transform3D(Basis(Vector3.UP, Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(mx, 0, z)))
		g.box("painted_metal", Vector3(mx - 0.3, top - 0.9, z), Vector3(0.7, 0.4, 0.5)) # bracket on the girder
		g.bar("steel", Vector3(mx, top + 5.6, z), Vector3(0.0, top + 5.4, z), 0.04)
		g.bar("steel", Vector3(mx, top + 4.6, z), Vector3(0.0, top + 5.25, z), 0.03)
		g.col = Color(0.75, 0.55, 0.4)
		g.lathe("props", Vector3(0.6, top + 5.0, z), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.02), Vector2(0.09, 0.32), Vector2(0.0, 0.34)]), 8) # insulator
		g.col = Color(0.5, 0.52, 0.5)
	g.col = Color(0.2, 0.2, 0.2)
	g.bar("steel", Vector3(0, top + 5.2, -ze - 2.0), Vector3(0, top + 5.2, ze + 2.0), 0.012, 4) # contact wire
	g.bar("steel", Vector3(0, top + 5.55, -ze - 2.0), Vector3(0, top + 5.55, ze + 2.0), 0.012, 4)
	_piers(c, g, xf, W, zp, ze, soffit, opts, true)
	# plaque on the girders
	for s: float in [-1.0, 1.0]:
		g.sign(Vector3(s * (hx + 0.06), soffit + gd * 0.55, 0), Vector3(s, 0, 0), 3.2, 0.0, opts.get("plaque", "p_rail"))
	_banner(g, opts, hx + 0.08, soffit - 0.0)
	if opts.get("train", true) and ResourceLoader.exists("res://scripts/track/gimmicks/gx_train.gd"):
		var topts: Dictionary = opts.duplicate()
		topts.soffit = soffit
		topts.ze = ze
		topts.W = W
		topts.top = top
		load("res://scripts/track/gimmicks/gx_train.gd").place(c, xf, topts)


## Concrete piers + abutments for the steel bridges.
static func _piers(c: Node3D, g: GxGeo, xf: Transform3D, W: float, zp: float, ze: float, soffit: float, _opts: Dictionary, abut: bool) -> void:
	var hx := W * 0.5
	for s: float in [-1.0, 1.0]:
		var z := s * zp
		var gmin := _ground_min(c, xf, -hx, hx, z - 1.0, z + 1.0)
		g.col = CONC
		g.box("concrete", Vector3(0, soffit - 0.45, z), Vector3(W + 0.6, 0.9, 1.6), 0.08)
		var y0 := gmin - 0.8
		var y1 := soffit - 0.9
		# tapered wall pier with rounded-off ends
		g.box("concrete", Vector3(0, (y0 + y1) * 0.5, z), Vector3(W - 0.4, y1 - y0, 1.2), 0.25)
		g.collide(Vector3(0, (y0 + y1) * 0.5, z), Vector3(W - 0.4, y1 - y0, 1.2))
		g.col = CONC_DARK
		g.box("concrete", Vector3(0, gmin + 0.1, z), Vector3(W + 0.8, 0.6, 2.2), 0.06)
		if abut:
			var za := s * (ze + 0.7)
			var ga := _ground_min(c, xf, -hx, hx, za - 1.0, za + 1.0) - 1.0
			g.col = CONC
			g.box("concrete", Vector3(0, (ga + soffit + 2.0) * 0.5, za), Vector3(W + 1.6, soffit + 2.0 - ga, 1.4), 0.05)
			g.collide(Vector3(0, (ga + soffit + 2.0) * 0.5, za), Vector3(W + 1.6, soffit + 2.0 - ga, 1.4))
			var top := soffit + 2.0
			var h := top - _ground(c, xf, 0.0, za + s * 4.0)
			if h > 0.8:
				_ramp(c, g, xf, hx + 0.8, za - s * 0.7, s, top, h, clampf(h * 1.6, 6.0, 24.0), "concrete", Color(0.42, 0.38, 0.33))


# ---------------------------------------------------------------- footbridge

static func _foot(c: Node3D, g: GxGeo, xf: Transform3D, W: float, zp: float, ze: float, soffit: float, opts: Dictionary) -> void:
	var A := _across()
	var paint: Color = opts.get("paint", Color(0.2, 0.3, 0.38))
	var hx := W * 0.5
	var deck := soffit + 0.45
	var th := 1.7 # truss height above deck
	g.col = CONC
	g.extrude_xf("concrete", _rect(0, soffit + 0.3, hx, 0.15, 0.03), -ze, ze, A)
	g.col = paint
	for s: float in [-1.0, 1.0]:
		var x := s * (hx + 0.05)
		# bottom & top chords (rectangular hollow sections), Warren diagonals, verticals
		g.extrude_xf("painted_metal", _rect(x, soffit + 0.15, 0.1, 0.15, 0.015), -ze, ze, A)
		g.extrude_xf("painted_metal", _rect(x, deck + th, 0.09, 0.09, 0.015), -ze, ze, A)
		var n := maxi(int(ze * 2.0 / 2.4), 2)
		for k in n:
			var za := -ze + k * ze * 2.0 / n
			var zb := -ze + (k + 1) * ze * 2.0 / n
			var lo := soffit + 0.28
			var hi := deck + th - 0.05
			if k % 2 == 0:
				g.beam("painted_metal", Vector3(x, lo, za), Vector3(x, hi, zb), 0.1)
			else:
				g.beam("painted_metal", Vector3(x, hi, za), Vector3(x, lo, zb), 0.1)
			g.beam("painted_metal", Vector3(x, lo, za), Vector3(x, hi, za), 0.08)
		# mesh infill (vertical bars) inside the truss
		g.col = Color(0.55, 0.57, 0.58)
		var bars := int(ze * 2.0 / 0.15)
		for k in bars:
			g.box("steel", Vector3(x - s * 0.06, deck + 0.6, -ze + (k + 0.5) * ze * 2.0 / bars), Vector3(0.015, 1.15, 0.015))
		g.col = paint
		g.box("painted_metal", Vector3(x - s * 0.06, deck + 1.18, 0), Vector3(0.05, 0.05, ze * 2.0))
	# top cross bracing (portal frames) at a few points
	for k in 5:
		var z := lerpf(-ze, ze, k / 4.0)
		g.beam("painted_metal", Vector3(-hx - 0.05, deck + th, z), Vector3(hx + 0.05, deck + th, z), 0.08)
	# slender steel column piers (round, on concrete pads)
	for s: float in [-1.0, 1.0]:
		var z := s * zp
		for px: float in [-hx + 0.3, hx - 0.3]:
			var gy := _ground(c, xf, px, z)
			g.col = paint
			g.lathe("painted_metal", Vector3(px, gy - 0.5, z), PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.2, soffit - gy + 0.5)]), 12)
			g.col = CONC
			g.box("concrete", Vector3(px, gy + 0.1, z), Vector3(0.9, 0.5, 0.9), 0.05)
			g.collide(Vector3(px, (gy + soffit) * 0.5, z), Vector3(0.45, soffit - gy, 0.45))
		g.col = paint
		g.box("painted_metal", Vector3(0, soffit - 0.15, z), Vector3(W + 0.2, 0.3, 0.35))
	# stair flights at both ends, running back along the track (-x), with a landing
	for s: float in [-1.0, 1.0]:
		var z := s * (ze + 0.9)
		g.col = CONC
		g.box("concrete", Vector3(0, deck - 0.15, z), Vector3(W, 0.3, 1.8), 0.02) # landing
		var gy := _ground_min(c, xf, -14.0, 0.0, z - 1.0, z + 1.0)
		var rise := deck - gy
		var steps := maxi(int(rise / 0.17), 3)
		var run := steps * 0.28
		var x0 := -hx
		g.col = paint
		for f: float in [-0.65, 0.65]:
			var a := Vector3(x0, deck - 0.2, z + f)
			var b := Vector3(x0 - run, gy + 0.1, z + f)
			g.beam("painted_metal", a, b, 0.08, 0.3)
			var rail_a := a + Vector3(0, 1.1, 0)
			var rail_b := b + Vector3(0, 1.1, 0)
			g.col = Color(0.6, 0.62, 0.63)
			g.tube("steel", [rail_a, rail_b], 0.035, 6)
			for k in int(run / 1.6) + 1:
				var t := float(k) / maxf(run / 1.6, 1.0)
				var p := a.lerp(b, minf(t, 1.0))
				g.box("steel", p + Vector3(0, 0.55, 0), Vector3(0.05, 1.1, 0.05))
			g.col = paint
		g.col = Color(0.6, 0.6, 0.58)
		for k in steps:
			var t := (k + 0.5) / steps
			g.box("concrete", Vector3(x0 - run * t, lerpf(deck - 0.2, gy + 0.1, t) + 0.05, z), Vector3(0.3, 0.06, 1.3))
		g.col = paint
		g.lathe("painted_metal", Vector3(x0 - run * 0.5, gy - 0.3, z), PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.12, (deck - gy) * 0.5 + 0.2)]), 8)
		g.collide(Vector3(x0 - run * 0.5, (gy + deck) * 0.5, z), Vector3(run, 0.4, 1.6), Basis(Vector3.BACK, -atan2(rise, run)))
	_banner(g, opts, hx + 0.16, soffit + 0.4 + 0.9)

## Approach ramp / embankment from the abutment at z (side s) down to the ground:
## retaining walls with coping and pilasters, `top_mat` surface.
static func _ramp(c: Node3D, g: GxGeo, xf: Transform3D, hx: float, z: float, s: float, deck: float, h: float, rl: float, top_mat: String, top_col: Color) -> void:
	var steps := maxi(int(rl / 2.0), 2)
	var z_start := z + s * 1.4
	for k in steps:
		var za := z_start + s * rl * k / steps
		var zb := z_start + s * rl * (k + 1) / steps
		var ya := lerpf(deck, deck - h, float(k) / steps)
		var yb := lerpf(deck, deck - h, float(k + 1) / steps)
		g.col = top_col
		g.quad_n(top_mat, Vector3(-hx + 0.35, ya, za), Vector3(hx - 0.35, ya, za), Vector3(hx - 0.35, yb, zb), Vector3(-hx + 0.35, yb, zb), Vector3.UP)
		for ws: float in [-1.0, 1.0]:
			var xo := ws * hx
			var xi := ws * (hx - 0.35)
			var ga := _ground(c, xf, xo, za) - 0.8
			var gb := _ground(c, xf, xo, zb) - 0.8
			var ta := ya + 0.85
			var tb := yb + 0.85
			g.col = CONC
			g.quad_n("concrete", Vector3(xo, ga, za), Vector3(xo, gb, zb), Vector3(xo, tb, zb), Vector3(xo, ta, za), Vector3(ws, 0, 0))
			g.quad_n("concrete", Vector3(xi, ya - 0.2, za), Vector3(xi, yb - 0.2, zb), Vector3(xi, tb, zb), Vector3(xi, ta, za), Vector3(-ws, 0, 0))
			g.col = CONC_DARK
			g.quad_n("concrete", Vector3(xo + ws * 0.05, ta, za), Vector3(xo + ws * 0.05, tb, zb), Vector3(xi - ws * 0.05, tb, zb), Vector3(xi - ws * 0.05, ta, za), Vector3.UP)
			g.quad_n("concrete", Vector3(xo + ws * 0.05, ta - 0.12, za), Vector3(xo + ws * 0.05, tb - 0.12, zb), Vector3(xo + ws * 0.05, tb, zb), Vector3(xo + ws * 0.05, ta, za), Vector3(ws, 0, 0))
			if k % 2 == 1:
				g.col = CONC * 0.97
				g.box("concrete", Vector3(xo + ws * 0.04, (ga + ta) * 0.5, za), Vector3(0.08, ta - ga - 0.15, 0.5))
			g.collide(Vector3((xo + xi) * 0.5, (minf(ga, gb) + maxf(ta, tb)) * 0.5, (za + zb) * 0.5), Vector3(0.35, maxf(ta, tb) - minf(ga, gb), absf(zb - za)))
		if k == steps - 1:
			var ge := _ground(c, xf, 0, zb) - 0.8
			g.col = CONC
			g.quad_n("concrete", Vector3(-hx, ge, zb), Vector3(hx, ge, zb), Vector3(hx, yb + 0.85, zb), Vector3(-hx, yb + 0.85, zb), Vector3(0, 0, s))
