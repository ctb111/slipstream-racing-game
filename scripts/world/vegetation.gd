class_name Vegetation
extends RefCounted
## Procedural trees and bushes dressed with photo atlases (see
## assets/vegetation/CREDITS_vegetation.txt): Norway spruce, Scots pine, beech,
## oak, birch and leafy bushes. Each tree is grown from a branch skeleton
## (trunk, whorls or limbs, twig fronds / leaf clusters) and emitted twice in
## the same pass: a detailed near mesh and a cheap far mesh with the same
## silhouette, so the LOD switch doesn't change the forest.
##
## Every plant is one surface using shaders/veg_tree.gdshader, so a MultiMesh of
## them is a single draw call. Vertex layout (read by the wind shader):
##   COLOR.r = leaf/needle flutter weight, COLOR.g = ambient occlusion,
##   COLOR.b = 0 foliage / 0.5 bark column 0 / 1.0 bark column 1,
##   COLOR.a = branch weight (0 at the trunk .. 1 at a branch tip),
##   UV2.x   = per-branch phase (0..1), UV2.y = tree height (mesh units).

const DIR := "res://assets/vegetation/trees/"

enum Species { SPRUCE, PINE, BEECH, OAK, BIRCH }

## Conifer atlas (4x4): 0-2 fir top views, 3-5 pine top views,
## 6-11 fir side views, 12-15 pine side views.
const CONIFER_COLS := 4
const FIR_TOP := [0, 1, 2]
const PINE_TOP := [3, 4, 5]
const FIR_SIDE := [6, 7, 8, 9, 10, 11]
const PINE_SIDE := [12, 13, 14, 15]
## Leaf atlas (4x2): 0-1 beech, 2-3 birch, 4-5 oak, 6-7 dense bush sprays.
const LEAF_COLS := 4
const LEAF_ROWS := 2

const BARK0 := 0.5 ## COLOR.b for the left bark column (spruce / beech)
const BARK1 := 1.0 ## COLOR.b for the right bark column (pine / birch)

## Every tree material made, so weather changes can reach them (weak refs).
static var _materials: Array[WeakRef] = []


# ---------------------------------------------------------------- materials

static func _tree_material(leaf: String, bark: String, noise: Texture2D, wind: float, snow: float, wet: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/veg_tree.gdshader")
	m.set_shader_parameter("leaf_tex", load(DIR + leaf + ".png"))
	m.set_shader_parameter("leaf_normal", load(DIR + leaf + "_normal.png"))
	# Dense leaf masses for the baked models (their foliage UVs sit at u + 2).
	var clumps := "leaf_clumps" if leaf == "leaf_atlas" else "conifer_clumps"
	m.set_shader_parameter("clump_tex", load(DIR + clumps + ".png"))
	m.set_shader_parameter("clump_normal", load(DIR + clumps + "_normal.png"))
	m.set_shader_parameter("bark_tex", load(DIR + bark + ".jpg"))
	m.set_shader_parameter("bark_normal", load(DIR + bark + "_normal.jpg"))
	m.set_shader_parameter("noise_tex", noise)
	m.set_shader_parameter("snow", snow)
	m.set_shader_parameter("wet", wet)
	set_material_wind(m, wind)
	_materials = _materials.filter(func(w: WeakRef) -> bool: return w.get_ref() != null)
	_materials.append(weakref(m))
	return m


static func set_material_wind(m: ShaderMaterial, wind: float) -> void:
	m.set_shader_parameter("wind_strength", wind)
	# Gust fronts sweep across the forest at roughly wind speed (8..25 m/s).
	m.set_shader_parameter("gust_speed", 0.03 + wind * 0.07)


## Live weather change for every tree/bush material (wind 0 calm .. 1 storm,
## snow and wet 0..1). Negative values leave that parameter alone.
static func set_weather(wind := -1.0, snow := -1.0, wet := -1.0) -> void:
	for w: WeakRef in _materials:
		var m := w.get_ref() as ShaderMaterial
		if m == null:
			continue
		if wind >= 0.0:
			set_material_wind(m, wind * float(m.get_meta("wind_mul", 1.0)))
		if snow >= 0.0:
			m.set_shader_parameter("snow", snow * float(m.get_meta("snow_mul", 1.0)))
		if wet >= 0.0:
			m.set_shader_parameter("wet", wet)


## Material for spruce and pine meshes.
static func conifer_material(noise: Texture2D, wind: float, snow := 0.0, wet := 0.0) -> ShaderMaterial:
	var m := _tree_material("conifer_atlas", "bark_conifer", noise, wind, snow, wet)
	# The sapling scans are a fresh olive green; mature spruce is darker and bluer.
	m.set_shader_parameter("tint", Vector3(0.56, 0.68, 0.53))
	m.set_shader_parameter("translucency", 0.3)
	m.set_shader_parameter("flutter_amp", 0.45) # needles are stiff, the branches do the moving
	m.set_shader_parameter("branch_amp", 0.55)
	return m


## Material for beech, oak, birch and bushes.
static func broadleaf_material(noise: Texture2D, wind: float, snow := 0.0, wet := 0.0) -> ShaderMaterial:
	var m := _tree_material("leaf_atlas", "bark_broadleaf", noise, wind, snow, wet)
	m.set_shader_parameter("tint", Vector3(0.47, 0.57, 0.34))
	m.set_shader_parameter("translucency", 0.45)
	m.set_shader_parameter("flutter_amp", 1.0)
	m.set_shader_parameter("branch_amp", 0.45)
	return m


# ---------------------------------------------------------------- baked models

const MODEL_DIR := "res://assets/vegetation/trees/models/"
const SPECIES_MODEL := ["spruce", "pine", "beech", "oak", "birch"]
static var _models := {}


## Baked Sapling tree (tools/trees/gen_trees.py): [near mesh, far mesh] for
## e.g. "oak_2", or [] when it isn't there. Same vertex layout as the grown trees.
static func model(name: String) -> Array:
	if _models.has(name):
		return _models[name]
	var res: Array = []
	# --trees_old: the previous grown trees / theme blobs (perf A/B).
	if ResourceLoader.exists(MODEL_DIR + name + "_near.res") and not OS.get_cmdline_user_args().has("--trees_old"):
		res = [load(MODEL_DIR + name + "_near.res"), load(MODEL_DIR + name + "_far.res")]
	_models[name] = res
	return res


## Model for forest species `sp` (Species) and age class `age` (TREE_AGES index).
static func forest_model(sp: int, age: int, autumn := false) -> Array:
	if autumn and sp == Species.BEECH:
		var m := model("maple_%d" % mini(age, 2))
		if not m.is_empty():
			return m
	return model("%s_%d" % [SPECIES_MODEL[sp], age])


# ---------------------------------------------------------------- mesh helpers

## A vertex: [position, normal, uv, Color(flutter, ao, kind, branch weight), phase].
class Builder:
	var st := SurfaceTool.new()
	var height := 10.0

	func _init(h: float) -> void:
		height = h
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func vert(v: Array) -> void:
		st.set_color(v[3])
		st.set_uv(v[2])
		st.set_uv2(Vector2(v[4], height))
		st.set_normal(v[1])
		st.add_vertex(v[0])

	func tri(a: Array, b: Array, c: Array) -> void:
		vert(a)
		vert(b)
		vert(c)

	func quad(a: Array, b: Array, c: Array, d: Array) -> void:
		tri(a, b, c)
		tri(a, c, d)

	func commit() -> ArrayMesh:
		st.generate_tangents()
		return st.commit()


## UV rect of an atlas cell (tiny inset against bleeding).
static func _cell(i: int, cols: int, rows: int) -> Rect2:
	var s := Vector2(1.0 / cols, 1.0 / rows)
	return Rect2(Vector2(i % cols, i / cols) * s + s * 0.004, s * 0.992)


static func _uv(cell: Rect2, u: float, v: float) -> Vector2:
	return cell.position + cell.size * Vector2(u, v)


## Tapered bark tube along a path of points (radius and branch weight per point).
static func _limb(b: Builder, path: Array, radii: Array, weights: Array, sides: int, bark: float, v_scale: float, ao0: float, phase: float) -> void:
	var v_acc := 0.0
	for k in path.size() - 1:
		var p0: Vector3 = path[k]
		var p1: Vector3 = path[k + 1]
		var axis := (p1 - p0).normalized()
		var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
		var fwd := axis.cross(side)
		var v0 := v_acc
		var v1 := v_acc + p0.distance_to(p1) * v_scale
		v_acc = v1
		var ao_a := lerpf(ao0, 1.0, float(k) / path.size())
		var ao_b := lerpf(ao0, 1.0, float(k + 1) / path.size())
		var r0: float = radii[k]
		var r1: float = radii[k + 1]
		var w0: float = weights[k]
		var w1: float = weights[k + 1]
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var d0 := side * cos(a0) + fwd * sin(a0)
			var d1 := side * cos(a1) + fwd * sin(a1)
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			b.quad([p0 + d0 * r0, d0, Vector2(u0, v0), Color(0, ao_a, bark, w0), phase],
				[p1 + d0 * r1, d0, Vector2(u0, v1), Color(0, ao_b, bark, w1), phase],
				[p1 + d1 * r1, d1, Vector2(u1, v1), Color(0, ao_b, bark, w1), phase],
				[p0 + d1 * r0, d1, Vector2(u1, v0), Color(0, ao_a, bark, w0), phase])


## A twig frond: an atlas cell laid along a curved branch starting at `base`,
## heading horizontally along `dir`. Height along it follows
## length * (rise * t + curl * t^2) (negative curl droops, positive turns the
## tip up). The card is folded along its midrib so both halves hang down by
## `fold` radians: it has body from the side as well as from above. Normals
## point away from `centre` (the crown) so the tree shades as one soft mass.
static func _frond(b: Builder, base: Vector3, dir: Vector3, length: float, width: float, rise: float, curl: float, fold: float,
		cell: Rect2, rows: int, w0: float, w1: float, phase: float, ao0: float, centre: Vector3) -> void:
	var grid: Array = []
	var hw := width * 0.5
	for r in rows + 1:
		var t := float(r) / rows
		var p := base + dir * length * t + Vector3.UP * length * (rise * t + curl * t * t)
		var tan := (dir + Vector3.UP * (rise + 2.0 * curl * t)).normalized()
		var side := tan.cross(Vector3.UP).normalized()
		var up := side.cross(tan)
		var out := p - centre
		out.y *= 0.5
		var n := (out.normalized() * 0.75 + up * 0.55).normalized()
		var w := lerpf(w0, w1, t)
		var ao := lerpf(ao0, 1.0, t * 0.75)
		var hang := (side * cos(fold) - up * sin(fold)) * hw
		var hang2 := (-side * cos(fold) - up * sin(fold)) * hw
		grid.append([
			[p + hang, n, _uv(cell, 0.0, 1.0 - t), Color(0.4 + 0.6 * t, ao, 0.0, w), phase],
			[p + up * hw * 0.08, n, _uv(cell, 0.5, 1.0 - t), Color(0.25 * t, minf(1.0, ao * 1.05), 0.0, w), phase],
			[p + hang2, n, _uv(cell, 1.0, 1.0 - t), Color(0.4 + 0.6 * t, ao, 0.0, w), phase],
		])
	for r in rows:
		b.quad(grid[r][0], grid[r + 1][0], grid[r + 1][1], grid[r][1])
		b.quad(grid[r][1], grid[r + 1][1], grid[r + 1][2], grid[r][2])


## A drooping disc of needles (top-view atlas cell mapped planar onto it) -
## the tufts at the ends of pine limbs.
static func _tuft(b: Builder, rng: RandomNumberGenerator, centre: Vector3, radius: float, droop: float, cell: Rect2, segs: int, ao_in: float, w: float, phase: float) -> void:
	var rot := rng.randf() * TAU
	var mid := 0.5
	var rim: Array = []
	var ring: Array = []
	for s in segs:
		var a := rot + TAU * s / segs
		var dir := Vector3(cos(a), 0, sin(a))
		var rr := radius * rng.randf_range(0.82, 1.12)
		var uvd := Vector2(cos(a - rot), sin(a - rot)) * 0.5
		var p_rim := centre + dir * rr + Vector3.DOWN * (droop * rr + rng.randf_range(-0.1, 0.1) * radius)
		var p_mid := centre + dir * rr * mid + Vector3.DOWN * droop * rr * mid * 0.55
		var n_rim := (dir * 0.6 + Vector3.UP).normalized()
		var n_mid := (dir * 0.3 + Vector3.UP).normalized()
		rim.append([p_rim, n_rim, cell.position + cell.size * (Vector2(0.5, 0.5) + uvd), Color(1.0, 1.0, 0.0, 1.0), phase])
		ring.append([p_mid, n_mid, cell.position + cell.size * (Vector2(0.5, 0.5) + uvd * mid), Color(0.5, lerpf(ao_in, 1.0, 0.6), 0.0, lerpf(w, 1.0, 0.5)), phase])
	var c := [centre + Vector3.UP * radius * 0.08, Vector3.UP, cell.get_center(), Color(0.1, ao_in, 0.0, w), phase]
	for s in segs:
		var s1 := (s + 1) % segs
		b.tri(c, ring[s], ring[s1])
		b.quad(ring[s], rim[s], rim[s1], ring[s1])


## Vertical card (side-view cell) split into a grid so it bends: the leader
## at the top of a conifer.
static func _vcard(b: Builder, base: Vector3, yaw: float, width: float, height: float, cell: Rect2, cols: int, rows: int, ao0: float, w0: float, w1: float, phase: float) -> void:
	var right := Vector3(cos(yaw), 0, sin(yaw))
	var face := right.cross(Vector3.UP)
	var grid: Array = []
	for r in rows + 1:
		var fy := float(r) / rows
		var line: Array = []
		for c in cols + 1:
			var fx := float(c) / cols
			var p := base + right * (fx - 0.5) * width + Vector3.UP * fy * height
			var n := (right * (fx - 0.5) * 1.6 + face * 0.3 + Vector3.UP * (fy - 0.2)).normalized()
			var edge := absf(fx - 0.5) * 2.0
			line.append([p, n, _uv(cell, fx, 1.0 - fy), Color(clampf(edge + fy * 0.5, 0.0, 1.0), lerpf(ao0, 1.0, clampf(edge * 0.6 + fy * 0.5, 0.0, 1.0)), 0.0, lerpf(w0, w1, fy)), phase])
		grid.append(line)
	for r in rows:
		for c in cols:
			b.quad(grid[r][c], grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1])


## A leaf-spray card: attached at `at`, pointing along `out`, facing roughly `face`.
static func _spray(b: Builder, at: Vector3, out: Vector3, face: Vector3, size: float, cell: Rect2, crown_n: Vector3, ao: float, w0: float, w1: float, phase: float) -> void:
	var up := out.normalized()
	var right := up.cross(face).normalized()
	if right.length_squared() < 0.01:
		right = up.cross(Vector3.RIGHT).normalized()
	var hw := size * 0.5
	var n := crown_n.normalized()
	b.quad([at - right * hw, n, cell.position + Vector2(0, cell.size.y), Color(0.3, ao, 0.0, w0), phase],
		[at - right * hw + up * size, n, cell.position, Color(1.0, minf(1.0, ao + 0.15), 0.0, w1), phase],
		[at + right * hw + up * size, n, cell.position + Vector2(cell.size.x, 0), Color(1.0, minf(1.0, ao + 0.15), 0.0, w1), phase],
		[at + right * hw, n, cell.position + cell.size, Color(0.3, ao, 0.0, w0), phase])


## Random unit vector.
static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var d := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.UP


## Quadratic Bezier point: limbs are bent through a control point.
static func _bez(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


# ---------------------------------------------------------------- species
# Each generator returns [near: ArrayMesh, far: ArrayMesh] for a tree of height
# `h` (metres before instance scaling). Both LODs are grown from the same
# skeleton in one pass.

## Norway spruce: straight trunk, whorls of drooping branches whose tips turn
## up, each carrying a folded frond; the crown is a tall narrow cone. Old trees
## have a bare lower trunk with a few dead stubs.
static func spruce(rng: RandomNumberGenerator, h: float) -> Array:
	var nb := Builder.new(h)
	var fb := Builder.new(h)
	var young := h < 8.0
	var r := h * rng.randf_range(0.13, 0.16) + 0.75
	var trunk_r := 0.011 * h + 0.04
	var y0 := h * (rng.randf_range(0.02, 0.07) if young else rng.randf_range(0.12, 0.3))
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.012 * h
	var axis := func(y: float) -> Vector3: return Vector3.UP * y + lean * pow(y / h, 2.0)
	var trunk_path: Array = [0.0, 0.3, 0.6, 0.85, 0.99].map(func(f: float) -> Vector3: return axis.call(h * f))
	_limb(nb, trunk_path, [trunk_r * 1.3, trunk_r * 0.85, trunk_r * 0.5, trunk_r * 0.22, 0.02], [0, 0, 0, 0, 0], 5 if young else 7, BARK0, 0.35, 0.35, 0.0)
	_limb(fb, [axis.call(0.0), axis.call(y0 + h * 0.2), axis.call(h * 0.9)], [trunk_r * 1.2, trunk_r * 0.6, 0.03], [0, 0, 0], 3, BARK0, 0.35, 0.4, 0.0)
	# Dead stubs on the shaded lower trunk.
	if not young:
		for k in clampi(int(y0 * 1.6), 0, 12):
			var y := rng.randf_range(1.2, y0)
			var a := rng.randf() * TAU
			var d := Vector3(cos(a), rng.randf_range(-0.35, 0.05), sin(a)).normalized()
			var p := axis.call(y) as Vector3
			_limb(nb, [p, p + d * rng.randf_range(0.3, 1.1)], [0.035, 0.008], [0.0, 0.15], 3, BARK0, 0.8, 0.4, rng.randf())
	var centre_y := (y0 + h) * 0.45
	# Leader: two crossed cards at the tip.
	var lead := minf(2.4, h * 0.16 + 0.3)
	var lyaw := rng.randf() * PI
	for c in 2:
		var cell := _cell(FIR_SIDE[rng.randi() % FIR_SIDE.size()], CONIFER_COLS, 4)
		var lp: Vector3 = axis.call(h - lead)
		_vcard(nb, lp, lyaw + c * PI * 0.5, lead * 0.8, lead * 1.08, cell, 1, 2, 0.8, 0.35, 1.0, 0.3 + c * 0.3)
		if c == 0:
			_vcard(fb, lp, lyaw + PI * 0.25, lead * 0.9, lead * 1.08, cell, 1, 1, 0.8, 0.35, 1.0, 0.3)
	var y := h - lead * 0.55
	var wi := 0
	while y > y0:
		var f := clampf((h - y) / maxf(h - y0, 0.1), 0.0, 1.0) # 0 top .. 1 crown base
		var length := (r * pow(f, 0.8) + 0.35) * rng.randf_range(0.85, 1.1)
		var n := rng.randi_range(5, 7) if f > 0.2 else rng.randi_range(4, 5)
		var rot := rng.randf() * TAU
		var rise := lerpf(0.3, -0.5, f)
		var curl := lerpf(-0.08, 0.34, f)
		var far_whorl := wi % 2 == 0
		var at: Vector3 = axis.call(y)
		var ctr := Vector3(at.x, centre_y, at.z)
		for k in n:
			var a := rot + TAU * k / n + rng.randf_range(-0.3, 0.3)
			var dir := Vector3(cos(a), 0, sin(a))
			var lk := length * rng.randf_range(0.85, 1.1)
			var cell := _cell(FIR_SIDE[rng.randi() % FIR_SIDE.size()], CONIFER_COLS, 4)
			var fold := rng.randf_range(0.45, 0.7) + f * 0.35
			var ph := rng.randf()
			var rs := rise + rng.randf_range(-0.1, 0.1)
			var base := at + dir * trunk_r * (1.0 - y / h)
			var ao0 := lerpf(0.6, 0.28, f)
			_frond(nb, base, dir, lk * 1.08, lk * rng.randf_range(0.9, 1.1), rs, curl, fold, cell, 2, 0.05, 1.0, ph, ao0, ctr)
			if far_whorl:
				if k % 3 != 2:
					_frond(fb, base, dir, lk * 1.1, lk * 1.25, rs, curl, fold, cell, 1, 0.05, 1.0, ph, ao0, ctr)
		y -= clampf(length * 0.22, 0.26, 0.95) * rng.randf_range(0.85, 1.15)
		wi += 1
	return [nb.commit(), fb.commit()]


## Scots pine. Young trees are loose cones; mature ones have a tall bare,
## slightly sinuous trunk and an irregular flat-topped crown of rising limbs
## ending in needle tufts.
static func pine(rng: RandomNumberGenerator, h: float) -> Array:
	var nb := Builder.new(h)
	var fb := Builder.new(h)
	var young := h < 11.0
	var trunk_r := 0.012 * h + 0.05
	var r := h * rng.randf_range(0.14, 0.18) + 0.8
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.025 * h
	var wob := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.25
	var axis := func(y: float) -> Vector3:
		var f := y / h
		return Vector3.UP * y + lean * pow(f, 1.5) + wob * sin(f * PI * 2.0)
	var crown0 := h * (rng.randf_range(0.08, 0.25) if young else rng.randf_range(0.5, 0.66))
	var trunk_path: Array = [0.0, 0.25, 0.5, 0.75, 0.97].map(func(f: float) -> Vector3: return axis.call(h * f))
	_limb(nb, trunk_path, [trunk_r * 1.25, trunk_r * 0.9, trunk_r * 0.7, trunk_r * 0.4, 0.03], [0, 0, 0, 0, 0], 5 if young else 7, BARK1, 0.3, 0.4, 0.0)
	_limb(fb, [axis.call(0.0), axis.call(crown0), axis.call(h * 0.92)], [trunk_r * 1.2, trunk_r * 0.75, 0.04], [0, 0, 0], 3, BARK1, 0.3, 0.45, 0.0)
	var ctr: Vector3 = axis.call((crown0 + h) * 0.5)
	if young:
		# Loose cone of ascending branches.
		var y := h * 0.94
		var wi := 0
		while y > crown0:
			var f := clampf((h - y) / maxf(h - crown0, 0.1), 0.0, 1.0)
			var length := (r * 0.9 * pow(f, 0.75) + 0.4) * rng.randf_range(0.85, 1.1)
			var n := rng.randi_range(3, 5)
			var rot := rng.randf() * TAU
			var at: Vector3 = axis.call(y)
			for k in n:
				var a := rot + TAU * k / n + rng.randf_range(-0.35, 0.35)
				var dir := Vector3(cos(a), 0, sin(a))
				var lk := length * rng.randf_range(0.85, 1.1)
				var cell := _cell(PINE_SIDE[rng.randi() % PINE_SIDE.size()], CONIFER_COLS, 4)
				var ph := rng.randf()
				var rs := lerpf(0.55, 0.05, f) + rng.randf_range(-0.1, 0.1)
				var fold := rng.randf_range(0.35, 0.6)
				_frond(nb, at, dir, lk, lk * 0.85, rs, -0.08, fold, cell, 2, 0.05, 1.0, ph, 0.45, ctr)
				if wi % 2 == 0 or h < 7.0:
					_frond(fb, at, dir, lk * 1.05, lk, rs, -0.08, fold, cell, 1, 0.05, 1.0, ph, 0.45, ctr)
			y -= clampf(length * 0.4, 0.45, 1.2) * rng.randf_range(0.85, 1.2)
			wi += 1
		var tcell := _cell(PINE_SIDE[rng.randi() % PINE_SIDE.size()], CONIFER_COLS, 4)
		_vcard(nb, axis.call(h * 0.85), rng.randf() * PI, h * 0.2, h * 0.17, tcell, 1, 2, 0.8, 0.3, 1.0, 0.5)
		return [nb.commit(), fb.commit()]
	# Mature: dead stubs, then limbs out to needle clumps filling a flattish,
	# irregular crown.
	for k in rng.randi_range(3, 7):
		var y := rng.randf_range(2.0, crown0)
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(-0.2, 0.25), sin(a)).normalized()
		var p := axis.call(y) as Vector3
		_limb(nb, [p, p + d * rng.randf_range(0.3, 0.9)], [0.04, 0.01], [0.0, 0.1], 3, BARK1, 0.8, 0.45, rng.randf())
	var crown_h := h - crown0
	var n_cl := clampi(int(r * crown_h * 0.42), 9, 17)
	var ga := rng.randf() * TAU
	var csize := clampf(h / 18.0, 0.8, 1.2)
	for i in n_cl:
		var f := (i + rng.randf()) / n_cl # 0 crown base .. 1 top
		var a := ga + i * 2.4 + rng.randf_range(-0.4, 0.4)
		var dh := Vector3(cos(a), 0, sin(a))
		var y := crown0 + crown_h * lerpf(0.12, 0.93, f)
		var rad := (r * (1.0 - f * f * 0.65) * rng.randf_range(0.5, 1.0)) + 0.3
		var start: Vector3 = axis.call(lerpf(crown0 * 0.97, y, 0.5))
		var tip: Vector3 = axis.call(y) + dh * rad
		var mid := start.lerp(tip, 0.5) + Vector3.UP * rad * 0.12 + _rand_dir(rng) * rad * 0.12
		var ph := rng.randf()
		_limb(nb, [start, mid, tip], [trunk_r * 0.36 * (1.0 - f * 0.5), trunk_r * 0.2, 0.03], [0.0, 0.35, 0.7], 4, BARK1, 0.5, 0.5, ph)
		if i % 2 == 0 and rad > 2.0:
			_limb(fb, [start, tip], [trunk_r * 0.3, 0.04], [0.0, 0.7], 3, BARK1, 0.5, 0.5, ph)
		var cs := rng.randf_range(1.3, 2.0) * csize
		var tcell := _cell(PINE_TOP[rng.randi() % PINE_TOP.size()], CONIFER_COLS, 4)
		var droop := rng.randf_range(0.3, 0.5)
		var st := rng.state
		_tuft(nb, rng, tip + Vector3.UP * cs * 0.2, cs, droop, tcell, 7, 0.55, 0.8, ph)
		rng.state = st
		_tuft(fb, rng, tip + Vector3.UP * cs * 0.2, cs * 1.1, droop, tcell, 5, 0.55, 0.8, ph)
		for j in 3:
			var t := lerpf(0.55, 1.0, j * 0.5)
			var at := _bez(start, mid, tip, t)
			var fdir := dh.rotated(Vector3.UP, rng.randf_range(-1.2, 1.2))
			var fl := cs * rng.randf_range(0.9, 1.3)
			var cell := _cell(PINE_SIDE[rng.randi() % PINE_SIDE.size()], CONIFER_COLS, 4)
			var rs := rng.randf_range(0.15, 0.6)
			var fold := rng.randf_range(0.3, 0.6)
			_frond(nb, at, fdir, fl, fl * 0.95, rs, -0.15, fold, cell, 2, lerpf(0.35, 0.75, t), 1.0, ph, 0.5, ctr)
			if j == 1:
				_frond(fb, at, fdir, fl * 1.2, fl * 1.15, rs, -0.15, fold, cell, 1, 0.6, 1.0, ph, 0.5, ctr)
	# Apex clump.
	var acell := _cell(PINE_TOP[rng.randi() % PINE_TOP.size()], CONIFER_COLS, 4)
	_tuft(nb, rng, axis.call(h * 0.96), r * 0.3 + 0.5, 0.35, acell, 7, 0.6, 0.6, 0.5)
	_tuft(fb, rng, axis.call(h * 0.96), r * 0.3 + 0.5, 0.35, acell, 5, 0.6, 0.6, 0.5)
	return [nb.commit(), fb.commit()]


## Broadleaf tree (BEECH, OAK or BIRCH): trunk and scaffold limbs, with leaf
## clumps spread through the crown volume, each on a twig from the nearest
## limb; the gaps between clumps give a natural, broken silhouette. Birch is
## slender with hanging sprays; oak has crooked, spreading limbs and a broad
## crown; beech an upright oval crown.
static func broadleaf(rng: RandomNumberGenerator, h: float, kind: int) -> Array:
	var nb := Builder.new(h)
	var fb := Builder.new(h)
	var birch := kind == Species.BIRCH
	var oak := kind == Species.OAK
	var young := h < 7.5
	var bark := BARK1 if birch else BARK0
	var cells: Array = [2, 3] if birch else ([4, 5] if oak else [0, 1])
	var trunk_r := (0.008 if birch else (0.016 if oak else 0.012)) * h + 0.05
	var r := (h * (0.16 if birch else (0.29 if oak else 0.24)) + 0.9) * rng.randf_range(0.88, 1.1)
	var fork := h * (rng.randf_range(0.22, 0.36) if birch else (rng.randf_range(0.2, 0.3) if oak else rng.randf_range(0.22, 0.34)))
	if young:
		r = h * 0.24 + 0.5
		fork = h * 0.25
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * (0.03 if birch else 0.015) * h
	var axis := func(y: float) -> Vector3: return Vector3.UP * y + lean * pow(y / h, 1.5)
	var ry := (h - fork) * 0.5
	var centre: Vector3 = axis.call(fork + ry)
	var top := h * (0.75 if oak else 0.94)
	var trunk_path: Array = [0.0, fork * 0.5, fork, lerpf(fork, top, 0.5), top].map(func(y: float) -> Vector3: return axis.call(y))
	_limb(nb, trunk_path, [trunk_r * 1.3, trunk_r, trunk_r * 0.8, trunk_r * 0.42, 0.04], [0, 0, 0, 0.1, 0.3], 5 if young or birch else 7, bark, 0.4 if not birch else 0.9, 0.4, 0.0)
	_limb(fb, [axis.call(0.0), axis.call(fork), centre], [trunk_r * 1.2, trunk_r * 0.8, trunk_r * 0.4], [0, 0, 0], 3, bark, 0.4, 0.45, 0.0)
	# Scaffold limbs: [start, mid, tip, phase, radius].
	var limbs: Array = []
	var nl := rng.randi_range(6, 8) if birch else (3 if young else rng.randi_range(5, 7))
	var ga := rng.randf() * TAU
	for i in nl:
		var a := ga + i * 2.4 + rng.randf_range(-0.35, 0.35)
		var dh := Vector3(cos(a), 0, sin(a))
		var fy := (i + rng.randf()) / nl
		var ys := lerpf(fork, fork + (h - fork) * 0.5, fy)
		var up_ang := rng.randf_range(0.7, 1.1) if birch else (rng.randf_range(0.15, 0.5) if oak else rng.randf_range(0.45, 0.9))
		var length := r * rng.randf_range(0.7, 0.9)
		var start: Vector3 = axis.call(ys)
		var tip := start + dh * length * cos(up_ang) + Vector3.UP * length * sin(up_ang)
		tip.y = minf(tip.y, h - 1.0)
		var mid := start.lerp(tip, 0.5) + Vector3.UP * length * 0.1 + _rand_dir(rng) * length * (0.18 if oak else 0.08)
		var ph := rng.randf()
		var lr := trunk_r * (0.4 if birch else 0.5) * (1.0 - fy * 0.4)
		_limb(nb, [start, mid, tip], [lr, lr * 0.55, 0.04], [0.0, 0.25, 0.55], 4 if birch else 5, bark, 0.5, 0.45, ph)
		if not birch and length > 3.0 and i % 2 == 0:
			_limb(fb, [start, tip], [lr * 0.8, 0.05], [0.0, 0.5], 3, bark, 0.5, 0.45, ph)
		limbs.append([start, mid, tip, ph, lr])
	# Leaf clumps through the crown, denser towards the shell: [pos, radius, phase].
	var clumps: Array = []
	var n_cl := clampi(int(r * ry * 0.95), 7, 32)
	for i in n_cl:
		var d := Vector3(rng.randfn(), rng.randfn() * 0.85, rng.randfn()).normalized()
		var shell := pow(rng.randf(), 0.3) * 0.72 + 0.2
		var cp := centre + Vector3(d.x * r, d.y * ry, d.z * r) * shell
		# Twig from the nearest point on a limb (or the trunk).
		var best: Vector3 = axis.call(clampf(cp.y, fork, top))
		var bph := rng.randf()
		var blr := trunk_r * 0.3
		for l: Array in limbs:
			for t in [0.5, 0.75, 1.0]:
				var lp := _bez(l[0], l[1], l[2], t)
				if lp.distance_squared_to(cp) < best.distance_squared_to(cp):
					best = lp
					bph = l[3]
					blr = l[4] * (1.0 - t * 0.6)
		var ph := fmod(bph + rng.randf_range(0.0, 0.3), 1.0)
		if best.distance_to(cp) > 0.6:
			_limb(nb, [best, cp], [maxf(blr * 0.6, 0.03), 0.015], [0.45, 0.8], 3, bark, 0.6, 0.5, ph)
		clumps.append([cp, r * rng.randf_range(0.28, 0.4), ph])
	var size := (1.35 if birch else (1.8 if oak else 1.65)) * clampf(h / 15.0, 0.7, 1.15)
	for c: Array in clumps:
		var cp: Vector3 = c[0]
		var cr: float = c[1]
		var ph: float = c[2]
		var ns := clampi(int(cr * 7.0), 7, 16)
		var outward := (cp - centre)
		outward = outward.normalized() if outward.length_squared() > 0.01 else Vector3.UP
		for s in ns:
			var jd := _rand_dir(rng)
			var at := cp + jd * cr * rng.randf_range(0.1, 0.55)
			var out := (jd + outward * 0.8 + (Vector3.DOWN * 0.7 if birch else Vector3.UP * 0.3)).normalized()
			var face := out.cross(Vector3.UP).rotated(out, rng.randf() * TAU)
			if face.length_squared() < 0.01:
				face = Vector3.FORWARD
			var sz := size * rng.randf_range(0.8, 1.2)
			var n := ((at - centre).normalized() * 0.8 + (at - cp).normalized() * 0.4 + Vector3.UP * 0.25).normalized()
			var shell := clampf(Vector2(at.x - centre.x, at.z - centre.z).length() / r + (at.y - centre.y) / (ry * 2.5), 0.0, 1.2)
			var ao := clampf(0.4 + shell * 0.5, 0.35, 1.0)
			var cell := _cell(cells[rng.randi() % cells.size()], LEAF_COLS, LEAF_ROWS)
			_spray(nb, at - out * sz * 0.3, out, face, sz, cell, n, ao, 0.7, 1.0, ph)
			if s < 2:
				var fsz := sz * 2.2
				_spray(fb, cp + jd * cr * 0.2 - out * fsz * 0.35, out, face, fsz, cell, n, ao, 0.7, 1.0, ph)
	return [nb.commit(), fb.commit()]


## Leafy trackside bush (hazel/dogwood-like), ~1 m radius before scaling.
static func bush(rng: RandomNumberGenerator, radius := 1.0) -> ArrayMesh:
	var b := Builder.new(radius * 1.2)
	# A few woody stems, then sprays from inside the crown pointing outwards in
	# all directions (darker inside), so it reads as a rounded mass of leaves.
	for k in 4:
		var a := rng.randf() * TAU
		var tip := Vector3(cos(a) * 0.45, rng.randf_range(0.6, 1.0), sin(a) * 0.45) * radius
		_limb(b, [Vector3.ZERO, tip], [0.035 * radius, 0.012], [0.0, 0.6], 3, BARK0, 0.8, 0.4, rng.randf())
	var centre := Vector3(0, radius * 0.55, 0)
	var n := rng.randi_range(26, 32)
	for k in n:
		var d := Vector3(rng.randfn(), absf(rng.randfn()) * 0.9 + 0.1, rng.randfn()).normalized()
		var shell := rng.randf_range(0.25, 0.6)
		var at := centre + Vector3(d.x, d.y * 0.6 - 0.25, d.z) * radius * shell
		var out := (d + Vector3.UP * 0.25).normalized()
		var face := out.cross(Vector3.UP).rotated(out, rng.randf() * TAU)
		if face.length_squared() < 0.01:
			face = Vector3.FORWARD
		var cell := 6 + rng.randi() % 2 if rng.randf() < 0.6 else rng.randi() % 2
		_spray(b, at, out, face, radius * rng.randf_range(0.9, 1.25), _cell(cell, LEAF_COLS, LEAF_ROWS), d + Vector3.UP * 0.4,
			clampf(0.35 + d.y * 0.5, 0.3, 1.0), 0.4, 1.0, rng.randf())
	return b.commit()


## Undergrowth bush for the baked forest: a dozen big cards of the dense leaf
## masses (leaf_clumps cells, foliage UVs at u + 2), crossed and facing out of a
## low dome, so it reads solid from every side for ~24 triangles. `kind` 0 hazel,
## 1 beech scrub, 2 birch/willow scrub. Unindexed (rides the forest's far merge).
static func bush_dense(rng: RandomNumberGenerator, radius := 1.0, kind := 0) -> ArrayMesh:
	var cells: Array = [[6, 7, 6], [0, 1, 6], [2, 3, 7]][kind % 3]
	var b := Builder.new(radius * 1.4)
	var centre := Vector3(0, radius * 0.55, 0)
	var n := 12
	for k in n:
		var cell := _cell(int(cells[rng.randi() % cells.size()]), 4, 4)
		cell.position += Vector2(2.0, 0.0)
		var d: Vector3
		if k < 3: # crossed core
			var a := float(k) * PI / 3.0 + rng.randf() * 0.4
			d = Vector3(cos(a), 0.15, sin(a))
		else:
			var a := rng.randf() * TAU
			d = Vector3(cos(a), rng.randf_range(0.05, 0.75), sin(a)).normalized()
		var out := Vector3(d.x, 0.0, d.z).normalized() if k >= 3 else Vector3(-d.z, 0.0, d.x)
		var up := (Vector3.UP + Vector3(d.x, 0.0, d.z) * 0.35).normalized()
		var right := up.cross(out).normalized()
		var size := radius * rng.randf_range(1.7, 2.2) * (1.15 if k < 3 else 1.0)
		var base := centre + Vector3(d.x, 0.0, d.z) * radius * (0.0 if k < 3 else rng.randf_range(0.25, 0.5)) - up * size * 0.45 + Vector3.UP * rng.randf_range(-0.1, 0.1) * radius
		var hw := size * 0.5
		var nrm := (out + Vector3.UP * 0.5).normalized() if k >= 3 else Vector3.UP
		var ao0 := 0.45 if k < 3 else 0.6
		var ph := rng.randf()
		b.quad([base - right * hw, nrm, cell.position + Vector2(0, cell.size.y), Color(0.3, ao0, 0.0, 0.2), ph],
			[base - right * hw + up * size, nrm, cell.position, Color(1.0, 1.0, 0.0, 0.8), ph],
			[base + right * hw + up * size, nrm, cell.position + Vector2(cell.size.x, 0), Color(1.0, 1.0, 0.0, 0.8), ph],
			[base + right * hw, nrm, cell.position + cell.size, Color(0.3, ao0, 0.0, 0.2), ph])
	return b.commit()


# ---------------------------------------------------------------- placement helpers

## Buckets exclusion zones ([centre, radius] pairs) into a 2D grid of `cell`
## metres so a point only tests the few zones near it.
static func zone_grid(zones: Array, cell: float, scale := 1.0) -> Dictionary:
	var g := {}
	for z: Array in zones:
		var c: Vector3 = z[0]
		var r: float = z[1] * scale
		for x in range(floori((c.x - r) / cell), floori((c.x + r) / cell) + 1):
			for y in range(floori((c.z - r) / cell), floori((c.z + r) / cell) + 1):
				var k := Vector2i(x, y)
				if not g.has(k):
					g[k] = []
				g[k].append([c, r])
	return g


static func in_zone(g: Dictionary, p: Vector3, cell: float) -> bool:
	var zs = g.get(Vector2i(floori(p.x / cell), floori(p.z / cell)))
	if zs == null:
		return false
	for z: Array in zs:
		if p.distance_to(z[0]) < z[1]:
			return true
	return false


## Grid cells (of `cell` metres) that come within `radius` of the curve.
static func near_curve_grid(curve: Curve3D, radius: float, cell: float) -> Dictionary:
	var g := {}
	var length := curve.get_baked_length()
	var r := radius + cell
	var step := cell * 0.5
	var off := 0.0
	while off < length:
		var p := curve.sample_baked(off)
		for x in range(floori((p.x - r) / cell), floori((p.x + r) / cell) + 1):
			for y in range(floori((p.z - r) / cell), floori((p.z + r) / cell) + 1):
				g[Vector2i(x, y)] = true
		off += step
	return g
