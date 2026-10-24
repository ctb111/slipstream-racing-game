class_name GxProps
extends RefCounted
## Real CC0 models (Poly Haven, assets/industrial/*.glb) as cheap MultiMeshes,
## plus procedural props shared by the industrial pieces (pallets, forklift,
## tractor, shipping containers, hay bales). Used by GxWarehouse / GxIndustrial.
##
##   GxProps.scatter(holder, "Barrel_01", [xf1, xf2], 160.0)   # one draw per surface
##   GxProps.pallet(g, Vector3(2, 0, 14), 0.3)                  # into a GxGeo
##   GxProps.forklift(g, Transform3D(Basis(), Vector3(0, 0, 14)))

const DIR := "res://assets/industrial/%s.glb"

static var _models := {}
## Largest dimension in metres (Poly Haven metadata).
const SIZE_M := {wooden_crate_01 = 0.83, wooden_crate_02 = 1.17, Barrel_01 = 0.88, barrel_03 = 0.93,
	steel_frame_shelves_01 = 2.14, hanging_industrial_lamp = 1.36, old_tyre = 0.6, propane_tank = 0.55,
	utility_box_01 = 1.12, security_light = 0.53, cardboard_box_01 = 0.52, cement_bag = 0.7,
	covered_car = 4.38, concrete_road_barrier = 1.55, metal_trash_can = 1.85, modular_chainlink_fence = 8.12,
	exterior_aircon_unit = 1.8, hand_truck = 1.4}
static var _mats := {}


## Merged mesh (one surface per material) of a glb, cached. null if missing.
static func model(id: String) -> ArrayMesh:
	if _models.has(id):
		return _models[id]
	var path := id if id.begins_with("res://") else DIR % id
	var out: ArrayMesh = null
	if ResourceLoader.exists(path):
		var root: Node = (load(path) as PackedScene).instantiate()
		var groups := {}
		_collect(root, Transform3D.IDENTITY, groups)
		out = _build(groups)
		# Some exports come in at the wrong scale: fit the largest side to the
		# real size from Poly Haven's metadata.
		var want: float = SIZE_M.get(id, 0.0)
		var have := out.get_aabb().size
		var big := maxf(have.x, maxf(have.y, have.z))
		if want > 0.0 and big > 0.0 and absf(big / want - 1.0) > 0.25:
			groups.clear()
			_collect(root, Transform3D(Basis().scaled(Vector3.ONE * want / big), Vector3.ZERO), groups)
			out = _build(groups)
		root.free()
		if id == "modular_chainlink_fence":
			_fix_wire(out)
	_models[id] = out
	return out


## The 1k glTF of the fence ships the wire colour as JPG (no alpha): give it the
## RGBA texture (diff + Poly Haven's wire_alpha map, tools/merge_alpha.gd) and an alpha cutout.
static func _fix_wire(mesh: ArrayMesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as StandardMaterial3D
		if m == null or not m.resource_name.contains("wire"):
			continue
		var w := m.duplicate() as StandardMaterial3D
		const RGBA := "res://assets/industrial/fence_wire_rgba.png"
		if ResourceLoader.exists(RGBA):
			w.albedo_texture = load(RGBA)
			w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			w.alpha_scissor_threshold = 0.5
			w.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		else: # fallback: faint see-through mesh rather than a black slab
			w.albedo_texture = null
			w.albedo_color = Color(0.55, 0.57, 0.56, 0.22)
			w.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		w.cull_mode = BaseMaterial3D.CULL_DISABLED
		w.metallic = 0.6
		w.roughness = 0.5
		mesh.surface_set_material(i, w)


static func _build(groups: Dictionary) -> ArrayMesh:
	var out := ArrayMesh.new()
	if true:
		for m: Material in groups:
			var st: SurfaceTool = groups[m]
			out = st.commit(out)
			out.surface_set_material(out.get_surface_count() - 1, m)
	return out


static func _collect(n: Node, xf: Transform3D, groups: Dictionary) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for s in mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				if m == null:
					m = StandardMaterial3D.new()
				if not groups.has(m):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[m] = st
				(groups[m] as SurfaceTool).append_from(mesh, s, t)
	for ch in n.get_children():
		_collect(ch, t, groups)


## One MultiMeshInstance3D of model `id` at world transforms `xfs`.
static func scatter(c: Node3D, id: String, xfs: Array, vis_end := 160.0, shadows := false) -> MultiMeshInstance3D:
	var mesh := model(id)
	if mesh == null or xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Gx_" + id.get_file().get_basename()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		var aabb := mm.get_aabb()
		mmi.visibility_range_end = vis_end + aabb.size.length() * 0.5
		mmi.visibility_range_end_margin = vis_end * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # dissolve over the margin, no pop
	c.add_child(mmi)
	return mmi


## Material variants for GxGeo meshes: "in_<type>" = Mats type with no rain /
## snow (indoors), "emit" = cool fluorescent diffuser, "emit_warm", "sky" =
## translucent roof light, "rock", "hay", "yellow" (floor paint), "black_rubber".
static func material(type: String) -> Material:
	if _mats.has(type):
		return _mats[type]
	var m: Material
	if type.begins_with("in_"):
		var base := Mats.mat(type.substr(3), Color.WHITE, false) as ShaderMaterial
		var d := base.duplicate() as ShaderMaterial
		d.set_shader_parameter("wet", 0.0)
		d.set_shader_parameter("snow", 0.0)
		d.set_shader_parameter("streaks", 0.0)
		m = d
	elif type == "emit_dim": # back-lit interiors behind glass, screens
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(1.0, 0.92, 0.8)
		s.emission_enabled = true
		s.emission = Color(1.0, 0.9, 0.75)
		s.emission_energy_multiplier = 1.4 if Car.night else 0.7
		m = s
	elif type == "amber_flash": # roadworks warning lamps: blink, phase from vertex colour .r
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
void fragment() {
	float on = step(0.0, sin(TIME * 6.0 + COLOR.r * 6.2832));
	ALBEDO = vec3(0.9, 0.5, 0.05);
	ROUGHNESS = 0.3;
	EMISSION = vec3(1.0, 0.55, 0.05) * on * mix(2.0, 9.0, night);
}"""
		sm.shader = sh
		sm.set_shader_parameter("night", 1.0 if Car.night else 0.0)
		m = sm
	elif type == "emit" or type == "emit_warm" or type == "emit_sodium":
		var s := StandardMaterial3D.new()
		var col := Color(0.92, 0.97, 1.0)
		if type == "emit_warm":
			col = Color(1.0, 0.82, 0.55)
		elif type == "emit_sodium":
			col = Color(1.0, 0.62, 0.25)
		s.albedo_color = col
		s.emission_enabled = true
		s.emission = col
		s.emission_energy_multiplier = 5.0
		s.roughness = 0.4
		m = s
	elif type == "sky":
		var s := StandardMaterial3D.new()
		s.albedo_color = Color(0.86, 0.9, 0.9, 0.62)
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.emission_enabled = true
		s.emission = Color(0.85, 0.9, 0.95)
		s.emission_energy_multiplier = 0.08 if Car.night else 0.9
		s.roughness = 0.3
		s.vertex_color_use_as_albedo = true
		m = s
	elif type == "rock" or type == "hay":
		var s := StandardMaterial3D.new()
		if type == "rock":
			s.albedo_texture = load("res://assets/themes/cliff_side/cliff_side_diff_1k.jpg")
			s.normal_texture = load("res://assets/themes/cliff_side/cliff_side_nor_gl_1k.jpg")
			s.uv1_scale = Vector3(0.12, 0.12, 0.12)
			s.roughness = 0.9
		else:
			s.albedo_texture = load("res://assets/industrial/hay/hay_diff.jpg")
			s.normal_texture = load("res://assets/industrial/hay/hay_nor_gl.jpg")
			s.uv1_scale = Vector3(0.7, 0.7, 0.7)
			s.roughness = 0.95
			s.albedo_color = Color(1.0, 0.93, 0.78)
		s.normal_enabled = true
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.uv1_triplanar = true
		s.uv1_world_triplanar = true
		s.vertex_color_use_as_albedo = true
		s.vertex_color_is_srgb = true
		m = s
	elif type == "fence_wire": # chain-link mesh (Poly Haven fence wire + alpha), 1 tile per metre
		var s := StandardMaterial3D.new()
		s.albedo_texture = load("res://assets/industrial/fence_wire_rgba.png")
		s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		s.alpha_scissor_threshold = 0.5
		s.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		s.cull_mode = BaseMaterial3D.CULL_DISABLED
		s.uv1_triplanar = true
		s.uv1_world_triplanar = true
		s.uv1_scale = Vector3(0.8, 0.8, 0.8)
		s.metallic = 0.6
		s.roughness = 0.45
		s.albedo_color = Color(0.85, 0.87, 0.86)
		m = s
	elif type == "yellow" or type == "black_rubber" or type == "white_paint":
		var s := StandardMaterial3D.new()
		s.albedo_color = {yellow = Color(0.85, 0.62, 0.08), black_rubber = Color(0.03, 0.03, 0.03),
			white_paint = Color(0.8, 0.8, 0.76)}[type]
		s.roughness = 0.75 if type != "black_rubber" else 0.9
		s.vertex_color_use_as_albedo = true
		s.vertex_color_is_srgb = true
		m = s
	else:
		m = Mats.mat(type, Color.WHITE, false)
	_mats[type] = m
	return m


## Commit a GxGeo into `c`, then swap in GxProps materials for the custom
## types (in_*, emit*, sky, rock, hay, yellow, ...). Returns the StaticBody (or null).
static func commit(g: GxGeo, c: Node3D, node_name: String, vis_end := 700.0, shadows := true) -> StaticBody3D:
	var before := c.get_child_count()
	g.commit(c, node_name, vis_end, shadows)
	var body: StaticBody3D = null
	for i in range(before, c.get_child_count()):
		var ch := c.get_child(i)
		if ch is MeshInstance3D:
			var mat := String(ch.name).trim_prefix(node_name + "_")
			if mat.begins_with("in_") or mat.begins_with("emit") or mat in ["sky", "rock", "hay", "yellow", "black_rubber", "white_paint", "fence_wire", "amber_flash"]:
				(ch as MeshInstance3D).material_override = material(mat)
			if mat.begins_with("emit") or mat == "sky" or mat == "yellow":
				(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif ch is StaticBody3D:
			body = ch
	return body


# ------------------------------------------------------------- procedural props

## Euro pallet 1.2 x 0.8 x 0.144 at local `p` (bottom centre), yaw `rot` (radians).
static func pallet(g: GxGeo, p: Vector3, rot := 0.0, mat := "in_wood") -> void:
	var b := Basis(Vector3.UP, rot)
	var prev := g.col
	g.col = prev * Color(1.0, 0.92, 0.8)
	for k in 3: # blocks + bottom boards
		var z := (k - 1) * 0.36
		g.box(mat, p + b * Vector3(0, 0.011, z), Vector3(1.2, 0.022, 0.1), 0.0, b)
		for i in 3:
			g.box(mat, p + b * Vector3((i - 1) * 0.53, 0.061, z), Vector3(0.145, 0.078, 0.1), 0.0, b)
		g.box(mat, p + b * Vector3(0, 0.111, z), Vector3(1.2, 0.022, 0.1), 0.0, b)
	for i in 5: # top deck boards
		var x := (i - 2) * 0.27
		g.box(mat, p + b * Vector3(x, 0.133, 0), Vector3(0.12 if i % 4 != 0 else 0.145, 0.022, 0.8), 0.0, b)
	g.col = prev


## A palletised load on a pallet: cardboard boxes, sacks or a shrink-wrapped block.
static func pallet_load(g: GxGeo, p: Vector3, rot: float, rng: RandomNumberGenerator, max_h := 1.4, indoor := true) -> void:
	var pre := "in_" if indoor else ""
	pallet(g, p, rot, pre + "wood")
	var b := Basis(Vector3.UP, rot)
	var top := p + Vector3.UP * 0.144
	var kind := rng.randi() % 4
	var prev := g.col
	if kind == 0: # stacked cartons
		var layers := rng.randi_range(2, maxi(2, int(max_h / 0.36)))
		var tint := Color(0.78, 0.6, 0.4) * rng.randf_range(0.85, 1.05)
		for l in layers:
			for i in 2:
				for j in 2:
					if l == layers - 1 and rng.randf() < 0.3:
						continue
					g.col = tint * rng.randf_range(0.88, 1.0)
					g.box(pre + "canvas", top + b * Vector3((i - 0.5) * 0.6, l * 0.36 + 0.175, (j - 0.5) * 0.4), Vector3(0.58, 0.35, 0.38), 0.0, b)
	elif kind == 1: # shrink-wrapped block
		var h := rng.randf_range(0.8, max_h)
		g.col = [Color(0.85, 0.85, 0.82), Color(0.25, 0.4, 0.62), Color(0.6, 0.2, 0.15), Color(0.82, 0.7, 0.3)][rng.randi() % 4]
		g.box(pre + "painted_metal", top + Vector3.UP * h * 0.5, Vector3(1.18, h, 0.78), 0.05, b)
	elif kind == 2: # sacks
		g.col = Color(0.82, 0.8, 0.72)
		for l in 4:
			for i in 2:
				var off := Vector3((i - 0.5) * 0.58, l * 0.16 + 0.08, 0.0) if l % 2 == 0 else Vector3(0.0, l * 0.16 + 0.08, (i - 0.5) * 0.38)
				var sz := Vector3(0.56, 0.15, 0.78) if l % 2 == 0 else Vector3(1.16, 0.15, 0.37)
				g.box(pre + "canvas", top + b * off, sz, 0.03, b)
	else: # crates
		g.col = Color(0.75, 0.62, 0.45)
		g.box(pre + "wood", top + Vector3.UP * 0.4, Vector3(1.15, 0.8, 0.76), 0.0, b)
		for s: float in [-1.0, 1.0]:
			g.col = Color(0.6, 0.48, 0.34)
			g.box(pre + "wood", top + b * Vector3(s * 0.56, 0.4, 0), Vector3(0.06, 0.82, 0.8), 0.0, b)
	g.col = prev


## Counterbalance forklift (~3.4 m long incl. forks, 2.2 m tall guard) at local xf, forks to +x.
static func forklift(g: GxGeo, xf: Transform3D, paint := Color(0.86, 0.6, 0.08), fork_h := 0.15, indoor := true) -> void:
	var pre := "in_" if indoor else ""
	var b := xf.basis
	var o := xf.origin
	var P := func(v: Vector3) -> Vector3: return o + b * v
	var prev := g.col
	# chassis + counterweight (rounded back)
	g.col = paint
	g.box(pre + "painted_metal", P.call(Vector3(0.0, 0.62, 0)), Vector3(1.9, 0.62, 1.1), 0.08, b)
	g.col = paint * 0.9
	g.box(pre + "painted_metal", P.call(Vector3(-0.85, 0.75, 0)), Vector3(0.55, 0.95, 1.12), 0.18, b)
	g.col = Color(0.12, 0.12, 0.12)
	g.box(pre + "painted_metal", P.call(Vector3(-1.13, 0.48, 0)), Vector3(0.08, 0.3, 1.0), 0.03, b) # rear bumper
	g.box(pre + "painted_metal", P.call(Vector3(0.0, 0.94, 0)), Vector3(1.2, 0.05, 1.05), 0.0, b) # floor plate
	# hood + seat
	g.col = paint
	g.box(pre + "painted_metal", P.call(Vector3(-0.42, 1.08, 0)), Vector3(0.75, 0.3, 0.95), 0.08, b)
	g.col = Color(0.08, 0.08, 0.08)
	g.box(pre + "rubber", P.call(Vector3(-0.42, 1.3, 0)), Vector3(0.45, 0.12, 0.48), 0.04, b)
	g.box(pre + "rubber", P.call(Vector3(-0.64, 1.58, 0)), Vector3(0.1, 0.5, 0.46), 0.04, b)
	# steering column + wheel
	g.bar(pre + "steel", P.call(Vector3(0.35, 1.0, 0)), P.call(Vector3(0.12, 1.55, 0)), 0.03)
	g.tube(pre + "rubber", [P.call(Vector3(0.1, 1.56, -0.18)), P.call(Vector3(0.1, 1.6, 0)), P.call(Vector3(0.1, 1.56, 0.18))], 0.025, 6)
	# overhead guard
	g.col = Color(0.1, 0.1, 0.1)
	for zz: float in [-0.48, 0.48]:
		g.tube(pre + "painted_metal", [P.call(Vector3(-0.95, 1.0, zz)), P.call(Vector3(-0.8, 2.15, zz)), P.call(Vector3(0.45, 2.2, zz)), P.call(Vector3(0.55, 1.0, zz))], 0.04, 6, false)
	for i in 6:
		var xx := lerpf(-0.75, 0.4, i / 5.0)
		g.box(pre + "painted_metal", P.call(Vector3(xx, 2.2, 0)), Vector3(0.05, 0.04, 1.0), 0.0, b)
	# mast: two uprights, cross members, carriage, forks
	g.col = Color(0.16, 0.16, 0.17)
	for zz: float in [-0.36, 0.36]:
		g.box(pre + "steel", P.call(Vector3(0.98, 1.25, zz)), Vector3(0.1, 2.35, 0.08), 0.01, b)
		g.box(pre + "steel", P.call(Vector3(1.05, 1.25, zz * 0.82)), Vector3(0.08, 2.35, 0.06), 0.01, b)
	g.box(pre + "steel", P.call(Vector3(0.98, 2.38, 0)), Vector3(0.1, 0.1, 0.8), 0.0, b)
	g.box(pre + "steel", P.call(Vector3(0.98, 0.55, 0)), Vector3(0.1, 0.1, 0.8), 0.0, b)
	g.box(pre + "steel", P.call(Vector3(1.12, fork_h + 0.45, 0)), Vector3(0.06, 0.6, 0.9), 0.01, b) # carriage
	for zz: float in [-0.3, 0.3]:
		g.box(pre + "steel", P.call(Vector3(1.17, fork_h + 0.4, zz)), Vector3(0.05, 0.75, 0.12), 0.0, b)
		g.box(pre + "steel", P.call(Vector3(1.75, fork_h + 0.025, zz)), Vector3(1.15, 0.045, 0.12), 0.006, b)
	# lift chains / hoses
	g.bar(pre + "rubber", P.call(Vector3(1.0, 0.6, 0.12)), P.call(Vector3(1.0, 2.3, 0.12)), 0.015, 4)
	# wheels
	for w in [[0.55, 0.33, 0.62, 0.22], [-0.75, 0.27, 0.6, 0.18]]:
		for s: float in [-1.0, 1.0]:
			_wheel(g, P.call(Vector3(w[0], w[1], s * w[2])), b * Vector3(0, 0, 1), w[1], w[3], pre)
	# amber beacon + warning
	g.col = Color(1.0, 0.5, 0.05)
	g.box(pre + "painted_metal", P.call(Vector3(-0.7, 2.28, 0.3)), Vector3(0.1, 0.12, 0.1), 0.03, b)
	g.col = prev


## Tyre + rim, axis `ax` (local), radius r, width w.
static func _wheel(g: GxGeo, c: Vector3, ax: Vector3, r: float, w: float, pre := "", rim := Color(0.55, 0.55, 0.5)) -> void:
	var a := ax.normalized()
	var prev := g.col
	g.col = Color(0.06, 0.06, 0.06)
	var n := 14
	var pts := []
	var radii := []
	for k in [[-0.5, 0.72], [-0.5, 0.92], [-0.42, 1.0], [0.42, 1.0], [0.5, 0.92], [0.5, 0.72]]:
		pts.append(c + a * (k[0] * w))
		radii.append(r * k[1])
	g.tube(pre + "rubber", pts, r, n, false, radii)
	g.col = rim
	g.tube(pre + "painted_metal", [c - a * w * 0.38, c + a * w * 0.38], r * 0.68, n, true)
	g.col = prev


## Farm tractor (~4 m long, 2.8 m tall cab) at local xf, nose to +x.
static func tractor(g: GxGeo, xf: Transform3D, paint := Color(0.13, 0.36, 0.14), indoor := true) -> void:
	var pre := "in_" if indoor else ""
	var b := xf.basis
	var o := xf.origin
	var P := func(v: Vector3) -> Vector3: return o + b * v
	var prev := g.col
	g.col = paint
	g.box(pre + "painted_metal", P.call(Vector3(1.05, 1.15, 0)), Vector3(1.9, 0.75, 0.72), 0.12, b) # bonnet
	g.col = Color(0.1, 0.1, 0.1)
	g.box(pre + "painted_metal", P.call(Vector3(2.02, 1.12, 0)), Vector3(0.06, 0.62, 0.62), 0.02, b) # grille
	g.box(pre + "steel", P.call(Vector3(0.7, 0.72, 0)), Vector3(2.4, 0.35, 0.55), 0.04, b) # frame / engine block
	g.col = paint * 0.85
	g.box(pre + "painted_metal", P.call(Vector3(-0.55, 1.0, 0)), Vector3(1.1, 0.7, 1.1), 0.08, b) # transmission
	for s: float in [-1.0, 1.0]: # rear mudguards
		g.col = paint
		g.box(pre + "painted_metal", P.call(Vector3(-0.75, 1.62, s * 0.88)), Vector3(1.5, 0.06, 0.6), 0.02, b)
		g.box(pre + "painted_metal", P.call(Vector3(-0.05, 1.3, s * 0.88)), Vector3(0.12, 0.62, 0.6), 0.02, b)
	# cab: four posts, roof, glass
	g.col = Color(0.12, 0.12, 0.12)
	for px: float in [-1.3, -0.15]:
		for pz: float in [-0.62, 0.62]:
			g.box(pre + "painted_metal", P.call(Vector3(px, 2.15, pz)), Vector3(0.07, 1.6, 0.07), 0.0, b)
	g.col = paint
	g.box(pre + "painted_metal", P.call(Vector3(-0.72, 2.98, 0)), Vector3(1.45, 0.1, 1.42), 0.04, b)
	g.col = Color(0.5, 0.55, 0.55)
	g.box("glass", P.call(Vector3(-0.72, 2.2, 0)), Vector3(1.12, 1.45, 1.2), 0.0, b)
	# exhaust stack
	g.col = Color(0.15, 0.15, 0.15)
	g.bar(pre + "steel", P.call(Vector3(0.45, 1.5, 0.3)), P.call(Vector3(0.45, 2.85, 0.3)), 0.05)
	# wheels: big rears, small fronts
	for s: float in [-1.0, 1.0]:
		_wheel(g, P.call(Vector3(-0.75, 0.78, s * 0.88)), b * Vector3(0, 0, 1), 0.78, 0.48, pre, Color(0.75, 0.6, 0.1))
		_wheel(g, P.call(Vector3(1.5, 0.48, s * 0.78)), b * Vector3(0, 0, 1), 0.48, 0.3, pre, Color(0.75, 0.6, 0.1))
	g.col = prev


## Round hay bale (1.5 m dia, 1.2 m wide) lying on its side, axis along local `ax`.
static func round_bale(g: GxGeo, c: Vector3, ax: Vector3, r := 0.75, w := 1.2) -> void:
	var a := ax.normalized()
	var pts := []
	var radii := []
	for k in [[-0.5, 0.0], [-0.5, 0.82], [-0.46, 0.96], [-0.35, 1.0], [0.35, 1.0], [0.46, 0.96], [0.5, 0.82], [0.5, 0.0]]:
		pts.append(c + a * (k[0] * w))
		radii.append(maxf(r * k[1], 0.01))
	g.tube("hay", pts, r, 16, false, radii)


## Square bale (0.9 x 0.45 x 0.36 m small, or 2.4 x 1.2 x 0.9 m big) with twine.
static func square_bale(g: GxGeo, c: Vector3, size: Vector3, rot := 0.0) -> void:
	var b := Basis(Vector3.UP, rot)
	g.box("hay", c, size, minf(size.y, size.z) * 0.12, b)


## Shipping container (ISO, 6.06 or 12.19 m) with corrugated walls, corner
## posts, castings and cargo doors at +x. `xf` = bottom centre, local frame of `g`.
static func container(g: GxGeo, xf: Transform3D, long := true, paint := Color(0.55, 0.2, 0.14), dirt := 0.0) -> void:
	var L := 12.19 if long else 6.06
	var W := 2.44
	var H := 2.59
	var b := xf.basis
	var o := xf.origin
	var P := func(v: Vector3) -> Vector3: return o + b * v
	var prev := g.col
	var pc := paint.lerp(Color(0.42, 0.4, 0.37), 0.28).lerp(Color(0.33, 0.24, 0.17), dirt)
	g.col = pc
	# corrugated long sides: trapezoid profile, period 0.28 m
	var per := 0.278
	var nper := int((L - 0.3) / per)
	var x0 := -nper * per * 0.5
	for s: float in [-1.0, 1.0]:
		var zf := s * W * 0.5
		for i in nper:
			var xa := x0 + i * per
			var xs := [xa, xa + per * 0.18, xa + per * 0.5, xa + per * 0.68, xa + per]
			var zs := [0.0, -0.036, -0.036, 0.0, 0.0]
			for k in 4:
				var p0 := Vector3(xs[k], 0.12, zf + s * zs[k])
				var p1 := Vector3(xs[k + 1], 0.12, zf + s * zs[k + 1])
				var a0: Vector3 = P.call(p0)
				var a1: Vector3 = P.call(p1)
				var up := b * Vector3(0, H - 0.27, 0)
				if s > 0:
					g.quad("painted_metal", a0, a1, a1 + up, a0 + up)
				else:
					g.quad("painted_metal", a1, a0, a0 + up, a1 + up)
	# front end (closed, -x) and roof
	g.box("painted_metal", P.call(Vector3(-L * 0.5 + 0.06, H * 0.5, 0)), Vector3(0.08, H - 0.2, W - 0.16), 0.0, b)
	g.box("painted_metal", P.call(Vector3(0, H - 0.06, 0)), Vector3(L - 0.2, 0.06, W - 0.06), 0.0, b)
	# doors (+x): two leaves with locking bars and hinges
	g.col = pc * 0.95
	for s: float in [-1.0, 1.0]:
		g.box("painted_metal", P.call(Vector3(L * 0.5 - 0.06, H * 0.5, s * W * 0.25)), Vector3(0.06, H - 0.26, W * 0.5 - 0.06), 0.008, b)
		for k in 2:
			var zz := s * W * (0.1 + 0.27 * k)
			g.col = Color(0.3, 0.3, 0.3).lerp(pc, 0.3)
			g.bar("steel", P.call(Vector3(L * 0.5 - 0.01, 0.15, zz)), P.call(Vector3(L * 0.5 - 0.01, H - 0.15, zz)), 0.018, 5)
			g.box("steel", P.call(Vector3(L * 0.5 + 0.01, 1.2, zz + s * 0.08)), Vector3(0.03, 0.05, 0.18), 0.0, b)
	# frame: bottom/top rails, corner posts, castings
	g.col = pc * 0.8
	for s: float in [-1.0, 1.0]:
		g.box("painted_metal", P.call(Vector3(0, 0.08, s * (W * 0.5 - 0.04))), Vector3(L - 0.2, 0.16, 0.1), 0.01, b)
		g.box("painted_metal", P.call(Vector3(0, H - 0.07, s * (W * 0.5 - 0.04))), Vector3(L - 0.2, 0.12, 0.1), 0.01, b)
		for e: float in [-1.0, 1.0]:
			g.box("painted_metal", P.call(Vector3(e * (L * 0.5 - 0.08), H * 0.5, s * (W * 0.5 - 0.08))), Vector3(0.16, H - 0.1, 0.16), 0.015, b)
			for yy: float in [0.06, H - 0.06]:
				g.col = Color(0.18, 0.17, 0.16)
				g.box("painted_metal", P.call(Vector3(e * (L * 0.5 - 0.09), yy, s * (W * 0.5 - 0.09))), Vector3(0.18, 0.12, 0.18), 0.01, b)
				g.col = pc * 0.8
	g.col = prev
