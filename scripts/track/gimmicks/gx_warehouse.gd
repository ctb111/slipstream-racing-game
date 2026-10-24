class_name GxWarehouse
extends RefCounted
## Drive-through building the road runs straight through (Burnout style).
##
##   GxWarehouse.place(c, Gx.road_frame(c, 1200.0), {kind = "warehouse", length = 54.0})
##
## kind: "warehouse" (steel portal-frame hall, corrugated cladding, truss roof
##       with skylights, roller doors rolled up at both ends, racking, forklift,
##       pallets, oil stains), "barn" (timber barn, hay bales, tractor),
##       "tunnel" (concrete tunnel with rock portals, LED strips, jet fans).
## length: metres along the road (default 54; shortened or skipped when the
##       road curves or the gradient changes inside it).
## brick: true = brick plinth / walls instead of corrugated cladding (warehouse).
## The opening is 26 m wide (road 12 + kerbs + rails at 12.1 m off centre) and
## >= 6.5 m high. Walls collide; the hall's StaticBody is in group "echo" with
## meta sound_reflective = true (engine echo).
## Interior: own ReflectionProbe (dark interior ambient), emissive strips + at
## most 2 real lights; everything inside culls beyond ~140 m.

const HALF_IN := 17.0 # inner wall face, metres from the centreline
const DOOR_HALF := 13.0
const BAY := 6.0


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind: String = str(opts.get("kind", "warehouse"))
	var want := float(opts.get("length", 54.0 if kind != "tunnel" else 90.0))
	var fit := _fit(c, xf, want)
	if fit.is_empty():
		push_warning("GxWarehouse: road not straight enough at %s, skipped" % xf.origin)
		return
	var holder := Node3D.new()
	holder.name = "GxWarehouse_" + kind
	c.add_child(holder)
	var F: Transform3D = fit.xf
	var L: float = fit.length
	var rng := Gx.rng(c, "warehouse%d" % int(xf.origin.x * 7.0 + xf.origin.z))
	match kind:
		"barn":
			_hall(c, holder, F, L, rng, true, opts)
		"tunnel":
			_tunnel(c, holder, F, L, rng, opts)
		_:
			_hall(c, holder, F, L, rng, false, opts)
	# Keep the forest and grass out.
	var n := int(L / 12.0) + 1
	for i in n + 1:
		var p := F * Vector3(-L * 0.5 + L * i / n, 0, 0)
		Gx.reserve(c, p, HALF_IN + 8.0)


## Extra camera views for gx_test: approach, inside, racks, exit.
static func views(c: Node3D, xf: Transform3D, opts: Dictionary) -> Array:
	var along := Gx.curve(c).get_closest_offset(xf.origin) - float(c.get("start_offset"))
	var L := float(opts.get("length", 54.0 if str(opts.get("kind", "")) != "tunnel" else 90.0))
	var up := Vector3.UP
	var z := xf.basis.z
	var x := xf.basis.x
	return [
		["approach", Gx.centre(c, along - L * 0.5 - 30.0) + up * 1.2 - z * 2.0, Gx.centre(c, along) + up * 3.5],
		["inside", Gx.centre(c, along - L * 0.25) + up * 1.2 - z * 2.5, Gx.centre(c, along + L * 0.25) + up * 2.2],
		["racks", xf.origin - z * 4.0 - x * 6.0 + up * 1.6, xf.origin + x * 4.0 + z * 16.0 + up * 2.6],
		["exit", Gx.centre(c, along + L * 0.5 - 10.0) + up * 1.2 + z * 2.0, Gx.centre(c, along + L * 0.5 + 40.0) + up * 1.5],
	]


## Frame for the building: centred on the road, x along the (sloped) road, y up,
## z to the right; or {} if the road is too curved even at 24 m.
static func _fit(c: Node3D, xf: Transform3D, want: float) -> Dictionary:
	var cv := Gx.curve(c)
	var along := cv.get_closest_offset(xf.origin) - float(c.get("start_offset"))
	var L := snappedf(maxf(want, 24.0), BAY)
	while L >= 24.0:
		var p0 := Gx.centre(c, along - L * 0.5)
		var p1 := Gx.centre(c, along + L * 0.5)
		var flat := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
		var hl := flat.length()
		if hl > 1.0:
			var t := flat / hl
			var r := t.cross(Vector3.UP).normalized()
			var ok := true
			var s := -L * 0.5 - 6.0
			while s <= L * 0.5 + 6.0:
				var p := Gx.centre(c, along + s)
				var d := p - p0
				var u := d.dot(t) / hl # 0..1 along
				var lat := d.dot(r)
				var dy := d.y - (p1.y - p0.y) * u
				if absf(lat) > 1.3 or absf(dy) > 0.9:
					ok = false
					break
				s += 3.0
			if ok:
				var xa := (p1 - p0) / hl # horizontal unit + slope
				return {xf = Transform3D(Basis(xa, Vector3.UP, r), (p0 + p1) * 0.5), length = L}
		L -= BAY
	return {}


## Ground height in the building frame at local (x, z).
static func _gy(c: Node3D, F: Transform3D, x: float, z: float) -> float:
	var w := F * Vector3(x, 0, z)
	return Gx.ground(c, w) - w.y


# ===================================================================== hall

static func _hall(c: Node3D, holder: Node3D, F: Transform3D, L: float, rng: RandomNumberGenerator, barn: bool, opts: Dictionary) -> void:
	var W := HALF_IN
	var eave := 7.6 if barn else 9.0
	var ridge := 12.4 if barn else 11.6
	var door_h := 6.6 if barn else 7.2
	var hl := L * 0.5
	var brick := bool(opts.get("brick", false))
	var g := GxGeo.new(F) # exterior shell: weathered
	var gi := GxGeo.new(F) # interior: dry materials
	var clad := Color(0.42, 0.47, 0.5) if not barn else Color(0.62, 0.42, 0.3)
	if not barn:
		clad = [Color(0.42, 0.47, 0.5), Color(0.62, 0.62, 0.6), Color(0.33, 0.4, 0.36), Color(0.55, 0.3, 0.22)][rng.randi() % 4]
	var roof_y := func(z: float) -> float: return eave + (ridge - eave) * (1.0 - absf(z) / W)
	var wall_mat := "corrugated" if not barn else "wood"
	if brick:
		wall_mat = "brick"

	# ---- side walls
	var win_lo := 6.0
	var win_hi := 7.2
	for s: float in [-1.0, 1.0]:
		var zc: float = s * (W + 0.15)
		g.col = Color(0.8, 0.8, 0.78)
		g.box("concrete", Vector3(0, -0.35, zc), Vector3(L + 0.6, 2.5, 0.36), 0.02) # plinth
		g.col = clad if not brick else Color(1, 1, 1)
		if barn:
			# vertical boards with battens
			g.box("wood", Vector3(0, (0.9 + eave) * 0.5, zc), Vector3(L, eave - 0.9, 0.12))
			var nb := int(L / 0.6)
			g.col = clad * 0.8
			for i in nb + 1:
				var x := -hl + i * L / nb
				g.box("wood", Vector3(x, (0.9 + eave) * 0.5, zc + s * 0.08), Vector3(0.07, eave - 0.9, 0.04))
		else:
			g.box(wall_mat, Vector3(0, (0.9 + win_lo) * 0.5, zc), Vector3(L, win_lo - 0.9, 0.14))
			g.box(wall_mat, Vector3(0, (win_hi + eave + 0.3) * 0.5, zc), Vector3(L, eave + 0.3 - win_hi, 0.14))
			# window band: glass + mullions + sills
			g.col = Color(0.55, 0.6, 0.62)
			g.box("glass", Vector3(0, (win_lo + win_hi) * 0.5, zc), Vector3(L, win_hi - win_lo, 0.04))
			g.col = Color(0.25, 0.26, 0.27)
			var nm := int(L / 1.5)
			for i in nm + 1:
				g.box("painted_metal", Vector3(-hl + i * L / nm, (win_lo + win_hi) * 0.5, zc), Vector3(0.06, win_hi - win_lo, 0.1))
			for y: float in [win_lo, win_hi]:
				g.box("painted_metal", Vector3(0, y, zc + s * 0.06), Vector3(L, 0.08, 0.16))
			# corner flashing + gutter + downpipes
			g.col = clad * 0.7
			g.box("painted_metal", Vector3(0, eave + 0.15, s * (W + 0.75)), Vector3(L + 1.2, 0.22, 0.22), 0.02)
			for x: float in [-hl + 0.4, 0.0, hl - 0.4]:
				g.tube("painted_metal", [Vector3(x, eave + 0.1, s * (W + 0.75)), Vector3(x, eave - 0.3, s * (W + 0.4)), Vector3(x, 0.2, s * (W + 0.4)), Vector3(x + 0.25, -0.05, s * (W + 0.55))], 0.07, 8)
		# columns (interior face) + wall girts
		gi.col = Color(0.5, 0.52, 0.55) if not barn else Color(0.55, 0.42, 0.3)
		var nbay := int(round(L / BAY))
		for i in nbay + 1:
			var x := -hl + i * L / nbay
			var zi: float = s * (W - 0.22)
			if barn:
				gi.box("in_wood", Vector3(x, eave * 0.5, zi), Vector3(0.3, eave, 0.3), 0.03)
				gi.beam("in_wood", Vector3(x, eave - 1.6, zi), Vector3(x + (1.4 if i < nbay else -1.4), eave - 0.1, zi), 0.16)
			else:
				_ibeam_v(gi, "in_painted_metal", Vector3(x, 0, zi), eave, s)
				gi.col = Color(0.3, 0.3, 0.3)
				gi.box("in_concrete", Vector3(x, 0.1, zi), Vector3(0.7, 0.2, 0.7), 0.03) # footing
				gi.col = Color(0.5, 0.52, 0.55)
		if not barn:
			for y: float in [3.0, win_lo - 0.1, win_hi + 0.1]:
				gi.box("in_painted_metal", Vector3(0, y, s * (W - 0.02)), Vector3(L, 0.18, 0.06))
		else:
			gi.box("in_wood", Vector3(0, 3.2, s * (W - 0.05)), Vector3(L, 0.2, 0.1))

	# ---- trusses / rafters + purlins
	var nbay2 := int(round(L / BAY))
	for i in nbay2 + 1:
		var x := -hl + i * L / nbay2
		if absf(x) > hl - 0.1:
			x = signf(x) * (hl - 0.35)
		if barn:
			_timber_truss(gi, x, W, eave, ridge)
		else:
			_steel_truss(gi, x, W, eave, ridge)
	# purlins
	gi.col = Color(0.5, 0.52, 0.55) if not barn else Color(0.5, 0.38, 0.27)
	var np := 7
	for s: float in [-1.0, 1.0]:
		for k in np:
			var z: float = s * (0.6 + k * (W - 0.6) / (np - 1))
			gi.box("in_painted_metal" if not barn else "in_wood", Vector3(0, roof_y.call(z) - 0.12, z), Vector3(L, 0.2, 0.08 if not barn else 0.14))

	# ---- roof sheets with skylights (warehouse) / plain (barn)
	var pitch := atan2(ridge - eave, W)
	var ov := 0.7
	for s: float in [-1.0, 1.0]:
		var rot := Basis(Vector3.RIGHT, pitch * s)
		var span := W + ov
		var zc: float = s * span * 0.5
		var yc: float = roof_y.call(zc) + 0.05
		g.col = clad * 0.9 if not barn else Color(0.55, 0.45, 0.4)
		var rmat := "corrugated" if not barn else "rusty_metal"
		if barn:
			g.box(rmat, Vector3(0, yc, zc), Vector3(L + 1.0, 0.06, span / cos(pitch)), 0.0, rot)
		else:
			# skylight strips in every other bay, between 30% and 70% of the slope
			var bw := L / nbay2
			for i in nbay2:
				var x0 := -hl + i * bw
				var xm := x0 + bw * 0.5
				var ext := 0.5 if i == 0 or i == nbay2 - 1 else 0.0
				var xc := xm - (ext if i == 0 else 0.0) + (ext if i == nbay2 - 1 else 0.0)
				var wx := bw + ext
				if i % 2 == 1:
					var a := 0.3
					var b2 := 0.7
					for part in [[0.0, a], [b2, 1.0]]:
						var za: float = s * span * part[0]
						var zb: float = s * span * part[1]
						var zm := (za + zb) * 0.5
						g.box(rmat, Vector3(xc, roof_y.call(zm) + 0.05 - (ov * (ridge - eave) / W if absf(zb) > W else 0.0) * 0.0, zm), Vector3(wx, 0.06, absf(zb - za) / cos(pitch)), 0.0, rot)
					var zs1: float = s * span * a
					var zs2: float = s * span * b2
					var zsm := (zs1 + zs2) * 0.5
					gi.col = Color(1, 1, 1)
					gi.box("sky", Vector3(xc, roof_y.call(zsm) + 0.05, zsm), Vector3(wx - 0.3, 0.03, absf(zs2 - zs1) / cos(pitch)), 0.0, rot)
					gi.col = Color(0.5, 0.52, 0.55)
				else:
					g.box(rmat, Vector3(xc, yc, zc), Vector3(wx, 0.06, span / cos(pitch)), 0.0, rot)
	g.col = Color(0.3, 0.3, 0.3)
	g.box("painted_metal", Vector3(0, ridge + 0.12, 0), Vector3(L + 1.0, 0.12, 0.6), 0.03) # ridge cap

	# ---- gable ends with the door openings
	for e: float in [-1.0, 1.0]:
		var xw: float = e * (hl + 0.1)
		g.col = clad if not brick else Color(1, 1, 1)
		for s: float in [-1.0, 1.0]:
			var za: float = s * DOOR_HALF
			var zb: float = s * (W + 0.3)
			var zm := (za + zb) * 0.5
			g.col = Color(0.8, 0.8, 0.78)
			g.box("concrete", Vector3(xw, -0.35, zm), Vector3(0.36, 2.5, absf(zb - za)), 0.02)
			g.col = clad if not brick else Color(1, 1, 1)
			g.box(wall_mat, Vector3(xw, (0.9 + eave) * 0.5, zm), Vector3(0.14, eave - 0.9, absf(zb - za)))
		g.box(wall_mat, Vector3(xw, (door_h + 1.3 + eave) * 0.5, 0), Vector3(0.14, eave - door_h - 1.3, DOOR_HALF * 2.0 + 0.1))
		# gable triangle (both faces)
		for f: float in [-0.07, 0.07]:
			var xf2: float = xw + f
			var A := Vector3(xf2, eave, -W - 0.3)
			var B := Vector3(xf2, eave, W + 0.3)
			var C := Vector3(xf2, ridge + 0.05, 0)
			if (f > 0.0) == (e > 0.0):
				g.tri(wall_mat, A, C, B)
			else:
				g.tri(wall_mat, A, B, C)
		# door: header box, rolled curtain drum, guides, bottom rail
		g.col = Color(0.75, 0.75, 0.72) if not barn else Color(0.45, 0.33, 0.22)
		if not barn:
			g.box("painted_metal", Vector3(xw - e * 0.45, door_h + 0.65, 0), Vector3(0.75, 1.3, DOOR_HALF * 2.0 + 0.6), 0.04) # drum housing
			g.col = Color(0.55, 0.57, 0.58)
			g.box("corrugated", Vector3(xw - e * 0.12, door_h + 0.05, 0), Vector3(0.05, 0.25, DOOR_HALF * 2.0), 0.0) # last slats
			g.col = Color(0.06, 0.06, 0.06)
			g.box("rubber", Vector3(xw - e * 0.12, door_h - 0.1, 0), Vector3(0.1, 0.08, DOOR_HALF * 2.0), 0.02)
			g.col = Color(0.35, 0.36, 0.37)
			for s: float in [-1.0, 1.0]:
				g.box("painted_metal", Vector3(xw - e * 0.12, (door_h + 0.6) * 0.5, s * (DOOR_HALF + 0.08)), Vector3(0.22, door_h + 0.6, 0.16), 0.01)
		else:
			# sliding barn doors pushed open along the outside of the gable
			for s: float in [-1.0, 1.0]:
				var zd: float = s * (DOOR_HALF + 3.4)
				g.col = Color(0.5, 0.25, 0.18)
				g.box("painted_wood", Vector3(xw + e * 0.2, door_h * 0.5 + 0.1, zd), Vector3(0.1, door_h, 6.6))
				g.col = Color(0.85, 0.82, 0.75)
				for d: float in [-1.0, 1.0]: # white X bracing
					var p0 := Vector3(xw + e * 0.27, 0.4, zd - 3.1)
					var p1 := Vector3(xw + e * 0.27, door_h - 0.2, zd + 3.1)
					if d > 0.0:
						p0 = Vector3(xw + e * 0.27, 0.4, zd + 3.1)
						p1 = Vector3(xw + e * 0.27, door_h - 0.2, zd - 3.1)
					g.beam("painted_wood", p0, p1, 0.18, 0.05)
				g.box("painted_wood", Vector3(xw + e * 0.27, door_h * 0.5 + 0.1, zd), Vector3(0.05, door_h, 0.2))
				g.col = Color(0.15, 0.15, 0.15)
				g.box("steel", Vector3(xw + e * 0.3, door_h + 0.35, s * (DOOR_HALF + 3.0)), Vector3(0.12, 0.12, 7.6)) # rail
		# door frame trim
		g.col = Color(0.85, 0.65, 0.1) if not barn else Color(0.4, 0.3, 0.2)
		for s: float in [-1.0, 1.0]:
			g.box("painted_metal" if not barn else "wood", Vector3(xw + e * 0.12, door_h * 0.5, s * (DOOR_HALF + 0.12)), Vector3(0.1, door_h, 0.24))
		g.box("painted_metal" if not barn else "wood", Vector3(xw + e * 0.12, door_h + 0.1, 0), Vector3(0.1, 0.24, DOOR_HALF * 2.0 + 0.5))
		# striped bollards protecting the jambs
		if not barn:
			for s: float in [-1.0, 1.0]:
				for k in 2:
					var bp := Vector3(xw + e * (0.5 + k * 0.0), 0, s * (DOOR_HALF - 0.25))
					if k == 1:
						bp = Vector3(xw - e * 0.6, 0, s * (DOOR_HALF - 0.25))
					var gy := _gy(c, F, bp.x, bp.z)
					for st in 5:
						g.col = Color(0.9, 0.7, 0.05) if st % 2 == 0 else Color(0.05, 0.05, 0.05)
						g.tube("painted_metal", [bp + Vector3(0, gy + st * 0.26, 0), bp + Vector3(0, gy + (st + 1) * 0.26, 0)], 0.11, 10, st == 4)
		# sign over the door
		var lab := Label3D.new()
		lab.text = ["HALLE 3", "LOGISTIK NORD", "KRONEN SPEDITION", "LAGER B", "VALTER TRANSPORT"][rng.randi() % 5] if not barn else ["HOF LINDNER", "GUT ROSENAU", ""][rng.randi() % 3]
		lab.font_size = 160
		lab.pixel_size = 0.01
		lab.outline_size = 0
		lab.modulate = Color(0.92, 0.92, 0.88) if not barn else Color(0.9, 0.86, 0.76)
		lab.shaded = true
		lab.double_sided = false
		lab.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5 * e).orthonormalized(), Vector3(xw + e * 0.09, eave + 0.8, 0))
		lab.transform = F * lab.transform
		lab.transform.basis = lab.transform.basis.orthonormalized()
		lab.visibility_range_end = 350.0
		holder.add_child(lab)

	# ---- floor slabs (dry, inside) left and right of the kerbs
	var road_edge := Gx.half_width() + 1.15
	gi.col = Color(0.95, 0.94, 0.9)
	for s: float in [-1.0, 1.0]:
		var nseg := int(L / 6.0)
		for i in nseg:
			var x0 := -hl + i * L / nseg
			var x1 := x0 + L / nseg
			var ymax := 0.0
			for xx: float in [x0, x1]:
				for zz: float in [road_edge, W]:
					ymax = maxf(ymax, _gy(c, F, xx, s * zz))
			var top := minf(ymax, 0.6) + 0.04
			var zm: float = s * (road_edge + W) * 0.5
			gi.box("in_concrete", Vector3((x0 + x1) * 0.5, top - 0.6, zm), Vector3(L / nseg + 0.02, 1.2, W - road_edge))
		# yellow walkway lines beyond the rails
		gi.col = Color(1, 1, 1)
		for zl: float in [12.9, 13.5]:
			gi.box("yellow", Vector3(0, _gy(c, F, 0, s * zl) * 0.0 + 0.055 + minf(maxf(_gy(c, F, 0, s * zl), 0.0), 0.6), s * zl), Vector3(L - 1.0, 0.012, 0.12))
		gi.col = Color(1, 1, 1)

	# ---- interior contents along both walls (keep z >= 12.9: the rails are at 12.1)
	var floor_at := func(x: float, z: float) -> float: return minf(maxf(_gy(c, F, x, z), 0.0), 0.6) + 0.04
	var crates_xf: Array = []
	var crate2_xf: Array = []
	var barrel_xf: Array = []
	var barrel3_xf: Array = []
	var shelf_xf: Array = []
	var tyre_xf: Array = []
	var propane_xf: Array = []
	var cardboard_xf: Array = []
	var truck_xf: Array = []
	var util_xf: Array = []
	var lamp_xf: Array = []
	var bulk := F.basis.orthonormalized()
	var W2 := func(p: Vector3, yaw: float) -> Transform3D: return Transform3D(bulk * Basis(Vector3.UP, yaw), F * p)
	for s: float in [-1.0, 1.0]:
		var x := -hl + 2.0
		var slot := 0
		while x < hl - 3.0:
			var kind := rng.randi() % 6 if not barn else rng.randi() % 5
			var y0: float = floor_at.call(x, s * 15.0)
			if not barn and kind <= 1:
				# pallet racking bay (2.7 m): blue uprights, orange beams, loads
				var zr: float = s * (W - 0.75)
				_rack(gi, Vector3(x + 1.35, y0, zr), rng)
				x += 2.9
			elif kind == 2:
				# pallet stack + crates/barrels in front
				var hgt := rng.randi_range(4, 11) if not barn else 0
				for k in hgt:
					GxProps.pallet(gi, Vector3(x + 0.7, y0 + k * 0.145, s * (W - 1.0)), rng.randf_range(-0.03, 0.03))
				if barn:
					GxProps.round_bale(gi, Vector3(x + 0.8, y0 + 0.75, s * (W - 1.1)), Vector3(0, 0, 1))
					GxProps.round_bale(gi, Vector3(x + 2.4, y0 + 0.75, s * (W - 1.1)), Vector3(0, 0, 1))
					GxProps.round_bale(gi, Vector3(x + 1.6, y0 + 2.05, s * (W - 1.1)), Vector3(0, 0, 1))
					x += 3.4
				else:
					barrel_xf.append(W2.call(Vector3(x + 1.9, y0, s * (W - 0.7)), rng.randf() * TAU))
					barrel_xf.append(W2.call(Vector3(x + 2.5, y0, s * (W - 0.75)), rng.randf() * TAU))
					barrel3_xf.append(W2.call(Vector3(x + 2.2, y0, s * (W - 1.35)), rng.randf() * TAU))
					x += 3.2
			elif kind == 3:
				if barn:
					# small bale stack
					for l in 4:
						for k in (4 - l):
							GxProps.square_bale(gi, Vector3(x + 0.6 + k * 0.95 + l * 0.47, y0 + 0.18 + l * 0.36, s * (W - 0.7)), Vector3(0.92, 0.36, 0.46))
							GxProps.square_bale(gi, Vector3(x + 0.6 + k * 0.95 + l * 0.47, y0 + 0.18 + l * 0.36, s * (W - 1.2)), Vector3(0.92, 0.36, 0.46))
					x += 4.2
				else:
					# floor pallets with loads + crates
					GxProps.pallet_load(gi, Vector3(x + 0.7, y0, s * (W - 1.0)), PI * 0.5 + rng.randf_range(-0.06, 0.06), rng)
					GxProps.pallet_load(gi, Vector3(x + 1.65, y0, s * (W - 1.0)), PI * 0.5 + rng.randf_range(-0.06, 0.06), rng)
					crates_xf.append(W2.call(Vector3(x + 1.2, y0, s * (W - 2.2)), rng.randf_range(-0.3, 0.3)))
					crate2_xf.append(W2.call(Vector3(x + 2.6, y0, s * (W - 1.0)), PI * 0.5))
					cardboard_xf.append(W2.call(Vector3(x + 2.0, y0, s * (W - 2.3)), rng.randf() * TAU))
					x += 3.3
			elif kind == 4:
				# workshop corner: shelves, tyres, propane, toolbox, power box
				var yaw := 0.0 if s > 0 else PI
				shelf_xf.append(W2.call(Vector3(x + 0.6, y0, s * (W - 0.3)), yaw))
				shelf_xf.append(W2.call(Vector3(x + 1.75, y0, s * (W - 0.3)), yaw))
				util_xf.append(W2.call(Vector3(x + 2.8, y0 + 0.0, s * (W - 0.25)), yaw))
				for k in rng.randi_range(2, 5):
					tyre_xf.append(W2.call(Vector3(x + 3.6, y0 + 0.08 + k * 0.165, s * (W - 0.9)), rng.randf() * TAU) * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
				propane_xf.append(W2.call(Vector3(x + 1.0, y0, s * (W - 1.2)), rng.randf() * TAU))
				truck_xf.append(W2.call(Vector3(x + 2.3, y0, s * (W - 1.3)), rng.randf_range(-0.6, 0.6)))
				x += 4.4
			else:
				# vehicle: forklift (warehouse) / tractor (barn), parked along the wall
				if barn:
					GxProps.tractor(gi, Transform3D(Basis(Vector3.UP, 0.0 if rng.randf() < 0.5 else PI), Vector3(x + 2.4, y0, s * (W - 1.8))),
						[Color(0.13, 0.36, 0.14), Color(0.62, 0.12, 0.08), Color(0.12, 0.22, 0.45)][rng.randi() % 3])
					x += 5.5
				else:
					GxProps.forklift(gi, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25) + (0.0 if rng.randf() < 0.5 else PI)), Vector3(x + 2.0, y0, s * (W - 2.3))),
						[Color(0.86, 0.6, 0.08), Color(0.75, 0.15, 0.08), Color(0.9, 0.42, 0.05)][rng.randi() % 3], 0.15)
					GxProps.pallet_load(gi, Vector3(x + 4.1, y0, s * (W - 2.3)), rng.randf_range(-0.2, 0.2), rng)
					x += 5.0
			slot += 1
			x += 0.3
		# lamps hanging under the trusses over the side areas
		for i in nbay2 + 1:
			var xl := -hl + i * L / nbay2
			if absf(xl) > hl - 1.0:
				continue
			lamp_xf.append(W2.call(Vector3(xl + 0.5, eave - 2.6, s * 9.5), 0.0))
	# fluorescent battens running along the road under the bottom chords
	gi.col = Color(1, 1, 1)
	var batt_y := eave - 0.75
	for s: float in [-1.0, 1.0]:
		for i in nbay2:
			var xa := -hl + i * L / nbay2 + 0.6
			var xb := -hl + (i + 1) * L / nbay2 - 0.6
			var zb: float = s * 4.0
			gi.col = Color(0.3, 0.3, 0.3)
			gi.box("in_steel", Vector3((xa + xb) * 0.5, batt_y + 0.14, zb), Vector3(xb - xa, 0.04, 0.05)) # trunking
			for f in 2: # two 1.5 m fittings per bay
				var fx := lerpf(xa, xb, 0.27 + f * 0.46)
				gi.col = Color(0.3, 0.3, 0.3)
				gi.box("in_painted_metal", Vector3(fx, batt_y + 0.06, zb), Vector3(1.55, 0.1, 0.26), 0.02)
				gi.col = Color(1, 1, 1)
				gi.box("emit" if not barn else "emit_warm", Vector3(fx, batt_y, zb), Vector3(1.45, 0.03, 0.18))
			for xx: float in [xa + 0.4, xb - 0.4]: # suspension wires
				gi.bar("in_steel", Vector3(xx, batt_y + 0.1, zb), Vector3(xx, eave - 0.45, zb), 0.006, 3)

	var body_e := GxProps.commit(g, holder, "WhShell", 900.0, true)
	var body_i := GxProps.commit(gi, holder, "WhInside", 160.0, false)
	for mi in holder.get_children():
		if mi is MeshInstance3D and String(mi.name).begins_with("WhInside"):
			# the interior's big structure still reads from outside through the doors
			(mi as MeshInstance3D).visibility_range_end = 300.0
			(mi as MeshInstance3D).visibility_range_end_margin = 40.0 # dissolves, never pops
			(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if body_i:
		body_i.queue_free()
	# models (one MultiMesh each)
	GxProps.scatter(holder, "wooden_crate_01", crates_xf, 130.0)
	GxProps.scatter(holder, "wooden_crate_02", crate2_xf, 130.0)
	GxProps.scatter(holder, "Barrel_01", barrel_xf, 130.0)
	GxProps.scatter(holder, "barrel_03", barrel3_xf, 130.0)
	GxProps.scatter(holder, "steel_frame_shelves_01", shelf_xf, 110.0)
	GxProps.scatter(holder, "old_tyre", tyre_xf, 110.0)
	GxProps.scatter(holder, "propane_tank", propane_xf, 100.0)
	GxProps.scatter(holder, "cardboard_box_01", cardboard_xf, 100.0)
	GxProps.scatter(holder, "hand_truck", truck_xf, 100.0)
	GxProps.scatter(holder, "utility_box_01", util_xf, 110.0)
	GxProps.scatter(holder, "hanging_industrial_lamp", lamp_xf, 160.0)
	# exterior floodlights over the doors
	var flood: Array = []
	for e: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			flood.append(W2.call(Vector3(e * (hl + 0.25), door_h + 1.0, s * (DOOR_HALF + 1.5)), PI * 0.5 * (1.0 - e)))
	GxProps.scatter(holder, "security_light", flood, 300.0)
	if Car.night: # glowing lamp faces on the floodlights
		var gf := GxGeo.new(F)
		for e: float in [-1.0, 1.0]:
			for s: float in [-1.0, 1.0]:
				gf.box("emit_warm", Vector3(e * (hl + 0.55), door_h + 0.85, s * (DOOR_HALF + 1.5)), Vector3(0.05, 0.22, 0.3))
		GxProps.commit(gf, holder, "WhFlood", 400.0, false)

	# ---- collision: walls (orthonormal boxes), echo tag
	var body := StaticBody3D.new()
	body.name = "WarehouseWalls"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.2
	body.physics_material_override = pm
	body.add_to_group("echo")
	body.set_meta("sound_reflective", true)
	body.set_meta("echo_kind", "barn" if barn else "warehouse")
	var ob := F.basis.orthonormalized()
	var add_box := func(cen: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(ob, F * cen)
		body.add_child(cs)
	for s: float in [-1.0, 1.0]:
		add_box.call(Vector3(0, eave * 0.5, s * (W + 0.15)), Vector3(L, eave + 2.0, 0.6))
		# props zone: a low invisible kerb wall at the racks so cars glance off
		add_box.call(Vector3(0, 0.6, s * (W - 3.2)), Vector3(L - 2.0, 1.6, 0.4))
		for e: float in [-1.0, 1.0]:
			var zm: float = s * (DOOR_HALF + W + 0.3) * 0.5
			add_box.call(Vector3(e * (hl + 0.1), eave * 0.5, zm), Vector3(0.6, eave + 2.0, W + 0.3 - DOOR_HALF))
	add_box.call(Vector3(0, ridge + 1.0, 0), Vector3(L, 0.5, W * 2.0)) # roof (nothing gets up there anyway)
	holder.add_child(body)
	if body_e:
		body_e.add_to_group("echo")
		body_e.set_meta("sound_reflective", true)

	# ---- interior lighting: ReflectionProbe (dark ambient + interior reflections), 2 lights
	var probe := ReflectionProbe.new()
	probe.size = Vector3(L - 0.5, ridge + 1.0, W * 2.0 - 0.4)
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.32, 0.31, 0.29) if not barn else Color(0.34, 0.29, 0.22)
	probe.ambient_color_energy = 0.35 if not Car.night else 0.3
	probe.blend_distance = 3.0
	probe.max_distance = 60.0
	probe.box_projection = true
	probe.transform = Transform3D(ob, F * Vector3(0, (ridge + 1.0) * 0.5 - 0.2, 0))
	probe.cull_mask = 0xFFFFF
	holder.add_child(probe)
	for k in 2:
		var om := OmniLight3D.new()
		om.light_color = Color(0.9, 0.95, 1.0) if not barn else Color(1.0, 0.8, 0.55)
		om.light_energy = 8.0 if Car.night else 1.2
		om.omni_range = maxf(L * 0.62, 24.0)
		om.omni_attenuation = 1.2
		om.shadow_enabled = false
		om.light_specular = 0.6
		om.distance_fade_enabled = true
		om.distance_fade_begin = 120.0
		om.distance_fade_length = 30.0
		om.position = F * Vector3((k - 0.5) * L * 0.5, eave - 1.5, 0)
		holder.add_child(om)

	# ---- oil stains
	_oil_stains(holder, F, L, rng, 9 if not barn else 4)
	# ---- rain / snow stop at the roof
	_precip_block(holder, F, L, ridge, W)


## Vertical I-beam column at local p (base), height h; flanges face the road.
static func _ibeam_v(g: GxGeo, mat: String, p: Vector3, h: float, s: float) -> void:
	g.box(mat, p + Vector3(0, h * 0.5, 0), Vector3(0.012 * 2.0, h, 0.36))
	for f: float in [-0.17, 0.17]:
		g.box(mat, p + Vector3(0, h * 0.5, f), Vector3(0.3, h, 0.024))
	g.box(mat, p + Vector3(0, h - 0.4, -s * 0.3), Vector3(0.024, 0.6, 0.3)) # haunch


static func _steel_truss(g: GxGeo, x: float, W: float, eave: float, ridge: float) -> void:
	var prev := g.col
	g.col = Color(0.5, 0.52, 0.55)
	var bot := eave - 0.55
	var top := func(z: float) -> float: return eave + (ridge - eave) * (1.0 - absf(z) / W) - 0.3
	g.beam("in_painted_metal", Vector3(x, bot, -W + 0.25), Vector3(x, bot, W - 0.25), 0.16, 0.14)
	for s: float in [-1.0, 1.0]:
		g.beam("in_painted_metal", Vector3(x, top.call(s * (W - 0.25)), s * (W - 0.25)), Vector3(x, top.call(0.0), 0.0), 0.18, 0.18)
		var n := 7
		for k in n:
			var za: float = s * (W - 0.25) * (1.0 - float(k) / n)
			var zb: float = s * (W - 0.25) * (1.0 - float(k + 1) / n)
			g.beam("in_painted_metal", Vector3(x, bot, za), Vector3(x, top.call(za), za), 0.07)
			g.beam("in_painted_metal", Vector3(x, bot, za), Vector3(x, top.call(zb), zb), 0.07)
	g.beam("in_painted_metal", Vector3(x, bot, 0), Vector3(x, top.call(0.0), 0), 0.08)
	g.col = prev


static func _timber_truss(g: GxGeo, x: float, W: float, eave: float, ridge: float) -> void:
	var prev := g.col
	g.col = Color(0.55, 0.42, 0.3)
	var top := func(z: float) -> float: return eave + (ridge - eave) * (1.0 - absf(z) / W) - 0.25
	g.beam("in_wood", Vector3(x, eave - 0.1, -W + 0.1), Vector3(x, eave - 0.1, W - 0.1), 0.26, 0.3)
	for s: float in [-1.0, 1.0]:
		g.beam("in_wood", Vector3(x, top.call(s * W), s * W), Vector3(x, top.call(0.0), 0), 0.26, 0.3)
		g.beam("in_wood", Vector3(x, eave - 0.1, s * W * 0.5), Vector3(x, top.call(s * W * 0.5), s * W * 0.5), 0.18)
		g.beam("in_wood", Vector3(x, eave - 0.1, s * W * 0.5), Vector3(x, top.call(0.0) - 0.4, 0), 0.18)
	g.beam("in_wood", Vector3(x, eave - 0.1, 0), Vector3(x, top.call(0.0), 0), 0.24) # king post
	g.col = prev


## One 2.7 m pallet-rack bay with three beam levels of loads, against the wall.
static func _rack(g: GxGeo, p: Vector3, rng: RandomNumberGenerator) -> void:
	var prev := g.col
	var h := 6.2
	var levels := [0.0, 1.85, 3.6, 5.3]
	g.col = Color(0.12, 0.25, 0.55)
	for dx: float in [-1.38, 1.38]:
		for dz: float in [-0.5, 0.5]:
			g.box("in_painted_metal", p + Vector3(dx, h * 0.5, dz), Vector3(0.09, h, 0.07))
		for k in 7: # frame bracing
			var y0 := 0.3 + k * 0.85
			g.beam("in_painted_metal", p + Vector3(dx, y0, -0.47), p + Vector3(dx, y0 + 0.85, 0.47), 0.03)
		g.col = Color(0.12, 0.25, 0.55)
	for li in levels.size():
		var y: float = levels[li]
		if li > 0:
			g.col = Color(0.85, 0.35, 0.06)
			for dz: float in [-0.5, 0.5]:
				g.box("in_painted_metal", p + Vector3(0, y - 0.07, dz), Vector3(2.7, 0.12, 0.05))
		if li < levels.size() - 1 or rng.randf() < 0.6:
			for k in 2:
				if rng.randf() < 0.15:
					continue
				var pp := p + Vector3((k - 0.5) * 1.3, y + (0.0 if li == 0 else 0.0), 0)
				GxProps.pallet_load(g, pp, PI * 0.5, rng, 1.35)
	g.col = prev


static var _oil_tex: Texture2D


static func _oil_stains(holder: Node3D, F: Transform3D, L: float, rng: RandomNumberGenerator, n: int) -> void:
	if _oil_tex == null:
		var sz := 128
		var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
		var nz := FastNoiseLite.new()
		nz.frequency = 0.045
		nz.fractal_octaves = 4
		for y in sz:
			for x in sz:
				var d := Vector2(x - sz * 0.5, y - sz * 0.5).length() / (sz * 0.5)
				var v := nz.get_noise_2d(x, y) * 0.6 + 0.5
				var a := clampf((1.0 - d) * 1.6 + (v - 0.5) * 1.4 - 0.2, 0.0, 1.0)
				a *= clampf(v * 1.2, 0.2, 1.0)
				img.set_pixel(x, y, Color(0.02, 0.018, 0.015, a * 0.85))
		_oil_tex = ImageTexture.create_from_image(img)
	var ob := F.basis.orthonormalized()
	for i in n:
		var d := Decal.new()
		d.texture_albedo = _oil_tex
		var s := rng.randf_range(1.0, 2.6)
		d.size = Vector3(s, 0.6, s * rng.randf_range(0.6, 1.0))
		d.upper_fade = 0.2
		d.lower_fade = 0.2
		d.albedo_mix = 0.85
		d.distance_fade_enabled = true
		d.distance_fade_begin = 70.0
		d.distance_fade_length = 20.0
		var z := signf(rng.randf() - 0.5) * rng.randf_range(8.6, 15.5) # off the tarmac (road decals own it)
		var x := rng.randf_range(-L * 0.45, L * 0.45)
		d.transform = Transform3D(ob * Basis(Vector3.UP, rng.randf() * TAU), F * Vector3(x, 0.1, z))
		holder.add_child(d)


## Box the falling rain/snow particles collide with (hidden on contact) so it
## does not fall inside. Needs collision on the weather particles.
static func _precip_block(holder: Node3D, F: Transform3D, L: float, ridge: float, W: float) -> void:
	var cb := GPUParticlesCollisionBox3D.new()
	cb.size = Vector3(L + 0.6, ridge + 0.6, W * 2.0 + 1.4)
	cb.transform = Transform3D(F.basis.orthonormalized(), F * Vector3(0, (ridge + 0.6) * 0.5 - 0.3, 0))
	holder.add_child(cb)


# =================================================================== tunnel

static func _tunnel(c: Node3D, holder: Node3D, F: Transform3D, L: float, rng: RandomNumberGenerator, opts: Dictionary) -> void:
	var hw := 13.6 # inner half width at road level
	var wall_h := 5.6
	var crown := 8.6
	var hl := L * 0.5
	var g := GxGeo.new(F)
	var gi := GxGeo.new(F)
	# arch profile: vertical walls then a segmental vault
	var prof: Array[Vector2] = []
	prof.append(Vector2(-hw, -0.4))
	prof.append(Vector2(-hw, wall_h))
	for k in range(1, 10):
		var a := PI * (1.0 - k / 10.0)
		prof.append(Vector2(cos(a) * hw, wall_h + sin(a) * (crown - wall_h)))
	prof.append(Vector2(hw, wall_h))
	prof.append(Vector2(hw, -0.4))
	var nseg := int(L / 6.0)
	for i in nseg:
		var x0 := -hl + i * L / nseg
		var x1 := x0 + L / nseg
		for k in prof.size() - 1:
			var p0 := prof[k]
			var p1 := prof[k + 1]
			gi.col = Color(0.78, 0.77, 0.74) * (0.9 + 0.1 * ((i + k) % 2))
			gi.quad("in_concrete", Vector3(x0, p0.y, p0.x), Vector3(x1, p0.y, p0.x), Vector3(x1, p1.y, p1.x), Vector3(x0, p1.y, p1.x))
		# panel joints
		gi.col = Color(0.35, 0.35, 0.34)
		for s: float in [-1.0, 1.0]:
			gi.box("in_concrete", Vector3(x0, wall_h * 0.5, s * (hw - 0.01)), Vector3(0.05, wall_h, 0.02))
	for s: float in [-1.0, 1.0]:
		# white wall cladding band with a dark kick plate
		gi.col = Color(0.86, 0.87, 0.85)
		gi.box("in_painted_metal", Vector3(0, 2.1, s * (hw - 0.04)), Vector3(L, 3.2, 0.05))
		gi.col = Color(0.2, 0.2, 0.2)
		gi.box("in_concrete", Vector3(0, 0.3, s * (hw - 0.08)), Vector3(L, 0.6, 0.12))
		# walkway kerb
		gi.col = Color(0.7, 0.7, 0.68)
		gi.box("in_concrete", Vector3(0, 0.12, s * (hw - 0.7)), Vector3(L, 0.36, 1.3), 0.03)
		# LED strip + cable tray high on the wall
		gi.col = Color(0.3, 0.3, 0.3)
		gi.box("in_steel", Vector3(0, wall_h - 0.3, s * (hw - 0.2)), Vector3(L, 0.12, 0.35))
		gi.col = Color(1, 1, 1)
		for i in int(L / 4.0):
			gi.box("emit_sodium" if opts.get("sodium", false) else "emit", Vector3(-hl + 2.0 + i * 4.0, wall_h + 0.25, s * (hw - 0.45)), Vector3(1.6, 0.12, 0.12))
		# emergency niches with green signs
		for i in range(1, int(L / 45.0) + 1):
			var xn := -hl + i * 45.0 - 22.0
			gi.col = Color(0.15, 0.6, 0.25)
			gi.box("emit_warm", Vector3(xn, 2.9, s * (hw - 0.08)), Vector3(0.9, 0.45, 0.04))
			gi.col = Color(0.75, 0.2, 0.15)
			gi.box("in_painted_metal", Vector3(xn, 1.3, s * (hw - 0.12)), Vector3(0.7, 1.0, 0.1), 0.02)
	# jet fans in pairs
	for i in range(1, int(L / 40.0) + 1):
		var xf := -hl + i * 40.0 - 15.0
		for s: float in [-1.0, 1.0]:
			var cpos := Vector3(xf, crown - 1.3, s * 3.2)
			gi.col = Color(0.6, 0.62, 0.64)
			gi.tube("in_steel", [cpos - Vector3(1.6, 0, 0), cpos + Vector3(1.6, 0, 0)], 0.55, 14)
			gi.col = Color(0.1, 0.1, 0.1)
			for e: float in [-1.0, 1.0]:
				gi.tube("in_steel", [cpos + Vector3(e * 1.6, 0, 0), cpos + Vector3(e * 1.75, 0, 0)], 0.5, 14, true)
			gi.col = Color(0.4, 0.4, 0.4)
			gi.bar("in_steel", cpos + Vector3(-0.8, 0.5, 0), cpos + Vector3(-0.8, 1.35, 0), 0.04)
			gi.bar("in_steel", cpos + Vector3(0.8, 0.5, 0), cpos + Vector3(0.8, 1.35, 0), 0.04)
	# portals: concrete arch ring with depth, stone headwall, pilasters, coping,
	# flared wing walls, nameplate, drainage stains, lamps
	var tname := str(opts.get("name", "TUNNEL " + ["KIEFERNBERG", "HOHE WAND", "STEINRIEGEL", "FALKENSTEIN", "SAN ROCCO"][rng.randi() % 5]))
	for e: float in [-1.0, 1.0]:
		_portal(g, holder, F, e * hl, e, prof, hw, wall_h, crown, tname, L, rng)
	# rock mass over the whole tube: displaced grid, cliff texture
	_rock_mass(g, c, F, L, hw, crown, rng)
	GxProps.commit(g, holder, "TunShell", 1200.0, true)
	var lamps: Array = []
	for e: float in [-1.0, 1.0]:
		for sd: float in [-1.0, 1.0]:
			lamps.append(Transform3D(F.basis.orthonormalized() * Basis(Vector3.UP, PI * 0.5 * (1.0 - e) - PI * 0.5 * 0.0), F * Vector3(e * (hl + 0.32), crown + 0.4, sd * (hw + 2.2))))
	GxProps.scatter(holder, "security_light", lamps, 300.0)
	GxProps.commit(gi, holder, "TunInside", 260.0, false)
	# collision walls + echo
	var body := StaticBody3D.new()
	body.name = "TunnelWalls"
	body.add_to_group("echo")
	body.set_meta("sound_reflective", true)
	body.set_meta("echo_kind", "tunnel")
	var pm := PhysicsMaterial.new()
	pm.friction = 0.2
	body.physics_material_override = pm
	var ob := F.basis.orthonormalized()
	for s: float in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(L, wall_h + 2.0, 1.0)
		cs.shape = sh
		cs.transform = Transform3D(ob, F * Vector3(0, wall_h * 0.5, s * (hw + 0.5)))
		body.add_child(cs)
	holder.add_child(body)
	var probe := ReflectionProbe.new()
	probe.size = Vector3(L - 0.5, crown + 1.0, hw * 2.0)
	probe.interior = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.3, 0.3, 0.3)
	probe.ambient_color_energy = 0.15
	probe.blend_distance = 6.0
	probe.box_projection = true
	probe.transform = Transform3D(ob, F * Vector3(0, (crown + 1.0) * 0.5 - 0.3, 0))
	holder.add_child(probe)
	var om := OmniLight3D.new()
	om.light_color = Color(0.9, 0.95, 1.0) if not opts.get("sodium", false) else Color(1.0, 0.65, 0.3)
	om.light_energy = 1.5
	om.omni_range = minf(L * 0.5, 30.0)
	om.shadow_enabled = false
	om.distance_fade_enabled = true
	om.distance_fade_begin = 140.0
	om.distance_fade_length = 30.0
	om.position = F * Vector3(0, wall_h, 0)
	holder.add_child(om)
	_precip_block(holder, F, L, crown + 2.0, hw)


static func _portal(g: GxGeo, holder: Node3D, F: Transform3D, xw: float, e: float, prof: Array[Vector2], hw: float, wall_h: float,
		crown: float, tname: String, L: float, rng: RandomNumberGenerator) -> void:
	var ring := 1.1 # arch ring width
	var proj := 0.9 # how far the ring stands proud of the tube end
	var face := 0.35 # headwall face, recessed behind the ring front
	var outer_h := crown + 3.6
	var outer_w := hw + 6.0
	var xr := xw + e * proj
	var xf_ := xw + e * face
	var dq := func(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
		g.quad(mat, a, b, c, d)
		g.quad(mat, a, d, c, b)
	# arch ring: front face, soffit and outer edge per profile segment (above ground)
	var cen := Vector2(0, wall_h * 0.55)
	var outer: Array[Vector2] = []
	for p in prof:
		var d := (p - cen).normalized()
		if p.y < 0.0:
			d = Vector2(signf(p.x), 0)
		outer.append(p + d * ring)
	g.col = Color(0.82, 0.8, 0.76)
	for k in prof.size() - 1:
		var a := prof[k]
		var b := prof[k + 1]
		var oa := outer[k]
		var ob2 := outer[k + 1]
		if a.y < -0.3 and b.y < -0.3:
			continue
		var q := [Vector3(xr, a.y, a.x), Vector3(xr, b.y, b.x), Vector3(xr, ob2.y, ob2.x), Vector3(xr, oa.y, oa.x)]
		if e > 0.0:
			dq.call("concrete", q[0], q[3], q[2], q[1])
		else:
			dq.call("concrete", q[0], q[1], q[2], q[3])
		# soffit (inside the ring) and outer edge
		var s0 := [Vector3(xw, a.y, a.x), Vector3(xr, a.y, a.x), Vector3(xr, b.y, b.x), Vector3(xw, b.y, b.x)]
		if e > 0.0:
			dq.call("in_concrete", s0[0], s0[1], s0[2], s0[3])
		else:
			dq.call("in_concrete", s0[0], s0[3], s0[2], s0[1])
		var s1 := [Vector3(xf_, oa.y, oa.x), Vector3(xr, oa.y, oa.x), Vector3(xr, ob2.y, ob2.x), Vector3(xf_, ob2.y, ob2.x)]
		if e > 0.0:
			dq.call("concrete", s1[0], s1[3], s1[2], s1[1])
		else:
			dq.call("concrete", s1[0], s1[1], s1[2], s1[3])
	# keystone
	g.col = Color(0.88, 0.86, 0.82)
	g.box("concrete", Vector3(xr + e * 0.12, crown + ring * 0.55, 0), Vector3(0.3, ring * 1.3, 1.1), 0.05)
	# stone headwall: fill between the ring's outer edge and the rectangle
	g.col = Color(0.92, 0.9, 0.86)
	var rect := func(o: Vector2) -> Vector2:
		var d := (o - cen)
		if o.y < 0.0:
			return Vector2(signf(o.x) * outer_w, o.y)
		var tx := outer_w / maxf(absf(d.x), 0.001)
		var ty := (outer_h - cen.y) / maxf(d.y, 0.001)
		return cen + d * minf(tx, ty) if d.y > 0.0 else Vector2(signf(o.x) * outer_w, o.y)
	for k in outer.size() - 1:
		var oa := outer[k]
		var ob2 := outer[k + 1]
		if prof[k].y < -0.3 and prof[k + 1].y < -0.3:
			continue
		var ra: Vector2 = rect.call(oa)
		var rb: Vector2 = rect.call(ob2)
		var q := [Vector3(xf_, oa.y, oa.x), Vector3(xf_, ob2.y, ob2.x), Vector3(xf_, rb.y, rb.x), Vector3(xf_, ra.y, ra.x)]
		if e > 0.0:
			dq.call("stone", q[0], q[3], q[2], q[1])
		else:
			dq.call("stone", q[0], q[1], q[2], q[3])
	# corner fills up to the top corners
	for sd: float in [-1.0, 1.0]:
		var last := outer[outer.size() - 1] if sd > 0.0 else outer[0]
		var rl: Vector2 = rect.call(last)
		g.box("stone", Vector3(xf_ - e * 0.2, (rl.y + outer_h) * 0.5, sd * (outer_w - 0.6)), Vector3(0.4, outer_h - rl.y + 0.6, 1.2))
	g.box("stone", Vector3(xf_ - e * 0.25, outer_h - 0.9, 0), Vector3(0.5, 1.8, outer_w * 2.0)) # top band behind the fill
	# coping + string course, pilasters
	g.col = Color(0.8, 0.78, 0.74)
	g.box("concrete", Vector3(xf_ + e * 0.2, outer_h + 0.25, 0), Vector3(1.3, 0.5, outer_w * 2.0 + 1.2), 0.06)
	g.box("concrete", Vector3(xf_ + e * 0.06, outer_h - 0.35, 0), Vector3(0.5, 0.18, outer_w * 2.0 + 0.4), 0.03)
	for sd: float in [-1.0, 1.0]:
		g.box("concrete", Vector3(xf_ + e * 0.3, outer_h * 0.5 - 0.3, sd * (hw + ring + 1.4)), Vector3(0.7, outer_h + 0.6, 1.2), 0.06)
		g.box("concrete", Vector3(xf_ + e * 0.3, outer_h * 0.5 - 0.3, sd * (outer_w + 0.2)), Vector3(0.7, outer_h + 0.6, 1.0), 0.06)
	# flared wing walls with a sloping top and coping
	for sd: float in [-1.0, 1.0]:
		var a0 := Vector3(xf_, 0, sd * (outer_w + 0.4))
		var dirw := Vector3(e * cos(0.6), 0, sd * sin(0.6))
		var a1 := a0 + dirw * 9.0
		var h0 := outer_h - 0.4
		var h1 := 1.2
		var nrm := Vector3(-dirw.z, 0, dirw.x) * 0.35
		g.col = Color(0.92, 0.9, 0.86)
		for f: float in [-1.0, 1.0]:
			var o := nrm * f
			var q := [a0 + o + Vector3(0, -1.0, 0), a1 + o + Vector3(0, -1.0, 0), a1 + o + Vector3(0, h1, 0), a0 + o + Vector3(0, h0, 0)]
			if (f * e * sd) > 0.0:
				dq.call("stone", q[0], q[3], q[2], q[1])
			else:
				dq.call("stone", q[0], q[1], q[2], q[3])
		g.col = Color(0.8, 0.78, 0.74)
		g.beam("concrete", a0 + Vector3(0, h0 + 0.12, 0), a1 + Vector3(0, h1 + 0.12, 0), 0.9, 0.24)
		g.box("concrete", a1 + Vector3(0, h1 * 0.5 - 0.4, 0), Vector3(0.9, h1 + 0.8, 0.9), 0.05)
	# nameplate above the keystone
	g.col = Color(0.1, 0.11, 0.12)
	g.box("painted_metal", Vector3(xf_ + e * 0.06, crown + ring + 1.25, 0), Vector3(0.08, 0.95, 7.6), 0.02)
	var lab := Label3D.new()
	lab.text = tname
	lab.font_size = 64
	lab.pixel_size = 0.01
	lab.modulate = Color(0.92, 0.9, 0.85)
	lab.outline_size = 0
	lab.shaded = true
	lab.double_sided = false
	lab.transform = Transform3D((F.basis * Basis(Vector3.UP, -PI * 0.5 * e)).orthonormalized(), F * Vector3(xf_ + e * 0.11, crown + ring + 1.35, 0))
	lab.visibility_range_end = 400.0
	holder.add_child(lab)
	var lab2 := lab.duplicate() as Label3D
	lab2.text = "%d m" % int(L)
	lab2.font_size = 30
	lab2.transform.origin = F * Vector3(xf_ + e * 0.11, crown + ring + 0.95, 0)
	holder.add_child(lab2)
	# drainage stains running down from the coping (decals projecting into the face)
	for k in 5:
		var d := Decal.new()
		d.texture_albedo = _stain_tex()
		var w := rng.randf_range(1.2, 3.0)
		var hgt := rng.randf_range(2.5, 6.0)
		d.size = Vector3(w, 1.2, hgt)
		d.albedo_mix = 0.7
		d.upper_fade = 0.1
		d.lower_fade = 0.1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 120.0
		d.distance_fade_length = 30.0
		var z := rng.randf_range(-outer_w + 1.0, outer_w - 1.0)
		var top := outer_h - 0.5
		# local -Y of the decal projects; point it into the headwall (-e along x), image "up" = world up
		var basis := Basis(Vector3(0, 0, 1), Vector3(e, 0, 0), Vector3(0, -1, 0))
		d.transform = Transform3D(F.basis.orthonormalized() * basis, F * Vector3(xf_ + e * 0.3, top - hgt * 0.5, z))
		holder.add_child(d)


static var _stain: Texture2D


static func _stain_tex() -> Texture2D:
	if _stain == null:
		var w := 64
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var nz := FastNoiseLite.new()
		nz.frequency = 0.15
		for x in w:
			var col_len := 0.35 + 0.65 * (nz.get_noise_1d(x * 1.0) * 0.5 + 0.5)
			var edge := clampf(1.0 - absf(x - w * 0.5) / (w * 0.5), 0.0, 1.0)
			for y in h:
				var t := float(y) / h # 0 at top
				var a := clampf((col_len - t) / col_len, 0.0, 1.0) * edge * (0.55 + 0.45 * nz.get_noise_2d(x * 3.0, y * 0.2))
				img.set_pixel(x, y, Color(0.06, 0.055, 0.045, clampf(a * 0.7, 0.0, 1.0)))
		_stain = ImageTexture.create_from_image(img)
	return _stain


static func _rock_mass(g: GxGeo, c: Node3D, F: Transform3D, L: float, hw: float, crown: float, rng: RandomNumberGenerator) -> void:
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.08
	nz.fractal_octaves = 3
	var nx := int(L / 3.0) + 1
	var zs := 16
	var zspan := hw + 22.0
	var pts := []
	for i in nx + 1:
		var x := -L * 0.5 - 1.0 + (L + 2.0) * i / nx
		var row := []
		for j in zs + 1:
			var z := -zspan + 2.0 * zspan * j / zs
			var t := absf(z) / zspan
			var hgt := (crown + 3.0) * (1.0 - t * t * 0.9) + 2.0 * (1.0 - t)
			var gy := _gy(c, F, x, z)
			hgt = maxf(hgt, gy - 0.5)
			if t > 0.85:
				hgt = lerpf(hgt, gy - 1.5, (t - 0.85) / 0.15)
			hgt += nz.get_noise_2d(x, z) * 2.2 * (1.0 - t * 0.5)
			if absf(z) < hw + 1.0:
				hgt = maxf(hgt, crown + 1.4)
			row.append(Vector3(x, hgt, z))
		pts.append(row)
	g.col = Color(0.85, 0.82, 0.78)
	for i in nx:
		for j in zs:
			g.quad("rock", pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j])
