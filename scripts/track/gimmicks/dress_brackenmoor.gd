extends RefCounted
## Brackenmoor: open moorland in a thunderstorm. Identity: a 400 kV power line
## striding across the bog and wind turbines turning on the horizon, a riveted
## railway bridge and a concrete moor-road overpass you drive under, a timber
## barn you drive through on the main straight, a lonely stone pub ("The
## Drowned Lamb"), a motorway sign gantry in the middle of nowhere, roadworks,
## soaked WRC fans in waterproofs with red flares at every corner, camps,
## muddy parked cars, graffiti and painted names in every braking zone, the
## TV helicopter fighting the wind. Something every ~140 m, both sides.

const H := preload("res://scripts/track/gimmicks/lm_dress_b.gd")


static func dress(c: Node3D) -> void:
	load(H.DIR % "dress_shots").attach(c)
	var busy: Array = [0.0] # alongs taken (start gantry at 0)
	# --- over / through the road ---------------------------------------------
	if H.has("gx_overpass"): # riveted rail bridge early on the main straight
		var xf := Gx.road_frame(c, 95.0)
		H.put(c, "gx_overpass", xf, {kind = "rail", graffiti = false})
		Gx.reserve(c, xf.origin, 18.0)
		busy.append(95.0)
	if H.has("gx_warehouse"): # the barn, late on the straight
		var xf := Gx.road_frame(c, 250.0)
		H.put(c, "gx_warehouse", xf, {kind = "barn", length = 26.0})
		Gx.reserve(c, xf.origin, 16.0)
		busy.append(250.0)
	if H.has("gx_overpass"): # moor road bridge, graffiti on the walls below it
		var xf := Gx.road_frame(c, 1610.0)
		H.put(c, "gx_overpass", xf, {kind = "road", banner = "b_helios", graffiti = false})
		Gx.reserve(c, xf.origin, 18.0)
		busy.append(1610.0)
		for side: float in [Gx.LEFT, Gx.RIGHT]:
			H.put(c, "gx_graffiti", Gx.frame(c, 1632.0, side, 3.5), {kind = "retaining", length = 24.0, height = 2.6, seed = int(side + 5)})
	if H.has("gx_sign_gantry"):
		H.put(c, "gx_sign_gantry", Gx.road_frame(c, 1120.0), {boards = [4, 2]})
		busy.append(1120.0)
	H.put(c, "gx_sponsor_arch", Gx.road_frame(c, 1040.0), {kind = "inflatable", brand = "helios"})
	busy.append(1040.0)
	# --- landmarks -----------------------------------------------------------------
	load(H.DIR % "gx_pylons").line(c, Vector3(-170, 0, -40), Vector3(700, 0, 70), {spacing = 125.0})
	H.put(c, "gx_turbine", Gx.frame(c, 700.0, Gx.RIGHT, 150.0), {count = 4, spacing = 170.0})
	if H.has("gx_cottage"):
		var px := Gx.frame(c, 1225.0, Gx.RIGHT, 24.0)
		H.put(c, "gx_cottage", px, {kind = "pub"})
		H.put(c, "gx_parked_cars", Gx.frame(c, 1200.0, Gx.RIGHT, 12.0), {count = 6, layout = "field", seed = 2})
		H.views(c, [[px * Vector3(-8, 0, -18), px * Vector3(0, 0, 4)]])
		busy.append(1225.0)
	H.put(c, "gx_hospitality", Gx.frame(c, 40.0, Gx.RIGHT, 6.0), {})
	# --- fans with flares at every real corner (storm = red smoke everywhere) ------
	var banks := [[364.0, 24, 3, "f_lind"], [1864.0, 24, 3, "f_weber"], [868.0, 20, 2, "f_novak"],
		[1444.0, 20, 2, "f_hopp"], [1768.0, 16, 2, ""], [1252.0, 16, 2, "f_duval"], [780.0, 14, 2, ""],
		[588.0, 14, 2, "f_rossi"], [1352.0, 12, 1, ""], [1176.0, 12, 2, ""]]
	for b: Array in banks:
		var along: float = b[0]
		var side := H.outside(c, along)
		H.put(c, "gx_fans", Gx.frame(c, along + 6.0, side, 7.0),
			{count = b[1], flares = b[2], flags = 2, banner = b[3], depth = 7.0})
		H.put(c, "gx_fans", Gx.frame(c, along - 4.0, -side, 2.0), {kind = "photographers"})
		H.put(c, "gx_billboard", Gx.frame(c, along, side, 1.5), {kind = "sign", sign = "chevron", count = 3})
		busy.append(along)
	H.put(c, "gx_fans", Gx.frame(c, 0.0, Gx.LEFT, 3.0), {kind = "banners", length = 70.0})
	# --- camps on the moor -------------------------------------------------------
	H.put(c, "gx_camp", Gx.frame(c, 905.0, H.outside(c, 868.0), 18.0), {size = "large", seed = 3})
	H.put(c, "gx_camp", Gx.frame(c, 1830.0, Gx.RIGHT, 22.0), {size = "large", seed = 11})
	H.put(c, "gx_parked_cars", Gx.frame(c, 330.0, Gx.LEFT, 14.0), {count = 6})
	busy.append_array([905.0, 1830.0, 330.0])
	# --- the rest of the lap: something every ~140 m, alternating sides ----------
	H.fill(c, busy, 200.0, ["billboard", "bank", "graffiti", "cars", "bank_big", "works", "flags", "camp", "photo"],
		{flares = 2, brands = [0, 2, 3, 5, 6, 7], flag_keys = ["flag_ie", "flag_de", "flag_fi", "flag_fan"]})
	H.put(c, "gx_billboard", Gx.frame(c, 1180.0, Gx.RIGHT, 2.0), {kind = "sign", sign = "village", speed = 50})
	# --- names painted in every braking zone --------------------------------------
	H.put(c, "gx_road_text", Gx.road_frame(c, 1400.0), {text = "FLAT OUT", color = "yellow"})
	H.braking_text(c, ["GO LIND", {kind = "player"}, "WEBER!", {kind = "allez"}, "BRAKE LATE", {kind = "heart"},
		"NOVAK 1", {kind = "arrows"}, "HOPP!", {kind = "gogo"}], [1400.0])
	H.put(c, "gx_heli", Transform3D.IDENTITY, {alt_min = 70.0, alt_max = 110.0})
