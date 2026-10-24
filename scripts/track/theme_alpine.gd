class_name AlpineTheme
extends RefCounted
## "alpine" theme (Alpenpass), built by TrackThemes with its batching helpers:
##  - the gorge with a waterfall at its head and the stone arch bridge
##    (AutumnTheme's river + bridge builder, fed by the def's river keys);
##  - rock faces draped over every cutting and drop the terrain shaper made
##    (alpine_terrain.gd), dry-stone retaining walls under the valley edge;
##  - stone parapets behind the guardrail wherever the valley side drops away;
##  - the concrete avalanche gallery on the summit ridge (roof on pillars,
##    open to the valley), and the summit tunnel through the rock spur
##    (AutumnTheme's rock cut + tunnel, fed by the def's cut / tunnel keys);
##  - the village on the start straight: Tyrolean chalets with timber upper
##    storeys, balconies with geraniums, deep eaves, the church;
##  - the Berghotel at the pass with its terrace;
##  - Alm pastures with hay barns (cows with bells: WildlifeBuilder, alm_zones);
##  - wayside shrines (Marterl) and stacked firewood.

const STONE := Color(0.8, 0.78, 0.74)
const TIMBER := Color(0.62, 0.45, 0.3)
const DARK_TIMBER := Color(0.36, 0.25, 0.16)
const CONCRETE := Color(0.82, 0.8, 0.76)
const ROOFS := [Color(0.34, 0.33, 0.33), Color(0.3, 0.24, 0.2), Color(0.42, 0.4, 0.38), Color(0.5, 0.3, 0.22)]
const PLASTER := [Color(0.95, 0.94, 0.9), Color(0.93, 0.9, 0.82), Color(0.96, 0.93, 0.86), Color(0.9, 0.88, 0.84)]
const GERANIUM := [Color(0.85, 0.08, 0.1), Color(0.9, 0.2, 0.35), Color(0.8, 0.1, 0.4)]

var t: TrackThemes
var body: StaticBody3D
var au: AutumnTheme
var flat := [] ## per lap sample: {1.0: m, -1.0: m} level ground from the centreline (shaper's)
var skip := {} ## lap sample -> true where a set piece owns the roadside
var alm: Array = [] ## [centre, radius] pastures for the cows


static func build(themes: TrackThemes) -> void:
	var a := AlpineTheme.new()
	a.t = themes
	a._run()


func _run() -> void:
	body = StaticBody3D.new()
	body.name = "AlpineColliders"
	t.parent.add_child(body)
	t.mats.wood = Mats.mat("wood")
	t.mats.slate = Mats.mat("slate")
	t.mats.concrete = Mats.mat("concrete")
	t.mats.canvas = Mats.mat("canvas")
	# Grey limestone (rock_08, triplanar, no shadows: "cutrock" key) for the
	# tunnel cut faces AutumnTheme drapes.
	var rock := t._vc(0.92)
	rock.albedo_texture = load("res://assets/themes/alpine/rock_08_diff_1k.jpg")
	rock.normal_enabled = true
	rock.normal_texture = load("res://assets/themes/alpine/rock_08_nor_gl_1k.jpg")
	rock.uv1_triplanar = true
	rock.uv1_world_triplanar = true
	rock.uv1_scale = Vector3.ONE * 0.11
	rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	t.mats.cutrock = rock
	t.vis.wood = 700.0
	t.vis.canvas = 350.0
	t.vis.flower = 220.0
	var flower := t._vc(0.8)
	t.mats.flower = flower
	flat = AlpineTerrain.flat_widths(t.centers)
	_ground_tint()
	au = AutumnTheme.new()
	au.t = t
	au.body = body
	au._river_and_bridge()
	au._rock_cut_and_tunnel()
	_skip_range(t.def.get("cut", []), 4)
	_skip_bridge()
	_gallery()
	_village()
	_hotel()
	_parapets()
	_backdrop()
	_waterfall()
	_alm()
	t.parent.set_meta("alm_zones", alm)


func _idx(p: Vector2) -> int:
	return t._nearest(Vector3(p.x, 0, p.y), 200.0)


func _skip_range(ends: Array, pad: int) -> void:
	if ends.size() < 2:
		return
	var i0 := _idx(ends[0])
	var i1 := _idx(ends[1])
	if i0 < 0 or i1 < 0:
		return
	for k in range(-pad, posmod(i1 - i0, t.n) + pad + 1):
		skip[t._i(i0 + k)] = true


func _skip_bridge() -> void:
	var rs := AutumnTerrain.river_samples(t.def)
	var best := INF
	var bi := -1
	for s in rs:
		var i := t._nearest(s, 40.0)
		if i < 0:
			continue
		var dd := Vector2(t.centers[i].x - s.x, t.centers[i].z - s.z).length()
		if dd < best:
			best = dd
			bi = i
	if bi >= 0:
		for k in range(-17, 18):
			skip[t._i(bi + k)] = true


func _col_box(c: Vector3, basis: Basis, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)


## Alpine ground: the circuit's shared ground material (terrain, far hills,
## backdrop) gets the alpine shader: meadow, rock on steep slopes, scree above
## the tree line, snow caps on the peaks.
func _ground_tint() -> void:
	var tn: Node = t.parent.get_node_or_null("Terrain")
	if tn == null:
		return
	for ch in tn.get_children():
		if ch is MeshInstance3D:
			var m := (ch as MeshInstance3D).material_override as ShaderMaterial
			if m == null:
				break
			var keep := {}
			for k in ["a_albedo", "a_normal", "b_albedo", "b_normal", "noise_tex", "wetness", "snow"]:
				keep[k] = m.get_shader_parameter(k)
			m.shader = load("res://shaders/alpine_terrain.gdshader")
			for k in keep:
				m.set_shader_parameter(k, keep[k])
			const D := "res://assets/themes/alpine/%s_1k.jpg"
			m.set_shader_parameter("moss_albedo", load(D % "aerial_rocks_02_diff"))
			m.set_shader_parameter("moss_normal", load(D % "aerial_rocks_02_nor_gl"))
			m.set_shader_parameter("cliff_albedo", load(D % "rock_08_diff"))
			m.set_shader_parameter("cliff_normal", load(D % "rock_08_nor_gl"))
			m.set_shader_parameter("scree_albedo", load(D % "gray_rocks_diff"))
			m.set_shader_parameter("snow_albedo", load(D % "snow_02_diff"))
			if float(t.preset.get("snow", 0.0)) <= 0.0:
				m.set_shader_parameter("tint", Vector3(0.6, 0.95, 0.46))
			break


# ================================================================ rock + walls

## Low stone parapet just behind the guardrail wherever the valley drops away.
func _parapets() -> void:
	for i in t.n:
		if skip.has(i):
			continue
		var j := t._i(i + 1)
		for side: float in [-1.0, 1.0]:
			var lat: float = flat[i][side] - AlpineTerrain.BACK + 0.9
			var c := t.centers[i]
			var r := t.rights[i] * side
			var probe := t._ground(c + r * (flat[i][side] + 6.0))
			if c.y - probe < 2.5:
				continue
			var a := c + r * lat
			var b := t.centers[j] + t.rights[j] * side * (float(flat[j][side]) - AlpineTerrain.BACK + 0.9)
			a.y = t._ground(a)
			b.y = t._ground(b)
			var mid := (a + b) * 0.5
			var fwd := b - a
			if fwd.length() < 0.5 or fwd.length() > 4.0:
				continue
			var ax := fwd.normalized()
			var az := Vector3.UP.cross(ax).normalized() * side
			var g := 0.72 + 0.08 * sin(i * 1.3)
			t._box("stone", mid + Vector3.UP * 0.2, ax, Vector3.UP, az, Vector3(fwd.length() + 0.04, 1.6, 0.6), Color(g, g * 0.97, g * 0.92))
			# Coping stones.
			t._box("stone", mid + Vector3.UP * 1.06, ax, Vector3.UP, az, Vector3(fwd.length() + 0.04, 0.14, 0.72), Color(0.84, 0.82, 0.78))


## The high Alps around the valley: a ring of steep, sharp-ridged peaks
## 900-2000 m above it, 1.4-3.2 km out, close enough to frame every view.
## One cheap mesh (no collision, no shadows, always drawn) with the alpine
## ground shader (its own material copy: higher tree / snow lines).
func _backdrop() -> void:
	var tn: Node = t.parent.get_node_or_null("Terrain")
	var gm: ShaderMaterial = null
	if tn:
		for ch in tn.get_children():
			if ch is MeshInstance3D:
				gm = (ch as MeshInstance3D).material_override as ShaderMaterial
				break
	if gm == null:
		return
	var m := gm.duplicate() as ShaderMaterial
	m.set_shader_parameter("tree_line", 520.0)
	m.set_shader_parameter("snow_line", 900.0)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for c in t.centers:
		lo = lo.min(Vector2(c.x, c.z))
		hi = hi.max(Vector2(c.x, c.z))
	var ctr := (lo + hi) * 0.5
	var r_in := maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 + 470.0 # from the terrain's edge
	var r_out := r_in + 2600.0
	var ridge := FastNoiseLite.new()
	ridge.seed = 11
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.frequency = 0.0011
	ridge.fractal_octaves = 5
	var mass := FastNoiseLite.new()
	mass.seed = 12
	mass.frequency = 0.0005
	var seg := 220
	var rings := 44
	var grid: Array[PackedVector3Array] = []
	for rr in rings + 1:
		var u := float(rr) / rings
		var rad := lerpf(r_in, r_out, u)
		var row := PackedVector3Array()
		for sg in seg + 1:
			var a := TAU * sg / seg
			var p := Vector3(ctr.x + cos(a) * rad, 0, ctr.y + sin(a) * rad)
			var rd := ridge.get_noise_2d(p.x, p.z) * 0.5 + 0.5 # sharp crests near 1
			var ms := mass.get_noise_2d(p.x, p.z) * 0.5 + 0.5
			var rise := smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.85, 1.0, u) * 0.4)
			p.y = -20.0 + rise * (500.0 + ms * 900.0) * (0.35 + 0.65 * pow(rd, 2.2))
			row.append(p)
		grid.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rr in rings:
		for sg in seg:
			var a := grid[rr][sg]
			var b := grid[rr][sg + 1]
			var c := grid[rr + 1][sg + 1]
			var d := grid[rr + 1][sg]
			for v in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "AlpineRange"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 50.0
	t.parent.add_child(mi)
	# The generic rolling far hills (built after the themes) would sit in front
	# of the range as soft green domes: hide them once they exist.
	var hider := HillHider.new()
	t.parent.add_child(hider)


class HillHider:
	extends Node

	var _t := 0.0

	# The build yields frames between steps: wait until the hills exist.
	func _process(delta: float) -> void:
		_t += delta
		var hills := get_parent().get_node_or_null("Hills") as Node3D
		if hills:
			hills.visible = false
			queue_free()
		elif _t > 120.0:
			queue_free()


# ================================================================ avalanche gallery

func _gallery() -> void:
	var ends: Array = t.def.get("gallery", [])
	if ends.size() < 2:
		return
	var i0 := _idx(ends[0])
	var i1 := _idx(ends[1])
	if i0 < 0 or i1 < 0:
		return
	var count := posmod(i1 - i0, t.n)
	# Uphill side: where the mountain is.
	var mid := t._i(i0 + count / 2)
	var up := 1.0
	if t._ground(t.centers[mid] + t.rights[mid] * 30.0) < t._ground(t.centers[mid] - t.rights[mid] * 30.0):
		up = -1.0
	var clear := 7.0 # headroom at the valley edge
	for k in range(-3, count + 4):
		skip[t._i(i0 + k)] = true
	for k in count:
		var i := t._i(i0 + k)
		var j := t._i(i0 + k + 1)
		var ci := t.centers[i]
		var cj := t.centers[j]
		var ri := t.rights[i] * up
		var rj := t.rights[j] * up
		var lw_i: float = flat[i][up] - AlpineTerrain.BACK + 1.6 # mountain wall line
		var lw_j: float = flat[j][up] - AlpineTerrain.BACK + 1.6
		var lv_i: float = flat[i][-up] - AlpineTerrain.BACK + 1.2 # valley pillar line
		var lv_j: float = flat[j][-up] - AlpineTerrain.BACK + 1.2
		var wa := ci + ri * lw_i
		var wb := cj + rj * lw_j
		# Mountain wall (faces the road), with a darker plinth.
		var top_w := clear + 1.4
		t._quad("concrete", wa - Vector3.UP * 0.5, wb - Vector3.UP * 0.5, wb + Vector3.UP * top_w, wa + Vector3.UP * top_w, CONCRETE * 0.92, -ri)
		t._quad("concrete", wa - Vector3.UP * 0.5 - ri * 0.02, wb - Vector3.UP * 0.5 - rj * 0.02, wb + Vector3.UP * 0.9 - rj * 0.02,
			wa + Vector3.UP * 0.9 - ri * 0.02, CONCRETE * 0.6, -ri)
		# Roof: underside and the earth / rock cover on top, sloping to the valley.
		var va := ci - ri * (lv_i + 1.0)
		var vb := cj - rj * (lv_j + 1.0)
		var u_wa := wa + Vector3.UP * top_w
		var u_wb := wb + Vector3.UP * top_w
		var u_va := va + Vector3.UP * clear
		var u_vb := vb + Vector3.UP * clear
		t._quad("concrete", u_wa, u_wb, u_vb, u_va, CONCRETE * 0.55, Vector3.DOWN)
		var th := Vector3.UP * 1.1
		var back_a := ci + ri * (lw_i + 14.0)
		var back_b := cj + rj * (lw_j + 14.0)
		back_a.y = maxf(t._ground(back_a), u_wa.y + th.y + 1.0)
		back_b.y = maxf(t._ground(back_b), u_wb.y + th.y + 1.0)
		t._quad("rock", u_va + th, u_vb + th, u_wb + th + Vector3.UP * 0.6, u_wa + th + Vector3.UP * 0.6, Color(0.5, 0.5, 0.47), Vector3.UP)
		t._quad("rock", u_wa + th + Vector3.UP * 0.6, u_wb + th + Vector3.UP * 0.6, back_b, back_a, Color(0.52, 0.52, 0.48), Vector3.UP)
		# Valley fascia beam.
		t._quad("concrete", u_va - Vector3.UP * 1.0, u_vb - Vector3.UP * 1.0, u_vb + th, u_va + th, CONCRETE, -ri * -1.0)
		t._quad("concrete", u_va - Vector3.UP * 1.0 + ri * 0.6, u_vb - Vector3.UP * 1.0 + rj * 0.6, u_vb + ri * 0.6, u_va + ri * 0.6, CONCRETE * 0.7, ri)
		t._quad("concrete", u_va - Vector3.UP * 1.0, u_vb - Vector3.UP * 1.0, u_vb - Vector3.UP * 1.0 + rj * 0.6, u_va - Vector3.UP * 1.0 + ri * 0.6, CONCRETE * 0.6, Vector3.DOWN)
		var fwd := (cj - ci).normalized()
		var bas := Basis.looking_at(fwd, Vector3.UP)
		_col_box((wa + wb) * 0.5 + ri * 0.5 + Vector3.UP * 3.5, bas, Vector3(1.0, 8.0, 2.3))
		# Pillars every 6 m on the valley side, a low wall between them.
		if k % 3 == 0:
			var pc := ci - ri * (lv_i + 0.4)
			var g := t._ground(pc)
			t._box("concrete", Vector3(pc.x, (g - 0.5 + ci.y + clear) * 0.5, pc.z), fwd, Vector3.UP, ri, Vector3(1.0, ci.y + clear - g + 0.5, 0.8), CONCRETE)
			_col_box(Vector3(pc.x, ci.y + clear * 0.5, pc.z), bas, Vector3(0.8, clear, 1.0))
		var pa := ci - ri * (lv_i + 0.4)
		var pb := cj - rj * (lv_j + 0.4)
		pa.y = t._ground(pa)
		pb.y = t._ground(pb)
		t._box("concrete", (pa + pb) * 0.5 + Vector3.UP * 0.35, fwd, Vector3.UP, ri, Vector3(pa.distance_to(pb) + 0.05, 1.2, 0.45), CONCRETE * 0.9)
		# Ceiling lamps (emissive strips, no lights).
		if k % 6 == 3:
			var lc := ci + Vector3.UP * (clear + 0.3) + ri * 2.0
			t._box("lamp", lc, fwd, Vector3.UP, ri, Vector3(1.6, 0.12, 0.3), Color(1.0, 0.95, 0.8))
	t.no_trees.append([t.centers[mid], count + 30.0])
	# Portal faces at both ends.
	for e in [[i0, -1.0], [i1, 1.0]]:
		var i: int = e[0]
		var ci := t.centers[i]
		var ri := t.rights[i] * up
		var out := t.tangents[i] * float(e[1])
		var lw: float = flat[i][up] - AlpineTerrain.BACK + 1.6
		var lv: float = flat[i][-up] - AlpineTerrain.BACK + 1.2
		var a := ci - ri * (lv + 1.0) + Vector3.UP * (clear - 1.0)
		var b := ci + ri * lw + Vector3.UP * (clear + 1.4 - 1.0)
		t._box("concrete", (a + b) * 0.5 + Vector3.UP * 1.0 + out * 0.3, ri, Vector3.UP, out, Vector3(a.distance_to(b) + 1.0, 2.6, 0.7), CONCRETE * 1.05)


# ================================================================ village

func _village() -> void:
	var ends: Array = t.def.get("village", [])
	if ends.size() < 2:
		return
	var i0 := _idx(ends[0])
	var i1 := _idx(ends[1])
	var span := posmod(i1 - i0, t.n)
	var church_done := false
	for side: float in [-1.0, 1.0]:
		var k := 0
		while k < span:
			var i := t._i(i0 + k)
			var fwd := t.tangents[i]
			var r := t.rights[i] * side
			if not church_done and side < 0.0 and k > span * 0.55:
				var cc := t.centers[i] + r * (t.rail_dist(i, side) + 22.0)
				if t._fits(cc, fwd, r, 30.0, 16.0, 1.0):
					au._church(cc, fwd, r)
					church_done = true
					k += 22
					continue
			var w := t.rng.randf_range(10.0, 13.0)
			var d := t.rng.randf_range(9.0, 12.0)
			var setback := t.rail_dist(i, side) + t.rng.randf_range(4.0, 8.0) + d * 0.5
			var hc := t.centers[i] + r * setback
			if t._fits(hc, fwd, r, w + 3.0, d + 3.0, 1.0) and t.rng.randf() < 0.9:
				t._mark(hc, fwd, r, w + 3.0, d + 3.0)
				_chalet(hc, fwd, r, w, d, 2 if t.rng.randf() < 0.7 else 3)
				if t.rng.randf() < 0.6:
					var fp := t.centers[i] + r * (t.rail_dist(i, side) + 1.5)
					fp.y = t._ground(fp)
					au._fan(fp, t.centers[i])
			k += int((w + t.rng.randf_range(3.0, 9.0)) / TrackThemes.STEP)
		# A second row further back so the village reads as a village.
		k = 6
		while k < span:
			var i := t._i(i0 + k)
			var fwd := t.tangents[i]
			var r := t.rights[i] * side
			var w := t.rng.randf_range(10.0, 14.0)
			var d := t.rng.randf_range(9.0, 12.0)
			var hc := t.centers[i] + r * (t.rail_dist(i, side) + t.rng.randf_range(26.0, 34.0))
			if t._fits(hc, fwd, r, w + 3.0, d + 3.0, 1.0):
				t._mark(hc, fwd, r, w + 3.0, d + 3.0)
				_chalet(hc, fwd.rotated(Vector3.UP, t.rng.randf_range(-0.2, 0.2)), r, w, d, 2 + t.rng.randi() % 2)
			k += int((w + t.rng.randf_range(6.0, 14.0)) / TrackThemes.STEP)


## Tyrolean chalet: white rendered ground floor(s) with windows (facade
## shader), a timber upper storey and gable, wide shallow roof with deep eaves
## (gable end to the road), a balcony with geraniums, firewood under the eaves.
## `az` points away from the road (front faces -az).
func _chalet(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float, floors: int) -> void:
	ax = Vector3(ax.x, 0, ax.z).normalized()
	az = Vector3(az.x, 0, az.z).normalized()
	var front := c - az * d * 0.5
	var street := t._ground(front)
	var lowest := street
	for p in t._footprint(c, ax, az, w, d, 3.0):
		lowest = minf(lowest, t._ground(p))
	var y0 := lowest - 1.0
	var plaster_h := 3.0 * (floors - 1) + 0.4
	var y1 := street + plaster_h
	var wall_col: Color = PLASTER[t.rng.randi() % PLASTER.size()]
	var variant := t.rng.randi() % 10
	var faces := [[front, -az, w], [c + az * d * 0.5, az, w], [c + ax * w * 0.5, ax, d], [c - ax * w * 0.5, -ax, d]]
	for f in faces:
		var fw: float = f[2]
		t._wall("wall", f[0], f[1], fw, y0, y1, street, wall_col, Vector2(fw + 3000.0, plaster_h + 100.0 * variant)) # style 3: photo farm facade with shutters
	# Stone plinth band.
	t._box("stone", Vector3(c.x, street + 0.1, c.z), ax, Vector3.UP, az, Vector3(w + 0.1, 1.0, d + 0.1), Color(0.66, 0.64, 0.6))
	# Timber top storey (log walls), windows as dark glass.
	var y2 := y1 + 2.8
	t._box("wood", Vector3(c.x, (y1 + y2) * 0.5, c.z), ax, Vector3.UP, az, Vector3(w, y2 - y1, d), DARK_TIMBER)
	for k in 3:
		var wp := Vector3(front.x, y1 + 1.5, front.z) - az * 0.03 + ax * (k - 1) * w * 0.3
		t._quad("glass", wp - ax * 0.55 - Vector3.UP * 0.65, wp + ax * 0.55 - Vector3.UP * 0.65, wp + ax * 0.55 + Vector3.UP * 0.65,
			wp - ax * 0.55 + Vector3.UP * 0.65, Color.WHITE, -az)
	# Roof: gable to the front, shallow, deep eaves; timber gable triangles.
	var rise := w * 0.24
	t._gable(Vector3(c.x, y2, c.z), az, ax, d, w, rise, 1.6, ROOFS[t.rng.randi() % ROOFS.size()], DARK_TIMBER, "wood")
	# Balcony along the front at the timber storey, with geraniums.
	var bal := Vector3(front.x, y1 + 0.1, front.z) - az * 0.9
	t._box("wood", bal, ax, Vector3.UP, az, Vector3(w + 0.6, 0.18, 1.8), TIMBER)
	t._box("wood", bal + Vector3.UP * 0.55 - az * 0.85, ax, Vector3.UP, az, Vector3(w + 0.6, 0.95, 0.1), TIMBER * 0.9)
	for s: float in [-1.0, 1.0]:
		t._box("wood", bal + Vector3.UP * 0.5 - az * 0.85 + ax * s * (w * 0.5 + 0.3), ax, Vector3.UP, az, Vector3(0.12, 1.1, 1.8), TIMBER * 0.8)
	var fl: Color = GERANIUM[t.rng.randi() % GERANIUM.size()]
	t._box("wood", bal + Vector3.UP * 1.12 - az * 0.92, ax, Vector3.UP, az, Vector3(w + 0.4, 0.22, 0.3), DARK_TIMBER)
	for k in int(w / 0.55):
		var fp := bal + Vector3.UP * 1.32 - az * (0.92 + t.rng.randf_range(-0.1, 0.12)) + ax * (-w * 0.5 + 0.3 + k * 0.55)
		t._box("flower", fp, ax, Vector3.UP, az, Vector3(0.5, 0.3 + t.rng.randf_range(0.0, 0.15), 0.4), fl * t.rng.randf_range(0.8, 1.1))
	# Firewood stacked under the side eave.
	if t.rng.randf() < 0.7:
		var side := 1.0 if t.rng.randf() < 0.5 else -1.0
		var wc := c + ax * side * (w * 0.5 + 0.5)
		wc.y = t._ground(wc) + 0.8
		t._box("wood", wc, az, Vector3.UP, ax, Vector3(d * 0.7, 1.6, 0.9), Color(0.55, 0.4, 0.26))
	t.no_trees.append([c, maxf(w, d) * 0.8 + 3.0])
	_col_box(Vector3(c.x, street + 2.5, c.z), Basis(ax, Vector3.UP, az), Vector3(w, 6.0, d))


# ================================================================ hotel at the pass

func _hotel() -> void:
	var ends: Array = t.def.get("gallery", [])
	var tun: Array = t.def.get("tunnel", [])
	if ends.size() < 2 or tun.size() < 2:
		return
	# Between the gallery exit and the tunnel, on the valley side.
	var g1 := _idx(ends[1])
	var t0 := _idx(tun[0])
	var span := posmod(t0 - g1, t.n)
	for k in range(6, span - 6, 3):
		var i := t._i(g1 + k)
		for side: float in [-1.0, 1.0]:
			var r := t.rights[i] * side
			var probe := t._ground(t.centers[i] + r * 40.0)
			if probe > t.centers[i].y + 4.0:
				continue # the mountain side
			var fwd := t.tangents[i]
			var c := t.centers[i] + r * (t.rail_dist(i, side) + 16.0)
			if not t._fits(c, fwd, r, 34.0, 16.0, 1.0):
				continue
			t._mark(c, fwd, r, 34.0, 16.0)
			_build_hotel(c, fwd, r, i)
			return


func _build_hotel(c: Vector3, ax: Vector3, az: Vector3, i: int) -> void:
	ax = Vector3(ax.x, 0, ax.z).normalized()
	az = Vector3(az.x, 0, az.z).normalized()
	var w := 30.0
	var d := 14.0
	var street := t.centers[i].y
	# Level terrace platform on a stone retaining wall.
	var front := c - az * d * 0.5
	var lowest := street
	for p in t._footprint(c, ax, az, w + 10.0, d + 14.0, 3.0):
		lowest = minf(lowest, t._ground(p))
	t._box("stone", Vector3(c.x, (lowest - 1.0 + street) * 0.5, c.z) - az * 3.0, ax, Vector3.UP, az, Vector3(w + 8.0, street - lowest + 1.0, d + 12.0), STONE * 0.85)
	t._box("stone", Vector3(c.x, street + 0.05, c.z) - az * 3.0, ax, Vector3.UP, az, Vector3(w + 8.1, 0.12, d + 12.1), Color(0.6, 0.58, 0.55))
	var floors := 4
	var plaster_h := 3.1 * (floors - 1)
	var y1 := street + plaster_h
	var col := Color(0.96, 0.94, 0.88)
	for f in [[front, -az, w], [c + az * d * 0.5, az, w], [c + ax * w * 0.5, ax, d], [c - ax * w * 0.5, -ax, d]]:
		var fw: float = f[2]
		t._wall("wall", f[0], f[1], fw, street - 0.6, y1, street, col, Vector2(fw, plaster_h + 300.0))
	var y2 := y1 + 3.0
	t._box("wood", Vector3(c.x, (y1 + y2) * 0.5, c.z), ax, Vector3.UP, az, Vector3(w, y2 - y1, d), DARK_TIMBER)
	t._gable(Vector3(c.x, y2, c.z), ax, az, w, d, d * 0.3, 1.8, Color(0.3, 0.29, 0.29), DARK_TIMBER, "wood")
	# Long balconies on every upper floor.
	for fl in range(1, floors + 1):
		var by := street + 3.1 * fl - 0.1
		var bc := Vector3(front.x, by, front.z) - az * 0.9
		t._box("wood", bc, ax, Vector3.UP, az, Vector3(w + 0.4, 0.18, 1.8), TIMBER)
		t._box("wood", bc + Vector3.UP * 0.55 - az * 0.85, ax, Vector3.UP, az, Vector3(w + 0.4, 0.95, 0.1), TIMBER * 0.85)
		var fcol: Color = GERANIUM[fl % GERANIUM.size()]
		for k in int(w / 0.6):
			var fp := bc + Vector3.UP * 1.25 - az * 0.92 + ax * (-w * 0.5 + 0.3 + k * 0.6)
			t._box("flower", fp, ax, Vector3.UP, az, Vector3(0.55, 0.32 + 0.1 * sin(k * 1.7), 0.4), fcol)
	# Terrace parasols and tables in front.
	for k in 5:
		var p := front - az * 6.0 + ax * (-12.0 + k * 6.0)
		p.y = street
		t._cyl("canvas", p + Vector3.UP * 2.2, 2.0, 0.0, 0.7, 8, Color(0.75, 0.12, 0.1) if k % 2 == 0 else Color(0.92, 0.9, 0.84), false)
		t._cyl("metal", p, 0.04, 0.04, 2.3, 4, Color(0.8, 0.8, 0.8), false)
		t._cyl("wood", p, 0.6, 0.6, 0.75, 8, TIMBER)
	t.no_trees.append([c, 30.0])
	_col_box(Vector3(c.x, street + 6.0, c.z), Basis(ax, Vector3.UP, az), Vector3(w, 14.0, d))
	# Name boards: real text (Label3D), on the facade and on the terrace wall.
	_label(Vector3(front.x, y1 + 1.6, front.z) - az * 0.08, -az, "BERGHOTEL ALPENROSE", 2.4, Color(0.95, 0.9, 0.75))
	_label(Vector3(front.x, street + 1.0, front.z) - az * 11.6 + Vector3.UP * 0.0, -az, "PASSHÖHE 2106 m", 1.2, Color(0.15, 0.12, 0.1))


func _label(p: Vector3, facing: Vector3, text: String, size: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size / 64.0
	l.font_size = 64
	l.outline_size = 0
	l.modulate = col
	l.shaded = true
	l.double_sided = false
	l.visibility_range_end = 400.0
	l.position = p
	l.basis = Basis.looking_at(-facing, Vector3.UP)
	t.parent.add_child(l)


# ================================================================ waterfall

func _waterfall() -> void:
	var rs := AutumnTerrain.river_samples(t.def)
	if rs.size() < 3:
		return
	var head := rs[0]
	var dir := (rs[2] - rs[0])
	dir.y = 0.0
	dir = dir.normalized()
	var r := dir.cross(Vector3.UP)
	# The cliff the stream falls over: the highest ground just upstream.
	var top := head.y
	var top_p := head
	for k in range(2, 14):
		var p := head - dir * k * 2.0
		var g := t._ground(p)
		if g > top:
			top = g
			top_p = p
	if top - head.y < 4.0:
		return
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
void fragment() {
	vec2 uv = UV;
	float n = texture(noise_tex, vec2(uv.x * 1.5, uv.y * 0.35 - TIME * 0.9)).r;
	float n2 = texture(noise_tex, vec2(uv.x * 3.1 + 0.3, uv.y * 0.6 - TIME * 1.6)).r;
	float foam = smoothstep(0.35, 0.75, n * 0.6 + n2 * 0.5);
	ALBEDO = mix(vec3(0.42, 0.52, 0.55), vec3(0.93, 0.95, 0.96), foam);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
	float edge = smoothstep(0.0, 0.18, uv.x) * smoothstep(1.0, 0.82, uv.x);
	ALPHA = clamp(edge * (0.55 + foam * 0.45), 0.0, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("noise_tex", t.noise_tex)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 5.0
	var steps := 8
	var foot := head - dir * 1.5
	for s in steps:
		var u0 := float(s) / steps
		var u1 := float(s + 1) / steps
		# Falls out over the lip and drops in a slight curve.
		var p0 := top_p.lerp(foot, u0 * u0 * 0.3 + u0 * 0.7)
		var p1 := top_p.lerp(foot, u1 * u1 * 0.3 + u1 * 0.7)
		p0.y = lerpf(top + 0.3, head.y, u0)
		p1.y = lerpf(top + 0.3, head.y, u1)
		p0 += dir * 1.2
		p1 += dir * 1.2
		var q := [[p0 - r * w * 0.5, Vector2(0, u0)], [p0 + r * w * 0.5, Vector2(1, u0)],
			[p1 + r * w * 0.5, Vector2(1, u1)], [p1 - r * w * 0.5, Vector2(0, u1)]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(dir)
			st.set_uv(q[k][1] * Vector2(1.0, (top - head.y) / 5.0))
			st.add_vertex(q[k][0])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Waterfall"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.parent.add_child(mi)
	# Rock face behind it and boulders in the plunge pool.
	for k in 10:
		var p := head + r * t.rng.randf_range(-7.0, 7.0) + dir * t.rng.randf_range(-2.0, 6.0)
		p.y = t._ground(p) - 0.2
		var sz := t.rng.randf_range(0.8, 2.0)
		t._box("rock", p + Vector3.UP * sz * 0.3, r, Vector3.UP, dir, Vector3(sz * 1.4, sz, sz * 1.1), Color(0.6, 0.6, 0.58))
	t.no_trees.append([head, 14.0])


# ================================================================ Alm pastures

## Open pasture clearings on gentle ground near the road, each with a timber
## hay barn (Heustadel); WildlifeBuilder puts brown cows with bells in them.
func _alm() -> void:
	var tries := 0
	while alm.size() < 6 and tries < 400:
		tries += 1
		var i := t.rng.randi() % t.n
		if skip.has(i):
			continue
		var side := -1.0 if t.rng.randf() < 0.5 else 1.0
		var r := t.rights[i] * side
		var c := t.centers[i] + r * (float(flat[i][side]) + t.rng.randf_range(18.0, 30.0))
		if not t._off_track(c, 14.0):
			continue
		# Gentle enough to graze (and to see from the road).
		var ok := true
		var g0 := t._ground(c)
		for a in 6:
			var q := c + Vector3(cos(a * 1.05), 0, sin(a * 1.05)) * 16.0
			if absf(t._ground(q) - g0) > 4.5 or not t._off_track(q, 6.0):
				ok = false
				break
		if not ok:
			continue
		var clash := false
		for z: Array in alm:
			if (z[0] as Vector3).distance_to(c) < 160.0:
				clash = true
		if clash:
			continue
		c.y = g0
		alm.append([c, 20.0])
		t.no_trees.append([c, 26.0])
		# Hay barn at the back of the pasture.
		var fwd := t.tangents[i]
		var bc := c + r * 14.0
		if t._fits(bc, fwd, r, 7.0, 6.0, 0.5):
			t._mark(bc, fwd, r, 7.0, 6.0)
			var g := t._ground(bc)
			for p in t._footprint(bc, fwd, r, 7.0, 6.0, 3.0):
				g = minf(g, t._ground(p))
			t._box("stone", Vector3(bc.x, g + 0.2, bc.z), fwd, Vector3.UP, r, Vector3(7.2, 1.4, 6.2), Color(0.6, 0.58, 0.54))
			t._box("wood", Vector3(bc.x, g + 2.5, bc.z), fwd, Vector3.UP, r, Vector3(7.0, 3.6, 6.0), Color(0.36, 0.27, 0.2))
			t._gable(Vector3(bc.x, g + 4.3, bc.z), fwd, r, 7.0, 6.0, 1.8, 0.8, Color(0.33, 0.3, 0.28), Color(0.36, 0.27, 0.2), "wood")
