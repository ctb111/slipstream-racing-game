extends RefCounted
## Autodromo di Valtellina dressing: an Italian autodromo weekend.
##   straights  sponsor gantry over the start, a concrete road overpass and a
##              steel footbridge on the long straights, an industrial hall the
##              road runs through with a container yard beside it, an
##              inflatable arch, billboards
##   corners    tifosi on the outside: Italian and fan-club flags, red flares,
##              "FORZA ROSSI" bedsheets; photographers at the apexes; painted
##              names in the braking zones
##   around     parked cars, two camps, the TV helicopter and a hilltop castle
## Helpers (site picking) are shared with dress_kiefernring.gd.

const P := "res://scripts/track/gimmicks/%s.gd"
const K := "res://scripts/track/gimmicks/dress_kiefernring.gd"
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


static func dress(c: Node3D) -> void:
	if OS.get_cmdline_user_args().has("--no-dress"):
		return # perf A/B: the track without its dressing
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c)
	var k: Script = load(K)
	var dbg := OS.get_cmdline_user_args().has("--debug-dress")
	var rng := Gx.rng(c, "valtellina")
	var lap := Gx.length(c)
	var runs := Gx.straights(c, 80.0)
	runs.sort_custom(func(a, b): return a.to - a.from > b.to - b.from)
	var used: Array = []
	if dbg:
		print("DRESS valtellina lap ", lap, " runs ", runs)

	await Gx.breath(c) # let the loading screen draw
	# ---- start: sponsor gantry, banners, tifosi flags, painted names
	if _place("gx_sponsor_arch", c, Gx.road_frame(c, 60.0), {kind = "gantry", brand = "marzelli", brand2 = "valter"}):
		used.append(60.0)
		Gx.reserve(c, Gx.centre(c, 60.0), 16.0)
	var fans := _piece("gx_fans")
	var tricolore := ["flag_it", "flag_it", "flag_fan", "flag_it", "flag_chk", "flag_ch"]
	if fans:
		fans.place(c, Gx.frame(c, 20.0, R, 1.0), {kind = "banners", length = 80.0, keys = ["b_marzelli", "b_valter", "b_aurel", "b_helios"]})
		fans.place(c, Gx.frame(c, 130.0, L, 1.0), {kind = "banners", length = 60.0, keys = ["b_marzelli", "b_press", "b_spect"]})
		fans.place(c, Gx.frame(c, -40.0, L, 10.0), {kind = "flags", count = 6, keys = tricolore})
	for t: Array in [[30.0, "FORZA ROSSI"], [55.0, "MANCINI"], [80.0, "VAI CASTELL!"]]:
		_place("gx_road_text", c, Gx.road_frame(c, t[0]), {text = t[1], color = "white" if t[0] < 50.0 else "yellow"})

	await Gx.breath(c) # let the loading screen draw
	# ---- over / through the road on the long straights
	var plan := [["gx_overpass", {kind = "road", banner = "b_valter"}, 26.0],
		["gx_warehouse", {kind = "warehouse", length = 54.0}, 32.0],
		["gx_overpass", {kind = "footbridge", banner = "b_marzelli", graffiti = false}, 12.0],
		["gx_sponsor_arch", {kind = "inflatable", brand = "valter"}, 12.0]]
	var placed := {}
	for p: Array in plan:
		if _piece(p[0]) == null:
			continue
		var at: float = k.over_road_site(c, runs, used, 160.0, p[2])
		if at < 0.0:
			at = k.gentle_site(c, used, 160.0, p[2], 0.06, 16.0)
		if at < 0.0:
			continue
		_place(p[0], c, Gx.road_frame(c, at), p[1])
		used.append(at)
		Gx.reserve(c, Gx.centre(c, at), p[2])
		placed[str(p[0]) + str((p[1] as Dictionary).get("kind", ""))] = at
		if p[0] == "gx_overpass" and p[1].kind == "road":
			for side: float in [L, R]:
				_place("gx_graffiti", c, Gx.frame(c, at + 30.0, side, k.rail_lat(c, at + 30.0, side)), {length = 12.0, height = 2.6})
		if p[0] == "gx_warehouse":
			var yf := Gx.frame(c, at + 75.0, L, 10.0)
			if not k.reserved(c, yf.origin + yf.basis.z * 20.0, 18.0):
				_place("gx_industrial", c, yf, {kind = "containers", width = 40.0, depth = 26.0, crane = false})

	await Gx.breath(c) # let the loading screen draw
	# ---- tifosi on the corners
	var sheets := ["f_rossi", "f_rossi", "f_weber", "f_duval", "f_hopp", "f_rossi", "f_lind", ""]
	var n_banks := 0
	for cn in Gx.corners(c, 0.3):
		if n_banks >= 8:
			break
		var along: float = cn.along
		if k.lap_gap(c, along, 0.0) < 70.0:
			continue
		var turn: float = k.turn_at(c, along)
		if fans:
			fans.place(c, Gx.frame(c, along + 8.0, -turn, 8.0), {count = rng.randi_range(10, 16), flares = 2 if n_banks % 2 == 0 else 1,
				flags = 4, banner = sheets[n_banks % sheets.size()], depth = 7.0})
			fans.place(c, Gx.frame(c, along + 14.0, -turn, 12.0), {kind = "flags", count = 3, keys = tricolore})
			fans.place(c, Gx.frame(c, along - 4.0, turn, 3.0), {kind = "photographers"})
			if n_banks % 2 == 1:
				fans.place(c, Gx.frame(c, along - 35.0, -turn, 1.0), {kind = "banners", length = 40.0, keys = ["b_marzelli", "b_kronen", "b_spect"]})
		if n_banks < 5:
			_place("gx_road_text", c, Gx.road_frame(c, along - 75.0), {})
		if n_banks < 3:
			_place("gx_billboard", c, Gx.frame(c, along - 50.0, -turn, k.rail_lat(c, along - 50.0, -turn)), {kind = "sign", sign = "chevron", count = 3})
		n_banks += 1

	await Gx.breath(c) # let the loading screen draw
	# ---- billboards along the straights
	var bb := 0
	for s in runs:
		if bb >= 4:
			break
		var at: float = lerpf(s.from, s.to, 0.15)
		var side := R if bb % 2 == 0 else L
		var f := Gx.frame(c, at, side, 12.0)
		if not k.reserved(c, f.origin, 4.0):
			_place("gx_billboard", c, f, {brand = bb * 2 + 1})
			bb += 1

	await Gx.breath(c) # let the loading screen draw
	# ---- parked cars, camps, heli
	var camps := 0
	for i in 40:
		if camps >= 1:
			break
		var at := rng.randf_range(150.0, lap - 150.0)
		var side := R if rng.randf() < 0.5 else L
		var f := Gx.frame(c, at, side, 24.0)
		if Gx.clear_of_road(c, f.origin, 18.0) and not k.reserved(c, f.origin, 14.0):
			if _place("gx_camp", c, f, {size = "small"}):
				Gx.reserve(c, f.origin + f.basis.z * 6.0, 13.0)
			camps += 1
	var rows := 0
	for i in 40:
		if rows >= 3:
			break
		var at := rng.randf_range(100.0, lap - 100.0)
		var f := Gx.frame(c, at, R if i % 2 else L, 15.0)
		if Gx.clear_of_road(c, f.origin, 12.0) and not k.reserved(c, f.origin, 10.0):
			_place("gx_parked_cars", c, f, {count = rng.randi_range(5, 9), layout = "field" if rows % 2 else "angled"})
			Gx.reserve(c, f.origin, 12.0)
			rows += 1
	_castle(c, rng)
	await Gx.breath(c) # let the loading screen draw
	# motorway-style sign gantry with fun destinations, a church spire on the hill
	var sg: float = -1.0 # sign gantry off: valtellina is at the frame budget
	if sg >= 0.0 and _place("gx_sign_gantry", c, Gx.road_frame(c, sg), {}):
		used.append(sg)
		Gx.reserve(c, Gx.centre(c, sg), 12.0)
	for i in 0: # church spire off: frame budget
		var f := Gx.frame(c, rng.randf_range(0.0, lap), R if i % 2 else L, rng.randf_range(60.0, 110.0))
		if Gx.clear_of_road(c, f.origin, 45.0) and not k.reserved(c, f.origin, 10.0):
			if _place("gx_tower", c, f, {kind = "church_spire"}):
				Gx.reserve(c, f.origin, 10.0)
			break
	var extra: int = k.fill(c, rng, ["billboard", "graffiti", "flags", "banners", "flare",
		"sign", "photographers", "text", "billboard"], 200.0, tricolore)
	if dbg:
		print("DRESS valtellina: fill ", extra)
	_place("gx_heli", c, Transform3D.IDENTITY, {})
	if dbg:
		print("DRESS valtellina: ", placed, " banks ", n_banks, " camps ", camps, " car rows ", rows)


## A ruined hilltop castle in the vineyards: square keep, curtain wall with
## merlons, a round corner tower. Weathered stone, far landmark.
static func _castle(c: Node3D, rng: RandomNumberGenerator) -> void:
	if _piece("gx_geo") == null:
		return
	var k: Script = load(K)
	var lap := Gx.length(c)
	var best := Vector3.INF
	var best_h := -INF
	for i in 40:
		var f := Gx.frame(c, rng.randf_range(0.0, lap), R if i % 2 else L, rng.randf_range(120.0, 220.0))
		if not Gx.clear_of_road(c, f.origin, 90.0) or k.reserved(c, f.origin, 25.0):
			continue
		if f.origin.y > best_h:
			best_h = f.origin.y
			best = f.origin
	if best == Vector3.INF:
		return
	var g := GxGeo.new(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), best + Vector3.DOWN * 1.0))
	var col := "stone"
	# curtain wall: a 34 x 26 m ring, 7 m high, merlons on top
	var hw := 17.0
	var hd := 13.0
	var wall_h := 7.0
	for side: Array in [[Vector3(0, 0, -hd), Vector3(hw * 2, 0, 0)], [Vector3(0, 0, hd), Vector3(hw * 2, 0, 0)],
			[Vector3(-hw, 0, 0), Vector3(0, 0, hd * 2)], [Vector3(hw, 0, 0), Vector3(0, 0, hd * 2)]]:
		var ctr: Vector3 = side[0]
		var ext: Vector3 = side[1]
		var size := Vector3(maxf(ext.x, 1.6), wall_h + 2.0, maxf(ext.z, 1.6))
		g.box(col, ctr + Vector3(0, wall_h * 0.5 - 1.0, 0), size, 0.05)
		var along := ext.normalized()
		var n := int(ext.length() / 1.6)
		for m in n:
			if m % 2 == 0:
				var p := ctr - ext * 0.5 + along * (m + 0.5) * 1.6
				g.box(col, p + Vector3(0, wall_h + 1.45, 0), Vector3(0.8, 0.9, 0.8) + along.abs() * 0.0, 0.03)
	# gap in the south wall (a ruin): rubble
	for m in 6:
		g.box(col, Vector3(rng.randf_range(-4.0, 4.0), 0.4, -hd - rng.randf_range(0.5, 2.5)), Vector3(1.2, 0.8, 1.0) * rng.randf_range(0.6, 1.3), 0.15,
			Basis(Vector3.UP, rng.randf() * TAU))
	# keep
	g.box(col, Vector3(-6.0, 9.0, 3.0), Vector3(10.0, 20.0, 10.0), 0.08)
	for m in 4:
		var d: Vector3 = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)][m]
		var tside := Vector3(d.z, 0, d.x).abs()
		for q in 3:
			g.box(col, Vector3(-6.0, 19.6, 3.0) + d * 4.6 + tside * (q - 1) * 3.4, Vector3(1.0, 1.2, 1.0), 0.04)
		g.box("glass", Vector3(-6.0, 13.0, 3.0) + d * 5.02, tside * 0.7 + d.abs() * 0.05 + Vector3(0, 1.6, 0), 0.0)
	# round corner tower
	var prof := PackedVector2Array([Vector2(0.0, -1.0), Vector2(3.6, -1.0), Vector2(3.3, 11.0), Vector2(3.6, 11.4), Vector2(3.6, 12.6), Vector2(0.0, 12.6)])
	g.lathe(col, Vector3(hw, 0, hd), prof, 16)
	g.collide(Vector3(0, wall_h * 0.5, 0), Vector3(hw * 2, wall_h, hd * 2))
	g.commit(c, "HilltopCastle", 2400.0)
	Gx.reserve(c, best, 26.0)
