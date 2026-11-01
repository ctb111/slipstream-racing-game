extends RefCounted
## Valle Club: a 1.3 km Italian club circuit in the hills, all hairpins and
## braking, sunny. Identity: a wine valley rally weekend. Own landmark
## (lm_valle.gd): the Tenuta Valle wine estate (vine rows down the slope,
## ochre farmhouse with a dovecote tower, cypress avenue). Kit pieces (each
## only if its file exists): a local-railway bridge over the end of the main
## straight (drive-under), an inflatable / sponsor arch, packed Italian fan
## banks with flares at the hairpins, photographers, graffiti on the bridge
## abutments, FORZA / VAI messages painted in the braking zones, billboards,
## a fan camp with parked cars, the TV helicopter over turn 1.
##
## Corners (along, m from the start line): T1 R 196, R 288, L 352, L 424,
## R 500, R 572, R 668, L 736, L 812, R 884, R 964, R 1076, L 1136, R 1164.
## Straight: 0-160 (main).

const P := "res://scripts/track/gimmicks/%s.gd"
const LM := "res://scripts/track/gimmicks/lm_valle.gd"


static func _piece(name: String) -> Script:
	var path := P % name
	return load(path) if ResourceLoader.exists(path) else null


static func _place(name: String, c: Node3D, xf: Transform3D, opts := {}) -> void:
	var s := _piece(name)
	if s != null:
		s.place(c, xf, opts)


static func dress(c: Node3D) -> void:
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c)
	var R := Gx.RIGHT
	var L := Gx.LEFT

	await Gx.breath(c) # let the loading screen draw
	# ---- landmark: the wine estate on the best slope
	load(LM).estate(c)

	await Gx.breath(c) # let the loading screen draw
	# ---- drive-under: local railway bridge over the end of the main straight
	if _piece("gx_overpass"):
		_place("gx_overpass", c, Gx.road_frame(c, 118.0), {kind = "rail", banner = "b_valter", graffiti = false})
		Gx.reserve(c, Gx.centre(c, 118.0), 22.0)
	_place("gx_graffiti", c, Gx.frame(c, 95.0, L, 5.0), {kind = "retaining", length = 18.0, height = 3.0})
	_place("gx_graffiti", c, Gx.frame(c, 140.0, R, 5.0), {length = 9.0})
	await Gx.breath(c) # let the loading screen draw
	# ---- the village gate (ochre render, clock tower) on the run to the last corners
	_place("gx_arch", c, Gx.road_frame(c, 1104.0), {kind = "gate", material = "plaster", walls = 10.0})
	await Gx.breath(c) # let the loading screen draw
	# ---- sponsor structures
	_place("gx_sponsor_arch", c, Gx.road_frame(c, 30.0), {kind = "gantry", brand = "valter", brand2 = "marzelli"})
	_place("gx_sponsor_arch", c, Gx.road_frame(c, 780.0), {kind = "inflatable", brand = "marzelli"})

	await Gx.breath(c) # let the loading screen draw
	# ---- fan banks at the hairpins, photographers on the inside
	if _piece("gx_fans"):
		var fans := _piece("gx_fans")
		var flags := ["flag_it", "flag_it", "flag_fan", "flag_chk", "flag_it"]
		var zones := [
			[196.0, 28, 3, "f_rossi"], [500.0, 18, 1, ""], [668.0, 20, 2, "f_duval"], [736.0, 14, 1, ""],
			[884.0, 22, 2, "f_weber"], [1164.0, 24, 2, "f_rossi"], [288.0, 12, 0, ""],
		]
		for z: Array in zones:
			var along: float = z[0]
			var turn := _turn_at(c, along)
			fans.place(c, Gx.frame(c, along + 5.0, -turn, 8.0), {count = z[1], flares = z[2], flags = 3, banner = z[3], depth = 6.0})
			fans.place(c, Gx.frame(c, along - 3.0, turn, 6.0), {kind = "photographers"})
		fans.place(c, Gx.frame(c, 150.0, L, 4.0), {kind = "banners", length = 60.0, keys = ["b_valter", "b_marzelli", "b_spect"]})
		fans.place(c, Gx.frame(c, 40.0, R, 10.0), {kind = "flags", count = 6, keys = flags})
		fans.place(c, Gx.frame(c, 820.0, R, 9.0), {kind = "flags", count = 4, keys = flags})

	await Gx.breath(c) # let the loading screen draw
	# ---- painted messages in the braking zones (Italian fans)
	_place("gx_road_text", c, Gx.road_frame(c, 152.0), {text = "FORZA!", color = "yellow"})
	_place("gx_road_text", c, Gx.road_frame(c, 462.0), {kind = "player"})
	_place("gx_road_text", c, Gx.road_frame(c, 640.0), {text = "VAI VAI VAI"})
	_place("gx_road_text", c, Gx.road_frame(c, 852.0), {kind = "name"})
	_place("gx_road_text", c, Gx.road_frame(c, 1124.0), {kind = "heart"})
	await Gx.breath(c) # let the loading screen draw
	# ---- billboards and signs
	for b: Array in [[62.0, L, "MARZELLI"], [330.0, R, "VALTER OIL"], [940.0, L, "AUREL WATCHES"]]:
		_place("gx_billboard", c, Gx.frame(c, b[0], b[1], 12.0), {brand = b[2]})
	_place("gx_billboard", c, Gx.frame(c, 1060.0, R, 2.0), {kind = "sign", sign = "village", speed = 50})
	_place("gx_billboard", c, Gx.frame(c, 192.0, -_turn_at(c, 196.0), 1.5), {kind = "sign", sign = "chevron", count = 4})
	await Gx.breath(c) # let the loading screen draw
	# ---- fan camp + parked cars on the outside of the back section
	var f := Gx.frame(c, 600.0, L, 9.0)
	if Gx.clear_of_road(c, f.origin, 6.0):
		pass # large camp dropped for the frame budget
	_place("gx_parked_cars", c, Gx.frame(c, 990.0, L, 7.0), {count = 7, layout = "field"})
	await Gx.breath(c) # let the loading screen draw
	# ---- density pass (cheap pieces only: this track is tight on frame time)
	# lots of graffiti: the valley kids' walls
	_place("gx_graffiti", c, Gx.frame(c, 250.0, L, 5.0), {length = 9.0})
	_place("gx_graffiti", c, Gx.frame(c, 395.0, R, 6.0), {kind = "retaining", length = 16.0, height = 2.8})
	_place("gx_graffiti", c, Gx.frame(c, 560.0, R, 5.0), {length = 8.0})
	_place("gx_graffiti", c, Gx.frame(c, 980.0, R, 5.0), {kind = "pier", width = 1.5, height = 4.5})
	_place("gx_graffiti", c, Gx.frame(c, 1210.0, L, 5.0), {length = 10.0})
	await Gx.breath(c) # let the loading screen draw
	# big b_valter banner run on the start straight
	if _piece("gx_fans"):
		_piece("gx_fans").place(c, Gx.frame(c, 80.0, R, 4.0), {kind = "banners", length = 90.0, keys = ["b_valter", "b_valter", "b_marzelli", "b_press"]})
	await Gx.breath(c) # let the loading screen draw
	# painted messages on the crest and in the remaining braking zones
	_place("gx_road_text", c, Gx.road_frame(c, 335.0), {kind = "gogo"})
	_place("gx_road_text", c, Gx.road_frame(c, 272.0), {text = "DAI!", color = "yellow"})
	_place("gx_road_text", c, Gx.road_frame(c, 720.0), {kind = "allez"})
	_place("gx_road_text", c, Gx.road_frame(c, 560.0), {kind = "arrows"})
	await Gx.breath(c) # let the loading screen draw
	# signs
	_place("gx_billboard", c, Gx.frame(c, 320.0, L, 1.5), {kind = "sign", sign = "crest"})
	_place("gx_billboard", c, Gx.frame(c, 480.0, R, 1.5), {kind = "sign", sign = "fans"})
	_place("gx_billboard", c, Gx.frame(c, 700.0, R, 12.0), {brand = "HELIOS BENZIN"})
	await Gx.breath(c) # let the loading screen draw
	# a sponsor water tower on the hill, seen from all round the lap
	# wooden power poles along the back section
	_place("gx_power", c, Gx.road_frame(c, 620.0), {kind = "poles", route = "along", side = L, lateral = 10.0, reach = 120.0})

	await Gx.breath(c) # let the loading screen draw
	# motorway sign bridge mid-straight and two turbines on the far hill (gxstruct)
	_place("gx_sign_gantry", c, Gx.road_frame(c, 72.0), {boards = [3, 1]})
	_place("gx_turbine", c, Gx.frame(c, 900.0, L, 210.0), {count = 2, spacing = 170.0})
	await Gx.breath(c) # let the loading screen draw
	# ---- TV helicopter (no drone here: perf budget)
	_place("gx_heli", c, Transform3D.IDENTITY, {livery = 2})


static func _turn_at(c: Node3D, along: float) -> float:
	var a := Gx.tangent(c, along - 10.0)
	var b := Gx.tangent(c, along + 10.0)
	return -signf(a.signed_angle_to(b, Vector3.UP))
