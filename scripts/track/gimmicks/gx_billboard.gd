class_name GxBillboard
extends RefCounted
## Roadside billboards and fun road signs.
##   kind "billboard" (default): a 5 m paper poster board (photo ads for the
##       game's invented brands, weathered: sheet seams, sun fade, dirt runs)
##       in a painted steel frame on two steel legs with concrete footings and
##       two lamp arms.  opts: brand (0..7 or name, see BRANDS), scale (1.0),
##       lift (board bottom height, 2.4), yaw (deg towards oncoming traffic, 8).
##   kind "sign": galvanised post(s) with a reflective road sign:
##       sign = "fans" (CAUTION: FANS), "crest" (CREST · JUMP!), "village"
##       (SLOW — VILLAGE + speed limit, opts.speed 30/50/80), "speed", "chevron"
##       (opts.count boards spaced 2.6 m; arrows point along the driving direction,
##       so put them on the OUTSIDE of the bend). yaw (18).
##
##   GxBillboard.place(c, Gx.frame(c, 900.0, Gx.LEFT, 5.0), {brand = "HELIOS BENZIN"})
##   GxBillboard.place(c, Gx.frame(c, 1200.0, Gx.RIGHT, 1.5), {kind = "sign", sign = "chevron"})
##
## Frame: xf from Gx.frame (-z faces the road, x = driving direction); left-side
## (mirrored) frames are handled. Art: tools/make_gx_billboard.py (real photos,
## see assets/CREDITS.txt; Barlow fonts). Cost: billboard 4 draw calls (print,
## steel, paint, concrete), signs 2; identical pieces share a cached template:
## 0.06 ms per sign / 0.2 ms per billboard placed, first build of each sign kind
## ~0.4 ms, of each brand ~3 ms (once per track). Colliders on legs / posts.

const ATLAS := "res://assets/gimmicks/gx_billboard.png"
const BRANDS := ["MARZELLI", "NORDLICHT", "HELIOS BENZIN", "VALTER OIL", "AUREL WATCHES", "OSTRA FILM",
	"HALDEN TYRES", "BERGMANN"]
const AW := 2048.0
const AH := 4096.0
const SY := 2944.0
## atlas pixel rects (tools/make_gx_billboard.py SIGNS)
const SIGNS := {
	tri_fans = Rect2(0, SY, 512, 460), tri_crest = Rect2(512, SY, 512, 460),
	speed30 = Rect2(1024, SY, 384, 384), speed50 = Rect2(1408, SY, 384, 384), speed80 = Rect2(1024, SY + 384, 384, 384),
	plate_fans = Rect2(0, SY + 470, 500, 170), plate_jump = Rect2(510, SY + 470, 500, 170),
	village = Rect2(0, SY + 680, 900, 420), chevron = Rect2(1024, SY + 780, 640, 320),
	steel = Rect2(1792, SY, 256, 256), frame = Rect2(1792, SY + 256, 256, 256),
}
const FRAME_COLORS := [Color(0.16, 0.24, 0.19), Color(0.22, 0.23, 0.24), Color(0.45, 0.46, 0.45), Color(0.1, 0.12, 0.2)]

static var _mat: ShaderMaterial
static var _tpl := {} ## cache key -> template Node3D (not in the tree)


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/gx_print.gdshader")
		_mat.set_shader_parameter("atlas", load(ATLAS))
		_mat.set_shader_parameter("detail_nor", Mats.tex("plaster", "nor_gl"))
		_mat.set_shader_parameter("detail_arm", Mats.tex("plaster", "arm"))
		_mat.set_shader_parameter("detail_scale", 1.2)
		_mat.set_shader_parameter("normal_strength", 0.25)
		_mat.set_shader_parameter("rough_base", 0.75)
		_mat.set_shader_parameter("rough_detail", 0.2)
	return _mat


## Right-handed version of a frame (safety: a mirrored basis would turn text
## back to front). Returns [xf, oncoming] where oncoming is the
## local x direction (+1/-1) the traffic comes FROM.
static func upright(c: Node3D, xf: Transform3D) -> Array:
	if xf.basis.determinant() < 0.0:
		xf = Transform3D(Basis(-xf.basis.x, xf.basis.y, xf.basis.z), xf.origin)
	var t := Gx.frame_x(c, xf)
	return [xf, -1.0 if xf.basis.x.dot(t) >= 0.0 else 1.0]


static func _uv(px: Rect2) -> Rect2:
	return Rect2(px.position.x / AW, px.position.y / AH, px.size.x / AW, px.size.y / AH)


## Printed polygon: local 2D points (x = viewer's right, y = up) on the plane
## through `o` with axes `u` (right) / `v` (up), uv-mapped from `px` (atlas pixel
## rect) by the points' bounding box [lo, hi]. Front faces the viewer (u x v).
static func _poly(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, pts: PackedVector2Array,
		lo: Vector2, hi: Vector2, px: Rect2, col := Color.WHITE, mirror_uv := false) -> void:
	var r := _uv(px)
	var n := u.cross(v).normalized()
	var verts: Array = []
	var uvs: Array = []
	for p in pts:
		verts.append(o + u * p.x + v * p.y)
		var t := (p - lo) / (hi - lo)
		if mirror_uv:
			t.x = 1.0 - t.x
		uvs.append(Vector2(r.position.x + r.size.x * t.x, r.position.y + r.size.y * (1.0 - t.y)))
	for k in range(1, pts.size() - 1): # fan (convex shapes), clockwise seen from the front
		for idx: int in [0, k + 1, k]:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.set_uv2(Vector2(pts[idx].x, -pts[idx].y))
			st.add_vertex(verts[idx])


static func _rect_pts(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), Vector2(-w * 0.5, h * 0.5)])


## A sign plate centred at `c` (local), facing `nrm` (horizontal), shape "rect" /
## "tri" / "disc", printed front, galvanised back.
static func _plate(st: SurfaceTool, c: Vector3, nrm: Vector3, w: float, h: float, shape: String, px: Rect2, mirror := false) -> void:
	var u := Vector3.UP.cross(nrm).normalized() # viewer's right when looking at the front
	var v := Vector3.UP
	var pts: PackedVector2Array
	if shape == "tri":
		pts = PackedVector2Array([Vector2(0, h * 0.5), Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, -h * 0.5)])
	elif shape == "disc":
		pts = PackedVector2Array()
		for i in 24:
			var a := -TAU * i / 24.0
			pts.append(Vector2(cos(a), sin(a)) * w * 0.5)
		pts.reverse()
	else:
		pts = _rect_pts(w, h)
	var lo := Vector2(-w * 0.5, -h * 0.5)
	var hi := Vector2(w * 0.5, h * 0.5)
	_poly(st, c + nrm * 0.006, u, v, pts, lo, hi, px, Color.WHITE, mirror)
	# back: same outline, reversed, galvanised steel
	var back := PackedVector2Array()
	for p in pts:
		back.append(Vector2(-p.x, p.y))
	back.reverse() # mirrored outline: back to counter-clockwise
	_poly(st, c - nrm * 0.004, -u, v, back, lo, hi, SIGNS.steel, Color(0.8, 0.8, 0.8))


static func _num(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	for k in o:
		if o[k] is String and (o[k] as String).is_valid_float():
			o[k] = float(o[k])
	return o


static func place(c: Node3D, xf_in: Transform3D, opts := {}) -> void:
	opts = _num(opts)
	var up := upright(c, xf_in)
	var oncoming: float = up[1]
	var kind: String = opts.get("kind", "billboard")
	var yaw := deg_to_rad(float(opts.get("yaw", 8.0 if kind == "billboard" else 18.0)))
	# turn the face (-z) towards the oncoming traffic
	var xf: Transform3D = up[0] * Transform3D(Basis(Vector3.UP, -yaw * oncoming), Vector3.ZERO)
	var r := Gx.rng(c, "billboard")
	r.seed = hash(str(r.seed) + str(Vector3i(xf.origin.round())))
	# resolve the random choices first: identical pieces share one cached template
	if kind == "sign":
		if not opts.has("sign"):
			opts.sign = ["fans", "crest", "village", "speed", "chevron"][r.randi() % 5]
		if not opts.has("speed") and opts.sign in ["village", "speed"]:
			opts.speed = 50 if opts.sign == "village" else [30, 50, 80][r.randi() % 3]
	else:
		if not opts.has("brand"):
			opts.brand = r.randi_range(0, BRANDS.size() - 1)
		var bi = opts.brand
		opts.frame = (BRANDS.find(bi) if bi is String else int(bi)) % FRAME_COLORS.size() # one template per brand
	var mirror := oncoming < 0.0
	var key := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [kind, opts.get("sign", ""), opts.get("speed", ""), opts.get("count", ""),
		opts.get("brand", ""), opts.get("frame", ""), opts.get("scale", ""), opts.get("lift", ""), opts.get("reverse", ""), mirror]
	if not _tpl.has(key):
		var holder := Node3D.new()
		holder.name = "GxBillboard"
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var g := GxGeo.new()
		var vis := 300.0 if kind == "sign" else 500.0
		if kind == "sign":
			_sign(c, st, g, r, opts, oncoming)
		else:
			_board(c, st, g, r, opts)
		Gx.add_mesh(holder, st, material(), "Print", vis)
		g.commit(holder, "Frame", vis, kind != "sign")
		_tpl[key] = holder
	c.add_child(_instance(_tpl[key], xf))
	Gx.reserve(c, xf.origin, 6.0 if kind != "sign" else 2.0)


## A placed copy of a cached template: new nodes sharing its meshes, materials
## and collision shapes (cheaper than Node.duplicate()).
static func _instance(tpl: Node3D, xf: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "GxBillboard"
	root.transform = xf
	for ch in tpl.get_children():
		if ch is MeshInstance3D:
			var src := ch as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.cast_shadow = src.cast_shadow
			mi.visibility_range_end = src.visibility_range_end
			mi.visibility_range_end_margin = src.visibility_range_end_margin
			root.add_child(mi)
		elif ch is StaticBody3D:
			var body := StaticBody3D.new()
			body.physics_material_override = (ch as StaticBody3D).physics_material_override
			for cs in ch.get_children():
				var n := CollisionShape3D.new()
				n.shape = (cs as CollisionShape3D).shape
				n.transform = (cs as CollisionShape3D).transform
				body.add_child(n)
			root.add_child(body)
	return root


static func _board(c: Node3D, st: SurfaceTool, g: GxGeo, r: RandomNumberGenerator, opts: Dictionary) -> void:
	var s: float = opts.get("scale", 1.0)
	var w := 5.0 * s
	var h := w / 1.414
	var lift: float = opts.get("lift", 2.4)
	var brand = opts.get("brand", r.randi_range(0, BRANDS.size() - 1))
	var bi: int = BRANDS.find(brand) if brand is String else int(brand)
	bi = clampi(bi, 0, BRANDS.size() - 1)
	var y0 := lift
	var cy := y0 + h * 0.5
	var fw := 0.09 # frame width
	var depth := 0.16
	# poster: one quad on the board front (z = -depth/2 - 1 mm)
	var px := Rect2((bi % 2) * 1024 + 2, (bi / 2) * 724 + 2, 1020, 720)
	_poly(st, Vector3(0, cy, -depth * 0.5 - 0.004), Vector3(-1, 0, 0), Vector3.UP, _rect_pts(w, h), Vector2(-w * 0.5, -h * 0.5), Vector2(w * 0.5, h * 0.5), px)
	# board box and frame (painted steel), back panel
	var fc: Color = FRAME_COLORS[int(opts.get("frame", 0))]
	g.col = fc
	g.box("painted_metal", Vector3(0, cy, 0.0), Vector3(w + 0.02, h + 0.02, depth))
	g.box("painted_metal", Vector3(0, y0 + h + fw * 0.5, -depth * 0.5 - 0.02), Vector3(w + fw * 2.0, fw, 0.07), 0.01)
	g.box("painted_metal", Vector3(0, y0 - fw * 0.5, -depth * 0.5 - 0.02), Vector3(w + fw * 2.0, fw, 0.07))
	for sx: float in [-1.0, 1.0]:
		g.box("painted_metal", Vector3(sx * (w * 0.5 + fw * 0.5), cy, -depth * 0.5 - 0.02), Vector3(fw, h + fw * 2.0, 0.07))
	# legs: two square steel tubes behind, with diagonal braces and concrete footings
	g.col = Color(0.75, 0.76, 0.78)
	var legx := w * 0.3
	var sink := 0.6
	for sx: float in [-1.0, 1.0]:
		var lx := sx * legx
		var base := Vector3(lx, -sink, depth * 0.5 + 0.12)
		g.box("steel", Vector3(lx, (y0 + h * 0.85 - sink) * 0.5, depth * 0.5 + 0.12), Vector3(0.18, y0 + h * 0.85 + sink, 0.18))
		g.beam("steel", Vector3(lx, y0 * 0.45, depth * 0.5 + 0.12), Vector3(lx * 0.35, y0 + 0.1, depth * 0.5 + 0.1), 0.07)
		g.col = Color(0.85, 0.85, 0.82)
		g.box("concrete", base + Vector3(0, 0.25, 0), Vector3(0.7, 0.7, 0.7))
		g.col = Color(0.75, 0.76, 0.78)
		g.collide(Vector3(lx, y0 * 0.5, depth * 0.5 + 0.12), Vector3(0.3, y0 + 0.4, 0.3))
	g.box("steel", Vector3(0, y0 - 0.12, depth * 0.5 + 0.12), Vector3(legx * 2.0 + 0.18, 0.12, 0.12))
	# back of the board: horizontal rails, vertical struts and diagonals (steel frame, not a slab)
	var bz := depth * 0.5 + 0.05
	for k in 3:
		g.box("steel", Vector3(0, y0 + 0.15 + k * (h - 0.3) * 0.5, bz), Vector3(w - 0.1, 0.08, 0.08))
	for k in 5:
		g.box("steel", Vector3(-w * 0.5 + 0.1 + k * (w - 0.2) / 4.0, cy, bz + 0.04), Vector3(0.06, h - 0.1, 0.06))
	for sx: float in [-1.0, 1.0]:
		g.beam("steel", Vector3(sx * w * 0.45, y0 + 0.15, bz + 0.08), Vector3(sx * w * 0.08, y0 + h - 0.15, bz + 0.08), 0.05)
	# two lamp arms over the top, lamp heads looking down at the poster
	g.col = Color(0.3, 0.31, 0.32)
	for sx: float in [-0.28, 0.28]:
		var top := Vector3(sx * w, y0 + h + fw, -depth * 0.5)
		g.beam("steel", top, top + Vector3(0, 0.3, -0.2), 0.05)
		g.beam("steel", top + Vector3(0, 0.3, -0.2), top + Vector3(0, 0.38, -0.65), 0.05)
		g.box("steel", top + Vector3(0, 0.34, -0.75), Vector3(0.36, 0.1, 0.22))
	g.cast_shadows("painted_metal")
	g.cast_shadows("steel")


static func _post(g: GxGeo, x: float, height: float, z := 0.04) -> void:
	g.col = Color(0.82, 0.83, 0.85)
	g.tube("steel", [Vector3(x, -0.5, z), Vector3(x, height, z)], 0.035, 6, false)
	g.box("steel", Vector3(x, height + 0.02, z), Vector3(0.08, 0.03, 0.08))
	g.collide(Vector3(x, height * 0.5, z), Vector3(0.12, height + 0.5, 0.12))


static func _sign(c: Node3D, st: SurfaceTool, g: GxGeo, r: RandomNumberGenerator, opts: Dictionary, oncoming: float) -> void:
	var kind: String = opts.get("sign", "fans")
	var n := Vector3(0, 0, -1) # face normal (towards the road)
	match kind:
		"fans", "crest":
			var tri := "tri_fans" if kind == "fans" else "tri_crest"
			var plate := "plate_fans" if kind == "fans" else "plate_jump"
			_plate(st, Vector3(0, 2.25, 0), n, 1.0, 0.9, "tri", SIGNS[tri])
			_plate(st, Vector3(0, 1.62, 0), n, 1.0, 0.34, "rect", SIGNS[plate])
			_post(g, 0.0, 2.6)
		"speed":
			var sp := int(opts.get("speed", 50))
			_plate(st, Vector3(0, 2.1, 0), n, 0.75, 0.75, "disc", SIGNS.get("speed%d" % sp, SIGNS.speed50))
			_post(g, 0.0, 2.4)
		"village":
			var sp := int(opts.get("speed", 50))
			_plate(st, Vector3(0, 1.6, 0), n, 1.6, 0.75, "rect", SIGNS.village)
			_plate(st, Vector3(0, 2.55, 0), n, 0.75, 0.75, "disc", SIGNS.get("speed%d" % sp, SIGNS.speed50))
			_post(g, -0.55, 2.85)
			_post(g, 0.55, 2.0)
		_: # chevron boards along the bend
			var count := int(opts.get("count", 3))
			for k in count:
				var x := (k - (count - 1) * 0.5) * 2.6
				# arrows point along the driving direction (put them on the outside of the bend)
				var mirror := (oncoming < 0.0) != bool(opts.get("reverse", false))
				_plate(st, Vector3(x, 1.25, 0), n, 1.0, 0.5, "rect", SIGNS.chevron, mirror)
				_post(g, x, 1.5)
