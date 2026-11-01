class_name SetDressing
extends RefCounted
## Set dressing around a circuit, in the spirit of a 70s/80s European race
## and rally weekend:
##  - a busy paddock behind the pit building: team transporters with awnings,
##    tool chests, tyre stacks, fuel drums, caravans, mechanics, a helicopter
##    on its pad, floodlight masts and a perimeter fence;
##  - pit-lane life: tarmac, signal boards on the pit wall, crews, tyres,
##    trolley jacks and fuel rigs;
##  - two or three landmarks on the skyline per track: hillside sponsor
##    letters, a guyed radio mast with beacons, a castle ruin, a stone
##    viaduct or a quarry;
##  - flag marshals waving yellow and blue flags;
##  - rally-style clutter along the verges: cones, marker posts, spare tyres,
##    sheds, service vans, a burnt-out wreck, bales, benches, road signs,
##    portable toilets, drums, and billboards on the hillsides.
##
## Static geometry is merged into vertex-coloured meshes per 100 m cell that
## all share one material (printed faces sample a small text atlas; rain and
## snow are handled in the shader), so each visible cell costs one draw call.
## People are two MultiMeshes. Nothing here has collision: everything stands
## behind the guardrails or in the verge.

const STEP := 2.0
const CELL := 100.0
const ATLAS_SIZE := Vector2i(2048, 1024)
const VERGE := TrackBuilder.CURB_WIDTH + 2.0 ## verge clutter starts this far past the road edge

## Draw settings per category: [cast shadows, visibility range end (0 = always)].
const CATS := {
	big = [true, 900.0], # paddock buildings and vehicles
	mid = [true, 420.0], # trackside sheds, vans, billboards
	small = [false, 230.0], # little clutter
	flat = [false, 650.0], # tarmac aprons laid on the ground
	far = [false, 0.0], # skyline landmarks
	lamp = [false, 0.0], # emissive beacons and floodlights
}

## Invented teams: name, body colour, ink, cab / accent colour.
const TEAMS := [
	["SCUDERIA VALTER", Color(0.44, 0.1, 0.08), Color(0.9, 0.86, 0.76), Color(0.84, 0.82, 0.76)],
	["NORDLICHT RACING", Color(0.1, 0.21, 0.15), Color(0.9, 0.9, 0.86), Color(0.72, 0.6, 0.26)],
	["BERGMANN MOTORSPORT", Color(0.8, 0.78, 0.72), Color(0.1, 0.13, 0.22), Color(0.12, 0.16, 0.3)],
	["HALDEN RALLYE TEAM", Color(0.08, 0.08, 0.085), Color(0.88, 0.68, 0.24), Color(0.84, 0.64, 0.22)],
	["MARZELLI CORSE", Color(0.15, 0.22, 0.38), Color(0.9, 0.88, 0.8), Color(0.82, 0.8, 0.74)],
	["OSTRA WERKSTEAM", Color(0.55, 0.5, 0.4), Color(0.08, 0.08, 0.08), Color(0.35, 0.12, 0.08)],
	["AUREL AUTOSPORT", Color(0.3, 0.32, 0.34), Color(0.86, 0.72, 0.4), Color(0.85, 0.84, 0.8)],
	["HELIOS RACING", Color(0.82, 0.78, 0.66), Color(0.1, 0.08, 0.06), Color(0.72, 0.32, 0.08)],
]

## Hillside billboards: text, background, ink.
const BILLBOARDS := [
	["HELIOS BENZIN", Color(0.86, 0.82, 0.7), Color(0.07, 0.06, 0.05)],
	["VALTER OIL", Color(0.1, 0.13, 0.26), Color(0.9, 0.86, 0.76)],
	["NORDLICHT BIER", Color(0.09, 0.22, 0.14), Color(0.92, 0.9, 0.84)],
	["AUREL UHREN", Color(0.05, 0.05, 0.05), Color(0.8, 0.66, 0.36)],
]

## Block letters for the hillside sign on a 5 x 7 grid: [x, y, w, h] strokes.
const LETTERS := {
	"H": [[0, 0, 1, 7], [4, 0, 1, 7], [1, 3, 3, 1]],
	"E": [[0, 0, 1, 7], [1, 6, 4, 1], [1, 3, 3, 1], [1, 0, 4, 1]],
	"L": [[0, 0, 1, 7], [1, 0, 4, 1]],
	"I": [[1, 0, 3, 1], [1, 6, 3, 1], [2, 1, 1, 5]],
	"O": [[0, 0, 1, 7], [4, 0, 1, 7], [1, 0, 3, 1], [1, 6, 3, 1]],
	"S": [[0, 6, 5, 1], [0, 4, 1, 2], [0, 3, 5, 1], [4, 1, 1, 2], [0, 0, 5, 1]],
}

## Landmarks per track (unknown tracks get the first set).
const LANDMARKS := {
	kiefernring = ["sign", "mast", "castle"],
	hochwald = ["viaduct", "sign", "mast"],
	valle_club = ["castle", "quarry", "sign"],
	brackenmoor = ["mast", "castle", "quarry"],
	schneekopf = ["mast", "viaduct", "sign"],
}

const GLASS := Color(0.05, 0.06, 0.07)
const TYRE := Color(0.035, 0.035, 0.035)
const DARK := Color(0.09, 0.09, 0.095)
const STEEL := Color(0.5, 0.51, 0.52)
const WOOD := Color(0.36, 0.27, 0.19)
const STRAW := Color(0.66, 0.56, 0.34)
const CONCRETE := Color(0.56, 0.55, 0.52)
const YELLOW_FLAG := Color(0.9, 0.72, 0.08)
const BLUE_FLAG := Color(0.1, 0.24, 0.62)

var parent: Node3D
var terrain: Terrain
var preset: Dictionary
var half := 6.0
var rng := RandomNumberGenerator.new()
var track_id := ""
var debug := false
var lit := false ## floodlights on (overcast weather, night)
var def: Dictionary = {}
var has_sea := false ## coast theme: keep landmarks off the seaward side
var sea_dir := Vector2(-1, 0)
var sea_limit := INF ## dot(p.xz, sea_dir) beyond this is sea

var centers: Array[Vector3] = []
var rights: Array[Vector3] = []
var tangents: Array[Vector3] = []
var corner: Array[float] = []
var n := 0
var no_trees: Array = []
var uv := {}
var pits := {} ## i0 / i1 sample range of the pit straight, when there is one

var _batches := {}
var _protos := {}
var _grid := {}
var _wrecks := 0
var crew_xf: Array[Transform3D] = []
var crew_col: Array[Color] = []
var crew_custom: Array[Color] = []
var marshal_xf: Array[Transform3D] = []
var marshal_col: Array[Color] = []
var marshal_custom: Array[Color] = []
var _log: Array[String] = []


static func build(p_parent: Node3D, curve: Curve3D, road_width: float, p_preset: Dictionary) -> void:
	var s := SetDressing.new()
	s.parent = p_parent
	s.terrain = p_parent.get_meta("terrain", null)
	s.preset = p_preset
	s.half = road_width * 0.5
	s.no_trees = p_parent.get_meta("no_trees", [])
	var d: Variant = p_parent.get("def")
	s.track_id = str(d.get("id", "")) if d is Dictionary else ""
	if d is Dictionary:
		s.def = d
	s.rng.seed = hash(s.track_id) ^ 0x5e7d
	s.lit = float(p_preset.get("wet", 0.0)) > 0.5 or float(p_preset.get("snow", 0.0)) > 0.0 \
		or float(p_preset.get("night", 0.0)) > 0.0
	s.debug = OS.get_cmdline_user_args().has("--debug-dressing")
	s._run(curve)


func _run(curve: Curve3D) -> void:
	var t0 := Time.get_ticks_msec()
	_sample(curve)
	if str(def.get("theme", "")) == "coast":
		has_sea = true
		sea_dir = (def.get("sea", Vector2(-1, 0)) as Vector2).normalized()
		sea_limit = -INF
		for c in centers:
			sea_limit = maxf(sea_limit, Vector2(c.x, c.z).dot(sea_dir))
		sea_limit += 25.0
	var atlas := _build_atlas()
	_paddock_and_pitlane()
	_marshals()
	_clutter()
	_billboards()
	_landmarks()
	var stats := _commit(atlas)
	parent.set_meta("no_trees", no_trees)
	if debug:
		for line in _log:
			print("set dressing: ", line)
		print("set dressing: %d meshes, %d triangles, %d crew, %d marshals in %d ms" % [stats.x, stats.y,
			crew_xf.size(), marshal_xf.size(), Time.get_ticks_msec() - t0])


# ---------------------------------------------------------------- sampling & placement

func _sample(curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var t := (curve.sample_baked(fmod(off + 1.0, length)) - curve.sample_baked(fmod(off - 1.0 + length, length))).normalized()
		centers.append(p)
		tangents.append(t)
		rights.append(t.cross(Vector3.UP).normalized())
		var key := Vector2i(floori(p.x / 30.0), floori(p.z / 30.0))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)
	corner = TrackBuilder._corner_factors(centers)


func _i(k: int) -> int:
	return posmod(k, n)


## Distance from the centreline to the guardrail (same formula as TrackBuilder).
func rail_dist(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	var depth := TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0
	return half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)


func _gy(p: Vector3) -> float:
	return terrain.surface_at(p.x, p.z) if terrain else p.y


## Point `lateral` metres off the centreline at sample `i`, on the ground.
func at(i: int, lateral: float) -> Vector3:
	var k := _i(i)
	var p := centers[k] + rights[k] * lateral
	p.y = _gy(p)
	return p


func straight_extent(i: int, dir: int, max_samples: int) -> int:
	var k := 0
	while k < max_samples and absf(corner[_i(i + k * dir)]) < 0.1:
		k += 1
	return k


func _nearby(p: Vector3) -> Array:
	var out := []
	var cx := floori(p.x / 30.0)
	var cz := floori(p.z / 30.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			out.append_array(_grid.get(Vector2i(cx + dx, cz + dz), []))
	return out


## True if `p` is at least `margin` metres behind the guardrail of every
## nearby stretch of track, so nothing lands on a road, kerb or gravel trap.
func _road_clear(p: Vector3, margin: float) -> bool:
	for k: int in _nearby(p):
		var d := Vector3(p.x - centers[k].x, 0.0, p.z - centers[k].z)
		if d.length() < rail_dist(k, signf(d.dot(rights[k]))) + margin:
			return false
	return true


## Verge spot next to sample `own`: clear of the road edge and any gravel
## trap along this stretch, and behind the rails of other stretches.
func _verge_clear(p: Vector3, own: int) -> bool:
	for k: int in _nearby(p):
		var d := Vector3(p.x - centers[k].x, 0.0, p.z - centers[k].z)
		var side := signf(d.dot(rights[k]))
		var ring := absi(posmod(k - own + n / 2, n) - n / 2)
		var need: float
		if ring <= 20:
			var c: float = corner[k]
			var trap := TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0
			need = maxf(half + VERGE, half + TrackBuilder.CURB_WIDTH + trap + 1.5)
		else:
			need = rail_dist(k, side) + 1.5
		if d.length() < need:
			return false
	return true


## Clear of everything already registered in the "no_trees" list.
func _clear(p: Vector3, r: float) -> bool:
	for z in no_trees:
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(z[1]) + r:
			return false
	return true


func _track_dist(p: Vector3) -> float:
	var best := INF
	for k in range(0, n, 3):
		best = minf(best, Vector2(centers[k].x - p.x, centers[k].z - p.z).length())
	return best


## Horizontal unit vector from `p` towards the nearest bit of track.
func _to_track(p: Vector3) -> Vector3:
	var best := INF
	var dir := Vector3.FORWARD
	for k in range(0, n, 3):
		var d := Vector3(centers[k].x - p.x, 0.0, centers[k].z - p.z)
		if d.length() < best:
			best = d.length()
			dir = d.normalized()
	return dir


func _in_terrain(p: Vector3, margin: float) -> bool:
	if terrain == null:
		return true
	var size := terrain.cell * (Terrain.N - 1)
	return p.x > terrain.origin.x + margin and p.z > terrain.origin.y + margin \
		and p.x < terrain.origin.x + size - margin and p.z < terrain.origin.y + size - margin


## Is sample `i` on the pit straight (with some slack either side)?
func _in_pits(i: int, slack: int) -> bool:
	if pits.is_empty():
		return false
	var rel := _i(i)
	if rel > n / 2:
		rel -= n
	return rel >= int(pits.i0) - slack and rel <= int(pits.i1) + slack


# ---------------------------------------------------------------- geometry batching

## One merged mesh: vertex colour, atlas UV, UV2 = (printed, gloss).
class Batch:
	extends RefCounted
	var origin := Vector3.ZERO
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()


func _batch(cat: String, pos: Vector3) -> Batch:
	var key := cat
	var origin := Vector3.ZERO
	if cat != "lamp":
		var cx := floori(pos.x / CELL)
		var cz := floori(pos.z / CELL)
		key = "%s_%d_%d" % [cat, cx, cz]
		origin = Vector3((cx + 0.5) * CELL, pos.y, (cz + 0.5) * CELL)
	var b: Batch = _batches.get(key)
	if b == null:
		b = Batch.new()
		b.origin = origin
		_batches[key] = b
	return b


## Unit-sized primitive (1 m box / 1 m diameter), de-indexed: [verts, normals].
func _proto(kind: String, segs := 0) -> Array:
	var key := kind + str(segs)
	if _protos.has(key):
		return _protos[key]
	var mesh: PrimitiveMesh
	match kind:
		"box":
			mesh = BoxMesh.new()
		"prism":
			mesh = PrismMesh.new()
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = segs
			s.rings = maxi(segs / 2, 3)
			mesh = s
		_: # cyl / cone
			var c := CylinderMesh.new()
			c.top_radius = 0.5 if kind == "cyl" else 0.0
			c.bottom_radius = 0.5
			c.height = 1.0
			c.radial_segments = segs
			c.rings = 0
			c.cap_top = kind == "cyl"
			mesh = c
	var arr := mesh.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	ov.resize(idx.size())
	on.resize(idx.size())
	for j in idx.size():
		ov[j] = v[idx[j]]
		on[j] = nr[idx[j]]
	_protos[key] = [ov, on]
	return _protos[key]


func _emit(cat: String, proto: Array, xf: Transform3D, col: Color, gloss: float, uvv := Vector2.ZERO) -> void:
	var b := _batch(cat, xf.origin)
	var src: PackedVector3Array = proto[0]
	var m := src.size()
	b.verts.append_array(Transform3D(xf.basis, xf.origin - b.origin) * src)
	b.norms.append_array(Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO) * (proto[1] as PackedVector3Array))
	var c := PackedColorArray()
	c.resize(m)
	c.fill(col)
	b.cols.append_array(c)
	var u := PackedVector2Array()
	u.resize(m)
	u.fill(uvv)
	b.uvs.append_array(u)
	u.fill(Vector2(0.0, gloss))
	b.uv2s.append_array(u)


## Box of `size` centred at `c`, both in the model space of `m`.
func _box(cat: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, gloss := 0.0, rot := Basis()) -> void:
	_emit(cat, _proto("box"), Transform3D(m.basis * rot * Basis.from_scale(size), m * c), col, gloss)


func _cyl(cat: String, m: Transform3D, c: Vector3, radius: float, height: float, col: Color, segs := 10, rot := Basis(), gloss := 0.0) -> void:
	_emit(cat, _proto("cyl", segs), Transform3D(m.basis * rot * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), m * c), col, gloss)


func _cone(cat: String, m: Transform3D, c: Vector3, radius: float, height: float, col: Color, segs := 8, rot := Basis()) -> void:
	_emit(cat, _proto("cone", segs), Transform3D(m.basis * rot * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), m * c), col, 0.0)


func _ball(cat: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, gloss := 0.0, segs := 10) -> void:
	_emit(cat, _proto("sphere", segs), Transform3D(m.basis * Basis.from_scale(size), m * c), col, gloss)


func _prism(cat: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, rot := Basis()) -> void:
	_emit(cat, _proto("prism"), Transform3D(m.basis * rot * Basis.from_scale(size), m * c), col, 0.0)


## Beam of square section `thick` from `a` to `b` (world space).
func _strut(cat: String, a: Vector3, b: Vector3, thick: float, col: Color, gloss := 0.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var up := Vector3.UP if absf(d.y / len) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(d / len, up) * Basis.from_scale(Vector3(thick, thick, len))
	_emit(cat, _proto("box"), Transform3D(basis, (a + b) * 0.5), col, gloss)


## Printed quad from the atlas, facing `normal` (model space of `m`).
func _print(cat: String, m: Transform3D, c: Vector3, normal: Vector3, w: float, h: float, region: Rect2, up := Vector3.UP) -> void:
	var nw := (m.basis * normal).normalized()
	var uw := (m.basis * up).normalized()
	var rw := uw.cross(nw).normalized() # viewer's right
	var cw := m * c
	var b := _batch(cat, cw)
	cw -= b.origin
	var r := rw * w * 0.5
	var u := uw * h * 0.5
	var pts := [cw - r + u, cw + r + u, cw + r - u, cw - r - u]
	var uvp := [region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		b.verts.append(pts[k])
		b.norms.append(nw)
		b.cols.append(Color.WHITE)
		b.uvs.append(uvp[k])
		b.uv2s.append(Vector2(1.0, 0.0))


## Ground-hugging apron in the frame (o, t along, r across), draped on the terrain.
func _apron(o: Vector3, t: Vector3, r: Vector3, a0: float, a1: float, l0: float, l1: float, col: Color, lift: float, step := 4.0) -> void:
	var na := maxi(int(ceil((a1 - a0) / step)), 1)
	var nl := maxi(int(ceil((l1 - l0) / step)), 1)
	for ia in na:
		for il in nl:
			var p := [] # back-left, back-right, front-right, front-left
			for q: Vector2 in [Vector2(ia, il), Vector2(ia, il + 1), Vector2(ia + 1, il + 1), Vector2(ia + 1, il)]:
				var v := o + t * lerpf(a0, a1, q.x / na) + r * lerpf(l0, l1, q.y / nl)
				v.y = _gy(v) + lift
				p.append(v)
			var b := _batch("flat", p[0])
			var nrm: Vector3 = ((p[1] - p[0]) as Vector3).cross(p[3] - p[0]).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			for k: int in [0, 2, 1, 0, 3, 2]:
				b.verts.append((p[k] as Vector3) - b.origin)
				b.norms.append(nrm)
				b.cols.append(col)
				b.uvs.append(Vector2.ZERO)
				b.uv2s.append(Vector2.ZERO)


func _commit(atlas: Texture2D) -> Vector2i:
	# Photographic PBR version of set_props.gdshader (same mesh interface).
	var mat := Mats.props(atlas, _grime_texture(), preset)
	var lamp := ShaderMaterial.new()
	lamp.shader = load("res://shaders/set_lamp.gdshader")
	var root := Node3D.new()
	root.name = "SetDressing"
	parent.add_child(root)
	var tris := 0
	var meshes := 0
	for key: String in _batches:
		var b: Batch = _batches[key]
		if b.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = b.verts
		arrays[Mesh.ARRAY_NORMAL] = b.norms
		arrays[Mesh.ARRAY_COLOR] = b.cols
		arrays[Mesh.ARRAY_TEX_UV] = b.uvs
		arrays[Mesh.ARRAY_TEX_UV2] = b.uv2s
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = mesh
		mi.position = b.origin
		var cat := key.get_slice("_", 0)
		var cfg: Array = CATS[cat]
		mi.material_override = lamp if cat == "lamp" else mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg[0] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if float(cfg[1]) > 0.0:
			# The range is measured to the cell's AABB centre: add its
			# half-diagonal, and a little hysteresis so a still camera never
			# flickers it at the boundary.
			var box := mesh.get_aabb()
			mi.visibility_range_end = float(cfg[1]) + Vector2(box.size.x, box.size.z).length() * 0.5
			# Dissolve over +-25 m (the node sits at its cell centre, where the fade is measured from).
			mi.visibility_range_end_margin = 25.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
		tris += b.verts.size() / 3
		meshes += 1
	tris += _figures(root)
	return Vector2i(meshes, tris)


func _grime_texture() -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.03
	nz.fractal_octaves = 4
	nz.seed = 77
	var t := NoiseTexture2D.new()
	t.noise = nz
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	return t


# ---------------------------------------------------------------- people

func _person(p: Vector3, facing: Vector3, col: Color, fidget := 0.0) -> void:
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3.FORWARD
	var s := rng.randf_range(0.94, 1.06)
	crew_xf.append(Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP).scaled(Vector3(s, s, s)), p))
	crew_col.append(col)
	crew_custom.append(Color(rng.randf(), fidget, 0, 0))


func _marshal(p: Vector3, facing: Vector3, flag: Color, wave: float) -> void:
	facing.y = 0.0
	if debug and marshal_xf.size() < 3:
		_log.append("marshal at %s" % p)
	marshal_xf.append(Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP), p))
	marshal_col.append(flag)
	marshal_custom.append(Color(rng.randf(), wave, 1.0 if rng.randf() < 0.5 else 0.0, 0))


## Crew, bystanders and marshals as realistic baked figures (PeopleKit). Crew
## (fidget < 0.25) wear overalls in their colour; the rest are bystanders in
## everyday clothes. Returns an estimate of the triangles drawn.
func _figures(root: Node3D) -> int:
	var tris := 0
	var crew: Array[Transform3D] = []
	var crew_c: Array[Color] = []
	var crew_u: Array[Color] = []
	var civ: Array[Transform3D] = []
	var civ_c: Array[Color] = []
	var civ_u: Array[Color] = []
	for k in crew_xf.size():
		if crew_custom[k].g < 0.25:
			crew.append(crew_xf[k])
			crew_c.append(crew_col[k])
			crew_u.append(crew_custom[k])
		else:
			civ.append(crew_xf[k])
			civ_c.append(crew_col[k])
			civ_u.append(Color(crew_custom[k].r, 0.0, 0.0, 0.0))
	if not crew.is_empty():
		root.add_child(PeopleKit.crowd("Crew", PeopleKit.Role.CREW, crew, crew_c, crew_u, false))
	if not civ.is_empty():
		root.add_child(PeopleKit.crowd("Bystanders", PeopleKit.Role.SPECTATOR, civ, civ_c, civ_u, false))
	if not marshal_xf.is_empty():
		root.add_child(PeopleKit.crowd("Marshals", PeopleKit.Role.MARSHAL, marshal_xf, marshal_col, marshal_custom, false))
	tris += (crew_xf.size() + marshal_xf.size()) * PeopleKit.tris("man_overalls", PeopleKit.Pose.STAND, "lo")
	return tris


# ---------------------------------------------------------------- atlas

func _build_atlas() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = ATLAS_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var root := Control.new()
	root.size = Vector2(ATLAS_SIZE)
	vp.add_child(root)
	var bold: Font = load(UiTheme.FONT_BOLD)
	# Transporter liveries.
	for k in TEAMS.size():
		var tm: Array = TEAMS[k]
		var r := Rect2(Vector2((k % 4) * 512, (k / 4) * 160), Vector2(512, 160))
		_rect(root, r, tm[1])
		_rect(root, Rect2(r.position + Vector2(0, 108), Vector2(512, 16)), tm[3])
		_rect(root, Rect2(r.position + Vector2(0, 130), Vector2(512, 6)), tm[2])
		_label(root, Rect2(r.position + Vector2(8, 6), Vector2(496, 100)), tm[0], tm[2], bold, 54)
		uv["team%d" % k] = r
	# Pit signal boards.
	var boards := ["P2\n+1.4", "P5\nL 9", "IN", "+0.8\nL 12"]
	for k in boards.size():
		var r := Rect2(k * 256, 320, 256, 192)
		_rect(root, r, Color(0.03, 0.03, 0.035))
		_label(root, r, boards[k], Color(0.93, 0.84, 0.3) if k % 2 == 0 else Color(0.92, 0.92, 0.9), bold, 66 if "\n" in boards[k] else 120)
		uv["sig%d" % k] = r
	# Fictional road signs.
	var signs := [
		["BRACKENDORF\n4 km", Color(0.86, 0.7, 0.14), Color(0.05, 0.05, 0.05)],
		["P  FAHRERLAGER\nPADDOCK", Color(0.1, 0.24, 0.5), Color(0.92, 0.92, 0.9)],
		["ACHTUNG\nRENNSTRECKE", Color(0.9, 0.9, 0.87), Color(0.6, 0.08, 0.06)],
		["WERTUNGSPRÜFUNG\nSS 4", Color(0.1, 0.34, 0.2), Color(0.92, 0.92, 0.9)],
	]
	for k in signs.size():
		var r := Rect2(1024 + k * 256, 320, 256, 192)
		_rect(root, r, signs[k][2])
		_rect(root, r.grow(-10), signs[k][1])
		_label(root, r, signs[k][0], signs[k][2], bold, 32)
		uv["sign%d" % k] = r
	# Hillside billboards.
	for k in BILLBOARDS.size():
		var b: Array = BILLBOARDS[k]
		var r := Rect2(k * 512, 512, 512, 160)
		_rect(root, r, b[1])
		_rect(root, Rect2(r.position + Vector2(0, 140), Vector2(512, 10)), b[2])
		_label(root, Rect2(r.position, Vector2(512, 136)), b[0], b[2], bold, 76)
		uv["bb%d" % k] = r
	# Helipad marking.
	var pad := Rect2(0, 672, 256, 256)
	_rect(root, pad, Color(0.85, 0.84, 0.8))
	_rect(root, pad.grow(-14), Color(0.3, 0.3, 0.29))
	_label(root, pad, "H", Color(0.88, 0.87, 0.83), bold, 230)
	uv.pad = pad
	for key in uv:
		var r: Rect2 = uv[key]
		uv[key] = Rect2(r.position / Vector2(ATLAS_SIZE), r.size / Vector2(ATLAS_SIZE))
	parent.add_child(vp)
	var baker := Baker.new()
	baker.viewport = vp
	parent.add_child(baker)
	return baker.texture


func _rect(root: Control, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.position = r.position
	cr.size = r.size
	cr.color = c
	root.add_child(cr)


func _label(root: Control, r: Rect2, text: String, ink: Color, font: Font, size: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	l.add_theme_constant_override("line_spacing", -6)
	root.add_child(l)


## Copies the atlas SubViewport into a mipmapped ImageTexture once it rendered.
class Baker:
	extends Node
	var viewport: SubViewport
	var texture := ImageTexture.new()

	func _init() -> void:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.5, 0.5))
		texture.set_image(img)

	func _ready() -> void:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		if img and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			texture.set_image(img)
		viewport.queue_free()
		queue_free()


# ---------------------------------------------------------------- paddock & pit lane

func _paddock_and_pitlane() -> void:
	var back := straight_extent(0, -1, 75)
	var fwd := straight_extent(0, 1, 40)
	if back + fwd < 20:
		return
	# Same frame as TrackProps' pit building: straight along the middle sample.
	var i0 := -back + 2
	var i1 := fwd - 2
	var mid := (i0 + i1) / 2
	var length := (i1 - i0) * STEP
	pits = {i0 = i0, i1 = i1}
	var o := centers[_i(mid)]
	var t := tangents[_i(mid)]
	var r := rights[_i(mid)]
	var rail := rail_dist(mid, 1.0)
	_pitlane(o, t, r, rail, length)
	_paddock(o, t, r, rail + 20.0, length)


## Frame point: `along` metres down the straight, `lat` to the right, on the ground.
func _fp(o: Vector3, t: Vector3, r: Vector3, along: float, lat: float) -> Vector3:
	var p := o + t * along + r * lat
	p.y = _gy(p)
	return p


func _pitlane(o: Vector3, t: Vector3, r: Vector3, rail: float, length: float) -> void:
	var lane0 := rail + 2.25 # just behind TrackProps' pit wall
	var lane1 := rail + 8.0 # garage fronts
	_apron(o, t, r, -length * 0.5, length * 0.5, lane0, lane1, Color(0.2, 0.2, 0.21), 0.05)
	_apron(o, t, r, -length * 0.5, length * 0.5, lane0 + 0.5, lane0 + 0.65, Color(0.8, 0.8, 0.76), 0.07, 8.0)
	var doors := int(length / 7.0)
	var face_track := Basis.looking_at(-r, Vector3.UP)
	for k in doors:
		var z := ((k + 0.5) / doors - 0.5) * length
		var team := k % TEAMS.size()
		var overalls: Color = TEAMS[team][1] if k % 3 else TEAMS[team][3]
		# Signal board hung over the pit wall, towards the oncoming cars.
		if k % 2 == 0:
			var wall := _fp(o, t, r, z + 1.5, rail + 2.0) + Vector3.UP * 1.1
			var facing := (-r * 0.45 - t).normalized()
			var bm := Transform3D(Basis.looking_at(-facing, Vector3.UP), wall)
			_print("small", bm, Vector3(0, 0.55, 0.03), Vector3.BACK, 1.0, 0.75, uv["sig%d" % (k / 2 % 4)])
			_box("small", bm, Vector3(0, 0.55, 0.0), Vector3(1.04, 0.79, 0.04), DARK)
			_strut("small", wall + Vector3.UP * 0.2, wall + r * 0.7 + Vector3.UP * 0.6, 0.04, STEEL)
			_person(_fp(o, t, r, z + 1.5, rail + 2.7), -r, overalls, 0.05)
		# Crew waiting in front of the garage.
		for c in rng.randi_range(1, 3):
			_person(_fp(o, t, r, z + rng.randf_range(-2.0, 2.0), rail + rng.randf_range(5.0, 7.2)),
				-r + t * rng.randf_range(-0.8, 0.8), overalls, rng.randf_range(0.0, 0.12))
		# Tyres, a trolley jack and (every other garage) a fuel rig.
		var m := Transform3D(face_track, _fp(o, t, r, z + 2.2, rail + 7.4))
		_tyre_stack("small", m, Vector3(0, 0, 0), rng.randi_range(3, 5))
		_tyre_stack("small", m, Vector3(-0.7, 0, 0.1), rng.randi_range(2, 4))
		_jack(Transform3D(face_track.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6)), _fp(o, t, r, z - 1.2, rail + 6.4)))
		if k % 2 == 1:
			_fuel_rig(Transform3D(face_track, _fp(o, t, r, z - 2.6, rail + 7.3)))


func _paddock(o: Vector3, t: Vector3, r: Vector3, pb: float, length: float) -> void:
	var a0 := -length * 0.5 - 8.0
	var a1 := length * 0.5 + 8.0
	var depth := 38.0
	# Only as deep as the land allows before another stretch of track.
	while depth > 20.0 and not (_road_clear(_fp(o, t, r, a0, pb + depth), 4.0) and _road_clear(_fp(o, t, r, 0.0, pb + depth), 4.0)
			and _road_clear(_fp(o, t, r, a1, pb + depth), 4.0)):
		depth -= 4.0
	_apron(o, t, r, a0, a1, pb + 0.5, pb + depth, Color(0.33, 0.33, 0.32), 0.12)
	for a in range(int(a0), int(a1), 25):
		no_trees.append([_fp(o, t, r, a + 12.0, pb + depth * 0.5), depth * 0.5 + 12.0])
	_log.append("paddock at %s, %.0f m x %.0f m" % [_fp(o, t, r, 0.0, pb + depth * 0.5), a1 - a0, depth])

	# Transporters parked nose-first down the straight, awnings towards the pits.
	var count := clampi(int(length / 20.0), 2, 8)
	var spacing := length / count
	var fwd := Basis.looking_at(t, Vector3.UP) # local -X faces the pit building
	for k in count:
		var along := -length * 0.5 + (k + 0.5) * spacing
		var team := (k + rng.randi_range(0, 1)) % TEAMS.size()
		var m := Transform3D(fwd, _fp(o, t, r, along - 1.35, pb + 12.0) + Vector3.DOWN * 0.1)
		_truck(m, team)
		_awning_area(m, team)
		if depth >= 30.0:
			var back := Transform3D(fwd, _fp(o, t, r, along + rng.randf_range(-3.0, 3.0), pb + 22.5))
			match k % 3:
				0: _caravan(back, TEAMS[team][1])
				1: _portakabin(back)
				_: _drums("small", back, rng.randi_range(4, 7))
	# Back row: hospitality marquees, parked team cars, tyre mountains.
	if depth >= 34.0:
		var a := -length * 0.5 + 6.0
		var slot := 0
		while a < length * 0.5 - 6.0:
			var bm := Transform3D(fwd, _fp(o, t, r, a, pb + 31.0))
			match slot % 4:
				0:
					_marquee(bm, TEAMS[(slot / 4) % TEAMS.size()][1])
					for c in rng.randi_range(2, 4):
						_person(bm * Vector3(rng.randf_range(-4.5, -3.2), 0, rng.randf_range(-4.0, 4.0)), -r + t * rng.randf_range(-1, 1),
							[Color(0.55, 0.52, 0.46), Color(0.2, 0.25, 0.35), Color(0.45, 0.3, 0.16)][c % 3], 0.2)
					a += 13.0
				1, 3:
					for c in 3:
						_saloon(Transform3D(fwd.rotated(Vector3.UP, PI * 0.5), _fp(o, t, r, a + c * 2.9, pb + 31.0)),
							[Color(0.55, 0.52, 0.45), Color(0.2, 0.24, 0.3), Color(0.45, 0.12, 0.08), Color(0.3, 0.33, 0.25), Color(0.7, 0.66, 0.5)][rng.randi() % 5])
					a += 10.0
				_:
					for c in rng.randi_range(4, 7):
						_tyre_stack("small", bm, Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5)), rng.randi_range(3, 7))
					a += 6.0
			slot += 1
	# Race control cabins and parked cars at the near end.
	if depth >= 36.0:
		_portakabin(Transform3D(fwd.rotated(Vector3.UP, PI * 0.5), _fp(o, t, r, -length * 0.5 - 2.0, pb + 32.0)))
		for c in 4:
			var cm := Transform3D(fwd.rotated(Vector3.UP, PI * 0.5), _fp(o, t, r, -length * 0.5 + 6.0 + c * 3.0, pb + 34.0))
			_saloon(cm, [Color(0.55, 0.52, 0.45), Color(0.2, 0.24, 0.3), Color(0.45, 0.12, 0.08), Color(0.3, 0.33, 0.25)][c])
	# Helicopter pad at whichever end has room.
	for end: float in [-1.0, 1.0]:
		var along := end * (length * 0.5 + 16.0)
		var p := _fp(o, t, r, along, pb + minf(depth * 0.5, 18.0))
		if _road_clear(p, 10.0):
			_helipad(p, fwd)
			_log.append("helipad at %s" % p)
			no_trees.append([p, 18.0])
			break
	# Floodlights along both long sides of the paddock.
	for a: float in [-length * 0.5, 0.0, length * 0.5]:
		_floodlight(_fp(o, t, r, a, pb + 1.5), r)
		_floodlight(_fp(o, t, r, a, pb + depth - 1.0), -r)
	# Perimeter fence: back and both ends.
	_fence(o, t, r, Vector2(a0, pb + depth), Vector2(a1, pb + depth))
	_fence(o, t, r, Vector2(a0, pb + 1.0), Vector2(a0, pb + depth))
	_fence(o, t, r, Vector2(a1, pb + 1.0), Vector2(a1, pb + depth))


## Cab-over team transporter, livery down both sides. Model space: -Z forward.
func _truck(m: Transform3D, team: int) -> void:
	var tm: Array = TEAMS[team]
	var body: Color = tm[1]
	var cab: Color = tm[3]
	var c := "big"
	_box(c, m, Vector3(0, 0.78, 0.2), Vector3(1.8, 0.32, 10.8), DARK) # chassis
	_box(c, m, Vector3(0, 2.62, 1.35), Vector3(2.5, 3.0, 8.3), body, 0.5) # box body
	_box(c, m, Vector3(0, 1.08, 1.35), Vector3(2.54, 0.16, 8.34), DARK) # rubbing strip
	_box(c, m, Vector3(0, 2.62, 5.51), Vector3(2.3, 2.8, 0.04), body.darkened(0.25), 0.4) # rear doors
	_box(c, m, Vector3(0, 2.62, 5.53), Vector3(0.03, 2.8, 0.03), DARK)
	# Cab.
	_box(c, m, Vector3(0, 2.1, -4.05), Vector3(2.45, 2.3, 2.1), cab, 0.6)
	_box(c, m, Vector3(0, 1.55, -4.05), Vector3(2.47, 0.2, 2.12), tm[2], 0.6) # cab stripe
	_box(c, m, Vector3(0, 2.72, -5.11), Vector3(2.25, 0.85, 0.04), GLASS, 1.0)
	for sx: float in [-1.0, 1.0]:
		_box(c, m, Vector3(sx * 1.235, 2.72, -4.55), Vector3(0.04, 0.8, 0.9), GLASS, 1.0)
		_box(c, m, Vector3(sx * 1.45, 2.65, -4.9), Vector3(0.06, 0.45, 0.22), DARK) # mirror
		_box(c, m, Vector3(sx * 0.85, 1.12, -5.12), Vector3(0.34, 0.22, 0.04), Color(0.82, 0.8, 0.7), 1.0) # lamps
		_box(c, m, Vector3(sx * 1.24, 0.95, -4.4), Vector3(0.05, 0.3, 0.5), DARK) # step
		for z: float in [-4.0, 3.0, 4.2]:
			_cyl(c, m, Vector3(sx * 1.02, 0.52, z), 0.52, 0.34, TYRE, 12, Basis(Vector3.BACK, PI * 0.5))
			_cyl(c, m, Vector3(sx * 1.2, 0.52, z), 0.24, 0.02, STEEL, 8, Basis(Vector3.BACK, PI * 0.5), 0.8)
		_print(c, m, Vector3(sx * 1.262, 2.72, 1.35), Vector3(sx, 0, 0), 7.8, 2.5, uv["team%d" % team])
	_box(c, m, Vector3(0, 1.45, -5.12), Vector3(1.5, 0.5, 0.04), DARK) # grille
	_box(c, m, Vector3(0, 0.82, -5.2), Vector3(2.44, 0.28, 0.18), Color(0.22, 0.22, 0.22), 0.5) # bumper
	_cyl(c, m, Vector3(1.0, 0.95, -2.2), 0.3, 1.3, STEEL, 10, Basis(Vector3.RIGHT, PI * 0.5), 0.8) # fuel tank


## Awning off the pit side of a transporter, with the kit and crew under it.
func _awning_area(m: Transform3D, team: int) -> void:
	var canvas: Color = (TEAMS[team][1] as Color).lerp(Color(0.84, 0.82, 0.76), 0.5)
	var x0 := -1.3
	var y0 := 3.7
	var x1 := -5.8
	var y1 := 2.6
	var slope := atan2(y0 - y1, x0 - x1)
	var w := Vector2(x0 - x1, y0 - y1).length()
	_box("big", m, Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, 1.35), Vector3(w, 0.05, 8.1), canvas, 0.0, Basis(Vector3.BACK, slope))
	_box("big", m, Vector3(x1, y1 - 0.18, 1.35), Vector3(0.04, 0.36, 8.1), TEAMS[team][1])
	for z: float in [-2.6, 5.3]:
		_box("big", m, Vector3(x1 + 0.05, y1 * 0.5, z), Vector3(0.07, y1, 0.07), STEEL, 0.6)
	# Tool chests against the truck, a bench, an engine on a stand, tyres.
	var chest: Color = [Color(0.5, 0.1, 0.08), Color(0.32, 0.34, 0.36), Color(0.14, 0.2, 0.34)][team % 3]
	for z: float in [-1.6, 3.8]:
		_box("small", m, Vector3(-1.65, 0.55, z), Vector3(0.6, 1.1, 1.2), chest, 0.6)
		for d in 4:
			_box("small", m, Vector3(-1.96, 0.2 + d * 0.24, z), Vector3(0.02, 0.03, 1.1), DARK)
	_box("small", m, Vector3(-1.75, 0.45, 1.1), Vector3(0.8, 0.9, 2.0), WOOD)
	_box("small", m, Vector3(-3.4, 0.35, 0.2), Vector3(0.5, 0.7, 0.5), STEEL, 0.4)
	_box("small", m, Vector3(-3.4, 0.9, 0.2), Vector3(0.6, 0.45, 0.75), DARK, 0.6)
	_tyre_stack("small", m, Vector3(-4.9, 0, 4.6), rng.randi_range(3, 5))
	_tyre_stack("small", m, Vector3(-4.9, 0, 3.9), rng.randi_range(2, 5))
	_tyre_stack("small", m, Vector3(-4.2, 0, 4.6), rng.randi_range(1, 4))
	if rng.randf() < 0.5:
		# The race car under a dust cover.
		_box("small", m, Vector3(-3.9, 0.45, -1.4), Vector3(1.75, 0.75, 4.1), Color(0.28, 0.3, 0.33))
		_box("small", m, Vector3(-3.9, 1.0, -1.2), Vector3(1.35, 0.4, 2.0), Color(0.28, 0.3, 0.33))
	var overalls: Color = TEAMS[team][1] if team % 2 else TEAMS[team][3]
	for p in rng.randi_range(1, 3):
		_person(m * Vector3(rng.randf_range(-2.6, -5.2), 0, rng.randf_range(-2.0, 5.0)),
			m.basis * Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), overalls, rng.randf_range(0.0, 0.15))


func _tyre_stack(cat: String, m: Transform3D, c: Vector3, count: int) -> void:
	for s in count:
		_cyl(cat, m, c + Vector3(rng.randf_range(-0.03, 0.03), 0.12 + s * 0.235, 0), 0.31, 0.23, TYRE, 10)


func _jack(m: Transform3D) -> void:
	var red := Color(0.5, 0.1, 0.07)
	_box("small", m, Vector3(0, 0.12, 0), Vector3(0.32, 0.14, 0.8), red, 0.6)
	_box("small", m, Vector3(0, 0.25, -0.35), Vector3(0.2, 0.12, 0.12), DARK)
	var a := m * Vector3(0, 0.15, 0.38)
	_strut("small", a, m * Vector3(0, 0.95, 1.15), 0.035, STEEL, 0.6)


func _fuel_rig(m: Transform3D) -> void:
	for sx: float in [-0.35, 0.35]:
		_box("small", m, Vector3(sx, 1.0, 0), Vector3(0.05, 2.0, 0.05), STEEL)
	_cyl("small", m, Vector3(0, 1.4, 0), 0.32, 1.1, Color(0.58, 0.56, 0.5), 10, Basis(), 0.6)
	_box("small", m, Vector3(0, 2.02, 0), Vector3(0.8, 0.05, 0.3), STEEL)
	_strut("small", m * Vector3(0, 0.85, 0), m * Vector3(0.1, 0.1, -0.9), 0.05, DARK)


func _drums(cat: String, m: Transform3D, count: int) -> void:
	var cols := [Color(0.38, 0.2, 0.1), Color(0.16, 0.25, 0.4), Color(0.48, 0.1, 0.08), Color(0.3, 0.33, 0.2), Color(0.52, 0.5, 0.45)]
	for k in count:
		var c := Vector3((k % 3) * 0.62 + rng.randf_range(-0.05, 0.05), 0.45, (k / 3) * 0.62)
		var col: Color = cols[rng.randi() % cols.size()]
		if rng.randf() < 0.15:
			_cyl(cat, m, Vector3(c.x, 0.3, c.z + 1.4), 0.29, 0.88, col, 10, Basis(Vector3.RIGHT, PI * 0.5), 0.3)
		else:
			_cyl(cat, m, c, 0.29, 0.88, col, 10, Basis(), 0.3)
			_cyl(cat, m, c + Vector3.UP * 0.2, 0.3, 0.03, col.darkened(0.2), 10)


func _caravan(m: Transform3D, stripe: Color) -> void:
	var cream := Color(0.82, 0.8, 0.72)
	_box("big", m, Vector3(0, 1.6, 0), Vector3(2.3, 2.3, 6.4), cream, 0.3)
	_box("big", m, Vector3(0, 1.3, 0), Vector3(2.32, 0.3, 6.42), stripe, 0.3)
	for sx: float in [-1.0, 1.0]:
		_box("big", m, Vector3(sx * 1.16, 2.05, -1.2), Vector3(0.03, 0.6, 1.6), GLASS, 1.0)
		_box("big", m, Vector3(sx * 1.16, 2.05, 1.8), Vector3(0.03, 0.6, 1.1), GLASS, 1.0)
		_cyl("big", m, Vector3(sx * 1.0, 0.36, 0.4), 0.36, 0.25, TYRE, 10, Basis(Vector3.BACK, PI * 0.5))
	_box("big", m, Vector3(-1.16, 1.25, 0.6), Vector3(0.03, 1.8, 0.7), cream.darkened(0.2))
	_strut("big", m * Vector3(0, 0.5, -3.2), m * Vector3(0, 0.45, -4.3), 0.1, DARK)
	_box("big", m, Vector3(0, 2.8, 0.5), Vector3(0.7, 0.15, 0.7), cream.darkened(0.1))


## Hospitality marquee: pitched canvas roof on poles, open to the pit side.
func _marquee(m: Transform3D, trim: Color) -> void:
	var canvas := Color(0.84, 0.83, 0.78)
	for x: float in [-3.0, 3.0]:
		for z: float in [-4.5, 0.0, 4.5]:
			_box("big", m, Vector3(x, 1.25, z), Vector3(0.08, 2.5, 0.08), STEEL)
	_prism("big", m, Vector3(0, 3.1, 0), Vector3(6.6, 1.3, 9.4), canvas)
	_box("big", m, Vector3(0, 2.3, 0), Vector3(6.62, 0.35, 9.42), trim)
	_box("big", m, Vector3(3.0, 1.25, 0), Vector3(0.04, 2.5, 9.0), canvas.darkened(0.08)) # back wall
	for z: float in [-2.5, 0.0, 2.5]:
		_box("small", m, Vector3(0.8, 0.38, z), Vector3(0.9, 0.05, 0.9), Color(0.8, 0.78, 0.72)) # tables
		_box("small", m, Vector3(0.8, 0.19, z), Vector3(0.06, 0.38, 0.06), STEEL)


func _portakabin(m: Transform3D) -> void:
	var wall := Color(0.76, 0.74, 0.68)
	_box("big", m, Vector3(0, 1.6, 0), Vector3(3.0, 2.7, 7.2), wall, 0.2)
	_box("big", m, Vector3(0, 3.0, 0), Vector3(3.1, 0.12, 7.3), Color(0.35, 0.36, 0.36))
	for z: float in [-2.4, 0.0, 2.4]:
		_box("big", m, Vector3(-1.51, 1.95, z), Vector3(0.03, 0.8, 1.4), GLASS, 1.0)
	_box("big", m, Vector3(1.51, 1.3, 2.6), Vector3(0.03, 1.9, 0.85), Color(0.3, 0.32, 0.3))
	for z: float in [-3.0, 3.0]:
		_box("big", m, Vector3(0, 0.12, z), Vector3(2.8, 0.25, 0.4), CONCRETE)


## Period saloon, parked.
func _saloon(m: Transform3D, col: Color) -> void:
	_box("big", m, Vector3(0, 0.62, 0), Vector3(1.7, 0.6, 4.3), col, 0.7)
	_box("big", m, Vector3(0, 1.15, 0.2), Vector3(1.5, 0.48, 2.2), GLASS, 1.0)
	_box("big", m, Vector3(0, 1.41, 0.2), Vector3(1.52, 0.05, 2.1), col, 0.7)
	for sx: float in [-0.8, 0.8]:
		for z: float in [-1.35, 1.35]:
			_cyl("big", m, Vector3(sx, 0.32, z), 0.32, 0.22, TYRE, 10, Basis(Vector3.BACK, PI * 0.5))


func _helipad(p: Vector3, basis: Basis) -> void:
	var m := Transform3D(basis, p)
	_cyl("big", m, Vector3(0, 0.05, 0), 8.0, 0.4, Color(0.42, 0.42, 0.4), 20)
	_print("big", m, Vector3(0, 0.26, 0), Vector3.UP, 9.0, 9.0, uv.pad, Vector3.FORWARD)
	# Windsock.
	var sock := m * Vector3(9.5, 0, -6.0)
	_cyl("small", Transform3D.IDENTITY, sock + Vector3.UP * 2.5, 0.05, 5.0, STEEL, 6)
	var wind := basis * Vector3(0.6, 0, 1).normalized()
	var sock_basis := Basis.looking_at(wind, Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.25)
	for s in 3:
		var col := Color(0.8, 0.3, 0.08) if s % 2 == 0 else Color(0.85, 0.84, 0.8)
		_cone("small", Transform3D(sock_basis, sock + Vector3.UP * 4.9), Vector3(0, -0.35 - s * 0.45, 0), 0.32 - s * 0.06, 0.45, col, 8, Basis(Vector3.RIGHT, PI))
	_helicopter(Transform3D(basis.rotated(Vector3.UP, rng.randf_range(0.3, 0.9)), p + Vector3.UP * 0.25))
	_person(m * Vector3(3.0, 0.25, 2.0), basis * Vector3(-1, 0, -0.3), Color(0.2, 0.22, 0.25))


## Small turbine helicopter in a period two-tone scheme. -Z forward.
func _helicopter(m: Transform3D) -> void:
	var body := Color(0.13, 0.17, 0.3)
	var white := Color(0.82, 0.8, 0.76)
	var c := "big"
	_ball(c, m, Vector3(0, 1.55, -0.2), Vector3(1.7, 1.75, 3.4), body, 0.7, 14)
	_ball(c, m, Vector3(0, 1.72, -1.05), Vector3(1.56, 1.4, 1.9), GLASS, 1.0, 12)
	_box(c, m, Vector3(0, 1.25, 0.0), Vector3(1.66, 0.16, 2.4), white, 0.6)
	_box(c, m, Vector3(0, 1.9, 3.2), Vector3(0.32, 0.36, 4.4), body, 0.7)
	_box(c, m, Vector3(0, 2.5, 5.3), Vector3(0.1, 1.3, 0.8), body, 0.7, Basis(Vector3.RIGHT, 0.35))
	_box(c, m, Vector3(0, 1.9, 4.6), Vector3(1.6, 0.06, 0.45), white, 0.6)
	_box(c, m, Vector3(0.2, 2.5, 5.45), Vector3(0.03, 1.3, 0.12), DARK)
	_cyl(c, m, Vector3(0, 2.35, 0.2), 0.5, 0.4, body, 10, Basis(), 0.7)
	_cyl(c, m, Vector3(0, 2.7, 0), 0.1, 0.5, DARK, 8)
	for a: float in [0.6, 0.6 + PI * 0.5]:
		_box(c, m, Vector3(0, 2.95, 0), Vector3(0.28, 0.04, 10.4), DARK, 0.2, Basis(Vector3.UP, a))
	for sx: float in [-1.0, 1.0]:
		_cyl(c, m, Vector3(sx * 0.95, 0.06, -0.2), 0.05, 3.4, Color(0.3, 0.3, 0.3), 6, Basis(Vector3.RIGHT, PI * 0.5), 0.6)
		for z: float in [-1.0, 0.7]:
			_strut(c, m * Vector3(sx * 0.95, 0.06, z), m * Vector3(sx * 0.55, 0.95, z), 0.07, Color(0.3, 0.3, 0.3))


## Paddock floodlight mast; heads aim along `aim`.
func _floodlight(p: Vector3, aim: Vector3) -> void:
	var m := Transform3D(Basis.looking_at(aim, Vector3.UP), p)
	_cyl("big", m, Vector3(0, 8.0, 0), 0.16, 16.0, STEEL, 8, Basis(), 0.5)
	_box("big", m, Vector3(0, 15.6, -0.3), Vector3(3.2, 0.14, 0.14), STEEL)
	for k in 4:
		var hx := -1.2 + k * 0.8
		var tilt := Basis(Vector3.RIGHT, -0.45)
		_box("big", m, Vector3(hx, 16.0, -0.4), Vector3(0.6, 0.5, 0.3), DARK, 0.5, tilt)
		var face := m * (Vector3(hx, 16.0, -0.4) + tilt * Vector3(0, 0, -0.17))
		var fb := m.basis * tilt * Basis.from_scale(Vector3(0.5, 0.4, 0.03))
		if lit:
			_emit("lamp", _proto("box"), Transform3D(fb, face), Color(1.0, 0.92, 0.75), 0.0)
		else:
			_emit("small", _proto("box"), Transform3D(fb, face), Color(0.8, 0.8, 0.76), 1.0)


func _fence(o: Vector3, t: Vector3, r: Vector3, from: Vector2, to: Vector2) -> void:
	var len := from.distance_to(to)
	var posts := maxi(int(len / 3.0), 1)
	var prev := Vector3.INF
	for k in posts + 1:
		var q := from.lerp(to, float(k) / posts)
		var p := _fp(o, t, r, q.x, q.y)
		_box("mid", Transform3D.IDENTITY, p + Vector3.UP * 1.0, Vector3(0.07, 2.0, 0.07), STEEL)
		if prev != Vector3.INF:
			for y: float in [0.5, 1.2, 1.9]:
				_strut("mid", prev + Vector3.UP * y, p + Vector3.UP * y, 0.025, STEEL)
		prev = p


# ---------------------------------------------------------------- marshals

func _marshals() -> void:
	# Next to TrackProps' marshal huts (same spacing), one yellow and one blue.
	var i := 90
	var side := 1.0
	while i < n - 40:
		var k := _i(i)
		var p := at(k, side * (rail_dist(k, side) + 1.3))
		var facing := -rights[k] * side - tangents[k] * 0.6
		_marshal(p - tangents[k] * 1.5, facing, YELLOW_FLAG, rng.randf_range(0.7, 1.0))
		_marshal(p + tangents[k] * 3.0, facing, BLUE_FLAG, rng.randf_range(0.2, 0.5))
		i += 220
		side = -side
	# And on the inside at the entry of every proper corner.
	var in_corner := false
	for j in n:
		var c := absf(corner[j])
		if not in_corner and c > 0.5:
			in_corner = true
			var inside := -1.0 if corner[j] > 0.0 else 1.0 # a left turn's inside is on the left
			var k := _i(j - 2)
			var p := at(k, inside * (rail_dist(k, inside) + 1.4))
			if _road_clear(p, 0.6) and not _in_pits(k, 5):
				var wave := rng.randf_range(0.6, 1.0) if rng.randf() < 0.6 else rng.randf_range(0.1, 0.3)
				_marshal(p, -rights[k] * inside - tangents[k] * 0.7, YELLOW_FLAG if rng.randf() < 0.65 else BLUE_FLAG, wave)
		elif in_corner and c < 0.3:
			in_corner = false


# ---------------------------------------------------------------- trackside clutter

func _clutter() -> void:
	var i := 10
	var placed := 0
	while i < n - 10:
		i += rng.randi_range(15, 30)
		if _in_pits(i, 12):
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var k := _i(i)
		if rng.randf() < 0.4 and _verge_item(k, side):
			placed += 1
			continue
		if _behind_rail(k, side) or _behind_rail(k, -side):
			placed += 1
	_log.append("%d clutter spots" % placed)


func _verge_item(k: int, side: float) -> bool:
	var lo := half + VERGE
	var hi := rail_dist(k, side) - 1.0
	if hi - lo < 0.5:
		return false
	var p := at(k, side * rng.randf_range(lo, hi))
	if not _verge_clear(p, k) or not _clear(p, 1.5):
		return false
	var m := Transform3D(Basis.looking_at(-rights[k] * side, Vector3.UP), p)
	match rng.randi() % 4:
		0: # a few cones
			for c in rng.randi_range(2, 4):
				var cm := m * Transform3D(Basis(), Vector3(rng.randf_range(-0.4, 0.4), 0, (c - 1.5) * 1.6))
				_cone("small", cm, Vector3(0, 0.27, 0), 0.17, 0.5, Color(0.78, 0.33, 0.08), 8)
				_cyl("small", cm, Vector3(0, 0.3, 0), 0.105, 0.08, Color(0.88, 0.87, 0.82), 8)
				_box("small", cm, Vector3(0, 0.015, 0), Vector3(0.38, 0.03, 0.38), DARK)
		1: # marker post
			_box("small", m, Vector3(0, 0.5, 0), Vector3(0.12, 1.0, 0.12), Color(0.86, 0.85, 0.8))
			_box("small", m, Vector3(0, 0.82, 0), Vector3(0.13, 0.18, 0.13), DARK)
			_box("small", m, Vector3(0, 0.62, -0.066), Vector3(0.06, 0.12, 0.01), Color(0.6, 0.08, 0.05), 1.0)
		2: # spare tyres lying about
			for c in rng.randi_range(1, 3):
				var tm := Transform3D(Basis(Vector3.RIGHT, rng.randf_range(0.0, 0.3)), Vector3(rng.randf_range(-0.6, 0.6), 0.12, (c - 1) * 0.8))
				_cyl("small", m * tm, Vector3.ZERO, 0.31, 0.23, TYRE, 10)
		_: # low tyre stack
			_tyre_stack("small", m, Vector3.ZERO, rng.randi_range(2, 4))
	return true


func _behind_rail(k: int, side: float) -> bool:
	var kinds := ["shed", "van", "wreck", "bales", "bales", "bench", "sign", "drums", "loos", "tyres", "spool", "drums"]
	var radius := {shed = 3.0, van = 3.2, wreck = 3.0, bales = 2.2, bench = 1.3, sign = 1.0, drums = 1.6, loos = 1.8, tyres = 1.6, spool = 1.2}
	var kind: String = kinds[rng.randi() % kinds.size()]
	if kind == "wreck" and _wrecks >= 2:
		kind = "bales"
	var rad: float = radius[kind]
	var p := Vector3.INF
	for attempt in 3:
		var q := at(k + attempt * 3, side * (rail_dist(k, side) + rng.randf_range(1.2, 9.0) + rad))
		if _road_clear(q, rad + 0.5) and _clear(q, rad):
			p = q
			k = _i(k + attempt * 3)
			break
	if p == Vector3.INF:
		return false
	var face := -rights[k] * side
	var basis := Basis.looking_at(face, Vector3.UP)
	var m := Transform3D(basis, p)
	match kind:
		"shed":
			_shed(m.rotated_local(Vector3.UP, rng.randf_range(-0.3, 0.3)))
		"van":
			_van(Transform3D(Basis.looking_at(tangents[k] * (1.0 if rng.randf() < 0.5 else -1.0) + face * 0.4, Vector3.UP), p))
			if rng.randf() < 0.6:
				_person(p + face * 1.8 + tangents[k] * rng.randf_range(-2.0, 2.0), face, Color(0.2, 0.22, 0.3), 0.05)
		"wreck":
			_wreck(m.rotated_local(Vector3.UP, rng.randf() * TAU))
			_wrecks += 1
		"bales":
			_bales(m.rotated_local(Vector3.UP, rng.randf_range(-0.4, 0.4)))
		"bench":
			_bench(m)
			if rng.randf() < 0.5:
				_person(p + face * 0.6, face, [Color(0.45, 0.3, 0.16), Color(0.15, 0.22, 0.42), Color(0.55, 0.52, 0.46)][rng.randi() % 3], 0.3)
		"sign":
			_road_sign(Transform3D(Basis.looking_at((face - tangents[k] * 0.8).normalized(), Vector3.UP), p), "sign%d" % (rng.randi() % 4))
		"drums":
			_drums("small", m.rotated_local(Vector3.UP, rng.randf() * TAU), rng.randi_range(3, 6))
		"loos":
			_loos(m)
		"tyres":
			for c in rng.randi_range(5, 9):
				var tm := Transform3D(Basis(Vector3(rng.randf(), 0.2, rng.randf()).normalized(), rng.randf_range(0.0, 1.2)),
					Vector3(rng.randf_range(-1.2, 1.2), 0.16 + (c / 4) * 0.25, rng.randf_range(-1.2, 1.2)))
				_cyl("small", m * tm, Vector3.ZERO, 0.31, 0.23, TYRE, 10)
		"spool":
			_spool(m.rotated_local(Vector3.UP, rng.randf() * TAU))
	no_trees.append([p, rad + 1.0])
	if debug:
		_log.append("%s at %s (look from %s)" % [kind, p, at(k, -side * 2.0) + Vector3.UP * 2.0 - tangents[k] * 25.0])
	return true


func _shed(m: Transform3D) -> void:
	var wood: Color = [WOOD, Color(0.3, 0.26, 0.2), Color(0.34, 0.18, 0.12)][rng.randi() % 3]
	_box("mid", m, Vector3(0, 1.1, 0), Vector3(3.0, 2.2, 2.4), wood)
	_prism("mid", m, Vector3(0, 2.6, 0), Vector3(3.4, 0.8, 2.7), Color(0.17, 0.16, 0.15), Basis(Vector3.UP, PI * 0.5))
	_box("mid", m, Vector3(0.6, 0.95, -1.22), Vector3(0.9, 1.8, 0.04), wood.darkened(0.35))
	_box("mid", m, Vector3(-0.75, 1.45, -1.22), Vector3(0.6, 0.5, 0.04), GLASS, 1.0)
	for x: float in [-1.45, -0.5, 1.45]:
		_box("mid", m, Vector3(x, 1.1, -1.21), Vector3(0.05, 2.2, 0.02), wood.darkened(0.2))


func _van(m: Transform3D) -> void:
	var paints := [Color(0.8, 0.78, 0.7), Color(0.6, 0.34, 0.12), Color(0.34, 0.38, 0.28), Color(0.5, 0.6, 0.66), Color(0.62, 0.12, 0.08)]
	var col: Color = paints[rng.randi() % paints.size()]
	var c := "mid"
	_box(c, m, Vector3(0, 1.3, 0.35), Vector3(1.9, 1.8, 3.9), col, 0.5)
	_box(c, m, Vector3(0, 0.95, -2.05), Vector3(1.88, 0.95, 0.9), col, 0.5)
	_box(c, m, Vector3(0, 1.82, -1.72), Vector3(1.78, 0.72, 0.06), GLASS, 1.0, Basis(Vector3.RIGHT, 0.35))
	_box(c, m, Vector3(0, 0.58, -2.52), Vector3(1.95, 0.2, 0.15), DARK)
	_box(c, m, Vector3(0, 1.1, 0.35), Vector3(1.92, 0.14, 3.92), Color(0.85, 0.84, 0.8) if col.v < 0.7 else Color(0.5, 0.1, 0.07))
	for sx: float in [-1.0, 1.0]:
		_box(c, m, Vector3(sx * 0.955, 1.78, -1.15), Vector3(0.03, 0.5, 0.8), GLASS, 1.0)
		_cyl(c, m, Vector3(sx * 0.6, 0.95, -2.51), 0.12, 0.03, Color(0.82, 0.8, 0.7), 8, Basis(Vector3.RIGHT, PI * 0.5), 1.0)
		for z: float in [-1.75, 1.55]:
			_cyl(c, m, Vector3(sx * 0.86, 0.35, z), 0.35, 0.24, TYRE, 10, Basis(Vector3.BACK, PI * 0.5))
	# Rally service: roof rack with spare wheels.
	_box(c, m, Vector3(0, 2.25, 0.5), Vector3(1.7, 0.06, 2.8), STEEL)
	for z: float in [-0.3, 0.5, 1.3]:
		_cyl(c, m, Vector3(0, 2.4, z), 0.33, 0.24, TYRE, 10)


func _wreck(m: Transform3D) -> void:
	var rust := Color(0.3, 0.17, 0.1)
	var burnt := Color(0.08, 0.075, 0.07)
	var tilt: Transform3D
	if rng.randf() < 0.35:
		tilt = Transform3D(Basis(Vector3.BACK, PI - 0.12), Vector3(0, 1.45, 0)) # on its roof
	else:
		tilt = Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)) * Basis(Vector3.RIGHT, rng.randf_range(-0.06, 0.06)), Vector3(0, -0.12, 0))
	var w := m * tilt
	_box("mid", w, Vector3(0, 0.55, 0), Vector3(1.65, 0.6, 4.1), rust)
	_box("mid", w, Vector3(0, 1.08, 0.2), Vector3(1.4, 0.46, 2.0), burnt)
	_box("mid", w, Vector3(0, 0.9, -1.55), Vector3(1.55, 0.12, 1.0), rust.darkened(0.3), 0.0, Basis(Vector3.RIGHT, 0.2))
	for sx: float in [-0.8, 0.8]:
		_cyl("mid", w, Vector3(sx, 0.3, 1.3), 0.26, 0.16, Color(0.15, 0.1, 0.08), 8, Basis(Vector3.BACK, PI * 0.5))
	_cyl("mid", w, Vector3(0.8, 0.3, -1.3), 0.3, 0.2, TYRE, 8, Basis(Vector3.BACK, PI * 0.5))
	# A door that came off, lying in the grass.
	_box("mid", m, Vector3(2.0, 0.04, 0.5), Vector3(1.0, 0.05, 1.1), rust.darkened(0.1), 0.0, Basis(Vector3.UP, 0.5))


func _bales(m: Transform3D) -> void:
	if rng.randf() < 0.5:
		# Small square bales stacked in a pyramid.
		var rows := [4, 3, 2]
		for y in rows.size():
			for x in rows[y]:
				var c := Vector3((x - (rows[y] - 1) * 0.5) * 1.1, 0.24 + y * 0.46, rng.randf_range(-0.05, 0.05))
				_box("small", m, c, Vector3(1.05, 0.45, 0.5), STRAW, 0.0, Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)))
	else:
		for x in rng.randi_range(2, 3):
			_cyl("small", m, Vector3((x - 1) * 1.6, 0.72, 0), 0.72, 1.2, STRAW.darkened(0.1), 14, Basis(Vector3.BACK, PI * 0.5))


func _bench(m: Transform3D) -> void:
	_box("small", m, Vector3(0, 0.45, 0), Vector3(1.8, 0.06, 0.38), WOOD)
	_box("small", m, Vector3(0, 0.78, 0.18), Vector3(1.8, 0.28, 0.05), WOOD)
	for x: float in [-0.75, 0.75]:
		_box("small", m, Vector3(x, 0.24, 0.02), Vector3(0.07, 0.48, 0.4), DARK)


func _road_sign(m: Transform3D, key: String) -> void:
	_cyl("small", m, Vector3(0, 1.3, 0.04), 0.045, 2.6, STEEL, 6)
	_print("small", m, Vector3(0, 2.2, -0.035), Vector3.FORWARD, 1.5, 1.1, uv[key])
	_box("small", m, Vector3(0, 2.2, 0.0), Vector3(1.52, 1.12, 0.05), Color(0.45, 0.46, 0.46), 0.5)


func _loos(m: Transform3D) -> void:
	var cols := [Color(0.2, 0.34, 0.3), Color(0.26, 0.32, 0.44), Color(0.52, 0.48, 0.4)]
	for k in rng.randi_range(2, 3):
		var col: Color = cols[(k + rng.randi()) % cols.size()]
		var x := (k - 1) * 1.2
		_box("small", m, Vector3(x, 1.12, 0), Vector3(1.1, 2.25, 1.15), col, 0.3)
		_box("small", m, Vector3(x, 2.3, 0), Vector3(1.16, 0.1, 1.22), col.lightened(0.25), 0.3)
		_box("small", m, Vector3(x, 1.05, -0.58), Vector3(0.8, 1.9, 0.02), col.darkened(0.3))


func _spool(m: Transform3D) -> void:
	var rot := Basis(Vector3.RIGHT, PI * 0.5)
	for z: float in [-0.4, 0.4]:
		_cyl("small", m, Vector3(0, 0.7, z), 0.7, 0.07, WOOD, 12, rot)
	_cyl("small", m, Vector3(0, 0.7, 0), 0.4, 0.75, Color(0.12, 0.12, 0.12), 10, rot)


# ---------------------------------------------------------------- billboards on the hillsides

func _billboards() -> void:
	var i := 60
	var side := -1.0
	var brand := rng.randi() % BILLBOARDS.size()
	while i < n - 40:
		i += rng.randi_range(110, 170)
		side = -side
		var k := _i(i)
		if _in_pits(k, 20):
			continue
		var lat := rail_dist(k, side) + rng.randf_range(18.0, 34.0)
		var p := at(k, side * lat)
		if not _road_clear(p, 12.0) or not _clear(p, 6.0):
			continue
		var facing := (-rights[k] * side - tangents[k] * 0.5).normalized()
		var basis := Basis.looking_at(-facing, Vector3.UP) # +Z faces the track
		var along := basis.x
		var ground := minf(_gy(p + along * 3.5), _gy(p - along * 3.5))
		ground = minf(ground, p.y)
		var m := Transform3D(basis, Vector3(p.x, ground, p.z))
		var top := maxf(maxf(_gy(p + along * 3.5), _gy(p - along * 3.5)), p.y) - ground + 2.2
		_print("mid", m, Vector3(0, top + 1.6, 0.06), Vector3.BACK, 9.0, 3.0, uv["bb%d" % (brand % BILLBOARDS.size())])
		_box("mid", m, Vector3(0, top + 1.6, 0), Vector3(9.2, 3.2, 0.1), Color(0.25, 0.25, 0.24))
		for x: float in [-3.2, 3.2]:
			_box("mid", m, Vector3(x, (top + 0.2) * 0.5, -0.15), Vector3(0.2, top + 0.2, 0.2), WOOD)
			_strut("mid", m * Vector3(x, 0, -2.0), m * Vector3(x, top * 0.8, -0.2), 0.12, WOOD)
		no_trees.append([p, 8.0])
		brand += 1


# ---------------------------------------------------------------- landmarks

func _landmarks() -> void:
	var list: Array = LANDMARKS.get(track_id, LANDMARKS.kiefernring)
	for kind: String in list:
		match kind:
			"sign":
				var p := _site(150.0, 260.0, 45.0, 1.0)
				if p != Vector3.INF:
					_hill_sign(p, _to_track(p), "HELIOS")
			"mast":
				var p := _site(140.0, 320.0, 20.0, 1.0)
				if p != Vector3.INF:
					_mast(p)
			"castle":
				var p := _site(150.0, 300.0, 32.0, 1.0)
				if p != Vector3.INF:
					_castle(p, _to_track(p))
			"viaduct":
				for attempt in 6:
					var p := _site(170.0, 280.0, 30.0, -1.0)
					if p != Vector3.INF and _viaduct(p, _to_track(p)):
						break
			"quarry":
				var p := _site(150.0, 280.0, 45.0, 0.5)
				if p != Vector3.INF:
					_quarry(p, _to_track(p))


## On a coast track: would something of `radius` at `p` stand in the sea?
func _seaward(p: Vector3, radius: float) -> bool:
	return has_sea and Vector2(p.x, p.z).dot(sea_dir) + radius > sea_limit


## Best of a few random spots `lo`..`hi` m off the track with `radius` free,
## preferring high (prefer > 0) or low (prefer < 0) ground.
func _site(lo: float, hi: float, radius: float, prefer: float, tries := 80) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	for a in tries:
		var i := rng.randi() % n
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var p := centers[i] + rights[i] * side * rng.randf_range(lo, hi)
		p.y = _gy(p)
		if not _in_terrain(p, 80.0) or _seaward(p, radius) or _track_dist(p) < 120.0 + radius * 0.5 or not _clear(p, radius):
			continue
		var score := p.y * prefer + rng.randf() * 4.0
		if score > best_score:
			best_score = score
			best = p
	return best


## Giant sponsor letters standing on a hillside, facing the track.
func _hill_sign(p: Vector3, face: Vector3, word: String) -> void:
	var u := 2.0
	var along := Vector3.UP.cross(face).normalized() # the viewer's right
	var pitch := 6.4 * u
	var width := word.length() * pitch
	var white := Color(0.84, 0.83, 0.78)
	var frame := Basis(along, Vector3.UP, face) * Basis(Vector3.RIGHT, -0.12) # leaning back into the slope
	for li in word.length():
		var c := p + along * ((li + 0.5) * pitch - width * 0.5)
		c.y = minf(_gy(c - along * 2.5 * u), _gy(c + along * 2.5 * u)) + 0.6
		var m := Transform3D(frame, c)
		for s: Array in LETTERS.get(word[li], []):
			_box("far", m, Vector3((s[0] + s[2] * 0.5 - 2.5) * u, (s[1] + s[3] * 0.5) * u, 0), Vector3(s[2] * u, s[3] * u, 0.5), white)
		for lx: float in [-1.8, 1.8]:
			_box("far", m, Vector3(lx * u, 3.5 * u - 1.5, -1.2), Vector3(0.25, 7.0 * u + 3.0, 0.25), Color(0.3, 0.27, 0.23))
		_box("far", m, Vector3(0, 4.5 * u, -1.1), Vector3(4.2 * u, 0.2, 0.2), Color(0.3, 0.27, 0.23))
	no_trees.append([p, width * 0.5 + 20.0])
	_log.append("sign HELIOS at %s" % p)


## Guyed lattice radio / TV mast with red-and-white bands and blinking beacons.
func _mast(p: Vector3) -> void:
	var h := 84.0
	var sec := 6.0
	var rad := 1.4
	var red := Color(0.6, 0.18, 0.12)
	var white := Color(0.8, 0.79, 0.75)
	var base := p.y - 0.5
	var legs: Array[Vector3] = []
	for k in 3:
		legs.append(Vector3(cos(k * TAU / 3.0), 0.0, sin(k * TAU / 3.0)) * rad)
	for s in int(h / sec):
		var y0 := base + s * sec
		var col := red if (s / 2) % 2 == 0 else white
		for k in 3:
			var a := Vector3(p.x, y0, p.z) + legs[k]
			var b := Vector3(p.x, y0, p.z) + legs[(k + 1) % 3]
			_strut("far", a, a + Vector3.UP * sec, 0.2, col)
			_strut("far", a, b, 0.08, col)
			_strut("far", a, b + Vector3.UP * sec, 0.07, col)
	var top := Vector3(p.x, base + h, p.z)
	_cyl("far", Transform3D.IDENTITY, top + Vector3.UP * 4.0, 0.3, 8.0, white, 8)
	_cyl("far", Transform3D.IDENTITY, top + Vector3.UP * 0.2, rad + 0.6, 0.4, red, 8)
	for y: float in [h * 0.33, h * 0.66, h + 0.5, h + 8.2]:
		_emit("lamp", _proto("box"), Transform3D(Basis.from_scale(Vector3(0.7, 0.5, 0.7)), Vector3(p.x, base + y, p.z)),
			Color(1.0, 0.08, 0.04), 0.0, Vector2(1.0 if y > h else 0.0, 0.0))
	for g in 3:
		var dir := Vector3(cos(g * TAU / 3.0 + PI / 3.0), 0.0, sin(g * TAU / 3.0 + PI / 3.0))
		var anchor := p + dir * 46.0
		anchor.y = _gy(anchor)
		_box("far", Transform3D.IDENTITY, anchor + Vector3.UP * 0.3, Vector3(1.5, 1.2, 1.5), CONCRETE)
		for hy: float in [h * 0.4, h * 0.82]:
			_strut("far", Vector3(p.x, base + hy, p.z) + dir * rad, anchor + Vector3.UP * 0.8, 0.05, Color(0.2, 0.2, 0.2))
		no_trees.append([anchor, 5.0])
	var hut := Transform3D(Basis.looking_at(-_to_track(p), Vector3.UP), p + Vector3(6.0, 0, 5.0))
	hut.origin.y = _gy(hut.origin) - 0.3
	_box("far", hut, Vector3(0, 1.5, 0), Vector3(4.0, 3.0, 3.0), Color(0.62, 0.6, 0.55))
	_box("far", hut, Vector3(0, 3.1, 0), Vector3(4.3, 0.2, 3.3), DARK)
	no_trees.append([p, 14.0])
	_log.append("mast at %s" % p)


## Ruined hilltop castle: a broken keep inside a breached curtain wall.
func _castle(p: Vector3, face: Vector3) -> void:
	var basis := Basis.looking_at(face, Vector3.UP)
	var stone := [Color(0.5, 0.48, 0.44), Color(0.45, 0.43, 0.39), Color(0.55, 0.52, 0.47)]
	var low := INF
	for k in 8:
		var q := p + Vector3(cos(k * TAU / 8.0), 0.0, sin(k * TAU / 8.0)) * 8.0
		low = minf(low, _gy(q))
	var m := Transform3D(basis, Vector3(p.x, low - 2.0, p.z) + basis * Vector3(3.0, 0.0, 2.0))
	var heights := [24.0, 18.0, 12.0, 21.0]
	for k in 4:
		var rot := Basis(Vector3.UP, k * PI * 0.5)
		var hgt: float = heights[k] + rng.randf_range(-1.5, 1.5)
		var col: Color = stone[k % 3]
		# Each wall broken into three uneven pieces.
		for piece in 3:
			var ph := hgt - (rng.randf_range(0.0, 5.0) if piece != 1 else 0.0)
			_box("far", m, rot * Vector3(-3.9 + piece * 3.9, ph * 0.5, 5.0), Vector3(3.95, ph, 1.8), col, 0.0, rot)
			if ph > 17.0 and piece != 2:
				for c in 2:
					_box("far", m, rot * Vector3(-5.1 + piece * 3.9 + c * 2.4, ph + 0.6, 5.0), Vector3(1.2, 1.2, 1.8), col, 0.0, rot)
		for w in 2:
			_box("far", m, rot * Vector3(-2.0 + w * 4.0, hgt * 0.6, 5.92), Vector3(0.4, 1.8, 0.05), Color(0.07, 0.07, 0.07), 0.0, rot)
	# Curtain wall on a seven-sided ring, with a breach and round towers.
	var ring := 7
	var radius := 20.0
	for k in ring:
		var a0 := k * TAU / ring
		var a1 := (k + 1) * TAU / ring
		var q0 := p + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var q1 := p + Vector3(cos(a1), 0.0, sin(a1)) * radius
		if k % 2 == 0:
			var th := rng.randf_range(10.0, 15.0)
			var g := _gy(q0) - 2.0
			_cyl("far", Transform3D.IDENTITY, Vector3(q0.x, g + th * 0.5, q0.z), 3.3, th, stone[k % 3], 10)
			for c in 4:
				if rng.randf() < 0.7:
					var ca := c * TAU / 4.0
					_box("far", Transform3D.IDENTITY, Vector3(q0.x + cos(ca) * 2.8, g + th + 0.6, q0.z + sin(ca) * 2.8), Vector3(1.2, 1.2, 1.2), stone[k % 3])
		if k == 3 or rng.randf() < 0.15:
			continue # breached
		for s in 4:
			var u0 := q0.lerp(q1, s / 4.0)
			var u1 := q0.lerp(q1, (s + 1) / 4.0)
			var mid := (u0 + u1) * 0.5
			var g := _gy(mid) - 2.0
			var hh := rng.randf_range(4.0, 9.0) + 2.0
			_box("far", Transform3D(Basis.looking_at((u1 - u0).normalized(), Vector3.UP), Vector3(mid.x, g, mid.z)), Vector3(0, hh * 0.5, 0),
				Vector3(1.6, hh, u0.distance_to(u1) + 0.1), stone[(k + s + 1) % 3])
	no_trees.append([p, radius + 10.0])
	_log.append("castle at %s" % p)


## Old stone railway viaduct broadside to the track. False if the site is bad.
func _viaduct(p: Vector3, face: Vector3) -> bool:
	var dir := face.cross(Vector3.UP).normalized()
	var spans := 9
	var span := 18.0
	var total := spans * span
	var start := p - dir * total * 0.5
	var hi := -INF
	var lo := INF
	for k in spans + 1:
		var q := start + dir * k * span
		if _track_dist(q) < 110.0 or not _in_terrain(q, 40.0) or _seaward(q, 10.0):
			return false
		hi = maxf(hi, _gy(q))
		lo = minf(lo, _gy(q))
	var deck := maxf(hi + 6.0, lo + 20.0)
	var basis := Basis.looking_at(dir, Vector3.UP)
	var stone := Color(0.5, 0.46, 0.4)
	var I := Transform3D.IDENTITY
	for k in spans + 1:
		var q := start + dir * k * span
		var g := _gy(q) - 2.0
		_box("far", I, Vector3(q.x, (g + deck) * 0.5, q.z), Vector3(5.6, deck - g, 3.0), stone, 0.0, basis)
		_box("far", I, Vector3(q.x, g + 2.5, q.z), Vector3(6.4, 5.0, 3.8), stone.darkened(0.1), 0.0, basis)
		no_trees.append([q, 9.0])
	var r := (span - 3.0) * 0.5
	var crown := deck - 1.2
	var spring := crown - r
	var slices := 8
	for k in spans:
		var c := start + dir * (k + 0.5) * span
		for s in slices:
			var xm := -r + (s + 0.5) * 2.0 * r / slices
			var under := spring + sqrt(maxf(r * r - xm * xm, 0.0))
			var q := c + dir * xm
			_box("far", I, Vector3(q.x, (under + deck) * 0.5, q.z), Vector3(5.4, deck - under, 2.0 * r / slices + 0.04), stone, 0.0, basis)
	var centre := Vector3(p.x, 0.0, p.z)
	_box("far", I, centre + Vector3.UP * (deck + 0.3), Vector3(6.2, 0.6, total + 4.0), stone.darkened(0.12), 0.0, basis)
	for sx: float in [-2.9, 2.9]:
		_box("far", I, centre + basis.x * sx + Vector3.UP * (deck + 1.05), Vector3(0.4, 0.9, total + 4.0), stone.lightened(0.05), 0.0, basis)
	for end: float in [-1.0, 1.0]:
		var e := centre + dir * end * (total * 0.5 + 3.0)
		var g := _gy(e) - 2.0
		_box("far", I, Vector3(e.x, (g + deck) * 0.5, e.z), Vector3(7.0, deck - g, 6.0), stone.darkened(0.05), 0.0, basis)
	_log.append("viaduct at %s, deck %.0f m" % [p, deck - lo])
	return true


## Limestone quarry benched into a hillside, with spoil heaps and a crusher.
func _quarry(p: Vector3, face: Vector3) -> void:
	var back := -face
	var rock := [Color(0.72, 0.68, 0.6), Color(0.66, 0.62, 0.54), Color(0.76, 0.72, 0.64)]
	var floor_y := _gy(p)
	var I := Transform3D.IDENTITY
	for k in 4:
		var radius := 16.0 + k * 7.0
		var segs := 7 + k
		for s in segs:
			var ang := lerpf(-1.2, 1.2, (s + 0.5) / segs)
			var d := back.rotated(Vector3.UP, ang)
			var q := p + d * (radius + 3.5)
			var y0 := floor_y + k * 5.0 - 3.0
			var hgt := 8.0 + rng.randf_range(-0.6, 0.6)
			_box("far", I, Vector3(q.x, y0 + hgt * 0.5, q.z), Vector3(radius * 2.4 / segs + 1.0, hgt, 7.0), rock[(k + s) % 3], 0.0, Basis.looking_at(d, Vector3.UP))
	_cyl("far", I, Vector3(p.x, floor_y - 0.1, p.z), 18.0, 0.5, Color(0.62, 0.59, 0.52), 16)
	var side := face.cross(Vector3.UP).normalized()
	for h in 3:
		var q := p + side * (h - 1) * 11.0 + face * 6.0
		q.y = _gy(q)
		_cone("far", I, q + Vector3.UP * 1.8, rng.randf_range(4.0, 6.0), 4.0, rock[h].darkened(0.1), 10)
	var crusher := Transform3D(Basis.looking_at(face, Vector3.UP), p + side * 14.0)
	crusher.origin.y = _gy(crusher.origin)
	_box("far", crusher, Vector3(0, 4.0, 0), Vector3(6.0, 8.0, 5.0), Color(0.42, 0.37, 0.31))
	_box("far", crusher, Vector3(0, 8.2, 0), Vector3(6.4, 0.4, 5.4), Color(0.3, 0.2, 0.14))
	_strut("far", crusher * Vector3(0, 7.0, -2.5), crusher * Vector3(0, 0.5, -15.0), 1.0, Color(0.3, 0.3, 0.3))
	var dumper := Transform3D(Basis.looking_at(side, Vector3.UP), p - side * 6.0 + face * 2.0)
	dumper.origin.y = _gy(dumper.origin)
	_box("far", dumper, Vector3(0, 1.8, 1.0), Vector3(2.8, 1.4, 4.2), Color(0.6, 0.48, 0.2), 0.0, Basis(Vector3.RIGHT, 0.12))
	_box("far", dumper, Vector3(0, 2.0, -2.2), Vector3(2.2, 1.8, 1.6), Color(0.6, 0.48, 0.2))
	for sx: float in [-1.2, 1.2]:
		for z: float in [-2.0, 1.8]:
			_cyl("far", dumper, Vector3(sx, 0.75, z), 0.75, 0.5, TYRE, 10, Basis(Vector3.BACK, PI * 0.5))
	no_trees.append([p, 48.0])
	_log.append("quarry at %s" % p)
