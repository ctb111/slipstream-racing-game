class_name GxCottage
extends RefCounted
## Lonely buildings with a story, lit from inside in the storm / blizzard.
##   kind "pub":  a two-storey moorland stone inn ("The Drowned Lamb"): rubble
##                stone walls, wet slate roof, gable chimneys, white sash
##                windows glowing warm, a porch, a hanging painted sign, a
##                dry-stone wall round the car park, beer barrels, benches.
##   kind "hut":  an alpine mountain hut ("Schneekopfhütte 1840 m"): stone
##                ground floor, larch upper storey with a balcony, a shallow
##                roof with deep eaves under a thick load of snow, firewood
##                stacked under the eaves, skis against the wall.
##
##   GxCottage.place(c, Gx.frame(c, 1225.0, Gx.RIGHT, 24.0), {kind = "pub"})
##
## Frame: Gx.frame (front faces the road, -z). The building's front wall is at
## z = 0..; the footprint is about 16 x 9 m (pub) / 12 x 10 m (hut); it reserves
## the area against trees. opts: kind, name (sign text), vis (600).

const WARM := Color(1.0, 0.72, 0.38)


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind := str(opts.get("kind", "pub"))
	# sit on the lowest ground under the footprint so nothing floats
	var lo := INF
	for sx: float in [-8.0, 0.0, 8.0]:
		for sz: float in [0.0, 5.0, 10.0]:
			lo = minf(lo, Gx.ground(c, xf * Vector3(sx, 0, sz)))
	xf.origin.y = lo
	var g := GxGeo.new(xf)
	var lit := GxGeo.new(xf)
	_photo = SurfaceTool.new()
	_photo.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "hut":
		_hut(g, lit)
	else:
		_pub(g, lit)
	var vis: float = opts.get("vis", 600.0)
	var nm := "GxCottage_" + kind
	g.commit(c, nm, vis, true)
	var wins := Gx.add_mesh(c, _photo, FacadeKit.unit_material(1.0), nm + "_windows", vis)
	wins.transform = g.xf
	_photo = null
	var lit_root: Node = lit.commit(c, nm + "_lit", vis, false)
	var w: Node = lit_root.get_node_or_null("glass") if lit_root else null
	if w is MeshInstance3D:
		(w as MeshInstance3D).material_override = _window_mat()
	# sign text
	var label := Label3D.new()
	label.text = str(opts.get("name", "THE DROWNED LAMB" if kind == "pub" else "SCHNEEKOPFHÜTTE\n1840 m"))
	label.font_size = 64
	label.pixel_size = 0.006 if kind == "pub" else 0.007
	label.modulate = Color(0.92, 0.82, 0.55) if kind == "pub" else Color(0.18, 0.12, 0.08)
	label.outline_size = 0
	label.double_sided = false
	label.shaded = true
	label.visibility_range_end = 160.0
	var font_path := "res://assets/fonts/"
	var da := DirAccess.open(font_path)
	if da:
		for f in da.get_files():
			if f.ends_with(".ttf") or f.ends_with(".otf"):
				if f.to_lower().contains("bold") or f.to_lower().contains("semibold"):
					label.font = load(font_path + f)
					break
	if kind == "pub":
		label.transform = xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 6.05, -0.32))
	else:
		label.transform = xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 3.55, -0.36))
	c.add_child(label)
	Gx.reserve(c, xf * Vector3(0, 0, 5.0), 13.0)


static func _window_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.18, 0.1)
	m.emission_enabled = true
	m.emission = WARM
	m.emission_energy_multiplier = 1.6
	m.roughness = 0.15
	m.metallic_specular = 0.9
	return m


## A window in the front (-z) wall at (x, y): a real photo window (FacadeKit
## atlas, glass glowing warm from inside) with a stone sill and lintel.
static var _photo: SurfaceTool


static func _window(g: GxGeo, _lit: GxGeo, x: float, y: float, w: float, h: float, z: float, _frame := Color(0.9, 0.9, 0.86), back := false) -> void:
	var s := 1.0 if back else -1.0
	var cell := 1 if h >= 1.2 else 2 # white casement / small square window
	var right := Vector3.RIGHT if back else Vector3.LEFT
	var sz := FacadeKit.add_unit(_photo, Vector3(x, y - h * 0.5, z + s * 0.035), right, cell, h)
	w = sz.x
	g.col = Color(0.72, 0.7, 0.66)
	g.box("stone", Vector3(x, y - h * 0.5 - 0.1, z + s * 0.12), Vector3(w + 0.4, 0.12, 0.26), 0.02) # sill
	g.box("stone", Vector3(x, y + h * 0.5 + 0.14, z + s * 0.03), Vector3(w + 0.5, 0.22, 0.1), 0.02) # lintel


## Gable roof along x: walls' top at y0, ridge height rh, depth d (z 0..d),
## length l, overhang o; material roof, optional snow layer.
static func _roof(g: GxGeo, y0: float, rh: float, d: float, l: float, o: float, roof: String, roof_col: Color, snow: float) -> void:
	var half := d * 0.5
	var ang := atan2(rh, half)
	var slen := sqrt(rh * rh + half * half)
	for sd: float in [-1.0, 1.0]:
		var eave := Vector3(0, y0, 0.0 if sd < 0.0 else d)
		var u := Vector3(0, rh, -sd * half).normalized() # eave -> ridge
		var rot := Basis(Vector3.RIGHT, sd * ang)
		var nrm := rot * Vector3.UP
		var mid := eave + u * (slen - o) * 0.5
		g.col = roof_col
		g.box(roof, mid + nrm * 0.1, Vector3(l + o * 2.0, 0.18, slen + o), 0.03, rot)
		if snow > 0.0:
			g.col = Color(0.94, 0.96, 0.99)
			g.box("plaster", mid + nrm * (0.19 + snow * 0.5), Vector3(l + o * 2.0 - 0.1, snow, slen + o - 0.15), minf(snow * 0.45, 0.2), rot)
	# ridge cap
	g.col = roof_col.darkened(0.2) if snow <= 0.0 else Color(0.94, 0.96, 0.99)
	g.box(roof if snow <= 0.0 else "plaster", Vector3(0, y0 + rh + 0.12 + snow, half), Vector3(l + o * 2.0, 0.16 + snow * 0.4, 0.36 + snow), 0.04 + snow * 0.15)


static func _gable(g: GxGeo, mat: String, x: float, y0: float, rh: float, d: float, t: float) -> void:
	var prof := PackedVector2Array([Vector2(0.0, y0), Vector2(d, y0), Vector2(d * 0.5, y0 + rh)])
	g.extrude(mat, prof, x - t * 0.5, x + t * 0.5)


static func _pub(g: GxGeo, lit: GxGeo) -> void:
	var L := 15.0
	var D := 7.5
	var H := 5.6
	g.col = Color(0.8, 0.78, 0.74)
	# plinth + rubble stone walls (4 walls so the corners read with quoins)
	g.box("stone", Vector3(0, -0.4, D * 0.5), Vector3(L + 0.4, 0.9, D + 0.4), 0.05)
	g.box("stone", Vector3(0, H * 0.5, D * 0.5), Vector3(L, H, D), 0.06)
	g.col = Color(0.92, 0.9, 0.86)
	for sx: float in [-1.0, 1.0]:
		for k in 9:
			var y := 0.3 + k * 0.6
			var long := k % 2 == 0
			g.box("stone", Vector3(sx * (L * 0.5 - (0.3 if long else 0.2)), y, -0.03), Vector3(0.62 if long else 0.42, 0.28, 0.08), 0.02)
	g.col = Color(0.8, 0.78, 0.74)
	_gable(g, "stone", -L * 0.5 + 0.2, H, 3.0, D, 0.4)
	_gable(g, "stone", L * 0.5 - 0.2, H, 3.0, D, 0.4)
	_roof(g, H, 3.0, D, L, 0.35, "slate", Color(0.55, 0.57, 0.6), 0.0)
	# chimneys on both gables
	for sx: float in [-1.0, 1.0]:
		g.col = Color(0.78, 0.76, 0.72)
		g.box("stone", Vector3(sx * (L * 0.5 - 0.6), H + 3.6, D * 0.5), Vector3(1.0, 2.6, 1.4), 0.05)
		g.col = Color(0.62, 0.6, 0.58)
		g.box("stone", Vector3(sx * (L * 0.5 - 0.6), H + 4.95, D * 0.5), Vector3(1.15, 0.15, 1.55), 0.03)
		for k in 2:
			g.col = Color(0.55, 0.3, 0.2)
			g.tube("brick", [Vector3(sx * (L * 0.5 - 0.6), H + 5.0, D * 0.5 - 0.3 + k * 0.6), Vector3(sx * (L * 0.5 - 0.6), H + 5.45, D * 0.5 - 0.3 + k * 0.6)], 0.15, 8)
	# windows: ground floor and first floor, front and back
	for x: float in [-5.4, -2.6, 2.6, 5.4]:
		_window(g, lit, x, 1.6, 1.0, 1.3, 0.0)
		_window(g, lit, x, 4.2, 0.9, 1.1, 0.0)
		_window(g, lit, x, 1.6, 1.0, 1.3, D, Color(0.9, 0.9, 0.86), true)
	_window(g, lit, 0.0, 4.2, 0.9, 1.1, 0.0)
	# door + porch with slate roof
	g.col = Color(0.12, 0.22, 0.16)
	g.box("painted_wood", Vector3(0, 1.1, -0.05), Vector3(1.1, 2.2, 0.1), 0.02)
	lit.box("glass", Vector3(0, 2.0, -0.11), Vector3(0.7, 0.25, 0.02))
	g.col = Color(0.8, 0.78, 0.74)
	for sx: float in [-0.9, 0.9]:
		g.box("stone", Vector3(sx, 1.25, -0.9), Vector3(0.3, 2.5, 0.3), 0.03)
	g.col = Color(0.5, 0.52, 0.55)
	g.box("slate", Vector3(0, 2.75, -0.75), Vector3(2.4, 0.12, 1.8), 0.02, Basis(Vector3.RIGHT, 0.32))
	g.col = Color(0.75, 0.73, 0.7)
	g.box("stone", Vector3(0, 0.08, -1.0), Vector3(2.2, 0.16, 1.4), 0.03) # step
	# hanging sign on an iron bracket
	g.col = Color(0.1, 0.1, 0.1)
	g.beam("steel", Vector3(-3.9, 4.9, -0.05), Vector3(-3.9, 4.9, -1.5), 0.06)
	g.bar("steel", Vector3(-3.9, 4.0, -0.05), Vector3(-3.9, 4.88, -1.2), 0.03, 4)
	g.col = Color(0.14, 0.2, 0.13)
	g.box("painted_wood", Vector3(-3.9, 4.15, -1.2), Vector3(0.08, 1.2, 0.95), 0.02)
	# name board over the door
	g.col = Color(0.1, 0.16, 0.11)
	g.box("painted_wood", Vector3(0, 6.05, -0.22), Vector3(5.6, 0.62, 0.12), 0.02)
	# dry-stone wall round the car park (front, open at the gate)
	g.col = Color(0.62, 0.62, 0.6)
	for seg: Array in [[-L * 0.5 - 6.0, -3.0], [3.0, L * 0.5 + 6.0]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		g.box("stone", Vector3((x0 + x1) * 0.5, 0.45, -10.0), Vector3(x1 - x0, 1.1, 0.6), 0.12)
		g.collide(Vector3((x0 + x1) * 0.5, 0.45, -10.0), Vector3(x1 - x0, 1.1, 0.6))
	for sx: float in [-1.0, 1.0]:
		g.box("stone", Vector3(sx * (L * 0.5 + 6.0), 0.45, -5.0), Vector3(0.6, 1.1, 10.0), 0.12)
	# beer barrels + benches by the porch
	g.col = Color(0.42, 0.3, 0.2)
	for k in 3:
		var bx := 3.6 + k * 0.75
		var prof := PackedVector2Array([Vector2(0.24, 0.0), Vector2(0.3, 0.35), Vector2(0.24, 0.72)])
		g.lathe("wood", Vector3(bx, 0.0, -0.6), prof, 10)
		g.col = Color(0.25, 0.25, 0.26)
		g.tube("steel", [Vector3(bx - 0.3, 0.18, -0.6), Vector3(bx + 0.3, 0.18, -0.6)], 0.02, 4)
		g.col = Color(0.42, 0.3, 0.2)
	for x: float in [-6.5, -3.6]:
		g.col = Color(0.4, 0.31, 0.22)
		g.box("wood", Vector3(x, 0.75, -2.6), Vector3(1.8, 0.08, 0.8), 0.02)
		g.box("wood", Vector3(x, 0.45, -3.3), Vector3(1.8, 0.06, 0.3), 0.02)
		g.box("wood", Vector3(x, 0.45, -1.9), Vector3(1.8, 0.06, 0.3), 0.02)
		for sx: float in [-0.75, 0.75]:
			g.box("wood", Vector3(x + sx, 0.37, -2.6), Vector3(0.08, 0.74, 1.6), 0.01)
	g.collide(Vector3(0, H * 0.5, D * 0.5), Vector3(L, H, D))


static func _hut(g: GxGeo, lit: GxGeo) -> void:
	var L := 12.0
	var D := 9.0
	var H0 := 3.0 # stone ground floor
	var H := 6.0 # eaves
	g.col = Color(0.78, 0.76, 0.73)
	g.box("stone", Vector3(0, H0 * 0.5 - 0.4, D * 0.5), Vector3(L, H0 + 0.8, D), 0.06)
	# larch upper storey (darkened by weather) with horizontal boarding
	g.col = Color(0.55, 0.4, 0.28)
	g.box("wood", Vector3(0, (H0 + H) * 0.5, D * 0.5), Vector3(L - 0.2, H - H0, D - 0.2), 0.03)
	for k in int((H - H0) / 0.3):
		var y := H0 + 0.15 + k * 0.3
		g.col = Color(0.5, 0.36, 0.25) if k % 2 == 0 else Color(0.58, 0.43, 0.3)
		g.box("wood", Vector3(0, y, -0.02), Vector3(L - 0.1, 0.27, 0.06), 0.01, Basis(Vector3.RIGHT, -0.06))
	g.col = Color(0.55, 0.4, 0.28)
	_gable(g, "wood", -L * 0.5 + 0.2, H, 1.9, D, 0.3)
	_gable(g, "wood", L * 0.5 - 0.2, H, 1.9, D, 0.3)
	_roof(g, H, 1.9, D, L, 1.4, "wood", Color(0.35, 0.28, 0.22), 0.55)
	# icicles along the front eaves
	g.col = Color(0.85, 0.92, 1.0)
	for k in 26:
		var x := -L * 0.5 - 1.0 + k * (L + 2.0) / 25.0
		var ln := 0.25 + fmod(k * 0.37, 0.5)
		g.tube("glass", [Vector3(x, H - 0.75, -1.25), Vector3(x, H - 0.75 - ln, -1.25)], 0.03, 4, true, [0.04, 0.005])
	# chimney
	g.col = Color(0.74, 0.72, 0.7)
	g.box("stone", Vector3(2.5, H + 2.4, D * 0.6), Vector3(0.9, 2.0, 0.9), 0.05)
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(2.5, H + 3.5, D * 0.6), Vector3(1.05, 0.22, 1.05), 0.08)
	# windows with green shutters
	for x: float in [-4.0, -1.4, 1.4, 4.0]:
		_window(g, lit, x, 1.6, 0.9, 1.1, 0.0, Color(0.88, 0.86, 0.8))
		_window(g, lit, x, 4.7, 0.9, 1.1, -0.05, Color(0.88, 0.86, 0.8))
		for sx: float in [-1.0, 1.0]:
			g.col = Color(0.14, 0.3, 0.18)
			g.box("painted_wood", Vector3(x + sx * 0.75, 4.7, -0.12), Vector3(0.5, 1.25, 0.05), 0.01)
	# balcony across the front upper storey
	g.col = Color(0.5, 0.36, 0.25)
	g.box("wood", Vector3(0, H0 + 0.4, -0.75), Vector3(L - 1.0, 0.15, 1.5), 0.02)
	for k in 21:
		var x := -L * 0.5 + 0.6 + k * (L - 1.2) / 20.0
		g.box("wood", Vector3(x, H0 + 0.95, -1.45), Vector3(0.12, 1.0, 0.04), 0.01)
	g.box("wood", Vector3(0, H0 + 1.5, -1.45), Vector3(L - 1.0, 0.1, 0.1), 0.02)
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(0, H0 + 1.6, -1.45), Vector3(L - 1.0, 0.1, 0.16), 0.04)
	g.col = Color(0.42, 0.3, 0.2)
	for sx: float in [-1.0, 1.0]:
		g.box("wood", Vector3(sx * (L * 0.5 - 0.5), H0 * 0.5 - 0.2, -1.4), Vector3(0.2, H0 + 0.4, 0.2), 0.02)
	# door
	g.col = Color(0.3, 0.2, 0.13)
	g.box("wood", Vector3(0, 1.05, -0.05), Vector3(1.1, 2.1, 0.1), 0.02)
	# name board
	g.col = Color(0.85, 0.8, 0.7)
	g.box("painted_wood", Vector3(0, 3.55, -0.28), Vector3(4.2, 0.95, 0.08), 0.02)
	# firewood stacked against the gable
	g.col = Color(0.48, 0.36, 0.25)
	for row in 5:
		for k in 14:
			var z := 1.0 + k * 0.5
			g.tube("wood", [Vector3(L * 0.5 + 0.2, 0.15 + row * 0.28, z), Vector3(L * 0.5 + 0.75, 0.15 + row * 0.28, z + 0.04)], 0.13, 6)
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(L * 0.5 + 0.5, 1.6, 4.4), Vector3(0.7, 0.12, 7.2), 0.05)
	# skis leaning by the door
	for k in 4:
		var x := 1.4 + k * 0.28
		g.col = [Color(0.7, 0.1, 0.08), Color(0.1, 0.2, 0.5), Color(0.85, 0.8, 0.2), Color(0.1, 0.1, 0.1)][k]
		g.box("painted_metal", Vector3(x, 0.9, -0.3), Vector3(0.08, 1.8, 0.02), 0.005, Basis(Vector3.RIGHT, 0.18))
	# bench
	g.col = Color(0.42, 0.3, 0.2)
	g.box("wood", Vector3(-3.0, 0.45, -0.45), Vector3(2.2, 0.07, 0.4), 0.02)
	for sx: float in [-0.9, 0.9]:
		g.box("wood", Vector3(-3.0 + sx, 0.22, -0.45), Vector3(0.08, 0.44, 0.36), 0.01)
	g.col = Color(0.94, 0.96, 0.99)
	g.box("plaster", Vector3(-3.0, 0.5, -0.45), Vector3(2.1, 0.05, 0.36), 0.02)
	g.collide(Vector3(0, H * 0.5, D * 0.5), Vector3(L, H, D))
