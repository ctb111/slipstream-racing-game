class_name AutumnTheme
extends RefCounted
## "autumn" theme (Herbstwald): built by TrackThemes with its batching helpers.
##  - the river (water ribbon) and the old stone arch bridge the road crosses;
##  - the rock cut with a stone-portalled tunnel through the ridge;
##  - a timber sawmill hall the road runs straight through, log yard, wood piles;
##  - the forest village with its church by the start straight;
##  - a hunting lodge on the crest above the valley;
##  - spectator camps (tents, campfires, fans) at the crests, hairpin and bridge;
##  - drifts of fallen leaves on the verges, autumn-tinted ground.

const LEAF_COLS := [Color(0.62, 0.3, 0.06), Color(0.75, 0.42, 0.08), Color(0.5, 0.16, 0.05), Color(0.42, 0.26, 0.1),
	Color(0.7, 0.55, 0.15), Color(0.33, 0.2, 0.09)]
const TIMBER := Color(0.42, 0.3, 0.2)
const DARK_TIMBER := Color(0.25, 0.17, 0.11)
const STONE := Color(0.78, 0.74, 0.68)
const TENTS := [Color(0.16, 0.3, 0.18), Color(0.62, 0.12, 0.08), Color(0.12, 0.2, 0.42), Color(0.75, 0.6, 0.2),
	Color(0.35, 0.36, 0.3), Color(0.85, 0.42, 0.08)]

var t: TrackThemes
var body: StaticBody3D ## colliders for walls, deck and parapets
var fires: Array[Vector3] = []


static func build(themes: TrackThemes) -> void:
	var a := AutumnTheme.new()
	a.t = themes
	a._run()


func _run() -> void:
	body = StaticBody3D.new()
	body.name = "AutumnColliders"
	t.parent.add_child(body)
	t.mats.wood = Mats.mat("wood")
	t.mats.canvas = Mats.mat("canvas")
	t.mats.slate = Mats.mat("slate")
	t.mats.cutrock = t.mats.rock # same look, no shadows (big faces; costly in the shadow pass)
	t.vis.wood = 500.0
	t.vis.canvas = 350.0
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.55, 0.15)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.45, 0.1)
	fire.emission_energy_multiplier = 3.0
	t.mats.fire = fire
	t.vis.fire = 400.0
	_ground_tint()
	_river_and_bridge()
	_rock_cut_and_tunnel()
	_sawmill()
	_village()
	_lodge()
	_camps()
	_wood_piles()
	_leaf_drifts()
	FallingLeaves.attach(t.parent, float(t.preset.get("snow", 0.0)) > 0.0)


func _idx(p: Vector2) -> int:
	return t._nearest(Vector3(p.x, 0, p.y), 200.0)


func _col_box(c: Vector3, basis: Basis, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)


## Olive-brown autumn ground (the terrain material is shared by the far hills).
func _ground_tint() -> void:
	var tn: Node = t.parent.get_node_or_null("Terrain")
	if tn == null:
		return
	for ch in tn.get_children():
		if ch is MeshInstance3D:
			var m := (ch as MeshInstance3D).material_override as ShaderMaterial
			if m and float(t.preset.get("snow", 0.0)) <= 0.0:
				m.set_shader_parameter("tint", Vector3(0.74, 0.8, 0.46))
			break


# ================================================================ river + bridge

func _river_and_bridge() -> void:
	var rs := AutumnTerrain.river_samples(t.def)
	if rs.size() < 2:
		return
	# Water ribbon, a little wider than the channel at water level.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 8.2
	for i in rs.size() - 1:
		var a := rs[i]
		var b := rs[i + 1]
		var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		var r := d.cross(Vector3.UP)
		var d2 := (rs[mini(i + 2, rs.size() - 1)] - a)
		var r2 := Vector3(d2.x, 0, d2.z).normalized().cross(Vector3.UP)
		var q := [a - r * hw, a + r * hw, b + r2 * hw, b - r2 * hw]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q[k].x, q[k].z) * 0.05)
			st.add_vertex(q[k])
		t.no_trees.append([a, 22.0])
	var mi := MeshInstance3D.new()
	mi.name = "River"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	for key in ["ripple_a", "ripple_b"]:
		var nt := NoiseTexture2D.new()
		var nz := FastNoiseLite.new()
		nz.seed = t.rng.randi()
		nz.frequency = 0.05
		nt.noise = nz
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		nt.generate_mipmaps = true
		mat.set_shader_parameter(key, nt)
	mat.set_shader_parameter("choppiness", 0.8)
	mat.set_shader_parameter("deep", Vector3(0.05, 0.07, 0.05))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.parent.add_child(mi)
	# River-bed boulders.
	for i in range(0, rs.size(), 5):
		var s := rs[i]
		var d := (rs[mini(i + 1, rs.size() - 1)] - rs[maxi(i - 1, 0)]).normalized()
		var r := d.cross(Vector3.UP).normalized()
		for k in 2:
			var p := s + r * t.rng.randf_range(-8.5, 8.5) + d * t.rng.randf_range(-6, 6)
			if t._tdist(p, 30.0) < 26.0:
				continue
			p.y = t._ground(p) - 0.2
			var sz := t.rng.randf_range(0.6, 1.6)
			t._box("rock", p + Vector3.UP * sz * 0.3, r, Vector3.UP, d, Vector3(sz * 1.3, sz, sz), Color(0.7, 0.68, 0.64))

	# The bridge: where the river passes closest to the road.
	var best := INF
	var bi := 0
	var rp := Vector3.ZERO
	for s in rs:
		var i := t._nearest(s, 40.0)
		if i < 0:
			continue
		var dd := Vector2(t.centers[i].x - s.x, t.centers[i].z - s.z).length()
		if dd < best:
			best = dd
			bi = i
			rp = s
	if best > 30.0:
		return
	_bridge(bi, rp)


## Single-span stone arch bridge: deck slabs either side of the tarmac out to
## parapet walls, spandrel walls down to the banks with the arch over the water.
func _bridge(bi: int, river_pt: Vector3) -> void:
	var span := 14 # samples either side (2 m each)
	var lat0 := t.half + 0.2
	var lat1 := t.half + 7.4 # beyond the guardrail line
	var arch_half := 10.0
	var water := river_pt.y
	var col := STONE
	for k in range(-span, span):
		var i0 := t._i(bi + k)
		var i1 := t._i(bi + k + 1)
		var u0 := k * TrackThemes.STEP
		var u1 := (k + 1) * TrackThemes.STEP
		for side: float in [-1.0, 1.0]:
			var c0 := t.centers[i0]
			var c1 := t.centers[i1]
			var r0 := t.rights[i0] * side
			var r1 := t.rights[i1] * side
			var y0 := c0.y - 0.07
			var y1 := c1.y - 0.07
			# Deck slab.
			var a := c0 + r0 * lat0
			var b := c1 + r1 * lat0
			var c := c1 + r1 * lat1
			var d := c0 + r0 * lat1
			a.y = y0; d.y = y0; b.y = y1; c.y = y1
			t._quad("stone", a, b, c, d, Color(0.62, 0.6, 0.56), Vector3.UP)
			# Parapet: 0.55 thick, 0.95 high.
			var pa := c0 + r0 * (lat1 - 0.55)
			var pb := c1 + r1 * (lat1 - 0.55)
			pa.y = y0; pb.y = y1
			var ph := Vector3.UP * 0.95
			t._quad("stone", pa, pb, pb + ph, pa + ph, col, -r0)
			t._quad("stone", pa + ph, pb + ph, c + ph, d + ph, col, Vector3.UP)
			# Spandrel wall on the outside, down to the arch or the bank.
			var g0 := _arch_y(u0, arch_half, water, t._ground(d) - 0.5)
			var g1 := _arch_y(u1, arch_half, water, t._ground(c) - 0.5)
			var top0 := d + ph
			var top1 := c + ph
			t._quad("stone", Vector3(d.x, g0, d.z), Vector3(c.x, g1, c.z), top1, top0, col, r0)
			# Arch soffit (only over the opening).
			if absf(u0) < arch_half or absf(u1) < arch_half:
				t._quad("stone", Vector3(c0.x, g0, c0.z), Vector3(c1.x, g1, c1.z), Vector3(c.x, g1, c.z), Vector3(d.x, g0, d.z), col * 0.8, Vector3.DOWN)
			# Colliders: deck under the verge, parapet.
			var mid := (a + c) * 0.5
			var fwd := (c1 - c0).normalized()
			var bas := Basis.looking_at(fwd, Vector3.UP)
			_col_box(mid - Vector3.UP * 0.4, bas, Vector3(lat1 - lat0, 0.8, 2.2))
			_col_box((pa + pb) * 0.5 + r0 * 0.27 + Vector3.UP * 0.6, bas, Vector3(0.6, 1.2, 2.2))
	# Grey stone edge under the tarmac too (seen from the river).
	t.no_trees.append([t.centers[bi], 40.0])
	# Fans on the river bank below the bridge, looking up.
	for side: float in [-1.0, 1.0]:
		for n in 8:
			var along := t.rng.randf_range(-12.0, 12.0)
			var dir := t.tangents[bi] * along
			var p := t.centers[bi] + dir + t.rights[bi] * side * t.rng.randf_range(16.0, 24.0)
			p.y = t._ground(p)
			if p.y < water + 0.5:
				continue
			_fan(p, t.centers[bi])


func _arch_y(u: float, arch_half: float, water: float, ground: float) -> float:
	if absf(u) < arch_half:
		return maxf(water + 0.5 + 3.9 * sqrt(1.0 - pow(u / arch_half, 2.0)), ground)
	return ground


# ================================================================ rock cut + tunnel

func _rock_cut_and_tunnel() -> void:
	var cut: Array = t.def.get("cut", [])
	if cut.size() < 2:
		return
	var i0 := _idx(cut[0])
	var i1 := _idx(cut[1])
	var count := posmod(i1 - i0, t.n)
	# Rock faces draped over the steep walls.
	for k in count:
		var i := t._i(i0 + k)
		var j := t._i(i0 + k + 1)
		for side: float in [-1.0, 1.0]:
			var prev_a := Vector3.ZERO
			var prev_b := Vector3.ZERO
			for m in 9:
				var lat := 13.2 + m * 2.5
				var a := t.centers[i] + t.rights[i] * side * lat
				var b := t.centers[j] + t.rights[j] * side * lat
				a = t._on_ground(a, 0.12)
				b = t._on_ground(b, 0.12)
				if m > 0 and (a.y - t.centers[i].y > 0.6 or prev_a.y - t.centers[i].y > 0.6):
					t._quad("cutrock", prev_a, prev_b, b, a, Color(0.6, 0.6, 0.6), -t.rights[i] * side + Vector3.UP * 0.3)
				prev_a = a
				prev_b = b
	# Tunnel through the ridge.
	var tun: Array = t.def.get("tunnel", [])
	if tun.size() < 2:
		return
	var a0 := _idx(tun[0])
	var a1 := _idx(tun[1])
	var tc := posmod(a1 - a0, t.n)
	var wall := t.half + 7.0 # inner wall line, outside the rails
	var clear := 7.2 # headroom at the walls
	var crown := 9.5 # headroom at the centre
	var stone := Color(0.7, 0.67, 0.62)
	for k in tc:
		var i := t._i(a0 + k)
		var j := t._i(a0 + k + 1)
		var ci := t.centers[i]
		var cj := t.centers[j]
		var ri := t.rights[i]
		var rj := t.rights[j]
		# Arch profile: wall up, then a segmental vault; 8 facets.
		var prof: Array[Vector2] = []
		for s in 9:
			var ang := PI * s / 8.0
			var x := cos(ang) * wall
			var y := clear + sin(ang) * (crown - clear)
			prof.append(Vector2(x, y))
		for s in 8:
			var p0 := prof[s]
			var p1 := prof[s + 1]
			var A := ci + ri * p0.x + Vector3.UP * p0.y
			var B := cj + rj * p0.x + Vector3.UP * p0.y
			var C := cj + rj * p1.x + Vector3.UP * p1.y
			var D := ci + ri * p1.x + Vector3.UP * p1.y
			var inward := -(ri * (p0.x + p1.x) * 0.5 + Vector3.UP * ((p0.y + p1.y) * 0.5 - 3.0))
			t._quad("stone", A, B, C, D, stone * 0.75, inward)
		for side: float in [-1.0, 1.0]:
			var lo := ci + ri * side * wall
			var lo2 := cj + rj * side * wall
			t._quad("stone", lo - Vector3.UP * 0.3, lo2 - Vector3.UP * 0.3, lo2 + Vector3.UP * clear, lo + Vector3.UP * clear,
				stone * 0.7, -ri * side)
			# Earth and rock over the vault, out to the cut walls.
			var fill := clampf(t._ground(ci + ri * side * (wall + 12.0)) - ci.y, crown + 4.0, crown + 22.0)
			var top_i := ci + ri * side * (wall + 12.0) + Vector3.UP * fill
			var top_j := cj + rj * side * (wall + 12.0) + Vector3.UP * fill
			var mid_i := ci + Vector3.UP * (fill - 1.0)
			var mid_j := cj + Vector3.UP * (fill - 1.0)
			t._quad("rock", mid_i, mid_j, top_j, top_i, Color(0.62, 0.58, 0.5), Vector3.UP)
			# Wall colliders.
			var fwd := (cj - ci).normalized()
			_col_box((lo + lo2) * 0.5 + ri * side * 0.5 + Vector3.UP * 3.0, Basis.looking_at(fwd, Vector3.UP), Vector3(1.0, 7.0, 2.3))
	# Portals: a stone face with the arch opening, into the rock.
	for e in [[a0, -1.0], [a1, 1.0]]:
		var i: int = e[0]
		var dir: float = e[1]
		var c := t.centers[i]
		var r := t.rights[i]
		var out := t.tangents[i] * dir
		var face_w := wall + 12.0
		# Up to where the cut walls are, so no sky shows over the portal.
		var top := crown + 6.0
		for side: float in [-1.0, 1.0]:
			top = maxf(top, minf(t._ground(c + r * side * face_w) - c.y, crown + 22.0))
		# Above the arch.
		for s in 8:
			var ang0 := PI * s / 8.0
			var ang1 := PI * (s + 1) / 8.0
			var x0 := cos(ang0) * wall
			var x1 := cos(ang1) * wall
			var y0 := clear + sin(ang0) * (crown - clear)
			var y1 := clear + sin(ang1) * (crown - clear)
			t._quad("stone", c + r * x0 + Vector3.UP * y0, c + r * x1 + Vector3.UP * y1, c + r * x1 + Vector3.UP * top,
				c + r * x0 + Vector3.UP * top, stone, out)
		for side: float in [-1.0, 1.0]:
			var w0 := c + r * side * wall
			var w1 := c + r * side * face_w
			t._quad("stone", w0 - Vector3.UP * 0.5, w1 - Vector3.UP * 0.5, w1 + Vector3.UP * top, w0 + Vector3.UP * top, stone, out)
		# Rough rock crown above the face, set back, so the skyline is a hill.
		var crown_pts: Array[Vector3] = []
		for s in 13:
			var x := lerpf(-face_w - 4.0, face_w + 4.0, s / 12.0)
			var hgt := top + 3.0 + t.rng.randf_range(2.0, 9.0) * (1.0 - pow(absf(x) / (face_w + 4.0), 2.0) * 0.6)
			crown_pts.append(c + r * x + Vector3.UP * hgt - out * t.rng.randf_range(4.0, 9.0))
		for s in 12:
			var a := c + r * lerpf(-face_w - 4.0, face_w + 4.0, s / 12.0) + Vector3.UP * (top - 0.5) - out * 0.4
			var b := c + r * lerpf(-face_w - 4.0, face_w + 4.0, (s + 1) / 12.0) + Vector3.UP * (top - 0.5) - out * 0.4
			t._quad("rock", a, b, crown_pts[s + 1], crown_pts[s], Color(0.55, 0.55, 0.53), out + Vector3.UP * 0.5)
			var back := (crown_pts[s] + crown_pts[s + 1]) * 0.5 - out * 25.0 - Vector3.UP * 4.0
			t._tri("rock", crown_pts[s], crown_pts[s + 1], back, Color(0.5, 0.5, 0.48), Vector3.UP - out * 0.3)
		# Keystone band and cornice.
		t._box("stone", c + Vector3.UP * (top + 0.3) + out * 0.3, r, Vector3.UP, out, Vector3(face_w * 2.0 + 0.6, 0.6, 1.2), Color(0.6, 0.57, 0.52))
		t._box("stone", c + Vector3.UP * (crown + 0.6) + out * 0.25, r, Vector3.UP, out, Vector3(1.2, 1.4, 0.8), Color(0.84, 0.8, 0.72))
	t.no_trees.append([t.centers[t._i(a0 + tc / 2)], tc + 20.0])


# ================================================================ sawmill

func _sawmill() -> void:
	# The straight after the bridge: find the straightest 50 m in that stretch.
	var i0 := _idx(Vector2(835, 155))
	var i1 := _idx(Vector2(745, 212))
	if i0 < 0 or i1 < 0:
		return
	var mid := t._i(i0 + posmod(i1 - i0, t.n) / 2)
	var c := t.centers[mid]
	var fwd := t.tangents[mid]
	var r := t.rights[mid]
	var half_w := t.half + 7.5
	var length := 34.0
	var eave := 6.0
	var y := c.y
	# Posts and wall planks; the road-facing long sides are open with a low wall.
	var posts := 7
	for side: float in [-1.0, 1.0]:
		for p in posts + 1:
			var u := -length * 0.5 + length * p / posts
			var i := t._i(mid + int(round(u / TrackThemes.STEP)))
			var base := t.centers[i] + t.rights[i] * side * half_w
			base.y = minf(t._ground(base), t.centers[i].y) - 0.5
			var top_y := y + eave
			t._box("wood", Vector3(base.x, (base.y + top_y) * 0.5, base.z), r, Vector3.UP, fwd, Vector3(0.35, top_y - base.y, 0.35), DARK_TIMBER)
			_col_box(Vector3(base.x, base.y + 2.0, base.z), Basis.looking_at(fwd, Vector3.UP), Vector3(0.4, 4.0, 0.4))
		# Plank wall on the upper part (open below so you see out), full outer side.
		var wc := c + r * side * (half_w + 0.2)
		t._box("wood", wc + Vector3.UP * (eave - 1.4), r, Vector3.UP, fwd, Vector3(0.12, 2.6, length), TIMBER)
		t._box("wood", wc + Vector3.UP * 0.6, r, Vector3.UP, fwd, Vector3(0.12, 1.2, length), TIMBER)
	# Roof: big shallow gable across the road, shingles in slate.
	var ridge := c + Vector3.UP * (eave + 4.2)
	var hl := fwd * (length * 0.5 + 1.2)
	for side: float in [-1.0, 1.0]:
		var e := c + r * side * (half_w + 1.6) + Vector3.UP * (eave - 0.3)
		t._quad("slate", e - hl, e + hl, ridge + hl, ridge - hl, Color(0.45, 0.4, 0.36), r * side + Vector3.UP)
		t._quad("wood", e - hl - Vector3.UP * 0.15, e + hl - Vector3.UP * 0.15, ridge + hl - Vector3.UP * 0.15, ridge - hl - Vector3.UP * 0.15,
			DARK_TIMBER, -r * side - Vector3.UP)
	# Tie beams and gable boards at both ends.
	for s: float in [-1.0, 1.0]:
		var g := c + fwd * s * length * 0.5
		t._box("wood", g + Vector3.UP * eave, fwd, Vector3.UP, r, Vector3(0.3, 0.4, half_w * 2.0 + 1.0), DARK_TIMBER)
		t._tri("wood", g - r * half_w + Vector3.UP * eave, g + r * half_w + Vector3.UP * eave, g + Vector3.UP * (eave + 4.0), TIMBER, fwd * s)
		# Painted sign board over the entrance.
	t._box("wood", c - fwd * (length * 0.5 + 0.1) + Vector3.UP * (eave + 1.4), r, Vector3.UP, fwd, Vector3(9.0, 1.3, 0.15), Color(0.55, 0.12, 0.08))
	# Log yard and sawn timber beside the hall (outside, off the run-off).
	var yard := c + r * (half_w + 14.0)
	if t._off_track(yard, 2.0):
		_log_pile(yard, fwd, 14.0, 6)
		_log_pile(yard + fwd * 14.0, fwd, 10.0, 5)
		_plank_stack(yard - fwd * 12.0, fwd)
		_plank_stack(yard - fwd * 12.0 + r * 5.0, fwd)
	var yard2 := c - r * (half_w + 12.0) + fwd * 4.0
	if t._off_track(yard2, 2.0):
		_log_pile(yard2, fwd, 12.0, 5)
		_plank_stack(yard2 + fwd * 13.0, fwd)
	# Sawdust apron under the hall.
	t._drape("soil", c + r * (half_w + 8.0), r, fwd, 16.0, length + 10.0, 4.0, 0.05, Color(0.85, 0.7, 0.5))
	t.no_trees.append([c, 45.0])
	t.no_trees.append([yard, 25.0])


## Stacked logs on a slope: rows of cylinders along `fwd`.
func _log_pile(c: Vector3, fwd: Vector3, length: float, rows: int) -> void:
	var r := fwd.cross(Vector3.UP).normalized()
	c.y = t._ground(c)
	var rad := 0.32
	for row in rows:
		var count := rows - row + 2
		for k in count:
			var off := (k - (count - 1) * 0.5) * rad * 2.05
			var p := c + r * off + Vector3.UP * (rad + row * rad * 1.75)
			var col := Color(0.55, 0.42, 0.3).lerp(Color(0.4, 0.3, 0.2), t.rng.randf())
			_log(p, fwd, length * t.rng.randf_range(0.92, 1.0), rad * t.rng.randf_range(0.9, 1.1), col)
	t._box("wood", c - r * ((rows + 1) * rad * 1.1 + 0.3) + Vector3.UP * 1.0, r, Vector3.UP, fwd, Vector3(0.2, 2.0, 0.2), DARK_TIMBER)
	t._box("wood", c + r * ((rows + 1) * rad * 1.1 + 0.3) + Vector3.UP * 1.0, r, Vector3.UP, fwd, Vector3(0.2, 2.0, 0.2), DARK_TIMBER)


## A horizontal log (hexagonal prism with pale cut ends).
func _log(c: Vector3, along: Vector3, length: float, rad: float, col: Color) -> void:
	var r := along.cross(Vector3.UP).normalized()
	var u := r.cross(along).normalized()
	var segs := 6
	var h := along * length * 0.5
	for s in segs:
		var a0 := TAU * s / segs
		var a1 := TAU * (s + 1) / segs
		var d0 := r * cos(a0) + u * sin(a0)
		var d1 := r * cos(a1) + u * sin(a1)
		t._quad("wood", c - h + d0 * rad, c + h + d0 * rad, c + h + d1 * rad, c - h + d1 * rad, col, d0 + d1)
		t._tri("wood", c + h, c + h + d0 * rad, c + h + d1 * rad, Color(0.85, 0.7, 0.5), along)
		t._tri("wood", c - h, c - h + d0 * rad, c - h + d1 * rad, Color(0.85, 0.7, 0.5), -along)


func _plank_stack(c: Vector3, fwd: Vector3) -> void:
	var r := fwd.cross(Vector3.UP).normalized()
	c.y = t._ground(c)
	for layer in 6:
		t._box("wood", c + Vector3.UP * (0.2 + layer * 0.32), r, Vector3.UP, fwd, Vector3(3.2, 0.22, 6.0), Color(0.8, 0.66, 0.46))
		t._box("wood", c + Vector3.UP * (0.05 + layer * 0.32), r, Vector3.UP, fwd, Vector3(3.2, 0.1, 0.12), DARK_TIMBER)


## Firewood piles along the forest edges: split logs stacked between posts.
func _wood_piles() -> void:
	var placed := 0
	var tries := 0
	while placed < 18 and tries < 400:
		tries += 1
		var i := t.rng.randi() % t.n
		if absf(t.corner[i]) > 0.25:
			continue
		var side := -1.0 if t.rng.randf() < 0.5 else 1.0
		var lat := t.rail_dist(i, side) + t.rng.randf_range(3.0, 7.0)
		var p := t.centers[i] + t.rights[i] * side * lat
		if not t._foreign_clear(p, 4.0) or not t._off_track(p, 1.5):
			continue
		var fwd := t.tangents[i]
		var plen := t.rng.randf_range(4.0, 9.0)
		p.y = t._ground(p)
		var r := t.rights[i]
		# A stack of short split logs: a block, with the log ends (hexagons)
		# on the road-facing side only.
		var rows := t.rng.randi_range(3, 5)
		var face := -r * signf(r.dot(p - t.centers[i]))
		t._box("wood", p + Vector3.UP * (0.03 + rows * 0.17), r, Vector3.UP, fwd, Vector3(0.95, rows * 0.34, plen), Color(0.4, 0.3, 0.2))
		for row in rows:
			for k in int(plen / 0.36):
				var q := p + fwd * (-plen * 0.5 + 0.18 + k * 0.36) + Vector3.UP * (0.2 + row * 0.34) + face * 0.49
				var u := face.cross(Vector3.UP).normalized()
				var col := Color(0.86, 0.7, 0.5).lerp(Color(0.6, 0.45, 0.3), t.rng.randf())
				for sgi in 6:
					var a0 := TAU * sgi / 6.0
					var a1 := TAU * (sgi + 1) / 6.0
					t._tri("wood", q, q + (u * cos(a0) + Vector3.UP * sin(a0)) * 0.16, q + (u * cos(a1) + Vector3.UP * sin(a1)) * 0.16, col, face)
		t._box("wood", p + Vector3.UP * (0.2 + rows * 0.34 + 0.05), r, Vector3.UP, fwd, Vector3(1.3, 0.06, plen + 0.4), Color(0.3, 0.3, 0.3))
		t.no_trees.append([p, 4.0])
		placed += 1


# ================================================================ village + church

func _village() -> void:
	# Along the start straight, both sides, behind the rails.
	var i0 := _idx(Vector2(730, 214))
	var i1 := _idx(Vector2(515, 264))
	var span := posmod(i1 - i0, t.n)
	var walls := [Color(0.93, 0.9, 0.82), Color(0.9, 0.84, 0.66), Color(0.86, 0.8, 0.72), Color(0.8, 0.84, 0.76),
		Color(0.94, 0.93, 0.9), Color(0.88, 0.76, 0.66)]
	var roofs := [Color(0.55, 0.28, 0.2), Color(0.46, 0.24, 0.18), Color(0.38, 0.36, 0.36), Color(0.6, 0.34, 0.24)]
	var church_done := false
	for side: float in [-1.0, 1.0]:
		var k := 0
		while k < span:
			var i := t._i(i0 + k)
			var fwd := t.tangents[i]
			var r := t.rights[i] * side
			if not church_done and side > 0.0 and k > span * 0.45:
				var cc := t.centers[i] + r * (t.rail_dist(i, side) + 22.0)
				if t._fits(cc, fwd, r, 30.0, 16.0, 1.0):
					_church(cc, fwd, r)
					church_done = true
					k += 22
					continue
			var w := t.rng.randf_range(9.0, 13.0)
			var d := t.rng.randf_range(8.0, 11.0)
			var setback := t.rail_dist(i, side) + t.rng.randf_range(5.0, 9.0) + d * 0.5
			var hc := t.centers[i] + r * setback
			if t._fits(hc, fwd, r, w, d, 1.0) and t.rng.randf() < 0.85:
				t._mark(hc, fwd, r, w, d)
				t._house(hc, fwd, r, w, d, t.rng.randf_range(5.5, 7.5), walls[t.rng.randi() % walls.size()],
					roofs[t.rng.randi() % roofs.size()], 0, -1, true)
				t.no_trees.append([hc, maxf(w, d) * 0.7 + 3.0])
				# Firewood under the eaves, a fan or two at the fence.
				if t.rng.randf() < 0.5:
					_log_pile(hc - r * (d * 0.5 + 1.2), fwd, w * 0.6, 3)
				if t.rng.randf() < 0.6:
					var fp := t.centers[i] + r * (t.rail_dist(i, side) + 1.5)
					fp.y = t._ground(fp)
					_fan(fp, t.centers[i])
			k += int((w + t.rng.randf_range(4.0, 12.0)) / TrackThemes.STEP)


## Village church: nave with steep slate roof, west tower with an onion-less
## pointed spire, a clock face; facing the road.
func _church(c: Vector3, fwd: Vector3, out: Vector3) -> void:
	t._mark(c, fwd, out, 30.0, 16.0)
	var g := t._ground(c)
	var nave_l := 22.0
	var nave_w := 11.0
	var wall_h := 9.0
	var nc := c + fwd * 3.0
	t._house(Vector3(nc.x, g, nc.z), fwd, out, nave_l, nave_w, wall_h, Color(0.92, 0.9, 0.84), Color(0.32, 0.31, 0.32), 0, 0, true)
	# Tower at the end towards -fwd.
	var tc := c - fwd * (nave_l * 0.5 + 0.5)
	var th := 24.0
	var tw := 6.0
	t._box("plain", Vector3(tc.x, g + th * 0.5 - 1.0, tc.z), fwd, Vector3.UP, out, Vector3(tw, th + 2.0, tw), Color(0.93, 0.91, 0.86))
	t._box("stone", Vector3(tc.x, g + th - 0.2, tc.z), fwd, Vector3.UP, out, Vector3(tw + 0.5, 0.5, tw + 0.5), Color(0.7, 0.66, 0.6))
	# Spire: four-sided pyramid.
	var top := Vector3(tc.x, g + th + 14.0, tc.z)
	var corners := []
	for s in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
		corners.append(Vector3(tc.x, g + th, tc.z) + fwd * s[0] * (tw * 0.5 + 0.2) + out * s[1] * (tw * 0.5 + 0.2))
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		t._tri("roof", a, b, top, Color(0.25, 0.32, 0.3), ((a + b) * 0.5 - Vector3(tc.x, a.y, tc.z)).normalized() + Vector3.UP * 0.3)
	t._box("metal", top + Vector3.UP * 1.0, fwd, Vector3.UP, out, Vector3(0.12, 2.0, 0.12), Color(0.7, 0.6, 0.3))
	t._box("metal", top + Vector3.UP * 1.3, fwd, Vector3.UP, out, Vector3(0.9, 0.1, 0.1), Color(0.7, 0.6, 0.3))
	# Clock faces and belfry openings.
	for o: Vector3 in [-out, out, -fwd]:
		var fc := Vector3(tc.x, g + th - 4.0, tc.z) + o * (tw * 0.5 + 0.03)
		var rr := o.cross(Vector3.UP).normalized()
		t._quad("metal", fc - rr * 1.0 - Vector3.UP * 1.0, fc + rr * 1.0 - Vector3.UP * 1.0, fc + rr * 1.0 + Vector3.UP * 1.0,
			fc - rr * 1.0 + Vector3.UP * 1.0, Color(0.85, 0.82, 0.7), o)
		var bc := Vector3(tc.x, g + th - 8.0, tc.z) + o * (tw * 0.5 + 0.03)
		t._quad("metal", bc - rr * 0.7 - Vector3.UP * 1.3, bc + rr * 0.7 - Vector3.UP * 1.3, bc + rr * 0.7 + Vector3.UP * 1.3,
			bc - rr * 0.7 + Vector3.UP * 1.3, Color(0.05, 0.05, 0.05), o)
	t.no_trees.append([c, 30.0])
	# Churchyard wall.
	t._box("stone", c - out * 9.5 + Vector3.UP * (g - c.y + 0.5), fwd, Vector3.UP, out, Vector3(34.0, 1.1, 0.5), Color(0.72, 0.7, 0.66))


# ================================================================ hunting lodge

func _lodge() -> void:
	var i := _idx(Vector2(305, 438))
	if i < 0:
		return
	var side := -1.0 if t._inside_loop(t.centers[i] + t.rights[i] * 40.0) else 1.0
	side = -side # inside the loop looks over the valley
	var r := t.rights[i] * side
	var fwd := t.tangents[i]
	for tries in 6:
		var c := t.centers[i] + r * (t.rail_dist(i, side) + 16.0 + tries * 4.0)
		if not t._fits(c, fwd, r, 16.0, 11.0, 1.0):
			continue
		t._mark(c, fwd, r, 16.0, 11.0)
		var g := t._ground(c)
		for p in t._footprint(c, fwd, r, 16.0, 11.0, 8.0):
			g = minf(g, t._ground(p))
		# Stone plinth, dark log walls, steep shingled roof, deep eaves, antlers.
		t._box("stone", Vector3(c.x, g + 0.4, c.z), fwd, Vector3.UP, r, Vector3(16.4, 2.0, 11.4), Color(0.6, 0.58, 0.54))
		t._box("wood", Vector3(c.x, g + 3.4, c.z), fwd, Vector3.UP, r, Vector3(16.0, 4.0, 11.0), DARK_TIMBER)
		t._gable(Vector3(c.x, g + 5.4, c.z), fwd, r, 16.0, 11.0, 4.8, 1.4, Color(0.3, 0.27, 0.24), DARK_TIMBER, "wood")
		# Balcony facing the road, windows with light.
		var front := c - r * 5.6
		t._box("wood", Vector3(front.x, g + 3.0, front.z) - r * 1.0, fwd, Vector3.UP, r, Vector3(14.0, 0.2, 2.0), TIMBER)
		t._box("wood", Vector3(front.x, g + 3.6, front.z) - r * 1.95, fwd, Vector3.UP, r, Vector3(14.0, 1.0, 0.1), TIMBER)
		for k in 4: # photo windows with green shutters (FacadeKit), lit at night
			var wp := Vector3(front.x, g + 2.9, front.z) - r * 0.03 + fwd * (-5.0 + k * 3.3)
			t._photo_unit(wp, -r, 4 + k % 2, 1.4)
		# Antlers over the door: a few thin pale boxes.
		var ap := Vector3(front.x, g + 5.6, front.z) - r * 0.1
		for s: float in [-1.0, 1.0]:
			t._box("wood", ap + fwd * s * 0.45 + Vector3.UP * 0.3, fwd.rotated(r, s * 0.6), Vector3.UP, r, Vector3(0.08, 0.9, 0.08), Color(0.85, 0.8, 0.7))
		_log_pile(c + fwd * 10.5, r, 5.0, 4)
		t.no_trees.append([c, 16.0])
		# A camp of fans on the slope below the lodge.
		for n in 10:
			var fp := t.centers[i] + fwd * t.rng.randf_range(-20.0, 20.0) + r * (t.rail_dist(i, side) + t.rng.randf_range(1.0, 7.0))
			fp.y = t._ground(fp)
			_fan(fp, t.centers[i])
		return


# ================================================================ camps + fans

func _fan(p: Vector3, look: Vector3) -> void:
	var dir := Vector3(look.x - p.x, 0, look.z - p.z)
	if dir.length() < 0.1:
		return
	# Only on level ground: nobody stands on a steep bank or a rock face.
	var gx := t._ground(p + Vector3(1, 0, 0)) - t._ground(p - Vector3(1, 0, 0))
	var gz := t._ground(p + Vector3(0, 0, 1)) - t._ground(p - Vector3(0, 0, 1))
	if gx * gx + gz * gz > 0.36: # steeper than ~17 degrees
		return
	dir = dir.normalized().rotated(Vector3.UP, t.rng.randf_range(-0.5, 0.5))
	var b := Basis.looking_at(dir, Vector3.UP).scaled(Vector3.ONE * t.rng.randf_range(0.93, 1.07))
	t._person(Transform3D(b, p), PeopleKit.Role.SPECTATOR)


## Rally-style spectator camps: tents, a campfire with logs to sit on, a banner
## and fans along the fence, at the crests, hairpin and tunnel exit.
func _camps() -> void:
	var spots: Array = [Vector2(1095, -122), Vector2(935, -5), Vector2(245, 475), Vector2(42, 430), Vector2(680, -365)]
	for sp: Vector2 in spots:
		var i := _idx(sp)
		if i < 0:
			continue
		for side: float in [-1.0, 1.0]:
			if t.rng.randf() < 0.35:
				continue
			var r := t.rights[i] * side
			var fwd := t.tangents[i]
			var rd := t.rail_dist(i, side)
			var camp := t.centers[i] + r * (rd + 12.0)
			if not t._off_track(camp, 3.0) or not t._foreign_clear(camp, 8.0):
				continue
			camp.y = t._ground(camp)
			if absf(camp.y - t.centers[i].y) > 7.0:
				continue # too steep there
			t.no_trees.append([camp, 13.0])
			# Fans along the fence.
			for n in t.rng.randi_range(8, 16):
				var fp := t.centers[i] + fwd * t.rng.randf_range(-16.0, 16.0) + r * (rd + t.rng.randf_range(1.2, 4.0))
				fp.y = t._ground(fp)
				_fan(fp, t.centers[i])
			# Tents.
			for n in t.rng.randi_range(2, 4):
				var tp := camp + fwd * t.rng.randf_range(-10.0, 10.0) + r * t.rng.randf_range(2.0, 8.0)
				tp.y = t._ground(tp)
				_tent(tp, fwd.rotated(Vector3.UP, t.rng.randf_range(-0.6, 0.6)), TENTS[t.rng.randi() % TENTS.size()])
			# Campfire with sitting logs.
			var fc := camp + fwd * t.rng.randf_range(-3.0, 3.0)
			fc.y = t._ground(fc)
			_campfire(fc)
			for n in 3:
				var ang := TAU * n / 3.0 + t.rng.randf()
				var lp := fc + Vector3(cos(ang), 0, sin(ang)) * 1.8
				lp.y = t._ground(lp) + 0.2
				_log(lp, Vector3(-sin(ang), 0, cos(ang)), 1.6, 0.2, Color(0.4, 0.3, 0.2))
				if t.rng.randf() < 0.7:
					_fan(Vector3(lp.x, lp.y - 0.2, lp.z) + Vector3(cos(ang), 0, sin(ang)) * 0.6, fc)
			# Banner on two poles facing the road.
			var bp := t.centers[i] + r * (rd + 5.0) + fwd * t.rng.randf_range(-8.0, 8.0)
			bp.y = t._ground(bp)
			for s: float in [-1.0, 1.0]:
				t._box("wood", bp + fwd * s * 2.2 + Vector3.UP * 1.3, fwd, Vector3.UP, r, Vector3(0.08, 2.6, 0.08), DARK_TIMBER)
			t._box("canvas", bp + Vector3.UP * 2.1, fwd, Vector3.UP, r, Vector3(4.3, 0.9, 0.03), TENTS[t.rng.randi() % TENTS.size()])


func _tent(p: Vector3, fwd: Vector3, col: Color) -> void:
	var r := fwd.cross(Vector3.UP).normalized()
	var l := 2.6
	var w := 1.9
	var h := 1.35
	var hl := fwd * l * 0.5
	var ridge := p + Vector3.UP * h
	var e0 := p - r * w * 0.5 + Vector3.UP * 0.02
	var e1 := p + r * w * 0.5 + Vector3.UP * 0.02
	t._quad("canvas", e0 - hl, e0 + hl, ridge + hl, ridge - hl, col, -r + Vector3.UP * 0.6)
	t._quad("canvas", e1 - hl, e1 + hl, ridge + hl, ridge - hl, col, r + Vector3.UP * 0.6)
	t._tri("canvas", e0 + hl, e1 + hl, ridge + hl, col * 0.85, fwd)
	t._tri("canvas", e0 - hl, e1 - hl, ridge - hl, Color(0.05, 0.05, 0.05), -fwd)


func _campfire(c: Vector3) -> void:
	for k in 6:
		var ang := TAU * k / 6.0
		t._box("rock", c + Vector3(cos(ang), 0.1, sin(ang)) * 0.6, Vector3(cos(ang), 0, sin(ang)), Vector3.UP,
			Vector3(-sin(ang), 0, cos(ang)), Vector3(0.3, 0.25, 0.35), Color(0.45, 0.43, 0.4))
	# Embers and flames: crossed emissive cards (no light: lights cost frames).
	for k in 2:
		var d := Vector3(cos(k * PI * 0.5), 0, sin(k * PI * 0.5))
		var rr := d.cross(Vector3.UP)
		t._tri("fire", c - d * 0.35 + Vector3.UP * 0.05, c + d * 0.35 + Vector3.UP * 0.05, c + Vector3.UP * 0.75, Color.WHITE, rr)
		t._tri("fire", c - d * 0.35 + Vector3.UP * 0.05, c + d * 0.35 + Vector3.UP * 0.05, c + Vector3.UP * 0.75, Color.WHITE, -rr)
	fires.append(c)


# ================================================================ leaves on the verges

## Drifts of fallen leaves: flat irregular patches of leaf-coloured confetti on
## the verges and against the guardrails (MultiMesh, near range only).
func _leaf_drifts() -> void:
	if float(t.preset.get("snow", 0.0)) > 0.0:
		return
	var mesh := _drift_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.9 if float(t.preset.get("wet", 0.0)) < 0.3 else 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	t._mm_set("leaf_drift", mesh, mat, 110.0, false)
	for i in range(0, t.n, 2):
		for side: float in [-1.0, 1.0]:
			if t.rng.randf() < 0.5:
				continue
			# Between the kerb and the rail, thickest at the rail foot.
			var rd := t.rail_dist(i, side)
			var gd := t.gravel_depth(i, side)
			var lat := lerpf(t.half + 1.8 + (gd + 0.5 if gd > 0.3 else 0.0), rd + 1.5, sqrt(t.rng.randf()))
			var p := t.centers[i] + t.rights[i] * side * lat + t.tangents[i] * t.rng.randf_range(-1.0, 1.0)
			p.y = t._ground(p) + 0.03
			var s := t.rng.randf_range(0.7, 1.5)
			t._mm_add("leaf_drift", Transform3D(Basis(Vector3.UP, t.rng.randf() * TAU).scaled(Vector3(s, 1.0, s)), p))
	# Some leaves on the tarmac edge too (blown in, thin).
	for i in range(0, t.n, 3):
		if t.rng.randf() < 0.5 or absf(t.corner[i]) > 0.12:
			continue
		var side := -1.0 if t.rng.randf() < 0.5 else 1.0
		var p := t.centers[i] + t.rights[i] * side * t.rng.randf_range(t.half - 1.6, t.half - 0.3)
		p.y = t.centers[i].y + 0.025
		var s := t.rng.randf_range(0.4, 0.8)
		t._mm_add("leaf_drift", Transform3D(Basis(Vector3.UP, t.rng.randf() * TAU).scaled(Vector3(s, 0.5, s)), p))


func _drift_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for k in 70:
		var ang := rng.randf() * TAU
		var rad := sqrt(rng.randf()) * 1.4
		var c := Vector3(cos(ang) * rad * 1.3, rng.randf() * 0.04, sin(ang) * rad)
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.06, 0.1)
		var e := Vector3(-d.z, 0, d.x) * 0.7
		var col: Color = LEAF_COLS[rng.randi() % LEAF_COLS.size()]
		col = col.lerp(Color(0.3, 0.22, 0.12), rng.randf() * 0.4)
		var tilt := Vector3.UP * rng.randf_range(-0.02, 0.03)
		var q := [c - d, c + e + tilt, c + d, c - e - tilt]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(Vector3.UP)
			st.add_vertex(q[idx])
	return st.commit()
