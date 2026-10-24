class_name TrackThemes
extends RefCounted
## Theme-specific scenery for circuits whose def has a `theme` key:
##  - "coast": the land drops into the sea on one side (cliffs, beaches, a
##    harbour with a breakwater and boats), a lighthouse on a headland, villas.
##  - "town": an old-town street circuit lined with rows of houses and shops,
##    a market square with fountain and church, a gate tower over the road.
##  - "autodromo": long covered grandstands, a timing tower with scoreboard,
##    poplar rows, cypresses, vineyards and terracotta farmhouses.
## Called by Circuit (EXTRA_BUILDERS) after TrackProps and Scenery, before grass
## and forest. Everything is merged per material and per ~320 m cell (or
## MultiMesh'd) to keep the draw calls down, and kept off the road, run-off and
## rails using the same rail distance TrackProps uses.

const STEP := 2.0 ## metres between lap samples (same as TrackProps / Scenery)
const GRID := 16.0 ## spatial hash cell for distance-to-track queries
const OCC := 2.0 ## occupancy cell for building footprints
const BATCH := 320.0 ## merged meshes are split into cells this big so they cull
const TEX := "res://assets/themes/%s/%s_%s_1k.jpg"

## Invented shop names for the town signs (no real businesses).
const SHOPS := [
	"BÄCKEREI HOLM", "METZGEREI KRANZ", "APOTHEKE", "GASTHAUS ADLER", "UHREN BRANDT",
	"CAFÉ LINDE", "BUCHHANDLUNG", "EISENWAREN WEBER", "KONDITOREI", "SCHUHE MAURER",
	"WEINSTUBE", "HUTMACHER", "FOTO STERN", "KOLONIALWAREN", "STADTKASSE", "POST",
	"MODEHAUS RIEDL", "APOTHEKE", "GOLDSCHMIED", "BRAUHAUS", "LEDERWAREN", "DROGERIE",
	"RADIO FUNK", "ZUM LÖWEN",
]

var parent: Node3D
var def: Dictionary
var terrain: Terrain
var preset: Dictionary
var half := 6.0
var rng := RandomNumberGenerator.new()
var centers: Array[Vector3] = []
var rights: Array[Vector3] = []
var tangents: Array[Vector3] = []
var corner: Array[float] = []
var n := 0
var no_trees: Array = []
var foreign: Array = [] ## footprints of earlier builders (props, scenery)
var noise_tex: Texture2D

var _grid := {} ## Vector2i -> Array of sample indices
var _occ := {} ## Vector2i -> true where a building stands
var _tools := {} ## "key|cell" -> SurfaceTool
var _tool_key := {} ## "key|cell" -> material key
var mats := {}
var vis := {} ## material key -> visibility range end (0 = always)
var uv := {} ## sign atlas regions (normalised)
var _mm := {} ## name -> {mesh, mat, vis, shadow, cells: {Vector2i: Array[Transform3D]}}
var stats := {tris = 0}


static func build(p_parent: Node3D, curve: Curve3D, road_width: float, weather_preset: Dictionary) -> void:
	if OS.get_environment("NO_THEMES") != "":
		return
	var d: Variant = p_parent.get("def")
	if not (d is Dictionary):
		return
	var theme: String = (d as Dictionary).get("theme", "")
	if theme.is_empty():
		return
	# "mediterranean" is the coast theme plus a hilltop village etc. (own file).
	var t: TrackThemes = load("res://scripts/track/theme_mediterranean.gd").new() if theme == "mediterranean" else TrackThemes.new()
	t.parent = p_parent
	t.def = d
	t.terrain = p_parent.get_meta("terrain", null)
	t.preset = weather_preset
	t.half = road_width * 0.5
	t.rng.seed = hash(String(t.def.get("id", theme)))
	t.no_trees = p_parent.get_meta("no_trees", [])
	t.foreign = t.no_trees.duplicate()
	var nt: Variant = p_parent.get("noise_tex")
	t.noise_tex = nt if nt is Texture2D else null
	t._run(curve, theme)


func _run(curve: Curve3D, theme: String) -> void:
	var t0 := Time.get_ticks_msec()
	_sample(curve)
	_materials()
	match theme:
		"coast":
			_coast()
		"town":
			_town()
		"autodromo":
			_autodromo()
		"autumn":
			AutumnTheme.build(self) # theme_autumn.gd
		"harbour":
			load("res://scripts/track/theme_harbour.gd").build(self) # Hafenstadt
		"alpine":
			load("res://scripts/track/theme_alpine.gd").build(self) # Alpenpass
		"mediterranean":
			call("_mediterranean")
	_flush()
	parent.set_meta("no_trees", no_trees)
	if OS.get_cmdline_user_args().has("--debug-themes"):
		print("themes[%s]: %d ms, %d triangles merged, %d mesh batches, %d multimesh sets" % [
			theme, Time.get_ticks_msec() - t0, stats.tris, _tools.size(), _mm.size()])


func _debug(msg: String) -> void:
	if OS.get_cmdline_user_args().has("--debug-themes"):
		print("themes: ", msg)


# ================================================================ sampling

func _sample(curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var tn := (curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))).normalized()
		centers.append(p)
		tangents.append(tn)
		rights.append(tn.cross(Vector3.UP).normalized())
	corner = TrackBuilder._corner_factors(centers)
	for i in n:
		var k := _gkey(centers[i])
		if not _grid.has(k):
			_grid[k] = []
		_grid[k].append(i)


func _gkey(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.z / GRID))


func _i(k: int) -> int:
	return posmod(k, n)


## Nearest lap sample within `reach` metres (XZ), or -1.
func _nearest(p: Vector3, reach := 40.0) -> int:
	var r := int(ceil(reach / GRID))
	var k0 := _gkey(p)
	var best := reach * reach
	var bi := -1
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var arr: Variant = _grid.get(Vector2i(k0.x + dx, k0.y + dz))
			if arr == null:
				continue
			for i: int in arr:
				var c := centers[i]
				var d := (c.x - p.x) * (c.x - p.x) + (c.z - p.z) * (c.z - p.z)
				if d < best:
					best = d
					bi = i
	return bi


## Distance to the centreline, or INF when further than `reach`.
func _tdist(p: Vector3, reach := 40.0) -> float:
	var i := _nearest(p, reach)
	if i < 0:
		return INF
	return Vector2(centers[i].x - p.x, centers[i].z - p.z).length()


## Distance from the centreline to the guardrail (matches TrackBuilder/TrackProps).
func rail_dist(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	var outside := c * side > 0.0
	var depth := TrackBuilder.GRAVEL_MAX * absf(c) if outside else 0.0
	return half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)


func gravel_depth(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	return TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0


## True when p is at least `margin` metres beyond the guardrail of the nearest
## part of the track (and not inside the run-off).
func _off_track(p: Vector3, margin: float) -> bool:
	var i := _nearest(p, 34.0)
	if i < 0:
		return true
	var d := p - centers[i]
	var lat := d.x * rights[i].x + d.z * rights[i].z
	var side := 1.0 if lat >= 0.0 else -1.0
	return absf(lat) >= rail_dist(i, side) + margin and Vector2(d.x, d.z).length() >= rail_dist(i, side) + margin


func _ground(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain else p.y


func _on_ground(p: Vector3, lift := 0.0) -> Vector3:
	return Vector3(p.x, _ground(p) + lift, p.z)


## Earlier builders' footprints (small crowd circles count a bit smaller).
func _foreign_clear(p: Vector3, r: float) -> bool:
	for z in foreign:
		var zr: float = z[1]
		if zr <= 25.0:
			zr *= 0.72
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < zr + r:
			return false
	return true


# ================================================================ occupancy

## Footprint points of an oriented rectangle (centre c, axes ax/az, sizes w/d).
func _footprint(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float, spacing := 1.8) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var nx := maxi(1, int(ceil(w / spacing)))
	var nz := maxi(1, int(ceil(d / spacing)))
	for a in nx + 1:
		for b in nz + 1:
			pts.append(c + ax * (a / float(nx) - 0.5) * w + az * (b / float(nz) - 0.5) * d)
	return pts


func _okey(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / OCC), floori(p.z / OCC))


## Can a building of this footprint stand here? Checks other buildings, the
## track (rail + margin) at the corners and edge midpoints, and older props.
func _fits(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float, margin := 1.2) -> bool:
	for p in _footprint(c, ax, az, w - 0.6, d - 0.6):
		if _occ.has(_okey(p)):
			return false
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			if not _off_track(c + ax * sx * w + az * sz * d, margin):
				return false
	return _foreign_clear(c, maxf(w, d) * 0.5)


func _mark(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float) -> void:
	for p in _footprint(c, ax, az, w, d, 1.0):
		_occ[_okey(p)] = true


# ================================================================ mesh batching

func _st(key: String, at: Vector3) -> SurfaceTool:
	var cell := Vector2i(floori(at.x / BATCH), floori(at.z / BATCH))
	var id := "%s|%d,%d" % [key, cell.x, cell.y]
	if not _tools.has(id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[id] = st
		_tool_key[id] = key
	return _tools[id]


## Emits a triangle so its front face points along `out` (Godot: clockwise = front).
func _tri(key: String, a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
	var st := _st(key, a)
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-10:
		return
	nrm = nrm.normalized()
	var verts := [[a, ua], [c, uc], [b, ub]]
	if nrm.dot(out) < 0.0:
		nrm = -nrm
		verts = [[a, ua], [b, ub], [c, uc]]
	for v in verts:
		st.set_color(col)
		st.set_normal(nrm)
		st.set_uv(v[1])
		st.set_uv2(uv2)
		st.add_vertex(v[0])
	stats.tris += 1


func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO, uv2 := Vector2.ZERO) -> void:
	_tri(key, a, b, c, col, out, ua, ub, uc, uv2)
	_tri(key, a, c, d, col, out, ua, uc, ud, uv2)


## Box from its centre, orthonormal axes and full size; faces point outwards.
func _box(key: String, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, size: Vector3, col: Color, skip_bottom := true) -> void:
	var hx := ax * size.x * 0.5
	var hy := ay * size.y * 0.5
	var hz := az * size.z * 0.5
	var faces := [[hx, hy, hz], [-hx, hy, hz], [hz, hy, hx], [-hz, hy, hx], [hy, hx, hz]]
	if not skip_bottom:
		faces.append([-hy, hx, hz])
	for f in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var fc: Vector3 = c + nrm
		_quad(key, fc - u - v, fc + u - v, fc + u + v, fc - u + v, col, nrm)


func _hbox(key: String, c: Vector3, fwd: Vector3, size: Vector3, col: Color) -> void:
	var az := Vector3(fwd.x, 0, fwd.z).normalized()
	var ax := Vector3.UP.cross(az).normalized()
	_box(key, c, ax, Vector3.UP, az, size, col)


## A vertical wall face, UVs in metres for the facade shader (x from the
## viewer's left, y from `street` level).
func _wall(key: String, fc: Vector3, out: Vector3, width: float, y0: float, y1: float, street: float, col: Color, uv2: Vector2) -> void:
	var r := (-out).cross(Vector3.UP).normalized() # viewer's right
	var bl := Vector3(fc.x, y0, fc.z) - r * width * 0.5
	var br := Vector3(fc.x, y0, fc.z) + r * width * 0.5
	var tr := Vector3(br.x, y1, br.z)
	var tl := Vector3(bl.x, y1, bl.z)
	_quad(key, bl, br, tr, tl, col, out, Vector2(0, y0 - street), Vector2(width, y0 - street),
		Vector2(width, y1 - street), Vector2(0, y1 - street), uv2)


## One photo window / door (FacadeKit atlas cell) standing on `bottom_mid`,
## facing `out`, `h` metres tall (width from the photo). Returns its size.
func _photo_unit(bottom_mid: Vector3, out: Vector3, cell: int, h: float) -> Vector2:
	var s: Vector2 = FacadeKit.SIZES[cell] * (h / FacadeKit.SIZES[cell].y)
	var r := (-out).cross(Vector3.UP).normalized() * s.x * 0.5
	var pad := 16.0 / 512.0
	var u0 := (cell % 4 + pad) / 4.0
	var u1 := (cell % 4 + 1.0 - pad) / 4.0
	var v0 := (cell / 4 + pad) / 5.0
	var v1 := (cell / 4 + 1.0 - pad) / 5.0
	var up := Vector3.UP * s.y
	_quad("photo", bottom_mid - r, bottom_mid + r, bottom_mid + r + up, bottom_mid - r + up, Color.WHITE, out,
		Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0))
	return s


## Cylinder / cone frustum standing on `base`.
func _cyl(key: String, base: Vector3, r0: float, r1: float, h: float, segs: int, col: Color, cap := true) -> void:
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var out := (d0 + d1).normalized()
		var p0 := base + d0 * r0
		var p1 := base + d1 * r0
		var q0 := base + d0 * r1 + Vector3.UP * h
		var q1 := base + d1 * r1 + Vector3.UP * h
		if r1 > 0.001:
			_quad(key, p0, p1, q1, q0, col, out + Vector3.UP * (r0 - r1) / h)
		else:
			_tri(key, p0, p1, q0, col, out + Vector3.UP * r0 / h)
		if cap and r1 > 0.001:
			_tri(key, base + Vector3.UP * h, q0, q1, col, Vector3.UP)


## Gabled roof over a w x l footprint (ridge along `ax`), sitting on `top`.
## The gable-end triangles are wall, the slopes are roof.
func _gable(c_top: Vector3, ax: Vector3, az: Vector3, l: float, w: float, rise: float, over: float,
		roof_col: Color, wall_col: Color, wall_key := "wall") -> void:
	var drop := rise / (w * 0.5) * over
	var e0 := c_top - az * (w * 0.5 + over) - Vector3.UP * drop
	var e1 := c_top + az * (w * 0.5 + over) - Vector3.UP * drop
	var ridge := c_top + Vector3.UP * rise
	var hl := ax * (l * 0.5 + over * 0.6)
	_quad("roof", e0 - hl, e0 + hl, ridge + hl, ridge - hl, roof_col, -az + Vector3.UP)
	_quad("roof", e1 - hl, e1 + hl, ridge + hl, ridge - hl, roof_col, az + Vector3.UP)
	# Undersides of the overhang, dark.
	for s: float in [-1.0, 1.0]:
		var g := c_top + ax * s * l * 0.5
		var uv2 := Vector2(w + 2000.0, 99.0)
		_tri(wall_key, g - az * w * 0.5, g + az * w * 0.5, g + Vector3.UP * rise, wall_col, ax * s,
			Vector2(0, 50), Vector2(w, 50), Vector2(w * 0.5, 50 + rise), uv2)


## Hipped roof (all four sides slope): Italian farmhouses, church apses.
func _hip(c_top: Vector3, ax: Vector3, az: Vector3, l: float, w: float, rise: float, over: float, col: Color) -> void:
	var L := l * 0.5 + over
	var W := w * 0.5 + over
	var drop := rise / (w * 0.5) * over
	var base := c_top - Vector3.UP * drop
	var rl := maxf(L - W, 0.0)
	var r0 := c_top + Vector3.UP * rise - ax * rl
	var r1 := c_top + Vector3.UP * rise + ax * rl
	var a := base - ax * L - az * W
	var b := base + ax * L - az * W
	var c := base + ax * L + az * W
	var d := base - ax * L + az * W
	_quad("roof", a, b, r1, r0, col, -az + Vector3.UP)
	_quad("roof", c, d, r0, r1, col, az + Vector3.UP)
	_tri("roof", b, c, r1, col, ax + Vector3.UP)
	_tri("roof", d, a, r0, col, -ax + Vector3.UP)


## Draped grid over the terrain (paving, soil). `inside` filters cells.
func _drape(key: String, origin: Vector3, ax: Vector3, az: Vector3, w: float, d: float, cell: float, lift: float, col: Color) -> void:
	var nx := maxi(1, int(ceil(w / cell)))
	var nz := maxi(1, int(ceil(d / cell)))
	var rows: Array[PackedVector3Array] = []
	for b in nz + 1:
		var row := PackedVector3Array()
		for a in nx + 1:
			var p := origin + ax * (a / float(nx) - 0.5) * w + az * (b / float(nz) - 0.5) * d
			row.append(_on_ground(p, lift))
		rows.append(row)
	for b in nz:
		for a in nx:
			_quad(key, rows[b][a], rows[b][a + 1], rows[b + 1][a + 1], rows[b + 1][a], col, Vector3.UP)


## A textured quad showing an atlas region, facing `out`.
func _sign(c: Vector3, out: Vector3, w: float, h: float, region: Rect2) -> void:
	var r := (-out).cross(Vector3.UP).normalized() * w * 0.5
	var u := Vector3.UP * h * 0.5
	_quad("sign", c - r - u, c + r - u, c + r + u, c - r + u, Color.WHITE, out,
		Vector2(region.position.x, region.end.y), region.end, Vector2(region.end.x, region.position.y), region.position)


func _mm_set(name: String, mesh: Mesh, mat: Material, vis_end: float, shadow := true) -> void:
	if not _mm.has(name):
		_mm[name] = {mesh = mesh, mat = mat, vis = vis_end, shadow = shadow, cells = {}}


## Baked tree model (Vegetation.model, e.g. "cypress_1") as a MultiMesh set:
## the near mesh out to TREE_NEAR m, then the far LOD of the same tree, swapped
## per 100 m cell through visibility_parent (no fade, no gap; as the forest).
const TREE_NEAR := 220.0
func _tree_set(name: String, model: String, conifer: bool, vis_end: float, fallback: Mesh, shadow := true) -> void:
	var lods := Vegetation.model(model)
	if lods.is_empty():
		_mm_set(name, fallback, mats.foliage, vis_end, shadow)
		return
	var key := "veg_tree%d" % int(conifer)
	if not mats.has(key):
		mats[key] = Vegetation.conifer_material(noise_tex, 0.3) if conifer else Vegetation.broadleaf_material(noise_tex, 0.35)
	if not _mm.has(name):
		_mm[name] = {mesh = lods[0], far = lods[1], mat = mats[key], vis = vis_end, shadow = shadow, cells = {}}


func _mm_add(name: String, xf: Transform3D) -> void:
	var set: Dictionary = _mm[name]
	# Cells scale with the range (0.4 x): few draw calls, and the half-diagonal
	# added to the range end in _flush stays small next to it.
	var size := clampf(float(set.vis) * 0.4, 100.0, 400.0) if set.vis > 0.0 else 400.0
	if set.has("far"):
		size = 100.0 # near/far swap is measured to the cell centre
	var cell := Vector2i(floori(xf.origin.x / size), floori(xf.origin.z / size))
	if not set.cells.has(cell):
		set.cells[cell] = []
	set.cells[cell].append(xf)


func _flush() -> void:
	var names := {PeopleKit.Role.SPECTATOR: "ThemeSpectators", PeopleKit.Role.SEATED: "ThemeStands"}
	for role in _people:
		var xfs: Array[Transform3D] = _people[role][0]
		var custom: Array[Color] = []
		for k in xfs.size():
			custom.append(Color(rng.randf(), rng.randf_range(0.0, 0.6), 0.0, 0.0))
		if OS.get_cmdline_user_args().has("--debug-people"):
			print("theme crowd ", names[role], " n=", xfs.size(), " sample ", xfs[xfs.size() / 2].origin, " facing ", -xfs[xfs.size() / 2].basis.z)
		parent.add_child(PeopleKit.crowd(names[role], role, xfs, _people[role][1], custom, role != PeopleKit.Role.SEATED))
	for id in _tools:
		var key: String = _tool_key[id]
		var st: SurfaceTool = _tools[id]
		var mi := MeshInstance3D.new()
		mi.name = "Theme_" + id.replace("|", "_").replace(",", "_").replace("-", "m")
		mi.mesh = st.commit()
		mi.material_override = mats[key]
		var v: float = vis.get(key, 0.0)
		if v > 0.0:
			# Godot measures the range to the mesh's AABB centre: add the cell's
			# half-diagonal so nothing within `v` is culled with its cell.
			var box := mi.mesh.get_aabb()
			mi.visibility_range_end = v + Vector2(box.size.x, box.size.z).length() * 0.5
			mi.visibility_range_end_margin = v * 0.1
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if key in ["pave", "soil", "sign", "water", "cutrock", "photo"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	for name in _mm:
		var set: Dictionary = _mm[name]
		for cell in set.cells:
			var xfs: Array = set.cells[cell]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = set.mesh
			mm.instance_count = xfs.size()
			for k in xfs.size():
				mm.set_instance_transform(k, xfs[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "ThemeMM_" + name
			mmi.multimesh = mm
			mmi.material_override = set.mat
			if set.vis > 0.0:
				var lo := Vector2(INF, INF)
				var hi := -lo
				for xf: Transform3D in xfs:
					lo = lo.min(Vector2(xf.origin.x, xf.origin.z))
					hi = hi.max(Vector2(xf.origin.x, xf.origin.z))
				mmi.visibility_range_end = set.vis + (hi - lo).length() * 0.5 + 5.0
				mmi.visibility_range_end_margin = set.vis * 0.1
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if not set.shadow:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
			if set.has("far"):
				# Far LOD beyond TREE_NEAR; the near trees and their (cheap far-LOD)
				# shadows are its visibility children.
				var fmm := MultiMesh.new()
				fmm.transform_format = MultiMesh.TRANSFORM_3D
				fmm.mesh = set.far
				fmm.instance_count = xfs.size()
				for k in xfs.size():
					fmm.set_instance_transform(k, xfs[k])
				var far := MultiMeshInstance3D.new()
				far.name = "ThemeMMFar_" + name
				far.multimesh = fmm
				far.material_override = set.mat
				far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				far.visibility_range_begin = TREE_NEAR
				far.visibility_range_begin_margin = 8.0
				far.visibility_range_end = mmi.visibility_range_end
				far.visibility_range_end_margin = mmi.visibility_range_end_margin
				far.visibility_range_fade_mode = mmi.visibility_range_fade_mode
				far.extra_cull_margin = 4.0
				parent.add_child(far)
				mmi.visibility_range_end = 0.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.extra_cull_margin = 4.0
				mmi.visibility_parent = mmi.get_path_to(far)
				if set.shadow:
					var sh := MultiMeshInstance3D.new()
					sh.name = "ThemeMMShadow_" + name
					sh.multimesh = fmm
					sh.material_override = set.mat
					sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					sh.extra_cull_margin = 4.0
					parent.add_child(sh)
					sh.visibility_parent = sh.get_path_to(far)


# ================================================================ materials

func _tex(id: String, kind: String) -> Texture2D:
	return load(TEX % [id, id, kind])


func _vc(rough := 0.85, metal := 0.0, cull := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _triplanar(id: String, scale: float, rough := 0.9, cull := true) -> StandardMaterial3D:
	var m := _vc(rough, 0.0, cull)
	m.albedo_texture = _tex(id, "diff")
	m.normal_enabled = true
	m.normal_texture = _tex(id, "nor_gl")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _materials() -> void:
	var wet: float = preset.get("wet", 0.0)
	var facade := ShaderMaterial.new()
	facade.shader = load("res://shaders/theme_facade.gdshader")
	facade.set_shader_parameter("wall_albedo", _tex("plastered_wall", "diff"))
	facade.set_shader_parameter("wall_normal", _tex("plastered_wall", "nor_gl"))
	facade.set_shader_parameter("wet", wet * 0.6)
	var night := float(preset.get("night", 0.0)) > 0.0
	facade.set_shader_parameter("lit", 0.8 if night else (0.9 if wet > 0.5 else 0.0)) # lit windows
	FacadeKit._bind(facade) # photo windows / doors / shopfronts (facade_kit.gd)
	mats.photo = FacadeKit.unit_material(0.8 if night else 0.0) # single photo windows / doors (_photo_unit)
	facade.set_shader_parameter("region", FacadeKit.SOUTH if def.get("theme", "") in ["coast", "mediterranean"] else FacadeKit.NORTH)
	mats.wall = facade
	mats.stone = _triplanar("stone_wall", 0.22, 0.92)
	mats.roof = Mats.mat("roof_tiles") # face-aligned tiles, tinted by the vertex colour
	mats.pave = _triplanar("cobblestone_floor_08", 0.3, 0.85)
	mats.soil = _triplanar("farm_soil", 0.18, 0.95)
	mats.rock = _triplanar("cliff_side", 0.12, 0.95)
	mats.plain = Mats.mat("plaster") # photographic PBR (Mats), vertex colour kept
	mats.metal = Mats.mat("painted_metal")
	mats.glass = Mats.mat("glass", Color.WHITE, false)
	var water := _vc(0.04, 0.0)
	water.metallic_specular = 0.8
	mats.water = water
	var lamp := _vc(0.3)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.55)
	lamp.emission_energy_multiplier = 2.5
	mats.lamp = lamp
	var foliage: Material
	if noise_tex:
		foliage = WorldBuilder.foliage_material(noise_tex, 0.25, 14.0)
	else:
		foliage = _vc(0.9, 0.0, false)
	mats.foliage = foliage
	vis = {plain = 900.0, metal = 700.0, glass = 900.0, lamp = 600.0, sign = 450.0, water = 700.0, photo = 700.0}


## Signs and boards drawn once into a SubViewport (same baker as TrackProps).
func _atlas(entries: Array) -> Texture2D:
	var size := Vector2i(2048, 1024)
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var root := Control.new()
	root.size = Vector2(size)
	vp.add_child(root)
	var bold: Font = load(UiTheme.FONT_BOLD)
	# entries: [key, Rect2 (pixels), bg, ink, text, font size, border]
	for e in entries:
		var r: Rect2 = e[1]
		var bg := ColorRect.new()
		bg.position = r.position
		bg.size = r.size
		bg.color = e[2]
		root.add_child(bg)
		var border: Color = e[6]
		if border.a > 0.0:
			for k in 4:
				var line := ColorRect.new()
				line.color = border
				line.position = r.position + [Vector2(6, 6), Vector2(6, r.size.y - 12), Vector2(6, 6), Vector2(r.size.x - 12, 6)][k]
				line.size = [Vector2(r.size.x - 12, 5), Vector2(r.size.x - 12, 5), Vector2(5, r.size.y - 12), Vector2(5, r.size.y - 12)][k]
				root.add_child(line)
		var l := Label.new()
		l.text = e[4]
		l.position = r.position
		l.size = r.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", bold)
		l.add_theme_font_size_override("font_size", e[5])
		l.add_theme_color_override("font_color", e[3])
		root.add_child(l)
		uv[e[0]] = Rect2(r.position / Vector2(size), r.size / Vector2(size))
	parent.add_child(vp)
	var baker := TrackProps.AtlasBaker.new()
	baker.viewport = vp
	parent.add_child(baker)
	return baker.texture


func _sign_material(tex: Texture2D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.7
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats.sign = m


# ================================================================ shared models

const WALLS_NORTH := [Color(0.93, 0.9, 0.82), Color(0.9, 0.82, 0.62), Color(0.86, 0.72, 0.56), Color(0.8, 0.84, 0.76),
	Color(0.94, 0.93, 0.9), Color(0.78, 0.8, 0.82), Color(0.88, 0.76, 0.7), Color(0.82, 0.66, 0.5), Color(0.72, 0.78, 0.84),
	Color(0.9, 0.86, 0.7)]
const WALLS_SOUTH := [Color(0.9, 0.7, 0.5), Color(0.86, 0.6, 0.42), Color(0.92, 0.8, 0.6), Color(0.8, 0.55, 0.4),
	Color(0.94, 0.88, 0.76), Color(0.88, 0.66, 0.46)]
const ROOFS := [Color(0.72, 0.42, 0.32), Color(0.62, 0.34, 0.26), Color(0.8, 0.5, 0.38), Color(0.55, 0.3, 0.24),
	Color(0.42, 0.4, 0.42), Color(0.68, 0.46, 0.36)]


## A house: rendered walls with the facade shader, gabled or hipped roof,
## chimney. `c` is the footprint centre, `az` points away from the street
## (the front faces -az). Returns the top-of-wall height.
func _house(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float, h: float, wall_col: Color, roof_col: Color,
		style := 0, variant := -1, ridge_along := true, hipped := false, street := NAN) -> float:
	if variant < 0:
		variant = rng.randi() % 10
	# Footprint for AudioSpace (engine echo between buildings): [centre, along, across, w, d].
	var boxes: Array = parent.get_meta("sound_boxes", [])
	boxes.append([c, ax, az, w, d])
	parent.set_meta("sound_boxes", boxes)
	var front := c - az * d * 0.5
	if is_nan(street):
		street = _ground(front)
	var lowest := street
	for p in _footprint(c, ax, az, w, d, maxf(w, d)):
		lowest = minf(lowest, _ground(p))
	var y0 := lowest - 1.2
	var y1 := street + h
	var faces := [[front, -az, w, style], [c + az * d * 0.5, az, w, 0 if style != 3 else 3],
		[c + ax * w * 0.5, ax, d, 0 if style != 3 else 3], [c - ax * w * 0.5, -ax, d, 0 if style != 3 else 3]]
	for f in faces:
		var fw: float = f[2]
		var st: int = f[3]
		_wall("wall", f[0], f[1], fw, y0, y1, street, wall_col, Vector2(fw + 1000.0 * st, h + 100.0 * variant))
	var top := Vector3(c.x, y1, c.z)
	if hipped:
		_hip(top, ax if w >= d else az, az if w >= d else ax, maxf(w, d), minf(w, d), minf(w, d) * 0.28, 0.7, roof_col)
	elif ridge_along:
		_gable(top, ax, az, w, d, d * rng.randf_range(0.34, 0.5), 0.45, roof_col, wall_col)
	else:
		_gable(top, az, ax, d, w, w * rng.randf_range(0.45, 0.62), 0.45, roof_col, wall_col)
	if rng.randf() < 0.7:
		var ch := top + ax * rng.randf_range(-0.3, 0.3) * w + az * rng.randf_range(0.0, 0.25) * d
		_box("stone", ch + Vector3.UP * (minf(w, d) * 0.3 + 0.2), ax, Vector3.UP, az, Vector3(0.7, minf(w, d) * 0.6 + 1.4, 0.7), Color(0.75, 0.68, 0.62))
	return y1


## Spectators are collected here and built as PeopleKit crowds in _flush().
var _people := {} ## Role -> [Array[Transform3D], Array[Color]]
const SHIRTS := [Color(0.55, 0.1, 0.08), Color(0.15, 0.22, 0.42), Color(0.8, 0.75, 0.62), Color(0.12, 0.3, 0.16),
	Color(0.8, 0.62, 0.12), Color(0.1, 0.1, 0.11), Color(0.62, 0.64, 0.66), Color(0.35, 0.18, 0.3)]


func _person(xf: Transform3D, role: PeopleKit.Role) -> void:
	if not _people.has(role):
		var xfs: Array[Transform3D] = []
		var cols: Array[Color] = []
		_people[role] = [xfs, cols]
	_people[role][0].append(xf)
	_people[role][1].append(SHIRTS[rng.randi() % SHIRTS.size()])


## Lumpy vertex-coloured blob (trees, bushes, rocks), base at y=0.
func _blob(radius: float, height: float, cols: Array, bump: float, segs := 12, taper := 0.0) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segs
	sphere.rings = maxi(6, segs / 2)
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var moved := PackedVector3Array()
	for v in verts:
		var t := v.y * 0.5 + 0.5 # 0 bottom .. 1 top
		var shrink := lerpf(1.0, 1.0 - taper, t)
		var p := v * (1.0 + noise.get_noise_3dv(v * 1.3) * bump)
		p.x *= radius * shrink
		p.z *= radius * shrink
		p.y = (p.y * 0.5 + 0.5) * height
		moved.append(p)
	for k: int in arrays[Mesh.ARRAY_INDEX]:
		var p := moved[k]
		var shade := clampf(p.y / height * 0.8 + 0.2 + noise.get_noise_3dv(p * 0.7) * 0.25, 0.0, 1.0)
		st.set_color((cols[0] as Color).lerp(cols[1], shade))
		st.add_vertex(p)
	st.index()
	st.generate_normals()
	return st.commit()


## Tree = trunk + blob crown, merged into one mesh.
func _tree_mesh(crown_r: float, crown_h: float, trunk_h: float, cols: Array, bump: float, taper: float, segs := 12) -> ArrayMesh:
	var crown := _blob(crown_r, crown_h, cols, bump, segs, taper)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.2
	trunk.height = trunk_h + crown_h * 0.3
	trunk.radial_segments = 5
	trunk.rings = 1
	trunk.cap_top = false
	trunk.cap_bottom = false
	var arr := trunk.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for k: int in arr[Mesh.ARRAY_INDEX]:
		st.set_color(Color(0.22, 0.17, 0.12))
		st.set_normal(norms[k])
		st.add_vertex(verts[k] + Vector3.UP * trunk.height * 0.5)
	var carr := crown.surface_get_arrays(0)
	var cv: PackedVector3Array = carr[Mesh.ARRAY_VERTEX]
	var cn: PackedVector3Array = carr[Mesh.ARRAY_NORMAL]
	var cc: PackedColorArray = carr[Mesh.ARRAY_COLOR]
	for k: int in carr[Mesh.ARRAY_INDEX]:
		st.set_color(cc[k])
		st.set_normal(cn[k])
		st.add_vertex(cv[k] + Vector3.UP * trunk_h)
	return st.commit()


# ================================================================ coast

var sea_level := 0.0
var _sea := Vector2(-1, 0) ## direction towards the sea
var _perp := Vector2(0, -1)
var _u0 := 0.0 ## first coastline bin (along the coast)
const U_BIN := 6.0
var _ref := PackedFloat32Array() ## seaward-most track position per bin
var _d0 := PackedFloat32Array() ## where the land starts to fall, metres past _ref
var _fall := PackedFloat32Array() ## how far it takes to reach the water line
var _harbour_u := 0.0
var _headland_u := 0.0
var _beach_u := 0.0
const HARBOUR_HALF := 62.0
const QUAY := 70.0 ## harbour quay edge, metres past _ref


func _cs(p: Vector3) -> Vector2: ## (u along coast, s towards sea)
	var q := Vector2(p.x, p.z)
	return Vector2(q.dot(_perp), q.dot(_sea))


func _from_cs(u: float, s: float, lift := 0.0) -> Vector3:
	var q := _perp * u + _sea * s
	return _on_ground(Vector3(q.x, 0, q.y), lift)


func _bin(u: float) -> int:
	return clampi(int(round((u - _u0) / U_BIN)), 0, _ref.size() - 1)


func _coast() -> void:
	if terrain == null:
		return
	_sea = (def.get("sea", Vector2(-1, 0)) as Vector2).normalized()
	_perp = Vector2(-_sea.y, _sea.x)
	_coastline()
	# Sea level a few metres below the lowest stretch of coastal road.
	var low := INF
	for c in centers:
		var cs := _cs(c)
		if cs.y > _ref[_bin(cs.x)] - 40.0:
			low = minf(low, c.y)
	sea_level = low - 4.5
	_shape_land()
	_rebuild_terrain()
	_sea_plane()
	_harbour()
	_lighthouse()
	_villas()
	_shore_rocks()
	_sink_far_hills()
	# Where things are, for the per-track dressing (gimmicks/dress_<id>.gd).
	var bk := _bin(_beach_u)
	parent.set_meta("coast", {sea = Vector3(_sea.x, 0, _sea.y), sea_level = sea_level,
		harbour = _from_cs(_harbour_u, _ref[_bin(_harbour_u)] + QUAY), headland = _from_cs(_headland_u, _ref[_bin(_headland_u)] + 30.0),
		beach = _from_cs(_beach_u, _ref[bk] + _d0[bk] + _fall[bk])})
	# The sea needs no forest: a few big circles over the water.
	var u := _u0
	while u < _u0 + _ref.size() * U_BIN:
		var k := _bin(u)
		no_trees.append([_from_cs(u, _ref[k] + _d0[k] + _fall[k] + 150.0), 130.0])
		u += 160.0


## Coastline reference: the seaward-most point of the track along the coast,
## then how far the land runs before dropping (noise, headland, harbour, and
## wherever older props stand).
func _coastline() -> void:
	var span := (Terrain.N - 1) * terrain.cell
	var o := terrain.origin
	var us: Array[float] = []
	for c in [o, o + Vector2(span, 0), o + Vector2(0, span), o + Vector2(span, span)]:
		us.append((c as Vector2).dot(_perp))
	_u0 = us.min() - 20.0
	var bins := int((us.max() + 20.0 - _u0) / U_BIN) + 1
	_ref.resize(bins)
	_ref.fill(-INF)
	var lo_u := INF
	var hi_u := -INF
	for c in centers:
		var cs := _cs(c)
		lo_u = minf(lo_u, cs.x)
		hi_u = maxf(hi_u, cs.x)
		for k in range(_bin(cs.x - 36.0), _bin(cs.x + 36.0) + 1):
			_ref[k] = maxf(_ref[k], cs.y)
	# Past the ends of the track the coast carries on straight.
	var first := 0
	while first < bins and _ref[first] == -INF:
		first += 1
	var last := bins - 1
	while last > 0 and _ref[last] == -INF:
		last -= 1
	for k in bins:
		if k < first:
			_ref[k] = _ref[first]
		elif k > last:
			_ref[k] = _ref[last]
	for _pass in 2:
		var sm := _ref.duplicate()
		for k in bins:
			var acc := 0.0
			for j in range(-4, 5):
				acc += _ref[clampi(k + j, 0, bins - 1)]
			sm[k] = maxf(acc / 9.0, _ref[k] - 4.0)
		_ref = sm

	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = 0.012
	var nz2 := FastNoiseLite.new()
	nz2.seed = rng.randi()
	nz2.frequency = 0.008
	_d0.resize(bins)
	_fall.resize(bins)
	var along := hi_u - lo_u
	_headland_u = lo_u + along * float(def.get("headland_at", 0.86))
	_harbour_u = lo_u + along * float(def.get("harbour_at", 0.2))
	_beach_u = lo_u + along * float(def.get("beach_at", 0.55))
	for k in bins:
		var u := _u0 + k * U_BIN
		_d0[k] = 23.0 + maxf(nz.get_noise_1d(u), 0.0) * 30.0
		_fall[k] = lerpf(9.0, 60.0, smoothstep(-0.25, 0.35, nz2.get_noise_1d(u)))
		# A headland for the lighthouse, a gentle beach, a flat harbour apron.
		var hd := absf(u - _headland_u)
		_d0[k] = maxf(_d0[k], 125.0 - hd * 1.9)
		if hd < 110.0:
			_fall[k] = lerpf(8.0, _fall[k], smoothstep(40.0, 110.0, hd))
		var bd := absf(u - _beach_u)
		if bd < 120.0:
			var t := smoothstep(120.0, 50.0, bd)
			_fall[k] = lerpf(_fall[k], 75.0, t)
			_d0[k] = lerpf(_d0[k], 24.0, t)
		if absf(u - _harbour_u) < HARBOUR_HALF + 50.0:
			_d0[k] = lerpf(_d0[k], QUAY, smoothstep(HARBOUR_HALF + 50.0, HARBOUR_HALF, absf(u - _harbour_u)))
	# Keep the ground under things other builders already put down.
	var lake: Node3D = parent.get_node_or_null("Lake")
	for z in foreign:
		var c: Vector3 = z[0]
		var r: float = z[1]
		if lake and Vector2(c.x - lake.position.x, c.z - lake.position.z).length() < 1.0:
			continue
		var cs := _cs(c)
		var need := cs.y - _ref[_bin(cs.x)] + (r * 0.5 + 3.0 if r <= 25.0 else r * 0.8 + 10.0)
		for k in range(_bin(cs.x - r - 90.0), _bin(cs.x + r + 90.0) + 1):
			var du := maxf(absf(_u0 + k * U_BIN - cs.x) - r * 0.5, 0.0)
			_d0[k] = maxf(_d0[k], need - du * du * 0.02 - du * 0.6)
	if lake:
		var lcs := _cs(lake.position)
		if lcs.y - _ref[_bin(lcs.x)] > _d0[_bin(lcs.x)] - 60.0:
			lake.queue_free() # the sea replaces Scenery's lake


func _shape_land() -> void:
	var N := Terrain.N
	var cell := terrain.cell
	# Distance to the track per heightmap cell (stamped, like Terrain.carve).
	var near := PackedFloat32Array()
	near.resize(N * N)
	near.fill(INF)
	var reach := 44.0
	var r := int(ceil(reach / cell))
	for i in range(0, n, 2):
		var s := centers[i]
		var cx := int(round((s.x - terrain.origin.x) / cell))
		var cz := int(round((s.z - terrain.origin.y) / cell))
		for zi in range(maxi(cz - r, 0), mini(cz + r + 1, N)):
			var dz := terrain.origin.y + zi * cell - s.z
			for xi in range(maxi(cx - r, 0), mini(cx + r + 1, N)):
				var dx := terrain.origin.x + xi * cell - s.x
				var k := zi * N + xi
				near[k] = minf(near[k], dx * dx + dz * dz)
	var L := sea_level
	var apron := L + 1.7
	for zi in N:
		var z := terrain.origin.y + zi * cell
		for xi in N:
			var x := terrain.origin.x + xi * cell
			var q := Vector2(x, z)
			var u := q.dot(_perp)
			var b := _bin(u)
			var d := q.dot(_sea) - _ref[b]
			if d < 18.0:
				continue
			var k := zi * N + xi
			var h := heights_at(k)
			var d0 := _d0[b]
			var fall := _fall[b]
			var target: float
			var hu := absf(u - _harbour_u)
			if hu < HARBOUR_HALF + 50.0:
				# Harbour: the road embankment eases down to a flat quay apron,
				# then a sheer quay wall into deep water.
				var ta := smoothstep(26.0, 46.0, d)
				var quay_h := lerpf(maxf(h, L + 2.5), apron, ta)
				var sea_h := L - 6.0 - smoothstep(QUAY, QUAY + 80.0, d) * 18.0
				var harb := quay_h if d < QUAY else sea_h
				var edge := smoothstep(HARBOUR_HALF + 50.0, HARBOUR_HALF + 10.0, hu)
				var natural := _profile(h, d, d0, fall, L)
				target = lerpf(natural, harb, edge)
			else:
				target = _profile(h, d, d0, fall, L)
			var g := smoothstep(22.0, 32.0, sqrt(near[k]))
			terrain.heights[k] = lerpf(h, target, g)


func heights_at(k: int) -> float:
	return terrain.heights[k]


## Land height `d` metres seaward of the coastal road: unchanged (but kept
## above water) until d0, then down to the waterline over `fall` metres, then
## the seabed falls away out of sight.
func _profile(h: float, d: float, d0: float, fall: float, L: float) -> float:
	var top := maxf(h, L + 2.5)
	if d < d0:
		return top
	if d < d0 + fall:
		var t := (d - d0) / fall
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(top, L - 1.2, t)
	var e := smoothstep(d0 + fall, d0 + fall + 90.0, d)
	return lerpf(L - 1.2, L - 32.0, e)


## Swap the ground nodes for ones built from the reshaped heights, with a
## material that adds sand and rock.
func _rebuild_terrain() -> void:
	var old: Node = parent.get_node_or_null("Terrain")
	var ground: ShaderMaterial = null
	if old:
		for ch in old.get_children():
			if ch is MeshInstance3D:
				ground = (ch as MeshInstance3D).material_override as ShaderMaterial
				break
		parent.remove_child(old)
		old.free()
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/theme_coast_ground.gdshader")
	if ground:
		for uni in ground.shader.get_shader_uniform_list():
			m.set_shader_parameter(uni.name, ground.get_shader_parameter(uni.name))
	m.set_shader_parameter("sand_albedo", _tex("coast_sand_01", "diff"))
	m.set_shader_parameter("sand_normal", _tex("coast_sand_01", "nor_gl"))
	m.set_shader_parameter("rock_albedo", _tex("cliff_side", "diff"))
	m.set_shader_parameter("rock_normal", _tex("cliff_side", "nor_gl"))
	m.set_shader_parameter("sea_level", sea_level)
	terrain.build_nodes(parent, m, 0.55, 0.06)


func _sea_plane() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var far := 6000.0
	var rows: Array = []
	var u := _u0 - far
	while u <= _u0 + _ref.size() * U_BIN + far:
		var k := _bin(u)
		var s0 := _ref[k] + 20.0
		var a := _perp * u + _sea * s0
		var b := _perp * u + _sea * (s0 + far)
		rows.append([Vector3(a.x, sea_level, a.y), Vector3(b.x, sea_level, b.y)])
		var inside := u > _u0 and u < _u0 + _ref.size() * U_BIN
		u += U_BIN * 2.0 if inside else 400.0
	for i in rows.size() - 1:
		var a: Vector3 = rows[i][0]
		var b: Vector3 = rows[i][1]
		var c: Vector3 = rows[i + 1][1]
		var d: Vector3 = rows[i + 1][0]
		# Mid row so the far half isn't one huge sliver triangle.
		for v in [a, c, b, a, d, c]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	# Make sure faces point up (Godot: clockwise from the front).
	st.index()
	var mesh := st.commit()
	var arr := mesh.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for t in range(0, idx.size(), 3):
		var nrm := (vv[idx[t + 1]] - vv[idx[t]]).cross(vv[idx[t + 2]] - vv[idx[t]])
		if nrm.y > 0.0: # counter-clockwise seen from above -> back face; flip
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	arr[Mesh.ARRAY_INDEX] = idx
	var fixed := ArrayMesh.new()
	fixed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = fixed
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/theme_sea.gdshader")
	for key in ["ripple_a", "ripple_b"]:
		var nt := NoiseTexture2D.new()
		var nz := FastNoiseLite.new()
		nz.seed = rng.randi()
		nz.frequency = 0.02 if key == "ripple_a" else 0.035
		nz.fractal_octaves = 4
		nt.noise = nz
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		nt.width = 512
		nt.height = 512
		nt.generate_mipmaps = true
		mat.set_shader_parameter(key, nt)
	var fnt := NoiseTexture2D.new()
	var fnz := FastNoiseLite.new()
	fnz.seed = rng.randi()
	fnz.frequency = 0.04
	fnz.fractal_octaves = 3
	fnt.noise = fnz
	fnt.seamless = true
	fnt.width = 256
	fnt.height = 256
	fnt.generate_mipmaps = true
	mat.set_shader_parameter("foam_noise", fnt)
	mat.set_shader_parameter("choppiness", 0.8 if preset.get("wet", 0.0) > 0.5 else 0.5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## House colours on the harbour front (subclasses: warmer in the south).
func _harbour_walls() -> Array:
	return WALLS_NORTH


## Stone quay, a breakwater with a light at its end, a timber jetty, moored
## boats, harbour-front houses and sheds.
func _harbour() -> void:
	var L := sea_level
	var u0 := _harbour_u
	var sea3 := Vector3(_sea.x, 0, _sea.y)
	var along3 := Vector3(_perp.x, 0, _perp.y)
	# Quay wall along the apron edge.
	var k0 := _bin(u0 - HARBOUR_HALF)
	var k1 := _bin(u0 + HARBOUR_HALF)
	for k in range(k0, k1):
		var ua := _u0 + k * U_BIN
		var ub := ua + U_BIN
		var sa := _ref[k] + QUAY
		var sb := _ref[k + 1] + QUAY
		var pa := _perp * ua + _sea * sa
		var pb := _perp * ub + _sea * sb
		var a := Vector3(pa.x, 0, pa.y)
		var b := Vector3(pb.x, 0, pb.y)
		var top := L + 1.75
		_quad("stone", Vector3(a.x, L - 6.0, a.z), Vector3(b.x, L - 6.0, b.z), Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), Color(0.78, 0.76, 0.72), sea3)
		# Coping stones and bollards.
		_quad("stone", Vector3(a.x, top, a.z) - sea3 * 1.2, Vector3(b.x, top, b.z) - sea3 * 1.2, Vector3(b.x, top, b.z), Vector3(a.x, top, a.z), Color(0.7, 0.68, 0.64), Vector3.UP)
		if k % 3 == 0:
			_cyl("metal", Vector3(a.x, top, a.z) - sea3 * 0.6, 0.18, 0.14, 0.55, 6, Color(0.1, 0.1, 0.11))
	# Paved apron.
	var mid_ref := _ref[_bin(u0)]
	var apron_c := _from_cs(u0, mid_ref + (QUAY + 44.0) * 0.5)
	_drape("pave", apron_c, along3, sea3, HARBOUR_HALF * 2.0, QUAY - 44.0, 4.0, 0.06, Color(0.85, 0.83, 0.8))
	no_trees.append([apron_c, HARBOUR_HALF + 30.0])
	# Breakwaters: two stone arms closing the basin.
	for side: float in [-1.0, 1.0]:
		var root_u := u0 + side * (HARBOUR_HALF - 4.0)
		var root_s := _ref[_bin(root_u)] + QUAY
		var pts: Array[Vector2] = []
		var reach := 95.0 if side < 0.0 else 70.0
		for j in 14:
			var t := j / 13.0
			var s := root_s + t * reach
			var uu := root_u - side * smoothstep(0.45, 1.0, t) * (HARBOUR_HALF - (18.0 if side < 0.0 else 34.0))
			pts.append(Vector2(uu, s))
		for j in pts.size() - 1:
			var a := _perp * pts[j].x + _sea * pts[j].y
			var b := _perp * pts[j + 1].x + _sea * pts[j + 1].y
			var mid := (a + b) * 0.5
			var dir := (b - a).normalized()
			var c3 := Vector3(mid.x, L - 2.0, mid.y)
			var az := Vector3(dir.x, 0, dir.y)
			var ax := Vector3.UP.cross(az).normalized()
			_box("stone", c3, ax, Vector3.UP, az, Vector3(6.5, 7.6, (b - a).length() + 0.6), Color(0.72, 0.7, 0.66))
			# Tumbled blocks along the outside.
			for q in 2:
				var off := ax * (3.8 + rng.randf() * 1.5) * (1.0 if rng.randf() < 0.5 else -1.0)
				var bc := c3 + off + az * rng.randf_range(-2.0, 2.0) + Vector3.UP * rng.randf_range(0.8, 1.8)
				var rb := Basis(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf() * TAU)
				_box("stone", bc, rb.x, rb.y, rb.z, Vector3(2.2, 1.6, 2.0), Color(0.66, 0.64, 0.6))
		if side < 0.0:
			var tip := pts[pts.size() - 1]
			var tp := _perp * tip.x + _sea * tip.y
			var base := Vector3(tp.x, L + 1.8, tp.y)
			_cyl("plain", base, 1.4, 1.1, 7.0, 10, Color(0.85, 0.18, 0.14))
			_cyl("plain", base + Vector3.UP * 2.2, 1.28, 1.25, 1.4, 10, Color(0.92, 0.92, 0.9), false)
			_cyl("glass", base + Vector3.UP * 7.0, 0.8, 0.8, 1.2, 8, Color(0.3, 0.32, 0.3))
			_cyl("plain", base + Vector3.UP * 8.2, 1.0, 0.0, 0.9, 8, Color(0.15, 0.15, 0.16))
	# Timber jetty into the basin.
	var jr := _ref[_bin(u0 + 10.0)] + QUAY
	for j in 12:
		var s := jr + j * 3.0
		var p := _perp * (u0 + 10.0) + _sea * s
		var c := Vector3(p.x, L + 1.2, p.y)
		_box("plain", c, along3, Vector3.UP, sea3, Vector3(3.2, 0.2, 3.05), Color(0.45, 0.36, 0.26))
		for sx: float in [-1.4, 1.4]:
			_cyl("plain", c + along3 * sx - Vector3.UP * 4.0, 0.14, 0.14, 4.0, 5, Color(0.28, 0.22, 0.16), false)
	# Boats moored in the basin, a couple out at sea.
	var boats := 0
	for tries in 40:
		if boats >= 9:
			break
		var uu := u0 + rng.randf_range(-HARBOUR_HALF + 14.0, HARBOUR_HALF - 14.0)
		var s := _ref[_bin(uu)] + QUAY + rng.randf_range(7.0, 38.0)
		if absf(uu - (u0 + 10.0)) < 6.0:
			continue
		var p := _perp * uu + _sea * s
		var heading := sea3.rotated(Vector3.UP, rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0))
		_boat(Vector3(p.x, L, p.y), heading, rng.randf_range(6.0, 11.0), rng.randf() < 0.45)
		boats += 1
	for j in 3:
		var uu := u0 + rng.randf_range(-400.0, 600.0)
		var s := _ref[_bin(uu)] + rng.randf_range(260.0, 700.0)
		var p := _perp * uu + _sea * s
		_boat(Vector3(p.x, L, p.y), along3.rotated(Vector3.UP, rng.randf() * TAU), rng.randf_range(9.0, 14.0), true)
	# Harbour-front houses on the apron, facing the water, and sheds.
	var hu := u0 - HARBOUR_HALF + 8.0
	while hu < u0 + HARBOUR_HALF - 8.0:
		var w := rng.randf_range(7.0, 10.0)
		var dpt := rng.randf_range(8.0, 10.0)
		var s := _ref[_bin(hu)] + 46.0 + dpt * 0.5
		var c := _from_cs(hu + w * 0.5, s)
		if _fits(c, along3, -sea3, w, dpt, 1.0):
			_mark(c, along3, -sea3, w, dpt)
			var wall: Color = _harbour_walls()[rng.randi() % _harbour_walls().size()]
			var style := 1 if rng.randf() < 0.4 else 0
			_house(c, along3, -sea3, w, dpt, rng.randf_range(6.5, 9.5), wall, ROOFS[rng.randi() % ROOFS.size()], style,
				-1, rng.randf() < 0.7, false, L + 1.75)
			if style == 1:
				_shop_sign(c + sea3 * (dpt * 0.5 + 0.08), sea3, w)
		hu += w + rng.randf_range(0.0, 2.5)


## Hull (tapered, raised bow), cabin or mast; bottom at the waterline.
func _boat(at: Vector3, heading: Vector3, length: float, sail: bool) -> void:
	var az := Vector3(heading.x, 0, heading.z).normalized()
	var ax := Vector3.UP.cross(az).normalized()
	var beam := length * 0.34
	var hull_cols := [Color(0.9, 0.9, 0.88), Color(0.15, 0.28, 0.5), Color(0.62, 0.14, 0.1), Color(0.18, 0.4, 0.3), Color(0.92, 0.86, 0.66)]
	var col: Color = hull_cols[rng.randi() % hull_cols.size()]
	var sheer := 0.9 + length * 0.05
	# Stations along the hull: (along, half-beam, deck height, keel depth)
	var st := [[-0.5, 0.82, sheer, -0.4], [-0.25, 1.0, sheer, -0.6], [0.1, 1.0, sheer + 0.05, -0.65],
		[0.32, 0.8, sheer + 0.2, -0.55], [0.5, 0.05, sheer + 0.45, -0.3]]
	for j in st.size() - 1:
		var a: Array = st[j]
		var b: Array = st[j + 1]
		for side: float in [-1.0, 1.0]:
			var a_top: Vector3 = at + az * a[0] * length + ax * side * a[1] * beam * 0.5 + Vector3.UP * a[2]
			var b_top: Vector3 = at + az * b[0] * length + ax * side * b[1] * beam * 0.5 + Vector3.UP * b[2]
			var a_bot: Vector3 = at + az * a[0] * length + ax * side * a[1] * beam * 0.3 + Vector3.UP * a[3]
			var b_bot: Vector3 = at + az * b[0] * length + ax * side * b[1] * beam * 0.3 + Vector3.UP * b[3]
			_quad("plain", a_bot, b_bot, b_top, a_top, col, ax * side)
			# Keel line
			var ka: Vector3 = at + az * a[0] * length + Vector3.UP * (a[3] - 0.2)
			var kb: Vector3 = at + az * b[0] * length + Vector3.UP * (b[3] - 0.2)
			_quad("plain", ka, kb, b_bot, a_bot, col * 0.5, ax * side - Vector3.UP)
			# Rubbing strake
			_quad("plain", a_top - Vector3.UP * 0.12, b_top - Vector3.UP * 0.12, b_top, a_top, Color(0.25, 0.18, 0.12), ax * side + Vector3.UP * 0.2)
		# Deck
		var dl0: Vector3 = at + az * a[0] * length - ax * a[1] * beam * 0.5 + Vector3.UP * (a[2] - 0.05)
		var dr0: Vector3 = at + az * a[0] * length + ax * a[1] * beam * 0.5 + Vector3.UP * (a[2] - 0.05)
		var dl1: Vector3 = at + az * b[0] * length - ax * b[1] * beam * 0.5 + Vector3.UP * (b[2] - 0.05)
		var dr1: Vector3 = at + az * b[0] * length + ax * b[1] * beam * 0.5 + Vector3.UP * (b[2] - 0.05)
		_quad("plain", dl0, dr0, dr1, dl1, Color(0.62, 0.5, 0.36), Vector3.UP)
	# Transom
	var t0: Array = st[0]
	var tl: Vector3 = at + az * t0[0] * length - ax * t0[1] * beam * 0.5
	var tr: Vector3 = at + az * t0[0] * length + ax * t0[1] * beam * 0.5
	_quad("plain", tl + Vector3.UP * t0[3], tr + Vector3.UP * t0[3], tr + Vector3.UP * t0[2], tl + Vector3.UP * t0[2], col, -az)
	if sail:
		var mast := at + az * length * 0.1 + Vector3.UP * sheer
		_cyl("metal", mast, 0.07, 0.05, length * 1.25, 5, Color(0.8, 0.8, 0.8), false)
		_cyl("plain", mast + Vector3.UP * 1.4 - az * length * 0.2, 0.12, 0.12, 0.25, 6, Color(0.1, 0.2, 0.4))
		_box("plain", mast + Vector3.UP * 1.35 - az * length * 0.22, ax, Vector3.UP, az, Vector3(0.14, 0.14, length * 0.45), Color(0.12, 0.2, 0.4))
	else:
		var cab := at - az * length * 0.12 + Vector3.UP * (sheer + 0.7)
		_box("plain", cab, ax, Vector3.UP, az, Vector3(beam * 0.62, 1.5, length * 0.3), Color(0.92, 0.92, 0.9))
		_box("glass", cab + az * (length * 0.15 + 0.02) + Vector3.UP * 0.3, ax, Vector3.UP, az, Vector3(beam * 0.55, 0.5, 0.05), Color(0.1, 0.12, 0.14))
		_box("plain", cab + Vector3.UP * 0.8, ax, Vector3.UP, az, Vector3(beam * 0.7, 0.1, length * 0.34), Color(0.3, 0.3, 0.32))
		_cyl("metal", cab + Vector3.UP * 0.8, 0.05, 0.04, 2.6, 4, Color(0.7, 0.7, 0.7), false)


func _lighthouse() -> void:
	var k := _bin(_headland_u)
	var s := _ref[k] + _d0[k] - 34.0
	var base := _from_cs(_headland_u, s)
	# The tower stands on the highest nearby ground of the headland.
	for tries in 16:
		var p := _from_cs(_headland_u + rng.randf_range(-25.0, 25.0), s + rng.randf_range(-20.0, 15.0))
		if p.y > base.y:
			base = p
	var h := 26.0
	var bands := 6
	for b in bands:
		var t0 := float(b) / bands
		var t1 := float(b + 1) / bands
		var col := Color(0.92, 0.92, 0.9) if b % 2 == 0 else Color(0.72, 0.12, 0.1)
		_cyl("plain", base + Vector3.UP * (t0 * h - (0.6 if b == 0 else 0.0)), lerpf(3.4, 2.3, t0), lerpf(3.4, 2.3, t1), (t1 - t0) * h + (0.6 if b == 0 else 0.0), 16, col, false)
	var top := base + Vector3.UP * h
	_cyl("metal", top, 3.2, 3.2, 0.35, 16, Color(0.2, 0.2, 0.22))
	for j in 16:
		var a := TAU * j / 16.0
		_cyl("metal", top + Vector3(cos(a), 0, sin(a)) * 3.05, 0.04, 0.04, 1.0, 3, Color(0.2, 0.2, 0.22), false)
	_cyl("glass", top + Vector3.UP * 0.35, 1.7, 1.7, 2.4, 12, Color(0.35, 0.4, 0.38))
	_cyl("lamp", top + Vector3.UP * 0.9, 0.6, 0.6, 1.2, 8, Color(1.0, 0.95, 0.8))
	_cyl("metal", top + Vector3.UP * 2.75, 1.9, 0.2, 1.6, 12, Color(0.12, 0.13, 0.14))
	# Keeper's cottage beside it.
	var sea3 := Vector3(_sea.x, 0, _sea.y)
	var along3 := Vector3(_perp.x, 0, _perp.y)
	var cot := base - sea3 * 13.0 + along3 * 6.0
	cot.y = _ground(cot)
	_house(cot, along3, sea3, 9.0, 7.0, 4.2, Color(0.94, 0.94, 0.92), Color(0.3, 0.32, 0.34), 0, 3, true)
	_box("stone", base - sea3 * 4.0 + Vector3.UP * 0.4, along3, Vector3.UP, sea3, Vector3(16.0, 1.2, 0.6), Color(0.8, 0.8, 0.78))
	no_trees.append([base, 34.0])


## Villas and fishermen's cottages on the land side of the coastal road and
## on the slopes above the harbour.
func _villas() -> void:
	var sea3 := Vector3(_sea.x, 0, _sea.y)
	var placed := 0
	for tries in 900:
		if placed >= 46:
			break
		var i := rng.randi() % n
		var cs := _cs(centers[i])
		var coastal := cs.y > _ref[_bin(cs.x)] - 90.0
		if not coastal:
			continue
		var side := 1.0 if rights[i].dot(sea3) < 0.0 else -1.0 # landward
		if rng.randf() < 0.15:
			side = -side # a few on the sea side, above the cliffs
		var near_harbour := absf(cs.x - _harbour_u) < 180.0
		var back := rail_dist(i, side) + rng.randf_range(6.0, 40.0 if near_harbour else 90.0)
		var c := centers[i] + rights[i] * side * back
		c.y = _ground(c)
		if c.y < sea_level + 2.5:
			continue
		var az := rights[i] * side
		var ax := tangents[i]
		var w := rng.randf_range(8.0, 12.0)
		var d := rng.randf_range(8.0, 11.0)
		if not _fits(c, ax, az, w + 4.0, d + 4.0, 3.0):
			continue
		_mark(c, ax, az, w + 4.0, d + 4.0)
		var walls: Array = WALLS_NORTH if rng.randf() < 0.6 else WALLS_SOUTH
		_house(c, ax, az, w, d, rng.randf_range(5.5, 9.0), walls[rng.randi() % walls.size()],
			ROOFS[rng.randi() % ROOFS.size()], 0, -1, rng.randf() < 0.6, rng.randf() < 0.3)
		no_trees.append([c, 11.0])
		placed += 1


## Boulders along the foot of the cliffs and in the surf: real rock scans
## (Poly Haven rock_07 / rock_09 / stone_01, decimated, assets/vegetation/rocks),
## normalised to ~2 m wide with the pivot at the base, then scaled, turned and
## sunk into the sand; smaller stones scattered round the big ones.
func _shore_rocks() -> void:
	var meshes: Array[String] = []
	var norm: Array[Transform3D] = []
	for id: String in ["rock_07", "rock_09", "stone_01"]:
		var path := "res://assets/vegetation/rocks/%s.glb" % id
		if not ResourceLoader.exists(path):
			continue
		var node := (load(path) as PackedScene).instantiate()
		var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		var aabb := mesh.get_aabb()
		var k := 2.0 / maxf(maxf(aabb.size.x, aabb.size.z), 0.01)
		norm.append(Transform3D(Basis().scaled(Vector3.ONE * k), -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z) * k))
		var nm := "shore_" + id
		_mm_set(nm, mesh, mi.get_active_material(0), 700.0)
		meshes.append(nm)
		node.free()
	if meshes.is_empty():
		return
	var put := func(p: Vector2, sc: float, sink: float) -> void:
		var y := minf(_ground(Vector3(p.x, 0, p.y)), sea_level + 0.5) - sink * sc
		var v := rng.randi() % meshes.size()
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.35))
		b = b.scaled(Vector3(sc * rng.randf_range(0.8, 1.3), sc * rng.randf_range(0.9, 1.4), sc))
		_mm_add(meshes[v], Transform3D(b, Vector3(p.x, y, p.y)) * norm[v])
	for k in range(0, _ref.size(), 2):
		var u := _u0 + k * U_BIN
		if absf(u - _harbour_u) < HARBOUR_HALF + 30.0:
			continue
		var cliff := _fall[k] < 30.0
		var count := rng.randi_range(1, 3) if cliff else (1 if rng.randf() < 0.25 else 0)
		for j in count:
			var s := _ref[k] + _d0[k] + _fall[k] * rng.randf_range(0.8, 1.15) + rng.randf_range(-2.0, 6.0)
			var p := _perp * (u + rng.randf_range(-3.0, 3.0)) + _sea * s
			var sc := rng.randf_range(1.2, 3.6)
			put.call(p, sc, 0.08)
			for q in rng.randi_range(0, 3): # smaller stones round it
				var a := rng.randf() * TAU
				put.call(p + Vector2(cos(a), sin(a)) * sc * rng.randf_range(1.2, 2.2), rng.randf_range(0.25, 0.7), 0.25)


## The ring of distant hills would turn the sea into a lake; once the circuit
## is built, sink its seaward side below the horizon.
func _sink_far_hills() -> void:
	var sinker := HillSinker.new()
	var bounds := AABB(def.points[0], Vector3.ZERO)
	for p: Vector3 in def.points:
		bounds = bounds.expand(p)
	sinker.centre = bounds.get_center()
	sinker.inner = maxf(bounds.size.x, bounds.size.z) * 0.5 + 450.0
	sinker.sea = Vector3(_sea.x, 0, _sea.y)
	sinker.level = sea_level - 40.0
	parent.add_child(sinker)


class HillSinker:
	extends Node
	var centre := Vector3.ZERO
	var inner := 800.0
	var sea := Vector3.LEFT
	var level := -40.0

	func _ready() -> void:
		_sink.call_deferred()

	func _sink() -> void:
		var hills := get_parent().get_node_or_null("Hills") as MeshInstance3D
		if hills and hills.mesh:
			var arr := hills.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for v in verts:
				var d := Vector3(v.x - centre.x, 0, v.z - centre.z)
				var w := smoothstep(0.1, 0.55, d.normalized().dot(sea))
				var p := v
				p.y = lerpf(v.y, level, w)
				st.add_vertex(p)
			st.generate_normals()
			var mesh := st.commit()
			hills.mesh = mesh
		queue_free()


# ================================================================ town

## Straight runs of the lap: [first index, sample count], longest first.
func _straights(limit := 0.1, min_len := 25) -> Array:
	var runs := []
	var start := 0
	while start < n and absf(corner[start]) < limit:
		start += 1 # begin inside a corner so no run wraps
	var i := start
	var run_from := -1
	for k in n + 1:
		var j := _i(start + k)
		var straight := absf(corner[j]) < limit and k < n
		if straight and run_from < 0:
			run_from = start + k
		elif not straight and run_from >= 0:
			var length := start + k - run_from
			if length >= min_len:
				runs.append([_i(run_from), length])
			run_from = -1
	runs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return runs


func _inside_loop(p: Vector3) -> bool:
	var inside := false
	var j := n - 1
	for i in range(0, n, 2):
		var a := centers[i]
		var b := centers[j]
		if (a.z > p.z) != (b.z > p.z) and p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x:
			inside = not inside
		j = i
	return inside


func _shop_atlas() -> void:
	var entries := []
	var cols := [[Color(0.1, 0.16, 0.12), Color(0.85, 0.72, 0.4)], [Color(0.32, 0.08, 0.07), Color(0.93, 0.88, 0.76)],
		[Color(0.08, 0.1, 0.2), Color(0.9, 0.86, 0.72)], [Color(0.86, 0.82, 0.7), Color(0.12, 0.1, 0.08)],
		[Color(0.05, 0.05, 0.05), Color(0.82, 0.68, 0.36)], [Color(0.2, 0.28, 0.32), Color(0.95, 0.94, 0.9)]]
	for k in SHOPS.size():
		var c: Array = cols[k % cols.size()]
		entries.append(["shop%d" % k, Rect2((k % 4) * 512, (k / 4) * 96, 512, 96), c[0], c[1], SHOPS[k], 50, c[1]])
	entries.append(["town", Rect2(0, 640, 1024, 160), Color(0.84, 0.8, 0.7), Color(0.18, 0.12, 0.08), "ALTSTADT", 110, Color(0.4, 0.1, 0.08)])
	entries.append(["clock", Rect2(1024, 640, 256, 256), Color(0.9, 0.88, 0.82), Color(0.08, 0.08, 0.08), "XII\n\nIX       III\n\nVI", 34, Color(0.1, 0.1, 0.1)])
	_sign_material(_atlas(entries))


## A painted fascia sign over a shop window; sometimes a hanging sign too.
func _shop_sign(front_mid: Vector3, out: Vector3, w: float, street := NAN) -> void:
	if is_nan(street):
		street = _ground(front_mid)
	var region: Rect2 = uv["shop%d" % (rng.randi() % SHOPS.size())] if uv.has("shop0") else Rect2()
	if region.size == Vector2.ZERO:
		return
	var sw := minf(w - 1.4, 5.2)
	var c := Vector3(front_mid.x, street + 3.35, front_mid.z) + out * 0.07
	_sign(c, out, sw, sw * 96.0 / 512.0 * 1.15, region)
	if rng.randf() < 0.3:
		var r := (-out).cross(Vector3.UP).normalized()
		var hc := Vector3(front_mid.x, street + 4.4, front_mid.z) + out * 0.9 + r * (w * 0.5 - 1.0)
		_box("metal", hc + Vector3.UP * 0.55 - out * 0.4, r, Vector3.UP, out, Vector3(0.05, 0.05, 1.2), Color(0.1, 0.1, 0.1))
		var reg2: Rect2 = uv["shop%d" % (rng.randi() % SHOPS.size())]
		_sign(hc, r, 1.5, 0.55, reg2)
		_sign(hc, -r, 1.5, 0.55, reg2)


func _town() -> void:
	_shop_atlas()
	var runs := _straights(0.1, 20)
	var used := []
	for r in runs:
		var first: int = r[0]
		var length: int = r[1]
		var contains_start := false
		for k in length:
			if _i(first + k) == 0:
				contains_start = true
		if not contains_start:
			used.append(r)
	if used.size() > 0:
		var r0: Array = used[0]
		var mid := _i(r0[0] + r0[1] / 2)
		var side := -1.0 if _inside_loop(centers[mid] + rights[mid] * 40.0) else 1.0 # square outside the loop
		_market_square(mid, side, minf(r0[1] * STEP * 0.7, 64.0))
		parent.set_meta("town_square", [centers[mid], rights[mid] * side])
		_debug("market square at %s side %d" % [centers[mid], side])
	if used.size() > 1:
		var r1: Array = used[1]
		_town_gate(_i(r1[0] + r1[1] / 2))
		parent.set_meta("town_gate", centers[_i(r1[0] + r1[1] / 2)])
		_debug("town gate at %s" % centers[_i(r1[0] + r1[1] / 2)])
	for side: float in [-1.0, 1.0]:
		_frontage(side)
	_infill()
	_sidewalks()
	# No forest or verge grass in town.
	var bb := AABB(centers[0], Vector3.ZERO)
	for c in centers:
		bb = bb.expand(c)
	no_trees.append([bb.get_center(), maxf(bb.size.x, bb.size.z) * 0.5 + 40.0])
	for i in range(0, n, 36): # the big circle misses the corners of the town
		no_trees.append([centers[i], 62.0])


func _town_colours() -> Array:
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	if rng.randf() < 0.18:
		roof = Color(0.34, 0.34, 0.37) # slate
	return [WALLS_NORTH[rng.randi() % WALLS_NORTH.size()], roof]


## Continuous rows of houses and shops just beyond the guardrail.
func _frontage(side: float) -> void:
	var i := 0
	var misses := 0
	while i < n:
		var w := rng.randf_range(6.5, 11.5)
		var dep := rng.randf_range(10.0, 14.0)
		var mid := _i(i + int(w * 0.5 / STEP))
		var front := maxf(rail_dist(mid, side) + 1.5, 13.6)
		var az := rights[mid] * side
		var ax := tangents[mid]
		var c := centers[mid] + az * (front + dep * 0.5)
		if _fits(c, ax, az, w, dep, 1.0):
			_mark(c, ax, az, w, dep)
			var cols := _town_colours()
			var floors := rng.randi_range(2, 4)
			var shop := rng.randf() < 0.5
			var h := (3.9 if shop else 3.3) + floors * 3.0 - 2.6
			var street := _ground(c - az * dep * 0.5)
			_house(c, ax, az, w, dep, h, cols[0], cols[1], 1 if shop else 0, -1, rng.randf() < 0.65, false, street)
			if shop:
				_shop_sign(c - az * (dep * 0.5), -az, w, street)
			i += int(ceil(w / STEP))
			misses = 0
		else:
			i += 1
			misses += 1
			# Where no house fits (tight corners, props), a garden wall.
			if misses == 3 and _off_track(centers[_i(i)] + rights[_i(i)] * side * (front - 0.5), 0.3) \
					and _foreign_clear(centers[_i(i)] + rights[_i(i)] * side * front, 4.0):
				var wc := centers[_i(i)] + rights[_i(i)] * side * (front - 0.3)
				wc.y = _ground(wc) + 0.6
				_hbox("stone", wc, tangents[_i(i)], Vector3(0.5, 2.2, 6.2), Color(0.85, 0.8, 0.72))
				misses = 0


## Blocks behind the street fronts: smaller houses, courtyards, garden trees.
func _infill() -> void:
	var bb := AABB(centers[0], Vector3.ZERO)
	for c in centers:
		bb = bb.expand(c)
	bb = bb.grow(80.0)
	var garden := _tree_mesh(2.6, 5.5, 1.8, [Color(0.12, 0.2, 0.08), Color(0.3, 0.42, 0.16)], 0.35, 0.1, 10)
	_tree_set("garden_tree", "maple_0", false, 500.0, garden)
	var step := 12.0
	var x := bb.position.x
	while x < bb.end.x:
		var z := bb.position.z
		while z < bb.end.z:
			var p := Vector3(x + rng.randf_range(-3, 3), 0, z + rng.randf_range(-3, 3))
			z += step
			var i := _nearest(p, 90.0)
			var inside := _inside_loop(p)
			if i < 0 and not inside:
				continue
			if i >= 0 and Vector2(centers[i].x - p.x, centers[i].z - p.z).length() < 27.0:
				continue
			p.y = _ground(p)
			if rng.randf() < 0.14:
				if _off_track(p, 6.0) and not _occ.has(_okey(p)) and _foreign_clear(p, 3.0):
					var s := rng.randf_range(0.8, 1.3)
					_mm_add("garden_tree", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
				continue
			var az := rights[i] if i >= 0 else Vector3.FORWARD
			if i >= 0 and (p - centers[i]).dot(az) < 0.0:
				az = -az
			var ax := Vector3.UP.cross(az).normalized()
			var w := rng.randf_range(8.0, 12.5)
			var dep := rng.randf_range(8.0, 12.0)
			if not _fits(p, ax, az, w, dep, 2.0):
				continue
			_mark(p, ax, az, w, dep)
			var cols := _town_colours()
			_house(p, ax, az, w, dep, rng.randf_range(5.0, 9.5), cols[0], cols[1], 0, -1, rng.randf() < 0.6)
		x += step


## Paved pavements from the kerb (or gravel) out past the rail.
func _sidewalks() -> void:
	for side: float in [-1.0, 1.0]:
		var prev_in := Vector3.ZERO
		var prev_out := Vector3.ZERO
		for k in n + 1:
			var i := _i(k)
			var g := gravel_depth(i, side)
			var inner := half + TrackBuilder.CURB_WIDTH + (g + 0.3 if g > 0.3 else 0.0)
			var outer := maxf(rail_dist(i, side) + 1.6, 13.8)
			var a := _on_ground(centers[i] + rights[i] * side * inner, 0.07)
			var b := _on_ground(centers[i] + rights[i] * side * outer, 0.07)
			if k > 0:
				_quad("pave", prev_in, a, b, prev_out, Color(0.8, 0.78, 0.75), Vector3.UP)
			prev_in = a
			prev_out = b


func _market_square(i: int, side: float, length: float) -> void:
	var ax := tangents[i]
	var az := rights[i] * side
	var depth := 46.0
	var front := rail_dist(i, side) + 1.6
	var c := centers[i] + az * (front + depth * 0.5)
	c.y = _ground(c)
	_mark(c, ax, az, length, depth)
	_drape("pave", c, ax, az, length, depth, 4.0, 0.08, Color(0.9, 0.87, 0.82))
	# Fountain: octagonal stone basin, water, column with a bowl.
	var fc := _on_ground(c)
	_cyl("stone", fc - Vector3.UP * 0.3, 4.2, 4.2, 1.1, 8, Color(0.82, 0.78, 0.72))
	_cyl("water", fc + Vector3.UP * 0.72, 3.8, 3.8, 0.02, 8, Color(0.08, 0.14, 0.16))
	_cyl("stone", fc, 0.45, 0.35, 3.2, 8, Color(0.8, 0.76, 0.7))
	_cyl("stone", fc + Vector3.UP * 2.4, 0.3, 1.4, 0.5, 8, Color(0.8, 0.76, 0.7))
	_cyl("stone", fc + Vector3.UP * 3.2, 0.3, 0.2, 1.4, 6, Color(0.7, 0.66, 0.6))
	# Church at the back of the square, facade and tower facing it.
	var church_c := c + az * (depth * 0.5 + 16.0)
	church_c.y = _ground(church_c)
	_mark(church_c, ax, az, 16.0, 30.0)
	var nave_h := 13.0
	var wall := Color(0.86, 0.82, 0.74)
	var y0 := church_c.y - 1.5
	_box("stone", Vector3(church_c.x, y0 + (nave_h + 1.5) * 0.5, church_c.z), ax, Vector3.UP, az, Vector3(14.0, nave_h + 1.5, 28.0), wall)
	_gable(Vector3(church_c.x, church_c.y + nave_h, church_c.z), az, ax, 28.0, 14.0, 7.5, 0.5, Color(0.36, 0.36, 0.4), wall, "stone")
	for s: float in [-1.0, 1.0]:
		for k in 5:
			var wc := church_c + ax * s * 7.02 + az * (k - 2) * 5.0 + Vector3.UP * 6.5
			_box("glass", wc, ax, Vector3.UP, az, Vector3(0.06, 5.0, 1.5), Color(0.12, 0.14, 0.2))
			_cyl("glass", wc + Vector3.UP * 2.5 - ax * 0.03 * s, 0.75, 0.0, 0.8, 4, Color(0.12, 0.14, 0.2), false)
	var tower := c + az * (depth * 0.5 + 1.0 + 3.8)
	tower.y = _ground(tower)
	var th := 30.0
	_box("stone", Vector3(tower.x, tower.y - 1.5 + (th + 1.5) * 0.5, tower.z), ax, Vector3.UP, az, Vector3(7.6, th + 1.5, 7.6), wall)
	_box("stone", Vector3(tower.x, tower.y + th + 0.3, tower.z), ax, Vector3.UP, az, Vector3(8.4, 0.6, 8.4), wall * 0.9)
	var spire_b := Basis(Vector3.UP, PI * 0.25)
	for k in 4:
		var a := k * PI * 0.5
		var dir := (ax * cos(a) + az * sin(a))
		_box("glass", Vector3(tower.x, tower.y + th - 4.0, tower.z) + dir * 3.82, dir.cross(Vector3.UP), Vector3.UP, dir, Vector3(1.4, 3.2, 0.05), Color(0.06, 0.06, 0.07))
	_cyl("roof", Vector3(tower.x, tower.y + th + 0.6, tower.z), 5.3, 0.0, 15.0, 4, Color(0.25, 0.4, 0.34))
	_cyl("metal", Vector3(tower.x, tower.y + th + 15.4, tower.z), 0.05, 0.05, 2.2, 4, Color(0.7, 0.6, 0.3), false)
	_sign(Vector3(tower.x, tower.y + th - 9.0, tower.z) - az * 3.84, -az, 2.8, 2.8, uv.clock)
	_door(tower - az * 3.82, -az, 2.4, 4.2)
	# Market stalls with striped awnings, and townsfolk.
	var awnings := [[Color(0.75, 0.15, 0.12), Color(0.92, 0.9, 0.85)], [Color(0.16, 0.3, 0.2), Color(0.9, 0.88, 0.8)],
		[Color(0.2, 0.26, 0.46), Color(0.92, 0.9, 0.85)], [Color(0.8, 0.6, 0.15), Color(0.9, 0.88, 0.8)]]
	var stalls := 0
	for tries in 40:
		if stalls >= 9:
			break
		var p := c + ax * rng.randf_range(-length * 0.42, length * 0.42) + az * rng.randf_range(-depth * 0.4, depth * 0.35)
		if Vector2(p.x - c.x, p.z - c.z).length() < 8.0:
			continue
		p.y = _ground(p)
		_stall(p, ax, az, awnings[rng.randi() % awnings.size()])
		stalls += 1
	for k in 60:
		var p := c + ax * rng.randf_range(-length * 0.46, length * 0.46) + az * rng.randf_range(-depth * 0.46, depth * 0.46)
		p.y = _ground(p)
		_person(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p), PeopleKit.Role.SPECTATOR)
	# Houses around the two open sides, facing into the square.
	for s: float in [-1.0, 1.0]:
		var along := -depth * 0.5
		while along < depth * 0.5 + 14.0:
			var w := rng.randf_range(7.0, 10.0)
			var dep := rng.randf_range(10.0, 12.0)
			var hc := c + ax * s * (length * 0.5 + dep * 0.5 + 0.4) + az * (along + w * 0.5)
			hc.y = _ground(hc)
			var haz := ax * s
			var hax := az
			if _fits(hc, hax, haz, w, dep, 1.0):
				_mark(hc, hax, haz, w, dep)
				var cols := _town_colours()
				var street := _ground(hc - haz * dep * 0.5)
				var shop := rng.randf() < 0.6
				_house(hc, hax, haz, w, dep, rng.randf_range(8.5, 12.0), cols[0], cols[1], 1 if shop else 0, -1, rng.randf() < 0.5, false, street)
				if shop:
					_shop_sign(hc - haz * dep * 0.5, -haz, w, street)
			along += w
	foreign.append([c, 0.0]) # keep later rows from crowding the square


func _door(c: Vector3, out: Vector3, w: float, h: float) -> void:
	var r := (-out).cross(Vector3.UP).normalized()
	_box("plain", c + out * 0.04 + Vector3.UP * h * 0.5, r, Vector3.UP, out, Vector3(w, h, 0.1), Color(0.25, 0.15, 0.08))


func _stall(p: Vector3, ax: Vector3, az: Vector3, stripes: Array) -> void:
	var w := 3.2
	var d := 2.2
	_box("plain", p + Vector3.UP * 0.45, ax, Vector3.UP, az, Vector3(w, 0.9, d * 0.7), Color(0.42, 0.3, 0.2))
	_box("plain", p + Vector3.UP * 0.95, ax, Vector3.UP, az, Vector3(w - 0.2, 0.12, d * 0.6), [Color(0.7, 0.2, 0.1), Color(0.8, 0.65, 0.2), Color(0.35, 0.5, 0.2)][rng.randi() % 3])
	for sx: float in [-0.5, 0.5]:
		for sz: float in [-0.5, 0.5]:
			_box("plain", p + ax * sx * w + az * sz * d + Vector3.UP * 1.25, ax, Vector3.UP, az, Vector3(0.08, 2.5, 0.08), Color(0.3, 0.22, 0.15))
	var strips := 8
	for k in strips:
		var x0 := (k / float(strips) - 0.5) * w
		var x1 := ((k + 1) / float(strips) - 0.5) * w
		var col: Color = stripes[k % 2]
		var a := p + ax * x0 - az * d * 0.62 + Vector3.UP * 2.2
		var b := p + ax * x1 - az * d * 0.62 + Vector3.UP * 2.2
		var c2 := p + ax * x1 + az * d * 0.5 + Vector3.UP * 2.65
		var d2 := p + ax * x0 + az * d * 0.5 + Vector3.UP * 2.65
		_quad("plain", a, b, c2, d2, col, Vector3.UP - az * 0.3)


## Old town gate: two stone towers either side of the road, a covered bridge
## over it and the town wall running off both ways.
func _town_gate(i: int) -> void:
	var t := tangents[i]
	var r := rights[i]
	var lat := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 4.4
	var road_y := centers[i].y
	var wall := Color(0.8, 0.76, 0.68)
	var th := 18.0
	for s: float in [-1.0, 1.0]:
		var c := centers[i] + r * s * lat
		c.y = _ground(c)
		_mark(c, t, r * s, 8.0, 8.0)
		_box("stone", Vector3(c.x, c.y - 1.5 + (th + 1.5) * 0.5, c.z), t, Vector3.UP, r, Vector3(7.0, th + 1.5, 7.0), wall)
		_hip(Vector3(c.x, c.y + th, c.z), t, r, 7.0, 7.0, 5.5, 0.6, Color(0.55, 0.3, 0.22))
		for k in 3:
			var wc := Vector3(c.x, c.y + 7.0 + k * 3.6, c.z) - r * s * 3.52
			_box("glass", wc, t, Vector3.UP, r, Vector3(0.7, 1.4, 0.06), Color(0.05, 0.05, 0.06))
		# Town wall with crenellations, heading away from the road until it
		# meets something.
		var along := 0.0
		while along < 90.0:
			var wc := c + r * s * (4.5 + along + 1.5)
			wc.y = _ground(wc)
			if not _off_track(wc, 2.0) or _occ.has(_okey(wc)) or not _foreign_clear(wc, 2.0):
				break
			_mark(wc, r, t, 3.2, 2.6)
			_box("stone", Vector3(wc.x, wc.y - 1.0 + 4.0, wc.z), r, Vector3.UP, t, Vector3(3.05, 8.0, 2.2), wall * 0.95)
			if int(along / 3.0) % 2 == 0:
				_box("stone", Vector3(wc.x, wc.y + 7.6, wc.z), r, Vector3.UP, t, Vector3(1.4, 1.2, 2.2), wall * 0.95)
			along += 3.0
	# The bridge over the road.
	var bc := centers[i] + Vector3.UP * 9.8
	bc.y = road_y + 9.8
	var span := lat * 2.0 - 7.0
	_box("stone", bc, r, Vector3.UP, t, Vector3(span, 4.4, 6.0), wall)
	_box("stone", bc - Vector3.UP * 2.25, r, Vector3.UP, t, Vector3(span, 0.3, 6.6), wall * 0.85)
	_gable(bc + Vector3.UP * 2.2, r, t, span, 6.0, 3.2, 0.5, Color(0.55, 0.3, 0.22), wall, "stone")
	for s: float in [-1.0, 1.0]:
		_sign(bc + t * s * 3.04, t * s, 7.0, 1.1, uv.town)
		for k in 4:
			_box("glass", bc + t * s * 3.02 + r * (k - 1.5) * 4.2 + Vector3.UP * 1.2, r, Vector3.UP, t, Vector3(0.9, 1.1, 0.06), Color(0.05, 0.05, 0.06))


# ================================================================ autodromo

func _autodromo() -> void:
	var entries := [
		["title", Rect2(0, 0, 2048, 160), Color(0.07, 0.2, 0.13), Color(0.95, 0.94, 0.9), "AUTODROMO DI VALTELLINA", 118, Color(0.72, 0.1, 0.1)],
		["board", Rect2(0, 160, 1024, 512), Color(0.03, 0.03, 0.03), Color(0.95, 0.78, 0.25),
			"1   11   BRAMBILLA\n2   27   MARZOTTO\n3    5   CASTELLI\n4   18   FERRARIS\n5    3   GALLI\n6   44   VILLORESI", 58, Color(0.0, 0.0, 0.0, 0.0)],
		["clockface", Rect2(1024, 160, 512, 512), Color(0.9, 0.9, 0.86), Color(0.05, 0.05, 0.05), "12\n9         3\n6", 70, Color(0.05, 0.05, 0.05)],
		["cantina", Rect2(0, 672, 1024, 160), Color(0.45, 0.07, 0.1), Color(0.95, 0.9, 0.78), "CANTINE SASSELLA", 100, Color(0.85, 0.7, 0.35)],
		["benzina", Rect2(1024, 672, 1024, 160), Color(0.92, 0.88, 0.76), Color(0.1, 0.1, 0.1), "BENZINA ORIONE", 100, Color(0.1, 0.35, 0.2)],
		["gomme", Rect2(1536, 160, 512, 256), Color(0.1, 0.1, 0.12), Color(0.95, 0.8, 0.2), "GOMME\nVESTA", 90, Color(0.95, 0.8, 0.2)],
		["caffe", Rect2(1536, 416, 512, 256), Color(0.28, 0.15, 0.08), Color(0.95, 0.9, 0.8), "CAFFÈ\nLOMBARDO", 80, Color(0.95, 0.9, 0.8)],
	]
	_sign_material(_atlas(entries))
	_timing_tower()
	_long_stands()
	_farmhouses()
	_vineyards()
	_poplar_rows()
	_debug("stands %d, farms %d, vineyards %d" % [stats.get("stands", 0), stats.get("farms", 0), stats.get("vineyards", 0)])


func _timing_tower() -> void:
	var i := 4
	var side := 1.0
	var lat := rail_dist(i, side) + 44.0
	var c := centers[i] + rights[i] * side * lat
	c.y = _ground(c)
	var ax := tangents[i]
	var az := rights[i] * side
	var h := 30.0
	var col := Color(0.86, 0.85, 0.8)
	_box("plain", Vector3(c.x, c.y - 1.0 + (h + 1.0) * 0.5, c.z), ax, Vector3.UP, az, Vector3(4.5, h + 1.0, 4.5), col)
	# Glazed commentary cabin near the top, a flat roof and a flag mast.
	_box("glass", Vector3(c.x, c.y + h - 5.0, c.z), ax, Vector3.UP, az, Vector3(6.2, 3.0, 6.2), Color(0.1, 0.13, 0.15))
	_box("plain", Vector3(c.x, c.y + h - 3.3, c.z), ax, Vector3.UP, az, Vector3(7.0, 0.4, 7.0), col)
	_box("plain", Vector3(c.x, c.y + h - 6.6, c.z), ax, Vector3.UP, az, Vector3(6.6, 0.3, 6.6), col)
	_box("plain", Vector3(c.x, c.y + h + 0.2, c.z), ax, Vector3.UP, az, Vector3(5.2, 0.4, 5.2), col)
	_cyl("metal", Vector3(c.x, c.y + h + 0.4, c.z), 0.08, 0.05, 7.0, 5, Color(0.8, 0.8, 0.8), false)
	# Scoreboard facing the track, on a steel frame, with the clock above.
	var face := c - az * 2.3
	var board_c := Vector3(face.x, c.y + 13.0, face.z) - az * 0.6
	_box("metal", board_c + az * 0.3, ax, Vector3.UP, az, Vector3(12.6, 7.4, 0.5), Color(0.12, 0.12, 0.13))
	_sign(board_c - az * 0.02, -az, 12.0, 6.0, uv.board)
	_sign(Vector3(face.x, c.y + h - 10.0, face.z) - az * 0.02, -az, 4.0, 4.0, uv.clockface)
	_sign(Vector3(face.x, c.y + 20.0, face.z) - az * 0.3, -az, 14.0, 1.1, uv.title)
	_box("metal", Vector3(face.x, c.y + 20.0, face.z), ax, Vector3.UP, az, Vector3(14.2, 1.3, 0.4), Color(0.1, 0.1, 0.1))
	no_trees.append([c, 14.0])


## Long covered grandstands: both ends of the main straight and the outside
## of the big corners, wherever older props leave room.
func _long_stands() -> void:
	var runs := []
	var back := 0
	while back < 160 and absf(corner[_i(-back)]) < 0.12:
		back += 1
	var fwd := 0
	while fwd < 240 and absf(corner[_i(fwd)]) < 0.12:
		fwd += 1
	runs.append([-back + 4, 0, -1.0])
	runs.append([0, fwd - 6, -1.0])
	# Outside of the corners with the most turning: the big sweepers.
	var corners := []
	var in_c := false
	var entry := 0
	for i in n:
		var c: float = absf(corner[i])
		if not in_c and c > 0.35:
			in_c = true
			entry = i
		elif in_c and c < 0.25:
			in_c = false
			var apex := (entry + i) / 2
			corners.append([entry, i, 1.0 if corner[apex] > 0.0 else -1.0, i - entry])
	corners.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3])
	for k in mini(3, corners.size()):
		var cc: Array = corners[k]
		runs.append([cc[0] - 10, cc[1] + 10, cc[2]])
	var boards := ["cantina", "benzina", "gomme", "caffe"]
	var made := 0
	for r in runs:
		var i0: int = r[0]
		var i1: int = r[1]
		var side: float = r[2]
		# Split into pieces that stay clear of older props.
		var piece_from := -1
		for i in range(i0, i1 + 1):
			var lat := rail_dist(i, side) + 4.0
			var p := centers[_i(i)] + rights[_i(i)] * side * (lat + 6.0)
			var ok := _foreign_clear(p, 7.0) and not _occ.has(_okey(p)) and i < i1
			if ok and piece_from < 0:
				piece_from = i
			elif not ok and piece_from >= 0:
				if i - piece_from >= 18:
					_stand(piece_from, i - 1, side, boards[made % boards.size()])
					made += 1
				else:
					_debug("stand piece too short: %d" % (i - piece_from))
				piece_from = -1


## One covered stand following the track from sample i0 to i1.
func _stand(i0: int, i1: int, side: float, board: String) -> void:
	var tiers := 11
	var tread := 0.9
	var riser := 0.48
	var lat := 0.0
	for i in range(i0, i1 + 1):
		lat = maxf(lat, rail_dist(i, side) + 4.0)
	var concrete := Color(0.7, 0.69, 0.66)
	var seat_cols := [Color(0.62, 0.1, 0.09), Color(0.12, 0.3, 0.2), Color(0.85, 0.83, 0.78)]
	var seat: Color = seat_cols[rng.randi() % seat_cols.size()]
	var step := 3
	var base_y := INF
	for i in range(i0, i1 + 1, step):
		base_y = minf(base_y, _ground(centers[_i(i)] + rights[_i(i)] * side * lat))
	var roof_h := base_y + 1.4 + tiers * riser + 4.2
	var k := i0
	var col_count := 0
	while k < i1:
		var j := mini(k + step, i1)
		var a := _i(k)
		var b := _i(j)
		var ra := rights[a] * side
		var rb := rights[b] * side
		var out := (ra + rb).normalized()
		for t in tiers:
			var y := base_y + 1.2 + t * riser
			var l0 := lat + t * tread
			var pa0 := centers[a] + ra * l0
			var pb0 := centers[b] + rb * l0
			var pa1 := centers[a] + ra * (l0 + tread)
			var pb1 := centers[b] + rb * (l0 + tread)
			pa0.y = y
			pb0.y = y
			pa1.y = y
			pb1.y = y
			# Riser up to this tread, then the tread (seat strip at its front).
			_quad("plain", pa0 - Vector3.UP * riser, pb0 - Vector3.UP * riser, pb0, pa0, concrete * 0.9, -out)
			var sa := pa0.lerp(pa1, 0.45)
			var sb := pb0.lerp(pb1, 0.45)
			_quad("plain", pa0, pb0, sb, sa, seat, Vector3.UP)
			_quad("plain", sa, sb, pb1, pa1, concrete, Vector3.UP)
			# Spectators, sparse enough to keep the triangle count sane.
			var seg_len := pa0.distance_to(pb0)
			var spots := int(seg_len / 0.75)
			for q in spots:
				if rng.randf() < 0.62:
					continue
				var f := (q + 0.5) / spots
				var pos := pa0.lerp(pb0, f).lerp(pa1.lerp(pb1, f), 0.35)
				var fwd := -out
				var bas := Basis.looking_at(fwd, Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.3, 0.3))
				_person(Transform3D(bas, pos), PeopleKit.Role.SEATED)
		# Front wall, back wall, roof, columns.
		var fa := centers[a] + ra * lat
		var fb := centers[b] + rb * lat
		fa.y = base_y
		fb.y = base_y
		_quad("plain", fa - Vector3.UP * 2.0, fb - Vector3.UP * 2.0, fb + Vector3.UP * 1.2, fa + Vector3.UP * 1.2, concrete * 0.85, -out)
		var back := lat + tiers * tread
		var ba := centers[a] + ra * back
		var bb := centers[b] + rb * back
		ba.y = base_y - 2.0
		bb.y = base_y - 2.0
		var top := roof_h + 0.6
		_quad("plain", ba, bb, Vector3(bb.x, top, bb.z), Vector3(ba.x, top, ba.z), concrete * 0.8, out)
		_quad("plain", ba, bb, Vector3(bb.x, top, bb.z), Vector3(ba.x, top, ba.z), concrete * 0.75, -out)
		var ea := centers[a] + ra * (lat - 1.6)
		var eb := centers[b] + rb * (lat - 1.6)
		ea.y = roof_h + 0.8
		eb.y = roof_h + 0.8
		var ta := Vector3(ba.x, top, ba.z)
		var tb := Vector3(bb.x, top, bb.z)
		_quad("plain", ta, tb, eb, ea, Color(0.5, 0.51, 0.52), Vector3.UP)
		_quad("plain", ta - Vector3.UP * 0.12, tb - Vector3.UP * 0.12, eb - Vector3.UP * 0.12, ea - Vector3.UP * 0.12, Color(0.3, 0.31, 0.32), -Vector3.UP)
		_quad("plain", ea - Vector3.UP * 0.9, eb - Vector3.UP * 0.9, eb, ea, Color(0.9, 0.9, 0.87), -out)
		if col_count % 3 == 0:
			var cp := centers[a] + ra * (lat + 0.3)
			cp.y = base_y + 1.2
			_box("metal", cp + Vector3.UP * (roof_h - cp.y) * 0.5, tangents[a], Vector3.UP, ra, Vector3(0.25, roof_h - cp.y + 0.6, 0.25), Color(0.25, 0.26, 0.27))
		if col_count % 9 == 4:
			var sc := centers[a].lerp(centers[b], 0.5) + out * (lat - 1.62)
			sc.y = roof_h + 0.35
			_sign(sc, -out, 5.4, 0.85, uv[board])
		col_count += 1
		k = j
	# End walls.
	for e in [[i0, -1.0], [i1, 1.0]]:
		var ii := _i(e[0])
		var r := rights[ii] * side
		var p0 := centers[ii] + r * lat
		var p1 := centers[ii] + r * (lat + tiers * tread)
		p0.y = base_y - 2.0
		p1.y = base_y - 2.0
		var tan_out: Vector3 = tangents[ii] * float(e[1])
		_quad("plain", p0, p1, Vector3(p1.x, roof_h + 0.6, p1.z), Vector3(p0.x, base_y + 1.2, p0.z), concrete * 0.8, tan_out)
	stats.stands = stats.get("stands", 0) + 1
	var mid := _i((i0 + i1) / 2)
	var span := (i1 - i0) * STEP
	no_trees.append([centers[mid] + rights[mid] * side * (lat + 6.0), span * 0.5 + 12.0])
	for i in range(i0, i1 + 1, 3):
		var p := centers[_i(i)] + rights[_i(i)] * side * (lat + 5.0)
		_mark(p, tangents[_i(i)], rights[_i(i)], 7.0, 12.0)


## Terracotta farmhouses on the hillsides, with cypresses and a stone pine.
func _farmhouses() -> void:
	var cypress := _tree_mesh(1.0, 11.0, 0.8, [Color(0.05, 0.1, 0.05), Color(0.16, 0.24, 0.1)], 0.18, 0.88, 10)
	var pine := _tree_mesh(5.2, 3.2, 8.5, [Color(0.1, 0.17, 0.07), Color(0.24, 0.32, 0.12)], 0.3, 0.2, 12)
	_tree_set("cypress", "cypress_1", true, 900.0, cypress)
	_tree_set("stone_pine", "stonepine_0", true, 900.0, pine)
	var made := 0
	for tries in 400:
		if made >= 11:
			break
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var c := centers[i] + rights[i] * side * rng.randf_range(90.0, 330.0)
		c.y = _ground(c)
		if _tdist(c, 80.0) < 80.0 or not _foreign_clear(c, 30.0) or _occ.has(_okey(c)):
			continue
		var ok := true
		for z in no_trees:
			if (z[0] as Vector3).distance_to(c) < (z[1] as float) + 25.0:
				ok = false
		if not ok:
			continue
		var ang := rng.randf() * TAU
		var ax := Vector3(cos(ang), 0, sin(ang))
		var az := Vector3.UP.cross(ax).normalized()
		var wall: Color = WALLS_SOUTH[rng.randi() % WALLS_SOUTH.size()]
		var roof := Color(0.78, 0.46, 0.34)
		var w := rng.randf_range(15.0, 21.0)
		var d := rng.randf_range(9.0, 11.0)
		_house(c, ax, az, w, d, rng.randf_range(6.8, 8.2), wall, roof, 3, -1, true, rng.randf() < 0.6)
		# Lower barn wing and, often, the dovecote tower.
		var wing := c + ax * (w * 0.5 + 5.0) + az * 2.0
		wing.y = _ground(wing)
		_house(wing, ax, az, 10.0, d + 2.0, 4.8, wall * 0.95, roof * 0.95, 3, -1, true, false)
		if rng.randf() < 0.65:
			var tw := c - ax * (w * 0.5 - 2.5) + az * 0.5
			tw.y = _ground(tw)
			_house(tw, ax, az, 4.2, 4.2, 11.5, wall, roof, 3, -1, true, true)
		_mark(c, ax, az, w + 30.0, d + 30.0)
		no_trees.append([c, 34.0])
		for q in rng.randi_range(4, 9):
			var p := c + ax * rng.randf_range(-w, w) * 0.9 + az * (d * 0.5 + rng.randf_range(5.0, 16.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			p.y = _ground(p) - 0.2
			var s := rng.randf_range(0.85, 1.25)
			_mm_add("cypress", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.3), s)), p))
		if rng.randf() < 0.7:
			var p := c + az * (d * 0.5 + 14.0) + ax * rng.randf_range(-6.0, 6.0)
			p.y = _ground(p) - 0.2
			_mm_add("stone_pine", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
		# A cypress-lined drive running off towards the circuit.
		var drive := (centers[i] - c)
		drive.y = 0
		drive = drive.normalized()
		for q in range(2, 12):
			for s2: float in [-1.0, 1.0]:
				var p := c + drive * (d + q * 7.0) + drive.cross(Vector3.UP) * s2 * 3.2
				if _tdist(p, 50.0) < 50.0:
					break
				p.y = _ground(p) - 0.2
				var s := rng.randf_range(0.9, 1.15)
				_mm_add("cypress", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
		made += 1
	stats.farms = made


## A vine row segment: trunks + a lumpy leafy canopy strip, 6 m long.
func _vine_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	var len := 6.0
	var prof := [Vector2(-0.12, 0.45), Vector2(-0.34, 0.8), Vector2(-0.3, 1.45), Vector2(0.0, 1.6), Vector2(0.3, 1.45), Vector2(0.34, 0.8), Vector2(0.12, 0.45)]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	var rings: Array[PackedVector3Array] = []
	for s in segs + 1:
		var z := (s / float(segs) - 0.5) * len
		var ring := PackedVector3Array()
		for p: Vector2 in prof:
			var j := noise.get_noise_2d(z * 2.0, p.y * 3.0) * 0.12
			ring.append(Vector3(p.x * (1.0 + j * 2.0), p.y + j, z))
		rings.append(ring)
	for s in segs:
		for q in prof.size() - 1:
			var a := rings[s][q]
			var b := rings[s][q + 1]
			var c := rings[s + 1][q + 1]
			var d := rings[s + 1][q]
			var col := Color(0.2, 0.3, 0.08).lerp(Color(0.38, 0.46, 0.14), clampf((a.y - 0.45) / 1.2 + noise.get_noise_1d(a.z * 3.0) * 0.3, 0.0, 1.0))
			for v in [a, c, b, a, d, c]:
				st.set_color(col)
				st.add_vertex(v)
	# Trunks / posts.
	for z: float in [-2.8, 0.0, 2.8]:
		var post := [Vector3(-0.04, 0, z), Vector3(0.04, 0, z), Vector3(0.04, 1.6, z), Vector3(-0.04, 1.6, z)]
		for v in [post[0], post[2], post[1], post[0], post[3], post[2]]:
			st.set_color(Color(0.3, 0.24, 0.17))
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Vineyards: rows of vines on the slopes, running downhill, on bare soil.
func _vineyards() -> void:
	_mm_set("vines", _vine_mesh(), mats.foliage, 480.0, false)
	var made := 0
	for tries in 500:
		if made >= 14:
			break
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var c := centers[i] + rights[i] * side * rng.randf_range(75.0, 300.0)
		c.y = _ground(c)
		# Downhill direction from the terrain gradient.
		var gx := _ground(c + Vector3(4, 0, 0)) - _ground(c - Vector3(4, 0, 0))
		var gz := _ground(c + Vector3(0, 0, 4)) - _ground(c - Vector3(0, 0, 4))
		var grad := Vector3(gx, 0, gz)
		if grad.length() < 0.12:
			continue # vines like a slope
		var az := grad.normalized() # rows run up/down the slope
		var ax := Vector3.UP.cross(az).normalized()
		var w := rng.randf_range(60.0, 110.0)
		var d := rng.randf_range(45.0, 85.0)
		var ok := true
		for p in _footprint(c, ax, az, w, d, 20.0):
			if _tdist(p, 42.0) < 42.0 or _occ.has(_okey(p)) or not _foreign_clear(p, 0.0):
				ok = false
				break
		if not ok:
			continue
		for z in no_trees:
			if (z[0] as Vector3).distance_to(c) < (z[1] as float) + maxf(w, d) * 0.5:
				ok = false
				break
		if not ok:
			continue
		_mark(c, ax, az, w, d)
		_drape("soil", c, ax, az, w + 3.0, d + 3.0, 6.0, 0.06, Color(0.95, 0.88, 0.8))
		var rows := int(w / 2.6)
		for r in rows:
			var x := (r / float(rows - 1) - 0.5) * (w - 2.0)
			var seg := int(d / 6.0)
			for q in seg:
				var z := (q + 0.5) / seg * d - d * 0.5
				var p := c + ax * x + az * z
				var p0 := _on_ground(p - az * 3.0)
				var p1 := _on_ground(p + az * 3.0)
				var fwd := (p1 - p0).normalized()
				var basis := Basis(ax, fwd.cross(ax).normalized() * -1.0, fwd)
				basis = Basis(ax, ax.cross(fwd).normalized() * -1.0, fwd)
				var up := fwd.cross(ax).normalized()
				if up.y < 0.0:
					up = -up
				basis = Basis(up.cross(fwd).normalized(), up, fwd)
				_mm_add("vines", Transform3D(basis, (p0 + p1) * 0.5 - Vector3.UP * 0.05))
		no_trees.append([c, maxf(w, d) * 0.55])
		made += 1
	stats.vineyards = made


## Lines of tall Lombardy poplars along the straights and field edges.
func _poplar_rows() -> void:
	var meshes: Array[String] = []
	for v in 2:
		var nm := "poplar%d" % v
		_tree_set(nm, "poplar_%d" % v, false, 1100.0, _tree_mesh(1.7, 17.0 + v * 3.0, 1.8, [Color(0.06, 0.11, 0.04), Color(0.2, 0.28, 0.1)], 0.32, 0.62, 9))
		meshes.append(nm)
	# Along the long straights, well back from the rail.
	for r in _straights(0.08, 60):
		var first: int = r[0]
		var length: int = r[1]
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.3:
				continue
			var back := rng.randf_range(42.0, 70.0)
			for k in range(0, length, 4):
				var i := _i(first + k)
				var p := centers[i] + rights[i] * side * back + tangents[i] * rng.randf_range(-1.0, 1.0)
				if _tdist(p, 38.0) < 38.0 or _occ.has(_okey(p)) or not _foreign_clear(p, 2.0):
					continue
				var blocked := false
				for z in no_trees:
					if (z[0] as Vector3).distance_to(p) < (z[1] as float):
						blocked = true
						break
				if blocked:
					continue
				p.y = _ground(p) - 0.3
				var s := rng.randf_range(0.85, 1.2)
				_mm_add(meshes[rng.randi() % 2], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), p))
	# Field boundaries further out.
	for line in 14:
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var start := centers[i] + rights[i] * side * rng.randf_range(100.0, 320.0)
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0, sin(ang))
		for k in rng.randi_range(12, 30):
			var p := start + dir * k * 7.5
			if _tdist(p, 45.0) < 45.0 or _occ.has(_okey(p)):
				break
			var blocked := false
			for z in no_trees:
				if (z[0] as Vector3).distance_to(p) < (z[1] as float):
					blocked = true
					break
			if blocked:
				continue
			p.y = _ground(p) - 0.3
			var s := rng.randf_range(0.85, 1.2)
			_mm_add(meshes[rng.randi() % 2], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.2), s)), p))
