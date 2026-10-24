extends RefCounted
## Altstadt dressing (frugal: this is the track with the least fps margin).
## The town itself (rows of houses, market square with church + fountain, the
## gate tower) comes from themes.gd ("town"). On top of that:
##   - a second, plastered town gate (GxArch) over the north straight,
##   - modest fan banks on the outside of four corners,
##   - a fan zone along the front of the market square,
##   - a steel footbridge over the north straight,
##   - billboards, extra graffiti, painted road messages,
##   - landmark: a beer garden with festoon lights and a Bavarian maypole
##     (Maibaum) on the inside of the west hairpin (GxLandmarks).

const P := "res://scripts/track/gimmicks/"


static func _has(piece: String) -> bool:
	return ResourceLoader.exists(P + piece + ".gd")


static func _place(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if _has(piece):
		load(P + piece + ".gd").place(c, xf, opts)


static func dress(c: Node3D) -> void:
	if ResourceLoader.exists(P + "dress_shots.gd"):
		load(P + "dress_shots.gd").attach(c)
	var rng := Gx.rng(c, "dress")
	_landmark(c, rng)
	_square(c)
	_over_road(c)
	_art(c)
	if _has("gx_heli"):
		GxHeli.place(c, Transform3D.IDENTITY, {alt_min = 95.0})
	_fill(c, [300.0, 330.0, 422.0, 740.0, 866.0, 900.0, 939.0, 1314.0, 1400.0, 1490.0, 1556.0, 1600.0, 1690.0, 1734.0, 1770.0, 1826.0], ["graffiti", "text", "sign", "billboard", "graffiti", "banners", "text"])


## Beer garden + maypole on the inside of the hairpin at ~1440 m.
static func _landmark(c: Node3D, rng: RandomNumberGenerator) -> void:
	var at := 1400.0
	var xf := Gx.frame(c, at, Gx.RIGHT, 7.0)
	GxLandmarks.beer_garden(c, xf, {width = 17.0, depth = 12.0, rng = rng, people = 12})
	var mp := xf * Vector3(10.5, 0, 3.0)
	mp.y = Gx.ground(c, mp)
	GxLandmarks.maypole(c, mp, -xf.basis.z, {height = 26.0})


## Fans packed along the front of the market square (the square is on the
## left of the south straight, see themes.gd _market_square).
static func _square(c: Node3D) -> void:
	if not _has("gx_fans"):
		return
	var at := 422.0
	var sq = c.get_meta("town_square", null)
	if sq is Array:
		at = fposmod(Gx.curve(c).get_closest_offset(sq[0]) - float(c.get("start_offset")), Gx.length(c))
	GxFans.place(c, Gx.frame(c, at - 12.0, Gx.LEFT, 2.5), {count = 12, flags = 2, flares = 1, banner = "f_weber", depth = 4.0})
	GxFans.place(c, Gx.frame(c, at + 16.0, Gx.LEFT, 2.5), {count = 10, flags = 1, depth = 4.0})
	GxFans.place(c, Gx.frame(c, at + 2.0, Gx.LEFT, 2.0), {kind = "photographers"})


static func _over_road(c: Node3D) -> void:
	if _has("gx_overpass"):
		GxOverpass.place(c, Gx.road_frame(c, 1556.0), {kind = "footbridge", banner = "b_marzelli", graffiti = false})
		Gx.reserve(c, Gx.centre(c, 1556.0), 12.0)
	if _has("gx_arch"):
		GxArch.place(c, Gx.road_frame(c, 1734.0), {kind = "gate", material = "plaster", walls = 10.0})
		Gx.reserve(c, Gx.centre(c, 1734.0), 14.0)
	if _has("gx_fans"):
		for k: Array in [[1826.0, Gx.LEFT], [1690.0, Gx.LEFT], [1314.0, Gx.RIGHT], [866.0, Gx.LEFT]]:
			GxFans.place(c, Gx.frame(c, k[0], k[1], 5.0), {count = 10, flags = 1, flares = 1 if k[0] == 1826.0 else 0, banner = true})


static func _art(c: Node3D) -> void:
	if _has("gx_billboard"):
		GxBillboard.place(c, Gx.frame(c, 330.0, Gx.RIGHT, 3.0), {brand = "MARZELLI"})
		GxBillboard.place(c, Gx.frame(c, 900.0, Gx.LEFT, 3.0), {brand = "AUREL WATCHES"})
		GxBillboard.place(c, Gx.frame(c, 1600.0, Gx.LEFT, 3.0), {kind = "sign", sign = "village", speed = 30})
	if _has("gx_graffiti"):
		GxGraffiti.place(c, Gx.frame(c, 740.0, Gx.RIGHT, 2.5), {kind = "retaining", length = 22.0, height = 3.0})
		GxGraffiti.place(c, Gx.frame(c, 1770.0, Gx.LEFT, 2.5), {kind = "retaining", length = 18.0, height = 3.0})
	if _has("gx_road_text"):
		_place(c, "gx_road_text", Gx.road_frame(c, 300.0), {kind = "allez"})
		_place(c, "gx_road_text", Gx.road_frame(c, 1490.0), {kind = "name", color = "yellow"})
		_place(c, "gx_road_text", Gx.road_frame(c, 860.0), {kind = "arrows"})

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
