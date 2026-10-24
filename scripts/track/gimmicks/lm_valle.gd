extends RefCounted
## Valle Club's own landmark (called from dress_valle_club.gd): the "Tenuta
## Valle" wine estate on the slope above the circuit. Rows of trained vines on
## posts and wires running down the hill (photo-leaf foliage, one MultiMesh),
## an ochre farmhouse with a stone plinth, terracotta roof, green shutters and
## a dovecote tower (colombaia), a barrel store, and a cypress avenue.

const ROW_GAP := 2.5
const SEG := 1.6

static var _vine_mat: ShaderMaterial
static var _cyp_mat: ShaderMaterial


## Pick the best slope beside the track and build the estate. Returns its centre.
static func estate(c: Node3D) -> Vector3:
	var best := {}
	var best_score := -INF
	var l := Gx.length(c)
	var along := 0.0
	while along < l:
		for side: float in [Gx.LEFT, Gx.RIGHT]:
			for lat: float in [55.0, 75.0, 95.0]:
				var f := Gx.frame(c, along, side, lat)
				var u := f.basis.z # away from the road
				var v := f.basis.x
				var p := f.origin
				var ok := true
				for cu: float in [-32.0, 0.0, 32.0, 50.0]:
					for cv: float in [-26.0, 0.0, 26.0]:
						var q := p + u * cu + v * cv
						if not Gx.clear_of_road(c, q, 22.0) or _reserved(c, q):
							ok = false
				if not ok or not _in_terrain(c, p, 110.0):
					continue
				var rise := Gx.ground(c, p + u * 30.0) - Gx.ground(c, p - u * 30.0)
				var score := rise - lat * 0.05
				if score > best_score:
					best_score = score
					best = {p = p, u = u, v = v}
		along += 20.0
	if best.is_empty():
		return Vector3.INF
	var p: Vector3 = best.p
	var u: Vector3 = best.u
	var v: Vector3 = best.v
	_vineyard(c, p, u, v, 56.0, 14)
	var house := p + u * 46.0
	house.y = Gx.ground(c, house)
	_farmhouse(c, Transform3D(Basis(v, Vector3.UP, -u), house)) # front (-z) faces down the hill
	_cypresses(c, p + v * (14 * ROW_GAP * 0.5 + 5.0), u, 34.0, -26.0)
	for k: float in [-30.0, 0.0, 30.0, 48.0]:
		Gx.reserve(c, p + u * k, 30.0)
	if OS.get_cmdline_user_args().has("--debug-dress"):
		print("DRESS estate at ", p.snapped(Vector3.ONE), " up ", u.snapped(Vector3.ONE * 0.01), " score ", best_score)
	return p


static func _reserved(c: Node3D, p: Vector3) -> bool:
	for z: Array in c.get_meta("no_trees", []):
		var q: Vector3 = z[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < float(z[1]) + 2.0:
			return false if float(z[1]) > 100.0 else true
	return false


static func _in_terrain(c: Node3D, p: Vector3, margin: float) -> bool:
	var t = c.get("terrain")
	if not t is Terrain:
		return true
	var tt := t as Terrain
	var size := tt.cell * (Terrain.N - 1)
	return p.x > tt.origin.x + margin and p.z > tt.origin.y + margin \
		and p.x < tt.origin.x + size - margin and p.z < tt.origin.y + size - margin


# ------------------------------------------------------------------ vines

static func vine_mat() -> ShaderMaterial:
	if _vine_mat == null:
		_vine_mat = Vegetation.broadleaf_material(Mats.noise(), 0.25)
		_vine_mat.set_shader_parameter("tint", Vector3(0.5, 0.6, 0.26))
	return _vine_mat


## One 1.6 m stretch of a trained vine row: gnarled trunk + leafy curtain.
static func _vine_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var b := Vegetation.Builder.new(1.7)
	var tx := rng.randf_range(-0.3, 0.3)
	Vegetation._limb(b, [Vector3(tx, 0, 0), Vector3(tx + 0.05, 0.45, 0.03), Vector3(tx, 0.85, 0)], [0.045, 0.035, 0.03],
		[0.0, 0.0, 0.1], 4, Vegetation.BARK0, 0.6, 0.35, rng.randf())
	# cordon arms along the wire
	Vegetation._limb(b, [Vector3(tx, 0.85, 0), Vector3(-0.8, 0.9, 0.02)], [0.025, 0.018], [0.1, 0.2], 3, Vegetation.BARK0, 0.6, 0.4, rng.randf())
	Vegetation._limb(b, [Vector3(tx, 0.85, 0), Vector3(0.8, 0.88, -0.02)], [0.025, 0.018], [0.1, 0.2], 3, Vegetation.BARK0, 0.6, 0.4, rng.randf())
	for k in 12:
		var x := rng.randf_range(-0.85, 0.85)
		var y := rng.randf_range(0.8, 1.45)
		var side := -1.0 if k % 2 == 0 else 1.0
		var at := Vector3(x, y, side * rng.randf_range(0.05, 0.2))
		var out := Vector3(rng.randf_range(-0.3, 0.3), 1.0, side * rng.randf_range(0.2, 0.7)).normalized()
		var face := Vector3(0, 0, side).rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		var cell := Vegetation._cell(6 + rng.randi() % 2 if rng.randf() < 0.65 else 4 + rng.randi() % 2, Vegetation.LEAF_COLS, Vegetation.LEAF_ROWS)
		Vegetation._spray(b, at, out, face, rng.randf_range(0.55, 0.8), cell, Vector3(0, 0.6, side),
			clampf(0.45 + (y - 0.8), 0.4, 1.0), 0.3, 1.0, rng.randf())
	return b.commit()


static func _vineyard(c: Node3D, p: Vector3, u: Vector3, v: Vector3, length: float, rows: int) -> void:
	var rng := Gx.rng(c, "vines")
	var meshes: Array[ArrayMesh] = [_vine_mesh(rng), _vine_mesh(rng), _vine_mesh(rng)]
	var xfs: Array = [[], [], []]
	var g := GxGeo.new(Transform3D.IDENTITY)
	var basis := Basis(u, Vector3.UP, u.cross(Vector3.UP).normalized())
	for r in rows:
		var off := (r - (rows - 1) * 0.5) * ROW_GAP
		var start := p - u * length * 0.5 + v * off
		var n := int(length / SEG)
		var wire_lo: Array = []
		var wire_hi: Array = []
		for k in n:
			var q := start + u * (k + 0.5) * SEG
			q.y = Gx.ground(c, q)
			if k % 3 == 0 or k == n - 1:
				var post := q + u * (SEG * 0.5 if k == n - 1 else -SEG * 0.5)
				post.y = Gx.ground(c, post)
				g.col = Color(0.7, 0.62, 0.52).darkened(rng.randf_range(0.0, 0.25))
				g.box("wood", post + Vector3(0, 0.8, 0), Vector3(0.09, 1.75, 0.09), 0.015)
				wire_lo.append(post + Vector3(0, 0.88, 0))
				wire_hi.append(post + Vector3(0, 1.4, 0))
			if rng.randf() < 0.04:
				continue # a missing vine here and there
			var s := rng.randf_range(0.9, 1.1)
			var yaw := rng.randf_range(-0.05, 0.05)
			xfs[rng.randi() % 3].append(Transform3D(basis.rotated(Vector3.UP, yaw).scaled(Vector3(1.0, s, 1.0)), q))
		g.col = Color(0.5, 0.5, 0.5)
		if wire_lo.size() > 1:
			g.tube("steel", wire_lo, 0.008, 3, false)
			g.tube("steel", wire_hi, 0.008, 3, false)
	g.commit(c, "VinePosts", 380.0, false)
	for i in 3:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = xfs[i].size()
		for k in xfs[i].size():
			mm.set_instance_transform(k, xfs[i][k])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Vines%d" % i
		mmi.multimesh = mm
		mmi.material_override = vine_mat()
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 280.0 + length * 0.7
		mmi.visibility_range_end_margin = 50.0
		c.add_child(mmi)


# ------------------------------------------------------------------ cypresses

static func _cypresses(c: Node3D, p: Vector3, u: Vector3, from: float, to: float) -> void:
	var rng := Gx.rng(c, "cypress")
	# Baked Italian cypress (tools/trees); the old squashed spruce as a fallback.
	var meshes: Array = Vegetation.model("cypress_1")
	var baked := not meshes.is_empty()
	if not baked:
		meshes = Vegetation.spruce(rng, 13.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = meshes[0] if baked else meshes[1]
	var xfs: Array[Transform3D] = []
	var d := from
	while d > to:
		for off: float in [0.0, 4.5]:
			var q := p + u * d + u.cross(Vector3.UP).normalized() * off
			q.y = Gx.ground(c, q) - 0.2
			var h := rng.randf_range(0.8, 1.15)
			var w := h * rng.randf_range(0.9, 1.05) if baked else rng.randf_range(0.26, 0.32)
			xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w)), q))
		d -= 7.0
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	if _cyp_mat == null:
		_cyp_mat = Vegetation.conifer_material(Mats.noise(), 0.2)
		_cyp_mat.set_shader_parameter("tint", Vector3(0.3, 0.42, 0.3))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cypresses"
	mmi.multimesh = mm
	mmi.material_override = _cyp_mat
	mmi.visibility_range_end = 700.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.add_child(mmi)


# ------------------------------------------------------------------ farmhouse

static func _farmhouse(c: Node3D, xf: Transform3D) -> void:
	var g := GxGeo.new(xf)
	var gy := 0.0
	# lowest ground under the footprint so nothing floats
	for x: float in [-11.0, 0.0, 11.0, 17.0]:
		for z: float in [-5.0, 5.0]:
			gy = minf(gy, Gx.ground(c, xf * Vector3(x, 0, z)) - xf.origin.y)
	var ochre := Color(0.86, 0.63, 0.4)
	# main block: stone plinth + two plastered floors
	g.col = Color(0.85, 0.82, 0.76)
	g.box("stone", Vector3(0, gy + 0.6, 0), Vector3(18.4, 2.2, 8.4), 0.04)
	g.col = ochre
	g.box("plaster", Vector3(0, gy + 4.1, 0), Vector3(18.0, 5.6, 8.0), 0.05)
	g.collide(Vector3(0, gy + 3.5, 0), Vector3(18.4, 7.0, 8.4))
	_gable_roof(g, Vector3(0, gy + 6.9, 0), 19.0, 9.2, 2.3)
	# barrel store wing with arched (dark) openings
	g.col = ochre.darkened(0.06)
	g.box("plaster", Vector3(14.0, gy + 2.2, 0.8), Vector3(10.0, 4.6, 6.4), 0.05)
	g.collide(Vector3(14.0, gy + 2.2, 0.8), Vector3(10.0, 4.6, 6.4))
	_gable_roof(g, Vector3(14.0, gy + 4.5, 0.8), 10.6, 7.2, 1.5)
	for ax: float in [11.0, 14.0, 17.0]:
		g.col = Color(0.08, 0.07, 0.06)
		g.box("plaster", Vector3(ax, gy + 1.5, -2.42), Vector3(2.0, 2.8, 0.1))
		g.col = Color(0.85, 0.82, 0.76)
		g.extrude_xf("stone", _arch_profile(1.0, 0.3), -0.15, 0.15, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(ax, gy + 2.9, -2.42)), 0.0, false)
	# windows: photo windows with green shutters (FacadeKit), a Provençal door
	var ph := SurfaceTool.new()
	ph.begin(Mesh.PRIMITIVE_TRIANGLES)
	for fz: float in [-4.02, 4.02]:
		var nz := signf(fz)
		var right := Vector3.LEFT if nz < 0.0 else Vector3.RIGHT
		for wx: float in [-6.6, -3.3, 0.0, 3.3, 6.6]:
			for wy: float in [2.6, 5.4]:
				if fz < 0.0 and wy < 3.0 and absf(wx) < 0.1:
					FacadeKit.add_unit(ph, Vector3(wx, gy + 1.1, fz + nz * 0.23), right, 12, 2.6)
					continue
				FacadeKit.add_unit(ph, Vector3(wx, gy + wy - 0.75, fz + nz * 0.03), right, 4 + absi(int(wx + wy)) % 2, 1.5)
	var wins := Gx.add_mesh(c, ph, FacadeKit.unit_material(), "TenutaValle_windows", 1200.0)
	wins.transform = g.xf
	# dovecote tower (colombaia) at the west end, with its own hipped roof
	var tx := -11.0
	g.col = ochre.lightened(0.03)
	g.box("plaster", Vector3(tx, gy + 6.5, 0.5), Vector3(4.6, 13.0, 4.6), 0.05)
	g.collide(Vector3(tx, gy + 6.5, 0.5), Vector3(4.6, 13.0, 4.6))
	g.col = Color(0.85, 0.82, 0.76)
	g.box("stone", Vector3(tx, gy + 1.0, 0.5), Vector3(4.9, 2.0, 4.9), 0.04)
	g.box("stone", Vector3(tx, gy + 9.4, 0.5), Vector3(4.9, 0.25, 4.9), 0.03)
	for f: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0)]:
		for k: float in [-0.9, 0.9]:
			var side := Vector3(-f.z, 0, f.x)
			var at := Vector3(tx, gy + 11.0, 0.5) + f * 2.31 + side * k
			g.col = Color(0.06, 0.05, 0.05)
			g.box("plaster", at, Vector3(0.7 if f.x == 0.0 else 0.08, 1.6, 0.08 if f.x == 0.0 else 0.7))
	var roof := GxGeo.new(xf * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(tx, gy + 13.0, 0.5)))
	roof.col = Color(0.62, 0.3, 0.19)
	roof.lathe("roof_tiles", Vector3.ZERO, PackedVector2Array([Vector2(3.6, -0.05), Vector2(3.6, 0.15), Vector2(0.05, 2.2), Vector2(0.0, 2.21)]), 4)
	roof.commit(c, "EstateTowerRoof", 1200.0)
	# stone quoins on the corners of the house and the tower
	for q: Array in [[Vector3(-9.0, 0, -4.0), 5.6, -1.0, -1.0], [Vector3(9.0, 0, -4.0), 5.6, 1.0, -1.0], [Vector3(9.0, 0, 4.0), 5.6, 1.0, 1.0],
			[Vector3(tx - 2.3, 0, -1.8), 11.0, -1.0, -1.0], [Vector3(tx + 2.3, 0, -1.8), 11.0, 1.0, -1.0], [Vector3(tx - 2.3, 0, 2.8), 11.0, -1.0, 1.0]]:
		_quoins(g, q[0] + Vector3(0, gy + 1.7, 0), float(q[1]), float(q[2]), float(q[3]))
	# chimney
	g.col = ochre.darkened(0.1)
	g.box("plaster", Vector3(4.5, gy + 9.4, 1.6), Vector3(0.8, 2.2, 0.8), 0.03)
	g.col = Color(0.6, 0.3, 0.2)
	g.box("roof_tiles", Vector3(4.5, gy + 10.6, 1.6), Vector3(1.1, 0.15, 1.1), 0.03)
	# barrels and a bench by the store
	for k in 4:
		var bp := Vector3(10.5 + k * 1.1, gy + 0.0, -3.4 - (k % 2) * 0.3)
		g.col = Color(0.5, 0.33, 0.2)
		g.lathe("painted_wood", bp, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.36, 0.0), Vector2(0.43, 0.5), Vector2(0.36, 1.0), Vector2(0.0, 1.0)]), 10)
		g.col = Color(0.25, 0.25, 0.26)
		for hy: float in [0.15, 0.85]:
			g.lathe("steel", bp, PackedVector2Array([Vector2(0.385 + (0.02 if hy > 0.5 else 0.0), hy - 0.04), Vector2(0.39 + (0.02 if hy > 0.5 else 0.0), hy + 0.04)]), 10)
	# estate sign by the drive
	g.col = Color(0.85, 0.82, 0.76)
	g.box("stone", Vector3(-3.0, gy + 0.6, -12.0), Vector3(3.2, 1.2, 0.5), 0.05)
	g.commit(c, "TenutaValle", 1200.0)
	var lbl := Label3D.new()
	lbl.text = "TENUTA VALLE"
	lbl.font = load("res://assets/fonts/BarlowSemiCondensed-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/BarlowSemiCondensed-Bold.ttf") else null
	lbl.font_size = 64
	lbl.pixel_size = 0.006
	lbl.modulate = Color(0.25, 0.18, 0.12)
	lbl.outline_size = 0
	lbl.double_sided = false
	lbl.shaded = true
	lbl.transform = xf * Transform3D(Basis(Vector3.UP, PI), Vector3(-3.0, gy + 0.6, -12.27))
	lbl.visibility_range_end = 200.0
	c.add_child(lbl)
	Gx.reserve(c, xf.origin, 22.0)
	Gx.reserve(c, xf * Vector3(14, 0, 0), 10.0)


## Alternating long/short dressed stones up a building corner at `p` (local).
static func _quoins(g: GxGeo, p: Vector3, h: float, sx: float, sz: float) -> void:
	g.col = Color(0.88, 0.85, 0.78)
	var y := 0.0
	var k := 0
	while y < h - 0.3:
		var long := k % 2 == 0
		var ax := Vector3(-sx * (0.35 if long else 0.2), 0, -sz * (0.2 if long else 0.35))
		g.box("stone", p + ax + Vector3(0, y + 0.17, 0), Vector3(0.8 if long else 0.5, 0.32, 0.5 if long else 0.8), 0.02)
		y += 0.36
		k += 1


## Terracotta gable roof centred at `c` (ridge along x), with eaves overhang.
static func _gable_roof(g: GxGeo, c: Vector3, length: float, depth: float, rise: float) -> void:
	var hz := depth * 0.5
	g.col = Color(0.66, 0.33, 0.21)
	g.extrude_xf("roof_tiles", PackedVector2Array([Vector2(-hz, 0.0), Vector2(hz, 0.0), Vector2(0.0, rise)]),
		-length * 0.5, length * 0.5, Transform3D(Basis(), c))
	# gable end walls (plaster triangles) inset a little
	g.col = Color(0.84, 0.61, 0.39)
	for ex: float in [-length * 0.5 + 0.35, length * 0.5 - 0.35]:
		g.extrude_xf("plaster", PackedVector2Array([Vector2(-hz + 0.5, -0.02), Vector2(hz - 0.5, -0.02), Vector2(0.0, rise - 0.3)]), ex - 0.1, ex + 0.1, Transform3D(Basis(), c))


## Semicircular arch ring (stone voussoirs) as a (z, y) profile band of radius r.
static func _arch_profile(r: float, t: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 9:
		var a := PI * k / 8.0
		pts.append(Vector2(cos(a) * (r + t), sin(a) * (r + t)))
	for k in 9:
		var a := PI * (8 - k) / 8.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts
