extends RefCounted
## Alpenpass: the rally crowd on the mountain pass. The theme (theme_alpine.gd)
## builds the gorge bridge, cuttings, parapets, gallery, tunnel, village and
## hotel; this adds:
##  - packed fan banks with flares and flags on every hairpin, photographers
##    at the apexes, chevron boards on the outside;
##  - painted names and cheers on the climb;
##  - a chairlift up the mountain swinging over the summit road;
##  - a beer garden and maypole in the village, a sponsor gantry at the start;
##  - spectator camps and parked cars at the pass, the TV helicopter.

const P := "res://scripts/track/gimmicks/%s.gd"


static func _has(piece: String) -> bool:
	return ResourceLoader.exists(P % piece)


static func _put(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if _has(piece):
		load(P % piece).place(c, xf, opts)


static func dress(c: Node3D) -> void:
	if OS.has_environment("NO_DRESS"): # debug bisecting
		return
	if _has("dress_shots"):
		load(P % "dress_shots").attach(c)
	var rng := Gx.rng(c, "dress")
	var L := Gx.length(c)
	# --- hairpins: fan banks outside, photographers inside, chevrons ---------------
	var banners := ["f_rossi", "f_weber", "f_lind", "f_hopp", "f_duval"]
	var made := 0
	var used: Array[float] = []
	for corner in Gx.corners(c, 0.55):
		if made >= 6:
			break
		var along: float = corner.along
		var near := false
		for u in used:
			if absf(u - along) < 90.0 or absf(u - along) > L - 90.0:
				near = true
		if near or along < 60.0:
			continue
		used.append(along)
		var side := -float(corner.turn) # outside of the turn
		var bank = _bank(c, along + 4.0, side, [17.0, 21.0, 25.0]) # behind the hairpin gravel trap
		if bank != null:
			_put(c, "gx_fans", bank, {count = 22 + rng.randi_range(0, 10), flares = 1 + made % 3, flags = 3, depth = 7.0,
				banner = banners[made % banners.size()]})
		for e: Array in [[along - 30.0, side], [along + 36.0, -side]]:
			var xf = _bank(c, e[0], e[1])
			if xf != null:
				_put(c, "gx_fans", xf, {count = 8 + rng.randi_range(0, 6), flags = 1, depth = 5.0})
		var ph = _bank(c, along, -side)
		if ph != null:
			_put(c, "gx_fans", ph, {kind = "photographers"})
		if _has("gx_billboard"):
			_put(c, "gx_billboard", Gx.frame(c, along - 22.0, side, 17.0), {kind = "sign", sign = "chevron", count = 3})
		made += 1
	# --- cheers painted up the climb and over the summit -----------------------------
	if _has("gx_road_text"):
		for b: Array in [[620.0, "HOPP HOPP"], [780.0, "ALLEZ!"], [1100.0, "FORZA"], [1420.0, "WEBER"], [1750.0, "VOLLGAS"],
				[1950.0, "GO GO GO"], [2600.0, "LIND"], [3050.0, "FLAT OUT"]]:
			_put(c, "gx_road_text", Gx.road_frame(c, b[0]), {text = b[1]})
	# --- start: sponsor gantry; village: beer garden and maypole -------------------
	_put(c, "gx_sponsor_arch", Gx.road_frame(c, -14.0), {kind = "gantry", brand = "start", brand2 = "helios"})
	_put(c, "gx_fans", Gx.frame(c, 0.0, Gx.RIGHT, 3.0), {kind = "banners", length = 60.0})
	if _has("gx_landmarks") and _has("gx_spot"):
		var alongs: Array = []
		for k in 12:
			alongs.append(fposmod(-60.0 + k * 20.0, L))
		var xf = GxSpot.find(c, alongs, [7.0, 10.0], 9.0, 0.0, 13.0, 2.5)
		if xf != null:
			GxLandmarks.beer_garden(c, xf, {width = 17.0, depth = 12.0, rng = rng, people = 14})
			var mp: Vector3 = xf * Vector3(10.5, 0, 3.0)
			mp.y = Gx.ground(c, mp)
			GxLandmarks.maypole(c, mp, -(xf as Transform3D).basis.z, {height = 26.0})
	if _has("gx_billboard"):
		_put(c, "gx_billboard", Gx.frame(c, L - 260.0, Gx.RIGHT, 2.0), {kind = "sign", sign = "village", speed = 50})
		_put(c, "gx_billboard", Gx.frame(c, 330.0, Gx.LEFT, 6.0), {brand = 2})
	# --- the pass: camps, parked cars, a drone over the summit -------------------
	if _has("gx_spot"):
		var summit: Array = []
		for k in 20:
			summit.append(1900.0 + k * 25.0)
		var cxf = GxSpot.find(c, summit, [8.0, 14.0], 13.0, 0.0, 16.0, 3.0)
		if cxf != null and _has("gx_camp"):
			GxCamp.place(c, cxf, {size = "large", seed = 3})
		var pxf = GxSpot.find(c, summit, [5.0, 8.0], 14.0, 0.0, 8.0, 2.5)
		if pxf != null and _has("gx_parked_cars"):
			GxParkedCars.place(c, pxf, {count = 9, layout = "angled", seed = 11})
		var descent: Array = []
		for k in 24:
			descent.append(2700.0 + k * 25.0)
		var dxf = GxSpot.find(c, descent, [8.0, 12.0], 9.0, 0.0, 12.0, 3.0)
		if dxf != null and _has("gx_camp"):
			GxCamp.place(c, dxf, {size = "small", seed = 8})
	_wall_rocks(c, rng, L)
	# --- chairlift up the mountain over the summit road ---------------------------
	if _has("gx_skilift"):
		load(P % "gx_skilift").line(c, Vector3(-150, 0, -120), Vector3(-760, 0, -250), {})
	if _has("gx_heli"):
		GxHeli.place(c, Transform3D.IDENTITY, {alt_min = 110.0, alt_max = 190.0})


## A frame beside the road where people can stand: the ground behind the rail
## stays within 2.5 m of level for 8 m (no rock walls, no drops). Tries the
## given side further back, then gives up (null).
static func _bank(c: Node3D, along: float, side: float, lats := [8.0, 12.0, 16.0]):
	for lat: float in lats:
		var xf := Gx.frame(c, along, side, lat)
		var y0 := xf.origin.y
		var ok := absf(y0 - Gx.centre(c, along).y) < 4.0
		for z: float in [-3.0, 2.0, 5.0, 8.0]:
			for x: float in [-6.0, 0.0, 6.0]:
				var p: Vector3 = xf * Vector3(x, 0, z)
				if absf(Gx.ground(c, p) - y0) > 2.5:
					ok = false
		if ok:
			return xf
	return null



## Real rock scans (Poly Haven CC0, assets/vegetation/rocks) fallen at the
## foot of the cuttings, behind the guardrail: one MultiMesh per model.
static func _wall_rocks(c: Node3D, rng: RandomNumberGenerator, L: float) -> void:
	const R := "res://assets/vegetation/rocks/%s.glb"
	if not _has("gx_landmarks"):
		return
	var sets := {"rock_07": [], "rock_09": []}
	var along := 0.0
	while along < L:
		along += rng.randf_range(9.0, 22.0)
		for side: float in [Gx.LEFT, Gx.RIGHT]:
			var base := Gx.frame(c, along, side, 9.5)
			var up: Vector3 = base * Vector3(0, 0, 7.0)
			# A wall: level at the foot, 4 m higher a few metres further out.
			if absf(base.origin.y - Gx.centre(c, along).y) > 1.2 or Gx.ground(c, up) - base.origin.y < 4.0:
				continue
			for k in rng.randi_range(1, 3):
				var p: Vector3 = base * Vector3(rng.randf_range(-4.0, 4.0), 0, rng.randf_range(0.0, 2.5))
				if not Gx.clear_of_road(c, p, 5.5):
					continue
				p.y = Gx.ground(c, p) - 0.25
				var s := rng.randf_range(0.8, 2.4)
				var b := Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s))
				(sets["rock_07" if rng.randf() < 0.5 else "rock_09"] as Array).append(Transform3D(b, p))
	for key: String in sets:
		GxLandmarks.scatter(c, R % key, sets[key], 0.0, true)
