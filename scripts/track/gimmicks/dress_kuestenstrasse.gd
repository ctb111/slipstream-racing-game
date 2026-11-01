extends RefCounted
## Küstenstraße dressing: the harbour's industrial docks on the back straight
## (the road runs THROUGH a warehouse between container stacks and a yard),
## a road overpass, graffiti on the dock walls, fans on the cliff-top corners,
## parked cars, and two landmarks of its own: a timber fishing pier off the
## beach and a row of wind turbines on the hills inland (GxLandmarks).
## The harbour, lighthouse and villas themselves come from themes.gd (coast).

const P := "res://scripts/track/gimmicks/"


static func _has(piece: String) -> bool:
	return ResourceLoader.exists(P + piece + ".gd")


static func _place(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if _has(piece):
		load(P + piece + ".gd").place(c, xf, opts)


## Nothing registered (by any earlier builder) within `r` of `p`? Ignores the
## huge "no forest here" circles (sea, town).
static func _free(c: Node3D, p: Vector3, r: float) -> bool:
	for z in c.get_meta("no_trees", []):
		if float(z[1]) > 70.0:
			continue
		if Vector2(p.x - z[0].x, p.z - z[0].z).length() < r + float(z[1]):
			return false
	return true


static func dress(c: Node3D) -> void:
	if ResourceLoader.exists(P + "dress_shots.gd"):
		load(P + "dress_shots.gd").attach(c)
	var rng := Gx.rng(c, "dress")
	_landmarks(c, rng)
	_docks(c, rng)
	_overpass(c)
	_fans(c)
	_signs(c)
	_fill(c, [102.0, 150.0, 250.0, 262.0, 300.0, 600.0, 630.0, 822.0, 916.0, 1000.0, 1432.0, 1692.0, 1812.0, 1928.0, 1104.0, 2010.0, 2058.0, 2335.0, 2440.0, 2500.0, 2742.0], ["billboard", "graffiti", "text", "sign", "banners", "graffiti"])


# ---------------------------------------------------------------- landmarks

static func _landmarks(c: Node3D, rng: RandomNumberGenerator) -> void:
	var coast: Dictionary = c.get_meta("coast", {})
	if coast.is_empty():
		return
	var sea: Vector3 = coast.sea
	var level: float = coast.sea_level
	# Fishing pier off the beach: start where the sand drops below the deck.
	var deck := level + 2.0
	var p: Vector3 = coast.beach
	for k in 80:
		var q := p - sea * 1.0
		if Gx.ground(c, q) > deck - 0.3:
			break
		p = q
	GxLandmarks.fishing_pier(c, p, sea, 46.0, deck, {rng = rng, anglers = 4})
	if OS.get_cmdline_user_args().has("--debug-dress"):
		print("DRESS pier start ", p, " sea ", sea, " deck ", deck)
	_shore_band(c, level)
	# Wind turbines on the high ground inland, facing the sea breeze.
	var land := -sea
	var bounds := AABB(Gx.centre(c, 0.0), Vector3.ZERO)
	for i in 60:
		bounds = bounds.expand(Gx.centre(c, i * Gx.length(c) / 60.0))
	var placed: Array[Vector3] = []
	var cands: Array = []
	var cen := bounds.get_center()
	var across := Vector3(-land.z, 0, land.x)
	for i in 9:
		for j in 4:
			var q := cen + land * (bounds.size.dot(land.abs()) * 0.5 + 150.0 + j * 70.0) + across * ((i - 4) * 95.0)
			q.y = Gx.ground(c, q)
			cands.append(q)
	cands.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y > b.y)
	for q: Vector3 in cands:
		if placed.size() >= 4:
			break
		if not Gx.clear_of_road(c, q, 110.0) or not _free(c, q, 20.0):
			continue
		var ok := true
		for o in placed:
			if o.distance_to(q) < 170.0:
				ok = false
		if ok:
			placed.append(q)
	for q in placed:
		if OS.get_cmdline_user_args().has("--debug-dress"):
			print("DRESS turbine ", q)
		GxLandmarks.wind_turbine(c, q, sea, {speed = rng.randf_range(0.9, 1.3)})


# ---------------------------------------------------------------- docks

## Industrial docks on the back straight (2348-2512 m): drive-through
## warehouse, a yard with a crane on the inside, containers outside,
## graffiti on the dock walls, workers' cars.
static func _docks(c: Node3D, rng: RandomNumberGenerator) -> void:
	var at := 2440.0
	if _has("gx_warehouse"):
		GxWarehouse.place(c, Gx.road_frame(c, at), {kind = "warehouse", length = 54.0})
		Gx.reserve(c, Gx.centre(c, at), 30.0)
	var yard := Gx.frame(c, 2372.0, Gx.RIGHT, 7.0)
	if _free(c, yard.origin + yard.basis.z * 20.0, 14.0):
		_place(c, "gx_industrial", yard, {kind = "yard", width = 56.0, depth = 40.0})
	var box := Gx.frame(c, 2500.0, Gx.LEFT, 7.0)
	if _free(c, box.origin + box.basis.z * 12.0, 10.0):
		_place(c, "gx_industrial", box, {kind = "containers", width = 40.0, depth = 26.0, crane = false})
	if _has("gx_graffiti"):
		GxGraffiti.place(c, Gx.frame(c, 2380.0, Gx.LEFT, 3.0), {kind = "retaining", length = 34.0, height = 3.2})
		GxGraffiti.place(c, Gx.frame(c, 2496.0, Gx.RIGHT, 3.5), {kind = "retaining", length = 26.0, height = 3.0})
		# The harbour wall on the landward side of the quay road.
		GxGraffiti.place(c, Gx.frame(c, 2742.0, Gx.RIGHT, 3.0), {kind = "retaining", length = 30.0, height = 3.0})
	if _has("gx_parked_cars"):
		GxParkedCars.place(c, Gx.frame(c, 2335.0, Gx.LEFT, 6.0), {count = 6, layout = "angled", seed = rng.randi()})


static func _overpass(c: Node3D) -> void:
	if _has("gx_sign_gantry"):
		GxSignGantry.place(c, Gx.road_frame(c, 630.0), {boards = [5, 4]})
		Gx.reserve(c, Gx.centre(c, 630.0), 10.0)
	if _has("gx_overpass"):
		GxOverpass.place(c, Gx.road_frame(c, 1104.0), {kind = "road", banner = "b_aurel", graffiti = false})
		Gx.reserve(c, Gx.centre(c, 1104.0), 22.0)
		if _has("gx_graffiti"):
			for s: float in [Gx.LEFT, Gx.RIGHT]: # wing walls leading up to the bridge
				GxGraffiti.place(c, Gx.frame(c, 1080.0, s, 3.0), {kind = "retaining", length = 14.0, height = 2.6})


# ---------------------------------------------------------------- fans

## Cliff-top fan zones: the hairpin by the lighthouse (outside = the sea side,
## on the cliff edge), plus two more banks, cars parked in the field behind.
static func _fans(c: Node3D) -> void:
	if not _has("gx_fans"):
		return
	GxFans.place(c, Gx.frame(c, 306.0, Gx.LEFT, 9.0), {count = 34, flares = 2, flags = 3, banner = true, depth = 7.0})
	GxFans.place(c, Gx.frame(c, 282.0, Gx.RIGHT, 6.0), {count = 14, flags = 1})
	GxFans.place(c, Gx.frame(c, 296.0, Gx.RIGHT, 4.0), {kind = "photographers"})
	GxFans.place(c, Gx.frame(c, 2058.0, Gx.LEFT, 8.0), {count = 22, flares = 1, flags = 2, banner = true})
	GxFans.place(c, Gx.frame(c, 822.0, Gx.LEFT, 8.0), {count = 18, flags = 2})
	for k: Array in [[1432.0, Gx.LEFT], [916.0, Gx.RIGHT], [1812.0, Gx.RIGHT]]:
		GxFans.place(c, Gx.frame(c, k[0], k[1], 7.0), {count = 14, flags = 2, flares = 1 if k[0] == 1432.0 else 0, banner = true})
	if _has("gx_parked_cars"):
		var f := Gx.frame(c, 250.0, Gx.LEFT, 24.0)
		if _free(c, f.origin, 6.0):
			GxParkedCars.place(c, f, {count = 7, layout = "field", seed = 7})
	if _has("gx_heli"):
		GxHeli.place(c, Gx.frame(c, 300.0, Gx.LEFT, 14.0), {kind = "drone", height = 11.0})
		GxHeli.place(c, Transform3D.IDENTITY, {}) # the TV helicopter, sweeping out over the sea


static func _signs(c: Node3D) -> void:
	if not _has("gx_billboard"):
		return
	GxBillboard.place(c, Gx.frame(c, 150.0, Gx.RIGHT, 5.0), {brand = "NORDLICHT"})
	GxBillboard.place(c, Gx.frame(c, 600.0, Gx.RIGHT, 5.0), {brand = "HELIOS BENZIN"})
	GxBillboard.place(c, Gx.frame(c, 1000.0, Gx.RIGHT, 1.5), {kind = "sign", sign = "chevron", count = 4})
	if _has("gx_road_text"):
		GxRoadText.place(c, Gx.road_frame(c, 262.0), {kind = "gogo"})
		GxRoadText.place(c, Gx.road_frame(c, 2400.0), {kind = "mixed"})
		GxRoadText.place(c, Gx.road_frame(c, 2010.0), {kind = "heart"})

## Density pass: something every ~280 m of the lap, sides alternating, cycling
## through cheap pieces; skips stretches already dressed above (`used`).
static func _fill(c: Node3D, used: Array, cycle: Array, step := 280.0) -> void:
	var l := Gx.length(c)
	var rng := Gx.rng(c, "fill")
	var k := 0
	var a := 40.0
	while a < l - 40.0:
		var near := false
		for u: float in used:
			var d := absf(a - u)
			if minf(d, l - d) < 70.0:
				near = true
		if not near:
			var side := Gx.LEFT if k % 2 == 0 else Gx.RIGHT
			var kind: String = cycle[k % cycle.size()]
			match kind:
				"billboard":
					if _has("gx_billboard"):
						GxBillboard.place(c, Gx.frame(c, a, side, 4.0), {brand = rng.randi() % 8})
				"graffiti":
					if _has("gx_graffiti"):
						GxGraffiti.place(c, Gx.frame(c, a, side, 2.8), {kind = "wall" if rng.randf() < 0.5 else "retaining", length = rng.randf_range(8.0, 16.0), height = 2.8})
				"fans":
					if _has("gx_fans"):
						GxFans.place(c, Gx.frame(c, a, side, 6.0), {count = rng.randi_range(8, 12), flags = 1, banner = rng.randf() < 0.5})
				"banners":
					if _has("gx_fans"):
						GxFans.place(c, Gx.frame(c, a, side, 1.0), {kind = "banners", length = 36.0})
				"sign":
					if _has("gx_billboard"):
						GxBillboard.place(c, Gx.frame(c, a, side, 2.0), {kind = "sign", sign = ["fans", "crest", "speed"][rng.randi() % 3], speed = 50})
				"text":
					if _has("gx_road_text"):
						GxRoadText.place(c, Gx.road_frame(c, a), {kind = ["mixed", "name", "allez", "gogo", "flag"][rng.randi() % 5]})
				"cars":
					if _has("gx_parked_cars"):
						GxParkedCars.place(c, Gx.frame(c, a, side, 6.0), {count = 5, layout = "parallel", seed = rng.randi()})
			used.append(a)
			k += 1
			a += step
		else:
			a += 20.0


## No trees in the water: reserve every 30 m cell that is under (or just at)
## sea level and has dry land within 150 m (the open sea is already covered by
## themes.gd's big circles).
static func _shore_band(c: Node3D, level: float) -> void:
	var t = c.get("terrain")
	if not t is Terrain:
		return
	var span: float = (Terrain.N - 1) * (t as Terrain).cell
	var o: Vector2 = (t as Terrain).origin
	var step := 30.0
	var wet := func(x: float, z: float) -> bool: return (t as Terrain).surface_at(x, z) < level + 0.6
	var n := 0
	var x := o.x
	while x < o.x + span:
		var z := o.y
		while z < o.y + span:
			if wet.call(x, z) and _dry_near(wet, x, z):
				Gx.reserve(c, Vector3(x, level, z), 24.0)
				n += 1
			z += step
		x += step
	if OS.get_cmdline_user_args().has("--debug-dress"):
		print("DRESS shore band cells ", n)


static func _dry_near(wet: Callable, x: float, z: float) -> bool:
	for r: float in [60.0, 150.0]:
		for d: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r), Vector2(r, r) * 0.7, Vector2(-r, r) * 0.7, Vector2(r, -r) * 0.7, Vector2(-r, -r) * 0.7]:
			if not wet.call(x + d.x, z + d.y):
				return true
	return false
