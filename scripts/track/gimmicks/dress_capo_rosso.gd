extends RefCounted
## Capo Rosso: Riviera hill circuit. The theme (theme_mediterranean.gd) builds
## the harbour, fish market, village, arch and terraces; this adds the rally
## crowd: fans with red flares and banners at the hairpins on the climb and the
## cliff corners, photographers, painted names on the tarmac up the hill,
## graffiti retaining walls on the climb, sponsor banners at the start.
## Positions are metres from the start line; the village street and the market
## hall are left alone (no room behind the rails there).

const DIR := "res://scripts/track/gimmicks/%s.gd"
const VILLAGE := [1480.0, 1930.0] ## along-range of the village street (+ approach)
const MARKET := [215.0, 320.0]


static func _has(piece: String) -> bool:
	return ResourceLoader.exists(DIR % piece)


static func _put(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if _has(piece):
		load(DIR % piece).place(c, xf, opts)


static func _busy(along: float) -> bool:
	return (along > VILLAGE[0] and along < VILLAGE[1]) or (along > MARKET[0] and along < MARKET[1]) or along < 60.0


static func dress(c: Node3D) -> void:
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c) # debug views (only with --dress_shots)
	var rng := Gx.rng(c, "dress")
	await Gx.breath(c) # let the loading screen draw
	# --- fans at the best corners (outside), flares and Italian/French flags ----
	if _has("gx_fans"):
		var banners := ["f_rossi", "f_duval", "f_weber", "f_lind", "f_hopp"]
		var made := 0
		for corner in Gx.corners(c, 0.3):
			if made >= 7:
				break
			var along: float = corner.along
			if _busy(along):
				continue
			var side := -float(corner.turn)
			_put(c, "gx_fans", Gx.frame(c, along + 5.0, side, 7.0),
				{count = 18 + rng.randi_range(0, 12), flares = 1 + made % 3, flags = 2, depth = 6.0,
				banner = banners[made % banners.size()] if made < banners.size() else ""})
			if made % 2 == 0:
				_put(c, "gx_fans", Gx.frame(c, along - 8.0, -side, 5.0), {kind = "photographers"})
			made += 1
		_put(c, "gx_fans", Gx.frame(c, 0.0, Gx.RIGHT, 3.0), {kind = "banners", length = 60.0})
		_put(c, "gx_fans", Gx.frame(c, 1460.0, Gx.LEFT, 4.0), {kind = "flags", count = 4, keys = ["flag_it", "flag_fr"]})
	await Gx.breath(c) # let the loading screen draw
	# --- painted names and cheers on the climb and the cliff road ---------------
	if _has("gx_road_text"):
		for b: Array in [[1060.0, "FORZA"], [1250.0, "VAI!"], [1990.0, "ROSSI"], [2420.0, "ALLEZ!"], [2700.0, "FLAT OUT"]]:
			_put(c, "gx_road_text", Gx.road_frame(c, b[0]), {text = b[1]})
	else:
		var kit := TracksideKit.shared(c)
		for a: float in [1040.0, 1980.0, 2400.0]:
			kit.road_messages(kit.idx(a), 4)
	await Gx.breath(c) # let the loading screen draw
	# --- graffiti on retaining walls up the climb ----------------------------------
	if _has("gx_graffiti"):
		for g: Array in [[1120.0, 28.0, 1], [1330.0, 22.0, 2], [2240.0, 18.0, 3]]:
			var along: float = g[0]
			var side := -_outside(c, along)
			_put(c, "gx_graffiti", Gx.frame(c, along, side, 8.6), {kind = "retaining", length = g[1], height = 2.8, seed = g[2]}) # 2 m behind the rail
	if _has("gx_camp"):
		_put(c, "gx_camp", Gx.frame(c, 2580.0, Gx.RIGHT, 20.0), {size = "small", seed = 5})
	if _has("gx_heli"):
		_put(c, "gx_heli", Gx.frame(c, 2650.0, Gx.LEFT, 60.0), {height = 70.0})


## Outside of the corner at `along`.
static func _outside(c: Node3D, along: float) -> float:
	var t0 := Gx.tangent(c, along - 12.0)
	var t1 := Gx.tangent(c, along + 12.0)
	return Gx.RIGHT if t0.signed_angle_to(t1, Vector3.UP) > 0.0 else Gx.LEFT
