class_name Terrain
extends RefCounted
## Rolling hills around a circuit. The land is layered noise; the track's own
## height is taken from it (smoothed so gradients stay drivable), then the ground
## near the road is shaped to meet the tarmac, giving cuttings and embankments.
## One square heightmap is used both for collision and, at half resolution and
## in chunks, for rendering.

const N := 513 ## heightmap samples per side (2^k + 1 keeps Jolt's height field happy)
const FLAT := 16.0 ## legacy: metres beyond the road edge kept at road level (now per sample, see carve)
const BLEND := 60.0 ## legacy
const CHUNKS := 8
const RENDER_STRIDE := 2 ## build_nodes draws every 2nd sample (see surface_at)
const BEHIND_RAIL := 3.5 ## flat ground kept behind the guardrail before a bank may rise
const CUT_BLEND := 34.0 ## land higher than the road comes in over this (cuttings)
const FILL_BLEND := 55.0 ## land lower than the road falls away over this (embankments)

## Per-track terrain character. A track def may override any key with
## `terrain = {bank = [2, 9], ...}`.
##  bank:   [min, max] height (m) of the grass banks rising just behind the
##          run-off / guardrail (varies along the lap and per side)
##  bowl:   metres the land rises 50..280 m away from the road: ridges and
##          valley sides that close the horizon (infields become hills)
##  relief: mid-scale hills (wavelength ~150 m) beside the road, in metres
##  design: strength of the designed profile (crest on a straight, a climb
##          into a downhill braking zone, a compression); 0 = off
##  start_bank: bank scale on the start/finish straight (pits, grandstands)
const STYLE := {
	"kiefernring": {bank = [2.5, 9.0], bowl = 34.0, relief = 7.0, design = 1.0},
	"hochwald": {bank = [3.0, 12.0], bowl = 48.0, relief = 9.0, design = 1.2},
	"valle_club": {bank = [3.0, 9.0], bowl = 36.0, relief = 6.0, design = 0.9},
	"brackenmoor": {bank = [1.5, 6.0], bowl = 30.0, relief = 9.0, design = 1.0},
	"schneekopf": {bank = [4.0, 15.0], bowl = 75.0, relief = 12.0, design = 1.1},
	"kuestenstrasse": {bank = [2.0, 8.0], bowl = 34.0, relief = 6.0, design = 1.0},
	"altstadt": {bank = [0.0, 1.5], bowl = 26.0, relief = 2.0, design = 0.5, peaks = [[Vector3(240, 20, 90), 240.0]]},
	"valtellina": {bank = [2.0, 6.0], bowl = 65.0, relief = 4.0, design = 0.8},
	"herbstwald": {bank = [2.5, 10.0], bowl = 38.0, relief = 7.0, design = 0.0},
	"capo_rosso": {bank = [2.0, 8.0], bowl = 30.0, relief = 6.0, design = 0.8},
}
const DEFAULT_STYLE := {bank = [2.5, 9.0], bowl = 34.0, relief = 7.0, design = 1.0, start_bank = 0.3}
var style: Dictionary = DEFAULT_STYLE.duplicate()
var relief_noise := FastNoiseLite.new()
var bank_noise := FastNoiseLite.new()
## Coarse distance-to-road field for the bowl (filled in carve()).
const DIST_N := 97
var _dist := PackedFloat32Array()

var origin := Vector2.ZERO ## world XZ of sample (0, 0)
var cell := 4.0 ## metres between samples
var heights := PackedFloat32Array()
var amplitude := 20.0
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var _bounds: Rect2
## Fixed-height tracks (def.fixed_heights): a coarse field the land follows,
## interpolated from the track's own profile, plus raised bumps.
const BASE_N := 65
var _base := PackedFloat32Array()
var _bumps: Array = [] ## Vector4(x, z, radius, height)
## Optional big landforms from the track def ("peaks"): [[Vector3(x, height, z), radius], ...]
## added to the noise as smooth Gaussian domes (hilltop villages, headlands).
var peaks: Array = []


func _init(track_bounds: Rect2, margin: float, amp: float, seed_value: int) -> void:
	amplitude = amp
	noise.seed = seed_value
	noise.frequency = 0.0022
	noise.fractal_octaves = 4
	detail.seed = seed_value + 1
	detail.frequency = 0.03
	relief_noise.seed = seed_value + 7
	relief_noise.frequency = 0.0068
	relief_noise.fractal_octaves = 2
	bank_noise.seed = seed_value + 13
	bank_noise.frequency = 0.006
	bank_noise.fractal_octaves = 2
	var size := maxf(track_bounds.size.x, track_bounds.size.y) + margin * 2.0
	var centre := track_bounds.get_center()
	origin = centre - Vector2(size, size) * 0.5
	cell = size / (N - 1)
	_bounds = Rect2(origin, Vector2(size, size))


## Terrain character from the track def (STYLE table, then def.terrain overrides).
func configure(def: Dictionary) -> void:
	style = DEFAULT_STYLE.duplicate()
	if def.has("start"):
		style.start = def.start
	style.merge(STYLE.get(def.get("id", ""), {}), true)
	style.merge(def.get("terrain", {}), true)
	if OS.has_environment("TERRAIN_FLAT"): # A/B: the old gentle land, no banks, ridges or designed profile
		style.merge({bank = [0.0, 0.0], bowl = 0.0, relief = 0.0, design = 0.0}, true)
	if style.has("peaks") and peaks.is_empty():
		peaks = style.peaks


## Natural land height before the track is cut in, fading to 0 at the edges
## so it meets the distant hills ring.
func land(x: float, z: float) -> float:
	var h := noise.get_noise_2d(x, z) * amplitude + detail.get_noise_2d(x, z) * 0.8
	h += relief_noise.get_noise_2d(x, z) * float(style.relief)
	if not _base.is_empty():
		h += _base_at(x, z)
	for pk in peaks:
		var c: Vector3 = pk[0]
		var r: float = pk[1]
		h += c.y * exp(-((x - c.x) * (x - c.x) + (z - c.z) * (z - c.z)) / (r * r))
	var u := (x - origin.x) / _bounds.size.x
	var v := (z - origin.y) / _bounds.size.y
	var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
	return h * smoothstep(0.0, 0.12, edge)


## Fixed-height tracks: the land around follows the track profile (inverse
## distance weighted from samples every 40 m) so the road isn't left on a dam or
## in a trench; `bumps` (Vector4 x, z, radius, height) raise ridges and hills.
func set_base(points: Array, bumps: Array = []) -> void:
	_bumps = bumps
	var c := TrackBuilder.make_curve(points)
	var length := c.get_baked_length()
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for i in int(length / 40.0):
		var p := c.sample_baked(i * 40.0)
		xs.append(p.x)
		zs.append(p.z)
		ys.append(p.y)
	_base.resize(BASE_N * BASE_N)
	var step := _bounds.size.x / (BASE_N - 1)
	for zi in BASE_N:
		for xi in BASE_N:
			var x := origin.x + xi * step
			var z := origin.y + zi * step
			var acc := 0.0
			var ws := 0.0
			for k in xs.size():
				var d2 := (xs[k] - x) * (xs[k] - x) + (zs[k] - z) * (zs[k] - z) + 400.0
				var w := 1.0 / (d2 * sqrt(d2))
				acc += ys[k] * w
				ws += w
			_base[zi * BASE_N + xi] = acc / ws


func _base_at(x: float, z: float) -> float:
	var step := _bounds.size.x / (BASE_N - 1)
	var fx := clampf((x - origin.x) / step, 0.0, BASE_N - 1.001)
	var fz := clampf((z - origin.y) / step, 0.0, BASE_N - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var h := lerpf(lerpf(_base[z0 * BASE_N + x0], _base[z0 * BASE_N + x0 + 1], tx),
		lerpf(_base[(z0 + 1) * BASE_N + x0], _base[(z0 + 1) * BASE_N + x0 + 1], tx), tz)
	for b: Vector4 in _bumps:
		var d := Vector2(x - b.x, z - b.y).length()
		h += b.w * smoothstep(b.z, b.z * 0.25, d)
	return h


## Track lifted onto the land, smoothed along the lap so climbs stay drivable,
## then given a designed profile (see _design). Returns dense points (every
## 10 m, exact XZ of the original spline) so crests and dips between the
## sparse control points survive.
func elevate(points: Array) -> Array:
	var flat := TrackBuilder.make_curve(points)
	var length := flat.get_baked_length()
	var n := int(length / 5.0)
	var hs := PackedFloat32Array()
	hs.resize(n)
	var xz: Array[Vector3] = []
	for i in n:
		var p := flat.sample_baked(i * length / n)
		xz.append(p)
		hs[i] = land(p.x, p.z)
	for _pass in 3:
		var out := PackedFloat32Array()
		out.resize(n)
		for i in n:
			var acc := 0.0
			for j in range(-12, 13):
				acc += hs[(i + j + n) % n]
			out[i] = acc / 25.0
		hs = out
	if float(style.design) > 0.0:
		hs = _design(xz, hs, length / n)
	var result := []
	var stride := 2 # every 10 m
	for i in range(0, n - stride + 1, stride):
		result.append(Vector3(xz[i].x, hs[i], xz[i].z))
	return result


## Designed elevation on top of the smoothed land: the longest straight climbs
## and then drops into the braking zone of the corner at its end, the second
## longest gets a crest where the car goes light, the third a compression.
## `hs` holds heights every `ds` metres round the lap.
func _design(xz: Array[Vector3], hs: PackedFloat32Array, ds: float) -> PackedFloat32Array:
	var n := hs.size()
	var k := int(ceil(12.0 / ds))
	# Straightness: heading change over +-12 m (radians per metre).
	var bend := PackedFloat32Array()
	bend.resize(n)
	for i in n:
		var a := xz[(i - k + n) % n]
		var b := xz[i]
		var c := xz[(i + k) % n]
		var t0 := Vector2(b.x - a.x, b.z - a.z).normalized()
		var t1 := Vector2(c.x - b.x, c.z - b.z).normalized()
		bend[i] = absf(t0.angle_to(t1)) / (2.0 * k * ds)
	# Straight runs: radius > 280 m. Collect [start, count].
	var straight := func(i: int) -> bool: return bend[i % n] < 1.0 / 280.0
	var first := 0
	while first < n and straight.call(first):
		first += 1
	if first >= n:
		return hs
	var runs: Array = []
	var run_s := -1
	for step in n + 1:
		var idx := (first + step) % n
		if straight.call(idx):
			if run_s < 0:
				run_s = first + step
		elif run_s >= 0:
			runs.append([run_s, first + step - run_s])
			run_s = -1
	runs.sort_custom(func(p, q): return p[1] > q[1])
	var amp := float(style.design)
	var add: Array = [] # Array, not Packed: the lambda below must write into it
	add.resize(n)
	add.fill(0.0)
	var put := func(centre: float, f: Callable, half: int) -> void:
		for j in range(-half, half + 1):
			var idx := (int(round(centre)) + j + n * 4) % n
			add[idx] = float(add[idx]) + float(f.call(j * ds))
	if runs.size() >= 1 and runs[0][1] * ds > 160.0:
		# Climb along the straight, crest, then downhill into the braking zone.
		var end: float = runs[0][0] + runs[0][1]
		var L: float = minf(runs[0][1] * ds, 420.0)
		# The crest must come well before the braking point and be gentle
		# (drop * 6 / down^2 ~ 0.001: ~0.3 g light at 200 km/h), so nobody
		# arrives at the brakes with the wheels unloaded.
		var drop := 6.0 * amp * clampf(L / 380.0, 0.5, 1.0)
		var down := maxf(L * 0.45, 150.0) + 30.0
		var up := maxf(L - down + 60.0, 120.0)
		put.call(end, func(x: float) -> float:
			if x < -up - down or x > 25.0:
				return 0.0
			if x < -down:
				return drop * smoothstep(-up - down, -down, x)
			return drop * (1.0 - smoothstep(-down, 25.0, x)), int((up + down + 30.0) / ds))
	if runs.size() >= 2 and runs[1][1] * ds > 120.0:
		var mid: float = runs[1][0] + runs[1][1] * 0.55
		# Peak curvature A / sigma^2 = 0.0015 at most: ~0.75 g light at 250 km/h, never a jump.
		var A := minf(3.0, 3.2 * amp)
		put.call(mid, func(x: float) -> float: return A * exp(-x * x / (2.0 * 45.0 * 45.0)), int(160.0 / ds))
	if runs.size() >= 3 and runs[2][1] * ds > 90.0:
		var mid2: float = runs[2][0] + runs[2][1] * 0.5
		var D := -2.6 * amp
		put.call(mid2, func(x: float) -> float: return D * exp(-x * x / (2.0 * 34.0 * 34.0)), int(130.0 / ds))
	# One light smoothing pass on the additions only (no kinks at the joins).
	var out := PackedFloat32Array()
	out.resize(n)
	for j in n:
		out[j] = hs[j] + (float(add[(j - 1 + n) % n]) + float(add[j]) * 2.0 + float(add[(j + 1) % n])) * 0.25
	return out


## Shape the land around the finished (elevated) track curve. Every track
## sample (4 m) stamps its cross-section onto the ground cells it is nearest to:
## flat at road level out to just behind the guardrail (kerb, run-off, gravel
## trap), then a grass bank rising 2..15 m (STYLE.bank, varying along the lap
## and per side), with the natural land coming in steeply where it is higher
## (cuttings) and falling away gently where it is lower (embankments). Further
## out the land rises into ridges (STYLE.bowl) so the horizon is close.
func carve(curve: Curve3D, road_width: float) -> void:
	var half := road_width * 0.5
	var length := curve.get_baked_length()
	_build_dist(curve)
	heights.resize(N * N)
	for zi in N:
		for xi in N:
			var x := origin.x + xi * cell
			var z := origin.y + zi * cell
			heights[zi * N + xi] = land(x, z) + _bowl_at(x, z)
	# Cross-section per sample.
	var step := 4.0
	var ns := int(length / step)
	var c2: Array[Vector3] = []
	for i in int(length / 2.0):
		c2.append(curve.sample_baked(i * 2.0))
	var corner := TrackBuilder._corner_factors(c2)
	var pos := PackedVector3Array()
	var right := PackedVector3Array()
	var flat_l := PackedFloat32Array()
	var flat_r := PackedFloat32Array()
	var bank_l := PackedFloat32Array()
	var bank_r := PackedFloat32Array()
	var bmin: float = style.bank[0]
	var bmax: float = style.bank[1]
	var start_i := -1
	if style.has("start"):
		var st: Vector3 = style.start
		var bd := INF
		for i in ns:
			var q := curve.sample_baked(i * step)
			var dd := Vector2(q.x - st.x, q.z - st.z).length_squared()
			if dd < bd:
				bd = dd
				start_i = i
	var flat_max := 0.0
	for i in ns:
		var off := i * step
		var p := curve.sample_baked(off)
		var tn := curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))
		var r := tn.normalized().cross(Vector3.UP).normalized()
		pos.append(p)
		right.append(r)
		var cf: float = corner[mini(i * 2, corner.size() - 1)]
		var scale := 1.0
		if start_i >= 0:
			var ad := absf(i - start_i) * step
			ad = minf(ad, length - ad)
			scale = lerpf(float(style.get("start_bank", 0.3)), 1.0, smoothstep(140.0, 340.0, ad))
		for side: float in [1.0, -1.0]:
			# Same run-off as TrackBuilder: gravel on the outside of corners, rail behind.
			var depth := TrackBuilder.GRAVEL_MAX * absf(cf) if cf * side > 0.0 else 0.0
			var fl := half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0) + BEHIND_RAIL
			flat_max = maxf(flat_max, fl)
			var nb := clampf(bank_noise.get_noise_2d(off, side * 700.0) * 0.75 + 0.5, 0.0, 1.0)
			var hb := lerpf(bmin, bmax, nb * nb * (3.0 - 2.0 * nb)) * scale
			if side > 0.0:
				flat_r.append(fl)
				bank_r.append(hb)
			else:
				flat_l.append(fl)
				bank_l.append(hb)
	var reach := flat_max + maxf(FILL_BLEND, maxf(7.0, 2.2 * bmax) + 10.0 + 2.5 * bmax)
	var best_d := PackedFloat32Array()
	best_d.resize(N * N)
	best_d.fill(INF)
	var best_i := PackedInt32Array()
	best_i.resize(N * N)
	var rc := int(ceil(reach / cell))
	for i in ns:
		var s := pos[i]
		var cx := int(round((s.x - origin.x) / cell))
		var cz := int(round((s.z - origin.y) / cell))
		for zi in range(maxi(cz - rc, 0), mini(cz + rc + 1, N)):
			var dz := origin.y + zi * cell - s.z
			var row := zi * N
			for xi in range(maxi(cx - rc, 0), mini(cx + rc + 1, N)):
				var dx := origin.x + xi * cell - s.x
				var d := dx * dx + dz * dz
				if d < best_d[row + xi]:
					best_d[row + xi] = d
					best_i[row + xi] = i
	var reach2 := reach * reach
	for k in N * N:
		var d2 := best_d[k]
		if d2 >= reach2:
			continue
		var i := best_i[k]
		var s := pos[i]
		var cxw := origin.x + (k % N) * cell - s.x
		var czw := origin.y + (k / N) * cell - s.z
		var on_right := cxw * right[i].x + czw * right[i].z >= 0.0
		var fl := flat_r[i] if on_right else flat_l[i]
		var hb := bank_r[i] if on_right else bank_l[i]
		var road := s.y - 0.12
		var e := sqrt(d2) - fl
		if e <= 0.0:
			heights[k] = road
			continue
		var natural := heights[k]
		var h := lerpf(road, natural, smoothstep(0.0, CUT_BLEND if natural > road else FILL_BLEND, e))
		if hb > 0.05:
			var w := maxf(7.0, 2.2 * hb)
			var berm := hb * smoothstep(0.0, w, e) * (1.0 - smoothstep(w + 4.0, w + 10.0 + 2.5 * hb, e))
			h = maxf(h, road + berm)
		heights[k] = h
	# Where two stretches of road pass close at different heights (hairpins on a
	# hillside), "nearest sample" can lift ground cells to the upper stretch and
	# grid triangles then poke up through the lower road. Every cell that a
	# triangle crossing the road could use must sit under ALL road nearby.
	var under := half + cell * 1.5
	var ru := int(ceil(under / cell))
	for i in int(length / 2.0):
		var s := curve.sample_baked(i * 2.0)
		# Only cells BESIDE this sample (not ahead of / behind it along the road):
		# on a slope, road further along is lower and must not dig a ditch here.
		var tn := curve.sample_baked(fmod(i * 2.0 + 1.0, length)) - curve.sample_baked(fmod(i * 2.0 - 1.0 + length, length))
		var tx := tn.x
		var tz := tn.z
		var tl := maxf(sqrt(tx * tx + tz * tz), 0.001)
		tx /= tl
		tz /= tl
		var cx := int(round((s.x - origin.x) / cell))
		var cz := int(round((s.z - origin.y) / cell))
		for zi in range(maxi(cz - ru, 0), mini(cz + ru + 1, N)):
			var dz := origin.y + zi * cell - s.z
			for xi in range(maxi(cx - ru, 0), mini(cx + ru + 1, N)):
				var dx := origin.x + xi * cell - s.x
				if absf(dx * tx + dz * tz) <= 1.2 and dx * dx + dz * dz < under * under:
					var k := zi * N + xi
					heights[k] = minf(heights[k], s.y - 0.15)


## Coarse distance (XZ) from every point of the map to the road, for the bowl.
func _build_dist(curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	var pts := PackedVector2Array()
	for i in int(length / 15.0):
		var p := curve.sample_baked(i * 15.0)
		pts.append(Vector2(p.x, p.z))
	_dist.resize(DIST_N * DIST_N)
	var step := _bounds.size.x / (DIST_N - 1)
	for zi in DIST_N:
		for xi in DIST_N:
			var q := Vector2(origin.x + xi * step, origin.y + zi * step)
			var best := INF
			for p in pts:
				best = minf(best, q.distance_squared_to(p))
			_dist[zi * DIST_N + xi] = sqrt(best)


## Distance to the road (coarse, bilinear); INF-safe before carve().
func road_distance(x: float, z: float) -> float:
	if _dist.is_empty():
		return 0.0
	var step := _bounds.size.x / (DIST_N - 1)
	var fx := clampf((x - origin.x) / step, 0.0, DIST_N - 1.001)
	var fz := clampf((z - origin.y) / step, 0.0, DIST_N - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	return lerpf(lerpf(_dist[z0 * DIST_N + x0], _dist[z0 * DIST_N + x0 + 1], tx),
		lerpf(_dist[(z0 + 1) * DIST_N + x0], _dist[(z0 + 1) * DIST_N + x0 + 1], tx), tz)


## The land rising away from the road: valley sides, infield hills, ridges
## that close the horizon. 0 within ~50 m of the road.
func _bowl_at(x: float, z: float) -> float:
	var b := float(style.bowl)
	if b <= 0.0:
		return 0.0
	var d := road_distance(x, z)
	var vary := relief_noise.get_noise_2d(x * 0.22 + 300.0, z * 0.22) * 0.75 + 0.85
	var u := (x - origin.x) / _bounds.size.x
	var v := (z - origin.y) / _bounds.size.y
	var edge := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
	return b * smoothstep(40.0, 230.0, d) * maxf(vary, 0.2) * smoothstep(0.0, 0.12, edge)


func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell, 0.0, N - 1.001)
	var fz := clampf((z - origin.y) / cell, 0.0, N - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - x0
	var tz := fz - z0
	var h00 := heights[z0 * N + x0]
	var h10 := heights[z0 * N + x0 + 1]
	var h01 := heights[(z0 + 1) * N + x0]
	var h11 := heights[(z0 + 1) * N + x0 + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Height of the DRAWN ground: build_nodes renders every RENDER_STRIDE-th sample,
## each quad split along its (0,0)-(1,1) diagonal. On banks and dips that
## surface is up to ~1 m off height_at(), so things that must stand ON the
## visible ground (people, parked cars, props) use this one.
func surface_at(x: float, z: float) -> float:
	var g := cell * RENDER_STRIDE
	var fx := clampf((x - origin.x) / g, 0.0, (N - 1) / RENDER_STRIDE - 0.001)
	var fz := clampf((z - origin.y) / g, 0.0, (N - 1) / RENDER_STRIDE - 0.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var u := fx - x0
	var v := fz - z0
	x0 *= RENDER_STRIDE
	z0 *= RENDER_STRIDE
	var h00 := heights[z0 * N + x0]
	var h11 := heights[(z0 + RENDER_STRIDE) * N + x0 + RENDER_STRIDE]
	if u >= v:
		var h10 := heights[z0 * N + x0 + RENDER_STRIDE]
		return h00 + u * (h10 - h00) + v * (h11 - h10)
	var h01 := heights[(z0 + RENDER_STRIDE) * N + x0]
	return h00 + v * (h01 - h00) + u * (h11 - h01)


func build_nodes(parent: Node3D, mat: Material, grip: float, drag: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Terrain"
	body.set_meta("grip", grip)
	body.set_meta("drag", drag)
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	shape.map_data = heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	var span := (N - 1) * cell
	cs.position = Vector3(origin.x + span * 0.5, 0.0, origin.y + span * 0.5)
	cs.scale = Vector3(cell, 1.0, cell)
	body.add_child(cs)
	parent.add_child(body)

	# Render at every second sample, split into chunks so off-screen parts cull.
	var stride := RENDER_STRIDE
	var per := (N - 1) / CHUNKS
	var side := per / stride + 1
	for cz in CHUNKS:
		for cx in CHUNKS:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var idx := PackedInt32Array()
			for j in side:
				for i in side:
					var xi := cx * per + i * stride
					var zi := cz * per + j * stride
					verts.append(Vector3(origin.x + xi * cell, heights[zi * N + xi], origin.y + zi * cell))
					norms.append(_grid_normal(xi, zi))
			for j in side - 1:
				for i in side - 1:
					var a := j * side + i
					idx.append_array([a, a + 1, a + side + 1, a, a + side + 1, a + side])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # receives, doesn't cast: big saving
			body.add_child(mi)


func _grid_normal(xi: int, zi: int) -> Vector3:
	var l := heights[zi * N + maxi(xi - 1, 0)]
	var r := heights[zi * N + mini(xi + 1, N - 1)]
	var d := heights[maxi(zi - 1, 0) * N + xi]
	var u := heights[mini(zi + 1, N - 1) * N + xi]
	return Vector3(l - r, 2.0 * cell, d - u).normalized()
