extends RefCounted
## Schneekopf: a mountain circuit in a blizzard. Identity: a double chairlift
## climbing the slope and swinging over the road with its chairs moving, the
## Schneekopfhütte at the hairpin with its windows glowing, a concrete tunnel
## on the downhill main straight, a radio mast on the summit, an autobahn
## sign gantry pointing to "Nirgendwo", snowed-in roadworks, frozen WRC fans
## in puffer jackets with flares at the corners, winter camps with campfire
## smoke, snowed-in cars, painted names in every braking zone, the TV heli.
## Something every ~140 m, both sides.

const H := preload("res://scripts/track/gimmicks/lm_dress_b.gd")


static func dress(c: Node3D) -> void:
	load(H.DIR % "dress_shots").attach(c)
	var busy: Array = [0.0]
	await Gx.breath(c) # let the loading screen draw
	# --- over / through the road ---------------------------------------------
	if H.has("gx_warehouse"): # concrete tunnel on the downhill main straight
		var xf := Gx.road_frame(c, 110.0)
		H.put(c, "gx_warehouse", xf, {kind = "tunnel", length = 46.0})
		Gx.reserve(c, xf.origin, 26.0)
		busy.append(110.0)
	H.put(c, "gx_sign_gantry", Gx.road_frame(c, 180.0), {boards = [0, 4]})
	busy.append(180.0)
	H.put(c, "gx_sponsor_arch", Gx.road_frame(c, 1220.0), {kind = "inflatable", brand = "kronen"})
	busy.append(1220.0)
	await Gx.breath(c) # let the loading screen draw
	# --- landmarks ---------------------------------------------------------------
	var lift := _lift_line(c)
	if not lift.is_empty():
		load(H.DIR % "gx_skilift").line(c, lift[0], lift[1], {})
		var mid: Vector3 = (lift[0] + lift[1]) * 0.5
		busy.append(fposmod(Gx.curve(c).get_closest_offset(mid) - float(c.get("start_offset")), Gx.length(c)))
		H.views(c, [[mid + Vector3(25, 0, 25), mid], [mid + Vector3(4, 0, -6), lift[0].lerp(lift[1], 0.35)]])
	if H.has("gx_cottage"):
		var hx := Gx.frame(c, 1336.0, H.outside(c, 1336.0), 26.0)
		H.put(c, "gx_cottage", hx, {kind = "hut"})
		H.views(c, [[hx * Vector3(-6, 0, -16), hx * Vector3(0, 0, 4)]])
	H.put(c, "gx_tower", Gx.frame(c, 480.0, Gx.LEFT, 60.0), {kind = "radio_mast"})
	H.put(c, "gx_turbine", Gx.frame(c, 1000.0, Gx.RIGHT, 190.0), {count = 3, spacing = 160.0}) # valley-side ridge, not the summit (gxstruct)
	H.put(c, "gx_hospitality", Gx.frame(c, 40.0, Gx.LEFT, 6.0), {})
	await Gx.breath(c) # let the loading screen draw
	# --- frozen fans with flares at every real corner ---------------------------
	var banks := [[1336.0, 24, 2, "f_hopp"], [276.0, 22, 2, "f_lind"], [804.0, 20, 2, "f_weber"],
		[716.0, 16, 1, ""], [628.0, 16, 1, "f_novak"], [1092.0, 14, 1, ""], [548.0, 14, 1, "f_rossi"],
		[1004.0, 12, 1, ""], [1184.0, 12, 0, ""]]
	for b: Array in banks:
		var along: float = b[0]
		var side := H.outside(c, along)
		H.put(c, "gx_fans", Gx.frame(c, along + 6.0, side, 7.0),
			{count = b[1], flares = b[2], flags = 2, banner = b[3], depth = 7.0})
		H.put(c, "gx_fans", Gx.frame(c, along - 4.0, -side, 2.0), {kind = "photographers"})
		H.put(c, "gx_billboard", Gx.frame(c, along, side, 1.5), {kind = "sign", sign = "chevron", count = 3})
		busy.append(along)
	H.put(c, "gx_fans", Gx.frame(c, 0.0, Gx.RIGHT, 3.0), {kind = "banners", length = 60.0,
		keys = ["b_kronen", "b_nordlicht", "b_rallye", "b_spect"]})
	await Gx.breath(c) # let the loading screen draw
	# --- winter camps + snowed-in cars --------------------------------------------
	H.put(c, "gx_camp", Gx.frame(c, 300.0, H.outside(c, 276.0), 18.0), {size = "large", seed = 5})
	H.put(c, "gx_camp", Gx.frame(c, 840.0, H.outside(c, 804.0), 18.0), {size = "large", seed = 9})
	H.put(c, "gx_parked_cars", Gx.frame(c, 1290.0, Gx.LEFT, 14.0), {count = 6, layout = "parallel"})
	busy.append_array([300.0, 840.0, 1290.0])
	await Gx.breath(c) # let the loading screen draw
	# --- the rest of the lap: something every ~140 m, alternating sides ----------
	H.fill(c, busy, 200.0, ["billboard", "bank", "cars", "camp", "flags", "graffiti", "works", "bank_big", "photo"],
		{flares = 1, brands = [1, 4, 0, 6], flag_keys = ["flag_at", "flag_de", "flag_ch", "flag_no", "flag_fan"]})
	H.put(c, "gx_billboard", Gx.frame(c, 420.0, Gx.RIGHT, 2.0), {kind = "sign", sign = "crest"})
	await Gx.breath(c) # let the loading screen draw
	# --- names painted in every braking zone --------------------------------------
	H.braking_text(c, ["HOPP HOPP!", {kind = "player"}, "SERVUS", {kind = "allez"}, "LIND!", {kind = "heart"},
		"WEBER", {kind = "arrows"}, "VOLLGAS", {kind = "gogo"}], [])
	H.put(c, "gx_heli", Transform3D.IDENTITY, {alt_min = 70.0, alt_max = 120.0})


## Pick the chairlift line: crosses the road once, climbs the most, both ends
## well off the circuit. Deterministic (pure geometry).
static func _lift_line(c: Node3D) -> Array:
	var best := []
	var best_score := -INF
	var L := Gx.length(c)
	var a := 300.0
	while a < L - 60.0:
		var p := Gx.centre(c, a)
		var t := Gx.tangent(c, a)
		var r := t.cross(Vector3.UP).normalized()
		for skew: float in [-0.5, 0.0, 0.5]:
			var d := (r * cos(skew) + t * sin(skew)).normalized()
			for half: float in [110.0, 150.0]:
				var e0 := p - d * half
				var e1 := p + d * half
				if not Gx.clear_of_road(c, e0, 25.0) or not Gx.clear_of_road(c, e1, 25.0):
					continue
				# count road crossings along the line
				var inside := false
				var crossings := 0
				for k in 61:
					var q := e0.lerp(e1, k / 60.0)
					var now := not Gx.clear_of_road(c, q, 3.0)
					if now and not inside:
						crossings += 1
					inside = now
				if crossings != 1:
					continue
				var h0 := Gx.ground(c, e0)
				var h1 := Gx.ground(c, e1)
				var score := absf(h1 - h0) - absf(skew) * 4.0
				if score > best_score:
					best_score = score
					best = [e0, e1] if h1 > h0 else [e1, e0]
		a += 20.0
	return best
