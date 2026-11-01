extends RefCounted
## Herbstwald: autumn forest rally weekend. The track's own set pieces (rock cut
## and tunnel, stone bridge, sawmill, village and church, hunting lodge, small
## camps) are in theme_autumn.gd; this adds the shared Gx kit (each piece only
## if its file exists): big WRC forest camps on the two crests, flare-waving fan
## banks and photographers at the hairpin, painted fan messages on the crest
## straight, graffiti on the tunnel portals, the TV helicopter.

const P := "res://scripts/track/gimmicks/%s.gd"


static func _place(name: String, c: Node3D, xf: Transform3D, opts := {}) -> void:
	var path := P % name
	if ResourceLoader.exists(path):
		load(path).place(c, xf, opts)


## Lap distance of the centreline point nearest a world XZ point.
static func _along(c: Node3D, x: float, z: float) -> float:
	return Gx.curve(c).get_closest_offset(Vector3(x, Gx.ground(c, Vector3(x, 0, z)), z))


static func _turn_at(c: Node3D, along: float) -> float:
	var a := Gx.tangent(c, along - 15.0)
	var b := Gx.tangent(c, along + 15.0)
	return Gx.RIGHT if a.signed_angle_to(b, Vector3.UP) < 0.0 else Gx.LEFT


static func dress(c: Node3D) -> void:
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(c) # debug views (only with --dress_shots)
	var R := Gx.RIGHT
	var L := Gx.LEFT
	var crest1 := _along(c, 790, -323)
	var crest2 := _along(c, 982, -249)
	var hairpin := _along(c, 1214, -172)
	var tunnel_out := _along(c, 515, -400)
	var tunnel_in := _along(c, 430, -401)

	await Gx.breath(c) # let the loading screen draw
	# Forest camps just behind the fence on the crests (the classic jump spot).
	_place("gx_camp", c, Gx.frame(c, crest1 + 30.0, R, 9.0), {size = "large"})
	_place("gx_camp", c, Gx.frame(c, crest2 + 25.0, L, 9.0), {size = "small"})
	_place("gx_camp", c, Gx.frame(c, tunnel_out + 70.0, L, 9.0), {size = "small", cars = false})

	await Gx.breath(c) # let the loading screen draw
	# Fans with flares round the outside of the hairpin, photographers inside.
	var turn := _turn_at(c, hairpin)
	_place("gx_fans", c, Gx.frame(c, hairpin + 4.0, -turn, 9.0), {count = 30, flares = 3, flags = 3, depth = 6.0})
	_place("gx_fans", c, Gx.frame(c, hairpin - 30.0, -turn, 8.0), {count = 14, flares = 1, flags = 2})
	_place("gx_fans", c, Gx.frame(c, hairpin - 6.0, turn, 6.0), {kind = "photographers"})
	_place("gx_fans", c, Gx.frame(c, crest1 - 10.0, L, 6.0), {kind = "photographers"})

	await Gx.breath(c) # let the loading screen draw
	# Painted fan messages on the crest straight and the hairpin braking zone.
	_place("gx_road_text", c, Gx.road_frame(c, crest1 - 60.0), {})
	_place("gx_road_text", c, Gx.road_frame(c, crest2 - 45.0), {kind = "player"})
	_place("gx_road_text", c, Gx.road_frame(c, hairpin - 120.0), {kind = "allez"})

	await Gx.breath(c) # let the loading screen draw
	# Graffiti on the tunnel portal faces (the stone around the arch).
	var gpath := P % "gx_graffiti"
	if ResourceLoader.exists(gpath):
		var g = load(gpath)
		for e: Array in [[tunnel_in, -1.0], [tunnel_out, 1.0]]:
			var along: float = e[0]
			var out := Gx.tangent(c, along) * float(e[1])
			var right := Gx.tangent(c, along).cross(Vector3.UP).normalized()
			var ctr := Gx.centre(c, along)
			for side: float in [-1.0, 1.0]:
				var p := ctr + right * side * 16.5 + Vector3.UP * 2.6 + out * 0.06
				var b := Basis.looking_at(out, Vector3.UP) # -z out of the face, towards the viewer
				g.spray(c, Transform3D(b, p), Vector2(5.0, 2.2))

	await Gx.breath(c) # let the loading screen draw
	# The TV helicopter.
	_place("gx_heli", c, Gx.road_frame(c, hairpin), {})
