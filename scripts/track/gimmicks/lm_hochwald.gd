extends RefCounted
## Hochwald's own landmarks (called from dress_hochwald.gd):
##   ski_jump   "Hochwaldschanze": a summer ski jump inside the loop: concrete
##              in-run on columns with the stair flight beside it, start hut,
##              take-off table, earth landing hill with green plastic matting
##              and distance lines, judges' tower and floodlight masts.
##   log_yard   a forestry timber yard: long piles of spruce logs (bark ends,
##              pale sawn faces), skid timbers, a parked forwarder trailer.
##   high_seat  a hunter's high seat (Hochsitz) at the forest edge.
## Materials: Mats photo PBR sets + the forest's own conifer bark photo.

const BARK_TEX := "res://assets/vegetation/trees/bark_conifer.jpg"
const BARK_NRM := "res://assets/vegetation/trees/bark_conifer_normal.jpg"
const GRASS_TEX := "res://assets/textures/grass_ground/grass_ground_diff_2k.jpg"
const GRASS_NRM := "res://assets/textures/grass_ground/grass_ground_nor_2k.jpg"

static var _bark: StandardMaterial3D
static var _grass: StandardMaterial3D


static func bark_mat() -> StandardMaterial3D:
	if _bark == null:
		_bark = StandardMaterial3D.new()
		_bark.albedo_texture = load(BARK_TEX)
		_bark.normal_enabled = true
		_bark.normal_texture = load(BARK_NRM)
		_bark.uv1_triplanar = true
		_bark.uv1_world_triplanar = true
		_bark.uv1_scale = Vector3(0.9, 0.9, 0.9)
		_bark.roughness = 0.95
		_bark.vertex_color_use_as_albedo = true
		_bark.albedo_color = Color(0.85, 0.8, 0.75)
	return _bark


static func grass_mat() -> StandardMaterial3D:
	if _grass == null:
		_grass = StandardMaterial3D.new()
		_grass.albedo_texture = load(GRASS_TEX)
		_grass.normal_enabled = true
		_grass.normal_texture = load(GRASS_NRM)
		_grass.uv1_triplanar = true
		_grass.uv1_world_triplanar = true
		_grass.uv1_scale = Vector3(0.25, 0.25, 0.25)
		_grass.roughness = 0.95
		_grass.vertex_color_use_as_albedo = true
		_grass.albedo_color = Color(0.74, 0.76, 0.44)
	return _grass


## Swap the placeholder material of a committed GxGeo part.
static func _override(c: Node3D, node_name: String, part: String, m: Material) -> void:
	var n := c.get_node_or_null(NodePath("%s_%s" % [node_name, part]))
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_override = m


## Smallest distance from any of `pts` (world) to the road centreline.
static func _min_track_dist(c: Node3D, pts: Array) -> float:
	var d := INF
	var cv := Gx.curve(c)
	for p: Vector3 in pts:
		var q := cv.get_closest_point(p)
		d = minf(d, Vector2(p.x - q.x, p.z - q.z).length())
	return d


static func _reserved(c: Node3D, p: Vector3, r: float) -> bool:
	for z: Array in c.get_meta("no_trees", []):
		var q: Vector3 = z[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < float(z[1]) + r and float(z[1]) < 100.0:
			return true
	return false


# ------------------------------------------------------------------ ski jump

## Try the candidate spots (world xz) and headings; build at the first that fits.
static func ski_jump(c: Node3D, spots: Array, headings: Array) -> bool:
	for s: Vector2 in spots:
		for hd: float in headings:
			var dir := Vector3(cos(hd), 0, sin(hd))
			var o := Vector3(s.x, 0, s.y)
			o.y = Gx.ground(c, o)
			var foot := []
			for x: float in [-62.0, -40.0, -20.0, 0.0, 20.0, 40.0, 62.0]:
				for z: float in [-20.0, 0.0, 20.0]:
					foot.append(o + dir * x + dir.cross(Vector3.UP) * z)
			if _min_track_dist(c, foot) < 26.0:
				continue
			var bad := false
			for p: Vector3 in foot:
				if _reserved(c, p, 2.0):
					bad = true
					break
			if bad:
				continue
			_build_jump(c, Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), o))
			for x: float in [-50.0, -25.0, 0.0, 25.0, 50.0]:
				Gx.reserve(c, o + dir * x, 26.0)
			if OS.get_cmdline_user_args().has("--debug-dress"):
				print("DRESS ski jump at ", o.snapped(Vector3.ONE), " heading ", hd)
			return true
	return false


static func _build_jump(c: Node3D, xf: Transform3D) -> void:
	var g := GxGeo.new(xf)
	var gl := func(x: float, z: float) -> float:
		return Gx.ground(c, xf * Vector3(x, 0, z)) - xf.origin.y
	const T := 19.0 # take-off edge above the origin ground
	# --- in-run centreline, walked backwards from the take-off edge
	var pts: Array[Vector3] = []
	var p := Vector3(0, T, 0)
	pts.append(p)
	var walked := 0.0
	while walked < 72.0:
		var ang: float
		if walked < 7.0:
			ang = 10.0
		elif walked < 29.0:
			ang = lerpf(10.0, 35.0, (walked - 7.0) / 22.0)
		else:
			ang = 35.0
		var a := deg_to_rad(ang)
		p += Vector3(-cos(a), sin(a), 0) * 2.0
		walked += 2.0
		pts.append(p)
	pts.reverse() # top first
	var top := pts[0]
	# deck, ice tracks, side walls, railings
	g.col = Color(0.86, 0.85, 0.82)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var n := Vector3(-d.y, d.x, 0)
		if n.y < 0.0:
			n = -n
		var ext := d * 0.06
		g.col = Color(0.86, 0.85, 0.82)
		g.beam("concrete", a - ext - n * 0.35, b + ext - n * 0.35, 3.4, 0.7)
		for z: float in [-1.75, 1.75]: # kerb walls
			g.beam("concrete", a - ext + n * 0.2 + Vector3(0, 0, z), b + ext + n * 0.2 + Vector3(0, 0, z), 0.18, 0.5)
		g.col = Color(0.93, 0.94, 0.95)
		for z: float in [-0.55, 0.55]: # ceramic in-run tracks
			g.beam("painted_metal", a + n * 0.08 + Vector3(0, 0, z), b + n * 0.08 + Vector3(0, 0, z), 0.32, 0.12)
		g.col = Color(0.55, 0.57, 0.58)
		for z: float in [-1.85, 1.85]: # railing tube
			g.bar("steel", a + n * 1.15 + Vector3(0, 0, z), b + n * 1.15 + Vector3(0, 0, z), 0.035, 5)
		if i % 2 == 0:
			for z: float in [-1.85, 1.85]:
				g.bar("steel", a + n * 0.4 + Vector3(0, 0, z), a + n * 1.15 + Vector3(0, 0, z), 0.03, 4)
	# stair flight beside the in-run (z = +2.6), steps every 0.38 m of rise
	g.col = Color(0.78, 0.77, 0.74)
	var acc := 0.0
	for i in pts.size() - 1:
		var a := pts[i] + Vector3(0, -0.4, 2.65)
		var b := pts[i + 1] + Vector3(0, -0.4, 2.65)
		g.beam("concrete", a, b, 1.2, 0.25)
		var rise := a.y - b.y
		var k := 0
		while acc < rise:
			var q := a.lerp(b, acc / rise)
			g.box("concrete", q + Vector3(0, 0.16, 0), Vector3(0.36, 0.2, 1.1))
			acc += 0.38
			k += 1
		acc -= rise
		g.col = Color(0.55, 0.57, 0.58)
		g.bar("steel", a + Vector3(0, 1.0, 0.6), b + Vector3(0, 1.0, 0.6), 0.03, 4)
		g.col = Color(0.78, 0.77, 0.74)
	# columns: frames every ~7 m of run, down to the ground, with cross beams
	g.col = Color(0.8, 0.79, 0.76)
	var i := 0
	while i < pts.size() - 4:
		var q := pts[i]
		for z: float in [-1.3, 1.3]:
			var gy: float = gl.call(q.x, z)
			var h := q.y - 0.8 - gy
			if h > 1.0:
				g.box("concrete", Vector3(q.x, gy + h * 0.5 - 0.5, z), Vector3(0.75, h + 1.0, 0.75), 0.06)
				g.collide(Vector3(q.x, gy + h * 0.5, z), Vector3(0.8, h, 0.8))
		var gy0: float = gl.call(q.x, 0.0)
		var y := gy0 + 9.0
		while y < q.y - 3.0:
			g.box("concrete", Vector3(q.x, y, 0), Vector3(0.55, 0.6, 3.3), 0.04)
			y += 9.0
		g.box("concrete", Vector3(q.x, q.y - 1.0, 0), Vector3(0.9, 0.6, 3.6), 0.05)
		i += 4
	# start hut on a platform at the top
	g.col = Color(0.84, 0.83, 0.8)
	g.box("concrete", top + Vector3(-3.0, -0.4, 0), Vector3(7.0, 0.5, 7.5), 0.05)
	g.col = Color(0.62, 0.48, 0.34)
	g.box("painted_wood", top + Vector3(-4.0, 1.6, 0), Vector3(4.2, 3.4, 5.0), 0.05)
	g.col = Color(0.3, 0.32, 0.34)
	g.box("glass", top + Vector3(-1.88, 2.0, 0), Vector3(0.05, 1.3, 3.6))
	g.col = Color(0.32, 0.33, 0.34)
	g.box("slate", top + Vector3(-4.0, 3.55, 0), Vector3(5.2, 0.4, 6.0), 0.08, Basis(Vector3.BACK, 0.12))
	for z: float in [-3.6, 3.6]:
		g.col = Color(0.55, 0.57, 0.58)
		g.bar("steel", top + Vector3(-6.4, -0.2, z), top + Vector3(0.4, -0.2, z), 0.04, 4)
		g.bar("steel", top + Vector3(-6.4, 0.9, z), top + Vector3(0.4, 0.9, z), 0.04, 4)
	# flag masts on the hut
	for z: float in [-3.2, 3.2]:
		g.col = Color(0.85, 0.85, 0.86)
		g.bar("painted_metal", top + Vector3(-6.2, -0.2, z), top + Vector3(-6.2, 9.0, z), 0.06, 6)
	# take-off table front face + sponsor board under the lip
	g.col = Color(0.84, 0.83, 0.8)
	var gy_o: float = gl.call(0.0, 0.0)
	g.box("concrete", Vector3(-1.5, (T + gy_o) * 0.5 - 1.0, 0), Vector3(3.0, T - gy_o + 1.0, 4.2), 0.08)
	g.collide(Vector3(-1.5, (T + gy_o) * 0.5, 0), Vector3(3.0, T - gy_o, 4.2))
	g.sign(Vector3(0.02, T - 2.2, 0), Vector3(1, 0, 0), 4.0, 0.0, "b_kronen", Vector3.UP)
	g.sign(Vector3(-1.5, T - 5.0, 2.12), Vector3(0, 0, 1), 2.8, 0.0, "b_falke", Vector3.UP)
	g.sign(Vector3(-1.5, T - 5.0, -2.12), Vector3(0, 0, -1), 2.8, 0.0, "b_falke", Vector3.UP)
	# --- landing hill: earth mound, plastic matting band, distance lines
	var hill_h := T - 2.6
	var hill := func(x: float) -> float: # height above local ground, x >= 0
		if x <= 2.0:
			return hill_h
		var u := clampf((x - 2.0) / 52.0, 0.0, 1.0)
		var s := u * u * (3.0 - 2.0 * u)
		return hill_h * (1.0 - s)
	var surf := func(x: float, z: float) -> float:
		var w := 12.0 + x * 0.12 # matting half width
		var edge := clampf((absf(z) - w) / 9.0, 0.0, 1.0)
		var base: float = gl.call(x, z)
		return base + float(hill.call(x)) * (1.0 - edge * edge * (3.0 - 2.0 * edge)) - 0.15
	var st_mat := SurfaceTool.new()
	var st_grass := SurfaceTool.new()
	st_mat.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs: Array[float] = []
	var x := -1.0
	while x <= 66.0:
		xs.append(x)
		x += 2.5 if x < 40.0 else 4.0
	var zs: Array[float] = []
	for k in 25:
		zs.append(-30.0 + k * 2.5)
	var grid: Array = []
	for xx: float in xs:
		var row: Array[Vector3] = []
		for zz: float in zs:
			row.append(Vector3(xx, surf.call(xx, zz), zz))
		grid.append(row)
	for a in xs.size() - 1:
		for b in zs.size() - 1:
			var v00: Vector3 = grid[a][b]
			var v01: Vector3 = grid[a][b + 1]
			var v10: Vector3 = grid[a + 1][b]
			var v11: Vector3 = grid[a + 1][b + 1]
			var zc := absf((zs[b] + zs[b + 1]) * 0.5)
			var w := 12.0 + xs[a] * 0.12
			var st := st_mat if zc < w and xs[a] < 58.0 else st_grass
			var nrm := (v01 - v00).cross(v10 - v00).normalized()
			if nrm.y < 0.0:
				nrm = -nrm
			var shade := Color(1, 1, 1)
			if st == st_mat and (xs[a] > 6.0 and absf(fposmod(xs[a], 5.0)) < 0.01):
				shade = Color(1, 1, 1)
			for v: Vector3 in [v00, v11, v01, v00, v10, v11]:
				st.set_color(shade)
				st.set_normal(xf.basis * nrm)
				st.add_vertex(xf * v)
	# distance lines (white) and the K-point line (red) across the matting
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lx := 10.0
	while lx < 52.0:
		var red := absf(lx - 40.0) < 0.1
		var w := 12.0 + lx * 0.12
		var colr := Color(0.75, 0.08, 0.06) if red else Color(0.92, 0.92, 0.9)
		var zz := -w
		while zz < w - 0.01:
			var z1 := minf(zz + 2.0, w)
			var q00 := Vector3(lx - 0.18, float(surf.call(lx - 0.18, zz)) + 0.04, zz)
			var q01 := Vector3(lx - 0.18, float(surf.call(lx - 0.18, z1)) + 0.04, z1)
			var q10 := Vector3(lx + 0.18, float(surf.call(lx + 0.18, zz)) + 0.04, zz)
			var q11 := Vector3(lx + 0.18, float(surf.call(lx + 0.18, z1)) + 0.04, z1)
			for v: Vector3 in [q00, q11, q01, q00, q10, q11]:
				lines.set_color(colr)
				lines.set_normal(xf.basis * Vector3.UP)
				lines.add_vertex(xf * v)
			zz = z1
		lx += 5.0
	var matting := Mats.mat("canvas", Color(0.17, 0.28, 0.11))
	var mm := Gx.add_mesh(c, st_mat, matting, "SkiJumpMatting", 1400.0)
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Gx.add_mesh(c, st_grass, grass_mat(), "SkiJumpHill", 1400.0)
	var lm := StandardMaterial3D.new()
	lm.vertex_color_use_as_albedo = true
	lm.roughness = 0.8
	Gx.add_mesh(c, lines, lm, "SkiJumpLines", 500.0)
	# retaining wall under the take-off where the hill starts
	g.col = Color(0.8, 0.79, 0.76)
	g.box("concrete", Vector3(-0.2, (hill_h + gy_o) * 0.5 - 1.0, 0), Vector3(0.6, hill_h - gy_o + 2.0, 26.0), 0.05)
	# real photo graffiti (GxGraffiti) on the back of the retaining wall and the take-off block
	var gx_g := "res://scripts/track/gimmicks/gx_graffiti.gd"
	if ResourceLoader.exists(gx_g):
		var gg: Script = load(gx_g)
		var back := Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0)) # -z points out of the wall's back (-x)
		for gz: float in [-8.0, 7.5]:
			gg.spray(c, xf * Transform3D(back, Vector3(-0.52, gy_o + 2.6, gz)), Vector2(7.0, 3.2), {seed = int(gz)})
		gg.spray(c, xf * Transform3D(Basis(Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1)), Vector3(-1.5, gy_o + 2.2, 2.13)), Vector2(2.6, 1.3), {tag = true})
	# judges' tower beside the hill, glazed towards it
	var jz := -24.0
	var jx := 30.0
	var jg: float = gl.call(jx, jz)
	g.col = Color(0.9, 0.88, 0.84)
	g.box("plaster", Vector3(jx, jg + 6.0, jz - 1.0), Vector3(6.0, 12.0, 4.0), 0.06)
	g.collide(Vector3(jx, jg + 6.0, jz - 1.0), Vector3(6.0, 12.0, 4.0))
	g.col = Color(0.32, 0.36, 0.4)
	for f in 3:
		g.box("glass", Vector3(jx, jg + 5.0 + f * 2.6, jz + 1.05), Vector3(5.6, 1.6, 0.08))
	g.col = Color(0.7, 0.7, 0.7)
	g.box("painted_metal", Vector3(jx, jg + 12.2, jz - 0.6), Vector3(6.6, 0.4, 5.2), 0.05)
	g.sign(Vector3(jx, jg + 3.0, jz + 1.03), Vector3(0, 0, 1), 5.0, 0.0, "a_kronen", Vector3.UP)
	# floodlight masts down both sides of the hill
	for side: float in [-1.0, 1.0]:
		for fx: float in [8.0, 32.0]:
			var mz := side * 21.0
			var my: float = gl.call(fx, mz)
			g.col = Color(0.6, 0.62, 0.63)
			g.lathe("steel", Vector3(fx, my, mz), PackedVector2Array([Vector2(0.32, 0), Vector2(0.18, 24.0), Vector2(0.0, 24.1)]), 8)
			g.col = Color(0.25, 0.26, 0.27)
			g.box("painted_metal", Vector3(fx, my + 24.6, mz - side * 0.3), Vector3(2.6, 1.4, 0.4), 0.05)
			g.collide(Vector3(fx, my + 5.0, mz), Vector3(0.6, 10.0, 0.6))
	# outrun fence
	g.col = Color(0.42, 0.33, 0.24)
	for k in 13:
		var fz := -18.0 + k * 3.0
		var fy: float = gl.call(66.0, fz)
		g.box("wood", Vector3(66.0, fy + 0.6, fz), Vector3(0.12, 1.2, 0.12))
	g.box("wood", Vector3(66.0, float(gl.call(66.0, 0.0)) + 1.0, 0), Vector3(0.06, 0.12, 36.0))
	g.cast_shadows("concrete")
	g.commit(c, "HochwaldSchanze", 1600.0)


# ------------------------------------------------------------------ log yard

## Timber piles beside the road: `xf` is a Gx.frame (x along the road, +z away).
static func log_yard(c: Node3D, xf: Transform3D, length := 40.0) -> void:
	var g := GxGeo.new(xf)
	var rng := Gx.rng(c, "logyard%d" % int(xf.origin.x))
	var x0 := -length * 0.5
	var piles := int(length / 13.0)
	var px := x0
	for k in piles:
		var plen := rng.randf_range(9.0, 12.0)
		var depth_rows := rng.randi_range(6, 8)
		var logl := 4.0 if rng.randf() < 0.5 else 5.0
		_log_pile(c, g, xf, rng, px, px + plen, depth_rows, logl)
		px += plen + rng.randf_range(2.0, 4.0)
	# a forwarder trailer parked at the end
	var tx := px + 3.0
	var gy := Gx.ground(c, xf * Vector3(tx, 0, 4)) - xf.origin.y
	g.col = Color(0.15, 0.36, 0.18)
	g.box("painted_metal", Vector3(tx + 2.5, gy + 1.15, 4.0), Vector3(6.5, 0.35, 2.3), 0.05)
	for sx: float in [0.0, 2.6, 5.0]:
		g.bar("painted_metal", Vector3(tx + sx, gy + 1.2, 2.9), Vector3(tx + sx, gy + 3.0, 2.9), 0.06, 6)
		g.bar("painted_metal", Vector3(tx + sx, gy + 1.2, 5.1), Vector3(tx + sx, gy + 3.0, 5.1), 0.06, 6)
	g.col = Color(0.08, 0.08, 0.08)
	for wx: float in [1.4, 3.6]:
		for wz: float in [2.65, 5.35]:
			g.tube("rubber", [Vector3(tx + wx, gy + 0.55, wz - 0.3), Vector3(tx + wx, gy + 0.55, wz + 0.3)], 0.55, 12)
	g.col = Color(0.15, 0.36, 0.18)
	g.bar("painted_metal", Vector3(tx - 1.5, gy + 1.0, 4.0), Vector3(tx - 0.8, gy + 1.15, 4.0), 0.08, 6)
	g.commit(c, "LogYard%d" % int(xf.origin.x), 450.0)
	_override(c, "LogYard%d" % int(xf.origin.x), "bark", bark_mat())
	for x: float in [x0, 0.0, -x0]:
		Gx.reserve(c, xf * Vector3(x, 0, 4.0), 9.0)


static func _log_pile(c: Node3D, g: GxGeo, xf: Transform3D, rng: RandomNumberGenerator, xa: float, xb: float, rows: int, logl: float) -> void:
	var gy := Gx.ground(c, xf * Vector3((xa + xb) * 0.5, 0, 4.0)) - xf.origin.y
	# skid timbers underneath, across the pile
	g.col = Color(0.75, 0.72, 0.66)
	var sx := xa + 0.6
	while sx < xb:
		g.tube("bark", [Vector3(sx, gy + 0.12, 1.0), Vector3(sx, gy + 0.12, 2.0 + rows * 0.52)], 0.13, 6)
		sx += 2.6
	# logs lie ACROSS the frame (along z, butt ends facing the road), stacked in rows
	var y := gy + 0.28
	var n := int((xb - xa) / 0.5)
	for r in rows:
		var count := n - r
		if count < 3:
			break
		var off := xa + 0.25 + r * 0.25
		for k in count:
			var rad := rng.randf_range(0.17, 0.26)
			var lx := off + k * 0.5 + rng.randf_range(-0.04, 0.04)
			var z0 := 1.2 + rng.randf_range(-0.25, 0.25)
			var ly := y + rng.randf_range(-0.03, 0.03)
			g.col = Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.25))
			g.tube("bark", [Vector3(lx, ly, z0), Vector3(lx, ly, z0 + logl)], rad, 7, false)
			# sawn end faces: pale fresh spruce, darker heart (vertex shading)
			var fresh := Color(0.95, 0.82, 0.6).darkened(rng.randf_range(0.0, 0.2))
			for e: float in [z0, z0 + logl]:
				var cen := Vector3(lx, ly, e)
				var nrm := Vector3(0, 0, -1 if e == z0 else 1)
				for s in 7:
					var a0 := TAU * s / 7.0
					var a1 := TAU * (s + 1) / 7.0
					var pa := cen + Vector3(cos(a0), sin(a0), 0) * rad
					var pb := cen + Vector3(cos(a1), sin(a1), 0) * rad
					if e == z0:
						g.tri_n("painted_wood", cen, pa, pb, nrm, nrm, nrm, fresh.darkened(0.25), fresh, fresh)
					else:
						g.tri_n("painted_wood", cen, pb, pa, nrm, nrm, nrm, fresh.darkened(0.25), fresh, fresh)
		y += 0.43
	g.collide(Vector3((xa + xb) * 0.5, gy + rows * 0.2, 1.2 + logl * 0.5), Vector3(xb - xa, rows * 0.4, logl))


# ------------------------------------------------------------------ high seat

## Hunter's high seat (Hochsitz) at frame `xf` (x along road, +z away), facing the road.
static func high_seat(c: Node3D, xf: Transform3D) -> void:
	var g := GxGeo.new(xf)
	var gy := 0.0
	var H := 4.2
	g.col = Color(0.85, 0.8, 0.75)
	# four splayed log legs
	for lx: float in [-0.9, 0.9]:
		for lz: float in [-0.9, 0.9]:
			g.tube("bark", [Vector3(lx * 1.5, gy - 0.3, lz * 1.5), Vector3(lx, H, lz)], 0.09, 6)
	# cross bracing
	for lz: float in [-0.9, 0.9]:
		g.tube("bark", [Vector3(-1.3, 0.8, lz * 1.3), Vector3(1.0, H - 0.6, lz * 1.05)], 0.06, 5)
	# ladder on the back
	for lx: float in [-0.35, 0.35]:
		g.tube("bark", [Vector3(lx, -0.2, 2.2), Vector3(lx, H + 0.2, 1.0)], 0.06, 5)
	for k in 10:
		var t := (k + 0.5) / 10.0
		var p := Vector3(0, -0.2, 2.2).lerp(Vector3(0, H + 0.2, 1.0), t)
		g.tube("bark", [p + Vector3(-0.38, 0, 0), p + Vector3(0.38, 0, 0)], 0.035, 4)
	# weathered plank cabin with a felt roof
	g.col = Color(0.55, 0.47, 0.38)
	g.box("wood", Vector3(0, H + 0.1, 0), Vector3(2.0, 0.12, 2.0), 0.02)
	g.box("wood", Vector3(0, H + 0.6, -0.95), Vector3(2.0, 1.0, 0.08), 0.02)
	for sx: float in [-0.97, 0.97]:
		g.box("wood", Vector3(sx, H + 0.75, 0), Vector3(0.08, 1.3, 2.0), 0.02)
	g.box("wood", Vector3(0, H + 0.75, 0.97), Vector3(2.0, 1.3, 0.08), 0.02)
	for sx: float in [-0.95, 0.95]:
		g.box("wood", Vector3(sx, H + 1.55, -0.95), Vector3(0.1, 1.9, 0.1))
	g.col = Color(0.12, 0.12, 0.12)
	g.box("rubber", Vector3(0, H + 2.55, 0.1), Vector3(2.5, 0.08, 2.6), 0.02, Basis(Vector3.RIGHT, -0.2))
	g.commit(c, "HighSeat%d" % int(xf.origin.x), 260.0, false)
	_override(c, "HighSeat%d" % int(xf.origin.x), "bark", bark_mat())
	Gx.reserve(c, xf.origin, 3.0)
