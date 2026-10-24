class_name CarModel
extends RefCounted
## Loads a car glTF from CarCatalog and turns it into what Car needs: one
## merged body mesh (paint and brake lights as their own surfaces so each car
## can recolour / light them), four separate wheels centred on their hubs, and
## real measurements (wheelbase, track, wheel radius) so the physics matches
## the model.
##
## Wheels are found by material (catalog wheel_mats) and split into corners by
## quadrant, which works both when the source has them merged into the body
## and when they are separate nodes. Each wheel is recentred on its rim (the
## tyre is often squashed at the contact patch) so it spins without wobble.
##
## The source is rotated so its nose points to -Z, scaled to the real car's
## length, and kept in car space: wheel centres are where the hubs are.
## Credits: see CarCatalog and assets/cars/CREDITS_cars.txt.

static var _cache := {} ## model id -> data dictionary


static func available(model_id := CarCatalog.DEFAULT) -> bool:
	return CarCatalog.has(model_id) and ResourceLoader.exists(CarCatalog.get_car(model_id).path)


## Cached, shared by every car of that model. Keys: body (ArrayMesh),
## surface_mats, surface_keys (Array), paint_surface, brake_surface,
## lights_surface (int, -1 if none), wheels (Array of {mesh, mats, centre, front, left}),
## wheel_radius, wheel_width (float), body_aabb (AABB), model_id.
static func data(model_id := CarCatalog.DEFAULT) -> Dictionary:
	if not CarCatalog.has(model_id):
		model_id = CarCatalog.DEFAULT
	if _cache.has(model_id):
		return _cache[model_id]
	var spec := CarCatalog.get_car(model_id)
	var skip: Array = spec.get("skip", [])
	var wheel_mats: Array = spec.wheel_mats
	var paint_mats: Array = spec.get("paint_mats", [])
	var brake_mats: Array = spec.get("brake_mats", [])
	var lights_mat: String = spec.get("lights_mat", "")

	var scene: PackedScene = load(spec.path)
	var root := scene.instantiate()
	var parts := []
	_walk(root, Transform3D.IDENTITY, parts)

	# Orientation: the source nose points along spec.forward; we drive towards -Z.
	var fwd: Vector3 = spec.get("forward", Vector3(0, 0, 1))
	var rot := Basis.looking_at(fwd, Vector3.UP).inverse()
	# Size along the (rotated) length, and the tyres' extent to tell wheels from body.
	var box := AABB()
	var first := true
	var tyre_box := AABB()
	var first_tyre := true
	for part in parts:
		var mesh: Mesh = part[0].mesh
		var xf: Transform3D = Transform3D(rot, Vector3.ZERO) * part[1]
		for s in mesh.get_surface_count():
			var name := _mat_name(mesh, s)
			if name in skip:
				continue
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = xf * v
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				box = box.expand(p)
				if name == spec.tire_mat:
					if first_tyre:
						tyre_box = AABB(p, Vector3.ZERO)
						first_tyre = false
					tyre_box = tyre_box.expand(p)
	var scale: float = spec.length / box.size.z
	# Centre the car on its wheels in X/Z, keep Y as modelled (car.gd uses the hub height).
	var mid := tyre_box.get_center() if not first_tyre else box.get_center()
	var fix := Transform3D(rot.scaled(Vector3.ONE * scale), -Vector3(mid.x, 0.0, mid.z) * scale)
	var wheel_top := (tyre_box.end.y * scale) + 0.05 # anything above the tyres is body

	# Collect triangles per material (body) and per wheel corner.
	var body_tris := {} ## key -> [material, PackedVector3Array pos, normals, uvs]
	var wheel_tris := {} ## "fl_<mat>" etc -> same layout
	for part in parts:
		var mesh: Mesh = part[0].mesh
		var xf: Transform3D = fix * part[1]
		var nbasis := xf.basis.inverse().transposed()
		for s in mesh.get_surface_count():
			var name := _mat_name(mesh, s)
			if name in skip:
				continue
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] else PackedVector3Array()
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] else PackedInt32Array()
			if idx.is_empty():
				idx.resize(verts.size())
				for k in verts.size():
					idx[k] = k
			var mat := mesh.surface_get_material(s)
			var is_wheel := name in wheel_mats
			var is_paint := name in paint_mats
			var is_brake := name in brake_mats
			for t in range(0, idx.size(), 3):
				var tri := [idx[t], idx[t + 1], idx[t + 2]]
				var ps := [xf * verts[tri[0]], xf * verts[tri[1]], xf * verts[tri[2]]]
				var c: Vector3 = (ps[0] + ps[1] + ps[2]) / 3.0
				var key := name
				var bucket := body_tris
				if is_wheel and c.y < wheel_top:
					key = ("f" if c.z < 0.0 else "r") + ("l" if c.x < 0.0 else "r") + "_" + name
					bucket = wheel_tris
				elif is_brake and c.z > 0.0:
					key = "brake" # rear lamps: their own surface so they can glow
				elif is_paint:
					key = "paint"
				if not bucket.has(key):
					bucket[key] = [mat, PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
				var b: Array = bucket[key]
				for k in 3:
					b[1].append(ps[k])
					b[2].append((nbasis * norms[tri[k]]).normalized() if norms.size() > 0 else Vector3.UP)
					b[3].append(uvs[tri[k]] if uvs.size() > 0 else Vector2.ZERO)
	root.free()

	# Wheel hubs: centre of each corner's rim (round), radius from the top of the tyre.
	var wheels := []
	var radius := 0.0
	var width := 0.0
	for corner in ["fl", "fr", "rl", "rr"]:
		var tyre: Array = wheel_tris.get(corner + "_" + spec.tire_mat, [])
		var rim: Array = wheel_tris.get(corner + "_" + spec.rim_mat, [])
		if tyre.is_empty():
			continue
		var tbox := _box(tyre[1])
		var centre := tbox.get_center()
		if not rim.is_empty():
			var rbox := _box(rim[1])
			centre = Vector3(centre.x, rbox.get_center().y, rbox.get_center().z)
		radius = maxf(radius, tbox.end.y - centre.y)
		width = maxf(width, tbox.size.x)
		# Some models ship with the front wheels turned (or toed/cambered): spinning
		# such a wheel about the car's x axis makes it wobble. Find the tyre's real
		# axle (the direction its vertices spread least) and square the wheel up.
		var straighten := _square_up(tyre[1], centre)
		var mesh := ArrayMesh.new()
		var mats := []
		for m in wheel_mats:
			var b: Array = wheel_tris.get(corner + "_" + m, [])
			if b.is_empty():
				continue
			_commit(mesh, b, -centre, straighten)
			mats.append(b[0])
		wheels.append({mesh = mesh, mats = mats, centre = centre, front = corner[0] == "f", left = corner[1] == "l"})

	# Body: one surface per key; remember which is paint / brake lamps / headlamps.
	var body := ArrayMesh.new()
	var surface_mats := []
	var surface_keys := []
	var paint_surface := -1
	var brake_surface := -1
	var lights_surface := -1
	var body_box := AABB()
	var first_body := true
	for key in body_tris:
		var b: Array = body_tris[key]
		var bb := _box(b[1])
		body_box = bb if first_body else body_box.merge(bb)
		first_body = false
		_commit(body, b, Vector3.ZERO)
		if key == "paint":
			paint_surface = surface_mats.size()
		elif key == "brake":
			brake_surface = surface_mats.size()
		elif key == lights_mat:
			lights_surface = surface_mats.size()
		surface_mats.append(b[0])
		surface_keys.append(key)

	# Rebuilding the meshes drops the LODs Godot generated on import: make them
	# again, so distant cars (and their shadows) draw a fraction of the
	# triangles. Godot picks the LOD by on-screen error (< 1 px).
	var shadow := _shadow_mesh(body, surface_mats, wheels)
	body = _with_lods(body)
	for w: Dictionary in wheels:
		w.mesh = _with_lods(w.mesh)
	var d := {body = body, shadow = shadow, surface_mats = surface_mats, surface_keys = surface_keys, paint_surface = paint_surface,
		brake_surface = brake_surface, lights_surface = lights_surface, wheels = wheels, wheel_radius = radius,
		wheel_width = width, body_aabb = body_box, model_id = model_id}
	_cache[model_id] = d
	return d


## One single-surface mesh of the opaque body plus the wheels at rest (model
## space, like `body`), with LODs: the car's only shadow caster, so its
## shadows cost one draw call per shadow split instead of one per surface.
static func _shadow_mesh(body: ArrayMesh, mats: Array, wheels: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var parts := []
	for s in body.get_surface_count():
		var m = mats[s] if s < mats.size() else null
		if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue # glass
		parts.append([body.surface_get_arrays(s), Vector3.ZERO])
	for w: Dictionary in wheels:
		var wm: ArrayMesh = w.mesh
		for s in wm.get_surface_count():
			parts.append([wm.surface_get_arrays(s), w.centre])
	for part: Array in parts:
		var arr: Array = part[0]
		var off: Vector3 = part[1]
		var base := verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if off != Vector3.ZERO:
			v = Transform3D(Basis(), off) * v
		verts.append_array(v)
		norms.append_array(arr[Mesh.ARRAY_NORMAL])
		var ii = arr[Mesh.ARRAY_INDEX]
		if ii == null:
			for k in v.size():
				idx.append(base + k)
		else:
			for k: int in ii:
				idx.append(base + k)
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return _with_lods(mesh)


## `mesh` with an automatic LOD chain (meshoptimizer, as the importer does);
## same surfaces in the same order.
static func _with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {},
			mesh.surface_get_material(s), mesh.surface_get_name(s))
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


static func _box(pts: PackedVector3Array) -> AABB:
	var a := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		a = a.expand(p)
	return a


static func _walk(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as Node3D).visible:
		out.append([n, t])
	for c in n.get_children():
		_walk(c, t, out)


static func _mat_name(mesh: Mesh, s: int) -> String:
	var m := mesh.surface_get_material(s)
	return m.resource_name if m else ""


## Rotation that turns a tyre's own axle onto the car's x axis (identity when
## it's already within half a degree). The axle is the tyre's direction of least
## spread: the smallest-eigenvalue eigenvector of its vertex covariance.
static func _square_up(points: PackedVector3Array, centre: Vector3) -> Basis:
	if points.size() < 12:
		return Basis()
	var xx := 0.0
	var yy := 0.0
	var zz := 0.0
	var xy := 0.0
	var xz := 0.0
	var yz := 0.0
	for p in points:
		var d := p - centre
		xx += d.x * d.x
		yy += d.y * d.y
		zz += d.z * d.z
		xy += d.x * d.y
		xz += d.x * d.z
		yz += d.y * d.z
	var tr := xx + yy + zz
	# Power iteration on (tr·I − C): its largest eigenvector is C's smallest.
	var v := Vector3.RIGHT
	for i in 40:
		var w := Vector3((tr - xx) * v.x - xy * v.y - xz * v.z,
			-xy * v.x + (tr - yy) * v.y - yz * v.z,
			-xz * v.x - yz * v.y + (tr - zz) * v.z)
		if w.length() < 1e-9:
			return Basis()
		v = w.normalized()
	if v.x < 0.0:
		v = -v
	if v.angle_to(Vector3.RIGHT) < deg_to_rad(0.5):
		return Basis()
	return Basis(Quaternion(v, Vector3.RIGHT))


static func _commit(mesh: ArrayMesh, b: Array, offset: Vector3, rot := Basis()) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos: PackedVector3Array = b[1]
	var nrm: PackedVector3Array = b[2]
	var uv: PackedVector2Array = b[3]
	for k in pos.size():
		st.set_normal(rot * nrm[k])
		st.set_uv(uv[k])
		st.add_vertex(rot * (pos[k] + offset))
	var mat = b[0]
	if mat is BaseMaterial3D and mat.normal_enabled:
		st.generate_tangents()
	st.index()
	st.commit(mesh)
