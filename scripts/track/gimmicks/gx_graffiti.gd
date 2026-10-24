class_name GxGraffiti
extends RefCounted
## Graffiti: REAL photographed street-art walls (pieces, throw-ups, tags,
## stencils; Wikimedia Commons, see assets/CREDITS.txt) on concrete or brick,
## plus hand-drawn tags (ambientCG GraffitiSet001) sprayed over them with
## overspray and drips. Atlases baked by tools/make_gx_graffiti.py.
##
##   GxGraffiti.place(c, Gx.frame(c, 640.0, Gx.RIGHT, 4.0))                 # 8 m free-standing wall
##   GxGraffiti.place(c, xf, {kind = "retaining", length = 30.0, height = 3.5})
##   GxGraffiti.place(c, xf, {kind = "pier", width = 1.6, height = 5.5})      # square pillar, art all round
##   GxGraffiti.spray(c, xf, Vector2(6, 2.4))                    # decal on YOUR surface: a feathered piece
##   GxGraffiti.spray(c, xf, Vector2(1.4, 0.7), {tag = true})    # ... or a single tag
##
## Wall frame: front face on the xf plane (z = 0), facing -z (the road), base
## at y = 0 (sunk into the ground below), centred on x. spray(): xf ON the
## target surface, -z pointing out of it towards the viewer.
## Options: length, height, thick, cells (Array of 0..14), seed, tags (count of
## extra tags), collide (true), vis (vis range, 450).
## To paint your own mesh, use `add_face()` with `wall_material()` (one draw
## call shared with every graffiti wall).
## Cost: a wall = 2 draw calls (photo faces + coping in one mesh, tags), ~100 tris,
## one box collider; ~0.12-0.15 ms to build (first one per track ~15 ms: texture load).

const WALLS := "res://assets/gimmicks/gx_graffiti_walls.png"
const TAGS := "res://assets/gimmicks/gx_graffiti_tags.png"
const PIECES := 15 ## cells 0..14 are photographed walls; 15 = plain concrete
const PLAIN := 15
const BRICK_CELLS := [12] ## brick-wall photos
const TAG_CELLS := [13, 14] ## stencil / tags-only walls
## Realistic spray-can colours for the tags (tint of a white atlas).
const TAG_COLORS := [Color(0.05, 0.05, 0.06), Color(0.06, 0.06, 0.07), Color(0.85, 0.86, 0.88),
	Color(0.62, 0.08, 0.07), Color(0.1, 0.16, 0.42), Color(0.72, 0.74, 0.78), Color(0.8, 0.3, 0.55),
	Color(0.12, 0.35, 0.18)]

static var _wall_mat: ShaderMaterial
static var _decal_mat: ShaderMaterial
static var _tag_mat: ShaderMaterial


## UV rect of a wall cell (2 cols x 8 rows of 1024x512 in a 2048x4096 atlas).
static func cell_rect(cell: int) -> Rect2:
	return Rect2((cell % 2) * 0.5, (cell / 2) * 0.125, 0.5, 0.125)


static func _detail(m: ShaderMaterial, set_name: String) -> void:
	m.set_shader_parameter("detail_nor", Mats.tex(set_name, "nor_gl"))
	m.set_shader_parameter("detail_arm", Mats.tex(set_name, "arm"))
	m.set_shader_parameter("detail_scale", 0.45)


## Opaque material of the photo walls (also for your own meshes: see add_face).
static func wall_material() -> ShaderMaterial:
	if _wall_mat == null:
		_wall_mat = ShaderMaterial.new()
		_wall_mat.shader = load("res://shaders/gx_print.gdshader")
		_wall_mat.set_shader_parameter("atlas", load(WALLS))
		_detail(_wall_mat, "concrete")
		_wall_mat.set_shader_parameter("rough_base", 0.92)
		_wall_mat.set_shader_parameter("normal_strength", 0.9)
	return _wall_mat


static func _decal_material() -> ShaderMaterial:
	if _decal_mat == null:
		_decal_mat = ShaderMaterial.new()
		_decal_mat.shader = load("res://shaders/gx_print_alpha.gdshader")
		_decal_mat.set_shader_parameter("atlas", load(WALLS))
		_detail(_decal_mat, "concrete")
		_decal_mat.set_shader_parameter("rough_base", 0.85)
		_decal_mat.render_priority = 1
	return _decal_mat


static func _tag_material() -> ShaderMaterial:
	if _tag_mat == null:
		_tag_mat = ShaderMaterial.new()
		_tag_mat.shader = load("res://shaders/gx_print_alpha.gdshader")
		_tag_mat.set_shader_parameter("atlas", load(TAGS))
		_detail(_tag_mat, "concrete")
		_tag_mat.set_shader_parameter("rough_base", 0.7)
		_tag_mat.render_priority = 2
	return _tag_mat


## One textured quad into `st`: bottom-left corner `o`, edge vectors `u` (to
## the right as seen by the viewer) and `v` (up), mapped to the part [u0, u1] x
## [v0, v1] (0..1 within the cell, v = 0 at the TOP) of wall `cell`.
## UV2 = metres (for the concrete relief). Normal = u x v towards the viewer.
static func add_face(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, cell: int,
		u0 := 0.0, u1 := 1.0, v0 := 0.0, v1 := 1.0, col := Color.WHITE) -> void:
	var r := cell_rect(cell)
	var px := 1.0 / 2048.0 # stay inside the cell (mip bleeding)
	var ua := r.position.x + px + (r.size.x - 2.0 * px) * u0
	var ub := r.position.x + px + (r.size.x - 2.0 * px) * u1
	var va := r.position.y + px + (r.size.y - 2.0 * px) * v0
	var vb := r.position.y + px + (r.size.y - 2.0 * px) * v1
	_quad(st, o, u, v, Vector2(ua, vb), Vector2(ub, va), col)


## Quad with uv rect (uv_bl = bottom-left, uv_tr = top-right), CW front faces.
static func _quad(st: SurfaceTool, o: Vector3, u: Vector3, v: Vector3, uv_bl: Vector2, uv_tr: Vector2, col: Color) -> void:
	var n := u.cross(v).normalized() # u = viewer's right, v = up: normal towards the viewer
	var lu := u.length()
	var lv := v.length()
	var pts := [o, o + u, o + u + v, o + v]
	var uvs := [uv_bl, Vector2(uv_tr.x, uv_bl.y), uv_tr, Vector2(uv_bl.x, uv_tr.y)]
	var uv2s := [Vector2(0, 0), Vector2(lu, 0), Vector2(lu, -lv), Vector2(0, -lv)]
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.set_uv2(uv2s[k] + Vector2(o.x + o.z, -o.y))
		st.add_vertex(pts[k])


static func _rng(c: Node3D, xf: Transform3D, opts: Dictionary) -> RandomNumberGenerator:
	var r := Gx.rng(c, "graffiti")
	r.seed = hash(str(r.seed) + str(opts.get("seed", Vector3i(xf.origin.round()))))
	return r


## gx_test passes option values as strings: make numbers numbers.
static func _num(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	for k in o:
		if o[k] is String and (o[k] as String).is_valid_float():
			o[k] = float(o[k])
	return o


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	opts = _num(opts)
	xf = GxBillboard.upright(c, xf)[0] # never mirrored (photos would read backwards)
	var kind: String = opts.get("kind", "wall")
	var r := _rng(c, xf, opts)
	var vis: float = opts.get("vis", 450.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tags := SurfaceTool.new()
	tags.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_tags := 0
	var box := [] # collider [centre, size] (local)
	var cells: Array = opts.get("cells", [])
	var pick := func(i: int) -> int:
		if i < cells.size():
			return int(cells[i])
		# mostly full-colour pieces (0..12); the sparser stencil / tag walls only 1 in 8
		return r.randi_range(0, 12) if r.randf() > 0.125 else TAG_CELLS[r.randi() % TAG_CELLS.size()]

	if kind == "pier":
		var w: float = opts.get("width", 1.5)
		var h: float = opts.get("height", 5.0)
		var hw := w * 0.5
		var sink := _sink(c, xf, w)
		# four faces, each a slice of a different photo (aspect kept: slice width w / (2 h))
		var corners := [Vector3(hw, 0, -hw), Vector3(-hw, 0, -hw), Vector3(-hw, 0, hw), Vector3(hw, 0, hw)]
		for f in 4:
			var a: Vector3 = corners[f]
			var b: Vector3 = corners[(f + 1) % 4]
			var cell: int = pick.call(f)
			var span := clampf(w / (h * 2.0), 0.1, 1.0)
			var u0 := r.randf_range(0.0, 1.0 - span)
			add_face(st, a - Vector3(0, sink, 0), b - a, Vector3(0, h + sink, 0), cell, u0, u0 + span)
			n_tags += _tags_on(tags, r, a, (b - a).normalized(), w, h, int(opts.get("tags", 1)))
		box = [Vector3(0, h * 0.5, 0), Vector3(w, h, w)]
	else:
		var retaining := kind == "retaining"
		var h: float = opts.get("height", 3.5 if retaining else 2.8)
		var length: float = opts.get("length", 24.0 if retaining else 8.0)
		var thick: float = opts.get("thick", 0.6 if retaining else 0.3)
		var lean := 0.12 if retaining else 0.0 # top set back (m per m)
		var sink := _sink(c, xf, length)
		var n := maxi(1, roundi(length / (h * 2.1)))
		var pw := length / n
		var x0 := -length * 0.5
		var top := Vector3(0, h, h * lean)
		var bottom_off := Vector3(0, -sink, -sink * lean)
		for i in n:
			var cell: int = pick.call(i)
			if retaining and i >= cells.size() and r.randf() < float(opts.get("plain", 0.1)):
				cell = PLAIN # gets extra tags below
			var o := Vector3(-x0 - i * pw, 0, 0) + bottom_off # frame +x is the viewer's LEFT
			# slightly varied brightness per panel: painted at different times
			var tint := Color.WHITE.darkened(r.randf_range(0.0, 0.12))
			add_face(st, o, Vector3(-pw, 0, 0), top - bottom_off, cell, 0.0, 1.0, 0.0, 1.0, tint)
			var nt := int(opts.get("tags", 2 if cell == PLAIN else 1))
			n_tags += _tags_on(tags, r, Vector3(-x0 - i * pw, 0, 0), Vector3.LEFT, pw, h, nt, lean)
		# back + ends in plain concrete (the back of a retaining wall is buried)
		var bz := thick
		if not retaining:
			# the back is painted too (free-standing walls get sprayed on both sides)
			for i in n:
				add_face(st, Vector3(x0 + i * pw, -sink, bz), Vector3(pw, 0, 0), Vector3(0, h + sink, 0), r.randi_range(0, PIECES - 1),
					0.0, 1.0, 0.0, 1.0, Color.WHITE.darkened(r.randf_range(0.0, 0.12)))
				# tags over the back too (fans and TV cameras see it); dir +x = viewer's right there
				var bo := Vector3(x0 + i * pw, 0, bz)
				n_tags += _tags_on(tags, r, bo, Vector3.RIGHT, pw, h, 1)
		for e: float in [-1.0, 1.0]:
			var ex := length * 0.5 * e
			var front := Vector3(ex, -sink, -sink * lean)
			var back := Vector3(ex, -sink, bz + h * lean * (1.0 if retaining else 0.0))
			var a := back if e > 0.0 else front
			var b := front if e > 0.0 else back
			add_face(st, a, b - a, Vector3(0, h + sink, 0), PLAIN, 0.0, 0.15)
		# concrete coping along the top
		_coping(st, Vector3(0, h, h * lean + thick * 0.5), Vector3(length + 0.08, 0.14, thick + 0.1))
		box = [Vector3(0, h * 0.5, thick * 0.5 + h * lean * 0.5), Vector3(length, h + sink, thick + h * lean)]
	# faces and tags are built in local space (GxGeo bakes the frame itself)
	var mi := Gx.add_mesh(c, st, wall_material(), "GxGraffiti", vis, true)
	mi.transform = xf
	if n_tags > 0:
		Gx.add_mesh(c, tags, _tag_material(), "GxGraffitiTags", vis * 0.6).transform = xf
	if opts.get("collide", true) and not box.is_empty():
		var body := StaticBody3D.new()
		body.name = "GxGraffitiCol"
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = box[1]
		cs.shape = sh
		cs.position = box[0]
		body.add_child(cs)
		body.transform = xf
		c.add_child(body)
	Gx.reserve(c, xf.origin, float(opts.get("length", 8.0)) * 0.6 + 2.0)


## Concrete coping slab (top + 4 sides) into the wall mesh, plain concrete cell.
## `base` = centre of its underside, `size` = (along, height, depth).
static func _coping(st: SurfaceTool, base: Vector3, size: Vector3) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := base.y
	var y1 := base.y + size.y
	var z0 := base.z - hz
	var z1 := base.z + hz
	var col := Color(0.9, 0.9, 0.88)
	var vs := size.y / 4.0 # v span keeps the texel scale roughly right
	add_face(st, Vector3(hx, y0, z0), Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), PLAIN, 0.0, 1.0, 0.0, vs, col) # front
	add_face(st, Vector3(-hx, y0, z1), Vector3(size.x, 0, 0), Vector3(0, size.y, 0), PLAIN, 0.0, 1.0, 0.0, vs, col) # back
	add_face(st, Vector3(hx, y1, z0), Vector3(-size.x, 0, 0), Vector3(0, 0, size.z), PLAIN, 0.0, 1.0, 0.3, 0.3 + vs, col.darkened(0.05)) # top
	add_face(st, Vector3(hx, y0, z1), Vector3(0, 0, -size.z), Vector3(0, size.y, 0), PLAIN, 0.0, 0.05, 0.0, vs, col) # end +x
	add_face(st, Vector3(-hx, y0, z0), Vector3(0, 0, size.z), Vector3(0, size.y, 0), PLAIN, 0.0, 0.05, 0.0, vs, col) # end -x


## How far below the frame origin the base must go to stay buried over `span` metres.
static func _sink(c: Node3D, xf: Transform3D, span: float) -> float:
	var y0 := xf.origin.y
	var lowest := y0
	for k in 5:
		var p := xf * Vector3(lerpf(-span * 0.5, span * 0.5, k / 4.0), 0, 0)
		lowest = minf(lowest, Gx.ground(c, p))
	return clampf(y0 - lowest, 0.0, 3.0) + 0.35


## A few tags sprayed over a face (local o = bottom-left of the face, dir = along it).
static func _tags_on(st: SurfaceTool, r: RandomNumberGenerator, o: Vector3, dir: Vector3, w: float, h: float, count: int, lean := 0.0) -> int:
	var made := 0
	var n := dir.cross(Vector3.UP).normalized() # out of the face (dir = viewer's right)
	for _i in count:
		var tw := r.randf_range(0.7, minf(1.8, w * 0.45))
		var th := tw * r.randf_range(0.45, 0.65)
		var y := r.randf_range(0.25, minf(h - th - 0.1, 1.9)) # within arm's reach
		var x := r.randf_range(0.05, maxf(0.06, w - tw - 0.05))
		var p := o + dir * x + Vector3(0, y, y * lean) + n * 0.012
		var cell := r.randi_range(0, 15)
		var uvr := Rect2((cell % 4) * 0.25, (cell / 4) * 0.25, 0.25, 0.25)
		var col: Color = TAG_COLORS[r.randi() % TAG_COLORS.size()]
		col.a = r.randf_range(0.75, 0.95)
		_quad(st, p, dir * tw, Vector3(0, th, th * lean), Vector2(uvr.position.x, uvr.end.y), Vector2(uvr.end.x, uvr.position.y), col)
		made += 1
	return made


## Decal-style graffiti on someone else's surface: xf sits ON the surface with
## -z pointing out of it. `size` in metres (x along, y up). opts: tag (bool),
## cell (wall cell 0..14 or tag cell 0..15), color (tags), seed.
static func spray(c: Node3D, xf: Transform3D, size: Vector2, opts := {}) -> void:
	opts = _num(opts)
	xf = GxBillboard.upright(c, xf)[0]
	var r := _rng(c, xf, opts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := Vector3(size.x * 0.5, -size.y * 0.5, -0.015) # frame +x is the viewer's left
	var tag: bool = opts.get("tag", false)
	if tag:
		var cell := int(opts.get("cell", r.randi_range(0, 15)))
		var uvr := Rect2((cell % 4) * 0.25, (cell / 4) * 0.25, 0.25, 0.25)
		var col: Color = opts.get("color", TAG_COLORS[r.randi() % TAG_COLORS.size()])
		_quad(st, o, Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), Vector2(uvr.position.x, uvr.end.y), Vector2(uvr.end.x, uvr.position.y), col)
	else:
		var cell := int(opts.get("cell", r.randi_range(0, PIECES - 1)))
		add_face(st, o, Vector3(-size.x, 0, 0), Vector3(0, size.y, 0), cell)
	var mi := Gx.add_mesh(c, st, _tag_material() if tag else _decal_material(), "GxGraffitiSpray", float(opts.get("vis", 300.0)))
	mi.transform = xf
