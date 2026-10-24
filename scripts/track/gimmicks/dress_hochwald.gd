extends RefCounted
## Hochwald: 3 km of fast forest sweepers and one hairpin, clear high-summer
## weather. Identity: a German forest rally weekend. Own landmarks
## (lm_hochwald.gd): the Hochwaldschanze summer ski jump inside the loop, a
## forestry log yard on the south straight, hunters' high seats at the forest
## edges. Kit pieces (each only if its file exists): forest-road overpass on the
## north straight, timber barn / warehouse to drive through on the back
## straight, sponsor arch, WRC fan banks + flares at the hairpin and the big
## sweepers, photographers, forest camps with parked cars, graffiti on the
## bridge piers, painted fan messages in the braking zones, billboards, TV heli.
##
## Corners (along, m from the start line): hairpin L 2388, R 2732, R 1680,
## R 1168, L 1344, L 1524. Straights: 0-444 (main), 632-752, 756-948 (north/back),
## 2068-2204 (south), 2452-2536.

const P := "res://scripts/track/gimmicks/%s.gd"
const LM := "res://scripts/track/gimmicks/lm_hochwald.gd"


static func _piece(name: String) -> Script:
	var path := P % name
	return load(path) if ResourceLoader.exists(path) else null


static func _place(name: String, c: Node3D, xf: Transform3D, opts := {}) -> void:
	var s := _piece(name)
	if s != null:
		s.place(c, xf, opts)


static func dress(c: Node3D) -> void:
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c)
	var dbg := OS.get_cmdline_user_args().has("--debug-dress")
	var lm: Script = load(LM)
	var R := Gx.RIGHT
	var L := Gx.LEFT

	# ---- landmarks (big things first so the kit pieces see their reservations)
	var ok: bool = lm.ski_jump(c, [Vector2(270, -150), Vector2(300, -70), Vector2(230, -230), Vector2(330, 40), Vector2(250, 120)],
		[0.93, 0.6, 1.3, -0.5, 2.4])
	if dbg and not ok:
		print("DRESS ski jump: no site")
	lm.log_yard(c, Gx.frame(c, 2125.0, L, 9.0), 42.0)
	for hs: Array in [[560.0, L], [1060.0, R], [1910.0, L], [2610.0, R]]:
		var f := Gx.frame(c, hs[0], hs[1], 24.0)
		if Gx.clear_of_road(c, f.origin, 15.0):
			lm.high_seat(c, f)

	# ---- drive-under: forest-road bridge on the north straight, graffiti on its approach walls
	if _piece("gx_overpass"):
		_place("gx_overpass", c, Gx.road_frame(c, 692.0), {kind = "road", banner = "b_falke", graffiti = false})
		Gx.reserve(c, Gx.centre(c, 692.0), 24.0)
	_place("gx_graffiti", c, Gx.frame(c, 735.0, R, 5.0), {kind = "retaining", length = 26.0, height = 3.2})
	_place("gx_graffiti", c, Gx.frame(c, 650.0, L, 6.0), {length = 9.0})
	# ---- drive-through: timber barn on the back straight
	if _piece("gx_warehouse"):
		_place("gx_warehouse", c, Gx.road_frame(c, 860.0), {kind = "barn", length = 46.0})
		Gx.reserve(c, Gx.centre(c, 860.0), 30.0)
	_place("gx_graffiti", c, Gx.frame(c, 905.0, L, 6.0), {length = 8.0})
	# ---- sponsor gantry over the south straight, inflatable arch on the short one
	_place("gx_sponsor_arch", c, Gx.road_frame(c, 2160.0), {kind = "gantry", brand = "kronen", brand2 = "falke"})
	_place("gx_sponsor_arch", c, Gx.road_frame(c, 2494.0), {kind = "inflatable", brand = "falke"})

	# ---- WRC fan zones: outside of the big corners, photographers on the inside
	if _piece("gx_fans"):
		var fans := _piece("gx_fans")
		var zones := [
			[2388.0, 30, 3, "f_weber"], [2732.0, 22, 1, "f_hopp"], [1680.0, 20, 2, "f_lind"],
			[1168.0, 16, 1, ""], [1344.0, 18, 1, "f_novak"], [1524.0, 14, 1, ""],
		]
		for z: Array in zones:
			var along: float = z[0]
			var turn := _turn_at(c, along)
			fans.place(c, Gx.frame(c, along + 6.0, -turn, 9.0), {count = z[1], flares = z[2], flags = 3, banner = z[3], depth = 6.0})
			fans.place(c, Gx.frame(c, along - 4.0, turn, 6.0), {kind = "photographers"})
		# hairpin approach: a second bank on the inside + sponsor banners on the rail
		fans.place(c, Gx.frame(c, 2350.0, R, 8.0), {count = 12, flags = 2, flares = 1})
		fans.place(c, Gx.frame(c, 2370.0, L, 4.0), {kind = "banners", length = 50.0, keys = ["b_falke", "b_kronen", "b_spect", "b_press"]})
		fans.place(c, Gx.frame(c, 400.0, R, 4.0), {kind = "banners", length = 60.0, keys = ["b_kronen", "b_helios", "b_falke"]})
		fans.place(c, Gx.frame(c, 120.0, L, 9.0), {kind = "flags", count = 5, keys = ["flag_de", "flag_at", "flag_de", "flag_fan"]})
		# crest spectators: they come for the jump
		fans.place(c, Gx.frame(c, 1352.0, -_turn_at(c, 1344.0), 7.0), {kind = "flare"})

	# ---- painted fan messages on the tarmac: braking zones and crests
	_place("gx_road_text", c, Gx.road_frame(c, 2325.0), {text = "SPÄT BREMSEN!", color = "yellow"})
	_place("gx_road_text", c, Gx.road_frame(c, 392.0), {kind = "player"})
	_place("gx_road_text", c, Gx.road_frame(c, 1336.0), {kind = "gogo"})
	_place("gx_road_text", c, Gx.road_frame(c, 2694.0), {kind = "name"})
	_place("gx_road_text", c, Gx.road_frame(c, 1845.0), {kind = "heart"})
	_place("gx_road_text", c, Gx.road_frame(c, 1630.0), {kind = "allez"})
	# ---- billboards and fun signs
	for b: Array in [[210.0, R, "HALDEN TYRES"], [800.0, L, "BERGMANN"], [1440.0, R, "NORDLICHT"], [2010.0, L, "HELIOS BENZIN"]]:
		_place("gx_billboard", c, Gx.frame(c, b[0], b[1], 12.0), {brand = b[2]})
	_place("gx_billboard", c, Gx.frame(c, 1290.0, R, 1.5), {kind = "sign", sign = "crest"})
	_place("gx_billboard", c, Gx.frame(c, 2290.0, L, 1.5), {kind = "sign", sign = "fans"})
	_place("gx_billboard", c, Gx.frame(c, 2384.0, -_turn_at(c, 2388.0), 1.5), {kind = "sign", sign = "chevron", count = 4})
	# ---- spectator camps in the forest + parked spectator cars in the clearings
	for cp: Array in [[1000.0, R, "large"], [1850.0, L, "small"], [2560.0, R, "large"], [1250.0, L, "small"]]:
		var f := Gx.frame(c, cp[0], cp[1], 9.0)
		if Gx.clear_of_road(c, f.origin, 6.0):
			_place("gx_camp", c, f, {size = cp[2]})
	_place("gx_parked_cars", c, Gx.frame(c, 1030.0, R, 6.0), {count = 6, layout = "angled"})
	_place("gx_parked_cars", c, Gx.frame(c, 2600.0, R, 7.0), {count = 7, layout = "field"})
	# ---- density pass: something every ~300 m, alternating sides
	# graffiti piers / walls where the forest opens
	_place("gx_graffiti", c, Gx.frame(c, 815.0, R, 4.0), {kind = "pier", width = 1.6, height = 5.0})
	_place("gx_graffiti", c, Gx.frame(c, 1110.0, L, 5.0), {length = 10.0})
	_place("gx_graffiti", c, Gx.frame(c, 1960.0, R, 5.0), {kind = "retaining", length = 20.0, height = 3.0})
	_place("gx_graffiti", c, Gx.frame(c, 2450.0, R, 6.0), {length = 8.0})
	# more fan banks (8-9 total), smaller ones on the fast kinks
	if _piece("gx_fans"):
		var fans2 := _piece("gx_fans")
		for z: Array in [[2236.0, 14, 1], [2568.0, 12, 0], [520.0, 12, 1]]:
			var t := _turn_at(c, z[0])
			fans2.place(c, Gx.frame(c, z[0] + 4.0, -t if t != 0.0 else R, 8.0), {count = z[1], flares = z[2], flags = 2})
		fans2.place(c, Gx.frame(c, 40.0, R, 4.0), {kind = "banners", length = 70.0, keys = ["b_falke", "b_kronen", "b_falke", "b_press"]})
	# fun motorway sign bridge on the main straight (Würstchenbude / Vollgas)
	_place("gx_sign_gantry", c, Gx.road_frame(c, 270.0), {boards = [1, 4]})
	# forest fire lookout tower and a HV line striding over the lap
	_place("gx_tower", c, Gx.frame(c, 1480.0, L, 45.0), {kind = "fire_lookout"})
	_place("gx_power", c, Gx.road_frame(c, 1985.0), {kind = "pylon"})
	_place("gx_power", c, Gx.road_frame(c, 560.0), {kind = "poles", route = "along", side = R, lateral = 9.0})
	# roadworks lay-by on the back section
	_place("gx_works", c, Gx.frame(c, 1600.0, R, 7.0), {width = 34.0, machine = "excavator"})
	# more painted messages + signs
	_place("gx_road_text", c, Gx.road_frame(c, 1120.0), {text = "VOLLGAS!"})
	_place("gx_road_text", c, Gx.road_frame(c, 2190.0), {kind = "flag"})
	_place("gx_road_text", c, Gx.road_frame(c, 830.0), {kind = "arrows"})
	_place("gx_billboard", c, Gx.frame(c, 2640.0, L, 1.5), {kind = "sign", sign = "crest"})
	_place("gx_billboard", c, Gx.frame(c, 1150.0, R, 12.0), {brand = "OSTRA FILM"})
	_place("gx_billboard", c, Gx.frame(c, 2780.0, L, 12.0), {brand = "VALTER OIL"})
	_place("gx_parked_cars", c, Gx.frame(c, 1870.0, L, 6.0), {count = 5, layout = "parallel"})

	# wind turbines on the far ridge beyond the south section (gxstruct)
	_place("gx_turbine", c, Gx.frame(c, 1800.0, R, 170.0), {count = 3, spacing = 160.0})
	# ---- TV helicopter on its lap, a camera drone over the hairpin
	_place("gx_heli", c, Transform3D.IDENTITY, {livery = 1})
	_place("gx_heli", c, Gx.frame(c, 2388.0, -_turn_at(c, 2388.0), 6.0), {kind = "drone"})


## +1 right-hand corner, -1 left-hand, at `along`.
static func _turn_at(c: Node3D, along: float) -> float:
	var a := Gx.tangent(c, along - 12.0)
	var b := Gx.tangent(c, along + 12.0)
	return -signf(a.signed_angle_to(b, Vector3.UP))
