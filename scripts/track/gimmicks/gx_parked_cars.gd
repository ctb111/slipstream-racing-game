class_name GxParkedCars
extends RefCounted
## Spectator cars parked along a verge or in a field: the game's own car
## models (no physics, LODs, one MultiMesh per model) in everyday faded 80s /
## 90s colours, dusty and muddy low down, parked at casual angles following
## the ground, with their owners standing about.
##
##   GxParkedCars.place(c, Gx.frame(c, 1500.0, Gx.LEFT, 4.0), {count = 8})
##
## Frame: Gx.frame (x along the track, +z away from the road). Cars go in a
## row along x centred on the origin, the row's near edge at z ~ 1 m.
## Options: count (6), spacing (3.2 m between cars side by side), layout
##   "angled" (nose in, angled; default) | "parallel" (along the verge) |
##   "field" (loose rows), people (true), dirt (0..1 mean amount, 0.55),
##   models (Array of CarCatalog ids), variety (models used in this row, 2),
##   seed (int).

## Default set; each model costs ~0.3-0.9 s to load the first time on a track
## (shared with racing cars of the same model).
const MODELS := ["bmw_e30_m3", "toyota_ae86", "mazda_rx7_fc", "porsche930"]
## Everyday paint of the era (sRGB): whites, silvers, reds, dark blues, greens, beige, burgundy, black.
const PAINTS := [Color(0.80, 0.80, 0.77), Color(0.88, 0.87, 0.82), Color(0.55, 0.56, 0.57), Color(0.62, 0.08, 0.06),
	Color(0.10, 0.15, 0.30), Color(0.12, 0.25, 0.18), Color(0.62, 0.56, 0.42), Color(0.35, 0.06, 0.08),
	Color(0.06, 0.06, 0.07), Color(0.25, 0.32, 0.40), Color(0.70, 0.55, 0.12), Color(0.38, 0.40, 0.33)]
const JACKETS := [Color(0.10, 0.10, 0.12), Color(0.13, 0.18, 0.32), Color(0.55, 0.10, 0.08), Color(0.22, 0.28, 0.20),
	Color(0.85, 0.42, 0.05), Color(0.40, 0.40, 0.42), Color(0.08, 0.25, 0.45)]
const VIS := 450.0 # far LODs (lod_bias) keep rows of parked cars cheap; no pop at 200 m

static var _built := {} ## model id -> {mesh, shadow, lift, half}
static var _paint_shader: Shader


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(opts.get("seed", hash(xf.origin.snapped(Vector3.ONE) + Vector3(7, 0, 0))))
	var count := int(opts.get("count", 6))
	var spacing := float(opts.get("spacing", 3.2))
	var layout := str(opts.get("layout", "angled"))
	var dirt := float(opts.get("dirt", 0.55))
	var models: Array = opts.get("models", MODELS)
	var snow := float(opts.get("snow", _weather_snow(c)))
	var people: bool = GxCamp._b(opts.get("people", true))
	var avail := models.filter(func(m): return CarModel.available(m))
	if avail.is_empty():
		return
	# a few models per row (each model is one MultiMesh with ~8-12 surfaces = draw calls)
	var variety := clampi(int(opts.get("variety", 2)), 1, avail.size())
	var pool := []
	var shuffled := avail.duplicate()
	for i in shuffled.size():
		var j := r.randi_range(i, shuffled.size() - 1)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp
	pool = shuffled.slice(0, variety)
	avail = pool
	var root := Node3D.new()
	root.name = "GxParkedCars"
	c.add_child(root)
	var per := {} ## model -> [xfs, customs]
	var ppl_x: Array[Transform3D] = []
	var ppl_c: Array[Color] = []
	var ppl_u: Array[Color] = []
	var span := 0.0
	var blobs: Array = [] ## ground transforms under each car
	for i in count:
		var model: String = avail[r.randi() % avail.size()]
		var b := _build(model)
		var lx: float
		var lz: float
		var yaw: float
		match layout:
			"parallel":
				var step := float(b.length) + r.randf_range(0.8, 2.5)
				lx = span + step * 0.5 - (count * 5.6) * 0.5
				span += step
				lz = 1.2 + r.randf_range(0.0, 0.5)
				yaw = PI * 0.5 + r.randf_range(-0.12, 0.12) + (PI if r.randf() < 0.2 else 0.0)
			"field":
				var row := i % 2
				lx = (int(i / 2) - (count / 2) * 0.5) * spacing + r.randf_range(-0.6, 0.6)
				lz = 3.2 + row * 6.0 + r.randf_range(-0.6, 0.6)
				yaw = (0.0 if row == 0 else PI) + r.randf_range(-0.35, 0.35)
			_:
				lx = (i - (count - 1) * 0.5) * spacing + r.randf_range(-0.35, 0.35)
				lz = float(b.length) * 0.5 + 0.9 + r.randf_range(-0.3, 0.6)
				yaw = r.randf_range(-0.28, 0.28) + (PI if r.randf() < 0.25 else 0.0) # mostly nose to the road
		if r.randf() < 0.12 and layout != "parallel":
			continue # a gap in the row
		var p := xf * Vector3(lx, 0, lz)
		var basis := xf.basis * Basis(Vector3.UP, yaw)
		# sit on the terrain: height at the four wheels, pitch and roll from them
		var fwd := -basis.z
		var rt := basis.x
		var hl := float(b.length) * 0.36
		var hw := 0.72
		var yf := (Gx.ground(c, p + fwd * hl + rt * hw) + Gx.ground(c, p + fwd * hl - rt * hw)) * 0.5
		var yr := (Gx.ground(c, p - fwd * hl + rt * hw) + Gx.ground(c, p - fwd * hl - rt * hw)) * 0.5
		var yl := (Gx.ground(c, p + fwd * hl - rt * hw) + Gx.ground(c, p - fwd * hl - rt * hw)) * 0.5
		var yrr := (Gx.ground(c, p + fwd * hl + rt * hw) + Gx.ground(c, p - fwd * hl + rt * hw)) * 0.5
		var nf := (fwd * (2.0 * hl) + Vector3.UP * (yf - yr)).normalized()
		var sv := (rt * (2.0 * hw) + Vector3.UP * (yrr - yl)).normalized()
		var nu := sv.cross(nf).normalized()
		var nr := nf.cross(nu).normalized()
		var bas := Basis(nr, nu, -nf)
		var y := (yf + yr) * 0.5 + 0.02
		var t := Transform3D(bas, Vector3(p.x, y, p.z)) * Transform3D(Basis(), Vector3(0, b.lift, 0))
		blobs.append(Transform3D(bas, Vector3(p.x, y + 0.04, p.z)))
		if not per.has(model):
			per[model] = [[], []]
		per[model][0].append(t)
		var col: Color = PAINTS[r.randi() % PAINTS.size()]
		col = col.lerp(Color(0.42, 0.42, 0.40), r.randf_range(0.0, 0.12)) # sun-faded
		per[model][1].append(Color(col.r, col.g, col.b, clampf(dirt + r.randf_range(-0.3, 0.35), 0.05, 1.0)))
		Gx.reserve(c, p, float(b.length) * 0.6)
		if people and r.randf() < 0.55:
			# owner by the driver's door or leaning on the boot, chatting
			var side := -1.0 if r.randf() < 0.7 else 1.0
			var q := p + rt * side * 1.25 + fwd * r.randf_range(-0.6, 0.8)
			q.y = Gx.ground(c, q)
			var d := p - q
			ppl_x.append(Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z) + r.randf_range(-0.5, 0.5)), q))
			ppl_c.append(JACKETS[r.randi() % JACKETS.size()])
			ppl_u.append(Color(r.randf(), 0.0, 0.0, 0.0))
			if r.randf() < 0.4:
				var q2 := q + fwd * 1.0 + rt * side * 0.5
				q2.y = Gx.ground(c, q2)
				var d2 := q - q2
				ppl_x.append(Transform3D(Basis(Vector3.UP, atan2(-d2.x, -d2.z)), q2))
				ppl_c.append(JACKETS[r.randi() % JACKETS.size()])
				ppl_u.append(Color(r.randf(), 0.0, 0.0, 0.0))
	for model: String in per:
		var b := _build(model)
		var list: Array = per[model][0]
		var cus: Array = per[model][1]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = b.mesh if snow < 0.05 else _snowy(model, b.mesh, snow)
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, cus[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Cars_" + model
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.lod_bias = 0.35 # switch to the far LODs early
		mmi.visibility_range_end = VIS + mm.get_aabb().size.length() * 0.5
		mmi.visibility_range_end_margin = 20.0
		root.add_child(mmi)
	_blob_shadows(root, blobs)
	if not ppl_x.is_empty():
		root.add_child(GxCamp.limit(PeopleKit.crowd("CarOwners", PeopleKit.Role.SPECTATOR, ppl_x, ppl_c, ppl_u, false), 170.0))
	GxCamp.maybe_ab(root, xf * Vector3(-count * spacing * 0.6, 1.7, -5.0), xf * Vector3(0, 0.8, 3.0))


## One static mesh per model: body + the four wheels, surfaces merged by
## material, paint replaced by the dusty instance-coloured paint; with LODs.
static func _build(model: String) -> Dictionary:
	if _built.has(model):
		return _built[model]
	var t0 := Time.get_ticks_usec()
	var d := CarModel.data(model)
	var t1 := Time.get_ticks_usec()
	var groups := {} ## material -> SurfaceTool
	var order: Array = []
	var paint_mat := _paint_material(d)
	var add := func(mesh: Mesh, s: int, mat: Material, t: Transform3D) -> void:
		var key: Material = mat
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key] = st
			order.append(key)
		(groups[key] as SurfaceTool).append_from(mesh, s, t)
	var body: ArrayMesh = d.body
	for i in body.get_surface_count():
		var m: Material = d.surface_mats[i]
		if i == d.paint_surface:
			m = paint_mat
		add.call(body, i, m, Transform3D.IDENTITY)
	var hub_y := 0.0
	for w: Dictionary in d.wheels:
		hub_y += float(w.centre.y) * 0.25
		var wm: Mesh = w.mesh
		for s in wm.get_surface_count():
			var m: Material = w.mats[s] if s < w.mats.size() else wm.surface_get_material(s)
			add.call(wm, s, m, Transform3D(Basis(), w.centre))
	var mesh := ArrayMesh.new()
	for key: Material in order:
		var st: SurfaceTool = groups[key]
		var arr := st.commit_to_arrays()
		if (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, key)
	mesh = CarModel._with_lods(_decimate(mesh, TRI_BUDGET))
	var box: AABB = d.body_aabb
	var out := {mesh = mesh, shadow = d.shadow, lift = -(hub_y - float(d.wheel_radius)), length = box.size.z}
	_built[model] = out
	return out


## Triangles per parked car (the racing models are far denser): the base
## mesh is a meshoptimizer LOD of the merged car, picked per surface.
const TRI_BUDGET := 12000


static func _decimate(mesh: ArrayMesh, budget: int) -> ArrayMesh:
	var total := 0
	for s in mesh.get_surface_count():
		total += mesh.surface_get_array_index_len(s) / 3 if mesh.surface_get_array_index_len(s) > 0 else mesh.surface_get_array_len(s) / 3
	if total <= budget:
		return mesh
	var ratio := float(budget) / total
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_INDEX] == null:
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.index()
			arr = st.commit_to_arrays()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	var out := ArrayMesh.new()
	for s in im.get_surface_count():
		var arr := im.get_surface_arrays(s)
		var full: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var want := int(full.size() * ratio)
		var pick := full
		for l in im.get_surface_lod_count(s):
			var li := im.get_surface_lod_indices(s, l)
			if li.size() >= want and li.size() >= 36:
				pick = li # keep going: coarser LODs come later
			else:
				break
		arr[Mesh.ARRAY_INDEX] = pick
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, im.get_surface_material(s))
	return out


static var _blob_mat: StandardMaterial3D
## Soft dark contact shadow under each car (one MultiMesh, no shadow pass).
static func _blob_shadows(root: Node3D, xfs: Array) -> void:
	if xfs.is_empty():
		return
	if _blob_mat == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var u := (x + 0.5) / n * 2.0 - 1.0
				var v := (y + 0.5) / n * 2.0 - 1.0
				# rounded rectangle, car-shaped (long along v)
				var d := pow(pow(absf(u) / 0.9, 4.0) + pow(absf(v) / 0.95, 4.0), 0.25)
				img.set_pixel(x, y, Color(0, 0, 0, clampf((1.0 - d) * 2.2, 0.0, 0.8)))
		img.generate_mipmaps()
		_blob_mat = StandardMaterial3D.new()
		_blob_mat.albedo_texture = ImageTexture.create_from_image(img)
		_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_blob_mat.albedo_color = Color(0, 0, 0, 0.85)
		_blob_mat.disable_receive_shadows = true
	var q := PlaneMesh.new()
	q.size = Vector2(2.1, 4.9)
	q.material = _blob_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = xfs.size()
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "CarContactShadows"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 240.0 + mm.get_aabb().size.length() * 0.5
	root.add_child(mmi)


static func _weather_snow(c: Node3D) -> float:
	var wx = c.get("weather")
	if wx == null:
		return 0.0
	var pr = wx.get("preset")
	return float(pr.get("snow", 0.0)) if pr is Dictionary else 0.0


static var _snow_meshes := {}
## Same mesh, paint surface with a snowy copy of the paint material (shared per model + level).
static func _snowy(model: String, mesh: ArrayMesh, snow: float) -> ArrayMesh:
	var key := "%s_%.1f" % [model, snow]
	if _snow_meshes.has(key):
		return _snow_meshes[key]
	var m2: ArrayMesh = mesh.duplicate()
	for s in m2.get_surface_count():
		var mat := m2.surface_get_material(s)
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader == _paint_shader:
			var sm: ShaderMaterial = mat.duplicate()
			sm.set_shader_parameter("snow", snow)
			m2.surface_set_material(s, sm)
	_snow_meshes[key] = m2
	return m2


static func _paint_material(d: Dictionary) -> ShaderMaterial:
	if _paint_shader == null:
		_paint_shader = Shader.new()
		_paint_shader.code = """
shader_type spatial;
uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float ground_y = 0.0;
uniform float height = 1.3;
uniform float snow = 0.0;
varying vec3 mpos;
varying vec4 paint;
void vertex() {
	mpos = VERTEX;
	paint = INSTANCE_CUSTOM;
}
void fragment() {
	vec3 base = pow(paint.rgb, vec3(2.2));
	float dirt = paint.a;
	vec3 an = abs(NORMAL);
	float n = texture(noise_tex, mpos.xz * 0.45 + vec2(paint.r, paint.g) * 7.0).r * 0.5
		+ texture(noise_tex, vec2(mpos.x + mpos.z, mpos.y) * 0.9).r * 0.5;
	float h = clamp((mpos.y - ground_y) / height, 0.0, 1.0);
	float low = smoothstep(0.62, 0.1, h + (n - 0.5) * 0.35);           // mud splashed up the sills and arches
	float dust = dirt * (0.12 + 0.5 * n);                              // dust film everywhere
	vec3 dust_c = vec3(0.30, 0.26, 0.20);
	vec3 mud_c = vec3(0.07, 0.055, 0.04);
	vec3 col = mix(base, dust_c, clamp(dust * 0.6, 0.0, 0.45));
	float mud = clamp(low * dirt * (0.7 + 0.8 * n), 0.0, 1.0);
	col = mix(col, mud_c, mud);
	// settled snow on the upward faces (roof, bonnet, boot), patchy at the edges
	float up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
	float sn = snow * smoothstep(0.45, 0.8, up + (n - 0.5) * 0.35);
	col = mix(col, vec3(0.86, 0.88, 0.92), sn);
	ALBEDO = col;
	float grime = clamp(dust + mud, 0.0, 1.0);
	grime = max(grime, sn);
	ROUGHNESS = mix(0.32, 0.9, grime);
	METALLIC = mix(0.25, 0.0, grime);
	SPECULAR = 0.5;
	CLEARCOAT = 1.0 - grime;
	CLEARCOAT_ROUGHNESS = 0.15 + 0.5 * grime;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _paint_shader
	m.set_shader_parameter("noise_tex", load("res://assets/textures/car_dirt/dirt_noise.png"))
	var box: AABB = d.body_aabb
	var hub_y := 0.0
	for w: Dictionary in d.wheels:
		hub_y += float(w.centre.y) * 0.25
	m.set_shader_parameter("ground_y", hub_y - float(d.wheel_radius))
	m.set_shader_parameter("height", maxf(box.end.y - (hub_y - float(d.wheel_radius)), 0.8))
	return m
