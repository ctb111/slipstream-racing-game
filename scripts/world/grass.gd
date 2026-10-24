class_name Grass
extends RefCounted
## Wind-blown grass on the verges along the whole lap: crossed alpha cards cut
## from a photo atlas (Poly Haven grass, dandelion, celandine and weed scans,
## see assets/vegetation/CREDITS_vegetation.txt). Cards are grouped into ~3 m
## patches (one mesh = ~24 clumps) that are scattered as MultiMesh instances in
## chunks of ~40 m; each chunk only draws when the camera is close.

const CHUNK_SAMPLES := 20 ## track samples (2 m each) per chunk
const VISIBLE := 75.0
const ATLAS := "res://assets/vegetation/grass/grass_atlas.png"
const COLS := 8
const ROWS := 4
## World width (= height) in metres of each atlas cell as baked.
const SIZES := [0.323, 0.29, 0.284, 0.222, 0.192, 0.196, 0.189, 0.329, 0.291, 0.267, 0.324, 0.411, 0.333, 0.281, 0.226, 0.442,
	0.225, 0.206, 0.173, 0.262, 0.19, 0.36, 0.411, 0.224, 0.563, 1.01, 0.892, 0.584, 0.134, 0.221, 0.912, 0.781]
## Cells 0-15: grass clumps (9-11 and 15 dry), 16-20 flowers, 21-23 weeds,
## 24-31 forest floor (ferns, nettles).
const LUSH := [0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13, 14]
const DRY := [9, 10, 11, 15]
const FLOWERS := [16, 17, 18, 19, 20]
const WEEDS := [21, 22, 23, 28, 29]
const FERNS := [24, 25, 26, 27, 30, 31]


static func build(parent: Node3D, curve: Curve3D, terrain: Terrain, road_width: float, preset: Dictionary, noise: Texture2D) -> void:
	if OS.has_environment("VEG_OFF") or OS.has_environment("GRASS_OFF"):
		return
	var t0 := Time.get_ticks_msec()
	var snow: float = preset.snow
	var storm: bool = preset.wet > 0.5
	var mat := material(noise, 0.55 if storm else (0.3 if snow > 0.0 else 0.22), preset.wet, snow)
	mat.set_shader_parameter("gust_speed", 0.16 if storm else 0.06)
	var d: Variant = parent.get("def")
	var autumn: bool = d is Dictionary and d.get("theme", "") == "autumn"
	if autumn: # late-season verges: tired olive grass, straw-dry tufts
		mat.set_shader_parameter("tint", Vector3(0.88, 0.8, 0.5))
		mat.set_shader_parameter("dry_tint", Vector3(1.3, 0.95, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	# Patch variants: [flower share, weed share, dry share].
	var meshes: Array[ArrayMesh] = []
	var mixes := [[0.0, 0.02, 0.06], [0.05, 0.03, 0.1], [0.12, 0.03, 0.05], [0.02, 0.08, 0.22]]
	if autumn: # no flowers, much more dry grass
		mixes = [[0.0, 0.04, 0.3], [0.0, 0.06, 0.45], [0.01, 0.03, 0.25], [0.0, 0.1, 0.6]]
	for mix in mixes:
		meshes.append(patch_mesh(rng, 30, 1.4, mix[0], mix[1], mix[2]))

	var length := curve.get_baked_length()
	var n := int(length / 2.0)
	var centers: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var t := (curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))).normalized()
		centers.append(p)
		rights.append(t.cross(Vector3.UP).normalized())
	var corner := TrackBuilder._corner_factors(centers)
	var zones := Vegetation.zone_grid(parent.get_meta("no_trees", []), 10.0, 0.85)
	var half := road_width * 0.5
	var inner := half + TrackBuilder.CURB_WIDTH + 0.6
	var per_side := int((9 if snow > 0.0 else 28) * Game.grass_density())

	var total := 0
	for c0 in range(0, n, CHUNK_SAMPLES):
		for side: float in [-1.0, 1.0]:
			var xforms: Array[Transform3D] = []
			for i in range(c0, mini(c0 + CHUNK_SAMPLES, n)):
				# Skip the gravel traps on corner outsides.
				var gravel := TrackBuilder.GRAVEL_MAX * absf(corner[i]) if corner[i] * side > 0.0 else 0.0
				var from := inner + (gravel + 0.5 if gravel > 0.3 else 0.0)
				for k in per_side:
					# Densest along the road edge, thinning out towards the trees.
					var lat := side * (from + 0.3 + pow(rng.randf(), 2.2) * 30.0)
					var along := rng.randf_range(-1.0, 1.0)
					var p := centers[i] + rights[i] * lat + (centers[(i + 1) % n] - centers[i]) * along * 0.5
					if Vegetation.in_zone(zones, p, 10.0):
						continue
					var up := Vector3.UP
					if terrain:
						p.y = terrain.height_at(p.x, p.z) - 0.03
						var hx := terrain.height_at(p.x + 1.0, p.z) - p.y - 0.03
						var hz := terrain.height_at(p.x, p.z + 1.0) - p.y - 0.03
						up = Vector3(-hx, 1.0, -hz).normalized()
					var s := rng.randf_range(0.8, 1.2)
					var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
					b = Basis(Quaternion(Vector3.UP, up)) * b
					xforms.append(Transform3D(b, p))
			if xforms.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[(c0 / CHUNK_SAMPLES * 3 + int(side > 0)) % meshes.size()]
			mm.instance_count = xforms.size()
			total += xforms.size()
			var buf := PackedFloat32Array()
			buf.resize(xforms.size() * 12)
			for k in xforms.size():
				var x := xforms[k]
				var o := k * 12
				buf[o] = x.basis.x.x; buf[o + 1] = x.basis.y.x; buf[o + 2] = x.basis.z.x; buf[o + 3] = x.origin.x
				buf[o + 4] = x.basis.x.y; buf[o + 5] = x.basis.y.y; buf[o + 6] = x.basis.z.y; buf[o + 7] = x.origin.y
				buf[o + 8] = x.basis.x.z; buf[o + 9] = x.basis.y.z; buf[o + 10] = x.basis.z.z; buf[o + 11] = x.origin.z
			mm.buffer = buf
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Measured to the chunk's AABB centre: + its half-diagonal (+ patch
			# radius) keeps every patch that is not yet faded out by the shader.
			var lo := Vector2(INF, INF)
			var hi := -lo
			for x: Transform3D in xforms:
				lo = lo.min(Vector2(x.origin.x, x.origin.z))
				hi = hi.max(Vector2(x.origin.x, x.origin.z))
			mmi.visibility_range_end = VISIBLE + (hi - lo).length() * 0.5 + 4.0
			mmi.visibility_range_end_margin = 10.0
			parent.add_child(mmi)
	if OS.has_environment("VEG_DEBUG"):
		print("grass: %d patches of %d tris in %d ms" % [total, meshes[0].surface_get_array_index_len(0) / 3, Time.get_ticks_msec() - t0])


## The grass/flower card material (also used for ferns and weeds elsewhere).
static func material(noise: Texture2D, wind: float, wet := 0.0, snow := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	mat.set_shader_parameter("atlas", load(ATLAS))
	mat.set_shader_parameter("noise_tex", noise)
	mat.set_shader_parameter("wind_strength", wind)
	mat.set_shader_parameter("snow", snow)
	mat.set_shader_parameter("wet", wet)
	mat.set_shader_parameter("fade_start", VISIBLE - 35.0) # a wide dissolve (40-75 m); terrain.gdshader takes on a grass look over the same band
	mat.set_shader_parameter("fade_end", VISIBLE)
	return mat


## A patch of `count` clumps within `radius`, each two crossed cards picked
## from the atlas. Shares are the chance of a flower / weed / dry clump.
static func patch_mesh(rng: RandomNumberGenerator, count: int, radius: float, flowers: float, weeds: float, dry: float, scale := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in count:
		var x := rng.randf()
		var pick: Array = LUSH
		var grow := rng.randf_range(1.2, 1.9)
		if x < flowers:
			pick = FLOWERS
			grow = rng.randf_range(1.1, 1.5)
		elif x < flowers + weeds:
			pick = WEEDS
			grow = rng.randf_range(1.3, 1.9)
		elif x < flowers + weeds + dry:
			pick = DRY
		var cell: int = pick[rng.randi() % pick.size()]
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius
		clump(st, Vector3(cos(a) * d, 0, sin(a) * d), cell, SIZES[cell] * grow * scale, rng.randf() * PI, 2)
	st.index()
	return st.commit()


## Crossed vertical cards showing atlas `cell`, `size` metres wide and high.
static func clump(st: SurfaceTool, at: Vector3, cell: int, size: float, yaw: float, cards: int) -> void:
	var cs := Vector2(1.0 / COLS, 1.0 / ROWS)
	var o := Vector2(cell % COLS, cell / COLS) * cs + cs * 0.004
	cs *= 0.992
	for q in cards:
		var ang := yaw + PI * q / cards
		var r := Vector3(cos(ang), 0, sin(ang)) * size * 0.5
		var n := r.cross(Vector3.UP).normalized()
		var corners := [[at - r, Vector2(0, 1)], [at + r, Vector2(1, 1)], [at + r + Vector3.UP * size, Vector2(1, 0)], [at - r + Vector3.UP * size, Vector2(0, 0)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			var v: Array = corners[idx]
			var uv: Vector2 = v[1]
			st.set_normal(n)
			st.set_uv(o + uv * cs)
			st.set_uv2(Vector2(uv.x, 1.0 - uv.y))
			st.add_vertex(v[0])
