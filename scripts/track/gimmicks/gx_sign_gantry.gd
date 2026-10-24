class_name GxSignGantry
extends RefCounted
## Motorway-style overhead direction-sign gantry (Schilderbrücke) over the road:
## galvanised tubular posts on concrete plinths, a 4-chord tube truss with a
## maintenance walkway and railing, two reflective direction boards with fun
## destinations, lane arrows, sign lamps.
##   GxSignGantry.place(c, Gx.road_frame(c, 900.0), {})
## opts:
##   boards   two indices into the board designs (default chosen per site), e.g. [0, 2]
##            0 Schneekopf / Hochwald (blue), 1 Boxengasse / Würstchenbude (exit),
##            2 Ziel / Finish 2 km, 3 Valtellina / Capo Rosso (green, Italian),
##            4 Nirgendwo / Vollgas, 5 Altstadt / Bergwerk
##   both     true: boards on the back face too (default false: plain backs)
## Clearance >= 5.8 m over road + kerb, posts outside road + kerb + 1.5 m, colliders.

const GALV := Color(0.78, 0.8, 0.8)
const CELL := Vector2i(1024, 512)
const DESIGNS := [
	{bg = Color(0.05, 0.22, 0.6), lines = [["Schneekopf", "12"], ["Hochwald", "31"]], arrow = "down", shield = "A 7"},
	{bg = Color(0.05, 0.22, 0.6), lines = [["Boxengasse", ""], ["Würstchenbude", "500 m"]], arrow = "exit", shield = "3"},
	{bg = Color(0.05, 0.22, 0.6), lines = [["Ziel · Finish", ""], ["Kiefernring", "2 km"]], arrow = "up", shield = "E 52"},
	{bg = Color(0.0, 0.42, 0.22), lines = [["Valtellina", "48"], ["Capo Rosso", "112"]], arrow = "down", shield = "A 1"},
	{bg = Color(0.05, 0.22, 0.6), lines = [["Nirgendwo", "7"], ["Vollgas", "∞"]], arrow = "down", shield = "A 99"},
	{bg = Color(0.05, 0.22, 0.6), lines = [["Altstadt", "9"], ["Brackenmoor", "54"]], arrow = "exit", shield = "4"},
]

static var _tex: ImageTexture
static var _mat: StandardMaterial3D


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var g := GxGeo.new(xf)
	var hw := Gx.half_width() + TrackBuilder.CURB_WIDTH + 1.5
	var zp := hw + 0.6 # post axis
	var top := 0.0
	for x: float in [-1.5, 0.0, 1.5]:
		for z: float in [-hw, 0.0, hw]:
			top = maxf(top, Gx.curve(c).get_closest_point(xf * Vector3(x, 0, z)).y - xf.origin.y)
	var bh := 3.0 # board height
	var bw := 6.0
	var yb := top + 5.9 # board bottom
	var ty := yb + bh * 0.5 # truss centre height
	var td := 1.3 # truss depth (along x)
	var th := 1.4 # truss height
	# posts: tapered round tubes with a flange plate on a concrete plinth
	for s: float in [-1.0, 1.0]:
		var gy := Gx.ground(c, xf * Vector3(0, 0, s * zp)) - xf.origin.y
		g.col = Color(0.82, 0.81, 0.78)
		g.box("concrete", Vector3(0, gy + 0.2, s * zp), Vector3(1.6, 0.9, 1.6), 0.08)
		g.collide(Vector3(0, gy + 0.2, s * zp), Vector3(1.6, 0.9, 1.6))
		g.col = GALV
		g.box("steel", Vector3(0, gy + 0.68, s * zp), Vector3(0.9, 0.05, 0.9), 0.01)
		for bx: float in [-0.32, 0.32]:
			for bz: float in [-0.32, 0.32]:
				g.lathe("steel", Vector3(bx, gy + 0.7, s * zp + bz), PackedVector2Array([Vector2(0.035, 0), Vector2(0.035, 0.08), Vector2(0.0, 0.09)]), 6)
		for px: float in [-td * 0.5, td * 0.5]:
			g.lathe("steel", Vector3(px, gy + 0.7, s * zp), PackedVector2Array([Vector2(0.19, 0.0), Vector2(0.16, ty + th * 0.5 - gy - 0.2), Vector2(0.0, ty + th * 0.5 - gy - 0.18)]), 14)
			g.collide(Vector3(px, (gy + ty) * 0.5, s * zp), Vector3(0.36, ty - gy + 0.8, 0.36))
		# bracing between the twin posts
		var n := int((ty - gy) / 1.6)
		for k in n:
			var y0 := gy + 1.2 + k * 1.6
			g.bar("steel", Vector3(-td * 0.5, y0, s * zp), Vector3(td * 0.5, y0 + 1.6, s * zp), 0.05, 6)
	# 4-chord truss with Warren diagonals on all faces
	g.col = GALV
	var z0 := -zp - 0.3
	var z1 := zp + 0.3
	var ch := [Vector2(-td * 0.5, -th * 0.5), Vector2(td * 0.5, -th * 0.5), Vector2(td * 0.5, th * 0.5), Vector2(-td * 0.5, th * 0.5)]
	for p: Vector2 in ch:
		g.tube("steel", [Vector3(p.x, ty + p.y, z0), Vector3(p.x, ty + p.y, z1)], 0.09, 10)
	var cells := int((z1 - z0) / 1.5)
	for k in cells:
		var za := z0 + (z1 - z0) * k / cells
		var zb := z0 + (z1 - z0) * (k + 1) / cells
		for f in 4:
			var a: Vector2 = ch[f]
			var b: Vector2 = ch[(f + 1) % 4]
			var pa := Vector3(a.x, ty + a.y, za if k % 2 == 0 else zb)
			var pb := Vector3(b.x, ty + b.y, zb if k % 2 == 0 else za)
			g.bar("steel", pa, pb, 0.04, 6)
		for f in 4:
			var a: Vector2 = ch[f]
			var b: Vector2 = ch[(f + 1) % 4]
			g.bar("steel", Vector3(a.x, ty + a.y, za), Vector3(b.x, ty + b.y, za), 0.035, 6)
	# walkway grating + railing on the traffic side, behind the boards
	g.col = Color(0.55, 0.56, 0.56)
	g.box("steel", Vector3(-td * 0.5 - 0.55, ty - th * 0.5 - 0.02, 0), Vector3(0.8, 0.05, z1 - z0), 0.0)
	for zz in range(int(z0), int(z1) + 1, 2):
		g.bar("steel", Vector3(-td * 0.5 - 0.95, ty - th * 0.5, zz), Vector3(-td * 0.5 - 0.95, ty - th * 0.5 + 1.0, zz), 0.025, 5)
	g.tube("steel", [Vector3(-td * 0.5 - 0.95, ty - th * 0.5 + 1.0, z0), Vector3(-td * 0.5 - 0.95, ty - th * 0.5 + 1.0, z1)], 0.03, 6)
	# boards: hung on the front (facing traffic, -x), aluminium backs with Z-rails
	var picks: Array = opts.get("boards", [])
	if picks.size() < 2:
		var h: int = absi(hash(str(xf.origin)))
		picks = [h % DESIGNS.size(), (h / 7 + 1) % DESIGNS.size()]
		if picks[1] == picks[0]:
			picks[1] = (picks[0] + 1) % DESIGNS.size()
	var both: bool = opts.get("both", false)
	var bx := -td * 0.5 - 1.1 # board plane (in front of the walkway)
	for k in 2:
		var zc := (k - 0.5) * (bw + 0.4)
		g.col = Color(0.7, 0.72, 0.73)
		g.box("painted_metal", Vector3(bx + 0.06, ty, zc), Vector3(0.08, bh, bw), 0.01)
		for yy: float in [-0.9, 0.0, 0.9]:
			g.box("steel", Vector3(bx + 0.14, ty + yy, zc), Vector3(0.08, 0.1, bw - 0.2))
		for zz: float in [-bw * 0.35, bw * 0.35]:
			g.bar("steel", Vector3(bx + 0.18, ty + 0.6, zc + zz), Vector3(-td * 0.5, ty + 0.6, zc + zz), 0.04, 6)
			g.bar("steel", Vector3(bx + 0.18, ty - 0.6, zc + zz), Vector3(-td * 0.5, ty - 0.6, zc + zz), 0.04, 6)
		# sign lamp on an arm above each board
		g.col = Color(0.3, 0.31, 0.32)
		g.bar("painted_metal", Vector3(-td * 0.5, ty + th * 0.5, zc), Vector3(bx - 0.9, ty + bh * 0.5 + 0.35, zc), 0.035, 6)
		g.box("painted_metal", Vector3(bx - 0.95, ty + bh * 0.5 + 0.3, zc), Vector3(0.35, 0.14, 1.6), 0.03)
		_board(g, Vector3(bx - 0.005, ty, zc), -1.0, bw, bh, int(picks[k]))
		if both:
			_board(g, Vector3(td * 0.5 + 0.2, ty, zc), 1.0, bw, bh, int(picks[1 - k]))
	var root := g.commit(c, "GxSignGantry", 900.0)
	# the printed board faces live in their own mesh with the baked sign texture
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q: Array in g.get_meta("boards", []):
		st.set_normal(q[4])
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(q[5][idx])
			st.add_vertex(q[idx])
	var mi := Gx.add_mesh(c, st, _material(c), "boards", 900.0)
	mi.reparent(root)
	Gx.reserve(c, xf.origin, zp + 3.0)
	GxGeo.ab(root, xf * Vector3(-40.0, 1.4, 0.0), xf * Vector3(0, 6.0, 0))


## Queue one board face at local p facing f (-1 = traffic), design index d.
static func _board(g: GxGeo, p: Vector3, f: float, w: float, h: float, d: int) -> void:
	var cell := Vector2(d % 2, d / 2) * Vector2(0.5, 1.0 / 3.0)
	var uv0 := cell + Vector2(0.004, 0.006)
	var uv1 := cell + Vector2(0.5, 1.0 / 3.0) - Vector2(0.004, 0.006)
	var r := Vector3(0, 0, -f) * w * 0.5 # viewer's right
	var u := Vector3(0, h * 0.5, 0)
	var x := g.xf
	var q := [x * (p - r + u), x * (p + r + u), x * (p + r - u), x * (p - r - u), (x.basis * Vector3(f, 0, 0)).normalized(),
		[uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]]
	var list: Array = g.get_meta("boards", [])
	list.append(q)
	g.set_meta("boards", list)


static func _material(c: Node3D) -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = _atlas(c)
		_mat.roughness = 0.45
		_mat.metallic_specular = 0.6
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _mat


## 2 x 3 board designs drawn once into a SubViewport, baked to a mipmapped texture.
static func _atlas(c: Node3D) -> Texture2D:
	if _tex != null:
		return _tex
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * 2, CELL.y * 3)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var root := Control.new()
	root.size = Vector2(vp.size)
	vp.add_child(root)
	var font: Font = load(UiTheme.FONT_BOLD)
	for i in DESIGNS.size():
		var o := Vector2(i % 2, i / 2) * Vector2(CELL)
		_draw_design(root, Rect2(o, Vector2(CELL)), DESIGNS[i], font)
	c.add_child(vp)
	var baker := TrackProps.AtlasBaker.new()
	baker.viewport = vp
	c.add_child(baker)
	_tex = baker.texture
	return _tex


static func _draw_design(root: Control, r: Rect2, d: Dictionary, font: Font) -> void:
	var white := Color(0.96, 0.96, 0.94)
	var bg := ColorRect.new()
	bg.position = r.position
	bg.size = r.size
	bg.color = Color(0.6, 0.62, 0.62) # aluminium edge
	root.add_child(bg)
	var panel := Panel.new()
	panel.position = r.position + Vector2(6, 6)
	panel.size = r.size - Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = d.bg
	sb.border_color = white
	sb.set_border_width_all(12)
	sb.set_corner_radius_all(26)
	sb.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	# arrow on the left
	var ax := r.position.x + 120.0
	var ay := r.position.y + r.size.y * 0.5
	var poly := Polygon2D.new()
	poly.color = white
	match d.arrow:
		"down":
			poly.polygon = PackedVector2Array([Vector2(ax - 22, ay - 150), Vector2(ax + 22, ay - 150), Vector2(ax + 22, ay + 40), Vector2(ax + 70, ay + 40),
				Vector2(ax, ay + 150), Vector2(ax - 70, ay + 40), Vector2(ax - 22, ay + 40)])
		"up":
			poly.polygon = PackedVector2Array([Vector2(ax - 22, ay + 150), Vector2(ax + 22, ay + 150), Vector2(ax + 22, ay - 40), Vector2(ax + 70, ay - 40),
				Vector2(ax, ay - 150), Vector2(ax - 70, ay - 40), Vector2(ax - 22, ay - 40)])
		_:
			var pts := PackedVector2Array([Vector2(-22, 150), Vector2(22, 150), Vector2(22, -40), Vector2(70, -40),
				Vector2(0, -150), Vector2(-70, -40), Vector2(-22, -40)])
			var rot := Transform2D(0.75, Vector2(ax, ay))
			poly.polygon = rot * pts
	root.add_child(poly)
	# route shield (yellow federal / blue motorway style) top right
	var sh := Panel.new()
	var sbs := StyleBoxFlat.new()
	var motorway: bool = str(d.shield).begins_with("A") or str(d.shield).begins_with("E")
	sbs.bg_color = Color(0.05, 0.22, 0.6) if not str(d.shield).begins_with("E") else Color(0.0, 0.42, 0.22)
	if not motorway:
		sbs.bg_color = Color(0.98, 0.78, 0.1)
	sbs.border_color = white if motorway else Color(0.05, 0.05, 0.05)
	sbs.set_border_width_all(6)
	sbs.set_corner_radius_all(14)
	sh.add_theme_stylebox_override("panel", sbs)
	sh.position = r.position + Vector2(r.size.x - 230, 34)
	sh.size = Vector2(190, 92)
	root.add_child(sh)
	var sl := Label.new()
	sl.text = d.shield
	sl.position = sh.position
	sl.size = sh.size
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sl.add_theme_font_override("font", font)
	sl.add_theme_font_size_override("font_size", 64)
	sl.add_theme_color_override("font_color", white if motorway else Color(0.05, 0.05, 0.05))
	root.add_child(sl)
	# destination lines with distances
	var lines: Array = d.lines
	for i in lines.size():
		var y := r.position.y + 150.0 + i * 150.0
		var name_l := Label.new()
		name_l.text = lines[i][0]
		name_l.position = Vector2(r.position.x + 230, y)
		name_l.size = Vector2(560, 130)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.add_theme_font_override("font", font)
		var fs := 92
		while fs > 50 and font.get_string_size(str(lines[i][0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > (500.0 if str(lines[i][1]) != "" else 700.0):
			fs -= 4
		name_l.add_theme_font_size_override("font_size", fs)
		name_l.add_theme_color_override("font_color", white)
		root.add_child(name_l)
		var dist := Label.new()
		dist.text = lines[i][1]
		dist.position = Vector2(r.position.x + r.size.x - 260, y)
		dist.size = Vector2(220, 130)
		dist.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		dist.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dist.add_theme_font_override("font", font)
		dist.add_theme_font_size_override("font_size", 84)
		dist.add_theme_color_override("font_color", white)
		root.add_child(dist)
