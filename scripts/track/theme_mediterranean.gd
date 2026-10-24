extends TrackThemes
## "mediterranean" theme (Capo Rosso): the coast theme's sea, cliffs, harbour
## and lighthouse, plus
##  - a hilltop village of ochre and terracotta houses the road threads through,
##    a campanile, and a stone arch carrying a house over the road,
##  - a covered fish market on the harbour front that the road drives through,
##  - dry-stone walls along the road, terraced hillsides with olive groves,
##  - Mediterranean flora: stone (umbrella) pines, cypresses, olives, maquis,
##  - painted shop signs and graffiti on the harbour and market walls.
## The def gives anchors (nearest lap point): `village` [from, to], `arch_at`,
## `market_at`. Everything is merged/MultiMesh'd through TrackThemes' batching.

const OCHRE := [Color(0.86, 0.56, 0.28), Color(0.9, 0.68, 0.36), Color(0.78, 0.44, 0.26), Color(0.92, 0.78, 0.5),
	Color(0.76, 0.36, 0.24), Color(0.94, 0.86, 0.68), Color(0.86, 0.5, 0.38), Color(0.9, 0.74, 0.4),
	Color(0.82, 0.62, 0.42), Color(0.95, 0.66, 0.5)]
const TERRACOTTA := [Color(0.74, 0.4, 0.27), Color(0.68, 0.35, 0.24), Color(0.8, 0.47, 0.32), Color(0.62, 0.32, 0.22),
	Color(0.77, 0.52, 0.36)]
const SHOPS_IT := ["PANETTERIA", "ALIMENTARI", "TABACCHI", "FARMACIA", "BAR SPORT", "TRATTORIA DA NINO",
	"GELATERIA", "PESCHERIA", "MACELLERIA", "OSTERIA DEL PORTO", "FERRAMENTA", "CAFFÈ CENTRALE"]
## Spray-painted fan messages on the harbour walls (invented names, no real people).
const GRAFFITI := ["FORZA RINALDI!", "VAI MARCO", "ALLEZ LES BLEUS", "CAPO ROSSO 1974", "FLAT OUT!",
	"GRAZIE RAGAZZI", "PIEDE GIÙ", "DAJE!"]

var v0 := 0 ## village from..to (lap sample indices, forward)
var v1 := 0
var market_i := -1
var _zones := {}
var _cats: Array[Transform3D] = [] ## wildlife: cats on wall tops (sit at origin, face -Z)
var _perches: Array[Transform3D] = [] ## wildlife: pigeons / gulls on eaves and walls


func _mediterranean() -> void:
	_med_atlas()
	mats.drystone = _triplanar("stone_wall", 0.3, 0.95)
	vis.drystone = 800.0
	_flora_meshes()
	v0 = _anchor(def.get("village", [Vector3.ZERO, Vector3.ZERO])[0])
	v1 = _anchor(def.get("village", [Vector3.ZERO, Vector3.ZERO])[1])
	market_i = _anchor(def.get("market_at", centers[0]))
	# Built structures claim their ground first, then the coast, then filler.
	_market_hall(market_i)
	_harbour_sheds(market_i)
	_arch(_anchor(def.get("arch_at", centers[v0])))
	_campanile()
	_village_rows()
	_coast()
	_village_infill()
	_zones = Vegetation.zone_grid(no_trees, 20.0)
	_stone_walls()
	_terraces()
	_flora()
	parent.set_meta("cat_spots", _cats)
	parent.set_meta("perch_spots", _perches)
	_debug("village %d..%d, market %d, %d triangles" % [v0, v1, market_i, stats.tris])


# ---------------------------------------------------------------- helpers

## Dry-stone walls and terraces are many small boxes: no shadow casting
## (they sit on the ground; saves the shadow pass most of their triangles).
func _flush() -> void:
	super._flush()
	for ch in parent.get_children():
		if ch is MeshInstance3D and str(ch.name).begins_with("Theme_drystone"):
			(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _anchor(p: Vector3) -> int:
	var best := INF
	var bi := 0
	for i in n:
		var d: float = Vector2(centers[i].x - p.x, centers[i].z - p.z).length_squared()
		if d < best:
			best = d
			bi = i
	return bi


func _in_village(i: int, pad := 0) -> bool:
	var a := _i(v0 - pad)
	var b := _i(v1 + pad)
	i = _i(i)
	return (i >= a and i <= b) if a <= b else (i >= a or i <= b)


func _near_market(i: int, pad := 20) -> bool:
	if market_i < 0:
		return false
	var d := absi(_i(i) - market_i)
	return mini(d, n - d) <= pad


func _harbour_walls() -> Array:
	return OCHRE


## Southern villas: ochre and pink render, low terracotta roofs.
func _villas() -> void:
	var sea3 := Vector3(_sea.x, 0, _sea.y)
	var placed := 0
	for tries in 900:
		if placed >= 40:
			break
		var i := rng.randi() % n
		if _in_village(i, 30) or _near_market(i, 30):
			continue
		var cs: Vector2 = _cs(centers[i])
		if cs.y < _ref[_bin(cs.x)] - 140.0:
			continue
		var side := 1.0 if rights[i].dot(sea3) < 0.0 else -1.0 # landward
		if rng.randf() < 0.2:
			side = -side
		var back := rail_dist(i, side) + rng.randf_range(8.0, 70.0)
		var c: Vector3 = centers[i] + rights[i] * side * back
		c.y = _ground(c)
		if c.y < sea_level + 2.5:
			continue
		var az: Vector3 = rights[i] * side
		var ax: Vector3 = tangents[i]
		var w := rng.randf_range(8.0, 13.0)
		var d := rng.randf_range(8.0, 11.0)
		if not _fits(c, ax, az, w + 4.0, d + 4.0, 3.0):
			continue
		_mark(c, ax, az, w + 4.0, d + 4.0)
		_house(c, ax, az, w, d, rng.randf_range(5.5, 8.5), OCHRE[rng.randi() % OCHRE.size()],
			TERRACOTTA[rng.randi() % TERRACOTTA.size()], 0, -1, rng.randf() < 0.6, rng.randf() < 0.55)
		no_trees.append([c, 11.0])
		if rng.randf() < 0.6:
			var cp: Vector3 = c + ax * (w * 0.5 + 2.5) + az * rng.randf_range(-3.0, 3.0)
			cp.y = _ground(cp) - 0.2
			_mm_add("cypress", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.15)), cp))
		placed += 1


func _med_atlas() -> void:
	var entries := []
	var cols := [[Color(0.12, 0.22, 0.3), Color(0.95, 0.92, 0.82)], [Color(0.45, 0.12, 0.08), Color(0.96, 0.9, 0.74)],
		[Color(0.92, 0.88, 0.76), Color(0.2, 0.25, 0.3)], [Color(0.16, 0.3, 0.2), Color(0.95, 0.9, 0.72)]]
	for k in SHOPS_IT.size():
		var c: Array = cols[k % cols.size()]
		entries.append(["shop%d" % k, Rect2((k % 4) * 512, (k / 4) * 96, 512, 96), c[0], c[1], SHOPS_IT[k], 46, c[1]])
	entries.append(["mercato", Rect2(0, 288, 1024, 128), Color(0.9, 0.84, 0.7), Color(0.32, 0.1, 0.06), "MERCATO DEL PESCE", 80, Color(0.32, 0.1, 0.06)])
	entries.append(["village", Rect2(1024, 288, 1024, 128), Color(0.86, 0.8, 0.68), Color(0.25, 0.14, 0.08), "SANT'ELIA", 88, Color(0.0, 0.0, 0.0, 0.0)])
	for k in GRAFFITI.size():
		var bg: Color = [Color(0.78, 0.74, 0.68), Color(0.7, 0.66, 0.6), Color(0.82, 0.78, 0.7)][k % 3]
		var ink: Color = [Color(0.85, 0.12, 0.1), Color(0.1, 0.2, 0.7), Color(0.05, 0.05, 0.05), Color(0.95, 0.7, 0.1), Color(0.1, 0.5, 0.25)][k % 5]
		entries.append(["graf%d" % k, Rect2((k % 4) * 512, 416 + (k / 4) * 160, 512, 160), bg, ink, GRAFFITI[k], 64, Color(0, 0, 0, 0)])
	entries.append(["clock", Rect2(0, 736, 256, 256), Color(0.92, 0.9, 0.84), Color(0.08, 0.08, 0.08), "XII\n\nIX       III\n\nVI", 34, Color(0.1, 0.1, 0.1)])
	_sign_material(_atlas(entries))
	for k in range(SHOPS_IT.size(), SHOPS.size()): # TrackThemes._shop_sign picks shop0..shop(SHOPS.size()-1)
		uv["shop%d" % k] = uv["shop%d" % (k % SHOPS_IT.size())]


# ---------------------------------------------------------------- market hall

## A long tiled roof on stone piers right over the harbour-front road: open
## at both ends, arcaded along the sides, fish crates and stalls behind the piers.
func _market_hall(i: int) -> void:
	var t: Vector3 = tangents[i]
	var r: Vector3 = rights[i]
	var y := centers[i].y
	var lat := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 0.9
	var length := 44.0
	var eave := 7.2
	var stone := Color(0.84, 0.78, 0.68)
	var c: Vector3 = centers[i]
	# Piers every 5.5 m both sides, a beam on top.
	var k := -length * 0.5
	while k <= length * 0.5 + 0.1:
		for s: float in [-1.0, 1.0]:
			var pc: Vector3 = c + t * k + r * s * lat
			var g := _ground(pc)
			var bot := minf(g, y) - 1.0
			_box("stone", Vector3(pc.x, (bot + y + eave) * 0.5, pc.z), r, Vector3.UP, t, Vector3(1.1, y + eave - bot, 1.1), stone)
		k += 5.5
	for s: float in [-1.0, 1.0]:
		var bc: Vector3 = c + r * s * lat
		_box("stone", Vector3(bc.x, y + eave + 0.45, bc.z), r, Vector3.UP, t, Vector3(1.3, 0.9, length + 1.2), stone * 0.95)
		_mark(bc, t, r, length + 2.0, 6.0)
	# Roof: two tiled slopes, a dark ceiling under them, gable ends with signs.
	var ridge_h := 4.2
	var over := 1.6
	var top: Vector3 = Vector3(c.x, y + eave + 0.9, c.z)
	_gable(top, t, r, length + 1.2, lat * 2.0 + 1.3, ridge_h, over, TERRACOTTA[1], stone, "stone")
	_quad("plain", top - r * (lat + 0.6) - t * length * 0.5, top + r * (lat + 0.6) - t * length * 0.5,
		top + r * (lat + 0.6) + t * length * 0.5, top - r * (lat + 0.6) + t * length * 0.5, Color(0.22, 0.18, 0.15), Vector3.DOWN)
	for s: float in [-1.0, 1.0]:
		var face: Vector3 = top + t * s * (length * 0.5 + 0.62) + Vector3.UP * 1.3
		_sign(face, t * s, 7.5, 0.95, uv.mercato)
		# Hanging lamps over the road.
	for j in 4:
		var lp: Vector3 = top + t * ((j - 1.5) * 10.0) - Vector3.UP * 1.6
		_cyl("metal", lp + Vector3.UP * 0.4, 0.02, 0.02, 1.2, 3, Color(0.1, 0.1, 0.1), false)
		_cyl("lamp", lp, 0.45, 0.1, 0.4, 8, Color(1.0, 0.9, 0.7))
	# Stalls, crates and people just behind the piers on both sides.
	var awn := [[Color(0.16, 0.3, 0.5), Color(0.92, 0.9, 0.85)], [Color(0.75, 0.15, 0.12), Color(0.92, 0.9, 0.85)]]
	for s: float in [-1.0, 1.0]:
		for j in 5:
			var along := -length * 0.4 + j * length * 0.2 + rng.randf_range(-1.0, 1.0)
			var p: Vector3 = c + t * along + r * s * (lat + 2.6)
			p.y = _ground(p)
			if rng.randf() < 0.5:
				_stall(p, t, r * s, awn[j % 2])
			else:
				for q in 4:
					var cp: Vector3 = p + t * rng.randf_range(-1.5, 1.5) + r * s * rng.randf_range(-0.6, 0.6)
					cp.y = _ground(cp) + 0.2 + (0.4 if q == 3 else 0.0)
					_box("plain", cp, t, Vector3.UP, r, Vector3(0.9, 0.4, 0.6), [Color(0.7, 0.55, 0.35), Color(0.2, 0.35, 0.6), Color(0.85, 0.85, 0.82)][q % 3])
			for q in 3:
				var pp: Vector3 = c + t * (along + rng.randf_range(-2.0, 2.0)) + r * s * (lat + rng.randf_range(1.2, 4.0))
				pp.y = _ground(pp)
				_person(Transform3D(Basis.looking_at(-r * s, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.8, 0.8)), pp), PeopleKit.Role.SPECTATOR)
	# Graffiti on the outer walls between the piers' ends (harbour side).
	no_trees.append([c, length * 0.5 + 20.0])
	foreign.append([c, length * 0.5 + 6.0])


## Boat sheds and net stores between the harbour road and the quay, their
## road-facing walls sprayed with fan graffiti; graffiti on the market piers' ends too.
func _harbour_sheds(i0: int) -> void:
	var sea3 := Vector3(_sea.x, 0, _sea.y) if def.has("sea") else Vector3.BACK
	var made := 0
	var g := 0
	for k in range(-70, 71, 2):
		var i := _i(i0 + k)
		if _near_market(i, 13):
			continue
		var side := 1.0 if rights[i].dot(sea3) > 0.0 else -1.0
		var w := rng.randf_range(9.0, 14.0)
		var d := rng.randf_range(7.0, 10.0)
		var az: Vector3 = rights[i] * side
		var ax: Vector3 = tangents[i]
		var front := rail_dist(i, side) + 2.5
		var c: Vector3 = centers[i] + az * (front + d * 0.5)
		c.y = _ground(c)
		if not _fits(c, ax, az, w, d, 1.0):
			continue
		_mark(c, ax, az, w + 2.0, d)
		var street := _ground(c - az * d * 0.5)
		var col: Color = [Color(0.85, 0.8, 0.7), Color(0.78, 0.72, 0.62), Color(0.9, 0.86, 0.76), Color(0.74, 0.6, 0.48)][rng.randi() % 4]
		var h := rng.randf_range(4.0, 5.5)
		var low := minf(street, _ground(c + az * d * 0.5)) - 1.0
		_box("stone", Vector3(c.x, (low + street + h) * 0.5, c.z), ax, Vector3.UP, az, Vector3(w, street + h - low, d), col)
		_gable(Vector3(c.x, street + h, c.z), ax, az, w, d, 2.0, 0.4, TERRACOTTA[rng.randi() % TERRACOTTA.size()], col, "stone")
		# Big timber doors on the gable ends, graffiti across the road face.
		_box("plain", c + ax * (w * 0.5 + 0.03) + Vector3.UP * (street - c.y + 1.7), az, Vector3.UP, ax, Vector3(3.2, 3.4, 0.08), Color(0.2, 0.32, 0.4))
		var gw := minf(w - 1.5, 7.5)
		var gc := c - az * (d * 0.5 + 0.03) + Vector3.UP * (street - c.y + 1.9)
		if ResourceLoader.exists("res://scripts/track/gimmicks/gx_graffiti.gd"):
			# Real photographed street art from the trackside kit (decal on our wall).
			var out: Vector3 = -az
			var xf := Transform3D(Basis(Vector3.UP.cross(-out).normalized(), Vector3.UP, -out), gc)
			load("res://scripts/track/gimmicks/gx_graffiti.gd").spray(parent, xf, Vector2(gw, 2.6), {seed = g})
			if rng.randf() < 0.6:
				var tc := gc - ax * (gw * 0.5 + 0.8) * (1.0 if rng.randf() < 0.5 else -1.0) - Vector3.UP * 0.4
				load("res://scripts/track/gimmicks/gx_graffiti.gd").spray(parent, Transform3D(xf.basis, tc), Vector2(1.4, 0.7), {tag = true, seed = g + 50})
		else:
			_sign(gc, -az, gw, gw * 160.0 / 512.0 * 1.3, uv["graf%d" % (g % GRAFFITI.size())])
		g += 1
		made += 1
	stats.sheds = made


# ---------------------------------------------------------------- village

## The arch: two stone piers past the rails, an elliptical vault over the road
## and a little house built on top of it.
func _arch(i: int) -> void:
	var t: Vector3 = tangents[i]
	var r: Vector3 = rights[i]
	var y := centers[i].y
	var lat := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 1.6
	var spring := 5.2
	var rise := 4.0
	var depth := 7.0
	var stone := Color(0.8, 0.72, 0.6)
	for s: float in [-1.0, 1.0]:
		var pc: Vector3 = centers[i] + r * s * (lat + 1.6)
		var g := _ground(pc)
		var bot := minf(g, y) - 1.5
		_box("stone", Vector3(pc.x, (bot + y + spring + rise + 3.2) * 0.5, pc.z), r, Vector3.UP, t,
			Vector3(3.2, y + spring + rise + 3.2 - bot, depth), stone)
		_mark(pc, t, r, depth + 1.0, 4.0)
	# Vault: segments around a half-ellipse, voussoirs on both faces.
	var segs := 14
	var top_y := y + spring + rise + 3.2
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var p0: Vector3 = Vector3.UP * (y + spring + sin(a0) * rise) + r * cos(a0) * lat
		var p1: Vector3 = Vector3.UP * (y + spring + sin(a1) * rise) + r * cos(a1) * lat
		var base: Vector3 = Vector3(centers[i].x, 0, centers[i].z)
		var q0: Vector3 = base + p0
		var q1: Vector3 = base + p1
		var hub: Vector3 = base + Vector3.UP * (y + spring)
		var outward: Vector3 = ((q0 + q1) * 0.5 - hub).normalized()
		# Intrados (underside), facing in towards the road.
		_quad("stone", q0 - t * depth * 0.5, q1 - t * depth * 0.5, q1 + t * depth * 0.5, q0 + t * depth * 0.5,
			stone * 0.8, -outward)
		# Spandrel walls on both faces, from the vault up to the top.
		for s: float in [-1.0, 1.0]:
			var f: Vector3 = t * s * depth * 0.5
			var u0: Vector3 = Vector3(q0.x, top_y, q0.z)
			var u1: Vector3 = Vector3(q1.x, top_y, q1.z)
			_quad("stone", q0 + f, q1 + f, u1 + f, u0 + f, stone, t * s)
			# Voussoir ring, slightly proud.
			var ring := outward
			_quad("stone", q0 + f * 1.04, q1 + f * 1.04, q1 + f * 1.04 + ring * 0.7, q0 + f * 1.04 + ring * 0.7, stone * 0.88, t * s)
	# The house over the arch, its roof ridge across the road.
	var hc: Vector3 = Vector3(centers[i].x, top_y, centers[i].z)
	var hw := (lat + 3.2) * 2.0
	for f in [[hc - t * depth * 0.5, -t, hw], [hc + t * depth * 0.5, t, hw], [hc + r * hw * 0.5, r, depth], [hc - r * hw * 0.5, -r, depth]]:
		var fw: float = f[2]
		_wall("wall", f[0], f[1], fw, top_y - 0.5, top_y + 3.6, top_y, OCHRE[0], Vector2(fw, 3.6 + 200.0))
	_gable(hc + Vector3.UP * 3.6, r, t, hw, depth, 2.2, 0.45, TERRACOTTA[0], OCHRE[0])
	for s: float in [-1.0, 1.0]:
		_sign(Vector3(centers[i].x, y + spring + rise + 1.6, centers[i].z) + t * s * (depth * 0.5 + 0.05), t * s, 4.2, 0.55, uv.village)
	no_trees.append([centers[i], lat + 12.0])


## Bell tower and church facing the street near the middle of the village.
func _campanile() -> void:
	var span := _i(v1 - v0)
	for tries in 20:
		var i := _i(v0 + int(span * rng.randf_range(0.35, 0.75)))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var az: Vector3 = rights[i] * side
		var ax: Vector3 = tangents[i]
		var front := rail_dist(i, side) + 1.5
		var tc: Vector3 = centers[i] + az * (front + 3.5)
		if not _fits(tc, ax, az, 7.0, 7.0, 0.8):
			continue
		var nc: Vector3 = tc + az * 3.5 + ax * 9.0 + az * 8.0 # nave behind and beside the tower
		var g := _ground(tc)
		_mark(tc, ax, az, 7.0, 7.0)
		var stone := Color(0.86, 0.76, 0.6)
		var th := 27.0
		_box("stone", Vector3(tc.x, g - 2.0 + (th + 2.0) * 0.5, tc.z), ax, Vector3.UP, az, Vector3(6.2, th + 2.0, 6.2), stone)
		# Belfry: open arches (dark recesses) on all four sides, cornices.
		for k in 4:
			var a := k * PI * 0.5
			var dir: Vector3 = ax * cos(a) + az * sin(a)
			var side_ax: Vector3 = dir.cross(Vector3.UP).normalized()
			for b: float in [-1.0, 1.0]:
				_box("glass", Vector3(tc.x, g + th - 3.6, tc.z) + dir * 3.12 + side_ax * b * 1.2, side_ax, Vector3.UP, dir, Vector3(1.4, 3.4, 0.05), Color(0.04, 0.04, 0.05))
			_box("glass", Vector3(tc.x, g + 12.0, tc.z) + dir * 3.12, side_ax, Vector3.UP, dir, Vector3(0.6, 1.6, 0.05), Color(0.05, 0.05, 0.06))
		for yy: float in [th - 6.0, th]:
			_box("stone", Vector3(tc.x, g + yy, tc.z), ax, Vector3.UP, az, Vector3(6.9, 0.45, 6.9), stone * 0.9)
		_hip(Vector3(tc.x, g + th + 0.2, tc.z), ax, az, 6.4, 6.4, 3.2, 0.3, TERRACOTTA[2])
		_cyl("metal", Vector3(tc.x, g + th + 3.4, tc.z), 0.05, 0.05, 2.0, 4, Color(0.3, 0.3, 0.3), false)
		_sign(Vector3(tc.x, g + th - 9.0, tc.z) - az * 3.13, -az, 2.4, 2.4, uv.get("clock", uv.village))
		if _fits(nc, az, ax, 22.0, 11.0, 0.8):
			_mark(nc, az, ax, 22.0, 11.0)
			var ng := _ground(nc)
			_box("stone", Vector3(nc.x, ng - 1.5 + 6.0, nc.z), az, Vector3.UP, ax, Vector3(22.0, 12.0, 11.0), stone * 1.02)
			_gable(Vector3(nc.x, ng + 10.5, nc.z), az, ax, 22.0, 11.0, 3.2, 0.5, TERRACOTTA[0], stone, "stone")
			_door(nc - az * 11.02 + Vector3.UP * (ng - nc.y), -az, 2.4, 4.0)
		no_trees.append([tc, 20.0])
		_debug("campanile at %s" % tc)
		return


## Continuous house fronts on both sides of the village street, right behind
## the rails; a garden wall where nothing fits.
func _village_rows() -> void:
	for side: float in [-1.0, 1.0]:
		var i := v0
		var misses := 0
		var guard := 0
		while _in_village(i) and guard < n:
			guard += 1
			var w := rng.randf_range(6.0, 10.0)
			var dep := rng.randf_range(9.0, 13.0)
			var mid := _i(i + int(w * 0.5 / STEP))
			var front := rail_dist(mid, side) + 1.2
			var az: Vector3 = rights[mid] * side
			var ax: Vector3 = tangents[mid]
			var c: Vector3 = centers[mid] + az * (front + dep * 0.5)
			if _fits(c, ax, az, w, dep, 0.8):
				_mark(c, ax, az, w, dep)
				var shop := rng.randf() < 0.35
				var floors := rng.randi_range(2, 4)
				var h := (3.9 if shop else 3.3) + floors * 3.0 - 2.6
				var street := _ground(c - az * dep * 0.5)
				street = maxf(street, centers[mid].y - 0.3)
				_house(c, ax, az, w, dep, h, OCHRE[rng.randi() % OCHRE.size()], TERRACOTTA[rng.randi() % TERRACOTTA.size()],
					1 if shop else 0, -1, rng.randf() < 0.7, rng.randf() < 0.35, street)
				if shop:
					_shop_sign(c - az * (dep * 0.5), -az, w, street)
				if rng.randf() < 0.4: # on the eave over the street, looking down at it
					_perches.append(Transform3D(Basis.looking_at(-az, Vector3.UP), c - az * (dep * 0.5 + 0.1) + Vector3.UP * (street + h - c.y + 0.05)))
				i += int(ceil(w / STEP))
				misses = 0
			else:
				i += 1
				misses += 1
				if misses == 3 and _off_track(centers[_i(i)] + rights[_i(i)] * side * (front - 0.5), 0.3) \
						and _foreign_clear(centers[_i(i)] + rights[_i(i)] * side * front, 4.0):
					var wc := centers[_i(i)] + rights[_i(i)] * side * (front - 0.3)
					wc.y = _ground(wc) + 0.7
					_hbox("stone", wc, tangents[_i(i)], Vector3(0.6, 2.4, 6.2), Color(0.86, 0.78, 0.64))
					misses = 0
	var k := v0
	while _in_village(k):
		no_trees.append([centers[k], 45.0])
		k = _i(k + 10)
	# Paved street from the kerb to the house fronts (no grass verges in the village).
	for side: float in [-1.0, 1.0]:
		var prev_in: Vector3 = Vector3.INF
		var prev_out: Vector3 = Vector3.ZERO
		var j := _i(v0 - 4)
		while _in_village(j, 4):
			var g := gravel_depth(j, side)
			var inner := half + TrackBuilder.CURB_WIDTH + (g + 0.3 if g > 0.3 else 0.0)
			var a := _on_ground(centers[j] + rights[j] * side * inner, 0.07)
			var b := _on_ground(centers[j] + rights[j] * side * (rail_dist(j, side) + 1.4), 0.07)
			if prev_in != Vector3.INF:
				_quad("pave", prev_in, a, b, prev_out, Color(0.86, 0.8, 0.7), Vector3.UP)
			prev_in = a
			prev_out = b
			j = _i(j + 1)


## Houses stacked up the hill behind the street fronts.
func _village_infill() -> void:
	var placed := 0
	for tries in 1400:
		if placed >= 70:
			break
		var i := _i(v0 - 20 + rng.randi() % maxi(_i(v1 - v0) + 40, 1))
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var back := rail_dist(i, side) + rng.randf_range(14.0, 70.0)
		var c: Vector3 = centers[i] + rights[i] * side * back + tangents[i] * rng.randf_range(-6.0, 6.0)
		c.y = _ground(c)
		var az: Vector3 = rights[i] * side
		var ax: Vector3 = tangents[i]
		if rng.randf() < 0.3:
			var tmp: Vector3 = ax
			ax = az
			az = tmp
		var w := rng.randf_range(7.0, 11.0)
		var d := rng.randf_range(7.0, 10.0)
		if not _fits(c, ax, az, w, d, 3.0):
			continue
		_mark(c, ax, az, w, d)
		_house(c, ax, az, w, d, rng.randf_range(5.5, 10.0), OCHRE[rng.randi() % OCHRE.size()],
			TERRACOTTA[rng.randi() % TERRACOTTA.size()], 0, -1, rng.randf() < 0.6, rng.randf() < 0.4)
		no_trees.append([c, 9.0])
		placed += 1


# ---------------------------------------------------------------- walls and terraces

func _wall_seg(key: String, a: Vector3, b: Vector3, h: float, thick: float, col: Color, sink := 0.4) -> void:
	var mid := (a + b) * 0.5
	var along := b - a
	var len := along.length()
	if len < 0.01:
		return
	var az := along / len
	var ax: Vector3 = Vector3.UP.cross(az).normalized()
	var ay: Vector3 = az.cross(ax).normalized()
	_box(key, mid + ay * (h * 0.5 - sink), ax, ay, az, Vector3(thick, h, len + 0.15), col)


## Low dry-stone walls just behind the rails, both sides, most of the lap.
func _stone_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var prev: Vector3 = Vector3.INF
		for k in range(0, n + 1, 2):
			var i := _i(k)
			if _in_village(i, 3) or _near_market(i, 14):
				prev = Vector3.INF
				continue
			var p := centers[i] + rights[i] * side * (rail_dist(i, side) + 1.1)
			p.y = _ground(p)
			var ok := _off_track(p, 0.4) and not _occ.has(_okey(p)) and _foreign_clear(p, 1.0) and p.y > sea_level + 1.0
			if ok and prev != Vector3.INF and prev.distance_to(p) < 7.0:
				_wall_seg("drystone", prev, p, 1.05, 0.65, Color(0.9, 0.86, 0.8).lerp(Color(0.72, 0.66, 0.58), rng.randf()))
				if k % 60 == 0: # cats sun themselves on the wall, facing the road
					var top: Vector3 = (prev + p) * 0.5 + Vector3.UP * 0.65
					var face: Vector3 = -rights[i] * side
					if _in_village(i, 60) or rng.randf() < 0.3:
						_cats.append(Transform3D(Basis.looking_at(face, Vector3.UP), top))
					else:
						_perches.append(Transform3D(Basis.looking_at(face, Vector3.UP), top))
			prev = p if ok else Vector3.INF


## Retaining walls stepping up the hillsides above the road, olive trees on
## each terrace.
func _terraces() -> void:
	var made := 0
	for side: float in [-1.0, 1.0]:
		for row in 7:
			var back := 9.0 + row * 9.0
			var prev: Vector3 = Vector3.INF
			for k in range(0, n + 1, 2):
				var i := _i(k)
				if _in_village(i, 12) or _near_market(i, 30):
					prev = Vector3.INF
					continue
				var base := rail_dist(i, side) + back
				var p: Vector3 = centers[i] + rights[i] * side * base
				p.y = _ground(p)
				var below: Vector3 = centers[i] + rights[i] * side * (base - 9.0)
				var rise := p.y - _ground(below)
				var ok: bool = rise > 1.3 and _tdist(p, 30.0) >= 26.0 and not _occ.has(_okey(p)) and _foreign_clear(p, 2.0)
				if ok and prev != Vector3.INF and prev.distance_to(p) < 7.0:
					_wall_seg("drystone", prev, p, 1.7, 0.8, Color(0.86, 0.8, 0.7).lerp(Color(0.68, 0.62, 0.54), rng.randf()), 1.0)
					made += 1
					if k % 6 == 0 and rng.randf() < 0.75:
						var op: Vector3 = p + rights[i] * side * rng.randf_range(3.0, 5.5) + tangents[i] * rng.randf_range(-1.5, 1.5)
						op.y = _ground(op) - 0.15
						var s := rng.randf_range(0.75, 1.15)
						_mm_add("olive%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), op))
						no_trees.append([op, 4.0])
				prev = p if ok else Vector3.INF
	stats.terrace_walls = made


# ---------------------------------------------------------------- flora

func _flora_meshes() -> void:
	var umbrella := _tree_mesh(5.4, 3.0, 9.5, [Color(0.09, 0.15, 0.06), Color(0.24, 0.31, 0.12)], 0.32, 0.25, 12)
	var cypress := _tree_mesh(1.0, 11.0, 0.8, [Color(0.05, 0.1, 0.05), Color(0.16, 0.24, 0.1)], 0.18, 0.88, 10)
	var maquis0 := _blob(1.3, 1.5, [Color(0.1, 0.15, 0.07), Color(0.3, 0.36, 0.16)], 0.4, 8)
	var maquis1 := _blob(0.9, 1.1, [Color(0.16, 0.18, 0.09), Color(0.42, 0.42, 0.22)], 0.45, 8)
	_tree_set("umbrella", "stonepine_1", true, 900.0, umbrella)
	_tree_set("cypress", "cypress_1", true, 800.0, cypress)
	_mm_set("maquis0", maquis0, mats.foliage, 300.0, false)
	_mm_set("maquis1", maquis1, mats.foliage, 300.0, false)
	for v in 2:
		var olive := _tree_mesh(2.3 + v * 0.5, 2.8 + v * 0.6, 1.5, [Color(0.22, 0.26, 0.17), Color(0.5, 0.54, 0.4)], 0.5, 0.0, 10)
		_tree_set("olive%d" % v, "olive_%d" % v, false, 450.0, olive, false)


func _flora() -> void:
	# Stone pines: lone silhouettes on the cliff tops and in small groups by the road.
	var placed := 0
	for tries in 2000:
		if placed >= 150:
			break
		var i := rng.randi() % n
		if _in_village(i, 5):
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := centers[i] + rights[i] * side * (rail_dist(i, side) + rng.randf_range(4.0, 90.0)) + tangents[i] * rng.randf_range(-8.0, 8.0)
		if not _ok_plant(p, 10.0, 7.0):
			continue
		p.y = _ground(p) - 0.3
		var s := rng.randf_range(0.8, 1.2)
		_mm_add("umbrella", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), p))
		no_trees.append([p, 7.0])
		placed += 1
	# Cypress rows on the village approaches and the cemetery by the church.
	for anchor: int in [v0 - 40, v1 + 30]:
		var i0 := _i(anchor)
		for side: float in [-1.0, 1.0]:
			for k in 9:
				var i := _i(i0 + k * 4)
				var p := centers[i] + rights[i] * side * (rail_dist(i, side) + 2.6)
				if not _ok_plant(p, 2.5, 1.5):
					continue
				p.y = _ground(p) - 0.3
				var s := rng.randf_range(0.85, 1.1)
				_mm_add("cypress", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.95, 1.25), s)), p))
	# Maquis: dense scrub over the slopes, thinning out with distance.
	placed = 0
	for tries in 9000:
		if placed >= 1400:
			break
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var back := rail_dist(i, side) + 2.5 + pow(rng.randf(), 1.6) * 160.0
		var p: Vector3 = centers[i] + rights[i] * side * back + tangents[i] * rng.randf_range(-3.0, 3.0)
		if not _ok_plant(p, 2.0, 1.2):
			continue
		p.y = _ground(p) - 0.15
		var s := rng.randf_range(0.7, 1.5)
		_mm_add("maquis%d" % (rng.randi() % 2), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), p))
		placed += 1
	stats.maquis = placed


## Off the road (behind the rails), above the sea, not on buildings or in clear zones.
func _ok_plant(p: Vector3, margin: float, r: float) -> bool:
	if not _off_track(p, margin) or _occ.has(_okey(p)) or not _foreign_clear(p, r):
		return false
	p.y = _ground(p)
	if terrain and p.y < sea_level + 1.2:
		return false
	return not Vegetation.in_zone(_zones, p, 20.0)
