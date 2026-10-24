class_name GxGeo
extends RefCounted
## Merged-mesh builder for Gx pieces: bevelled boxes, profile extrusions, tube
## sweeps, lathes and printed sign quads, all merged per material into one
## MeshInstance3D each (via Gx.add_mesh) plus one StaticBody3D of box colliders.
##
##   var g := GxGeo.new(xf)                       # local frame (x along track, z across, y up)
##   g.box("concrete", Vector3(0, 6, 0), Vector3(20, 1, 8), 0.05)
##   g.extrude("steel", profile, -10.0, 10.0)      # profile: PackedVector2Array of (z, y), CCW
##   g.tube("steel", [p0, p1, p2], 0.04)           # railing / pipe through local points
##   g.sign(Vector3(0, 7, -4.01), Vector3(0, 0, -1), 8.0, 1.0, "b_helios")
##   g.collide(Vector3(0, 3, 9), Vector3(2, 6, 2))
##   g.commit(c, "GxOverpass", 700.0)
##
## Materials: any Mats type ("concrete", "stone", "brick", "steel",
## "painted_metal", "rusty_metal", "plaster", ...), "props" (paint colour +
## printed atlas faces, assets/trackside/trackside_signs.png, shaders/pbr_props)
## or "glass". The vertex colour multiplies the material (use it for grime/AO).

const SIGNS := "res://assets/trackside/trackside_signs.png"

var xf: Transform3D
var _b := {} ## mat -> [verts, norms, cols, uvs, uv2s]
var _boxes: Array = [] ## [Transform3D, size]
var _shadow_mats := {} ## mats whose mesh casts shadows
var col := Color.WHITE ## current vertex colour
var gloss := 0.0 ## current gloss for "props"

static var _props_mat: Material
static var stats := {} ## node_name -> [draw calls, triangles] (debug, gx_test prints it)
static var _paint_mat: Material
static var _grime_tex: NoiseTexture2D


func _init(p_xf := Transform3D.IDENTITY) -> void:
	xf = p_xf
	if xf.basis.determinant() < 0.0: # mirrored frame (Gx.frame on the LEFT side): make it right-handed
		xf.basis.x = -xf.basis.x # keeps -z facing the road; x (along) reversed


func _arr(mat: String) -> Array:
	if not _b.has(mat):
		_b[mat] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]
	return _b[mat]


## Raw triangle in LOCAL space with a flat normal.
func tri(mat: String, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	tri_n(mat, a, b, c, n, n, n)


func tri_n(mat: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca := Color(-1, 0, 0), cb := Color(-1, 0, 0), cc := Color(-1, 0, 0)) -> void:
	var r := _arr(mat)
	var bs := xf.basis
	r[0].append(xf * a); r[0].append(xf * c); r[0].append(xf * b) # Godot front faces are clockwise
	r[1].append((bs * na).normalized()); r[1].append((bs * nc).normalized()); r[1].append((bs * nb).normalized())
	r[2].append(col if ca.r < 0.0 else ca); r[2].append(col if cc.r < 0.0 else cc); r[2].append(col if cb.r < 0.0 else cb)
	for k in 3:
		r[3].append(Vector2.ZERO)
		r[4].append(Vector2(0.0, gloss))


## Quad a-b-c-d (counter-clockwise seen from the front), flat.
func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	tri(mat, a, b, c)
	tri(mat, a, c, d)


## Quad a-b-c-d forced to face local direction `n` (winding fixed up automatically).
func quad_n(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0 or (c - a).cross(d - a).dot(n) < 0.0:
		quad(mat, d, c, b, a)
	else:
		quad(mat, a, b, c, d)


## Triangle forced to face local direction `n`.
func tri_f(mat: String, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0:
		tri(mat, a, c, b)
	else:
		tri(mat, a, b, c)


## Box centred at local `c`, optional chamfer `bevel` on all 12 edges, rotated by `rot`.
func box(mat: String, c: Vector3, size: Vector3, bevel := 0.0, rot := Basis()) -> void:
	var h := size * 0.5
	var e := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var m := Transform3D(rot, c)
	if e <= 0.0:
		var p := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
			Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
		for i in 8:
			p[i] = m * (p[i] * h)
		quad(mat, p[4], p[5], p[6], p[7]) # +z
		quad(mat, p[1], p[0], p[3], p[2]) # -z
		quad(mat, p[5], p[1], p[2], p[6]) # +x
		quad(mat, p[0], p[4], p[7], p[3]) # -x
		quad(mat, p[3], p[7], p[6], p[2]) # +y
		quad(mat, p[0], p[1], p[5], p[4]) # -y
		return
	# chamfered: extrude an octagon-ish section along x, then cap with chamfered ends
	var prof := chamfer_rect(h.z, h.y, e)
	extrude_xf(mat, prof, -h.x, h.x, m, e)


## Rectangle half-size (hz, hy) with chamfer e, as a (z, y) profile, CCW looking down -x.
static func chamfer_rect(hz: float, hy: float, e: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-hz + e, -hy), Vector2(hz - e, -hy), Vector2(hz, -hy + e), Vector2(hz, hy - e),
		Vector2(hz - e, hy), Vector2(-hz + e, hy), Vector2(-hz, hy - e), Vector2(-hz, -hy + e)])


## Extrude a closed (z, y) profile along local x from x0 to x1 (caps included).
func extrude(mat: String, prof: PackedVector2Array, x0: float, x1: float, caps := true) -> void:
	extrude_xf(mat, prof, x0, x1, Transform3D.IDENTITY, 0.0, caps)


## Same, in sub-frame `m`; `end_bevel` shrinks the caps (chamfered ends).
func extrude_xf(mat: String, prof: PackedVector2Array, x0: float, x1: float, m: Transform3D, end_bevel := 0.0, caps := true) -> void:
	var n := prof.size()
	var cen := Vector2.ZERO
	for p in prof:
		cen += p
	cen /= n
	var xa := x0 + end_bevel
	var xb := x1 - end_bevel
	for i in n:
		var p := prof[i]
		var q := prof[(i + 1) % n]
		quad(mat, m * Vector3(xa, p.y, p.x), m * Vector3(xb, p.y, p.x), m * Vector3(xb, q.y, q.x), m * Vector3(xa, q.y, q.x))
	if not caps:
		return
	var shrink := func(p: Vector2) -> Vector2:
		if end_bevel <= 0.0:
			return p
		return p + (cen - p).normalized() * end_bevel
	for i in n:
		var p := prof[i]
		var q := prof[(i + 1) % n]
		if end_bevel > 0.0:
			var ps: Vector2 = shrink.call(p)
			var qs: Vector2 = shrink.call(q)
			quad(mat, m * Vector3(xb, p.y, p.x), m * Vector3(x1, ps.y, ps.x), m * Vector3(x1, qs.y, qs.x), m * Vector3(xb, q.y, q.x))
			quad(mat, m * Vector3(xa, q.y, q.x), m * Vector3(x0, qs.y, qs.x), m * Vector3(x0, ps.y, ps.x), m * Vector3(xa, p.y, p.x))
	# fan caps (profiles here are convex or star-shaped around the centroid)
	for i in n:
		var p: Vector2 = shrink.call(prof[i])
		var q: Vector2 = shrink.call(prof[(i + 1) % n])
		tri(mat, m * Vector3(x1, cen.y, cen.x), m * Vector3(x1, q.y, q.x), m * Vector3(x1, p.y, p.x))
		tri(mat, m * Vector3(x0, cen.y, cen.x), m * Vector3(x0, p.y, p.x), m * Vector3(x0, q.y, q.x))


## Extrude a NON-convex profile given as convex parts (e.g. an I-beam = 3 rects).
func extrude_parts(mat: String, parts: Array, x0: float, x1: float, m := Transform3D.IDENTITY) -> void:
	for p: PackedVector2Array in parts:
		extrude_xf(mat, p, x0, x1, m)


## Smooth round tube through local points (open ends capped flat).
func tube(mat: String, pts: Array, radius: float, segs := 8, caps := true, radii := []) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array = []
	var prev_side := Vector3.ZERO
	for i in n:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = (pts[i + 1] - pts[i - 1])
		t = t.normalized()
		var side := prev_side
		if side == Vector3.ZERO or absf(side.dot(t)) > 0.9:
			side = Vector3.UP.cross(t)
			if side.length() < 0.1:
				side = Vector3.RIGHT.cross(t)
		side = (side - t * side.dot(t)).normalized()
		prev_side = side
		var up := t.cross(side).normalized()
		var r: float = radii[i] if i < radii.size() else radius
		var ring := []
		for s in segs:
			var a := TAU * s / segs
			var nrm := side * cos(a) + up * sin(a)
			ring.append([pts[i] + nrm * r, nrm])
		rings.append(ring)
	for i in n - 1:
		for s in segs:
			var a0: Array = rings[i][s]
			var a1: Array = rings[i][(s + 1) % segs]
			var b0: Array = rings[i + 1][s]
			var b1: Array = rings[i + 1][(s + 1) % segs]
			tri_n(mat, a0[0], b1[0], b0[0], a0[1], b1[1], b0[1])
			tri_n(mat, a0[0], a1[0], b1[0], a0[1], a1[1], b1[1])
	if caps:
		for e: int in [0, n - 1]:
			var ring: Array = rings[e]
			for s in segs:
				if e == 0:
					tri(mat, pts[0], ring[(s + 1) % segs][0], ring[s][0])
				else:
					tri(mat, pts[n - 1], ring[s][0], ring[(s + 1) % segs][0])


## Straight round bar between two local points.
func bar(mat: String, a: Vector3, b: Vector3, radius: float, segs := 6) -> void:
	tube(mat, [a, b], radius, segs)


## Square-section beam between two local points (rotated so one face is "up").
func beam(mat: String, a: Vector3, b: Vector3, w: float, h := -1.0) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var x := d / l
	var up := Vector3.UP if absf(x.y) < 0.95 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	box(mat, (a + b) * 0.5, Vector3(l, h if h > 0.0 else w, w), 0.0, Basis(x, y, z))


## Surface of revolution around local +y at `c`: profile of (radius, height).
func lathe(mat: String, c: Vector3, prof: PackedVector2Array, segs := 12) -> void:
	for i in prof.size() - 1:
		var p := prof[i]
		var q := prof[i + 1]
		var slope := Vector2(q.y - p.y, -(q.x - p.x)).normalized() # outward normal in (r, y)
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var n0 := (d0 * slope.x + Vector3.UP * slope.y).normalized()
			var n1 := (d1 * slope.x + Vector3.UP * slope.y).normalized()
			var v00 := c + d0 * p.x + Vector3.UP * p.y
			var v01 := c + d1 * p.x + Vector3.UP * p.y
			var v10 := c + d0 * q.x + Vector3.UP * q.y
			var v11 := c + d1 * q.x + Vector3.UP * q.y
			tri_n(mat, v00, v11, v01, n0, n1, n1)
			tri_n(mat, v00, v10, v11, n0, n0, n1)


## Printed sign from the trackside signs atlas (TracksideUV.SIGNS key), facing
## local `normal`; h <= 0 keeps the region's aspect.
func sign(c: Vector3, normal: Vector3, w: float, h: float, key: String, up := Vector3.UP) -> void:
	var r: Array = TracksideUV.SIGNS.get(key, [0, 0, 0.01, 0.01, 1.0])
	var rg := Rect2(r[0], r[1], r[2], r[3])
	if h <= 0.0:
		h = w / float(r[4])
	var nn := normal.normalized()
	var rt := up.cross(nn).normalized() * w * 0.5
	var u := up.normalized() * h * 0.5
	var pts := [c - rt + u, c + rt + u, c + rt - u, c - rt - u]
	var uvp := [rg.position, Vector2(rg.end.x, rg.position.y), rg.end, Vector2(rg.position.x, rg.end.y)]
	var a := _arr("props")
	var nw := (xf.basis * nn).normalized()
	for k: int in [0, 1, 2, 0, 2, 3]:
		a[0].append(xf * pts[k])
		a[1].append(nw)
		a[2].append(Color.WHITE)
		a[3].append(uvp[k])
		a[4].append(Vector2(1.0, 0.0))


## Spray-paint decal from the trackside paint atlas (TracksideUV.PAINT key, e.g.
## TracksideKit.GRAFFITI_BIG), alpha-blended, tinted by `tint`; h <= 0 keeps aspect.
func paint(c: Vector3, normal: Vector3, w: float, h: float, key: String, tint := Color.WHITE, up := Vector3.UP) -> void:
	var r: Array = TracksideUV.PAINT.get(key, [0, 0, 0.01, 0.01, 1.0])
	var rg := Rect2(r[0], r[1], r[2], r[3])
	if h <= 0.0:
		h = w / float(r[4])
	var nn := normal.normalized()
	var rt := up.cross(nn).normalized() * w * 0.5
	var u := up.normalized() * h * 0.5
	var cc := c + nn * 0.015
	var pts := [cc - rt + u, cc + rt + u, cc + rt - u, cc - rt - u]
	var uvp := [rg.position, Vector2(rg.end.x, rg.position.y), rg.end, Vector2(rg.position.x, rg.end.y)]
	var a := _arr("paint")
	var nw := (xf.basis * nn).normalized()
	for k: int in [0, 1, 2, 0, 2, 3]:
		a[0].append(xf * pts[k])
		a[1].append(nw)
		a[2].append(tint)
		a[3].append(uvp[k])
		a[4].append(Vector2.ZERO)


## Box collider (local centre, size, rotation).
func collide(c: Vector3, size: Vector3, rot := Basis()) -> void:
	_boxes.append([xf * Transform3D(rot, c), size])


func cast_shadows(mat: String) -> void:
	_shadow_mats[mat] = true


## Build everything under a new Node3D `node_name` added to `c` (returned): one
## MeshInstance3D per material (named <mat>) + one StaticBody3D.
func commit(c: Node3D, node_name: String, vis_end := 700.0, shadows := true) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	c.add_child(root)
	var tris := 0
	for mat: String in _b:
		tris += _b[mat][0].size() / 3
	stats[node_name] = [_b.size(), tris]
	for mat: String in _b:
		var a: Array = _b[mat]
		if a[0].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = a[0]
		arrays[Mesh.ARRAY_NORMAL] = a[1]
		arrays[Mesh.ARRAY_COLOR] = a[2]
		arrays[Mesh.ARRAY_TEX_UV] = a[3]
		arrays[Mesh.ARRAY_TEX_UV2] = a[4]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = mat
		mi.mesh = mesh
		mi.material_override = material(c, mat)
		var sh: bool = shadows and mat != "paint" and mat != "glass" and (_shadow_mats.is_empty() or _shadow_mats.has(mat))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if vis_end > 0.0:
			var aabb := mesh.get_aabb()
			mi.visibility_range_end = vis_end + aabb.size.length() * 0.5
			mi.visibility_range_end_margin = vis_end * 0.1
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # dissolve over the margin, no pop
		root.add_child(mi)
	if not _boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "collision"
		var pm := PhysicsMaterial.new()
		pm.friction = 0.2
		body.physics_material_override = pm
		for bx: Array in _boxes:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = bx[1]
			cs.shape = shape
			cs.transform = bx[0]
			body.add_child(cs)
		root.add_child(body)
	_b.clear()
	_boxes.clear()
	return root


## Debug: `--gx_ab` frame-cost A/B of `root` (gxcamp's tool), camera at eye.
static func ab(root: Node3D, eye: Vector3, look: Vector3) -> void:
	const CAMP := "res://scripts/track/gimmicks/gx_camp.gd"
	if OS.get_cmdline_user_args().has("--gx_ab") and ResourceLoader.exists(CAMP):
		load(CAMP).maybe_ab(root, eye, look)


static func material(c: Node3D, mat: String) -> Material:
	if mat == "paint":
		if _paint_mat == null:
			var wx = c.get("weather")
			var wet: float = float(wx.preset.get("wet", 0.0)) if wx is Weather else 0.0
			var m := StandardMaterial3D.new()
			m.albedo_texture = load("res://assets/trackside/trackside_paint.png")
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.4 if wet > 0.3 else 0.8
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_paint_mat = m
		return _paint_mat
	if mat == "props":
		if _props_mat == null:
			var wx = c.get("weather")
			var preset: Dictionary = wx.preset if wx is Weather else {}
			_props_mat = Mats.props(load(SIGNS), _grime(), preset)
		return _props_mat
	return Mats.mat(mat, Color.WHITE, false)


static func _grime() -> NoiseTexture2D:
	if _grime_tex == null:
		var nz := FastNoiseLite.new()
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = 0.03
		nz.fractal_octaves = 4
		nz.seed = 91
		_grime_tex = NoiseTexture2D.new()
		_grime_tex.noise = nz
		_grime_tex.width = 256
		_grime_tex.height = 256
		_grime_tex.seamless = true
		_grime_tex.generate_mipmaps = true
	return _grime_tex
