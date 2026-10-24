class_name GxSpot
extends RefCounted
## Finds a free spot beside the road for a big piece: the whole footprint
## (local x in [-hx, hx], z in [z0, z1] of a Gx.frame) must be clear of the
## road (any part of the lap), outside every Gx.reserve circle already taken
## by other pieces, and flat enough. Candidates are tried in `alongs` order on
## both sides at the given laterals.
##
##   var xf = GxSpot.find(c, GxSpot.near_start(c), [6.0, 10.0], 16.0, 0.0, 18.0, 2.5)
##   if xf != null: GxHospitality.place(c, xf, {})

## Candidate alongs every 20 m, nearest to the start/finish line first.
static func near_start(c: Node3D) -> Array:
	var l := Gx.length(c)
	var out := []
	var a := 0.0
	while a < l:
		out.append(a)
		a += 20.0
	out.sort_custom(func(p, q): return minf(p, l - p) < minf(q, l - q))
	return out


## Candidate alongs on straights (longest first), every 25 m.
static func on_straights(c: Node3D, min_len := 120.0) -> Array:
	var st := Gx.straights(c, min_len)
	st.sort_custom(func(p, q): return p.to - p.from > q.to - q.from)
	var out := []
	for s in st:
		var a: float = s.from + 30.0
		while a < s.to - 30.0:
			out.append(a)
			a += 25.0
	return out


## The first frame that fits, or null.
static func find(c: Node3D, alongs: Array, laterals: Array, hx: float, z0: float, z1: float, max_rise: float, margin := 3.0):
	var nt: Array = c.get_meta("no_trees", [])
	for along: float in alongs:
		for lat: float in laterals:
			for side: float in [Gx.RIGHT, Gx.LEFT]:
				var xf := Gx.frame(c, along, side, lat)
				if _fits(c, xf, nt, hx, z0, z1, max_rise, margin):
					return xf
	return null


static func _fits(c: Node3D, xf: Transform3D, nt: Array, hx: float, z0: float, z1: float, max_rise: float, margin: float) -> bool:
	var lo := INF
	var hi := -INF
	var nx := maxi(int(hx * 2.0 / 6.0), 2)
	var nz := maxi(int((z1 - z0) / 6.0), 2)
	for i in nx + 1:
		for j in nz + 1:
			var p := xf * Vector3(lerpf(-hx, hx, float(i) / nx), 0, lerpf(z0, z1, float(j) / nz))
			if not Gx.clear_of_road(c, p, margin):
				return false
			for res: Array in nt:
				var q: Vector3 = res[0]
				if Vector2(p.x - q.x, p.z - q.z).length() < float(res[1]):
					return false
			var h := Gx.ground(c, p)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			if hi - lo > max_rise:
				return false
	return true


## Batch-2 dressing for a track: the sky (no balloons in storm / snow), one
## hospitality village near the start/finish, one farm field on a straight
## (opts.farm = false to skip). Each only when its piece exists and a spot fits.
static func dress_batch2(c: Node3D, opts := {}) -> void:
	var dir := "res://scripts/track/gimmicks/%s.gd"
	var wx = c.get("weather")
	var pr: Dictionary = wx.get("preset") if wx != null and wx.get("preset") is Dictionary else {}
	var rough := float(pr.get("snow", 0.0)) > 0.2 or float(pr.get("wet", 0.0)) > 0.5
	if ResourceLoader.exists(dir % "gx_sky"):
		load(dir % "gx_sky").place(c, Transform3D.IDENTITY, {balloons = 0 if rough else int(opts.get("balloons", 3)), blimp = true, brand = opts.get("brand", "b_helios")})
	if ResourceLoader.exists(dir % "gx_hospitality"):
		var xf = find(c, near_start(c).slice(0, 40), [8.0, 14.0, 22.0], 16.5, 0.0, 18.5, 3.0)
		if xf != null:
			load(dir % "gx_hospitality").place(c, xf, opts.get("hospitality", {}))
			print("gx_spot: hospitality at ", (xf as Transform3D).origin)
	if GxCamp._b(opts.get("farm", true)) and ResourceLoader.exists(dir % "gx_farm"):
		var xf = find(c, on_straights(c), [10.0, 18.0, 30.0], 36.0, 0.0, 50.0, 7.0)
		if xf != null:
			load(dir % "gx_farm").place(c, xf, opts.get("farm_opts", {}))
			print("gx_spot: farm at ", (xf as Transform3D).origin)
