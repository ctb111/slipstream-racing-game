class_name GxLandmarks
extends RefCounted
## One-off landmarks for the per-track dressing (kuestenstrasse, altstadt):
##   wind_turbine  80 m three-blade turbine: tapered steel tower, rounded
##                 nacelle, lofted twisted blades on a turning rotor (GxSpin),
##                 red aviation light. Far landmark: ~1.5k tris, 3 draw calls.
##   fishing_pier  Poly Haven CC0 "modular_wooden_pier" sections out to sea,
##                 lanterns, lifebuoy, barrels, crates, a few anglers.
##   maypole       Bavarian Maibaum: blue/white spiral pole, wreath, fir top,
##                 pennants. Stands on its own (no collision needed off-road).
##   beer_garden   Poly Haven picnic tables, barrels, festoon lights on posts
##                 (emissive bulbs, no real lights), drinkers standing about.
## Every model is merged per material into one MultiMesh per model.

const PIER := "res://assets/gimmicks/dress/modular_wooden_pier/modular_wooden_pier.gltf"
const TABLE := "res://assets/gimmicks/dress/wooden_picnic_table/wooden_picnic_table.gltf"
const LANTERN := "res://assets/gimmicks/dress/wooden_lantern_01/wooden_lantern_01.gltf"
const BUOY := "res://assets/gimmicks/dress/lifebuoy/lifebuoy.gltf"
const BARRELS := "res://assets/gimmicks/dress/wooden_barrels_01/wooden_barrels_01.gltf"
const BARREL := "res://assets/gimmicks/dress/wine_barrel_01/wine_barrel_01.gltf"
const CRATE := "res://assets/gimmicks/dress/wooden_crate_01/wooden_crate_01.gltf"

static var _models := {}


# ---------------------------------------------------------------- models

## Merged mesh (one surface per material) of a glTF scene; only nodes whose
## name contains `only` when given. Cached; null when the file is missing.
static func model(path: String, only := "") -> ArrayMesh:
	var key := path + "|" + only
	if _models.has(key):
		return _models[key]
	var out: ArrayMesh = null
	if ResourceLoader.exists(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		var groups := {}
		_collect(root, Transform3D.IDENTITY, groups, only)
		if not groups.is_empty():
			out = ArrayMesh.new()
			for m: Material in groups:
				out = (groups[m] as SurfaceTool).commit(out)
				out.surface_set_material(out.get_surface_count() - 1, m)
		root.free()
	_models[key] = out
	return out


static func _collect(n: Node, xf: Transform3D, groups: Dictionary, only: String) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (only == "" or String(n.name).contains(only)):
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				if m == null:
					m = StandardMaterial3D.new()
				if not groups.has(m):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[m] = st
				(groups[m] as SurfaceTool).append_from(mi.mesh, s, t)
	for ch in n.get_children():
		_collect(ch, t, groups, only)


## One MultiMeshInstance3D of a model at world transforms.
static func scatter(c: Node3D, path: String, xfs: Array, vis_end := 160.0, shadows := false, only := "") -> MultiMeshInstance3D:
	var mesh := model(path, only)
	if mesh == null or xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Lm_" + path.get_file().get_basename()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		mmi.visibility_range_end = vis_end + mm.get_aabb().size.length() * 0.5
		mmi.visibility_range_end_margin = vis_end * 0.1
	c.add_child(mmi)
	return mmi


static func _ground(c: Node3D, p: Vector3) -> Vector3:
	return Vector3(p.x, Gx.ground(c, p), p.z)


## Emissive bulbs (festoon lights, aviation lights): one unshaded MultiMesh.
static func _bulbs(c: Node3D, pts: Array, col: Color, radius: float, vis_end: float, energy := 3.0) -> void:
	if pts.is_empty():
		return
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	sm.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sm
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "LmBulbs"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = vis_end
	c.add_child(mmi)


static func _people(c: Node3D, name: String, xfs: Array[Transform3D], rng: RandomNumberGenerator) -> void:
	if xfs.is_empty():
		return
	var cols: Array[Color] = []
	var custom: Array[Color] = []
	var jackets := [Color(0.12, 0.14, 0.2), Color(0.5, 0.1, 0.08), Color(0.2, 0.25, 0.18), Color(0.75, 0.72, 0.62),
		Color(0.1, 0.1, 0.1), Color(0.25, 0.32, 0.45), Color(0.6, 0.45, 0.2)]
	for i in xfs.size():
		cols.append(jackets[rng.randi() % jackets.size()])
		custom.append(Color(rng.randf(), rng.randf_range(0.0, 0.25), 0.0, 0.0))
	c.add_child(PeopleKit.crowd(name, PeopleKit.Role.SPECTATOR, xfs, cols, custom))


# ---------------------------------------------------------------- wind turbine

## `base` on the ground; the rotor faces `wind` (horizontal direction the wind
## comes FROM). opts: hub (m, 78), blade (m, 38), speed (rad/s, 1.1).
static func wind_turbine(c: Node3D, base: Vector3, wind: Vector3, opts := {}) -> void:
	var hub: float = opts.get("hub", 78.0)
	var blade: float = opts.get("blade", 38.0)
	var f := Vector3(wind.x, 0, wind.z).normalized()
	var bz := -f # local -z points into the wind
	var bx := Vector3.UP.cross(bz).normalized()
	var basis := Basis(bx, Vector3.UP, bz)
	var g := GxGeo.new(Transform3D(basis, base))
	var white := Color(0.93, 0.93, 0.91)
	# Foundation plinth and tapered tower (sections with flange lines).
	g.col = Color(0.75, 0.74, 0.7)
	g.lathe("concrete", Vector3(0, -1.5, 0), PackedVector2Array([Vector2(6.5, 0.0), Vector2(6.5, 1.8), Vector2(3.2, 2.2), Vector2(0.0, 2.2)]), 20)
	g.col = white
	var prof := PackedVector2Array()
	var sections := 12
	for i in sections + 1:
		var t := float(i) / sections
		prof.append(Vector2(lerpf(2.25, 1.35, t), lerpf(0.0, hub - 1.6, t)))
	g.lathe("painted_metal", Vector3.ZERO, prof, 20)
	g.col = white * 0.92
	for y: float in [hub * 0.33, hub * 0.66]:
		var r := lerpf(2.25, 1.35, y / hub) + 0.03
		g.lathe("painted_metal", Vector3(0, y, 0), PackedVector2Array([Vector2(r, 0.0), Vector2(r, 0.18)]), 20)
	# Door at the foot, facing away from the wind.
	g.col = Color(0.55, 0.57, 0.58)
	g.box("steel", Vector3(0, 1.3, 2.2), Vector3(1.0, 2.2, 0.12), 0.03)
	# Nacelle: a rounded capsule along local z, yaw ring under it.
	g.col = white
	var ny := hub
	g.tube("painted_metal", [Vector3(0, ny, -1.6), Vector3(0, ny, -1.2), Vector3(0, ny + 0.1, 1.5), Vector3(0, ny + 0.15, 5.5),
		Vector3(0, ny + 0.15, 8.2), Vector3(0, ny + 0.1, 9.0)], 1.0, 14, true, [1.25, 1.75, 1.95, 1.95, 1.7, 1.0])
	g.lathe("painted_metal", Vector3(0, hub - 1.8, 0.4), PackedVector2Array([Vector2(1.45, 0.0), Vector2(1.6, 0.6), Vector2(1.2, 0.9)]), 16)
	g.col = Color(0.3, 0.32, 0.33)
	g.box("steel", Vector3(0, ny + 2.2, 6.5), Vector3(0.6, 0.5, 1.2), 0.05) # cooler
	g.bar("steel", Vector3(0, ny + 2.0, 7.6), Vector3(0, ny + 3.3, 7.6), 0.04, 4) # anemometer mast
	g.commit(c, "LmTurbine", 2600.0, true)
	# Rotor: spinner + three twisted, tapering blades, turning.
	var holder := GxSpin.new()
	holder.speed = float(opts.get("speed", 1.1))
	holder.name = "LmRotor"
	holder.transform = Transform3D(basis, base + basis * Vector3(0, ny + 0.1, -2.0))
	c.add_child(holder)
	var r := GxGeo.new()
	r.col = white
	r.tube("painted_metal", [Vector3(0, 0, 0.6), Vector3(0, 0, 0.0), Vector3(0, 0, -1.2), Vector3(0, 0, -2.4), Vector3(0, 0, -3.2)],
		1.0, 14, true, [1.3, 1.45, 1.35, 0.9, 0.08])
	for k in 3:
		_blade(r, TAU * k / 3.0, blade)
	r.commit(holder, "LmBlades", 2600.0, false) # moving shadow casters redraw the shadow map every frame
	# Red aviation light on the nacelle roof.
	_bulbs(c, [base + basis * Vector3(0, ny + 2.25, 8.4)], Color(1.0, 0.08, 0.04), 0.22, 3000.0, 6.0)
	Gx.reserve(c, base, 12.0)


## One lofted blade along local direction (cos a, sin a, 0) in the rotor plane.
static func _blade(g: GxGeo, a: float, length: float) -> void:
	var rad := Vector3(cos(a), sin(a), 0)
	var chd := Vector3(-sin(a), cos(a), 0) # chord direction (in the rotor plane)
	var ax := Vector3(0, 0, -1)
	var stations := [[1.0, 1.0, 0.95], [3.0, 2.6, 0.75], [7.0, 3.3, 0.45], [12.0, 2.9, 0.3], [20.0, 2.2, 0.2],
		[28.0, 1.5, 0.14], [34.0, 1.0, 0.1], [length, 0.35, 0.05]]
	var segs := 10
	var rings: Array = []
	for st: Array in stations:
		var rr: float = st[0] * (length / 38.0) if st[0] < length else length
		var chord: float = st[1] * (length / 38.0)
		var thick: float = chord * st[2]
		var twist := deg_to_rad(lerpf(14.0, 1.0, clampf(rr / length, 0.0, 1.0)))
		var cdir := (chd * cos(twist) + ax * sin(twist)).normalized()
		var tdir := (ax * cos(twist) - chd * sin(twist)).normalized()
		var ring := []
		for s in segs:
			var t := TAU * s / segs
			# Airfoil-ish: rounded leading edge at +chord, sharp trailing at -chord.
			var ch := cos(t)
			var x := (ch * 0.5 + 0.12) * chord if ch > 0.0 else ch * 0.62 * chord + 0.12 * chord
			var y := sin(t) * thick * 0.5 * (1.0 if ch > -0.6 else 0.6)
			var p: Vector3 = rad * rr + cdir * x + tdir * y
			var n := (cdir * cos(t) / maxf(chord, 0.1) + tdir * sin(t) / maxf(thick, 0.02)).normalized()
			ring.append([p, n])
		rings.append(ring)
	for i in rings.size() - 1:
		for s in segs:
			var a0: Array = rings[i][s]
			var a1: Array = rings[i][(s + 1) % segs]
			var b0: Array = rings[i + 1][s]
			var b1: Array = rings[i + 1][(s + 1) % segs]
			g.tri_n("painted_metal", a0[0], b1[0], b0[0], a0[1], b1[1], b0[1])
			g.tri_n("painted_metal", a0[0], a1[0], b1[0], a0[1], a1[1], b1[1])


# ---------------------------------------------------------------- fishing pier

## Timber pier from `start` (on the beach) out along `dir` for `length` m,
## deck at `deck_y`. opts: rng (RandomNumberGenerator), anglers (int, 4).
static func fishing_pier(c: Node3D, start: Vector3, dir: Vector3, length: float, deck_y: float, opts := {}) -> void:
	var sect := model(PIER, "section_01")
	if sect == null:
		return
	var rng: RandomNumberGenerator = opts.get("rng", RandomNumberGenerator.new())
	var aabb := sect.get_aabb()
	var d := Vector3(dir.x, 0, dir.z).normalized()
	var side := Vector3.UP.cross(d).normalized() # local x
	var basis := Basis(side, Vector3.UP, d) # module z (its length axis) runs out to sea
	var off := Vector3(-aabb.get_center().x, -aabb.end.y, -aabb.position.z)
	var step := 2.9
	var xfs: Array = []
	var n := int(length / step)
	for i in n:
		var o := Vector3(start.x, deck_y, start.z) + d * (i * step)
		xfs.append(Transform3D(basis, o + basis * off))
	scatter(c, PIER, xfs, 420.0, false, "section_01")
	# Piles down into the sand / seabed (the modules' own legs are short).
	var g := GxGeo.new()
	g.col = Color(0.55, 0.5, 0.45)
	for i in n + 1:
		var o := Vector3(start.x, deck_y, start.z) + d * (i * step)
		for s: float in [-1.0, 1.0]:
			var p := o + side * s * (aabb.size.x * 0.5 - 0.1)
			var floor_y := Gx.ground(c, p)
			if floor_y < deck_y - 1.0:
				g.bar("wood", Vector3(p.x, deck_y - 1.6, p.z), Vector3(p.x, floor_y - 0.5, p.z), 0.14, 7)
	g.commit(c, "LmPierPiles", 300.0, false)
	var end := Vector3(start.x, deck_y, start.z) + d * (n * step - 1.5)
	var mid := Vector3(start.x, deck_y, start.z) + d * (n * step * 0.5)
	var w := aabb.size.x * 0.5 - 0.35
	# Lanterns on posts down both sides, lifebuoy, barrels and crates at the end.
	var lan: Array = []
	var posts := GxGeo.new()
	posts.col = Color(0.45, 0.38, 0.3)
	for i in range(1, n, 4):
		for s: float in [-1.0, 1.0]:
			var p := Vector3(start.x, deck_y, start.z) + d * (i * step) + side * s * w
			posts.box("wood", p + Vector3.UP * 1.1, Vector3(0.14, 2.2, 0.14), 0.02, basis)
			posts.box("wood", p + Vector3.UP * 2.15 - side * s * 0.25, Vector3(0.6, 0.08, 0.08), 0.01, basis)
			lan.append(Transform3D(basis, p + Vector3.UP * 1.62 - side * s * 0.45))
	posts.commit(c, "LmPierPosts", 260.0, false)
	scatter(c, LANTERN, lan, 200.0)
	scatter(c, BUOY, [Transform3D(Basis(side, d, -Vector3.UP).orthonormalized().scaled(Vector3.ONE * 0.9), end - side * w + Vector3.UP * 1.2 + d * 0.0)], 160.0)
	scatter(c, BARRELS, [Transform3D(basis.rotated(Vector3.UP, 0.4), end + side * (w - 0.9) - d * 3.0)], 200.0, true)
	scatter(c, CRATE, [Transform3D(basis.rotated(Vector3.UP, 0.2), end - side * (w - 0.6) - d * 4.0),
		Transform3D(basis.rotated(Vector3.UP, -0.3), end - side * (w - 0.6) - d * 4.0 + Vector3.UP * 0.41)], 160.0)
	# Anglers at the rail looking out to sea.
	var ppl: Array[Transform3D] = []
	for i in int(opts.get("anglers", 4)):
		var s := 1.0 if i % 2 == 0 else -1.0
		var p := mid + d * rng.randf_range(-length * 0.3, length * 0.45) + side * s * (w - 0.3)
		ppl.append(Transform3D(Basis(Vector3.UP, atan2(side.x * s, side.z * s) + PI + rng.randf_range(-0.4, 0.4)), p))
	_people(c, "LmAnglers", ppl, rng)
	Gx.reserve(c, mid, length * 0.5 + 4.0)


# ---------------------------------------------------------------- maypole

## Bavarian Maibaum at `base` (on the ground). opts: height (m, 26).
static func maypole(c: Node3D, base: Vector3, facing: Vector3, opts := {}) -> void:
	var h: float = opts.get("height", 26.0)
	var f := Vector3(facing.x, 0, facing.z).normalized()
	var basis := Basis(Vector3.UP.cross(f).normalized(), Vector3.UP, f)
	var g := GxGeo.new(Transform3D(basis, base))
	var blue := Color(0.12, 0.3, 0.62)
	var white := Color(0.95, 0.95, 0.93)
	# Spiral stripes: rings of 16 facets, colour by (facet + ring) band.
	var segs := 16
	var ring_h := 0.28
	var rings := int(h / ring_h)
	for i in rings:
		var y0 := i * ring_h
		var y1 := y0 + ring_h
		var r0 := lerpf(0.26, 0.1, y0 / h)
		var r1 := lerpf(0.26, 0.1, y1 / h)
		for s in segs:
			var band := int(floor((s + i * 0.75) / 4.0)) % 2
			g.col = blue if band == 0 else white
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			g.tri_n("painted_wood", d0 * r0 + Vector3.UP * y0, d1 * r1 + Vector3.UP * y1, d0 * r1 + Vector3.UP * y1, d0, d1, d0)
			g.tri_n("painted_wood", d0 * r0 + Vector3.UP * y0, d1 * r0 + Vector3.UP * y0, d1 * r1 + Vector3.UP * y1, d0, d1, d1)
	# Stone socket.
	g.col = Color(0.8, 0.77, 0.72)
	g.lathe("stone", Vector3(0, -0.3, 0), PackedVector2Array([Vector2(1.1, 0.0), Vector2(1.1, 0.7), Vector2(0.95, 0.85), Vector2(0.3, 0.85)]), 12)
	# Evergreen wreath with ribbons, and the fir crown on top.
	g.col = Color(0.16, 0.26, 0.14)
	var wy := h * 0.7
	var wr := 2.2
	var pts: Array = []
	for k in 25:
		var t := TAU * k / 24.0
		pts.append(Vector3(cos(t) * wr, wy + 0.0, sin(t) * wr))
	g.tube("canvas", pts, 0.28, 7, false)
	for k in 4:
		var t := TAU * k / 4.0
		g.bar("canvas", Vector3(cos(t) * 0.12, wy + 2.4, sin(t) * 0.12), Vector3(cos(t) * wr, wy, sin(t) * wr), 0.05, 4)
		for q in 2:
			g.col = blue if q == 0 else white
			var p := Vector3(cos(t + 0.1 * q) * wr, wy, sin(t + 0.1 * q) * wr)
			g.box("canvas", p - Vector3.UP * 1.0, Vector3(0.12, 2.0, 0.02), 0.0, Basis(Vector3.UP, -t))
		g.col = Color(0.16, 0.26, 0.14)
	g.col = Color(0.14, 0.24, 0.13)
	g.lathe("canvas", Vector3(0, h - 0.4, 0), PackedVector2Array([Vector2(0.15, 0.0), Vector2(1.1, 0.6), Vector2(0.75, 1.4),
		Vector2(0.9, 1.6), Vector2(0.45, 2.6), Vector2(0.55, 2.8), Vector2(0.0, 4.0)]), 9)
	# Pennants on a cross arm under the crown.
	g.col = Color(0.4, 0.3, 0.2)
	g.beam("painted_wood", Vector3(-1.6, h - 1.4, 0), Vector3(1.6, h - 1.4, 0), 0.1)
	for s: float in [-1.0, 1.0]:
		g.col = blue
		g.tri_f("canvas", Vector3(s * 1.5, h - 1.45, 0), Vector3(s * 1.5, h - 3.6, 0), Vector3(s * 1.3, h - 1.45, 0), Vector3(0, 0, -1))
		g.col = white
		g.tri_f("canvas", Vector3(s * 1.3, h - 1.45, 0), Vector3(s * 1.5, h - 3.6, 0), Vector3(s * 1.1, h - 1.45, 0), Vector3(0, 0, -1))
	g.collide(Vector3(0, 1.0, 0), Vector3(1.0, 2.0, 1.0))
	g.commit(c, "LmMaypole", 900.0, true)
	Gx.reserve(c, base, 3.0)


# ---------------------------------------------------------------- beer garden

## Beer garden in the frame `xf` (x along, +z away from the road), filling
## x in [-w/2, w/2], z in [0, d]. opts: width (16), depth (12), rng, people (14).
static func beer_garden(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var w: float = opts.get("width", 16.0)
	var d: float = opts.get("depth", 12.0)
	var rng: RandomNumberGenerator = opts.get("rng", RandomNumberGenerator.new())
	var tables: Array = []
	var barrels: Array = []
	var ppl: Array[Transform3D] = []
	var cols := maxi(int(w / 4.2), 1)
	var rows := maxi(int((d - 2.0) / 3.6), 1)
	for i in cols:
		for j in rows:
			var lp := Vector3((i + 0.5) / cols * w - w * 0.5, 0, 1.8 + (j + 0.5) / rows * (d - 2.5))
			var p := xf * lp
			p.y = Gx.ground(c, p)
			var yaw := rng.randf_range(-0.08, 0.08)
			tables.append(Transform3D(xf.basis.rotated(Vector3.UP, yaw), p))
			for s: float in [-1.0, 1.0]:
				if rng.randf() < 0.55:
					var q := xf * (lp + Vector3(rng.randf_range(-0.7, 0.7), 0, s * 1.15))
					q.y = Gx.ground(c, q)
					ppl.append(Transform3D(xf.basis.rotated(Vector3.UP, (0.0 if s > 0.0 else PI) + rng.randf_range(-0.5, 0.5)), q))
	scatter(c, TABLE, tables, 180.0, true)
	for k in 3:
		var p := xf * Vector3(w * 0.5 + 0.8, 0, 1.5 + k * 1.0)
		p.y = Gx.ground(c, p)
		barrels.append(Transform3D(xf.basis.rotated(Vector3.UP, rng.randf() * TAU), p))
	scatter(c, BARREL, barrels, 150.0)
	# Festoon lights: posts round the edge, bulbs on sagging wires between them.
	var g := GxGeo.new(xf)
	g.col = Color(0.4, 0.33, 0.25)
	var corners := [Vector3(-w * 0.5, 0, 0.6), Vector3(w * 0.5, 0, 0.6), Vector3(w * 0.5, 0, d), Vector3(-w * 0.5, 0, d)]
	var post_h := 3.6
	var tops: Array = []
	for p: Vector3 in corners:
		var wp := xf * p
		var gy := Gx.ground(c, wp) - xf.origin.y
		g.box("wood", Vector3(p.x, gy + post_h * 0.5 - 0.3, p.z), Vector3(0.16, post_h + 0.6, 0.16), 0.02)
		tops.append(Vector3(p.x, gy + post_h, p.z))
	var bulbs: Array = []
	var pairs := [[0, 1], [1, 2], [2, 3], [3, 0], [0, 2], [1, 3]]
	for pr: Array in pairs:
		var a: Vector3 = tops[pr[0]]
		var b: Vector3 = tops[pr[1]]
		var pts: Array = []
		var segs := 10
		for k in segs + 1:
			var t := float(k) / segs
			pts.append(a.lerp(b, t) - Vector3.UP * 4.0 * t * (1.0 - t) * 0.6)
		g.col = Color(0.05, 0.05, 0.05)
		g.tube("steel", pts, 0.012, 3, false)
		var span := a.distance_to(b)
		var nb := int(span / 0.9)
		for k in nb:
			var t := (k + 0.5) / nb
			var p := a.lerp(b, t) - Vector3.UP * (4.0 * t * (1.0 - t) * 0.6 + 0.08)
			bulbs.append(xf * p)
	g.commit(c, "LmBeerGarden", 220.0, false)
	_bulbs(c, bulbs, Color(1.0, 0.78, 0.45), 0.06, 220.0, 2.5)
	_people(c, "LmBeerGardenPeople", ppl.slice(0, int(opts.get("people", 14))), rng)
	Gx.reserve(c, xf * Vector3(0, 0, d * 0.5), maxf(w, d) * 0.6)
