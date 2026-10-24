class_name WildlifeBuilder
extends RefCounted
## Puts the Wildlife kit (scripts/world/wildlife.gd) on every track (circuit
## EXTRA_BUILDERS entry, last, so the crowds and set pieces are already there):
##   forests  deer at the edges (bolt from cars), buzzards circling high, rooks
##   farmland fenced paddocks with cows / sheep / horses, a farm dog that races
##            cars along the fence, crows on the rails
##   coast    gulls wheeling over the water and standing by the road
##   towns    pigeons on the pavements, cats on doorsteps and walls
##   crowds   dogs on leads beside spectators
##   verges   crows / pigeons that scatter when a car comes past
## Weather: storms halve everything and ground the soaring birds, snow leaves
## only crows and deer, night only an owl calling.
## Optional circuit metas other builders may set: "perch_spots",
## "cat_spots" (Array[Transform3D]), "pasture_zones" (Array[Rect2], XZ).

const FOREST := ["kiefernring", "hochwald", "herbstwald", "schneekopf", "alpenpass"]
const FARM := ["valle_club", "brackenmoor", "valtellina", "hochwald", "herbstwald"]
const COAST := ["kuestenstrasse", "capo_rosso"]
const TOWN := ["altstadt", "capo_rosso"]

var parent: Node3D
var w: Wildlife
var curve: Curve3D
var width := 12.0
var terrain: Terrain
var zones := {}
var rng := RandomNumberGenerator.new()
var length := 0.0
var _road := {} ## 16 m cell -> road points
var sea_level := -1e9
var amount := 1.0 ## weather scale on counts
var id := ""
var theme := ""
var fence_xfs: Array[Transform3D] = []


static func build(p_parent: Node3D, p_curve: Curve3D, p_width: float, preset: Dictionary) -> void:
	if OS.get_cmdline_user_args().has("--no-wildlife"):
		return
	var b := WildlifeBuilder.new()
	b.parent = p_parent
	b.curve = p_curve
	b.width = p_width
	b._run(preset)


func _run(preset: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var def: Dictionary = parent.get("def") if parent.get("def") is Dictionary else {}
	id = def.get("id", "")
	theme = def.get("theme", "")
	rng.seed = hash(id + "wildlife")
	terrain = parent.get_meta("terrain", null)
	zones = Vegetation.zone_grid(parent.get_meta("no_trees", []), 10.0)
	length = curve.get_baked_length()
	var off := 0.0
	while off < length:
		var p := curve.sample_baked(off)
		var k := Vector2i(floori(p.x / 16.0), floori(p.z / 16.0))
		if not _road.has(k):
			_road[k] = []
		_road[k].append(p)
		off += 4.0
	var coast: Dictionary = parent.get_meta("coast", {})
	sea_level = float(coast.get("sea_level", -1e9))
	w = Wildlife.of(parent)
	var night := float(preset.get("night", 0.0)) > 0.0
	var snow := float(preset.get("snow", 0.0)) > 0.3
	var storm := not snow and float(preset.get("wet", 0.0)) > 0.6
	if night:
		w.owl_calls()
		w.finish()
		return
	amount = 0.5 if storm else 1.0
	var dbg := OS.get_cmdline_user_args().has("--debug-wildlife")
	if dbg:
		print("wildlife prep %d ms" % (Time.get_ticks_msec() - t0))
	if FOREST.has(id) or snow:
		_deer(7)
	if not snow:
		if FARM.has(id) or (theme == "" and not FOREST.has(id)):
			_paddocks(3 if FARM.has(id) else 2)
		_dogs()
		if COAST.has(id) or theme == "coast" or theme == "mediterranean":
			_gulls(coast)
		if TOWN.has(id) or theme == "town" or theme == "mediterranean":
			_town()
	if not snow and parent.has_meta("alm_zones"): # alpine pastures (theme_alpine.gd): cows with bells
		_alm(parent.get_meta("alm_zones"))
	if not snow:
		# GxFarm (gimmicks) leaves a spot inside its gate for a farm dog.
		for n in parent.get_children():
			if n.name.begins_with("GxFarm") and n.has_meta("dog_spot"):
				var dp: Vector3 = n.get_meta("dog_spot")
				var fwd := -(n as Node3D).global_basis.z if n is Node3D else Vector3.FORWARD
				w.add("dog_shepherd" if rng.randf() < 0.5 else "dog_lab", _yaw_xf(_ground(dp), fwd))
	if id == "herbstwald": # sawmill ridge and bridge parapets (autumn agent's set pieces)
		for k in 4:
			w.perch("crow", _yaw_xf(Vector3(790.0 + k * 1.3, 22.0, 183.0), _rand_dir()))
			w.perch("crow", _yaw_xf(Vector3(884.0 + k * 1.6, 12.5, 82.0), _rand_dir()))
	# Crows everywhere (also in snow): flocks of rooks over the fields, birds on the verges.
	_verge_birds("pigeon" if theme == "town" else "crow", 6)
	if not storm:
		for k in 2:
			_sky_flock("rook", rng.randi_range(6, 10), 26.0, 45.0)
		if not snow and not COAST.has(id):
			for k in 2:
				_sky_flock("raptor", 1, 70.0, 55.0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wildlife-test="):
			_lineup(a.get_slice("=", 1))
	if dbg:
		print("wildlife placement %d ms" % (Time.get_ticks_msec() - t0))
	w.finish()
	if dbg:
		print("wildlife[%s]: %d instances in %d multimeshes, %d ms" % [id, w.stats.instances, w.stats.multimeshes, Time.get_ticks_msec() - t0])


# --- Helpers -----------------------------------------------------------------

func _n(base: int) -> int:
	return maxi(int(round(base * amount)), 0 if base == 0 else 1)


func _ground(p: Vector3) -> Vector3:
	p.y = terrain.height_at(p.x, p.z) if terrain else p.y
	return p


## Distance (m) to the nearest road centre point (capped at 48).
func road_dist(p: Vector3) -> float:
	var best := 48.0
	var cx := floori(p.x / 16.0)
	var cz := floori(p.z / 16.0)
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var lst = _road.get(Vector2i(cx + dx, cz + dz))
			if lst == null:
				continue
			for q: Vector3 in lst:
				best = minf(best, Vector2(p.x - q.x, p.z - q.z).length())
	return best


func _free(p: Vector3, min_road: float) -> bool:
	if Vegetation.in_zone(zones, p, 10.0):
		return false
	if road_dist(p) < min_road:
		return false
	if p.y < sea_level + 0.8:
		return false
	return true


## [centre, tangent, right] at curve offset `o`.
func _frame(o: float) -> Array:
	o = fposmod(o, length)
	var c := curve.sample_baked(o)
	var t := (curve.sample_baked(fposmod(o + 2.0, length)) - curve.sample_baked(fposmod(o - 2.0, length)))
	t.y = 0.0
	t = t.normalized()
	return [c, t, t.cross(Vector3.UP).normalized()]


func _yaw_xf(p: Vector3, fwd: Vector3, s := 1.0) -> Transform3D:
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP).scaled(Vector3(s, s, s)), p)


func _rand_dir() -> Vector3:
	var a := rng.randf() * TAU
	return Vector3(cos(a), 0, sin(a))


# --- Placement ---------------------------------------------------------------

## Deer at the forest edge, in small groups, bolting away from the road.
func _deer(groups: int) -> void:
	var placed := 0
	var tries := 0
	while placed < _n(groups) and tries < groups * 12:
		tries += 1
		var f := _frame(rng.randf() * length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var c: Vector3 = f[0] + f[2] * side * rng.randf_range(24.0, 31.0)
		c = _ground(c)
		if not _free(c, 21.0):
			continue
		placed += 1
		for k in rng.randi_range(1, 3):
			var p := _ground(c + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)))
			var face := (f[1] as Vector3) * (1.0 if rng.randf() < 0.5 else -1.0) + _rand_dir() * 0.8
			w.add_reactive("deer", _yaw_xf(p, face, rng.randf_range(0.85, 1.05)), (f[2] as Vector3) * side)


## Fenced fields with livestock, a farm dog along the road-side fence.
func _paddocks(count: int) -> void:
	var placed := 0
	var tries := 0
	var spots: Array = parent.get_meta("pasture_zones", [])
	while placed < count and tries < count * 20:
		tries += 1
		var f := _frame(rng.randf() * length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var t: Vector3 = f[1]
		var r: Vector3 = f[2] * side
		var near := rng.randf_range(20.0, 30.0) # road-side fence
		var depth := rng.randf_range(26.0, 40.0)
		var span := rng.randf_range(34.0, 52.0)
		var o: Vector3 = f[0] + r * near
		var ok := true
		var corners := []
		for u in [-0.5, 0.0, 0.5]:
			for v in [0.0, 0.5, 1.0]:
				var q := _ground(o + t * span * u + r * depth * v)
				corners.append(q)
				if not _free(q, near - 4.0) or (terrain and absf(q.y - _ground(o).y) > 6.0):
					ok = false
		if not ok:
			continue
		placed += 1
		_fence(o, t, r, span, depth)
		# Livestock: one kind per field.
		var roll := rng.randf()
		var sp := "sheep" if roll < 0.4 else ("horse" if roll < 0.55 else ("cow_holstein" if roll < 0.8 else "cow_red"))
		var n := {"sheep": 12, "horse": 3, "cow_holstein": 8, "cow_red": 8}[sp] as int
		n = _n(n)
		var herd := Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(0.35, 0.65))
		for k in n:
			var uv := herd + Vector2(rng.randfn(0.0, 0.18), rng.randfn(0.0, 0.18))
			uv = Vector2(clampf(uv.x, -0.44, 0.44), clampf(uv.y, 0.1, 0.92))
			var p := _ground(o + t * span * uv.x + r * depth * uv.y)
			var face := _rand_dir() + t * rng.randf_range(-0.6, 0.6)
			var tint := Color.WHITE.lerp(Color(0.85, 0.82, 0.78), rng.randf())
			w.add(sp, _yaw_xf(p, face, rng.randf_range(0.9, 1.08)), tint)
		# Crows on the top rail and the farm dog.
		for k in rng.randi_range(2, 4):
			var u := rng.randf_range(-0.45, 0.45)
			var p := _ground(o + t * span * u)
			p.y += 1.16
			w.perch("crow", _yaw_xf(p, t * (1.0 if rng.randf() < 0.5 else -1.0) + _rand_dir() * 0.3))
		if rng.randf() < 0.8:
			var p := _ground(o + r * 1.3 + t * span * rng.randf_range(-0.3, 0.3))
			w.chase_dog("dog_shepherd", _yaw_xf(p, -r + t * 0.3), t)
	_flush_fences()


## Post-and-rail timber fence round a field (road side open at a gate).
func _fence(o: Vector3, t: Vector3, r: Vector3, span: float, depth: float) -> void:
	var a := o - t * span * 0.5
	var pts := [a, a + t * span, a + t * span + r * depth, a + r * depth, a]
	for e in 4:
		var p0: Vector3 = pts[e]
		var p1: Vector3 = pts[e + 1]
		var seg := p1 - p0
		seg.y = 0.0
		var n := maxi(int(seg.length() / 2.6), 1)
		for k in n + 1:
			var p := _ground(p0 + seg * (float(k) / n))
			# Posts: 0.12 square, 1.3 high, slightly askew.
			var b := Basis(Vector3.UP, rng.randf() * 0.3).rotated(_rand_dir(), rng.randf_range(0.0, 0.04))
			fence_xfs.append(Transform3D(b.scaled_local(Vector3(0.12, 1.3, 0.12)), p + Vector3(0, 0.6, 0)))
			if k < n:
				var q := _ground(p0 + seg * (float(k + 1) / n))
				var mid := (p + q) * 0.5
				var dir := q - p
				var rb := Basis.looking_at(dir.normalized(), Vector3.UP)
				for hgt in [0.55, 1.08]:
					fence_xfs.append(Transform3D(rb.scaled_local(Vector3(0.05, 0.11, dir.length() + 0.1)), mid + Vector3(0, hgt, 0)))


func _flush_fences() -> void:
	if fence_xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = fence_xfs.size()
	var box := AABB(fence_xfs[0].origin, Vector3.ZERO)
	for i in fence_xfs.size():
		mm.set_instance_transform(i, fence_xfs[i])
		box = box.expand(fence_xfs[i].origin)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PaddockFences"
	mmi.multimesh = mm
	mmi.material_override = Mats.mat("wood", Color(0.62, 0.58, 0.52))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = box.grow(2.0)
	mmi.visibility_range_end = 450.0
	w.add_child(mmi)
	fence_xfs.clear()


## Dogs on leads next to some of the spectators.
func _dogs() -> void:
	var people: Array = [] # [pos, facing]
	for n in parent.find_children("*", "Node3D", true, false):
		if not (n is PeopleKit.Crowd) or not (n.name in ["Spectators", "Fans", "Bystanders"]):
			continue
		for key: String in n._far:
			for ch: Array in n._far[key].chunks:
				var d: PackedFloat32Array = ch[1]
				for k in range(0, d.size(), 20):
					people.append([Vector3(d[k + 3], d[k + 7], d[k + 11]), Vector3(d[k + 2], d[k + 6], d[k + 10])])
	if people.is_empty():
		return
	var grid := {}
	for pp: Array in people:
		var q: Vector3 = pp[0]
		var gk := Vector2i(floori(q.x / 4.0), floori(q.z / 4.0))
		if not grid.has(gk):
			grid[gk] = []
		grid[gk].append(q)
	var want := mini(_n(maxi(people.size() / 22, 3)), 16)
	var leads: Array[Transform3D] = []
	var used := {}
	var placed_dogs := 0
	var tries := 0
	var kinds := ["dog_lab", "dog_shepherd", "dog_lab"]
	while placed_dogs < want and tries < want * 12:
		tries += 1
		var i := rng.randi() % people.size()
		if used.has(i):
			continue
		used[i] = true
		var pos: Vector3 = people[i][0]
		var back: Vector3 = people[i][1] # basis z = behind the figure
		back.y = 0.0
		back = back.normalized()
		var fwd := -back
		var right := fwd.cross(Vector3.UP).normalized()
		var sp: String = kinds[rng.randi() % kinds.size()]
		var p := _ground(pos + right * rng.randf_range(0.6, 0.85) + fwd * rng.randf_range(0.2, 0.6))
		# Room for the dog: nobody else standing there.
		var crowded := false
		for q: Vector3 in grid.get(Vector2i(floori(p.x / 4.0), floori(p.z / 4.0)), []) + grid.get(Vector2i(floori(p.x / 4.0) + 1, floori(p.z / 4.0)), []) + grid.get(Vector2i(floori(p.x / 4.0) - 1, floori(p.z / 4.0)), []) + grid.get(Vector2i(floori(p.x / 4.0), floori(p.z / 4.0) + 1), []) + grid.get(Vector2i(floori(p.x / 4.0), floori(p.z / 4.0) - 1), []):
			if q != pos and Vector2(q.x - p.x, q.z - p.z).length() < 0.95:
				crowded = true
				break
		if crowded:
			continue
		var face := (fwd + right * rng.randf_range(-0.6, 0.9)).normalized()
		w.add(sp, _yaw_xf(p, face))
		placed_dogs += 1
		# Lead: from the hand (right side, waist high) to the collar.
		var hand := pos + right * 0.28 + Vector3(0, 0.82, 0) + fwd * 0.1
		var collar := p + face * 0.32 + Vector3(0, 0.46, 0)
		var sag := (hand + collar) * 0.5 - Vector3(0, 0.12, 0)
		for seg in [[hand, sag], [sag, collar]]:
			var a: Vector3 = seg[0]
			var b: Vector3 = seg[1]
			var dir := b - a
			var bas := Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT)
			leads.append(Transform3D(bas.scaled_local(Vector3(0.012, 0.012, dir.length())), (a + b) * 0.5))
	if leads.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = leads.size()
	for i in leads.size():
		mm.set_instance_transform(i, leads[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "DogLeads"
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.07, 0.06)
	mat.roughness = 0.7
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 60.0 + mm.get_aabb().size.length() * 0.5 # to the AABB centre
	mmi.visibility_range_end_margin = 15.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # thin leads dissolve, no pop
	w.add_child(mmi)


## Gulls wheeling over the water by the road and standing on the verge.
func _gulls(coast: Dictionary) -> void:
	var sea: Vector3 = coast.get("sea", Vector3.ZERO)
	var groups := _n(6)
	for g in groups:
		var f := _frame(length * (g + rng.randf() * 0.6) / groups)
		var r: Vector3 = f[2]
		var to_sea := 1.0
		if sea != Vector3.ZERO:
			var probe: Vector3 = sea - f[0]
			to_sea = 1.0 if probe.dot(r) > 0.0 else -1.0
		var c: Vector3 = f[0] + r * to_sea * rng.randf_range(25.0, 70.0)
		c.y = maxf(sea_level, f[0].y) + rng.randf_range(12.0, 30.0)
		for k in rng.randi_range(3, 6):
			w.soar("gull", c + Vector3(rng.randf_range(-12, 12), rng.randf_range(-4, 4), rng.randf_range(-12, 12)),
				rng.randf_range(14.0, 30.0), rng.randf_range(0.18, 0.32) * (1.0 if rng.randf() < 0.6 else -1.0))
	_verge_birds("gull", _n(5))


## Town: pigeons in the square and on pavements, cats on doorsteps / walls.
func _town() -> void:
	var sq: Array = parent.get_meta("town_square", [])
	if sq.size() == 2:
		var c: Vector3 = sq[0] + (sq[1] as Vector3).normalized() * 9.0
		for k in _n(14):
			var p := _ground(c + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6)))
			if road_dist(p) > 7.5:
				w.perch("pigeon", _yaw_xf(p, _rand_dir()))
	var cat_spots: Array = parent.get_meta("cat_spots", [])
	var cats := ["cat_ginger"]
	if not cat_spots.is_empty():
		for xf: Transform3D in cat_spots:
			if rng.randf() < 0.6:
				w.add(cats[rng.randi() % cats.size()], xf)
		return
	# No spots given: doorsteps along the street fronts.
	var n := _n(8)
	var tries := 0
	var placed := 0
	while placed < n and tries < n * 10:
		tries += 1
		var f := _frame(rng.randf() * length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var p := _ground(f[0] + (f[2] as Vector3) * side * rng.randf_range(11.0, 12.8))
		if road_dist(p) < 10.5 or p.y < sea_level + 0.8:
			continue
		placed += 1
		var face: Vector3 = -(f[2] as Vector3) * side + (f[1] as Vector3) * rng.randf_range(-0.8, 0.8)
		w.add(cats[rng.randi() % cats.size()], _yaw_xf(p, face, rng.randf_range(0.9, 1.05)))


## Small groups on the verges / perch spots that take off as cars come past.
func _verge_birds(sp: String, groups: int) -> void:
	var spots: Array = parent.get_meta("perch_spots", [])
	for xf: Transform3D in spots:
		if rng.randf() < 0.5 * amount:
			w.perch("pigeon" if theme == "mediterranean" and rng.randf() < 0.6 else (sp if sp != "gull" else "crow"), xf)
	var g := 0
	var tries := 0
	while g < _n(groups) and tries < groups * 10:
		tries += 1
		var f := _frame(rng.randf() * length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var c := _ground(f[0] + (f[2] as Vector3) * side * rng.randf_range(10.0, 15.0))
		if not _free(c, 9.0):
			continue
		g += 1
		for k in rng.randi_range(2, 6):
			var p := _ground(c + Vector3(rng.randf_range(-2.5, 2.5), 0, rng.randf_range(-2.5, 2.5)))
			if road_dist(p) > 8.5:
				w.perch(sp, _yaw_xf(p, _rand_dir(), rng.randf_range(0.9, 1.1)))


## Birds circling over a random stretch of the course.
func _sky_flock(plumage: String, n: int, height: float, radius: float) -> void:
	var f := _frame(rng.randf() * length)
	var c: Vector3 = f[0] + (f[2] as Vector3) * rng.randf_range(-60.0, 60.0)
	c.y = maxf(c.y, sea_level) + height + rng.randf_range(0.0, 20.0)
	w.flock(plumage, c, n, radius, rng.randf_range(0.12, 0.22) * (1.0 if rng.randf() < 0.5 else -1.0))


## Debug: every species in a row along +X from x,y,z (facing +Z, towards a
## camera in front), birds circling above. --wildlife-test=x,y,z
func _lineup(arg: String) -> void:
	if arg == "start":
		# Reactive animals just past the start line: crows on the verge, a deer, a farm dog.
		for k in 4:
			var f := _frame(60.0 + k * 40.0)
			var r: Vector3 = f[2]
			for j in 4:
				w.perch("crow", _yaw_xf(_ground(f[0] + r * (9.0 + j * 0.8)), _rand_dir()))
			print("wildlife test spot %d: road %s right %s fwd %s" % [k, f[0], r, f[1]])
			w.add_reactive("deer", _yaw_xf(_ground(f[0] - r * 26.0), f[1]), -r)
			w.chase_dog("dog_shepherd", _yaw_xf(_ground(f[0] - r * 14.0), -r), f[1])
		return
	var v := arg.split_floats(",")
	var p := Vector3(v[0], v[1], v[2])
	var x := 0.0
	for sp: String in Wildlife.SPECIES:
		var big: bool = Wildlife.SPECIES[sp].kind == Wildlife.Kind.GRAZER
		x += 2.6 if big else 1.0
		w.add(sp, _yaw_xf(_ground(p + Vector3(x, 0, 0)), Vector3(0.6, 0, 1)))
		x += 2.6 if big else 1.0
	for pl: String in ["gull", "rook", "raptor"]:
		w.flock(pl, p + Vector3(x * 0.5, 9.0 + randf() * 4.0, -6.0), 3, 7.0, 0.5)


## Alpine pastures ([centre, radius] from theme_alpine.gd): brown cows grazing
## with a looping, positional clank of cowbells per herd.
func _alm(zones_alm: Array) -> void:
	var bells := _cowbells()
	for z: Array in zones_alm:
		var c: Vector3 = z[0]
		var rad: float = z[1]
		var n := _n(rng.randi_range(5, 8))
		for k in n:
			var p := _ground(c + _rand_dir() * rng.randf_range(0.0, rad * 0.8))
			var tint := Color.WHITE.lerp(Color(0.8, 0.72, 0.62), rng.randf())
			w.add("cow_red" if rng.randf() < 0.8 else "cow_holstein", _yaw_xf(p, _rand_dir(), rng.randf_range(0.92, 1.06)), tint)
		var snd := AudioStreamPlayer3D.new()
		snd.name = "Cowbells"
		snd.stream = bells
		snd.position = c + Vector3.UP * 1.0
		snd.unit_size = 9.0
		snd.max_distance = 140.0
		snd.volume_db = -4.0
		snd.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
		snd.autoplay = true
		parent.add_child(snd)


## A 9 s loop of three cowbells (inharmonic metal partials, quick clank attack),
## each rung irregularly as the cow grazes. Synthesised: no samples needed.
static func _cowbells() -> AudioStreamWAV:
	var rate := 22050
	var total := 9.0
	var n := int(total * rate)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var r := RandomNumberGenerator.new()
	r.seed = 4711
	for bell in 3:
		var f0 := [520.0, 610.0, 455.0][bell] as float
		var parts := [[1.0, 1.0], [2.31, 0.55], [3.83, 0.35], [5.2, 0.22], [6.9, 0.12]]
		var dur := int(0.55 * rate)
		var ring := PackedFloat32Array() # one strike, mixed in many times
		ring.resize(dur)
		for i in dur:
			var tt := float(i) / rate
			var s := 0.0
			for pt: Array in parts:
				var pf: float = pt[0]
				s += sin(TAU * f0 * pf * tt) * float(pt[1]) * exp(-tt * (7.0 + pf * 3.0))
			ring[i] = s + (r.randf() - 0.5) * exp(-tt * 90.0) * 0.6 # + the clapper's clank
		var t := r.randf_range(0.0, 0.8)
		while t < total - 0.6:
			var amp := r.randf_range(0.25, 0.6)
			var start := int(t * rate)
			for i in mini(dur, n - start):
				buf[start + i] += ring[i] * amp
			# Grazing: a few rings close together, then a pause.
			t += r.randf_range(0.18, 0.4) if r.randf() < 0.6 else r.randf_range(0.9, 2.2)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * 0.3, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav
