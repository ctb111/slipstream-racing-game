class_name CarBodyBuilder
extends RefCounted
## Generates a smooth car body by lofting cross-sections along the car's length,
## shaped like a classic rear-engined coupé (930-ish): round headlights on raised
## front fenders, fastback roof, wide rear hips, whale-tail spoiler.
## Car-local space: -Z is forward, wheel mounts at y = 0, ground at about y = -0.54.

const Z_FRONT := -2.17
const Z_REAR := 2.2
const DZ := 0.025
const WHEEL_Z_FRONT := -1.13
const WHEEL_Z_REAR := 1.14
const ARCH_CENTER_Y := -0.2
const ARCH_R_FRONT := 0.37
const ARCH_R_REAR := 0.38

# [z, value] keyframes, interpolated with smoothstep between keys.
const HALF_WIDTH := [[-2.17, 0.62], [-2.1, 0.76], [-1.9, 0.83], [-1.13, 0.86], [-0.5, 0.845],
		[0.3, 0.86], [1.1, 0.9], [1.85, 0.875], [2.12, 0.84], [2.2, 0.78]]
const BOTTOM := [[-2.17, -0.2], [-2.08, -0.32], [-1.85, -0.36], [1.95, -0.36], [2.2, -0.28]]
const CENTER_TOP := [[-2.17, -0.1], [-2.1, 0.0], [-1.85, 0.06], [-1.3, 0.11], [-0.8, 0.14],
		[0.9, 0.22], [1.55, 0.29], [1.9, 0.23], [2.12, 0.15], [2.2, 0.08]]
const FENDER_TOP := [[-2.17, -0.08], [-2.08, 0.08], [-1.85, 0.18], [-1.2, 0.23], [-0.7, 0.17],
		[-0.2, 0.13], [0.5, 0.18], [1.1, 0.28], [1.6, 0.27], [2.0, 0.19], [2.2, 0.08]]
const BELT := [[-2.17, -0.1], [-2.05, 0.0], [-1.2, 0.05], [1.2, 0.08], [2.0, 0.08], [2.2, 0.02]]

# Greenhouse (glass + roof): height above the body at its base.
const GH_Z0 := -0.8
const GH_Z1 := 1.55
const GH_HEIGHT := [[-0.8, 0.0], [-0.6, 0.16], [-0.3, 0.42], [-0.1, 0.53], [0.1, 0.56],
		[0.35, 0.54], [0.7, 0.44], [1.1, 0.24], [1.55, 0.0]]
const GH_BASE_W := [[-0.8, 0.7], [0.0, 0.71], [1.0, 0.68], [1.55, 0.6]]
const GH_TOP_W := [[-0.8, 0.64], [-0.2, 0.57], [0.4, 0.57], [1.0, 0.5], [1.55, 0.44]]


static func _key(table: Array, z: float) -> float:
	if z <= table[0][0]:
		return table[0][1]
	for i in range(1, table.size()):
		if z <= table[i][0]:
			var t: float = (z - table[i - 1][0]) / (table[i][0] - table[i - 1][0])
			return lerpf(table[i - 1][1], table[i][1], smoothstep(0.0, 1.0, t))
	return table[-1][1]


static func _arch_y(z: float) -> float:
	for a in [[WHEEL_Z_FRONT, ARCH_R_FRONT], [WHEEL_Z_REAR, ARCH_R_REAR]]:
		var dz: float = absf(z - a[0])
		if dz < a[1]:
			return ARCH_CENTER_Y + sqrt(a[1] * a[1] - dz * dz)
	return -INF


## Catmull-Rom subdivision so the visible upper surface is round, not faceted.
static func _smooth(pts: Array[Vector2], sub: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in pts.size() - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, pts.size() - 1)]
		for s in sub:
			var t := float(s) / sub
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(pts[-1])
	return out


## Right half (x >= 0) of the lower body section, bottom centre -> top centre.
## First 4 points are underbody / wheel well, the rest is the visible skin.
static func _body_section(z: float) -> Array[Vector2]:
	var w := _key(HALF_WIDTH, z)
	var yb := _key(BOTTOM, z)
	var yc := _key(CENTER_TOP, z)
	var yf := _key(FENDER_TOP, z)
	var belt := _key(BELT, z)
	var arch := _arch_y(z)
	var sill := maxf(yb + 0.08, arch)
	var lower: Array[Vector2] = [
		Vector2(0, yb), Vector2(w * 0.6, yb), Vector2(w * 0.62, maxf(yb, arch)), Vector2(w, sill)]
	var upper: Array[Vector2] = [Vector2(w, sill)]
	var side_top := maxf(belt, sill + 0.03)
	upper.append(Vector2(w, side_top))
	var shoulder := maxf(belt + 0.07, side_top + 0.04)
	upper.append(Vector2(w * 0.94, shoulder))
	var crown := maxf(yf, shoulder + 0.03)
	upper.append(Vector2(w * 0.74, crown))
	upper.append(Vector2(w * 0.45, lerpf(crown, yc, 0.8)))
	upper.append(Vector2(w * 0.2, yc))
	upper.append(Vector2(0, yc))
	var pts := lower.slice(0, 3)
	pts.append_array(_smooth(upper, 3))
	return pts


static func _body_y_at(section: Array[Vector2], x: float) -> float:
	# Walk the visible skin from the top centre outwards.
	for i in range(section.size() - 1, 3, -1):
		var a := section[i]
		var b := section[i - 1]
		if x >= a.x and x <= b.x and b.x > a.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return section[-1].y


static func _greenhouse_section(z: float, body: Array[Vector2]) -> Array[Vector2]:
	var h := _key(GH_HEIGHT, z)
	var wb := _key(GH_BASE_W, z)
	var wt := _key(GH_TOP_W, z)
	var base := _body_y_at(body, wb) - 0.02
	var top := base + h
	var s := clampf(h / 0.2, 0.0, 1.0)
	var pts: Array[Vector2] = [Vector2(wb, base), Vector2(lerpf(wb, wt, s), top - 0.07 * s)]
	pts.append_array(_smooth([Vector2(lerpf(wb, wt, s), top - 0.07 * s), Vector2(wt * 0.8, top - 0.012 * s), Vector2(0, top)], 3).slice(1))
	return pts


## Adds a lofted surface (both mirrored halves) to per-material SurfaceTools.
## `mat_for(segment, z)` picks a material key for each quad.
static func _loft(sections: Array, zs: Array[float], tools: Dictionary, mat_for: Callable) -> void:
	for i in range(1, sections.size()):
		var a: Array[Vector2] = sections[i - 1]
		var b: Array[Vector2] = sections[i]
		for j in a.size() - 1:
			var key: String = mat_for.call(j, zs[i])
			var st: SurfaceTool = tools[key]
			for side: float in [1.0, -1.0]:
				var p00 := Vector3(a[j].x * side, a[j].y, zs[i - 1])
				var p01 := Vector3(a[j + 1].x * side, a[j + 1].y, zs[i - 1])
				var p10 := Vector3(b[j].x * side, b[j].y, zs[i])
				var p11 := Vector3(b[j + 1].x * side, b[j + 1].y, zs[i])
				var uv00 := Vector2(j, zs[i - 1])
				var uv01 := Vector2(j + 1, zs[i - 1])
				var uv10 := Vector2(j, zs[i])
				var uv11 := Vector2(j + 1, zs[i])
				if side > 0:
					_tri(st, [p00, p10, p11], [uv00, uv10, uv11])
					_tri(st, [p00, p11, p01], [uv00, uv11, uv01])
				else:
					_tri(st, [p00, p11, p10], [uv00, uv11, uv10])
					_tri(st, [p00, p01, p11], [uv00, uv01, uv11])


static func _cap(section: Array[Vector2], z: float, bulge: float, st: SurfaceTool) -> void:
	var centre := Vector3(0, (section[0].y + section[-1].y) * 0.5, z + bulge)
	for j in section.size() - 1:
		for side: float in [1.0, -1.0]:
			var p0 := Vector3(section[j].x * side, section[j].y, z)
			var p1 := Vector3(section[j + 1].x * side, section[j + 1].y, z)
			_tri(st, [centre, p0, p1], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


static func _tri(st: SurfaceTool, p: Array, uv: Array) -> void:
	for k in 3:
		st.set_uv(uv[k])
		st.add_vertex(p[k])


## One merged mesh per car / wheel type, shared by every car: each material is
## a single surface, so a whole car costs a handful of draw calls.
const SURF_PAINT := 0
const SURF_BRAKE := 6
static var _body_mesh: ArrayMesh
static var _wheel_meshes := {}


static func _tools(keys: Array) -> Dictionary:
	var tools := {}
	for k in keys:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[k] = st
	return tools


static func _add_prim(st: SurfaceTool, mesh: PrimitiveMesh, xform: Transform3D) -> void:
	st.append_from(mesh, 0, xform)


# ---------------------------------------------------------------- materials

static func paint_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.25
	m.roughness = 0.38
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _emissive(color: Color, glow: Color, energy: float) -> StandardMaterial3D:
	var m := _mat(color, 0.0, 0.15)
	m.emission_enabled = true
	m.emission = glow
	m.emission_energy_multiplier = energy
	return m


# ---------------------------------------------------------------- body

## Builds the body under `parent`. Returns the brake-light material so the car
## can brighten it when braking.
static func build(parent: Node3D, paint_color: Color) -> StandardMaterial3D:
	if _body_mesh == null:
		_body_mesh = _build_body_mesh()
	var mi := MeshInstance3D.new()
	mi.name = "BodyMesh"
	mi.mesh = _body_mesh
	var glass := _mat(Color(0.03, 0.035, 0.04), 0.1, 0.03)
	glass.metallic_specular = 0.9
	var brake_mat := _emissive(Color(0.35, 0.01, 0.01), Color(1.0, 0.04, 0.02), 0.25)
	var surface_mats := [
		paint_material(paint_color),
		glass,
		_mat(Color(0.025, 0.025, 0.025), 0.0, 0.9), # underbody
		_mat(Color(0.035, 0.035, 0.035), 0.0, 0.7), # rubber
		_mat(Color(0.85, 0.85, 0.85), 1.0, 0.12), # chrome
		_emissive(Color(0.9, 0.9, 0.86), Color(1.0, 0.96, 0.88), 1.2), # headlight lens
		brake_mat,
	]
	for i in surface_mats.size():
		mi.set_surface_override_material(i, surface_mats[i])
	parent.add_child(mi)
	return brake_mat


static func _build_body_mesh() -> ArrayMesh:
	var tools := _tools(["paint", "glass", "under", "rubber", "chrome", "lens", "brake"])
	var loft := _tools(["paint", "glass", "under"]) # lofted panels: normals generated separately

	# Lower body
	var zs: Array[float] = []
	var body_sections: Array = []
	var z := Z_FRONT
	while z <= Z_REAR + 0.0001:
		zs.append(z)
		body_sections.append(_body_section(z))
		z += DZ
	_loft(body_sections, zs, loft, func(seg: int, _z: float) -> String:
		return "under" if seg < 3 else "paint")
	_cap(body_sections[0], zs[0], -0.03, loft["paint"])
	_cap(body_sections[-1], zs[-1], 0.01, loft["paint"])

	# Greenhouse
	var gzs: Array[float] = []
	var gh_sections: Array = []
	for i in zs.size():
		if zs[i] >= GH_Z0 - 0.0001 and zs[i] <= GH_Z1 + 0.0001:
			gzs.append(zs[i])
			gh_sections.append(_greenhouse_section(zs[i], body_sections[i]))
	_loft(gh_sections, gzs, loft, func(seg: int, zz: float) -> String:
		if seg == 0: # side windows, with B-pillar
			var pillar := zz > 0.34 and zz < 0.42
			return "glass" if zz > -0.62 and zz < 1.05 and not pillar else "paint"
		return "glass" if zz < -0.22 or zz > 0.62 else "paint") # windscreen / rear window / roof
	for k in loft:
		var st: SurfaceTool = loft[k]
		st.index()
		st.generate_normals()
		tools[k].append_from(st.commit(), 0, Transform3D.IDENTITY)

	# Round headlights set into the front fenders.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.085
	torus.outer_radius = 0.105
	torus.rings = 20
	torus.ring_segments = 8
	var lens := CylinderMesh.new()
	lens.top_radius = 0.088
	lens.bottom_radius = 0.088
	lens.height = 0.03
	lens.radial_segments = 20
	lens.rings = 1
	for x in [-0.58, 0.58]:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-72)), Vector3(x, 0.05, -2.04))
		_add_prim(tools["chrome"], torus, xf)
		_add_prim(tools["lens"], lens, xf)

	# Impact bumpers: body colour with a black rubber strip.
	_capsule_bar(tools["paint"], 0.1, 1.5, Vector3(0, -0.23, -2.15), Vector3(1, 0.9, 0.9))
	_capsule_bar(tools["rubber"], 0.035, 1.3, Vector3(0, -0.2, -2.235), Vector3(1, 0.8, 0.6))
	_capsule_bar(tools["paint"], 0.1, 1.62, Vector3(0, -0.23, 2.19), Vector3(1, 0.9, 0.9))
	_capsule_bar(tools["rubber"], 0.035, 1.42, Vector3(0, -0.2, 2.275), Vector3(1, 0.8, 0.6))
	# Whale-tail spoiler with rubber lip.
	_capsule_bar(tools["paint"], 0.36, 1.56, Vector3(0, 0.34, 1.82), Vector3(1, 0.14, 1.0))
	_capsule_bar(tools["rubber"], 0.045, 1.5, Vector3(0, 0.38, 2.15), Vector3(1, 0.9, 1.0))
	# Full-width tail-light bar.
	_capsule_bar(tools["brake"], 0.055, 1.52, Vector3(0, 0.02, 2.2), Vector3(1, 1, 0.4))

	# Door mirrors.
	var mirror := SphereMesh.new()
	mirror.radius = 0.07
	mirror.height = 0.1
	mirror.radial_segments = 12
	mirror.rings = 6
	for x in [-0.93, 0.93]:
		_add_prim(tools["paint"], mirror, Transform3D(Basis().scaled(Vector3(1.0, 0.8, 1.3)), Vector3(x, 0.3, -0.55)))

	# Exhaust tip.
	var ex := CylinderMesh.new()
	ex.top_radius = 0.045
	ex.bottom_radius = 0.045
	ex.height = 0.2
	ex.radial_segments = 12
	ex.rings = 1
	_add_prim(tools["chrome"], ex, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.45, -0.32, 2.2)))

	var mesh := ArrayMesh.new()
	for k in ["paint", "glass", "under", "rubber", "chrome", "lens", "brake"]:
		tools[k].commit(mesh)
	return mesh


static func _capsule_bar(st: SurfaceTool, radius: float, length: float, pos: Vector3, scl: Vector3) -> void:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length
	c.radial_segments = 16
	c.rings = 3
	# Capsule axis is local Y; lay it along X.
	_add_prim(st, c, Transform3D(Basis(Vector3.BACK, PI * 0.5) * Basis().scaled(Vector3(scl.y, scl.x, scl.z)), pos))


# ---------------------------------------------------------------- wheels

## Revolves a profile (x = axial offset, y = radius) around the X axis.
static func _lathe(st: SurfaceTool, profile: Array[Vector2], segments: int, xform := Transform3D.IDENTITY) -> void:
	var tmp := SurfaceTool.new()
	tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		for j in profile.size() - 1:
			var p := profile[j]
			var q := profile[j + 1]
			var v00 := Vector3(p.x, p.y * cos(a0), p.y * sin(a0))
			var v01 := Vector3(p.x, p.y * cos(a1), p.y * sin(a1))
			var v10 := Vector3(q.x, q.y * cos(a0), q.y * sin(a0))
			var v11 := Vector3(q.x, q.y * cos(a1), q.y * sin(a1))
			var u0 := float(i) / segments
			var u1 := float(i + 1) / segments
			_tri(tmp, [v00, v10, v11], [Vector2(u0, j), Vector2(u0, j + 1), Vector2(u1, j + 1)])
			_tri(tmp, [v00, v11, v01], [Vector2(u0, j), Vector2(u1, j + 1), Vector2(u1, j)])
	tmp.index()
	tmp.generate_normals()
	st.append_from(tmp.commit(), 0, xform)


## Tire + Fuchs-style five-petal rim, outer face towards +X (flipped for left wheels).
static func build_wheel(spinner: Node3D, radius: float, width: float, left: bool) -> void:
	var key := "%.3f_%.3f" % [radius, width]
	if not _wheel_meshes.has(key):
		_wheel_meshes[key] = _build_wheel_mesh(radius, width)
	var mi := MeshInstance3D.new()
	mi.mesh = _wheel_meshes[key]
	if left:
		mi.rotation.y = PI
	var mats := [
		_mat(Color(0.03, 0.03, 0.03), 0.0, 0.85), # tire
		_mat(Color(0.82, 0.82, 0.8), 1.0, 0.18), # polished alloy
		_mat(Color(0.05, 0.05, 0.055), 0.4, 0.5), # recessed dish
		_mat(Color(0.18, 0.17, 0.16), 0.8, 0.45), # brake disc
	]
	for i in mats.size():
		mi.set_surface_override_material(i, mats[i])
	spinner.add_child(mi)


static func _build_wheel_mesh(radius: float, width: float) -> ArrayMesh:
	var tools := _tools(["tire", "polished", "recess", "disc"])
	var h := width * 0.5
	var r := radius
	var rim_r := r * 0.64
	_lathe(tools["tire"], [
		Vector2(-h + 0.01, rim_r), Vector2(-h, r * 0.8), Vector2(-h + 0.012, r * 0.95),
		Vector2(-h + 0.04, r), Vector2(h - 0.04, r), Vector2(h - 0.012, r * 0.95),
		Vector2(h, r * 0.8), Vector2(h - 0.01, rim_r)], 28)
	_lathe(tools["polished"], [Vector2(h - 0.03, rim_r), Vector2(h - 0.004, rim_r + 0.004),
		Vector2(h + 0.002, rim_r - 0.01), Vector2(h - 0.012, rim_r - 0.02)], 28)
	_lathe(tools["recess"], [Vector2(h - 0.012, rim_r - 0.02), Vector2(h - 0.05, rim_r - 0.035),
		Vector2(h - 0.07, 0.06), Vector2(h - 0.07, 0.0)], 20)
	var bd := CylinderMesh.new()
	bd.top_radius = rim_r * 0.85
	bd.bottom_radius = rim_r * 0.85
	bd.height = 0.025
	bd.radial_segments = 20
	bd.rings = 1
	_add_prim(tools["disc"], bd, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.02, 0, 0)))
	var petal := CapsuleMesh.new()
	petal.radius = 0.036
	petal.height = rim_r * 0.95
	petal.radial_segments = 8
	petal.rings = 2
	for k in 5:
		var spin := Basis(Vector3.RIGHT, TAU * k / 5.0)
		var xf := Transform3D(spin, Vector3(h - 0.045, 0, 0)) * Transform3D(Basis().scaled(Vector3(0.45, 1.0, 1.0)), Vector3(0, rim_r * 0.45, 0))
		_add_prim(tools["polished"], petal, xf)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.05
	hub.bottom_radius = 0.055
	hub.height = 0.04
	hub.radial_segments = 16
	hub.rings = 1
	_add_prim(tools["polished"], hub, Transform3D(Basis(Vector3.BACK, -PI * 0.5), Vector3(h - 0.03, 0, 0)))
	var mesh := ArrayMesh.new()
	for k in ["tire", "polished", "recess", "disc"]:
		tools[k].commit(mesh)
	return mesh
