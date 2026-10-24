extends RefCounted
## Shared helpers for dress_brackenmoor.gd / dress_schneekopf.gd: guarded
## piece calls, corner sides, a density filler (something every ~140 m on
## alternating sides) and painted messages in every braking zone.

const DIR := "res://scripts/track/gimmicks/%s.gd"


static func has(piece: String) -> bool:
	return ResourceLoader.exists(DIR % piece)


static func put(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if has(piece):
		load(DIR % piece).place(c, xf, opts)


## Outside of the corner at `along` (+1 right / -1 left).
static func outside(c: Node3D, along: float) -> float:
	var t0 := Gx.tangent(c, along - 12.0)
	var t1 := Gx.tangent(c, along + 12.0)
	return Gx.RIGHT if t0.signed_angle_to(t1, Vector3.UP) > 0.0 else Gx.LEFT


static func free_at(busy: Array, along: float, gap: float, L: float) -> bool:
	for b: float in busy:
		var d := absf(fposmod(along - b + L * 0.5, L) - L * 0.5)
		if d < gap:
			return false
	return true


## Fill the lap: every `step` m (skipping `busy` spots) one item from `items`
## in turn, alternating sides. Items: "bank", "bank_big", "billboard",
## "graffiti", "cars", "camp", "flags", "works", "photo".
static func fill(c: Node3D, busy: Array, step: float, items: Array, opts := {}) -> void:
	var L := Gx.length(c)
	var rng := Gx.rng(c, "fill")
	var k := 0
	var a := step * 0.6
	var flares: int = opts.get("flares", 1)
	var brands: Array = opts.get("brands", [0, 1, 2, 3, 4, 5])
	var banners: Array = ["f_weber", "f_rossi", "f_lind", "f_hopp", "f_novak", "f_duval"]
	while a < L - 40.0:
		if not free_at(busy, a, 38.0, L):
			a += 20.0
			continue
		var side := Gx.LEFT if k % 2 == 0 else Gx.RIGHT
		var item: String = items[k % items.size()]
		match item:
			"bank":
				put(c, "gx_fans", Gx.frame(c, a, side, 7.0), {count = rng.randi_range(10, 16), flares = flares, flags = rng.randi_range(1, 3),
					banner = banners[rng.randi() % banners.size()] if rng.randf() < 0.5 else ""})
			"bank_big":
				put(c, "gx_fans", Gx.frame(c, a, side, 7.0), {count = rng.randi_range(16, 22), flares = flares + 1, flags = 3, banner = true, depth = 7.0})
				put(c, "gx_billboard", Gx.frame(c, a - 45.0, side, 2.0), {kind = "sign", sign = "fans"})
			"billboard":
				put(c, "gx_billboard", Gx.frame(c, a, side, 8.0), {brand = brands[k % brands.size()]})
			"graffiti":
				put(c, "gx_graffiti", Gx.frame(c, a, side, 5.0), {kind = "wall" if k % 3 != 0 else "retaining", length = rng.randf_range(9.0, 18.0),
					height = rng.randf_range(2.4, 3.2), seed = k})
			"cars":
				put(c, "gx_parked_cars", Gx.frame(c, a, side, 12.0), {count = rng.randi_range(4, 7), layout = ["angled", "field", "parallel"][k % 3], seed = k})
			"camp":
				put(c, "gx_camp", Gx.frame(c, a, side, 16.0), {size = "small", seed = 20 + k})
			"flags":
				put(c, "gx_fans", Gx.frame(c, a, side, 6.0), {kind = "flags", count = 4, keys = opts.get("flag_keys", [])})
				put(c, "gx_fans", Gx.frame(c, a + 8.0, side, 6.0), {count = 8, flares = flares, flags = 1})
			"works":
				put(c, "gx_works", Gx.frame(c, a, side, 6.5), {width = 36.0})
			"photo":
				put(c, "gx_fans", Gx.frame(c, a, side, 4.0), {kind = "photographers"})
				put(c, "gx_fans", Gx.frame(c, a, side, 6.0), {kind = "banners", length = 40.0})
		Gx.reserve(c, Gx.frame(c, a, side, 10.0).origin, 12.0)
		busy.append(a)
		k += 1
		a += step


## Hand-painted fan messages in the braking zone of every real corner.
static func braking_text(c: Node3D, texts: Array, skip: Array) -> void:
	if not has("gx_road_text"):
		return
	var L := Gx.length(c)
	var done: Array = skip.duplicate()
	var k := 0
	for corner in Gx.corners(c, 0.4):
		var a := fposmod(float(corner.along) - 55.0, L)
		if not free_at(done, a, 45.0, L):
			continue
		var t = texts[k % texts.size()]
		if t is Dictionary:
			put(c, "gx_road_text", Gx.road_frame(c, a), t)
		else:
			put(c, "gx_road_text", Gx.road_frame(c, a), {text = str(t), color = "yellow" if k % 3 == 1 else "white"})
		done.append(a)
		k += 1


## Extra debug camera views (only when --dress_shots is on).
static func views(c: Node3D, list: Array) -> void:
	for n in c.get_children():
		if n.get_script() == load(DIR % "dress_shots"):
			for v: Array in list:
				var p: Vector3 = v[0]
				var q: Vector3 = v[1]
				p.y = Gx.ground(c, p) + 2.5
				q.y = Gx.ground(c, q) + 5.0
				n.views.append([p, q])
