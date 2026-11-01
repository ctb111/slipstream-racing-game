extends RefCounted
## Kiefernring dressing, the showcase: a WRC weekend in the pine forest.
##   main straight  sponsor gantry, then a steel footbridge, banners on the rails,
##                  fan messages painted on the tarmac past the grid
##   back straights a timber barn the road runs through, an inflatable arch,
##                  an overpass-free run with graffiti on a retaining wall
##   corners        fan banks with red flares, flags and bedsheet banners on
##                  the outside, photographers at the inside of the apex
##   forest         camps with campfires, parked spectator cars, a sawmill log
##                  yard, hunters' high seats and a fire lookout tower
##   sky            the TV helicopter
## Sites are picked from the lap's own straights and corners at load time, so
## nothing lands on the start line or another builder's reserved footprint.

const P := "res://scripts/track/gimmicks/%s.gd"
const LM := "res://scripts/track/gimmicks/lm_hochwald.gd"
const R := 1.0
const L := -1.0


static func _piece(name: String) -> Script:
	var path := P % name
	return load(path) if ResourceLoader.exists(path) else null


static func _place(name: String, c: Node3D, xf: Transform3D, opts := {}) -> bool:
	var s := _piece(name)
	if s == null:
		return false
	s.place(c, xf, opts)
	return true


## +1 right-hand corner, -1 left-hand, at `along`.
static func turn_at(c: Node3D, along: float) -> float:
	var a := Gx.tangent(c, along - 12.0)
	var b := Gx.tangent(c, along + 12.0)
	return -signf(a.signed_angle_to(b, Vector3.UP))


## Lateral (beyond the road edge, as Gx.frame takes it) of the guardrail at
## `along` on `side` (gravel traps included) plus `extra` metres.
static func rail_lat(c: Node3D, along: float, side: float, extra := 1.5) -> float:
	var kit := TracksideKit.shared(c)
	var i := kit.nearest(Gx.centre(c, along))
	var worst := 0.0
	for d in range(-6, 7, 2):
		worst = maxf(worst, kit.rail_dist(i + d, side))
	return worst - Gx.half_width() + extra


## Something already reserved (no_trees) within r of p?
static func reserved(c: Node3D, p: Vector3, r: float) -> bool:
	for z in c.get_meta("no_trees", []):
		var q: Vector3 = z[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < float(z[1]) + r:
			return true
	return false


static func lap_gap(c: Node3D, a: float, b: float) -> float:
	var l := Gx.length(c)
	var d := fposmod(a - b, l)
	return minf(d, l - d)


## Picks a spot on a straight (fraction f of it) at least `gap` m (along the lap)
## from every entry of `used` and from the start line, clear of reservations.
static func over_road_site(c: Node3D, runs: Array, used: Array, gap: float, radius: float, fracs := [0.5, 0.35, 0.65, 0.25, 0.75]) -> float:
	for s in runs:
		for f: float in fracs:
			var along: float = lerpf(s.from, s.to, f)
			var ok := lap_gap(c, along, 0.0) > 90.0
			for u: float in used:
				if lap_gap(c, along, u) < gap:
					ok = false
			if ok and not reserved(c, Gx.centre(c, along), radius):
				return along
	return -1.0


## The straightest spot (heading change over +-half_len < max_turn rad) away
## from `used`, the start line and reservations; -1 if none.
static func gentle_site(c: Node3D, used: Array, gap: float, radius: float, max_turn: float, half_len: float) -> float:
	var lap := Gx.length(c)
	var best := -1.0
	var best_turn := max_turn
	var at := 0.0
	while at < lap:
		var ok := lap_gap(c, at, 0.0) > 110.0
		for u: float in used:
			if lap_gap(c, at, u) < gap:
				ok = false
		if ok:
			var t := absf(Gx.tangent(c, at - half_len).signed_angle_to(Gx.tangent(c, at + half_len), Vector3.UP))
			if t < best_turn and not reserved(c, Gx.centre(c, at), radius):
				best_turn = t
				best = at
		at += 8.0
	return best


## Density pass: every `step` metres round the lap, alternating sides, try
## the next piece from `menu` at that spot (skipping reserved / tight spots)
## so something interesting passes by every few seconds.
## menu entries: "fans", "flare", "flags", "banners", "graffiti", "billboard",
## "sign", "cars", "camp", "industrial", "photographers", "text".
static func fill(c: Node3D, rng: RandomNumberGenerator, menu: Array, step := 140.0, flags: Array = []) -> int:
	var lap := Gx.length(c)
	var at := 110.0
	var side := 1.0
	var k := 0
	var placed := 0
	var fans := _piece("gx_fans")
	while at < lap - 60.0:
		var kind: String = menu[k % menu.size()]
		var lat := {"fans": 8.0, "flare": 4.0, "flags": 6.0, "banners": 1.0, "graffiti": 7.5, "billboard": 11.0,
			"sign": 7.0, "cars": 14.0, "camp": 22.0, "industrial": 12.0, "photographers": 3.0, "text": 0.0}.get(kind, 6.0) as float
		var r := {"camp": 14.0, "industrial": 30.0, "cars": 10.0, "graffiti": 6.0, "billboard": 4.0}.get(kind, 3.0) as float
		var f := Transform3D()
		var probe := Vector3.ZERO
		var ok := false
		for tryv: Array in [[0.0, side], [0.0, -side], [25.0, side], [-25.0, side], [25.0, -side], [-25.0, -side]]:
			var a2: float = at + tryv[0]
			var s2: float = tryv[1]
			var l2 := lat
			if kind != "text" and kind != "banners" and kind != "photographers":
				l2 = maxf(lat, rail_lat(c, a2, s2, 1.5 if kind in ["sign", "graffiti", "flare", "flags", "fans"] else 3.0))
			f = Gx.frame(c, a2, s2, l2)
			probe = f.origin + f.basis.z * (r * 0.6 if kind in ["camp", "industrial", "cars"] else 0.0)
			if kind == "text":
				f = Gx.road_frame(c, a2)
				ok = true
				break
			if Gx.clear_of_road(c, probe, l2 * 0.5 + 1.0) and not reserved(c, probe, r):
				ok = true
				side = s2
				break
		if ok:
			match kind:
				"fans":
					if fans: fans.place(c, f, {count = rng.randi_range(6, 10), flags = 2, flares = 1 if rng.randf() < 0.4 else 0,
						banner = rng.randf() < 0.4, depth = 4.0})
				"flare":
					if fans: fans.place(c, f, {count = 5, flares = 1, flags = 1, tape = false, depth = 2.0})
				"flags":
					if fans: fans.place(c, f, {kind = "flags", count = 3, keys = flags})
				"banners":
					if fans: fans.place(c, f, {kind = "banners", length = 36.0})
				"photographers":
					if fans: fans.place(c, f, {kind = "photographers"})
				"graffiti":
					_place("gx_graffiti", c, f, {length = rng.randf_range(8.0, 16.0), height = rng.randf_range(2.2, 3.2)})
				"billboard":
					_place("gx_billboard", c, f, {brand = rng.randi_range(0, 7)})
				"sign":
					_place("gx_billboard", c, f, {kind = "sign", sign = ["fans", "crest", "chevron"][rng.randi() % 3]})
				"cars":
					_place("gx_parked_cars", c, f, {count = rng.randi_range(4, 7), layout = ["angled", "parallel", "field"][rng.randi() % 3]})
				"camp":
					_place("gx_camp", c, f, {size = "small"})
				"industrial":
					_place("gx_industrial", c, f, {kind = ["containers", "tanks"][rng.randi() % 2], width = 40.0, depth = 28.0, crane = false})
				"text":
					_place("gx_road_text", c, f, {})
			if kind != "text":
				Gx.reserve(c, probe, r)
			placed += 1
			side = -side
		k += 1
		at += step * rng.randf_range(0.8, 1.2)
	return placed


static func dress(c: Node3D) -> void:
	if OS.get_cmdline_user_args().has("--no-dress"):
		return # perf A/B: the track without its dressing
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c)
	var dbg := OS.get_cmdline_user_args().has("--debug-dress")
	var rng := Gx.rng(c, "kiefernring")
	var runs := Gx.straights(c, 70.0)
	runs.sort_custom(func(a, b): return a.to - a.from > b.to - b.from)
	var corners := Gx.corners(c, 0.3)
	var used: Array = []
	var lap := Gx.length(c)
	if dbg:
		print("DRESS kiefernring lap ", lap, " runs ", runs)

	await Gx.breath(c) # let the loading screen draw
	# ---- main straight (offset 0 = start line; the straight runs on past it)
	var main_end := 0.0
	for s in runs:
		if s.from <= 5.0 or s.to >= lap - 5.0:
			main_end = s.to if s.to < lap * 0.5 else 0.0
	if main_end < 150.0:
		main_end = 300.0
	var gantry_at := 70.0
	var bridge_at := clampf(main_end * 0.45, 140.0, main_end - 90.0)
	if _place("gx_sponsor_arch", c, Gx.road_frame(c, gantry_at), {kind = "gantry", brand = "helios", brand2 = "kronen"}):
		used.append(gantry_at)
		Gx.reserve(c, Gx.centre(c, gantry_at), 16.0)
	if not reserved(c, Gx.centre(c, bridge_at), 10.0) \
			and _place("gx_overpass", c, Gx.road_frame(c, bridge_at), {kind = "footbridge", banner = "b_nordlicht", graffiti = false}):
		used.append(bridge_at)
		Gx.reserve(c, Gx.centre(c, bridge_at), 16.0)
	var fans := _piece("gx_fans")
	if fans:
		fans.place(c, Gx.frame(c, 30.0, L, 1.0), {kind = "banners", length = 70.0, keys = ["b_rallye", "b_nordlicht", "b_kronen", "b_helios"]})
		fans.place(c, Gx.frame(c, 150.0, R, 1.0), {kind = "banners", length = 60.0, keys = ["b_helios", "b_spect", "b_press"]})
		fans.place(c, Gx.frame(c, bridge_at - 25.0, L, 7.0), {count = 16, flags = 3, flares = 1, banner = "f_weber"})
		fans.place(c, Gx.frame(c, -60.0, R, 9.0), {kind = "flags", count = 5, keys = ["flag_de", "flag_at", "flag_fi", "flag_chk", "flag_fan"]})
	for at: float in [28.0, 52.0]:
		_place("gx_road_text", c, Gx.road_frame(c, at), {kind = "player" if at < 30.0 else "mixed"})

	await Gx.breath(c) # let the loading screen draw
	# ---- drive-through barn at the end of the main straight (the lap's only
	#      long straight), inflatable arch on the straightest bit of the back half
	var barn_len := 30.0
	var barn_at := main_end - barn_len * 0.5 - 18.0
	if lap_gap(c, barn_at, bridge_at) < 60.0 or reserved(c, Gx.centre(c, barn_at), 18.0):
		barn_at = gentle_site(c, used, 120.0, 24.0, 0.05, barn_len * 0.5 + 6.0)
	if barn_at >= 0.0 and _place("gx_warehouse", c, Gx.road_frame(c, barn_at), {kind = "barn", length = barn_len}):
		used.append(barn_at)
		Gx.reserve(c, Gx.centre(c, barn_at), 24.0)
	var arch_at := gentle_site(c, used, 150.0, 14.0, 0.08, 12.0)
	if arch_at >= 0.0 and _place("gx_sponsor_arch", c, Gx.road_frame(c, arch_at), {kind = "inflatable", brand = "nordlicht"}):
		used.append(arch_at)
		Gx.reserve(c, Gx.centre(c, arch_at), 14.0)

	await Gx.breath(c) # let the loading screen draw
	# ---- corners: WRC banks outside, photographers inside, messages in the braking zone
	var sheets := ["f_lind", "f_hopp", "f_novak", "f_duval", "f_rossi", ""]
	var n_banks := 0
	for k in corners:
		if n_banks >= 7:
			break
		var along: float = k.along
		if lap_gap(c, along, 0.0) < 60.0:
			continue
		var turn := turn_at(c, along)
		if dbg:
			print("DRESS kiefernring bank at ", along, " outside ", -turn)
		if fans:
			fans.place(c, Gx.frame(c, along + 8.0, -turn, 8.0), {count = rng.randi_range(10, 16), flares = 2 if n_banks % 2 == 0 else 1,
				flags = 3, banner = sheets[n_banks % sheets.size()], depth = 6.0})
			fans.place(c, Gx.frame(c, along - 4.0, turn, 3.0), {kind = "photographers"})
			if n_banks % 3 == 0:
				fans.place(c, Gx.frame(c, along - 30.0, -turn, 1.0), {kind = "banners", length = 40.0, keys = ["b_kronen", "b_spect"]})
		if n_banks < 5:
			_place("gx_road_text", c, Gx.road_frame(c, along - 70.0), {})
		if n_banks < 3:
			_place("gx_billboard", c, Gx.frame(c, along - 45.0, -turn, rail_lat(c, along - 45.0, -turn)), {kind = "sign", sign = "chevron", count = 3})
		n_banks += 1

	await Gx.breath(c) # let the loading screen draw
	# ---- graffiti on a retaining wall along a back straight
	for s in runs:
		var mid: float = (s.from + s.to) * 0.5
		if lap_gap(c, mid, 0.0) > 200.0 and not reserved(c, Gx.frame(c, mid, L, rail_lat(c, mid, L)).origin, 6.0):
			_place("gx_graffiti", c, Gx.frame(c, mid, L, rail_lat(c, mid, L)), {kind = "retaining", length = 28.0, height = 3.2})
			break

	await Gx.breath(c) # let the loading screen draw
	# ---- billboards, fun signs
	var bb := 0
	for s in runs:
		if bb >= 3:
			break
		var at: float = lerpf(s.from, s.to, 0.2)
		var side := R if bb % 2 == 0 else L
		if not reserved(c, Gx.frame(c, at, side, 12.0).origin, 4.0):
			_place("gx_billboard", c, Gx.frame(c, at, side, 12.0), {brand = bb * 3})
			bb += 1
	_place("gx_billboard", c, Gx.frame(c, 110.0, R, 7.0), {kind = "sign", sign = "fans"})

	await Gx.breath(c) # let the loading screen draw
	# ---- forest: camps, parked cars, log yard, high seats, fire lookout tower
	var camps := 0
	for k in 40:
		if camps >= 2:
			break
		var at := rng.randf_range(80.0, lap - 80.0)
		var side := R if rng.randf() < 0.5 else L
		var f := Gx.frame(c, at, side, 24.0)
		if Gx.clear_of_road(c, f.origin, 18.0) and not reserved(c, f.origin, 14.0):
			if _place("gx_camp", c, f, {size = "large" if camps % 2 == 0 else "small"}):
				Gx.reserve(c, f.origin + f.basis.z * 7.0, 15.0)
				var pf := Gx.frame(c, at + 30.0, side, 14.0)
				if not reserved(c, pf.origin, 6.0):
					_place("gx_parked_cars", c, pf, {count = rng.randi_range(4, 7), layout = "parallel" if camps % 2 else "angled"})
			camps += 1
	if ResourceLoader.exists(LM):
		var lm: Script = load(LM)
		for k in 20:
			var at := rng.randf_range(100.0, lap - 100.0)
			var f := Gx.frame(c, at, L if k % 2 else R, 12.0)
			if Gx.clear_of_road(c, f.origin, 10.0) and not reserved(c, f.origin + f.basis.z * 10.0, 14.0):
				lm.log_yard(c, f, 36.0)
				break
		for hs: Array in [[lap * 0.22, R], [lap * 0.47, L], [lap * 0.71, R]]:
			var f := Gx.frame(c, hs[0], hs[1], 22.0)
			if Gx.clear_of_road(c, f.origin, 15.0) and not reserved(c, f.origin, 3.0):
				lm.high_seat(c, f)
	_lookout_tower(c, rng)
	await Gx.breath(c) # let the loading screen draw
	# wooden telegraph poles with sagging wires across the back of the lap
	if arch_at >= 0.0:
		_place("gx_power", c, Gx.road_frame(c, fposmod(arch_at + 420.0, lap)), {kind = "poles", route = "cross"})

	var extra := fill(c, rng, ["graffiti", "flags", "billboard", "flare", "banners", "sign",
		"photographers", "text", "graffiti"], 200.0, ["flag_de", "flag_at", "flag_fi", "flag_se", "flag_fan", "flag_chk"])
	_place("gx_heli", c, Transform3D.IDENTITY, {})
	if dbg:
		print("DRESS kiefernring: fill ", extra)
		print("DRESS kiefernring: gantry ", gantry_at, " footbridge ", bridge_at, " barn ", barn_at, " arch ", arch_at,
			" banks ", n_banks, " camps ", camps)


## Fire lookout tower on a rise in the forest: a tapering steel lattice of four
## legs with X bracing, a stair zig-zag, and a timber cabin with windows on top.
static func _lookout_tower(c: Node3D, rng: RandomNumberGenerator) -> void:
	if not ResourceLoader.exists(P % "gx_geo"):
		return
	var lap := Gx.length(c)
	var best := Vector3.INF
	var best_h := -INF
	for k in 30:
		var f := Gx.frame(c, rng.randf_range(0.0, lap), R if k % 2 else L, rng.randf_range(45.0, 80.0))
		if not Gx.clear_of_road(c, f.origin, 35.0) or reserved(c, f.origin, 8.0):
			continue
		if f.origin.y > best_h:
			best_h = f.origin.y
			best = f.origin
	if best == Vector3.INF:
		return
	var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU), best)
	var g := GxGeo.new(xf)
	var h := 24.0
	var base := 3.2
	var top := 1.6
	var legs: Array[Vector3] = []
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		legs.append(Vector3(cos(a), 0, sin(a)))
	for k in 4:
		var l0: Vector3 = legs[k] * base + Vector3(0, -1.0, 0)
		var l1: Vector3 = legs[k] * top + Vector3(0, h, 0)
		g.bar("steel", l0, l1, 0.09)
		var n0: Vector3 = legs[(k + 1) % 4]
		for lvl in 6:
			var y0 := h * lvl / 6.0
			var y1 := h * (lvl + 1) / 6.0
			var w0 := lerpf(base, top, y0 / h)
			var w1 := lerpf(base, top, y1 / h)
			var a0: Vector3 = legs[k] * w0 + Vector3(0, y0, 0)
			var b0: Vector3 = n0 * w0 + Vector3(0, y0, 0)
			var a1: Vector3 = legs[k] * w1 + Vector3(0, y1, 0)
			var b1: Vector3 = n0 * w1 + Vector3(0, y1, 0)
			g.bar("steel", a0, b1, 0.035)
			g.bar("steel", b0, a1, 0.035)
			g.bar("steel", a1, b1, 0.05)
	# cabin
	g.box("wood", Vector3(0, h + 0.15, 0), Vector3(3.6, 0.3, 3.6), 0.03)
	for k in 4:
		var d: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][k]
		var side := Vector3(d.z, 0, d.x).abs()
		g.box("wood", Vector3(0, h + 0.75, 0) + d * 1.7, side * 3.5 + d.abs() * 0.12 + Vector3(0, 0.9, 0), 0.02)
		g.box("glass", Vector3(0, h + 1.75, 0) + d * 1.72, side * 3.2 + d.abs() * 0.04 + Vector3(0, 1.1, 0), 0.0)
		g.box("wood", Vector3(0, h + 2.4, 0) + d * 1.7, side * 3.5 + d.abs() * 0.12 + Vector3(0, 0.2, 0), 0.02)
	for k in 4:
		g.bar("wood", legs[k] * 1.7 + Vector3(0, h + 0.3, 0), legs[k] * 1.7 + Vector3(0, h + 2.5, 0), 0.1)
	g.box("roof_tiles", Vector3(0, h + 2.75, 0), Vector3(4.4, 0.3, 4.4), 0.08)
	g.box("roof_tiles", Vector3(0, h + 3.15, 0), Vector3(2.6, 0.5, 2.6), 0.15)
	g.collide(Vector3(0, h * 0.5, 0), Vector3(base * 1.4, h, base * 1.4))
	g.commit(c, "LookoutTower", 1600.0)
	Gx.reserve(c, best, 8.0)
