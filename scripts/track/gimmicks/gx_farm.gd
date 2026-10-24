class_name GxFarm
extends Node3D
## A working farm field beside the track: a ploughed field (Poly Haven farm
## soil), a tractor pulling a disc harrow up and down the rows with a dust
## trail, round bales (straw, and silage bales in white / green / black
## wrap), a scarecrow, and a galvanised five-bar farm gate in a post-and-wire
## fence at the verge (gate half open; `dog_spot` meta marks where a farm dog
## sits).
##
##   GxFarm.place(c, Gx.frame(c, 1500.0, Gx.LEFT, 6.0), {})
##
## Frame: Gx.frame (x along, +z away from the road). The fence runs along
## z = 0 over x in [-w/2, w/2]; the field fills z in [4, 4 + depth].
## Options: width (70), depth (45), tractor (true), bales (10), scarecrow (true),
##   colour "green" | "red" | "blue" (tractor), dust (true; off when wet/snow),
##   seed. Root node "GxFarm" carries meta "dog_spot" (world Vector3, by the gate).

const TRACTOR_COLS := {green = Color(0.18, 0.42, 0.18), red = Color(0.62, 0.08, 0.06), blue = Color(0.10, 0.25, 0.55)}

var path: Curve3D
var speed := 3.2
var _s := 0.0
var _wheels: Array[Node3D] = []
var _radii: Array[float] = []


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(opts.get("seed", hash(xf.origin.snapped(Vector3.ONE) + Vector3(0, 0, 5))))
	var w := float(opts.get("width", 70.0))
	var depth := float(opts.get("depth", 45.0))
	var root := Node3D.new()
	root.name = "GxFarm"
	c.add_child(root)
	Gx.reserve(c, xf * Vector3(0, 0, 4.0 + depth * 0.5), maxf(w, depth) * 0.6)
	var cam := GxCamp.Camp.new(c, root, xf, r)
	_field(c, root, xf, w, depth)
	_fence(cam, w, r)
	root.set_meta("dog_spot", xf * Vector3(-1.2, 0, 1.2))
	# bales: a few scattered, one stack by the gate
	var nb := int(opts.get("bales", 10))
	for i in nb:
		var p := Vector3(r.randf_range(-w * 0.42, w * 0.42), 0, r.randf_range(8.0, 4.0 + depth * 0.9))
		_bale(cam, p, r.randf() * TAU, r)
	for i in 3:
		_bale(cam, Vector3(4.5 + i * 1.6, 0, 6.0), 0.0, r, 0)
	_bale(cam, Vector3(5.3, 1.45, 6.0), 0.0, r, 0)
	if GxCamp._b(opts.get("scarecrow", true)):
		_scarecrow(cam, Vector3(r.randf_range(-w * 0.2, w * 0.2), 0, 4.0 + depth * 0.45), r.randf_range(-0.5, 0.5))
	cam.commit()
	if GxCamp._b(opts.get("tractor", true)):
		var t := GxFarm.new()
		t.name = "Tractor"
		t.path = _rows(c, xf, w, depth)
		t._s = r.randf() * t.path.get_baked_length()
		var col: Color = TRACTOR_COLS.get(str(opts.get("colour", ["green", "red", "blue"][r.randi() % 3])), TRACTOR_COLS.green)
		t._build(col)
		var wx = c.get("weather")
		var wet: bool = wx != null and wx.get("preset") is Dictionary and (float(wx.preset.get("wet", 0.0)) > 0.3 or float(wx.preset.get("snow", 0.0)) > 0.3)
		if GxCamp._b(opts.get("dust", true)) and not wet:
			t._dust()
		root.add_child(t)


## Ploughed soil draped on the terrain (a grid a few cm above it).
static func _field(c: Node3D, root: Node3D, xf: Transform3D, w: float, depth: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 28
	var nz := 18
	var pts := []
	for j in nz + 1:
		var row := []
		for i in nx + 1:
			var lp := Vector3(lerpf(-w * 0.5, w * 0.5, float(i) / nx), 0, lerpf(4.0, 4.0 + depth, float(j) / nz))
			var wp := xf * lp
			wp.y = Gx.ground(c, wp) + 0.06
			row.append(wp)
		pts.append(row)
	for j in nz:
		for i in nx:
			var a: Vector3 = pts[j][i]
			var b: Vector3 = pts[j][i + 1]
			var cc: Vector3 = pts[j + 1][i + 1]
			var d: Vector3 = pts[j + 1][i]
			var n := (d - a).cross(b - a).normalized()
			if n.y < 0.0:
				n = -n
			# edge fade into the grass: vertex alpha
			for v: Vector3 in [a, b, cc, a, cc, d]:
				st.set_normal(n)
				st.add_vertex(v)
	st.index()
	var tris := st.commit_to_arrays()
	# fix winding so the soil faces up
	var verts: PackedVector3Array = tris[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = tris[Mesh.ARRAY_INDEX]
	for k in range(0, idx.size(), 3):
		var nrm := (verts[idx[k + 1]] - verts[idx[k]]).cross(verts[idx[k + 2]] - verts[idx[k]])
		if nrm.y > 0.0: # Godot front faces are clockwise seen from the front
			var tmp := idx[k + 1]
			idx[k + 1] = idx[k + 2]
			idx[k + 2] = tmp
	tris[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tris)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/themes/farm_soil/farm_soil_diff_1k.jpg")
	m.normal_enabled = true
	m.normal_texture = load("res://assets/themes/farm_soil/farm_soil_nor_gl_1k.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.25
	m.albedo_color = Color(0.85, 0.8, 0.75)
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var mi := MeshInstance3D.new()
	mi.name = "Field"
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 600.0
	root.add_child(mi)


## Lawn-mower rows with U-turns and a headland back to the start (closed).
static func _rows(c: Node3D, xf: Transform3D, w: float, depth: float) -> Curve3D:
	var cv := Curve3D.new()
	cv.bake_interval = 1.0
	var x0 := -w * 0.5 + 6.0
	var x1 := w * 0.5 - 6.0
	var rows := maxi(int((depth - 10.0) / 6.0), 2)
	var pts: Array[Vector3] = []
	for k in rows:
		var z := 9.0 + k * 6.0
		var fwd := k % 2 == 0
		var xa := x0 if fwd else x1
		var xb := x1 if fwd else x0
		pts.append(Vector3(xa, 0, z))
		pts.append(Vector3(xb, 0, z))
		if k < rows - 1: # U-turn
			var sgn := 1.0 if fwd else -1.0
			for q in 5:
				var a := PI * (q + 1) / 6.0
				pts.append(Vector3(xb + sgn * sin(a) * 3.0, 0, z + 3.0 - cos(a) * 3.0))
	# headland back along the far end and down the side
	var last := pts[pts.size() - 1]
	pts.append(Vector3(last.x + (3.0 if last.x > 0 else -3.0), 0, last.z + 3.0))
	pts.append(Vector3(x0 - 3.0, 0, last.z + 3.0))
	pts.append(Vector3(x0 - 4.0, 0, 7.0))
	pts.append(Vector3(x0, 0, 9.0))
	for p in pts:
		var wp := xf * p
		wp.y = Gx.ground(c, wp)
		cv.add_point(wp)
	return cv


func _process(delta: float) -> void:
	if path == null:
		return
	var l := path.get_baked_length()
	_s = fmod(_s + speed * delta, l)
	var p := path.sample_baked(_s, true)
	var ahead := path.sample_baked(fmod(_s + 2.5, l), true)
	var dir := ahead - p
	if dir.length() < 0.01:
		return
	var b := Basis.looking_at(dir.normalized(), Vector3.UP)
	transform = Transform3D(b, p)
	for i in _wheels.size():
		_wheels[i].rotate_object_local(Vector3.RIGHT, -speed * delta / _radii[i])


func _build(col: Color) -> void:
	var g := GxGeo.new()
	var dark := Color(0.08, 0.08, 0.08)
	# chassis + bonnet (nose at -z), rounded
	g.col = dark
	g.box("steel", Vector3(0, 0.75, -0.6), Vector3(0.75, 0.45, 3.0), 0.05)
	g.col = col
	g.box("painted_metal", Vector3(0, 1.25, -1.15), Vector3(0.95, 0.85, 2.0), 0.16)
	g.col = Color(0.12, 0.12, 0.12)
	g.box("painted_metal", Vector3(0, 1.2, -2.16), Vector3(0.8, 0.65, 0.04), 0.03) # grille
	g.col = Color(0.95, 0.95, 0.9)
	for sx: float in [-0.3, 0.3]:
		g.box("glass", Vector3(sx, 1.52, -2.17), Vector3(0.16, 0.08, 0.03), 0.01)
	# cab: four posts, glass, roof
	var cab := Vector3(0, 0, 0.75)
	g.col = dark
	for sx: float in [-0.62, 0.62]:
		for sz: float in [-0.55, 0.65]:
			g.box("steel", cab + Vector3(sx, 2.05, sz), Vector3(0.07, 1.6, 0.07))
	g.col = Color.WHITE
	g.box("glass", cab + Vector3(0, 2.05, -0.56), Vector3(1.22, 1.45, 0.02), 0.02)
	g.box("glass", cab + Vector3(0, 2.05, 0.66), Vector3(1.22, 1.45, 0.02), 0.02)
	for sx: float in [-0.63, 0.63]:
		g.box("glass", cab + Vector3(sx, 2.1, 0.05), Vector3(0.02, 1.35, 1.15), 0.02)
	g.col = col
	g.box("painted_metal", cab + Vector3(0, 2.9, 0.05), Vector3(1.45, 0.14, 1.55), 0.06)
	g.col = Color(0.9, 0.55, 0.05)
	g.box("glass", cab + Vector3(0, 3.02, 0.5), Vector3(0.12, 0.1, 0.12), 0.03) # beacon
	# seat + steering wheel silhouette
	g.col = dark
	g.box("painted_metal", cab + Vector3(0, 1.55, 0.25), Vector3(0.5, 0.5, 0.45), 0.08)
	g.tube("steel", [cab + Vector3(-0.18, 1.8, -0.3), cab + Vector3(0.18, 1.8, -0.3)], 0.12, 10, false)
	# rear mudguards over the big wheels
	g.col = col
	for sx: float in [-1.0, 1.0]:
		var pts := []
		for k in 7:
			var a := PI * (0.05 + 0.6 * k / 6.0)
			pts.append(Vector3(sx * 0.95, 0.85 + sin(a) * 0.95, 0.75 + cos(a) * 0.95))
		g.tube("painted_metal", pts, 0.2, 4, false)
	# exhaust stack
	g.col = Color(0.2, 0.2, 0.2)
	g.bar("steel", Vector3(0.35, 1.6, -1.6), Vector3(0.35, 2.9, -1.6), 0.05, 8)
	# three-point linkage + disc harrow behind
	g.col = dark
	g.beam("steel", Vector3(0, 0.6, 1.5), Vector3(0, 0.55, 2.6), 0.1)
	g.col = Color(0.75, 0.55, 0.1)
	g.box("painted_metal", Vector3(0, 0.75, 2.8), Vector3(3.0, 0.12, 0.15), 0.02)
	g.box("painted_metal", Vector3(0, 0.75, 3.6), Vector3(3.0, 0.12, 0.15), 0.02)
	g.col = Color(0.35, 0.35, 0.35)
	for row in 2:
		for k in 8:
			var x := -1.35 + k * 0.385
			g.lathe("steel", Vector3(x, 0.3, 2.85 + row * 0.8), PackedVector2Array([Vector2(0.0, -0.03), Vector2(0.28, 0.0), Vector2(0.0, 0.03)]), 10)
	_commit_into(g, self)
	# wheels: rear r 0.85 (lugged), front r 0.5
	_axle(Vector3(0, 0.85, 0.75), 0.85, 0.5, 1.0)
	_axle(Vector3(0, 0.5, -1.55), 0.5, 0.32, 0.85)


func _axle(c: Vector3, rad: float, wdt: float, half: float) -> void:
	var n := Node3D.new()
	n.position = c
	add_child(n)
	var g := GxGeo.new()
	for sx: float in [-1.0, 1.0]:
		var x := sx * half
		g.col = Color(0.07, 0.07, 0.07)
		g.tube("rubber", [Vector3(x - wdt * 0.5, 0, 0), Vector3(x + wdt * 0.5, 0, 0)], rad * 0.93, 18)
		# chevron lugs
		var lugs := 20
		for k in lugs:
			var a := TAU * k / lugs
			var rot := Basis(Vector3.RIGHT, a)
			g.box("rubber", rot * Vector3(x - wdt * 0.22, rad * 0.95, 0), Vector3(wdt * 0.48, rad * 0.1, 0.09), 0.01, rot * Basis(Vector3.UP, 0.5))
			g.box("rubber", rot * Vector3(x + wdt * 0.22, rad * 0.95, 0.04), Vector3(wdt * 0.48, rad * 0.1, 0.09), 0.01, rot * Basis(Vector3.UP, -0.5))
		g.col = Color(0.9, 0.75, 0.15) # yellow rims
		g.tube("painted_metal", [Vector3(x + sx * wdt * 0.5, 0, 0), Vector3(x + sx * (wdt * 0.5 + 0.01), 0, 0)], rad * 0.62, 14)
	_commit_into(g, n)
	_wheels.append(n)
	_radii.append(rad)


func _dust() -> void:
	var ps := GPUParticles3D.new()
	ps.name = "Dust"
	ps.amount = 28
	ps.lifetime = 4.0
	ps.local_coords = false
	ps.position = Vector3(0, 0.3, 3.3)
	ps.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 12, 40))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.visibility_range_end = 400.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.5, 0.1, 0.3)
	pm.direction = Vector3(0, 1, 0.4)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.3, 0.15, 0.0)
	pm.scale_min = 1.2
	pm.scale_max = 2.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.5))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angle_max = 360.0
	var gr := Gradient.new()
	gr.set_color(0, Color(0.55, 0.45, 0.33, 0.0))
	gr.set_color(1, Color(0.6, 0.52, 0.42, 0.0))
	gr.add_point(0.12, Color(0.5, 0.42, 0.3, 0.35))
	gr.add_point(0.5, Color(0.58, 0.5, 0.4, 0.18))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	ps.process_material = pm
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = GxCamp.fx_texture("smoke")
	m.disable_receive_shadows = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	q.material = m
	ps.draw_pass_1 = q
	add_child(ps)


static func _commit_into(g: GxGeo, parent: Node3D) -> void:
	g.commit(parent, "Part", 500.0, false)


# ---------------------------------------------------------------- statics

## Post-and-wire fence along z = 0 with a galvanised five-bar gate (half open).
static func _fence(cam: GxCamp.Camp, w: float, r: RandomNumberGenerator) -> void:
	var g := cam.g
	var gate_hw := 1.8
	var x := -w * 0.5
	var prev_top := Vector3.ZERO
	var first := true
	while x <= w * 0.5:
		if absf(x) < gate_hw + 0.1:
			x = gate_hw + 0.1
			first = true
			continue
		var t := cam.at(Vector3(x, 0, 0.0), r.randf_range(-0.1, 0.1))
		cam.use(t)
		g.col = Color(0.55, 0.45, 0.35) * r.randf_range(0.8, 1.05)
		g.col.a = 1.0
		g.box("wood", Vector3(0, 0.55, 0), Vector3(0.1, 1.15, 0.1), 0.015, Basis(Vector3.FORWARD, r.randf_range(-0.04, 0.04)))
		cam.done()
		var top := cam.xf * (t * Vector3(0, 1.0, 0))
		if not first:
			for k in 3:
				var dy := -0.3 * k
				var a := cam.xf.affine_inverse() * (prev_top + Vector3(0, dy, 0))
				var b := cam.xf.affine_inverse() * (top + Vector3(0, dy, 0))
				g.col = Color(0.45, 0.45, 0.45)
				g.bar("steel", a, b, 0.006, 3)
		prev_top = top
		first = false
		x += 3.0
	# gate posts + gate
	for sx: float in [-1.0, 1.0]:
		cam.use(cam.at(Vector3(sx * gate_hw, 0, 0), 0.0))
		g.col = Color(0.45, 0.36, 0.28)
		g.box("wood", Vector3(0, 0.7, 0), Vector3(0.2, 1.45, 0.2), 0.02)
		cam.done()
	var hinge := cam.at(Vector3(-gate_hw + 0.12, 0, 0), -0.75) # swung half open into the field
	cam.use(hinge)
	g.col = Color(0.72, 0.74, 0.76)
	var gl := gate_hw * 2.0 - 0.3
	for k in 5:
		var y := 0.25 + k * 0.22
		g.bar("steel", Vector3(0, y, 0), Vector3(gl, y, 0), 0.022, 6)
	g.bar("steel", Vector3(0, 0.15, 0), Vector3(0, 1.25, 0), 0.03, 6)
	g.bar("steel", Vector3(gl, 0.15, 0), Vector3(gl, 1.25, 0), 0.025, 6)
	g.bar("steel", Vector3(0, 0.25, 0), Vector3(gl * 0.55, 1.13, 0), 0.02, 6) # diagonal brace
	cam.done()


## Round bale lying on its side. kind: 0 straw, 1 white wrap, 2 green wrap, 3 black wrap.
static func _bale(cam: GxCamp.Camp, p: Vector3, yaw: float, r: RandomNumberGenerator, kind := -1) -> void:
	if kind < 0:
		kind = [0, 0, 1, 1, 2, 3][r.randi() % 6]
	var t := cam.at(Vector3(p.x, 0, p.z), yaw, 0.04)
	t.origin.y += p.y
	cam.use(t)
	var g := cam.g
	var rad := 0.72
	var ln := 1.2
	var mat := "canvas" if kind == 0 else "painted_metal"
	var col: Color = [Color(0.78, 0.66, 0.38), Color(0.88, 0.88, 0.86), Color(0.22, 0.38, 0.22), Color(0.06, 0.06, 0.06)][kind]
	g.col = col
	# slightly barrel-shaped, flattened where it sits
	var pts := []
	var radii := []
	for k in 5:
		var s := float(k) / 4.0
		pts.append(Vector3(lerpf(-ln * 0.5, ln * 0.5, s), rad * 0.97, 0))
		radii.append(rad * (0.94 + 0.06 * sin(PI * s)))
	g.tube(mat, pts, rad, 16, true, radii)
	if kind == 0: # twine wraps
		g.col = col.darkened(0.25)
		for k in 4:
			var x := -0.45 + k * 0.3
			g.tube("canvas", cam._ring(Vector3.ZERO, rad + 0.006, 16).map(func(v: Vector3) -> Vector3: return Vector3(x, v.z + rad * 0.97, v.x)), 0.008, 3, false)
	cam.done()


static func _scarecrow(cam: GxCamp.Camp, p: Vector3, yaw: float) -> void:
	cam.use(cam.at(p, yaw, 0.2))
	var g := cam.g
	g.col = Color(0.5, 0.4, 0.3)
	g.box("wood", Vector3(0, 1.0, 0), Vector3(0.08, 2.2, 0.08), 0.01)
	g.box("wood", Vector3(0, 1.6, 0), Vector3(1.5, 0.07, 0.07), 0.01)
	# old checked shirt: torso + sleeves (canvas, tinted)
	g.col = Color(0.55, 0.18, 0.12)
	g.box("canvas", Vector3(0, 1.35, 0), Vector3(0.48, 0.65, 0.24), 0.08)
	g.tube("canvas", [Vector3(-0.72, 1.58, 0), Vector3(-0.2, 1.6, 0)], 0.09, 8, true, [0.11, 0.08])
	g.tube("canvas", [Vector3(0.2, 1.6, 0), Vector3(0.72, 1.58, 0)], 0.09, 8, true, [0.08, 0.11])
	# trousers hanging
	g.col = Color(0.2, 0.25, 0.35)
	for sx: float in [-0.1, 0.1]:
		g.tube("canvas", [Vector3(sx, 1.05, 0), Vector3(sx * 1.3, 0.45, 0.02)], 0.08, 8, true, [0.09, 0.07])
	# sack head + hat
	g.col = Color(0.72, 0.62, 0.45)
	g.lathe("canvas", Vector3(0, 1.72, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.13, 0.05), Vector2(0.15, 0.17), Vector2(0.11, 0.3), Vector2(0.0, 0.33)]), 10)
	g.col = Color(0.3, 0.22, 0.14)
	g.lathe("canvas", Vector3(0, 1.98, 0), PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.32, 0.0), Vector2(0.3, 0.03), Vector2(0.14, 0.04), Vector2(0.13, 0.2), Vector2(0.0, 0.22)]), 12)
	# straw tufts at the cuffs
	g.col = Color(0.8, 0.68, 0.35)
	for sx: float in [-1.0, 1.0]:
		g.tube("canvas", [Vector3(sx * 0.72, 1.58, 0), Vector3(sx * 0.85, 1.52, 0)], 0.06, 6, true, [0.06, 0.02])
	cam.done()
