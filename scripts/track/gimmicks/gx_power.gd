class_name GxPower
extends RefCounted
## Power lines across the landscape, with sagging cables.
##   GxPower.place(c, Gx.road_frame(c, 700.0), {kind = "pylon"})        # HV line crossing OVER the track
##   GxPower.place(c, Gx.road_frame(c, 300.0), {kind = "poles", route = "along", side = 1.0})
## opts:
##   kind     "pylon": galvanised steel lattice towers (~35 m), insulator strings,
##            6 conductors + earth wire; lowest wire >= 12 m above the road
##            "poles": wooden utility poles (Poly Haven modular_electricity_poles,
##            CC0) with crossarms, insulators, transformers, 3-4 sagging wires
##   route    "cross" (default): the line runs across the track at xf (along local z)
##            "along": the line follows the track at `lateral` m beyond the edge on `side`
##   reach    metres the line runs each way (default 420 pylon / 160 poles)
##   span     metres between towers (default 150 pylon / 38 poles)
## Towers keep clear of every part of the road; cables over it stay high.

const POLES := "res://assets/gimmicks/electricity_poles/modular_electricity_poles.gltf"
const GALV := Color(0.72, 0.74, 0.74)
const WIRE := Color(0.32, 0.33, 0.34)

static var _pole_parts := {} ## preset -> [[Mesh, Transform3D]]


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var pylon: bool = opts.get("kind", "pylon") == "pylon"
	var reach: float = float(opts.get("reach", 420.0 if pylon else 160.0))
	var span: float = float(opts.get("span", 150.0 if pylon else 38.0))
	var sites: Array = [] # [position, line direction]
	if opts.get("route", "cross") == "along":
		var cv := Gx.curve(c)
		var along0 := fposmod(cv.get_closest_offset(xf.origin) - float(c.get("start_offset")), cv.get_baked_length())
		var side: float = float(opts.get("side", 1.0))
		var lat: float = float(opts.get("lateral", 22.0 if pylon else 9.0))
		var k := -reach
		while k <= reach:
			var f := Gx.frame(c, along0 + k, side, lat)
			sites.append([f.origin, Gx.tangent(c, along0 + k)])
			k += span
	else:
		var dir := xf.basis.z.normalized()
		var n := int(reach / span)
		for k in range(-n, n):
			var p := xf.origin + dir * ((k + 0.5) * span)
			sites.append([p, dir])
	# drop towers that would stand on or near any road; ground them
	var keep: Array = []
	for s: Array in sites:
		var p: Vector3 = s[0]
		if not Gx.clear_of_road(c, p, 8.0 if pylon else 3.0):
			continue
		p.y = Gx.ground(c, p)
		keep.append([p, s[1]])
	if keep.size() < 2:
		return
	var root := Node3D.new()
	root.name = "GxPower"
	c.add_child(root)
	if pylon:
		_pylons(c, root, keep, xf)
	else:
		_poles(c, root, keep)
	GxGeo.ab(root, xf * Vector3(-40.0, 2.0, 0.0), xf * Vector3(0, 15.0, 0))


# ---------------------------------------------------------------- lattice pylons

static func _pylons(c: Node3D, root: Node3D, sites: Array, xf: Transform3D) -> void:
	# height so the lowest sagging wire clears the road by 12 m where it crosses
	var H := 34.0
	var road_y := xf.origin.y
	var g := GxGeo.new()
	var wires := GxGeo.new()
	var attach: Array = [] # per tower: list of world attachment points
	for s: Array in sites:
		var p: Vector3 = s[0]
		var d: Vector3 = s[1]
		var h := maxf(H, road_y + 12.0 + 8.0 + 4.5 - p.y) # arm at 0.62 h, insulator 3 m, sag ~5 m
		var b := Basis(d.cross(Vector3.UP).normalized(), Vector3.UP, d) # x across the line, z along it
		attach.append(_pylon(g, Transform3D(b, p), h))
		g.xf = Transform3D.IDENTITY
		g.collide(p + Vector3(0, 2.0, 0), Vector3(6.0, 4.0, 6.0))
		Gx.reserve(c, p, 12.0)
	# conductors between consecutive towers
	wires.col = WIRE
	for i in sites.size() - 1:
		var a: Array = attach[i]
		var bb: Array = attach[i + 1]
		var span := (sites[i][0] as Vector3).distance_to(sites[i + 1][0])
		for w in a.size():
			_catenary(wires, a[w], bb[w], span * (0.03 if w < a.size() - 1 else 0.025), 0.035)
	var r1 := g.commit(root, "towers", 0.0, true)
	r1.name = "towers"
	wires.commit(root, "wires", 1400.0, false)


## One lattice tower in frame m (x across the line). Returns its wire points (world).
static func _pylon(g: GxGeo, m: Transform3D, h: float) -> Array:
	g.xf = m
	g.col = GALV
	var base := 3.6
	var waist := 1.1
	var yw := h * 0.6
	var leg := func(sx: float, sz: float, y: float) -> Vector3:
		var w := lerpf(base, waist, clampf(y / yw, 0.0, 1.0)) if y <= yw else waist
		return Vector3(sx * w, y, sz * w)
	# legs + horizontal rings + X bracing per panel
	var levels: Array[float] = [0.0]
	var y := 0.0
	var pan := 4.2
	while y < h - 0.5:
		y = minf(y + pan, h)
		pan *= 0.9
		levels.append(y)
	var corners := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
	for i in levels.size() - 1:
		var y0: float = levels[i]
		var y1: float = levels[i + 1]
		for k in 4:
			var ca: Array = corners[k]
			var cb: Array = corners[(k + 1) % 4]
			var a0: Vector3 = leg.call(ca[0], ca[1], y0)
			var a1: Vector3 = leg.call(ca[0], ca[1], y1)
			var b0: Vector3 = leg.call(cb[0], cb[1], y0)
			var b1: Vector3 = leg.call(cb[0], cb[1], y1)
			g.beam("steel", a0, a1, 0.2)
			g.beam("steel", a1, b1, 0.09)
			g.beam("steel", a0, b1, 0.07)
			g.beam("steel", b0, a1, 0.07)
	# concrete footings
	g.col = Color(0.75, 0.74, 0.7)
	for k in 4:
		var ca: Array = corners[k]
		g.box("concrete", Vector3(ca[0] * base, 0.1, ca[1] * base), Vector3(1.2, 1.0, 1.2), 0.08)
	g.col = GALV
	# cross arms: lower (wide) and upper (narrower), each a triangular truss
	var pts: Array = []
	for arm: Array in [[h * 0.62, 9.5], [h * 0.8, 7.0]]:
		var ya: float = arm[0]
		var reach: float = arm[1]
		for s: float in [-1.0, 1.0]:
			var tip := Vector3(s * reach, ya, 0)
			for z: float in [-waist, waist]:
				g.beam("steel", Vector3(s * waist, ya - 0.0, z), tip, 0.1)
				g.beam("steel", Vector3(s * waist, ya + 1.8, z), tip, 0.08)
			for k in 4:
				var t := (k + 1) / 5.0
				var q := Vector3(s * lerpf(waist, reach, t), ya, 0)
				g.beam("steel", q + Vector3(0, 0, -waist * (1.0 - t)), q + Vector3(0, 1.8 * (1.0 - t), waist * (1.0 - t)), 0.05)
			# insulator strings at the tip and halfway
			for f: float in [1.0, 0.55]:
				var at := Vector3(s * lerpf(waist, reach, f), ya, 0)
				_insulator(g, at, 2.6)
				pts.append(m * (at - Vector3(0, 2.75, 0)))
	# earth-wire peak
	g.beam("steel", Vector3(-waist, h, -waist), Vector3(0, h + 3.0, 0), 0.08)
	g.beam("steel", Vector3(waist, h, waist), Vector3(0, h + 3.0, 0), 0.08)
	g.beam("steel", Vector3(-waist, h, waist), Vector3(0, h + 3.0, 0), 0.08)
	g.beam("steel", Vector3(waist, h, -waist), Vector3(0, h + 3.0, 0), 0.08)
	pts.append(m * Vector3(0, h + 3.0, 0))
	# danger plate
	g.col = Color(0.95, 0.85, 0.1)
	g.box("props", Vector3(0, 3.0, -base * 0.85 - 0.05), Vector3(0.5, 0.6, 0.02))
	g.col = GALV
	return pts


static func _insulator(g: GxGeo, at: Vector3, length: float) -> void:
	var save := g.col
	g.col = Color(0.55, 0.6, 0.55)
	g.bar("steel", at, at - Vector3(0, length + 0.15, 0), 0.025, 4)
	var n := int(length / 0.2)
	g.col = Color(0.36, 0.48, 0.42) # green glass caps
	for i in n:
		g.lathe("glass", at - Vector3(0, 0.2 + i * 0.2, 0), PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.14, 0.03), Vector2(0.05, 0.1), Vector2(0.0, 0.11)]), 8)
	g.col = save


## Sagging cable from a to b (world), parabola sag `sag` metres at midspan.
static func _catenary(g: GxGeo, a: Vector3, b: Vector3, sag: float, radius: float) -> void:
	var n := 16
	var pts := []
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0))
	g.tube("steel", pts, radius, 4, false)


# ---------------------------------------------------------------- wooden poles

static func _parts(preset: String) -> Array:
	if _pole_parts.has(preset):
		return _pole_parts[preset]
	var out: Array = []
	if ResourceLoader.exists(POLES):
		var scene: Node = (load(POLES) as PackedScene).instantiate()
		var base := Vector3.ZERO
		var pole := scene.find_child(preset + "_pole", true, false) as Node3D
		if pole:
			base = pole.transform.origin
		for n in scene.find_children(preset + "_*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var t := mi.transform
			t.origin -= base
			out.append([mi.mesh, t])
		scene.free()
	_pole_parts[preset] = out
	return out


static func _poles(c: Node3D, root: Node3D, sites: Array) -> void:
	var scale := 1.45
	var presets := ["preset_02", "preset_01", "preset_02", "preset_03"]
	var by_mesh := {} # Mesh -> Array[Transform3D]
	var tops: Array = []
	var rng := Gx.rng(c, "poles" + str(sites[0][0]))
	for i in sites.size():
		var p: Vector3 = sites[i][0]
		var d: Vector3 = sites[i][1]
		var across := d.cross(Vector3.UP).normalized()
		var lean := Basis(d, rng.randf_range(-0.02, 0.02)) * Basis(across, rng.randf_range(-0.015, 0.015))
		var b := lean * Basis(across, Vector3.UP, -d) * Basis.from_scale(Vector3.ONE * scale)
		var m := Transform3D(b, p - Vector3(0, 0.25, 0))
		var preset: String = presets[i % presets.size()] if i % 5 != 2 else "preset_01"
		for part: Array in _parts(preset):
			var mesh: Mesh = part[0]
			if not by_mesh.has(mesh):
				by_mesh[mesh] = []
			by_mesh[mesh].append(m * (part[1] as Transform3D))
		tops.append([m * Vector3(-0.55, 5.86, 0.0), m * Vector3(0.55, 5.86, 0.0), m * Vector3(0.0, 5.93, 0.0), m * Vector3(0.3, 4.76, 0.0)])
		Gx.reserve(c, p, 3.0)
	for mesh: Mesh in by_mesh:
		var xfs: Array = by_mesh[mesh]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for k in xfs.size():
			mm.set_instance_transform(k, xfs[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if mesh.get_aabb().size.y > 3.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 700.0
		root.add_child(mmi)
	var wires := GxGeo.new()
	wires.col = Color(0.12, 0.12, 0.12)
	for i in tops.size() - 1:
		var span := (sites[i][0] as Vector3).distance_to(sites[i + 1][0])
		if span > 90.0:
			continue
		for w in 4:
			_catenary(wires, tops[i][w], tops[i + 1][w], 0.25 + span * 0.012, 0.012)
	wires.commit(root, "wires", 450.0, false)
	var col := StaticBody3D.new()
	col.name = "collision"
	for s: Array in sites:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.16
		sh.height = 9.0
		cs.shape = sh
		cs.position = (s[0] as Vector3) + Vector3(0, 4.5, 0)
		col.add_child(cs)
	root.add_child(col)


## gx_test framing: the line crossing the road, seen from the road.
static func views(_c: Node3D, xf: Transform3D, _opts: Dictionary) -> Array:
	var o := xf.origin
	return [["line", o - xf.basis.x * 90.0 + Vector3.UP * 2.0, o + Vector3.UP * 14.0 + xf.basis.z * 40.0],
		["tower", o - xf.basis.x * 40.0 - xf.basis.z * 20.0 + Vector3.UP * 3.0, o + xf.basis.z * 75.0 + Vector3.UP * 18.0]]
