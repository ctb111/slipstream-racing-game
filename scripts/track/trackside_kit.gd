class_name TracksideKit
extends RefCounted
## Reusable trackside life and set pieces (WRC weekend atmosphere):
##   crowd life  - fans on the banks with red smoke flares, waving flags,
##                 hand-painted bedsheet banners and spectator tape; forest
##                 camps (tents, campers, campfire smoke, camp chairs, parked
##                 cars); photographers with camera flashes
##   gimmicks    - graffiti walls, fan messages painted on the tarmac, fence
##                 banners, timing board, warning / fun signs
##   set pieces  - drive-through / drive-under: inflatable sponsor arch, timber
##                 spectator footbridge, steel truss gantry, a barn the road runs
##                 through, a masonry arch (brick railway bridge or town gate),
##                 an avalanche gallery, a giant tyre arch, a concrete overpass
##
## Usage (GxFans wraps the crowd part; dress_*.gd may call set pieces directly):
##   var kit := TracksideKit.new(circuit_node, lap_curve, road_width, preset)
##   kit.inflatable_arch(kit.idx(300.0), "a_helios", Color(...), Color(...))
##   kit.spectator_bank(i, 1.0, 14, {flags = 3, flares = 2})
##   ...
##   kit.commit()   # builds meshes, crowds, effects, colliders; once, at the end
## Sample index i = lap distance / STEP from the start line; side +1 = right of
## the direction of travel, -1 = left.
##
## Cost: static geometry is merged per 80 m cell and material (one draw call per
## visible cell), with visibility ranges padded by the cell half-diagonal; fx
## (smoke, glows, flags) are a few MultiMeshes per cell, animated in shaders; no
## real lights. Everything over the road keeps >= CLEARANCE above the tarmac;
## solid parts off the road get box colliders.

const STEP := 2.0
const CELL := 80.0
const CLEARANCE := 5.6
const LIFT := 0.036 ## road paint above the centreline (the road ribbon is at +0.02, tyre marks +0.032)
const PAINT := "res://assets/trackside/trackside_paint.png"
const SIGNS := "res://assets/trackside/trackside_signs.png"

## Visibility tiers: [cast shadows, range end (0 = always)].
const VIS := {
	big = [true, 900.0],
	mid = [true, 450.0],
	small = [false, 240.0],
	road = [false, 300.0],
}

const CLOTHES := [Color(0.62, 0.1, 0.08), Color(0.12, 0.2, 0.42), Color(0.86, 0.82, 0.7), Color(0.1, 0.28, 0.14),
	Color(0.9, 0.62, 0.1), Color(0.18, 0.18, 0.2), Color(0.85, 0.3, 0.1), Color(0.35, 0.42, 0.5),
	Color(0.92, 0.92, 0.9), Color(0.5, 0.12, 0.3), Color(0.2, 0.5, 0.75), Color(0.9, 0.85, 0.2)]
const CAR_COLS := [Color(0.62, 0.08, 0.06), Color(0.82, 0.8, 0.74), Color(0.08, 0.1, 0.12), Color(0.15, 0.25, 0.45),
	Color(0.5, 0.52, 0.52), Color(0.2, 0.32, 0.2), Color(0.75, 0.55, 0.15), Color(0.9, 0.9, 0.88)]
const FLAGS := ["flag_de", "flag_it", "flag_fr", "flag_ro", "flag_at", "flag_fi", "flag_se", "flag_pl", "flag_cz",
	"flag_nl", "flag_be", "flag_ch", "flag_no", "flag_hu", "flag_ee", "flag_ie", "flag_dk", "flag_chk", "flag_fan"]
const FAN_SHEETS := ["f_weber", "f_rossi", "f_lind", "f_hopp", "f_novak", "f_duval"]
const GRAFFITI_BIG := ["g_vollgas", "g_apex", "g_nolift", "g_kurve", "g_slip", "g_flat"]
const GRAFFITI_SMALL := ["t_kaos", "t_mira", "t_brk", "t_toxa", "t_zone", "t_lupo", "u_rx", "u_gt", "u_om", "s_brake"]
const ROAD_WORDS := ["GO!", "GO GO GO", "ALLEZ!", "VAI!", "FORZA", "HOPP HOPP", "VAMOS", "HAJRÁ", "HAI!", "WEBER",
	"ROSSI", "LINDQVIST", "DUVAL", "NOVAK", "BRENNAN", "HAAS", "MANCINI", "KOWALSKI", "MOREAU", "SØRENSEN",
	"CASTELL", "FLAT OUT", "NO LIFT", "SEND IT"]
const PAINT_TINTS := [Color(0.95, 0.95, 0.92), Color(0.98, 0.85, 0.2), Color(0.95, 0.95, 0.92), Color(0.6, 0.85, 1.0)]

const RED_SMOKE := Color(0.78, 0.07, 0.05, 0.9)
const PINK_SMOKE := Color(0.9, 0.22, 0.16, 0.8)
const CAMP_SMOKE := Color(0.62, 0.62, 0.6, 0.38)
const WOOD := Color(0.36, 0.26, 0.17)
const DARK := Color(0.08, 0.08, 0.085)
const STEEL := Color(0.52, 0.53, 0.56)
const CONCRETE := Color(0.6, 0.59, 0.56)

var parent: Node3D
var terrain: Terrain
var preset: Dictionary
var half := 6.0
var rng := RandomNumberGenerator.new()
var track_id := ""
var night := false

var centers: Array[Vector3] = []
var rights: Array[Vector3] = []
var tangents: Array[Vector3] = [] ## horizontal
var corner: Array[float] = []
var curv: Array[float] = [] ## signed turn per sample (rad over +-4 samples), + = left
var n := 0
var length := 0.0
var no_trees: Array = []
var _grid := {}

var _batches := {}
var _protos := {}
var _mats := {}
var _solo: Batch = null
var fans_xf: Array[Transform3D] = []
var fans_col: Array[Color] = []
var fans_cus: Array[Color] = []
var seat_xf: Array[Transform3D] = []
var seat_col: Array[Color] = []
var seat_cus: Array[Color] = []
var photo_xf: Array[Transform3D] = []
var photo_col: Array[Color] = []
var photo_cus: Array[Color] = []
var _smoke := {} ## cell key -> [Transform3D, Color, Color custom]
var _glow := {}
var _flags := {}
var _boxes: Array = [] ## [Transform3D, size]
var stats := {}


class Batch:
	extends RefCounted
	var origin := Vector3.ZERO
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()


func _init(p_parent: Node3D, curve: Curve3D, road_width: float, p_preset: Dictionary) -> void:
	parent = p_parent
	terrain = p_parent.get_meta("terrain", null)
	preset = p_preset
	half = road_width * 0.5
	no_trees = p_parent.get_meta("no_trees", [])
	var d: Variant = p_parent.get("def")
	track_id = str(d.get("id", "")) if d is Dictionary else ""
	night = float(p_preset.get("night", 0.0)) > 0.0
	rng.seed = hash(track_id) ^ 0x7a11
	# Sample the circuit's own centreline (offset 0 = start line), like RoadDecals,
	# so paint on the tarmac sits exactly on the road ribbon.
	var base: Curve3D = curve
	var start := 0.0
	var own = p_parent.get("curve")
	if own is Curve3D:
		base = own
		start = float(p_parent.get("start_offset"))
	length = base.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := fposmod(start + i * length / n, length)
		var p := base.sample_baked(off)
		var t := base.sample_baked(fposmod(off + 1.0, length)) - base.sample_baked(fposmod(off - 1.0, length))
		t.y = 0.0
		t = t.normalized()
		centers.append(p)
		tangents.append(t)
		rights.append(t.cross(Vector3.UP).normalized())
		var key := Vector2i(floori(p.x / 30.0), floori(p.z / 30.0))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)
	corner = TrackBuilder._corner_factors(centers)
	curv.resize(n)
	for i in n:
		curv[i] = tangents[_i(i - 4)].signed_angle_to(tangents[_i(i + 4)], Vector3.UP)


# ---------------------------------------------------------------- shared instance

## One kit per circuit, shared by every caller (GxFans etc.) so all their
## geometry merges into the same cells; flush() builds it (gimmicks.gd calls
## it after the per-track dressing).
static func shared(c: Node3D) -> TracksideKit:
	var k = c.get_meta("trackside_kit") if c.has_meta("trackside_kit") else null
	if k == null:
		var w := TrackDefs.ROAD_WIDTH
		var pr: Dictionary = {}
		var wx = c.get("weather")
		if wx != null and wx.get("preset") is Dictionary:
			pr = wx.get("preset")
		k = TracksideKit.new(c, c.get("curve"), w, pr)
		c.set_meta("trackside_kit", k)
	return k


static func flush(c: Node3D) -> void:
	if c.has_meta("trackside_kit"):
		var k = c.get_meta("trackside_kit")
		c.remove_meta("trackside_kit")
		(k as TracksideKit).commit()


# ---------------------------------------------------------------- placement

## Nearest centreline sample to `p` (2D).
func nearest(p: Vector3) -> int:
	var best := INF
	var bi := 0
	var cand := _nearby(p)
	if cand.is_empty():
		cand = range(0, n, 2)
	for k: int in cand:
		var d := Vector2(centers[k].x - p.x, centers[k].z - p.z).length_squared()
		if d < best:
			best = d
			bi = k
	return bi


## Side of the road `p` is on: +1 right of the driving direction, -1 left.
func side_of(p: Vector3, i: int) -> float:
	return 1.0 if (p - centers[_i(i)]).dot(rights[_i(i)]) >= 0.0 else -1.0

func _i(k: int) -> int:
	return posmod(k, n)


## Sample index at `metres` along the lap from the start line.
func idx(metres: float) -> int:
	return _i(int(round(metres / STEP)))


## Guardrail distance from the centreline (TrackBuilder's formula).
func rail_dist(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	var depth := TrackBuilder.GRAVEL_MAX * absf(c) if c * side > 0.0 else 0.0
	return half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)


func gy(p: Vector3) -> float:
	return terrain.surface_at(p.x, p.z) if terrain else p.y


## Point `lateral` metres right of the centreline at sample i, on the ground.
func at(i: int, lateral: float) -> Vector3:
	var k := _i(i)
	var p := centers[k] + rights[k] * lateral
	p.y = gy(p)
	return p


## Frame at sample i: x = right, y = up, -z = direction of travel, origin at `p`.
func frame(i: int, p: Vector3) -> Transform3D:
	var k := _i(i)
	return Transform3D(Basis(rights[k], Vector3.UP, -tangents[k]), p)


## Frame facing `dir` (its -z) at `p`.
func frame_facing(p: Vector3, dir: Vector3) -> Transform3D:
	dir.y = 0.0
	dir = dir.normalized()
	return Transform3D(Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, -dir), p)


func _nearby(p: Vector3) -> Array:
	var out := []
	var cx := floori(p.x / 30.0)
	var cz := floori(p.z / 30.0)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			out.append_array(_grid.get(Vector2i(cx + dx, cz + dz), []))
	return out


## At least `margin` behind the guardrail of every nearby stretch of track.
func road_clear(p: Vector3, margin: float) -> bool:
	for k: int in _nearby(p):
		var d := Vector3(p.x - centers[k].x, 0.0, p.z - centers[k].z)
		if d.length() < rail_dist(k, signf(d.dot(rights[k]))) + margin:
			return false
	return true


## Clear of everything registered in no_trees (other builders' footprints).
func is_free(p: Vector3, r: float) -> bool:
	for z in parent.get_meta("no_trees", []):
		var c: Vector3 = z[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(z[1]) + r:
			return false
	return in_terrain(p, 30.0)


func claim(p: Vector3, r: float) -> void:
	var nt: Array = parent.get_meta("no_trees", [])
	nt.append([p, r])
	parent.set_meta("no_trees", nt)


func in_terrain(p: Vector3, margin: float) -> bool:
	if terrain == null:
		return true
	var size := terrain.cell * (Terrain.N - 1)
	return p.x > terrain.origin.x + margin and p.z > terrain.origin.y + margin \
		and p.x < terrain.origin.x + size - margin and p.z < terrain.origin.y + size - margin


func site_ok(p: Vector3, r: float, margin := 1.5) -> bool:
	return road_clear(p, margin) and is_free(p, r)


## Straight runs: [first sample, sample count], longest first.
func straights(min_samples := 20, limit := 0.08) -> Array:
	var out := []
	var k := 0
	var guard := 0
	# start inside a corner so a straight across the start line is not split
	while absf(corner[_i(k)]) < limit and guard < n:
		k += 1
		guard += 1
	var end := k + n
	while k < end:
		if absf(corner[_i(k)]) >= limit:
			k += 1
			continue
		var j := k
		while j < end and absf(corner[_i(j)]) < limit:
			j += 1
		if j - k >= min_samples:
			out.append([_i(k), j - k])
		k = j
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


## Corner apexes: [sample, turn sign (+1 left)], sharpest first.
func apexes(min_turn := 0.12, sep := 25) -> Array:
	var out := []
	for i in n:
		var c := absf(curv[i])
		if c < min_turn:
			continue
		var best := true
		for j in range(-sep, sep + 1):
			if j != 0 and absf(curv[_i(i + j)]) > c:
				best = false
				break
		if best:
			out.append([i, signf(curv[i])])
	out.sort_custom(func(a, b): return absf(curv[a[0]]) > absf(curv[b[0]]))
	return out


## Lap distance between two samples (shortest way round).
func ring_dist(a: int, b: int) -> int:
	return absi(posmod(a - b + n / 2, n) - n / 2)


## Highest road point on samples i-a .. i+a.
func road_top(i: int, a: int) -> float:
	var y := -INF
	for k in range(-a, a + 1):
		y = maxf(y, centers[_i(i + k)].y)
	return y


# ---------------------------------------------------------------- geometry batching

func _batch(mat: String, vis: String, pos: Vector3) -> Batch:
	if _solo != null:
		return _solo
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	var key := "%s|%s|%d|%d" % [mat, vis, cx, cz]
	var b: Batch = _batches.get(key)
	if b == null:
		b = Batch.new()
		b.origin = Vector3((cx + 0.5) * CELL, pos.y, (cz + 0.5) * CELL)
		_batches[key] = b
	return b


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
		_:
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
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	ov.resize(ix.size())
	on.resize(ix.size())
	for j in ix.size():
		ov[j] = v[ix[j]]
		on[j] = nr[ix[j]]
	_protos[key] = [ov, on]
	return _protos[key]


func _emit(mat: String, vis: String, proto: Array, xf: Transform3D, col: Color, gloss: float) -> void:
	var b := _batch(mat, vis, xf.origin)
	var src: PackedVector3Array = proto[0]
	var m := src.size()
	b.verts.append_array(Transform3D(xf.basis, xf.origin - b.origin) * src)
	var nb := xf.basis.inverse().transposed()
	var nn := PackedVector3Array()
	nn.resize(m)
	var srcn: PackedVector3Array = proto[1]
	for j in m:
		nn[j] = (nb * srcn[j]).normalized()
	b.norms.append_array(nn)
	var c := PackedColorArray()
	c.resize(m)
	c.fill(col)
	b.cols.append_array(c)
	var u := PackedVector2Array()
	u.resize(m)
	u.fill(Vector2.ZERO)
	b.uvs.append_array(u)
	u.fill(Vector2(0.0, gloss))
	b.uv2s.append_array(u)


## Box of `size` centred at local `c` in frame `m`. mat: "props" (paint colour,
## surface inferred) or a Mats type ("brick", "concrete", "wood", "roof_tiles",
## "steel", "corrugated", "plaster", "slate", "rubber") or "stone".
func box(mat: String, vis: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, gloss := 0.0,
		rot := Basis(), collide := false) -> void:
	var xf := Transform3D(m.basis * rot * Basis.from_scale(size), m * c)
	_emit(mat, vis, _proto("box"), xf, col, gloss)
	if collide:
		_boxes.append([Transform3D(m.basis * rot, m * c), size])


func cyl(mat: String, vis: String, m: Transform3D, c: Vector3, radius: float, height: float, col: Color, segs := 10,
		rot := Basis(), gloss := 0.0) -> void:
	_emit(mat, vis, _proto("cyl", segs), Transform3D(m.basis * rot * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), m * c), col, gloss)


func cone(mat: String, vis: String, m: Transform3D, c: Vector3, radius: float, height: float, col: Color, segs := 8) -> void:
	_emit(mat, vis, _proto("cone", segs), Transform3D(m.basis * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)), m * c), col, 0.0)


func ball(mat: String, vis: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, segs := 10, gloss := 0.0) -> void:
	_emit(mat, vis, _proto("sphere", segs), Transform3D(m.basis * Basis.from_scale(size), m * c), col, gloss)


func prism(mat: String, vis: String, m: Transform3D, c: Vector3, size: Vector3, col: Color, rot := Basis()) -> void:
	_emit(mat, vis, _proto("prism"), Transform3D(m.basis * rot * Basis.from_scale(size), m * c), col, 0.0)


## Beam of square section from world `a` to world `b`.
func strut(mat: String, vis: String, a: Vector3, b: Vector3, thick: float, col: Color, gloss := 0.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var up := Vector3.UP if absf(d.y / len) < 0.99 else Vector3.RIGHT
	_emit(mat, vis, _proto("box"), Transform3D(Basis.looking_at(d / len, up) * Basis.from_scale(Vector3(thick, thick, len)), (a + b) * 0.5), col, gloss)


static func region(table: Dictionary, key: String) -> Rect2:
	var r: Array = table.get(key, [0, 0, 0.01, 0.01, 1.0])
	return Rect2(r[0], r[1], r[2], r[3])


static func aspect(table: Dictionary, key: String) -> float:
	var r: Array = table.get(key, [0, 0, 0.01, 0.01, 1.0])
	return float(r[4])


## Quad facing local `normal` (with local `up`), w x h metres, textured from
## an atlas region. mat "props" = printed sign (opaque, signs atlas), "paint" =
## spray paint / road paint (alpha, paint atlas, tinted by `col`).
func quad(mat: String, vis: String, m: Transform3D, c: Vector3, normal: Vector3, w: float, h: float, key: String,
		col := Color.WHITE, up := Vector3.UP) -> void:
	var table: Dictionary = TracksideUV.SIGNS if mat == "props" else TracksideUV.PAINT
	var rg := region(table, key)
	if h <= 0.0:
		h = w / aspect(table, key)
	var nw := (m.basis * normal).normalized()
	var uw := (m.basis * up).normalized()
	var rw := uw.cross(nw).normalized()
	var cw: Vector3 = m * c
	var b := _batch(mat, vis, cw)
	cw -= b.origin
	var r := rw * w * 0.5
	var u := uw * h * 0.5
	var pts := [cw - r + u, cw + r + u, cw + r - u, cw - r - u]
	var uvp := [rg.position, Vector2(rg.end.x, rg.position.y), rg.end, Vector2(rg.position.x, rg.end.y)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		b.verts.append(pts[k])
		b.norms.append(nw)
		b.cols.append(col)
		b.uvs.append(uvp[k])
		b.uv2s.append(Vector2(1.0, 0.0))


## Same quad printed on both faces (banners seen from both directions).
func quad2(vis: String, m: Transform3D, c: Vector3, normal: Vector3, w: float, h: float, key: String, key_back := "") -> void:
	quad("props", vis, m, c + normal * 0.02, normal, w, h, key)
	quad("props", vis, m, c - normal * 0.02, -normal, w, h, key if key_back == "" else key_back)


# ---------------------------------------------------------------- people & fx

## Jacket colours by outfit: "summer" (default), "winter" (snow: dark puffer
## jackets), "rain" (wet: waterproofs in bright yellow / red / navy / green).
const OUTFITS := {
	winter = [Color(0.08, 0.09, 0.12), Color(0.12, 0.16, 0.3), Color(0.35, 0.08, 0.08), Color(0.2, 0.22, 0.2),
		Color(0.55, 0.1, 0.08), Color(0.1, 0.1, 0.1), Color(0.25, 0.3, 0.38), Color(0.8, 0.45, 0.08)],
	rain = [Color(0.92, 0.78, 0.1), Color(0.75, 0.12, 0.08), Color(0.1, 0.16, 0.36), Color(0.1, 0.35, 0.2),
		Color(0.12, 0.12, 0.14), Color(0.9, 0.42, 0.08), Color(0.3, 0.42, 0.55)],
}
var outfit := "" ## "" = from the weather


func _outfit() -> String:
	if outfit != "":
		return outfit
	if float(preset.get("snow", 0.0)) > 0.0:
		return "winter"
	if float(preset.get("wet", 0.0)) > 0.3:
		return "rain"
	return "summer"


func fan(p: Vector3, facing: Vector3, excitement := -1.0) -> void:
	var ex := excitement if excitement >= 0.0 else rng.randf_range(0.0, 1.0)
	fans_xf.append(frame_facing(p, facing.rotated(Vector3.UP, rng.randf_range(-0.35, 0.35))))
	var pal: Array = OUTFITS.get(_outfit(), CLOTHES)
	fans_col.append(pal[rng.randi() % pal.size()])
	if _outfit() == "rain" and rng.randf() < 0.22:
		umbrella(p + Vector3.UP * 0.05)
	fans_cus.append(Color(rng.randf(), ex, 0.0, 0.0))


## Umbrella held over a fan's head (pole + 8-panel canopy), for rainy banks.
func umbrella(p: Vector3) -> void:
	var cols := [Color(0.1, 0.1, 0.12), Color(0.12, 0.2, 0.45), Color(0.7, 0.1, 0.08), Color(0.9, 0.9, 0.88), Color(0.15, 0.32, 0.18)]
	var col: Color = cols[rng.randi() % cols.size()]
	var tilt := Basis(Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU), rng.randf_range(0.05, 0.25))
	var mm := Transform3D(tilt, p + Vector3(0.18, 0.0, 0.0))
	cyl("props", "small", mm, Vector3(0, 1.45, 0), 0.012, 1.1, Color(0.15, 0.15, 0.15), 4)
	cone("props", "small", mm, Vector3(0, 2.12, 0), 0.55, 0.32, col, 8)


func seated_fan(xf: Transform3D) -> void:
	seat_xf.append(xf)
	seat_col.append(CLOTHES[rng.randi() % CLOTHES.size()])
	seat_cus.append(Color(rng.randf(), 0.2, 0.0, 0.0))


func photographer_at(p: Vector3, facing: Vector3) -> void:
	photo_xf.append(frame_facing(p, facing))
	photo_col.append([Color(0.12, 0.13, 0.12), Color(0.3, 0.32, 0.24), Color(0.85, 0.42, 0.1)][rng.randi() % 3])
	photo_cus.append(Color(rng.randf(), 0.0, 0.0, 0.0))
	var f := facing.normalized()
	_add_fx(_glow, p + Vector3.UP * 1.62 + f * 0.35, Color(1.0, 0.97, 0.9), Color(rng.randf(), 0.9, 1.0, 2.5))


func _cell_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func _add_fx(table: Dictionary, p: Vector3, col: Color, custom: Color, basis := Basis()) -> void:
	var key := _cell_key(p)
	if not table.has(key):
		table[key] = []
	table[key].append([Transform3D(basis, p), col, custom])


## A smoke column: `puffs` looping puffs at `p`.
func smoke(p: Vector3, col: Color, puffs: int, size: float, glow := 0.0, life_scale := 1.0) -> void:
	for k in puffs:
		_add_fx(_smoke, p, col, Color(float(k) / puffs + rng.randf_range(0.0, 0.5 / puffs), size * rng.randf_range(0.8, 1.2), glow, life_scale))


## Red smoke flare held up by a fan (or stuck in the ground): smoke + glowing head.
func flare(p: Vector3) -> void:
	smoke(p, RED_SMOKE if rng.randf() < 0.8 else PINK_SMOKE, 8, 1.1, 0.8, 0.85)
	_add_fx(_glow, p, Color(1.0, 0.22, 0.12), Color(rng.randf(), 0.55, 0.0, 2.2))


func campfire(p: Vector3) -> void:
	var m := Transform3D(Basis(), p)
	for k in 6: # stone ring
		var a := k * TAU / 6.0
		ball("props", "small", m, Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.32, 0.2, 0.28), Color(0.45, 0.44, 0.42), 6)
	for k in 3:
		box("props", "small", m, Vector3(0, 0.12, 0), Vector3(0.12, 0.12, 0.8), Color(0.25, 0.17, 0.1), 0.0, Basis(Vector3.UP, k * 1.05))
	_add_fx(_glow, p + Vector3.UP * 0.3, Color(1.0, 0.5, 0.15), Color(rng.randf(), 0.9, 0.0, 1.6))
	smoke(p + Vector3.UP * 0.4, CAMP_SMOKE, 8, 1.3, 0.0, 1.6)


## Flag on a pole planted at `p`, flying towards `dir` (horizontal).
func flag_pole(p: Vector3, dir: Vector3, key := "", height := 3.2) -> void:
	if key == "":
		key = FLAGS[rng.randi() % FLAGS.size()]
	var m := Transform3D(Basis(), p)
	cyl("props", "small", m, Vector3(0, height * 0.5, 0), 0.025, height, Color(0.6, 0.6, 0.62), 5)
	var rg := region(TracksideUV.SIGNS, key)
	_add_fx(_flags, p + Vector3.UP * (height - 1.0), Color.WHITE, Color(rg.position.x, rg.position.y, rg.size.x, rg.size.y),
		frame_facing(Vector3.ZERO, Vector3.UP.cross(dir)).basis)


# ---------------------------------------------------------------- crowd life

## A knot of fans on the bank behind the rail at sample i, facing the road:
## opts: flags (int), flares (int), banner (sheet key or ""), tape (bool), depth (m).
func spectator_bank(i: int, side: float, count: int, opts := {}) -> void:
	var min_off: float = opts.get("min_lat", 0.0) ## metres from the centreline
	var rd := maxf(rail_dist(i, side), min_off - 2.2)
	var depth: float = opts.get("depth", 5.0)
	var spread := maxf(count * 0.9, 8.0)
	var placed := 0
	for k in count * 3:
		if placed >= count:
			break
		var along := rng.randf_range(-spread, spread) * 0.5
		var j := i + int(along / STEP)
		var lat := side * (maxf(rail_dist(j, side), min_off - 2.2) + 2.2 + rng.randf_range(0.0, depth))
		var p := at(j, lat)
		if not road_clear(p, 1.6) or not is_free(p, 0.4):
			continue
		fan(p, -rights[_i(j)] * side, rng.randf_range(0.3, 1.0))
		placed += 1
	if placed == 0:
		return
	var zone := at(i, side * (rd + 2.0 + depth * 0.5))
	claim(zone, spread * 0.5 + 2.0)
	var zones: Array = parent.get_meta("fan_zones", [])
	zones.append({pos = zone, dir = -rights[_i(i)] * side, radius = spread * 0.5, count = placed})
	parent.set_meta("fan_zones", zones)
	for k in int(opts.get("flags", 0)):
		var j := i + rng.randi_range(-int(spread / 4.0), int(spread / 4.0))
		var p := at(j, side * (rd + 2.6 + rng.randf_range(0.0, depth)))
		if road_clear(p, 1.6):
			flag_pole(p, tangents[_i(j)] * (1.0 if rng.randf() < 0.5 else -1.0) + Vector3(0.3, 0, 0.2))
	for k in int(opts.get("flares", 0)):
		var j := i + rng.randi_range(-int(spread / 4.0), int(spread / 4.0))
		var p := at(j, side * (rd + 2.4 + rng.randf_range(0.0, depth)))
		if road_clear(p, 1.6):
			fan(p, -rights[_i(j)] * side, 1.0)
			flare(p + Vector3.UP * 2.05 - rights[_i(j)] * side * 0.25)
	var sheet: String = opts.get("banner", "")
	if sheet != "":
		var p := at(i, side * (rd + 1.6))
		var m := frame_facing(p, -rights[_i(i)] * side)
		for sx: float in [-2.2, 2.2]:
			cyl("props", "small", m, Vector3(sx, 0.9, 0), 0.04, 1.8, WOOD, 5)
		quad2("small", m, Vector3(0, 1.25, 0), Vector3(0, 0, -1), 4.4, 1.1, sheet)
	if opts.get("tape", true):
		spectator_tape(i - int(spread / 4.0) - 2, i + int(spread / 4.0) + 2, side, rd + 1.4)


## Red/white spectator tape on stakes, `lat` metres from the centreline.
func spectator_tape(i0: int, i1: int, side: float, lat: float) -> void:
	var prev := Vector3.INF
	var k := i0
	while k <= i1:
		var p := at(k, side * maxf(lat, rail_dist(k, side) + 1.2))
		var m := Transform3D(Basis(), p)
		cyl("props", "small", m, Vector3(0, 0.5, 0), 0.025, 1.0, Color(0.85, 0.82, 0.75), 4)
		if prev != Vector3.INF:
			var a := prev + Vector3.UP * 0.92
			var b := p + Vector3.UP * 0.92
			var mid := (a + b) * 0.5
			strut("props", "small", a, mid, 0.05, Color(0.85, 0.08, 0.06))
			strut("props", "small", mid, b, 0.05, Color(0.95, 0.94, 0.9))
		prev = p
		k += 2


## A camp in the trees: tent(s), a camper or estate car, camp chairs with
## seated fans, a campfire with smoke, a flag. `face` points at the track.
func camp(p: Vector3, face: Vector3) -> void:
	var m := frame_facing(p, face)
	var tent_cols := [Color(0.2, 0.42, 0.22), Color(0.75, 0.42, 0.12), Color(0.2, 0.32, 0.6), Color(0.62, 0.12, 0.1), Color(0.55, 0.55, 0.5)]
	for k in rng.randi_range(1, 3): # ridge tents
		var c := Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(2.0, 6.0))
		var rot := Basis(Vector3.UP, rng.randf_range(-0.6, 0.6))
		var tc: Color = tent_cols[rng.randi() % tent_cols.size()]
		prism("props", "mid", Transform3D(m.basis, m * Vector3(c.x, gy(m * c) - p.y, c.z)), Vector3(0, 0.6, 0), Vector3(2.0, 1.2, 2.6), tc, rot)
	# camper van or estate car
	var vc := Vector3(rng.randf_range(-3.0, 3.0), 0, 8.5)
	var vm := Transform3D(m.basis * Basis(Vector3.UP, PI * 0.5 + rng.randf_range(-0.3, 0.3)), m * vc)
	vm = on_slope(vm, 1.0, 1.8)
	if rng.randf() < 0.55:
		camper(vm)
	else:
		parked_car(vm, CAR_COLS[rng.randi() % CAR_COLS.size()], true)
	# fire, chairs and the people on them
	var fc: Vector3 = m * Vector3(0, 0, -1.0)
	fc.y = gy(fc)
	campfire(fc)
	var chairs := rng.randi_range(2, 4)
	for k in chairs:
		var a := -PI * 0.5 + (k - (chairs - 1) * 0.5) * 0.9 + PI
		var cp: Vector3 = fc + m.basis * Vector3(cos(a) * 1.7, 0, sin(a) * 1.7)
		cp.y = gy(cp)
		var to_fire := (fc - cp).normalized()
		var cm := frame_facing(cp, to_fire)
		box("props", "small", cm, Vector3(0, 0.42, 0.05), Vector3(0.5, 0.05, 0.45), Color(0.15, 0.25, 0.5))
		box("props", "small", cm, Vector3(0, 0.7, 0.28), Vector3(0.5, 0.55, 0.04), Color(0.15, 0.25, 0.5), 0.0, Basis(Vector3.RIGHT, -0.2))
		seated_fan(Transform3D(cm.basis, cp + Vector3.UP * 0.45 + to_fire * 0.02))
	flag_pole(m * Vector3(4.5, 0, 3.0) + Vector3.UP * (gy(m * Vector3(4.5, 0, 3.0)) - p.y), m.basis.x)
	claim(p + m.basis * Vector3(0, 0, 3.5), 11.0)


func camper(m: Transform3D) -> void:
	var body := Color(0.88, 0.86, 0.8)
	box("props", "mid", m, Vector3(0, 1.45, 0), Vector3(2.2, 2.3, 5.6), body, 0.4)
	box("props", "mid", m, Vector3(0, 1.05, 0), Vector3(2.22, 0.35, 5.62), Color(0.55, 0.22, 0.12), 0.4) # stripe
	box("props", "mid", m, Vector3(0, 1.85, -2.81), Vector3(1.9, 0.7, 0.04), Color(0.05, 0.06, 0.07), 0.95) # windscreen
	for sx: float in [-1.12, 1.12]:
		box("props", "mid", m, Vector3(sx, 1.9, 0.6), Vector3(0.04, 0.6, 1.6), Color(0.05, 0.06, 0.07), 0.95)
		for sz: float in [-1.8, 1.8]:
			cyl("props", "small", m, Vector3(sx * 0.9, 0.36, sz), 0.36, 0.25, DARK, 10, Basis(Vector3.FORWARD, PI * 0.5))
	# awning
	box("props", "small", m, Vector3(2.1, 2.45, 0.4), Vector3(2.2, 0.05, 3.0), Color(0.75, 0.55, 0.2), 0.0, Basis(Vector3.FORWARD, -0.12))


## `m` (upright) set down on the ground and tilted to it: half-track `hx`,
## half-wheelbase `hz`, so a car or camper rests on all four wheels.
func on_slope(m: Transform3D, hx: float, hz: float) -> Transform3D:
	var o := m.origin
	var x := m.basis.x.normalized()
	var z := m.basis.z.normalized()
	var yr := gy(o + x * hx)
	var yl := gy(o - x * hx)
	var yb := gy(o + z * hz)
	var yf := gy(o - z * hz)
	var bx := (x + Vector3.UP * (yr - yl) / (2.0 * hx)).normalized()
	var bz := (z + Vector3.UP * (yb - yf) / (2.0 * hz)).normalized()
	var by := bz.cross(bx).normalized()
	o.y = (yr + yl + yb + yf) * 0.25
	return Transform3D(Basis(bx, by, bx.cross(by)), o)


## A parked saloon / estate (local -z = its nose).
func parked_car(m: Transform3D, col: Color, estate := false) -> void:
	box("props", "mid", m, Vector3(0, 0.62, 0), Vector3(1.7, 0.62, 4.3), col, 0.55)
	var cab_len := 2.6 if estate else 2.0
	box("props", "mid", m, Vector3(0, 1.17, 0.35 if estate else 0.15), Vector3(1.5, 0.5, cab_len), col, 0.55)
	box("props", "mid", m, Vector3(0, 1.17, 0.35 if estate else 0.15), Vector3(1.52, 0.4, cab_len - 0.2), Color(0.05, 0.06, 0.07), 0.95)
	for sx: float in [-0.78, 0.78]:
		for sz: float in [-1.35, 1.35]:
			cyl("props", "small", m, Vector3(sx, 0.32, sz), 0.32, 0.2, DARK, 10, Basis(Vector3.FORWARD, PI * 0.5))


## Cars parked nose-to-tail along an access track from `p` towards `dir`.
func car_row(p: Vector3, dir: Vector3, count: int) -> void:
	dir.y = 0.0
	dir = dir.normalized()
	var placed := 0
	for k in count:
		var c := p + dir * k * 5.4
		c.y = gy(c)
		if not site_ok(c, 1.5, 3.0):
			continue
		var m := on_slope(frame_facing(c, dir.rotated(Vector3.UP, PI * 0.5 + rng.randf_range(-0.12, 0.12))), 0.8, 1.4)
		parked_car(m, CAR_COLS[rng.randi() % CAR_COLS.size()], rng.randf() < 0.4)
		placed += 1
	if placed > 0:
		for k in count / 2 + 1:
			claim(p + dir * k * 10.8, 6.0)


## Photographer at the inside of an apex (or wherever), with camera flashes.
func photographer(i: int, side: float) -> void:
	var p := at(i, side * (rail_dist(i, side) + 1.3))
	if not road_clear(p, 1.0):
		return
	var to_road := -rights[_i(i)] * side
	photographer_at(p, (to_road - tangents[_i(i)] * 0.7).normalized()) # looking at the cars coming
	var p2 := at(i + 3, side * (rail_dist(i + 3, side) + 1.6))
	if road_clear(p2, 1.0) and rng.randf() < 0.6:
		photographer_at(p2, (to_road - tangents[_i(i)] * 0.5).normalized())
	var bm := frame_facing(at(i - 2, side * (rail_dist(i - 2, side) + 0.9)), -tangents[_i(i)])
	box("props", "small", bm, Vector3(0, 0.25, 0), Vector3(0.45, 0.3, 0.3), DARK) # camera bag


# ---------------------------------------------------------------- signs & paint

## Sponsor banners hung on the rail / catch fence from i0 to i1 (facing the road).
func fence_banners(i0: int, i1: int, side: float, keys: Array) -> void:
	var k := i0
	var b := 0
	while k + 2 <= i1:
		var a := at(k, side * (rail_dist(k, side) + 0.35))
		var e := at(k + 2, side * (rail_dist(k + 2, side) + 0.35))
		var mid := (a + e) * 0.5
		var along := e - a
		along.y = 0.0
		var w := along.length()
		if w > 0.5 and road_clear(mid, -0.2):
			var face := -along.normalized().cross(Vector3.UP) * side # towards the road
			var m := frame_facing(mid, face)
			quad2("small", m, Vector3(0, 0.85, 0), Vector3(0, 0, -1), w + 0.04, 0.7, keys[b % keys.size()])
		k += 2
		b += 1 if k % 6 == 0 else 0


## A sign on two posts facing the traffic, `back` metres behind the rail.
func road_sign(i: int, side: float, key: String, scale := 1.0, back := 1.0) -> void:
	var p := at(i, side * (rail_dist(i, side) + back))
	if not road_clear(p, 0.3):
		return
	var m := frame_facing(p, (-tangents[_i(i)] - rights[_i(i)] * side * 0.35).normalized())
	var w := 1.2 * scale
	var h := w / aspect(TracksideUV.SIGNS, key)
	for sx: float in [-0.35, 0.35]:
		cyl("props", "small", m, Vector3(sx * w, (1.2 + h * 0.5) * 0.5, 0.03), 0.035, 1.2 + h * 0.5, Color(0.55, 0.56, 0.58), 5)
	box("props", "small", m, Vector3(0, 1.2 + h * 0.5, 0.025), Vector3(w, h, 0.03), Color(0.55, 0.56, 0.58))
	quad("props", "small", m, Vector3(0, 1.2 + h * 0.5, 0.0), Vector3(0, 0, -1), w, h, key)


## Big timing board on legs (stage times in amber).
func timing_board(i: int, side: float) -> void:
	var p := at(i, side * (rail_dist(i, side) + 4.0))
	if not site_ok(p, 3.0, 2.0):
		return
	var m := frame_facing(p, (-tangents[_i(i)] - rights[_i(i)] * side * 0.8).normalized())
	for sx: float in [-2.2, 2.2]:
		box("props", "mid", m, Vector3(sx, 2.0, 0.2), Vector3(0.2, 4.0, 0.2), DARK, 0.4, Basis(), true)
	box("props", "mid", m, Vector3(0, 4.6, 0.12), Vector3(5.2, 3.3, 0.2), DARK, 0.4)
	quad("props", "mid", m, Vector3(0, 4.6, 0.0), Vector3(0, 0, -1), 5.0, 3.1, "timing")
	claim(p, 4.0)


## A stretch of old concrete wall behind the rail covered in graffiti.
func graffiti_wall(i: int, side: float, wall_len: float, height := 2.6, back := 1.5) -> void:
	var segs := maxi(int(wall_len / 4.0), 1)
	var k0 := i - int(wall_len / STEP * 0.5)
	var wall_col := Color(0.58, 0.57, 0.53)
	var placed := false
	for s in segs:
		var k := k0 + s * 2
		var a := at(k, side * (rail_dist(k, side) + back))
		var e := at(k + 2, side * (rail_dist(k + 2, side) + back))
		var mid := (a + e) * 0.5
		if not road_clear(mid, back - 0.6) or not is_free(mid, 1.0):
			continue
		var along := e - a
		along.y = 0.0
		var face := -along.normalized().cross(Vector3.UP) * side
		var m := frame_facing(Vector3(mid.x, minf(a.y, e.y) - 0.3, mid.z), face)
		box("concrete", "mid", m, Vector3(0, height * 0.5, 0.2), Vector3(along.length() + 0.05, height + 0.3, 0.3), wall_col, 0.0, Basis(), true)
		box("concrete", "mid", m, Vector3(0, height + 0.18, 0.2), Vector3(along.length() + 0.1, 0.1, 0.38), wall_col)
		placed = true
	if not placed:
		return
	# Graffiti: one big piece in the middle, tags and throw-ups around it.
	var spots := [[0.0, true]]
	for s in range(1, int(wall_len / 7.0) + 1):
		spots.append([s * 6.5 * (1.0 if s % 2 else -1.0) * 0.5 * ceil(s / 2.0), false])
	for sp: Array in spots:
		var along_m: float = sp[0]
		if absf(along_m) > wall_len * 0.5 - 1.5:
			continue
		var k := i + int(round(along_m / STEP))
		var a := at(k - 1, side * (rail_dist(k - 1, side) + back))
		var e := at(k + 1, side * (rail_dist(k + 1, side) + back))
		var mid := (a + e) * 0.5
		var along := e - a
		along.y = 0.0
		var face := -along.normalized().cross(Vector3.UP) * side
		var m := frame_facing(Vector3(mid.x, minf(a.y, e.y) - 0.3, mid.z), face)
		var big: bool = sp[1]
		var key: String = GRAFFITI_BIG[rng.randi() % GRAFFITI_BIG.size()] if big else GRAFFITI_SMALL[rng.randi() % GRAFFITI_SMALL.size()]
		var w := minf(6.0, wall_len - 1.0) if big else rng.randf_range(1.8, 3.0)
		var h := w / aspect(TracksideUV.PAINT, key)
		if h > height - 0.3:
			h = height - 0.3
			w = h * aspect(TracksideUV.PAINT, key)
		quad("paint", "mid", m, Vector3(rng.randf_range(-0.3, 0.3), 0.3 + 0.25 + h * 0.5 + rng.randf_range(0.0, maxf(height - h - 0.5, 0.0)), -0.03),
			Vector3(0, 0, -1), w, h, key)


## Graffiti sprayed straight onto a wall face: frame `m` (its -z = out of the
## wall), centre `c` local. For set pieces and other builders' walls.
func graffiti(m: Transform3D, c: Vector3, w: float, key := "", big := true) -> void:
	if key == "":
		key = GRAFFITI_BIG[rng.randi() % GRAFFITI_BIG.size()] if big else GRAFFITI_SMALL[rng.randi() % GRAFFITI_SMALL.size()]
	quad("paint", "mid", m, c + Vector3(0, 0, -0.03), Vector3(0, 0, -1), w, 0.0, key)


## Fan message painted on the tarmac at sample i, readable when approaching.
## `stretch` lengthens it along the road the way real road paint is drawn.
func road_text(i: int, lat: float, key: String, width := 5.0, tint := Color(0.95, 0.95, 0.92), stretch := 2.4) -> void:
	var rkey := "r_" + key
	if not TracksideUV.PAINT.has(rkey):
		return
	var rg := region(TracksideUV.PAINT, rkey)
	var long := width / aspect(TracksideUV.PAINT, rkey) * stretch
	width = minf(width, (half - 0.6 - absf(lat)) * 2.0)
	var segs := maxi(int(long / 1.5), 1)
	tint.a = 1.0 - 0.75 * float(preset.get("snow", 0.0))
	var base_off := i * STEP
	var prev := []
	for s in segs + 1:
		var f := float(s) / segs
		var off := base_off - long * 0.5 + long * f
		var k := posmod(int(floor(off / STEP)), n)
		var k2 := _i(k + 1)
		var fr := fposmod(off / STEP, 1.0)
		var c := centers[k].lerp(centers[k2], fr)
		var r := rights[k].lerp(rights[k2], fr).normalized()
		var row := [c + r * (lat - width * 0.5) + Vector3.UP * LIFT, c + r * (lat + width * 0.5) + Vector3.UP * LIFT, f]
		if s > 0:
			# the far end of the text (its top, v = 0) is further down the road
			var v0 := rg.end.y - (rg.size.y * float(prev[2]))
			var v1 := rg.end.y - (rg.size.y * f)
			var b := _batch("paint", "road", prev[0])
			var o := b.origin
			var pts := [prev[0], prev[1], row[1], row[0]]
			var uv := [Vector2(rg.position.x, v0), Vector2(rg.end.x, v0), Vector2(rg.end.x, v1), Vector2(rg.position.x, v1)]
			for q: int in [0, 2, 1, 0, 3, 2]:
				b.verts.append((pts[q] as Vector3) - o)
				b.norms.append(Vector3.UP)
				b.cols.append(tint)
				b.uvs.append(uv[q])
				b.uv2s.append(Vector2(1.0, 0.0))
		prev = row


## A run of fan messages through a braking zone or straight: names and cheers.
func road_messages(i: int, count: int, spacing := 18.0) -> void:
	for k in count:
		var key: String = ROAD_WORDS[rng.randi() % ROAD_WORDS.size()]
		var lat := rng.randf_range(-2.0, 2.0)
		road_text(i + int(k * spacing / STEP), lat, key, rng.randf_range(4.0, 6.5), PAINT_TINTS[rng.randi() % PAINT_TINTS.size()])
		if rng.randf() < 0.25:
			var sym: String = ["sym_arrow", "sym_heart", "sym_check"][rng.randi() % 3]
			road_text(i + int(k * spacing / STEP) + 4, -lat * 0.5, sym, 1.8, Color(0.95, 0.95, 0.92), 1.6)


# ---------------------------------------------------------------- set pieces

## Inflatable sponsor arch spanning the road (legs behind the rails).
func inflatable_arch(i: int, header: String, col_a: Color, col_b: Color) -> void:
	var d := maxf(maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 1.0, 9.5)
	var y0 := maxf(road_top(i, 3), maxf(at(i, d).y, at(i, -d).y)) - 0.2
	var m := frame(i, Vector3(centers[i].x, y0, centers[i].z))
	var segs := 18
	var tube := 0.85
	for k in segs + 1:
		var a := PI * float(k) / segs
		var c := Vector3(cos(a) * d, sin(a) * d, 0)
		ball("props", "mid", m, c, Vector3.ONE * tube * 2.1, col_a if (k / 3) % 2 == 0 else col_b, 10)
		if k < segs:
			var a2 := PI * float(k + 1) / segs
			var c2 := Vector3(cos(a2) * d, sin(a2) * d, 0)
			var dir := (c2 - c).normalized()
			cyl("props", "mid", m, (c + c2) * 0.5, tube, (c2 - c).length(), col_a if (k / 3) % 2 == 0 else col_b, 10,
				Basis(Vector3.BACK, atan2(-dir.x, dir.y)))
	# header banner at the crown, both directions
	quad2("mid", m, Vector3(0, d - 0.2, 0), Vector3(0, 0, 1), 6.6, 1.1, header)
	box("props", "mid", m, Vector3(0, d - 0.2, 0), Vector3(6.6, 1.1, 0.03), Color(0.1, 0.1, 0.1))
	for sx: float in [-d, d]:
		box("props", "small", m, Vector3(sx, 0.15, 0), Vector3(1.9, 0.3, 1.9), Color(0.2, 0.2, 0.2), 0.0, Basis(), true)
		cyl("props", "small", m, Vector3(sx * 1.08, 0.4, 0.9), 0.3, 0.6, Color(0.25, 0.25, 0.27), 8) # blower
		strut("props", "small", m * Vector3(sx * 0.9, d * 0.42, 0), m * Vector3(sx * 1.25, -0.3, -1.6), 0.02, Color(0.9, 0.9, 0.9)) # guy ropes
		strut("props", "small", m * Vector3(sx * 0.9, d * 0.42, 0), m * Vector3(sx * 1.25, -0.3, 1.6), 0.02, Color(0.9, 0.9, 0.9))
	claim(m.origin, d + 2.0)


## Timber spectator footbridge with fans and flags on it.
func timber_footbridge(i: int, banner: String, with_fans := true) -> void:
	var d := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 1.5
	var deck_y := road_top(i, 3) + CLEARANCE + 0.3
	var m := frame(i, Vector3(centers[i].x, deck_y, centers[i].z))
	var w := 2.6
	# trestle towers each side, down to the ground
	for side: float in [-1.0, 1.0]:
		var g := minf(at(i, side * d).y, at(i, side * (d + 3.0)).y)
		var h := deck_y - g + 0.2
		for sx: float in [0.0, 3.0]:
			for sz: float in [-w * 0.5, w * 0.5]:
				box("wood", "big", m, Vector3(side * (d + sx), -h * 0.5, sz), Vector3(0.3, h, 0.3), WOOD, 0.0, Basis(), true)
		# cross bracing
		strut("wood", "big", m * Vector3(side * d, -h + 0.3, -w * 0.5), m * Vector3(side * (d + 3.0), -0.4, -w * 0.5), 0.14, WOOD)
		strut("wood", "big", m * Vector3(side * d, -h + 0.3, w * 0.5), m * Vector3(side * (d + 3.0), -0.4, w * 0.5), 0.14, WOOD)
		# stairs down the back
		var steps := int(h / 0.25)
		for s in steps:
			var f := float(s) / steps
			box("wood", "mid", m, Vector3(side * (d + 3.4 + f * h * 0.9), -f * h, 0), Vector3(0.32, 0.06, 1.1), WOOD)
		box("wood", "big", m, Vector3(side * (d + 1.5), 0, 0), Vector3(3.3, 0.25, w), WOOD) # landing
	# deck and truss sides
	var span := d * 2.0
	box("wood", "big", m, Vector3(0, 0, 0), Vector3(span, 0.3, w), WOOD)
	box("wood", "big", m, Vector3(0, -0.45, 0), Vector3(span, 0.6, 0.3), Color(0.3, 0.22, 0.15))
	for sz: float in [-w * 0.5, w * 0.5]:
		box("wood", "big", m, Vector3(0, 1.1, sz), Vector3(span, 0.14, 0.14), WOOD)
		var posts := int(span / 1.8)
		for p in posts + 1:
			var x := -d + span * p / posts
			box("wood", "mid", m, Vector3(x, 0.55, sz), Vector3(0.12, 1.1, 0.12), WOOD)
			if p < posts:
				var x2 := -d + span * (p + 1) / posts
				strut("wood", "mid", m * Vector3(x, 0.15, sz), m * Vector3(x2, 1.05, sz), 0.08, WOOD)
	# banners hung on both faces
	for sz: float in [-1.0, 1.0]:
		var fm := Transform3D(m.basis, m * Vector3(0, -0.35, sz * (w * 0.5 + 0.1)))
		quad("props", "big", fm, Vector3(-4.6, 0, 0), Vector3(0, 0, sz), 8.0, 1.0, banner)
		quad("props", "big", fm, Vector3(4.6, 0, 0), Vector3(0, 0, sz), 8.0, 1.0, "b_rallye" if banner != "b_rallye" else "b_kronen")
	if with_fans:
		for k in int(span / 1.1):
			var x := -d + 0.6 + k * 1.1
			var sz := rng.randf_range(-0.7, 0.7)
			var facing := -tangents[i] if (k % 3) != 0 else tangents[i]
			fan(m * Vector3(x, 0.15, sz), facing, rng.randf_range(0.5, 1.0))
		for k in 3:
			flag_pole(m * Vector3(rng.randf_range(-d + 1.0, d - 1.0), 0.15, -w * 0.5 + 0.2), rights[i], "", 2.4)
		flare(m * Vector3(rng.randf_range(-3.0, 3.0), 2.1, -w * 0.5 - 0.1))
	claim(m.origin, d + 6.0)


## Steel truss sponsor gantry over the road, header both sides.
func truss_gantry(i: int, header: String, header_back := "") -> void:
	var d := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 0.8
	var beam_y := road_top(i, 2) + CLEARANCE + 0.6
	var m := frame(i, Vector3(centers[i].x, beam_y, centers[i].z))
	var col := Color(0.62, 0.63, 0.66)
	var t := 0.9
	for side: float in [-1.0, 1.0]:
		var g := at(i, side * d).y
		var h := beam_y - g + 1.2
		for cx: float in [-t * 0.5, t * 0.5]:
			for cz: float in [-t * 0.5, t * 0.5]:
				box("steel", "big", m, Vector3(side * d + cx, -h * 0.5 + 1.2, cz), Vector3(0.1, h, 0.1), col, 0.0, Basis(), true)
		var rungs := int(h / 1.2)
		for r in rungs:
			var y := 1.2 - h + r * 1.2
			strut("steel", "mid", m * Vector3(side * d - t * 0.5, y, -t * 0.5), m * Vector3(side * d + t * 0.5, y + 1.2, -t * 0.5), 0.05, col)
			strut("steel", "mid", m * Vector3(side * d - t * 0.5, y, t * 0.5), m * Vector3(side * d + t * 0.5, y + 1.2, t * 0.5), 0.05, col)
		box("concrete", "mid", m, Vector3(side * d, g - beam_y + 0.15, 0), Vector3(1.6, 0.5, 1.6), CONCRETE)
	var span := d * 2.0
	for cy: float in [0.0, 1.2]:
		for cz: float in [-t * 0.5, t * 0.5]:
			box("steel", "big", m, Vector3(0, cy, cz), Vector3(span, 0.1, 0.1), col)
	var cells := int(span / 1.2)
	for c in cells:
		var x := -d + c * span / cells
		var x2 := -d + (c + 1) * span / cells
		for cz: float in [-t * 0.5, t * 0.5]:
			strut("steel", "mid", m * Vector3(x, 0.0, cz), m * Vector3(x2, 1.2, cz), 0.05, col)
	# header boards on both faces
	box("props", "big", m, Vector3(0, 0.6, 0), Vector3(9.4, 1.6, 0.06), DARK)
	quad("props", "big", m, Vector3(0, 0.6, 0.06), Vector3(0, 0, 1), 9.2, 1.53, header_back if header_back != "" else header)
	quad("props", "big", m, Vector3(0, 0.6, -0.06), Vector3(0, 0, -1), 9.2, 1.53, header)
	claim(m.origin, d + 2.0)


## A timber barn the road runs straight through (walls behind the rails).
func barn(i: int, barn_len := 22.0, sign_key := "p_barn") -> void:
	var a := int(barn_len / STEP * 0.5)
	var d := 0.0
	for k in range(-a, a + 1):
		d = maxf(d, maxf(rail_dist(i + k, 1.0), rail_dist(i + k, -1.0)))
	d += 0.8
	var top := road_top(i, a)
	var eave := top + CLEARANCE + 1.2
	var g := INF
	for k in [-a, 0, a]:
		g = minf(g, minf(at(i + k, d).y, at(i + k, -d).y))
	var m := frame(i, Vector3(centers[i].x, eave, centers[i].z))
	var wall_h := eave - g + 0.6
	var plank := Color(0.42, 0.2, 0.14)
	var beam := Color(0.3, 0.22, 0.15)
	for side: float in [-1.0, 1.0]:
		box("wood", "big", m, Vector3(side * (d + 0.15), -wall_h * 0.5, 0), Vector3(0.3, wall_h, barn_len), plank, 0.0, Basis(), true)
		for z in range(-int(barn_len * 0.5), int(barn_len * 0.5) + 1, 4):
			box("wood", "big", m, Vector3(side * (d - 0.05), -wall_h * 0.5, z), Vector3(0.3, wall_h, 0.3), beam)
		# hay bales stacked against the outside
		for k in 3:
			cyl("props", "mid", m, Vector3(side * (d + 1.2), g - eave + 0.65, -barn_len * 0.3 + k * 1.5), 0.65, 1.2, Color(0.66, 0.56, 0.34), 10, Basis(Vector3.FORWARD, PI * 0.5))
	# gable roof
	var rise := d * 0.55
	var slope := atan2(rise, d)
	var rlen := sqrt(d * d + rise * rise) + 1.0
	for side: float in [-1.0, 1.0]:
		box("roof_tiles", "big", m, Vector3(side * d * 0.5, rise * 0.5 + 0.15, 0), Vector3(rlen, 0.25, barn_len + 1.6),
			Color(0.6, 0.32, 0.24), 0.0, Basis(Vector3.BACK, -side * slope))
	# gable ends above the opening (triangles from boxes, stepped planks)
	for ez: float in [-barn_len * 0.5, barn_len * 0.5]:
		var rows := 7
		for r in rows:
			var y := 0.2 + r * rise / rows
			var w := d * 2.0 * (1.0 - float(r) / rows)
			box("wood", "big", m, Vector3(0, y, ez), Vector3(w, rise / rows + 0.02, 0.25), plank)
		box("wood", "big", m, Vector3(0, -0.4, ez), Vector3(d * 2.0 + 0.4, 0.8, 0.4), beam) # lintel
	for ez: float in [-1.0, 1.0]:
		var fm := Transform3D(m.basis, m * Vector3(0, 1.4, ez * (barn_len * 0.5 + 0.15)))
		quad("props", "big", fm, Vector3.ZERO, Vector3(0, 0, ez), 4.0, 1.0, sign_key)
	# graffiti on the outer wall ends
	for side: float in [-1.0, 1.0]:
		var gm := frame_facing(m * Vector3(side * (d + 0.32), 0, 0), m.basis.x * side * -1.0)
		graffiti(Transform3D(gm.basis, gm.origin), Vector3(0, g - eave + 1.8, 0), 5.0, "", true)
	claim(m.origin, maxf(d, barn_len * 0.5) + 4.0)


## Masonry arch over the road: style "rail" = brick railway bridge on the moor,
## "gate" = stone town gate with a tower.
func masonry_arch(i: int, style := "rail") -> void:
	var w := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 0.4 ## opening half-width
	var depth := 7.0 if style == "rail" else 9.0
	var spring := road_top(i, 3) + CLEARANCE - 1.0
	var crown := spring + w
	var top := crown + (2.2 if style == "rail" else 3.0)
	var wing := w + (14.0 if style == "rail" else 7.0)
	var mat := "brick" if style == "rail" else "stone"
	var col := Color(0.82, 0.6, 0.5) if style == "rail" else Color(0.9, 0.87, 0.8)
	var m := frame(i, Vector3(centers[i].x, 0.0, centers[i].z))
	var gmin := INF
	for x in [-wing, -w, 0.0, w, wing]:
		gmin = minf(gmin, at(i, x).y)
	var bottom := gmin - 1.5
	# solid piers outside the opening, down into the ground
	for side: float in [-1.0, 1.0]:
		var x0 := w
		var x1 := wing
		box(mat, "big", m, Vector3(side * (x0 + x1) * 0.5, (bottom + top) * 0.5, 0), Vector3(x1 - x0, top - bottom, depth), col, 0.0, Basis(), true)
	# the arch itself: slices across the opening, intrados smooth
	var slices := 24
	for s in slices:
		var xa := -w + 2.0 * w * s / slices
		var xb := -w + 2.0 * w * (s + 1) / slices
		var ya := spring + sqrt(maxf(w * w - xa * xa, 0.0))
		var yb := spring + sqrt(maxf(w * w - xb * xb, 0.0))
		var y_low := minf(ya, yb)
		box(mat, "big", m, Vector3((xa + xb) * 0.5, (y_low + top) * 0.5, 0), Vector3(xb - xa + 0.02, top - y_low, depth), col)
	# the springing walls up to the arch start
	for side: float in [-1.0, 1.0]:
		box(mat, "big", m, Vector3(side * (w + 0.4), (bottom + spring) * 0.5, 0), Vector3(0.8, spring - bottom, depth), col)
	# coping / parapet
	box(mat, "big", m, Vector3(0, top + 0.5, depth * 0.5 - 0.25), Vector3(wing * 2.0, 1.0, 0.5), col * 0.92)
	box(mat, "big", m, Vector3(0, top + 0.5, -depth * 0.5 + 0.25), Vector3(wing * 2.0, 1.0, 0.5), col * 0.92)
	if style == "rail":
		# track bed and rails on top, a signal post
		box("props", "big", m, Vector3(0, top + 0.1, 0), Vector3(wing * 2.0, 0.2, depth - 1.2), Color(0.32, 0.3, 0.28))
		for rz: float in [-0.72, 0.72]:
			box("steel", "big", m, Vector3(0, top + 0.3, rz), Vector3(wing * 2.0, 0.15, 0.08), STEEL, 0.5)
		var sp := Vector3(wing - 3.0, top, depth * 0.5 - 1.0)
		cyl("steel", "mid", m, sp + Vector3(0, 3.0, 0), 0.1, 6.0, DARK, 6)
		box("props", "mid", m, sp + Vector3(0.35, 5.4, 0), Vector3(0.9, 0.2, 0.12), Color(0.8, 0.1, 0.08))
		for ez: float in [-1.0, 1.0]:
			var fm := Transform3D(m.basis, m * Vector3(0, crown + 0.9, ez * (depth * 0.5 + 0.03)))
			quad("props", "big", fm, Vector3.ZERO, Vector3(0, 0, ez), 4.0, 1.0, "p_rail")
	else:
		# gate tower with a pyramid roof and a plaque, a clock-like disc
		var tw := minf(w * 1.2, 9.0)
		box(mat, "big", m, Vector3(0, top + 4.0, 0), Vector3(tw, 8.0, depth - 1.0), col)
		prism("roof_tiles", "big", m, Vector3(0, top + 10.0, 0), Vector3(tw + 1.0, 4.0, depth), Color(0.62, 0.3, 0.22))
		for ez: float in [-1.0, 1.0]:
			var fm := Transform3D(m.basis, m * Vector3(0, crown + 1.4, ez * (depth * 0.5 + 0.03)))
			quad("props", "big", fm, Vector3.ZERO, Vector3(0, 0, ez), 5.0, 1.25, "p_town")
			cyl("props", "big", m, Vector3(0, top + 5.0, ez * (depth * 0.5 - 0.45)), 1.1, 0.12, Color(0.92, 0.9, 0.82), 16, Basis(Vector3.RIGHT, PI * 0.5))
			for wx: float in [-tw * 0.3, tw * 0.3]:
				box("props", "big", m, Vector3(wx, top + 2.4, ez * (depth * 0.5 - 0.48)), Vector3(0.7, 1.3, 0.06), Color(0.06, 0.06, 0.07), 0.9)
	# graffiti on the piers (road side faces)
	for side: float in [-1.0, 1.0]:
		for ez: float in [-1.0, 1.0]:
			if style == "gate" and rng.randf() < 0.6:
				continue
			var fm := Transform3D(m.basis, m * Vector3(side * (w + 4.5), 0, ez * (depth * 0.5 + 0.02)))
			var gy0 := at(i, side * (w + 4.5)).y
			graffiti(Transform3D(Basis(-m.basis.x * ez, Vector3.UP, -m.basis.z * ez), fm.origin), Vector3(0, gy0 + 1.6, 0), rng.randf_range(4.5, 6.5), "", ez > 0.0)
	claim(m * Vector3(0, 0, 0), wing + 2.0)


## Avalanche gallery: a concrete roof over the road from i to i + len,
## solid on the `wall_side`, open pillars on the other side.
func gallery(i: int, gal_len := 60.0, wall_side := 1.0) -> void:
	var segs := int(gal_len / 4.0)
	var col := Color(0.66, 0.65, 0.62)
	for s in segs:
		var k := i + s * 2
		var din := rail_dist(k, wall_side) + 0.6
		var dout := rail_dist(k, -wall_side) + 0.6
		var top := maxf(centers[_i(k)].y, centers[_i(k + 2)].y) + CLEARANCE + 0.5
		var c := (centers[_i(k)] + centers[_i(k + 2)]) * 0.5
		var m := frame(k + 1, Vector3(c.x, top, c.z))
		var seg_len := centers[_i(k)].distance_to(centers[_i(k + 2)]) + 0.15
		var span := din + dout
		var mid_x := (din - dout) * 0.5 * wall_side
		box("concrete", "big", m, Vector3(mid_x, 0.5, 0), Vector3(span + 1.4, 1.0, seg_len), col)
		box("props", "big", m, Vector3(mid_x, 1.1, 0), Vector3(span + 1.4, 0.25, seg_len), Color(0.95, 0.96, 0.98)) # snow on top
		var g_in := at(k + 1, wall_side * din).y
		var g_out := at(k + 1, -wall_side * dout).y
		var hin := top - g_in + 1.0
		box("concrete", "big", m, Vector3(wall_side * (din + 0.4), -hin * 0.5 + 0.5, 0), Vector3(0.8, hin, seg_len), col, 0.0, Basis(), true)
		if s % 2 == 0:
			var hout := top - g_out + 1.0
			box("concrete", "big", m, Vector3(-wall_side * (dout + 0.4), -hout * 0.5 + 0.5, 0), Vector3(0.9, hout, 1.0), col, 0.0, Basis(), true)
			box("concrete", "big", m, Vector3(-wall_side * (dout + 0.0), -0.6, 0), Vector3(1.6, 0.9, 1.0), col, 0.0, Basis(Vector3.BACK, wall_side * 0.6))
		if s == 0 or s == segs - 1:
			var ez := 1.0 if s == 0 else -1.0
			var fm := Transform3D(m.basis, m * Vector3(mid_x, 0.5, ez * (seg_len * 0.5 + 0.02)))
			quad("props", "big", fm, Vector3.ZERO, Vector3(0, 0, ez), 6.0, 1.2, "p_gallery")
		if s % 5 == 2:
			var wm := Transform3D(Basis(-m.basis.x * wall_side, Vector3.UP, m.basis.z * wall_side), m * Vector3(wall_side * (din - 0.02), 0, 0))
			graffiti(wm, Vector3(0, g_in - top + 2.0, 0), rng.randf_range(2.0, 3.5), "", false)
		claim(c, span * 0.5 + 3.0)


## Giant tyre arch (Dunlop-bridge style) with a sponsor on the sidewall.
func tyre_arch(i: int) -> void:
	var r_in := maxf(maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 0.6, 10.0)
	var r_out := r_in + 2.4
	var y0 := road_top(i, 3) - 0.6
	var m := frame(i, Vector3(centers[i].x, y0, centers[i].z))
	var width := 3.4
	var segs := 30
	var rubber := Color(0.06, 0.06, 0.065)
	for s in segs:
		var a0 := PI * float(s) / segs
		var a1 := PI * float(s + 1) / segs
		var am := (a0 + a1) * 0.5
		var rm := (r_in + r_out) * 0.5
		var arc := rm * (a1 - a0) + 0.08
		var c := Vector3(cos(am) * rm, sin(am) * rm, 0)
		var rot := Basis(Vector3.BACK, am - PI * 0.5)
		box("rubber", "big", m, c, Vector3(arc, r_out - r_in, width), rubber, 0.0, rot)
		# tread blocks
		var cb := Vector3(cos(am) * (r_out + 0.12), sin(am) * (r_out + 0.12), 0)
		for z: float in [-1.0, 0.0, 1.0]:
			box("rubber", "mid", m, cb + Vector3(0, 0, z * 1.05 + (0.3 if s % 2 else -0.3)), Vector3(arc * 0.55, 0.25, 0.7), rubber, 0.0, rot)
	# sponsor on both sidewalls at the crown
	for ez: float in [-1.0, 1.0]:
		var fm := Transform3D(m.basis, m * Vector3(0, (r_in + r_out) * 0.5, ez * (width * 0.5 + 0.03)))
		quad("props", "big", fm, Vector3.ZERO, Vector3(0, 0, ez), 7.5, 1.2, "p_kronen")
	for side: float in [-1.0, 1.0]:
		box("concrete", "big", m, Vector3(side * (r_in + r_out) * 0.5, 0.4, 0), Vector3(r_out - r_in + 1.0, 1.6, width + 1.0), CONCRETE, 0.0, Basis(), true)
	claim(m.origin, r_out + 3.0)


## Concrete overpass (a farm road bridge) with graffiti on the piers.
func overpass(i: int) -> void:
	var d := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 1.0
	var deck_y := road_top(i, 4) + CLEARANCE + 0.8
	var m := frame(i, Vector3(centers[i].x, deck_y, centers[i].z))
	var width := 8.0
	var span := d * 2.0 + 16.0
	var col := Color(0.64, 0.63, 0.6)
	box("concrete", "big", m, Vector3(0, -0.5, 0), Vector3(span, 1.2, width), col)
	for ez: float in [-1.0, 1.0]:
		box("concrete", "big", m, Vector3(0, 0.6, ez * (width * 0.5 - 0.2)), Vector3(span, 1.0, 0.35), col)
		var fm := Transform3D(Basis(-m.basis.x * ez, Vector3.UP, -m.basis.z * ez), m * Vector3(0, 0, ez * (width * 0.5 + 0.0)))
		graffiti(fm, Vector3(rng.randf_range(-3.0, 3.0), 0.55, -0.15), 4.0, GRAFFITI_SMALL[rng.randi() % GRAFFITI_SMALL.size()], false)
	for side: float in [-1.0, 1.0]:
		var g := at(i, side * (d + 0.8)).y
		var h := deck_y - g + 0.2
		box("concrete", "big", m, Vector3(side * (d + 0.8), -h * 0.5 - 0.9, 0), Vector3(1.6, h, width - 1.0), col, 0.0, Basis(), true)
		# embankment block beyond the pier
		var ge := at(i, side * (d + 6.0)).y
		var he := deck_y - ge
		box("concrete", "big", m, Vector3(side * (d + 5.0), -he * 0.5 - 0.6, 0), Vector3(6.5, he, width), col * 0.95, 0.0, Basis(), true)
		for ez: float in [-1.0, 1.0]:
			var fm := Transform3D(Basis(-m.basis.x * ez, Vector3.UP, -m.basis.z * ez), m * Vector3(side * (d + 0.8), 0, ez * ((width - 1.0) * 0.5 + 0.0)))
			graffiti(fm, Vector3(0, g - deck_y + 2.2, -0.02), 2.6, "", false)
		graffiti(Transform3D(Basis(m.basis.z * side, Vector3.UP, m.basis.x * side), m * Vector3(side * (d + 1.75), 0, 0)), Vector3(0, ge - deck_y + 2.4, 0), 5.5, "", true)
	# a parked farm truck on top
	var tm := Transform3D(m.basis * Basis(Vector3.UP, PI * 0.5), m * Vector3(d * 0.4, 0.1, 1.5))
	parked_car(tm, Color(0.25, 0.35, 0.3), true)
	claim(m.origin, d + 8.0)


# ---------------------------------------------------------------- commit

func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"props":
			m = Mats.props(load(SIGNS), _grime(), preset)
		"paint":
			var s := StandardMaterial3D.new()
			s.albedo_texture = load(PAINT)
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			s.roughness = 0.4 if float(preset.get("wet", 0.0)) > 0.3 else 0.75
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			s.cull_mode = BaseMaterial3D.CULL_BACK
			s.shadow_receive = true
			m = s
		"stone":
			var s := StandardMaterial3D.new()
			s.albedo_texture = load("res://assets/themes/stone_wall/stone_wall_diff_1k.jpg")
			s.normal_enabled = true
			s.normal_texture = load("res://assets/themes/stone_wall/stone_wall_nor_gl_1k.jpg")
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.uv1_triplanar = true
			s.uv1_world_triplanar = true
			s.uv1_scale = Vector3.ONE * 0.33
			s.roughness = 0.9
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			m = s
		_:
			m = Mats.mat(key, Color.WHITE, false)
	_mats[key] = m
	return m


func _grime() -> NoiseTexture2D:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.frequency = 0.03
	nz.fractal_octaves = 4
	nz.seed = 91
	var t := NoiseTexture2D.new()
	t.noise = nz
	t.width = 256
	t.height = 256
	t.seamless = true
	t.generate_mipmaps = true
	return t


func _mesh_of(b: Batch) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.verts
	arrays[Mesh.ARRAY_NORMAL] = b.norms
	arrays[Mesh.ARRAY_COLOR] = b.cols
	arrays[Mesh.ARRAY_TEX_UV] = b.uvs
	arrays[Mesh.ARRAY_TEX_UV2] = b.uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _range_for(mi: GeometryInstance3D, base: float, box: AABB) -> void:
	if base <= 0.0:
		return
	mi.visibility_range_end = base + Vector2(box.size.x, box.size.z).length() * 0.5
	# Dissolve over +-25 m instead of popping (the node sits at its cell centre,
	# where Godot measures the fade from).
	mi.visibility_range_end_margin = 25.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Builds everything queued so far into the scene. Call once.
func commit(node_name := "TracksideLife") -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	var tris := 0
	for key: String in _batches:
		var b: Batch = _batches[key]
		if b.verts.is_empty():
			continue
		var parts := key.split("|")
		var mesh := _mesh_of(b)
		var mi := MeshInstance3D.new()
		mi.name = key.replace("|", "_")
		mi.mesh = mesh
		mi.position = b.origin
		mi.material_override = _mat(parts[0])
		var cfg: Array = VIS[parts[1]]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cfg[0] and parts[0] != "paint" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_range_for(mi, cfg[1], mesh.get_aabb())
		root.add_child(mi)
		tris += b.verts.size() / 3
	# colliders for solid parts
	if not _boxes.is_empty():
		var body := StaticBody3D.new()
		body.name = "TracksideColliders"
		root.add_child(body)
		for bx: Array in _boxes:
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = bx[1]
			cs.shape = sh
			cs.transform = bx[0]
			body.add_child(cs)
	# people
	if not fans_xf.is_empty():
		root.add_child(PeopleKit.crowd("Fans", PeopleKit.Role.SPECTATOR, fans_xf, fans_col, fans_cus, false))
	if not seat_xf.is_empty():
		root.add_child(PeopleKit.crowd("CampFans", PeopleKit.Role.SEATED, seat_xf, seat_col, seat_cus, false))
	if not photo_xf.is_empty():
		root.add_child(PeopleKit.crowd("Photographers", PeopleKit.Role.PHOTOGRAPHER, photo_xf, photo_col, photo_cus, false))
	# effects
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2.ONE
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = load("res://shaders/trackside_smoke.gdshader")
	var pn := _grime()
	pn.noise.frequency = 0.08
	pn.width = 128
	pn.height = 128
	smoke_mat.set_shader_parameter("puff_noise", pn)
	var wind: float = parent.get_meta("wind", 0.4)
	smoke_mat.set_shader_parameter("wind", wind * 1.6)
	smoke_mat.set_shader_parameter("rise", lerpf(1.2, 0.7, wind))
	var glow_mat := ShaderMaterial.new()
	glow_mat.shader = load("res://shaders/trackside_glow.gdshader")
	var flag_mat := ShaderMaterial.new()
	flag_mat.shader = load("res://shaders/trackside_flag.gdshader")
	flag_mat.set_shader_parameter("atlas", load(SIGNS))
	flag_mat.set_shader_parameter("wind", wind)
	_fx_multimeshes(root, "Smoke", _smoke, quad_mesh, smoke_mat, 300.0, AABB(Vector3(-8, -1, -8), Vector3(16, 14, 16)))
	_fx_multimeshes(root, "Glow", _glow, quad_mesh, glow_mat, 600.0, AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	_fx_multimeshes(root, "Flags", _flags, _flag_mesh(), flag_mat, 260.0, AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	stats = {meshes = _batches.size(), tris = tris, fans = fans_xf.size(), seated = seat_xf.size(), photographers = photo_xf.size(),
		smoke = _count(_smoke), glows = _count(_glow), flags = _count(_flags), colliders = _boxes.size()}
	return root


func _count(table: Dictionary) -> int:
	var c := 0
	for k in table:
		c += (table[k] as Array).size()
	return c


func _fx_multimeshes(root: Node3D, label: String, table: Dictionary, mesh: Mesh, mat: Material, vis: float, pad: AABB) -> void:
	for key: Vector2i in table:
		var items: Array = table[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = items.size()
		var origin: Vector3 = (items[0][0] as Transform3D).origin
		var box := AABB(origin, Vector3.ZERO)
		for k in items.size():
			var xf: Transform3D = items[k][0]
			box = box.expand(xf.origin)
			mm.set_instance_transform(k, Transform3D(xf.basis, xf.origin - origin))
			mm.set_instance_color(k, items[k][1])
			mm.set_instance_custom_data(k, items[k][2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [label, key.x, key.y]
		mmi.multimesh = mm
		mmi.position = origin
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var local := AABB(box.position - origin + pad.position, box.size + pad.size)
		mmi.custom_aabb = local
		_range_for(mmi, vis, local)
		root.add_child(mmi)


func _flag_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 6
	var ny := 3
	for x in nx:
		for y in ny:
			var q := [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				var g: Vector2 = q[k]
				st.set_normal(Vector3(0, 0, 1))
				st.set_uv(Vector2(g.x / nx, 1.0 - g.y / ny))
				st.add_vertex(Vector3(g.x / nx * 1.5, g.y / ny * 1.0, 0.0))
	return st.commit()
