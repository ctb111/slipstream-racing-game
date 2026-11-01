extends RefCounted
## Landscape filler: the near and middle distance (20-300 m from the road) of
## every circuit, so no lap shows an empty plain. Field boundaries (hedgerows,
## dry-stone walls, post-and-rail / post-and-wire fences with gates), tree
## lines and solitary field trees (baked Sapling trees, near/far LOD swapped
## like the forest: never popping), farm buildings (timber / stone / brick
## barns, open Dutch hay barns, sheds) with farm tracks, round bales and
## tractors, forestry log piles and hunters' high seats, telegraph lines,
## distant spectator banks, cars parked along the access tracks, and race-event
## infrastructure (scaffold TV towers, marshal posts, floodlight masts).
## Themed per track (PROFILES). Called once per track by gimmicks.gd after the
## dress file. Everything static is merged per material per 250 m cell; small
## details fade out by 600 m (sub-pixel there), big shapes are always drawn.
## --fill_off (or FILL_OFF=1 headless) skips it (perf A/B).

const CELL := 250.0
const DETAIL_VIS := 600.0

## Per track: bounds (weighted boundary kinds), trees (Sapling model names for
## tree lines and field trees, conifer flag), barn styles, extras.
const PROFILES := {
	kiefernring = {copses = 0.6, bounds = {rail = 3, wire = 2, hedge = 1}, trees = ["pine_2", "pine_3", "birch_1", "oak_2"], conifer = [true, true, false, false],
		barns = ["timber", "timber", "dutch"], forest = true, crowds = 3, infra = ["tv", "tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.35, fields = 0.7},
	hochwald = {copses = 0.4, bounds = {rail = 2, hedge = 2, wire = 1}, trees = ["spruce_2", "spruce_3", "beech_2", "oak_2"], conifer = [true, true, false, false],
		barns = ["timber", "dutch", "timber"], forest = true, crowds = 3, infra = ["tv", "tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.4, fields = 0.7},
	herbstwald = {copses = 0.5, bounds = {hedge = 3, rail = 2, wall = 1}, trees = ["oak_2", "maple_2", "beech_2", "birch_1"], conifer = [false, false, false, false],
		barns = ["timber", "stone", "dutch"], forest = true, crowds = 3, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.5, fields = 0.75},
	brackenmoor = {copses = 1.4, bounds = {wall = 5, wire = 1}, trees = ["birch_1", "oak_1", "spruce_2"], conifer = [false, false, true],
		barns = ["stone", "stone", "dutch"], forest = false, crowds = 2, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.3, fields = 0.9},
	schneekopf = {copses = 0.7, bounds = {rail = 4, wire = 1}, trees = ["spruce_2", "spruce_3", "spruce_1"], conifer = [true, true, true],
		barns = ["alpine", "alpine", "alpine"], forest = true, crowds = 2, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.0, fields = 0.6},
	kuestenstrasse = {copses = 0.8, bounds = {wall = 2, hedge = 2, wire = 2}, trees = ["pine_2", "oak_1", "birch_1"], conifer = [true, false, false],
		barns = ["stone", "brick", "dutch"], forest = false, crowds = 2, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.35, fields = 0.85},
	capo_rosso = {copses = 0.7, bounds = {wall = 3, wire = 1}, trees = ["olive_1", "stonepine_1", "cypress_1", "olive_0"], conifer = [false, false, false, false],
		barns = ["plaster", "stone", "plaster"], forest = false, crowds = 2, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.15, fields = 0.85},
	altstadt = {copses = 1.2, bounds = {hedge = 3, wall = 1, wire = 1}, trees = ["oak_2", "beech_2", "birch_1", "maple_1"], conifer = [false, false, false, false],
		barns = ["brick", "plaster", "timber"], forest = false, crowds = 2, infra = ["tv", "marshal", "marshal"], poles = 1, bales = 0.2, fields = 0.6},
	valtellina = {copses = 0.5, bounds = {wire = 4, hedge = 1}, trees = ["poplar_1", "poplar_0", "oak_2", "cypress_1"], conifer = [false, false, false, false],
		barns = ["plaster", "brick", "dutch"], forest = false, crowds = 3, infra = ["tv", "tv", "tv", "marshal", "marshal", "marshal", "marshal", "light", "light", "light", "light"], poles = 1, bales = 0.3, fields = 0.5},
	valle_club = {copses = 1.4, bounds = {wall = 2, hedge = 2, wire = 1}, trees = ["cypress_1", "poplar_1", "olive_1", "oak_2"], conifer = [false, false, false, false],
		barns = ["plaster", "stone", "plaster"], forest = false, crowds = 2, infra = ["tv", "marshal", "marshal", "marshal"], poles = 1, bales = 0.25, fields = 0.8},
}


static func fill(c: Node3D) -> void:
	if OS.has_environment("FILL_OFF") or OS.get_cmdline_user_args().has("--fill_off") or Gx.curve(c) == null:
		return
	var def = c.get("def")
	var id: String = str(def.get("id", "")) if def is Dictionary else ""
	if not PROFILES.has(id) or (def is Dictionary and def.get("street", false)):
		return # city street circuits (hafenstadt) and tracks without a profile: no countryside
	var t0 := Time.get_ticks_msec()
	var w := Filler.new(c, PROFILES[id], id)
	w.run()
	if w._holder != null:
		var nodes := 0
		var tris := 0
		for n in w._holder.find_children("*", "GeometryInstance3D", true, false):
			nodes += 1
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				tris += (n as MeshInstance3D).mesh.get_faces().size() / 3 if OS.has_environment("FILL_TRIS") else 0
		w.counts["nodes"] = nodes
	print("fill_landscape %s: %d ms, %s" % [id, Time.get_ticks_msec() - t0, w.counts])


class Filler:
	var c: Node3D
	var p: Dictionary
	var id: String
	var rng: RandomNumberGenerator
	var L: float
	var dens := FastNoiseLite.new()
	var main := {} ## cell -> GxGeo (always drawn)
	var detail := {} ## cell -> GxGeo (fades by DETAIL_VIS)
	var hedges := {} ## cell -> [Array[Transform3D] per bush variant]
	var trees := {} ## model -> cell(100 m) -> Array[Transform3D]
	var bush_meshes: Array[ArrayMesh] = []
	var snow := 0.0
	var wet := 0.0
	var night := false
	var counts := {}
	var taken: Array = [] ## [Vector3, radius] of my own big pieces
	var _mats := {}

	func _init(p_c: Node3D, p_p: Dictionary, p_id: String) -> void:
		c = p_c
		p = p_p
		id = p_id
		rng = Gx.rng(c, "fill_landscape")
		L = Gx.length(c)
		dens.seed = 7 # the forest's density field (world_builder.build_forest)
		dens.frequency = 0.006
		var wx = c.get("weather")
		if wx is Weather:
			snow = float(wx.preset.get("snow", 0.0))
			wet = float(wx.preset.get("wet", 0.0))
		night = Car.night

	var views := {} ## kind -> target (debug shots: --dress_shots with --fill_views)

	func _n(k: String, at := Vector3.INF) -> void:
		counts[k] = int(counts.get(k, 0)) + 1
		if at != Vector3.INF and not views.has(k):
			views[k] = at

	## Debug: driver-height views from the road towards one of each kind.
	func _shots() -> void:
		if not OS.get_cmdline_user_args().has("--fill_views"):
			return
		var ds = load("res://scripts/track/gimmicks/dress_shots.gd")
		var node: Node = null
		for n in c.get_children():
			if n.get_script() == ds:
				node = n
		if node == null:
			ds.attach(c)
			for n in c.get_children():
				if n.get_script() == ds:
					node = n
		if node == null:
			return
		node.views.clear()
		for k: String in views:
			var tgt: Vector3 = views[k]
			var cv := Gx.curve(c)
			var q := cv.get_closest_point(tgt)
			var back := (q - tgt)
			back.y = 0.0
			var eye := q + back.normalized() * 2.0
			eye.y = Gx.ground(c, eye) + 1.3
			var off := cv.get_closest_offset(q)
			var ahead := cv.sample_baked(fposmod(off + 25.0, cv.get_baked_length()))
			var look := tgt.lerp(ahead, 0.25) + Vector3(0, 2.0, 0)
			if OS.get_cmdline_user_args().has("--fill_close"):
				eye = tgt + back.normalized() * 16.0 + back.normalized().cross(Vector3.UP) * 5.0
				eye.y = Gx.ground(c, eye) + 1.8
				look = tgt + Vector3(0, 1.5, 0)
			node.views.append([eye, look])
			print("fill view ", node.views.size() - 1, ": ", k)

	# ------------------------------------------------------------ queries

	## 0 = open clearing .. 1 = dense forest (where build_forest puts its trees).
	func forest_at(q: Vector3) -> float:
		var d := dens.get_noise_2d(q.x, q.z) * 0.5 + 0.5
		return smoothstep(0.35, 0.65, d)

	func ok_at(q: Vector3, road_margin: float, r := 0.0) -> bool:
		if not Gx.clear_of_road(c, q, road_margin + r):
			return false
		var nt: Array = c.get_meta("no_trees", [])
		for res: Array in nt:
			var o: Vector3 = res[0]
			if Vector2(q.x - o.x, q.z - o.z).length() < float(res[1]) + r:
				return false
		for res: Array in taken:
			var o: Vector3 = res[0]
			if Vector2(q.x - o.x, q.z - o.z).length() < float(res[1]) + r:
				return false
		return true

	func gnd(q: Vector3) -> Vector3:
		return Vector3(q.x, Gx.ground(c, q), q.z)

	func _cell(q: Vector3) -> Vector2i:
		return Vector2i(floori(q.x / CELL), floori(q.z / CELL))

	func G(q: Vector3) -> GxGeo:
		var k := _cell(q)
		if not main.has(k):
			main[k] = GxGeo.new()
		return main[k]

	var structs := {} ## cell -> GxGeo (buildings / infra: shadows, always drawn)

	## The cell batch for a building or mast, its local frame set to `xf`
	## (reset with done()).
	func B(xf: Transform3D) -> GxGeo:
		var k := _cell(xf.origin)
		if not structs.has(k):
			structs[k] = GxGeo.new()
		var g: GxGeo = structs[k]
		g.xf = xf
		return g

	func done(g: GxGeo) -> void:
		g.xf = Transform3D.IDENTITY
		g.col = Color.WHITE

	func D(q: Vector3) -> GxGeo:
		var k := _cell(q)
		if not detail.has(k):
			detail[k] = GxGeo.new()
		return detail[k]

	func take(q: Vector3, r: float) -> void:
		taken.append([q, r])
		Gx.reserve(c, q, r)

	func pick_bound() -> String:
		var b: Dictionary = p.bounds
		var tot := 0.0
		for k in b:
			tot += float(b[k])
		var x := rng.randf() * tot
		for k in b:
			x -= float(b[k])
			if x <= 0.0:
				return k
		return "wire"

	# ------------------------------------------------------------ run

	func run() -> void:
		_fields()
		_copses()
		_buildings()
		if p.forest:
			_forestry()
		_poles()
		_infra()
		_crowds()
		_batch2()
		_flush()
		_shots()

	# ------------------------------------------------------------ fields

	## Parcels along both sides: a front boundary parallel to the road, a side
	## boundary running away from it, sometimes a back one; tree lines on some
	## boundaries, solitary trees and bales in the fields.
	func _fields() -> void:
		var a := rng.randf_range(0.0, 60.0)
		while a < L - 40.0:
			var plen := rng.randf_range(90.0, 170.0)
			for side: float in [Gx.LEFT, Gx.RIGHT]:
				if rng.randf() < float(p.fields):
					_parcel(a, minf(a + plen, L - 10.0), side)
			a += plen

	func _parcel(a0: float, a1: float, side: float) -> void:
		var n0 := rng.randf_range(20.0, 34.0)
		var depth := rng.randf_range(110.0, 230.0)
		var kind := pick_bound()
		var mid := Gx.frame(c, (a0 + a1) * 0.5, side, n0 + depth * 0.5).origin
		if forest_at(mid) > 0.8 and rng.randf() < 0.7:
			return # deep in the forest: nothing would show
		if rng.randf() < 0.8 * GxCorridor.boost_at(c, Gx.frame(c, (a0 + a1) * 0.5, side, 14.0).origin):
			return # behind the corridor tree wall (gx_corridor.gd): nothing would show
		# front boundary (gate gap somewhere)
		var gate := rng.randf_range(a0 + 15.0, a1 - 15.0)
		var pts: Array = []
		var s := a0
		while s <= a1:
			if absf(s - gate) < 2.5:
				_line(kind, pts)
				pts = []
				if kind != "hedge":
					_gate(Gx.frame(c, gate, side, n0), kind)
			else:
				pts.append(Gx.frame(c, s, side, n0).origin)
			s += 3.0
		_line(kind, pts)
		# side boundary away from the road
		var xf := Gx.frame(c, a0, side, n0)
		pts = []
		var z := 0.0
		while z <= depth:
			pts.append(xf * Vector3(0, 0, z))
			z += 3.0
		var tl := rng.randf() < 0.45
		_line("hedge" if tl and kind == "hedge" else kind, pts)
		if tl:
			_tree_line(pts, 7.0, 0.85)
		# back boundary (only on rather straight bits: on bends it would cut across)
		if rng.randf() < 0.5:
			pts = []
			s = a0
			while s <= a1:
				pts.append(Gx.frame(c, s, side, n0 + depth).origin)
				s += 3.0
			_line(kind, pts)
			if rng.randf() < 0.5:
				_tree_line(pts, 8.0, 0.8)
		# a solitary field tree or two
		for k in rng.randi_range(0, 2):
			var q := Gx.frame(c, rng.randf_range(a0 + 10.0, a1 - 10.0), side, n0 + rng.randf_range(25.0, depth - 15.0)).origin
			_tree(q, 1.15)
		# bales
		if rng.randf() < float(p.bales):
			_bales(Gx.frame(c, rng.randf_range(a0 + 20.0, a1 - 20.0), side, n0 + rng.randf_range(15.0, depth * 0.6)))

	## Copses and small stands out in the open, 50-260 m from the road, where
	## the forest leaves a clearing: they close the view without walling it.
	func _copses() -> void:
		var want := int(L / 110.0 * float(p.get("copses", 1.0)))
		var made := 0
		for tries in want * 6:
			if made >= want:
				break
			var a := rng.randf() * L
			var side := Gx.LEFT if rng.randf() < 0.5 else Gx.RIGHT
			var lat := lerpf(50.0, 260.0, pow(rng.randf(), 1.4))
			var q := Gx.frame(c, a, side, lat).origin
			if forest_at(q) > 0.35 or not ok_at(q, 30.0, 10.0):
				continue
			if rng.randf() < 0.6 * GxCorridor.boost_at(c, Gx.frame(c, a, side, 14.0).origin):
				continue # hidden behind the corridor tree wall
			var n := rng.randi_range(5, 14)
			var r := sqrt(float(n)) * 4.5
			for k in n:
				var ang := rng.randf() * TAU
				var d := sqrt(rng.randf()) * r
				_tree(q + Vector3(cos(ang) * d, 0, sin(ang) * d), rng.randf_range(0.8, 1.2))
			if bush_meshes.size() > 0 or true:
				_scrub(q, r + 3.0)
			_n("copse", q)
			made += 1
		counts["copses"] = made

	## Undergrowth round a copse edge (bushes), so it doesn't stand on bare lawn.
	func _scrub(q: Vector3, r: float) -> void:
		if bush_meshes.is_empty():
			var rb := Gx.rng(c, "fill_bush")
			for v in 3:
				bush_meshes.append(Vegetation.bush(rb, 1.0))
		for k in int(r * 1.2):
			var ang := rng.randf() * TAU
			var o := q + Vector3(cos(ang), 0, sin(ang)) * r * rng.randf_range(0.6, 1.05)
			if not ok_at(o, 14.0):
				continue
			o = gnd(o) - Vector3(0, 0.2, 0)
			var s := rng.randf_range(0.9, 1.8)
			var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), o)
			var kc := _cell(o)
			if not hedges.has(kc):
				hedges[kc] = [[], [], []]
			hedges[kc][absi(kc.x * 7 + kc.y * 13) % 3].append(xf)

	## Draw a boundary through world points: consecutive valid points form runs.
	func _line(kind: String, pts: Array) -> void:
		var run: Array = []
		for q: Vector3 in pts:
			if ok_at(q, 12.0) and forest_at(q) < 0.92:
				run.append(gnd(q))
			else:
				_run(kind, run)
				run = []
		_run(kind, run)

	func _run(kind: String, run: Array) -> void:
		if run.size() < 3:
			return
		_n(kind, run[run.size() / 2])
		match kind:
			"wall":
				for i in run.size() - 1:
					_wall_seg(run[i], run[i + 1])
			"hedge":
				_hedge(run)
			"rail":
				_fence(run, true)
			_:
				_fence(run, false)

	func _wall_seg(a: Vector3, b: Vector3) -> void:
		var g := G(a)
		var dir := b - a
		var l := dir.length()
		if l < 0.1:
			return
		var x := dir / l
		var zz := x.cross(Vector3.UP).normalized()
		var m := Transform3D(Basis(x, zz.cross(x).normalized(), zz), a)
		var h := rng.randf_range(0.95, 1.2) * (0.8 if id == "capo_rosso" else 1.0)
		var prof := PackedVector2Array([Vector2(-0.36, -0.35), Vector2(0.36, -0.35), Vector2(0.3, h * 0.82),
			Vector2(0.2, h), Vector2(-0.2, h), Vector2(-0.3, h * 0.82)])
		var v := rng.randf_range(0.82, 1.0)
		g.col = Color(v, v * 0.98, v * 0.94)
		g.extrude_xf("drystone", prof, -0.05, l + 0.05, m, 0.0, false)
		g.col = Color.WHITE
		if not Gx.clear_of_road(c, a, 60.0):
			g.collide(m * Vector3(l * 0.5, h * 0.5, 0), Vector3(l, h, 0.6), m.basis)

	func _fence(run: Array, rails: bool) -> void:
		var pitch := 2.6 if rails else 3.2
		var acc := 0.0
		var posts: Array = [run[0]]
		for i in range(1, run.size()):
			acc += (run[i] as Vector3).distance_to(run[i - 1])
			if acc >= pitch:
				posts.append(run[i])
				acc = 0.0
		var wood := Color(0.62, 0.55, 0.47) if snow < 0.3 else Color(0.5, 0.44, 0.38)
		for i in posts.size():
			var q: Vector3 = posts[i]
			var g := D(q)
			g.col = wood * rng.randf_range(0.8, 1.05)
			var lean := Basis(Vector3(1, 0, 0), rng.randf_range(-0.03, 0.03)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.03, 0.03))
			if rails:
				g.box("wood", q + Vector3(0, 0.55, 0), Vector3(0.13, 1.4, 0.13), 0.02, lean)
			else:
				g.box("wood", q + Vector3(0, 0.5, 0), Vector3(0.09, 1.25, 0.09), 0.015, lean)
			if i == 0:
				continue
			var a: Vector3 = posts[i - 1]
			if a.distance_to(q) > pitch * 2.5:
				continue
			if rails:
				for y: float in [0.45, 0.95]:
					g.beam("wood", a + Vector3(0, y, 0), q + Vector3(0, y, 0), 0.06, 0.11)
			else:
				g.col = Color(0.35, 0.35, 0.33)
				for y: float in [0.35, 0.7, 1.0]:
					g.bar("steel", a + Vector3(0, y, 0), q + Vector3(0, y - 0.03, 0), 0.008, 3)

	func _gate(xf: Transform3D, kind: String) -> void:
		var o := gnd(xf.origin)
		if not ok_at(o, 10.0):
			return
		var g := D(o)
		var x := xf.basis.x.normalized()
		g.col = Color(0.55, 0.5, 0.42) if kind == "rail" or kind == "wall" else Color(0.75, 0.76, 0.75)
		var mat := "wood" if kind == "rail" or kind == "wall" else "steel"
		for s: float in [-2.4, 2.4]:
			g.box(mat, o + x * s + Vector3(0, 0.7, 0), Vector3(0.18, 1.6, 0.18), 0.02)
		# five-bar gate, swung half open
		var hinge := o - x * 2.3
		var open := Basis(Vector3.UP, rng.randf_range(0.2, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0))
		var gx := open * x
		for k in 5:
			var y := 0.25 + k * 0.24
			g.beam(mat, hinge + Vector3(0, y, 0), hinge + gx * 4.4 + Vector3(0, y, 0), 0.05, 0.07)
		g.beam(mat, hinge + Vector3(0, 0.25, 0), hinge + gx * 4.4 + Vector3(0, 1.21, 0), 0.04, 0.06)
		g.col = Color.WHITE
		# a farm track through the gate, out into the field
		_track(xf, 0.0, rng.randf_range(30.0, 70.0), 3.0)

	# ------------------------------------------------------------ vegetation

	func _hedge(run: Array) -> void:
		if bush_meshes.is_empty():
			var r := Gx.rng(c, "fill_bush")
			for v in 3:
				bush_meshes.append(Vegetation.bush(r, 1.0))
		var acc := 0.0
		for i in range(1, run.size()):
			var a: Vector3 = run[i - 1]
			var b: Vector3 = run[i]
			var seg := a.distance_to(b)
			var t := 0.0
			while t < seg:
				var q := a.lerp(b, t / seg)
				var dir := (b - a).normalized()
				var s := rng.randf_range(1.5, 2.0)
				var yaw := atan2(dir.x, dir.z) + rng.randf_range(-0.4, 0.4)
				var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s * 1.1, s * rng.randf_range(0.7, 0.95), s * 1.35)),
					q + Vector3(rng.randf_range(-0.3, 0.3), -0.25, rng.randf_range(-0.3, 0.3)))
				var k := _cell(q)
				if not hedges.has(k):
					hedges[k] = [[], [], []]
				hedges[k][absi(k.x * 7 + k.y * 13) % 3].append(xf)
				t += rng.randf_range(2.1, 2.7)
				acc += 1.0
			# hedgerow trees
			if rng.randf() < 0.04:
				_tree(b, 1.0)

	func _tree_line(pts: Array, pitch: float, chance: float) -> void:
		var acc := 0.0
		for i in range(1, pts.size()):
			acc += (pts[i] as Vector3).distance_to(pts[i - 1])
			if acc >= pitch:
				acc = rng.randf_range(-2.0, 1.0)
				if rng.randf() < chance:
					_tree(pts[i] + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), 1.0)

	func _tree(q: Vector3, scale: float) -> void:
		if not ok_at(q, 14.0, 2.0) or forest_at(q) > 0.75:
			return
		var list: Array = p.trees
		var o := gnd(q) - Vector3(0, 0.2, 0)
		var kc := Vector2i(floori(o.x / 100.0), floori(o.z / 100.0))
		var model: String = list[absi(kc.x * 31 + kc.y * 17 + 3) % list.size()] # one species per 100 m cell: 3 draws, not 12
		var s := rng.randf_range(0.85, 1.15) * scale
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.93, 1.08), s)), o)
		if not trees.has(model):
			trees[model] = {}
		var k := Vector2i(floori(o.x / 100.0), floori(o.z / 100.0))
		if not trees[model].has(k):
			trees[model][k] = []
		trees[model][k].append(xf)
		_n("tree")

	# ------------------------------------------------------------ props in the fields

	func _bales(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		if not ok_at(o, 14.0, 6.0) or forest_at(o) > 0.6:
			return
		var g := D(o)
		var x := xf.basis.x.normalized()
		var z := xf.basis.z.normalized()
		var wrap := id in ["kuestenstrasse", "brackenmoor", "altstadt"] and rng.randf() < 0.5
		if rng.randf() < 0.45:
			# a stack: 4 + 3 + 2 round bales
			var row := 0
			for n: int in [5, 4]:
				for k in n:
					var cpos := o + x * ((k - (n - 1) * 0.5) * 1.55) + Vector3(0, 0.72 + row * 1.3, 0)
					g.col = Color(1.0, 0.98, 0.92) * rng.randf_range(0.9, 1.0)
					GxProps.round_bale(g, cpos, z, 0.75, 1.2)
				row += 1
		else:
			for k in rng.randi_range(5, 11):
				var q := gnd(o + x * rng.randf_range(-35.0, 35.0) + z * rng.randf_range(-10.0, 25.0))
				if not ok_at(q, 12.0):
					continue
				var ax := Basis(Vector3.UP, rng.randf() * TAU) * x
				if wrap:
					g.col = [Color(0.92, 0.93, 0.9), Color(0.12, 0.13, 0.12), Color(0.35, 0.45, 0.3)][rng.randi() % 3]
					GxProps.round_bale(g, q + Vector3(0, 0.7, 0), ax, 0.74, 1.2) # (wrapped: tinted)
				else:
					g.col = Color(1.0, 0.98, 0.92) * rng.randf_range(0.88, 1.0)
					GxProps.round_bale(g, q + Vector3(0, 0.7, 0), ax, 0.75, 1.2)
		g.col = Color.WHITE
		take(o, 8.0)
		_n("bales", o)

	## Two dirt wheel ruts, from the frame origin out to z1 (local z).
	func _track(xf: Transform3D, z0: float, z1: float, width: float, ruts := 2) -> void:
		var x := xf.basis.x.normalized()
		var z := xf.basis.z.normalized()
		var bend := rng.randf_range(-0.004, 0.004)
		var prev: Array = [null, null]
		var t := z0
		var g := D(xf.origin)
		g.col = Color.WHITE
		while t <= z1:
			var cen := xf.origin + z * t + x * (bend * t * t)
			var ok := Gx.clear_of_road(c, cen, 3.0)
			for r in ruts:
				var q := cen + x * (r * 2 - 1) * width * 0.32 if ruts == 2 else cen
				var hw := 0.38 if ruts == 2 else width * 0.5
				var a := gnd(q - x * hw) + Vector3(0, 0.07, 0)
				var b := gnd(q + x * hw) + Vector3(0, 0.07, 0)
				if ok and prev[r] != null:
					var pa: Vector3 = prev[r][0]
					var pb: Vector3 = prev[r][1]
					g.quad_n("soil", pa, pb, b, a, Vector3.UP)
				prev[r] = [a, b] if ok else null
			t += 3.0

	# ------------------------------------------------------------ buildings

	func _buildings() -> void:
		var styles: Array = p.barns
		var want := clampi(int(L / 650.0) + 1, 2, 5)
		var cand := []
		var a := rng.randf_range(0.0, 200.0)
		while a < L:
			cand.append(a)
			a += 95.0
		cand.shuffle()
		var placed := 0
		var last: Array = []
		for along: float in cand:
			if placed >= want:
				break
			var near := false
			for l: float in last:
				if absf(l - along) < 250.0:
					near = true
			if near:
				continue
			var style: String = styles[placed % styles.size()]
			var w := 22.0 if style != "dutch" else 18.0
			var xf = GxSpot.find(c, [along], [30.0, 45.0, 60.0], w * 0.5 + 8.0, -2.0, 32.0, 3.0)
			if xf == null:
				continue
			var m: Transform3D = xf
			if forest_at(m * Vector3(0, 0, 14)) > 0.7 and not p.forest:
				continue
			_farmstead(m, style)
			last.append(along)
			placed += 1

	## A barn (+ a shed or Dutch barn), a yard, a tractor, a farm track to the road.
	func _farmstead(xf: Transform3D, style: String) -> void:
		var o := xf.origin
		take(xf * Vector3(0, 0, 14), 24.0)
		var g := B(xf)
		var rot := Basis(Vector3.UP, rng.randf_range(-0.15, 0.15))
		if style == "dutch":
			_dutch(g, Transform3D(rot, Vector3(0, 0, 14)))
			_shed(g, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-14, 0, 22)), "timber")
		else:
			_barn(g, Transform3D(rot, Vector3(0, 0, 16)), style, rng.randf_range(16.0, 22.0), rng.randf_range(9.0, 12.0))
			if rng.randf() < 0.6:
				_dutch(g, Transform3D(Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.1, 0.1)), Vector3(17, 0, 18)))
		# yard: a few bales (no tractor: the procedural one reads as a toy close up)
		for k in rng.randi_range(2, 5):
			var bp := Vector3(rng.randf_range(10.0, 14.0), 0, rng.randf_range(4.0, 9.0))
			bp.y = Gx.ground(c, xf * bp) - o.y + 0.72
			g.col = Color(0.95, 0.9, 0.8) * rng.randf_range(0.85, 1.0)
			GxProps.round_bale(g, bp, Vector3(1, 0, rng.randf_range(-0.5, 0.5)), 0.75, 1.2)
		g.col = Color.WHITE
		done(g)
		_track(xf, -2.0, 6.0, 3.0)
		_n("farm_" + style, xf * Vector3(0, 0, 16))

	## Walls + gables + roof of a pitched barn. Frame m: front (big doors) at -z.
	func _barn(g: GxGeo, m: Transform3D, style: String, l: float, d: float) -> void:
		var hw := l * 0.5
		var hd := d * 0.5
		var eave := 5.2 if style != "alpine" else 4.4
		var pitch := 0.62 if style in ["timber", "alpine"] else 0.5
		if style == "plaster":
			pitch = 0.35
		var ridge := eave + hd * pitch
		var wall: String = {timber = "painted_wood", stone = "stone", brick = "brick", plaster = "plaster", alpine = "wood"}[style]
		var roof: String = {timber = "corrugated", stone = "slate", brick = "roof_tiles", plaster = "roof_tiles", alpine = "wood"}[style]
		var wcol := Color.WHITE
		if style == "timber":
			wcol = [Color(0.42, 0.12, 0.08), Color(0.2, 0.18, 0.16), Color(0.55, 0.5, 0.42)][rng.randi() % 3]
		elif style == "plaster":
			wcol = [Color(0.92, 0.82, 0.62), Color(0.88, 0.7, 0.55), Color(0.9, 0.88, 0.82)][rng.randi() % 3]
		var rcol := Color(0.62, 0.62, 0.6) if roof == "corrugated" else Color.WHITE
		var B := m.basis
		var P := func(v: Vector3) -> Vector3: return m * v
		# sink the footprint into the slope: plinth down to the lowest corner
		g.col = Color(0.75, 0.74, 0.7)
		g.box("concrete", P.call(Vector3(0, -0.5, 0)), Vector3(l + 0.3, 1.6, d + 0.3), 0.04, B)
		g.col = wcol
		g.box(wall, P.call(Vector3(0, eave * 0.5 + 0.3, -hd + 0.15)), Vector3(l, eave - 0.6, 0.3), 0.03, B)
		g.box(wall, P.call(Vector3(0, eave * 0.5 + 0.3, hd - 0.15)), Vector3(l, eave - 0.6, 0.3), 0.03, B)
		g.box(wall, P.call(Vector3(-hw + 0.15, eave * 0.5 + 0.3, 0)), Vector3(0.3, eave - 0.6, d - 0.6), 0.03, B)
		g.box(wall, P.call(Vector3(hw - 0.15, eave * 0.5 + 0.3, 0)), Vector3(0.3, eave - 0.6, d - 0.6), 0.03, B)
		for s: float in [-1.0, 1.0]: # gables
			var x := s * (hw - 0.15)
			var n := Vector3(s, 0, 0)
			var a: Vector3 = P.call(Vector3(x, eave, -hd))
			var b: Vector3 = P.call(Vector3(x, eave, hd))
			var top: Vector3 = P.call(Vector3(x, ridge, 0))
			g.tri_f(wall, a, b, top, B * n)
			if style == "stone": # gable coping
				pass
		# roof: two slabs with overhangs, ridge cap
		g.col = rcol
		var slope := atan(pitch)
		var rl := (hd + 0.6) / cos(slope)
		for s: float in [-1.0, 1.0]:
			var rb := B * Basis(Vector3(1, 0, 0), s * slope)
			var cen: Vector3 = P.call(Vector3(0, ridge - (hd * 0.5 + 0.3) * pitch + 0.12, s * (hd * 0.5 + 0.3)))
			g.box(roof, cen, Vector3(l + 1.0, 0.16, rl), 0.02, rb)
		if snow > 0.3:
			g.col = Color(0.95, 0.96, 1.0)
			for s: float in [-1.0, 1.0]:
				var rb := B * Basis(Vector3(1, 0, 0), s * slope)
				var cen: Vector3 = P.call(Vector3(0, ridge - (hd * 0.5 + 0.3) * pitch + 0.32, s * (hd * 0.5 + 0.3)))
				g.box("plaster", cen, Vector3(l + 0.9, 0.25, rl - 0.1), 0.1, rb)
		g.col = Color(0.4, 0.4, 0.4)
		g.box("steel", P.call(Vector3(0, ridge + 0.1, 0)), Vector3(l + 1.0, 0.18, 0.4), 0.05, B)
		# big doors on the front, a small door + windows
		g.col = Color(0.33, 0.24, 0.17) if style != "timber" else wcol * 0.7
		var door := minf(l * 0.3, 5.0)
		g.box("painted_wood", P.call(Vector3(-l * 0.18, 2.1, -hd - 0.05)), Vector3(door, 3.8, 0.12), 0.02, B)
		g.col = Color(0.15, 0.13, 0.12)
		g.box("steel", P.call(Vector3(-l * 0.18, 4.1, -hd - 0.08)), Vector3(door + 1.2, 0.12, 0.1), 0.01, B) # sliding rail
		g.box("painted_wood", P.call(Vector3(l * 0.25, 1.2, -hd - 0.04)), Vector3(1.0, 2.1, 0.1), 0.01, B)
		for wx: float in [l * 0.12, l * 0.38]:
			g.col = Color(0.06, 0.07, 0.08)
			g.box("glass", P.call(Vector3(wx, 3.4, -hd - 0.03)), Vector3(0.9, 0.7, 0.06), 0.0, B)
		g.col = Color.WHITE
		g.collide(P.call(Vector3(0, eave * 0.5, 0)), Vector3(l, eave, d), B)

	## Open-sided Dutch hay barn: steel columns, curved-ish roof, bales stacked inside.
	func _dutch(g: GxGeo, m: Transform3D) -> void:
		var bays := rng.randi_range(3, 4)
		var bay := 4.6
		var l := bays * bay
		var d := 9.0
		var h := 5.6
		var B := m.basis
		var P := func(v: Vector3) -> Vector3: return m * v
		g.col = Color(0.42, 0.44, 0.42)
		for i in bays + 1:
			var x := -l * 0.5 + i * bay
			for z: float in [-d * 0.5, d * 0.5]:
				g.box("painted_metal", P.call(Vector3(x, h * 0.5 - 0.3, z)), Vector3(0.22, h + 0.6, 0.22), 0.02, B)
		g.col = Color(0.55, 0.56, 0.55)
		var segs := 6
		for k in segs: # shallow arched roof
			var z0 := -d * 0.5 - 0.5 + (d + 1.0) * k / segs
			var z1 := -d * 0.5 - 0.5 + (d + 1.0) * (k + 1) / segs
			var y0 := h + 1.4 * (1.0 - pow(z0 / (d * 0.5 + 0.5), 2.0))
			var y1 := h + 1.4 * (1.0 - pow(z1 / (d * 0.5 + 0.5), 2.0))
			var zm := (z0 + z1) * 0.5
			var ang := atan2(y1 - y0, z1 - z0)
			g.box("corrugated", P.call(Vector3(0, (y0 + y1) * 0.5, zm)), Vector3(l + 0.8, 0.08, (z1 - z0) / cos(ang) + 0.05), 0.0, B * Basis(Vector3(1, 0, 0), -ang))
		# side cladding on the back (top half)
		g.col = Color(0.5, 0.52, 0.5)
		g.box("corrugated", P.call(Vector3(0, h - 1.2, d * 0.5 + 0.12)), Vector3(l, 2.4, 0.06), 0.0, B)
		# bales stacked inside
		var fill := rng.randf_range(0.4, 1.0)
		var rows := int(3 * fill) + 1
		for r in rows:
			for i in int((l - 1.0) / 2.45):
				for z: float in [-2.6, 0.0, 2.6]:
					if rng.randf() < 0.1:
						continue
					g.col = Color(0.95, 0.88, 0.72) * rng.randf_range(0.85, 1.0)
					g.box("hay", P.call(Vector3(-l * 0.5 + 1.4 + i * 2.45, 0.45 + r * 0.92, z)), Vector3(2.4, 0.9, 1.2), 0.06, B)
		g.col = Color.WHITE
		g.collide(P.call(Vector3(0, h * 0.5, 0)), Vector3(l, h, d), B)

	func _shed(g: GxGeo, m: Transform3D, style: String) -> void:
		var B := m.basis
		var P := func(v: Vector3) -> Vector3: return m * v
		g.col = Color(0.35, 0.3, 0.26) if style == "timber" else Color.WHITE
		g.box("wood", P.call(Vector3(0, 1.3, 0)), Vector3(6.0, 2.6, 4.0), 0.03, B)
		g.col = Color(0.5, 0.5, 0.48)
		g.box("corrugated", P.call(Vector3(0, 2.85, 0)), Vector3(6.6, 0.08, 4.8), 0.0, B * Basis(Vector3(1, 0, 0), 0.12))
		g.col = Color(0.2, 0.17, 0.14)
		g.box("painted_wood", P.call(Vector3(0.8, 1.05, -2.03)), Vector3(1.6, 2.0, 0.08), 0.0, B)
		g.col = Color.WHITE
		g.collide(P.call(Vector3(0, 1.3, 0)), Vector3(6.0, 2.6, 4.0), B)

	# ------------------------------------------------------------ forest tracks

	## Log piles at forest-road pull-offs and hunters' high seats on forest edges.
	func _forestry() -> void:
		var a := rng.randf_range(50.0, 200.0)
		while a < L:
			var side := Gx.LEFT if rng.randf() < 0.5 else Gx.RIGHT
			if rng.randf() < 0.55:
				var xf := Gx.frame(c, a, side, rng.randf_range(14.0, 22.0))
				if ok_at(xf.origin, 10.0, 7.0):
					_logs(xf)
			else:
				var xf := Gx.frame(c, a, side, rng.randf_range(26.0, 45.0))
				if ok_at(xf.origin, 18.0, 3.0):
					_high_seat(xf)
			a += rng.randf_range(220.0, 380.0)

	func _logs(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		var g := D(o)
		var x := xf.basis.x.normalized()
		var ll := rng.randf_range(4.0, 6.0)
		var rows := [5, 4, 3, 2] if rng.randf() < 0.5 else [6, 5, 4]
		var y := 0.0
		var fresh := rng.randf() < 0.6
		for r in rows.size():
			var n: int = rows[r]
			var rad := rng.randf_range(0.2, 0.28)
			for k in n:
				var zc := (k - (n - 1) * 0.5) * rad * 2.05
				var cpos := o + xf.basis.z.normalized() * zc + Vector3(0, y + rad, 0)
				var sh := rng.randf_range(-0.3, 0.3)
				g.col = Color(0.75, 0.68, 0.6) * rng.randf_range(0.8, 1.0)
				g.tube("logbark", [cpos - x * (ll * 0.5 + sh), cpos + x * (ll * 0.5 - sh)], rad, 7, false)
				g.col = Color(0.95, 0.82, 0.62) if fresh else Color(0.6, 0.52, 0.42)
				for e: float in [-1.0, 1.0]:
					var ec := cpos + x * e * (ll * 0.5 - sh * e)
					_disc(g, ec, x * e, rad * 0.97)
			y += 0.4
		g.col = Color.WHITE
		g.collide(o + Vector3(0, y * 0.5, 0), Vector3(ll, y, float(rows[0]) * 0.5), xf.basis.orthonormalized())
		take(o, 5.0)
		_n("logs", o)

	func _disc(g: GxGeo, cen: Vector3, n: Vector3, r: float) -> void:
		var u := n.cross(Vector3.UP).normalized()
		var v := n.cross(u).normalized()
		var prev := cen + u * r
		for k in range(1, 8):
			var a := TAU * k / 7.0
			var q := cen + (u * cos(a) + v * sin(a)) * r
			g.tri_f("endgrain", cen, prev, q, n)
			prev = q

	func _high_seat(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		var g := D(o)
		var b := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * xf.basis.orthonormalized()
		var P := func(v: Vector3) -> Vector3: return o + b * v
		var h := rng.randf_range(3.5, 4.5)
		g.col = Color(0.7, 0.62, 0.52)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				g.bar("logbark", P.call(Vector3(sx * 1.2, -0.2, sz * 1.2)), P.call(Vector3(sx * 0.7, h + 1.6, sz * 0.7)), 0.07, 5)
		# ladder up the road side
		for sx: float in [-0.3, 0.3]:
			g.bar("logbark", P.call(Vector3(sx, -0.1, -2.2)), P.call(Vector3(sx, h, -0.8)), 0.05, 4)
		for k in 9:
			var t := (k + 0.5) / 9.0
			g.bar("wood", P.call(Vector3(-0.3, t * h, -2.2 + t * 1.4)), P.call(Vector3(0.3, t * h, -2.2 + t * 1.4)), 0.03, 3)
		g.col = Color(0.42, 0.34, 0.26)
		g.box("wood", P.call(Vector3(0, h, 0)), Vector3(1.7, 0.1, 1.7), 0.01, b)
		g.box("wood", P.call(Vector3(0, h + 0.5, 0.82)), Vector3(1.6, 1.0, 0.06), 0.0, b)
		g.box("wood", P.call(Vector3(-0.82, h + 0.5, 0)), Vector3(0.06, 1.0, 1.6), 0.0, b)
		g.box("wood", P.call(Vector3(0.82, h + 0.5, 0)), Vector3(0.06, 1.0, 1.6), 0.0, b)
		g.box("wood", P.call(Vector3(0, h + 0.3, -0.82)), Vector3(1.6, 0.6, 0.06), 0.0, b)
		g.col = Color(0.3, 0.3, 0.3)
		g.box("corrugated", P.call(Vector3(0, h + 1.75, 0)), Vector3(2.0, 0.06, 2.0), 0.0, b * Basis(Vector3(1, 0, 0), 0.15))
		g.col = Color.WHITE
		take(o, 3.0)
		_n("high_seat", o)

	# ------------------------------------------------------------ lines, infra, people

	func _poles() -> void:
		for k in int(p.poles):
			for tries in 6:
				var a := rng.randf_range(0.0, L)
				var side := Gx.LEFT if rng.randf() < 0.5 else Gx.RIGHT
				var lat := rng.randf_range(45.0, 90.0)
				var xf := Gx.frame(c, a, side, lat)
				if forest_at(xf.origin) > 0.5:
					continue
				GxPower.place(c, Gx.road_frame(c, a), {kind = "poles", route = "along", side = side, lateral = lat, reach = 260.0, span = 42.0})
				_n("poles")
				break

	func _infra() -> void:
		var corners := Gx.corners(c, 0.3)
		var list: Array = p.infra
		var ci := 0
		var used: Array = []
		for kind: String in list:
			var done := false
			while ci < corners.size() and not done:
				var cr: Dictionary = corners[ci]
				ci += 1
				var along: float = cr.along
				var clash := false
				for u: float in used:
					if absf(u - along) < 120.0:
						clash = true
				if clash:
					continue
				var outside := -float(cr.turn) # outside of the corner: run-off side
				var side := outside if kind == "tv" else (-outside if kind == "marshal" else outside)
				var lat: float = {tv = 16.0, marshal = 9.0, light = 30.0}[kind]
				for tries in 4:
					var xf := Gx.frame(c, along + (tries * 18.0 - 27.0) + (40.0 if kind == "light" else 0.0), side, lat + tries * 3.0)
					if ok_at(xf.origin, 7.0, 4.0):
						match kind:
							"tv":
								_tv_tower(xf)
							"marshal":
								_marshal_post(xf)
							_:
								_light_mast(xf)
						used.append(along)
						done = true
						break
		# light masts on straights too (autodromo)
		if list.has("light"):
			for st: Dictionary in Gx.straights(c, 200.0):
				var a: float = st.from + 60.0
				while a < float(st.to) - 40.0:
					var xf := Gx.frame(c, a, Gx.LEFT if int(a / 160.0) % 2 == 0 else Gx.RIGHT, 28.0)
					if ok_at(xf.origin, 10.0, 4.0):
						_light_mast(xf)
					a += 160.0

	## Scaffold TV camera tower: tube-and-clamp, plank deck, railing, sponsor
	## sheeting, camera on a fluid head.
	func _tv_tower(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		var g := B(Transform3D(xf.basis.orthonormalized(), o))
		var h := rng.randf_range(6.0, 9.0)
		var s := 1.6
		g.col = Color(0.75, 0.75, 0.73)
		for sx: float in [-s, s]:
			for sz: float in [-s, s]:
				g.bar("steel", Vector3(sx, -0.3, sz), Vector3(sx, h + 1.1, sz), 0.03, 6)
		var y := 0.2
		while y < h + 0.1:
			for sx: float in [-s, s]:
				g.bar("steel", Vector3(sx, y, -s), Vector3(sx, y, s), 0.025, 4)
			for sz: float in [-s, s]:
				g.bar("steel", Vector3(-s, y, sz), Vector3(s, y, sz), 0.025, 4)
			y += 2.0
		y = 0.2
		var flip := 1.0
		while y < h - 1.9:
			g.bar("steel", Vector3(-s, y, s), Vector3(s, y + 2.0, s), 0.022, 4)
			g.bar("steel", Vector3(s * flip, y, -s), Vector3(-s * flip, y + 2.0, -s), 0.022, 4)
			g.bar("steel", Vector3(-s, y, -s * flip), Vector3(-s, y + 2.0, s * flip), 0.022, 4)
			flip = -flip
			y += 2.0
		for sz: float in [-s, s]: # top rail
			g.bar("steel", Vector3(-s, h + 1.0, sz), Vector3(s, h + 1.0, sz), 0.025, 4)
		g.bar("steel", Vector3(s, h + 1.0, -s), Vector3(s, h + 1.0, s), 0.025, 4)
		g.bar("steel", Vector3(-s, h + 1.0, -s), Vector3(-s, h + 1.0, s), 0.025, 4)
		g.col = Color(0.55, 0.45, 0.33)
		g.box("wood", Vector3(0, h + 0.03, 0), Vector3(s * 2.0 + 0.3, 0.06, s * 2.0 + 0.3), 0.0)
		# sheeting with a sponsor print facing the road
		g.col = Color(0.15, 0.17, 0.2)
		g.box("canvas", Vector3(0, h - 1.2, -s - 0.04), Vector3(s * 2.0, 2.0, 0.03), 0.0)
		var keys := ["b_helios", "b_kronen", "b_nordlicht", "b_aurel", "b_falke", "b_spect"]
		g.sign(Vector3(0, h - 1.2, -s - 0.07), Vector3(0, 0, -1), s * 2.0 - 0.2, 0.0, keys[rng.randi() % keys.size()])
		# camera + operator's umbrella
		g.col = Color(0.12, 0.12, 0.13)
		g.bar("steel", Vector3(0, h, -0.6), Vector3(0, h + 1.35, -0.6), 0.04, 5)
		g.box("painted_metal", Vector3(0, h + 1.5, -0.7), Vector3(0.3, 0.32, 0.6), 0.03)
		g.bar("steel", Vector3(0, h + 1.5, -1.0), Vector3(0, h + 1.5, -1.35), 0.09, 8)
		g.col = Color(0.85, 0.85, 0.83)
		g.bar("steel", Vector3(0.9, h, 0.6), Vector3(0.9, h + 2.4, 0.6), 0.02, 4)
		g.col = [Color(0.9, 0.9, 0.88), Color(0.12, 0.25, 0.55), Color(0.75, 0.12, 0.1)][rng.randi() % 3]
		g.lathe("canvas", Vector3(0.9, h + 2.0, 0.6), PackedVector2Array([Vector2(0.02, 0.45), Vector2(1.2, 0.0), Vector2(0.0, 0.0)]), 10)
		g.col = Color.WHITE
		g.collide(Vector3(0, h * 0.5, 0), Vector3(s * 2.0, h, s * 2.0))
		done(g)
		take(o, 4.0)
		_n("tv", o)

	## Marshal post: a small white cabin on a concrete pad, flag box, fire
	## extinguisher stand, a numbered board.
	func _marshal_post(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		var g := B(Transform3D(xf.basis.orthonormalized(), o))
		g.col = Color(0.8, 0.79, 0.76)
		g.box("concrete", Vector3(0, -0.15, 0.4), Vector3(4.0, 0.5, 3.4), 0.03)
		g.col = Color(0.93, 0.93, 0.9)
		g.box("painted_metal", Vector3(0, 1.25, 1.0), Vector3(2.4, 2.4, 2.0), 0.05)
		g.col = Color(0.85, 0.42, 0.06)
		g.box("painted_metal", Vector3(0, 2.0, -0.02), Vector3(2.42, 0.3, 0.06), 0.0)
		g.col = Color(0.1, 0.1, 0.11)
		g.box("glass", Vector3(0, 1.55, -0.02), Vector3(1.6, 0.7, 0.05), 0.0)
		g.col = Color(0.55, 0.55, 0.53)
		g.box("painted_metal", Vector3(0, 2.52, 1.0), Vector3(2.7, 0.08, 2.4), 0.02)
		# flag box + extinguishers
		g.col = Color(0.85, 0.12, 0.08)
		for k in 2:
			g.lathe("painted_metal", Vector3(1.6 + k * 0.3, 0.1, -0.4), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.09, 0.0), Vector2(0.09, 0.55), Vector2(0.05, 0.65), Vector2(0.0, 0.66)]), 8)
		g.col = Color(0.3, 0.3, 0.3)
		g.box("steel", Vector3(-1.6, 0.6, -0.4), Vector3(0.5, 0.9, 0.3), 0.02)
		g.col = Color.WHITE
		g.collide(Vector3(0, 1.25, 1.0), Vector3(2.4, 2.4, 2.0))
		done(g)
		take(o, 3.5)
		_n("marshal", o)

	## Floodlight mast: tapered galvanised tube, a head frame with lamp boxes.
	func _light_mast(xf: Transform3D) -> void:
		var o := gnd(xf.origin)
		var g := B(Transform3D(xf.basis.orthonormalized(), o))
		var h := rng.randf_range(24.0, 30.0)
		g.col = Color(0.72, 0.73, 0.72)
		g.tube("steel", [Vector3(0, -0.5, 0), Vector3(0, h, 0)], 0.35, 10, true, [0.38, 0.17])
		g.col = Color(0.75, 0.75, 0.74)
		g.box("concrete", Vector3(0, -0.1, 0), Vector3(1.6, 0.6, 1.6), 0.05)
		g.col = Color(0.62, 0.63, 0.62)
		g.box("steel", Vector3(0, h + 0.2, -0.2), Vector3(4.2, 0.14, 0.14), 0.0)
		g.box("steel", Vector3(0, h + 1.5, -0.2), Vector3(4.2, 0.14, 0.14), 0.0)
		for k in 4:
			var x := -1.6 + k * 1.07
			g.bar("steel", Vector3(x, h + 0.2, -0.2), Vector3(x, h + 1.6, -0.2), 0.04, 4)
		var tilt := Basis(Vector3(1, 0, 0), 0.35)
		for r in 2:
			for k in 4:
				var lp := Vector3(-1.6 + k * 1.07, h + 0.55 + r * 0.95, -0.5)
				g.col = Color(0.3, 0.31, 0.31)
				g.box("painted_metal", lp, Vector3(0.75, 0.6, 0.3), 0.03, tilt)
				g.col = Color(0.85, 0.88, 0.9)
				g.box("glass", lp + tilt * Vector3(0, 0, -0.16), Vector3(0.62, 0.48, 0.02), 0.0, tilt)
		# ladder cage line
		g.col = Color(0.6, 0.6, 0.6)
		g.bar("steel", Vector3(0.0, 0.5, 0.42), Vector3(0.0, h, 0.25), 0.025, 4)
		g.col = Color.WHITE
		g.collide(Vector3(0, 2.0, 0), Vector3(0.8, 4.0, 0.8))
		done(g)
		take(o, 3.0)
		_n("light", o)

	## Spectator banks further back on rises at the corners, cars parked along
	## a farm track behind one of them.
	func _crowds() -> void:
		var zones: Array = c.get_meta("fan_zones", [])
		var corners := Gx.corners(c, 0.35)
		var placed := 0
		var cars := 0
		for cr: Dictionary in corners:
			if placed >= int(p.crowds):
				break
			var along: float = cr.along
			var side := -float(cr.turn)
			var xf := Gx.frame(c, along + 20.0, side, rng.randf_range(24.0, 36.0))
			var near := false
			for z: Dictionary in zones:
				if (z.get("pos", Vector3.INF) as Vector3).distance_to(xf.origin) < 60.0:
					near = true
			if near or not ok_at(xf.origin, 18.0, 8.0) or forest_at(xf.origin) > 0.8:
				continue
			GxFans.place(c, xf, {count = rng.randi_range(16, 26), flags = 2, depth = 8.0, tape = false})
			take(xf.origin + xf.basis.z.normalized() * 4.0, 10.0)
			# the worn footpath the fans walked in on
			var px := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)) * xf.basis.orthonormalized(), xf.origin + xf.basis.x.normalized() * 6.0)
			_track(px, 6.0, rng.randf_range(35.0, 60.0), 1.3, 1)
			placed += 1
			_n("crowd", xf.origin)
			if cars < 1:
				var cx := Gx.frame(c, along + 55.0, side, 26.0)
				if ok_at(cx.origin, 18.0, 12.0) and forest_at(cx.origin) < 0.8:
					GxParkedCars.place(c, cx, {count = 8, layout = "parallel", seed = 11})
					take(cx.origin, 14.0)
					cars += 1
					_n("cars")

	## One batch-2 piece per track (frame budget): a working farm on the
	## countryside tracks, the hospitality village at the autodromo.
	func _batch2() -> void:
		var dir := "res://scripts/track/gimmicks/%s.gd"
		if id in ["valle_club", "herbstwald", "kuestenstrasse", "altstadt"] and ResourceLoader.exists(dir % "gx_farm"):
			var xf = GxSpot.find(c, GxSpot.on_straights(c), [12.0, 20.0, 30.0], 36.0, 0.0, 50.0, 7.0)
			if xf != null:
				load(dir % "gx_farm").place(c, xf, {})
				_n("gx_farm")

	# ------------------------------------------------------------ materials / commit

	func _mat(key: String) -> Material:
		if _mats.has(key):
			return _mats[key]
		var m: Material = null
		match key:
			"drystone":
				var s := StandardMaterial3D.new()
				s.albedo_texture = load("res://assets/themes/stone_wall/stone_wall_diff_1k.jpg")
				s.normal_enabled = true
				s.normal_texture = load("res://assets/themes/stone_wall/stone_wall_nor_gl_1k.jpg")
				s.uv1_triplanar = true
				s.uv1_world_triplanar = true
				s.uv1_scale = Vector3(0.45, 0.45, 0.45)
				s.vertex_color_use_as_albedo = true
				s.roughness = 0.6 if wet > 0.4 else 0.92
				s.albedo_color = Color(0.92, 0.9, 0.86) if id != "capo_rosso" else Color(1.05, 0.98, 0.88)
				m = s
			"soil":
				var s := StandardMaterial3D.new()
				s.albedo_texture = load("res://assets/themes/farm_soil/farm_soil_diff_1k.jpg")
				s.normal_enabled = true
				s.normal_texture = load("res://assets/themes/farm_soil/farm_soil_nor_gl_1k.jpg")
				s.uv1_triplanar = true
				s.uv1_world_triplanar = true
				s.uv1_scale = Vector3(0.3, 0.3, 0.3)
				s.roughness = 0.55 if wet > 0.4 else 0.95
				s.albedo_color = Color(0.85, 0.8, 0.72) if snow < 0.3 else Color(0.95, 0.96, 1.0)
				m = s
			"logbark":
				var s := StandardMaterial3D.new()
				s.albedo_texture = load("res://assets/vegetation/trees/bark_conifer.jpg")
				s.normal_enabled = true
				s.normal_texture = load("res://assets/vegetation/trees/bark_conifer_normal.jpg")
				s.uv1_triplanar = true
				s.uv1_world_triplanar = true
				s.uv1_scale = Vector3(0.8, 0.8, 0.8)
				s.vertex_color_use_as_albedo = true
				s.roughness = 0.9
				m = s
			"endgrain":
				var s := StandardMaterial3D.new()
				s.vertex_color_use_as_albedo = true
				s.albedo_texture = load("res://assets/vegetation/trees/bark_broadleaf.jpg")
				s.uv1_triplanar = true
				s.uv1_world_triplanar = true
				s.uv1_scale = Vector3(3.0, 3.0, 3.0)
				s.albedo_color = Color(1.6, 1.4, 1.2)
				s.roughness = 0.85
				m = s
			"hay":
				m = GxProps.material("hay")
		_mats[key] = m
		return m

	var _holder: Node3D
	func holder() -> Node3D:
		if _holder == null:
			_holder = Node3D.new()
			_holder.name = "FillLandscape"
			c.add_child(_holder)
		return _holder

	func _commit(g: GxGeo, node_name: String, vis_end: float, shadows := false) -> Node3D:
		var root := g.commit(holder(), node_name, vis_end, shadows)
		for ch in root.get_children():
			if ch is MeshInstance3D:
				var mm := _mat(String(ch.name))
				if mm != null:
					(ch as MeshInstance3D).material_override = mm
				if String(ch.name) in ["soil", "endgrain", "glass", "steel", "canvas"] and vis_end == 0.0 and not shadows:
					(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return root

	func _flush() -> void:
		var hold := holder()
		for k in main:
			_commit(main[k], "FillMain", 0.0, false)
		for k in detail:
			_commit(detail[k], "FillDetail", DETAIL_VIS, false)
		for k in structs:
			_commit(structs[k], "FillStruct", 0.0, true)
		# hedges: bush MultiMeshes per cell, always drawn (cheap cards)
		if not hedges.is_empty():
			var mat := Vegetation.broadleaf_material(c.get("noise_tex"), 0.35, snow * 0.8, wet)
			mat.set_meta("wind_mul", 1.1)
			for k in hedges:
				for v in 3:
					var xfs: Array = hedges[k][v]
					if xfs.is_empty():
						continue
					var mm := MultiMesh.new()
					mm.transform_format = MultiMesh.TRANSFORM_3D
					mm.mesh = bush_meshes[v]
					counts["hedge_tris"] = int(counts.get("hedge_tris", 0)) + xfs.size() * bush_meshes[v].surface_get_array_len(0) / 3
					mm.instance_count = xfs.size()
					for i in xfs.size():
						mm.set_instance_transform(i, xfs[i])
					var mmi := MultiMeshInstance3D.new()
					mmi.name = "FillHedge"
					mmi.multimesh = mm
					mmi.material_override = mat
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					mmi.extra_cull_margin = 2.0
					hold.add_child(mmi)
		# trees: near MultiMesh -> far LOD MultiMesh per 100 m cell (as the forest / themes)
		var near_end: float = [160.0, 200.0, 300.0, 340.0][clampi(Game.quality, 0, 3)]
		var mats := {}
		for model: String in trees:
			var lods := Vegetation.model(model)
			if lods.is_empty():
				continue
			var list: Array = p.trees
			var conifer: bool = p.conifer[maxi(list.find(model), 0)]
			if not mats.has(conifer):
				mats[conifer] = Vegetation.conifer_material(c.get("noise_tex"), 0.3, snow, wet) if conifer else Vegetation.broadleaf_material(c.get("noise_tex"), 0.35, snow * 0.7, wet)
				if not conifer:
					(mats[conifer] as Material).set_meta("wind_mul", 1.15)
					(mats[conifer] as Material).set_meta("snow_mul", 0.7)
					var def = c.get("def")
					if def is Dictionary and def.get("theme", "") == "autumn":
						(mats[conifer] as ShaderMaterial).set_shader_parameter("autumn", 1.0)
			var mat: Material = mats[conifer]
			for k in trees[model]:
				var xfs: Array = trees[model][k]
				var near := _mmi(lods[0], xfs, mat, "FillTreeNear")
				counts["tree_tris_near"] = int(counts.get("tree_tris_near", 0)) + xfs.size() * (lods[0] as ArrayMesh).surface_get_array_len(0) / 3
				counts["tree_tris_far"] = int(counts.get("tree_tris_far", 0)) + xfs.size() * (lods[1] as ArrayMesh).surface_get_array_len(0) / 3
				var far := _mmi(lods[1], xfs, mat, "FillTreeFar")
				var sh := _mmi(lods[1], xfs, mat, "FillTreeShadow")
				far.visibility_range_begin = near_end
				far.visibility_range_begin_margin = 8.0
				near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				hold.add_child(far)
				hold.add_child(near)
				hold.add_child(sh)
				near.visibility_parent = near.get_path_to(far)
				sh.visibility_parent = sh.get_path_to(far)

	func _mmi(mesh: Mesh, xfs: Array, mat: Material, node_name: String) -> MultiMeshInstance3D:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = node_name
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.extra_cull_margin = 4.0
		return mmi
