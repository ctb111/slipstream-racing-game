class_name TrackProps
extends RefCounted
## Trackside detail for a circuit: start/finish + grid + gantry, pits and
## grandstand, bridge, brake boards, corner chevrons, advertising, tyre walls,
## hay bales, catch fences, marshal posts, flags, bushes and rocks.
##
## `curve` must start at the start/finish line (offset 0) and run in the
## direction of travel. Geometry is merged per material, printed faces share
## one texture atlas, so the whole lot costs a few dozen draw calls.

const STEP := 2.0
const RAIL_FROM_EDGE := TrackBuilder.CURB_WIDTH
const ATLAS_SIZE := Vector2i(2048, 1024)

# Invented period sponsors (no real trademarks): text, background, ink, accent.
const BRANDS := [
	["VALTER OIL", Color(0.08, 0.12, 0.25), Color(0.92, 0.88, 0.78), Color(0.62, 0.1, 0.08)],
	["HALDEN TYRES", Color(0.04, 0.04, 0.045), Color(0.95, 0.72, 0.22), Color(0.95, 0.72, 0.22)],
	["MARZELLI", Color(0.34, 0.06, 0.07), Color(0.93, 0.88, 0.78), Color(0.93, 0.88, 0.78)],
	["NORDLICHT", Color(0.07, 0.2, 0.13), Color(0.94, 0.94, 0.9), Color(0.75, 0.62, 0.25)],
	["HELIOS BENZIN", Color(0.9, 0.86, 0.75), Color(0.06, 0.06, 0.06), Color(0.8, 0.35, 0.08)],
	["BERGMANN", Color(0.28, 0.3, 0.32), Color(0.95, 0.95, 0.93), Color(0.8, 0.12, 0.1)],
	["AUREL WATCHES", Color(0.03, 0.03, 0.03), Color(0.8, 0.66, 0.36), Color(0.8, 0.66, 0.36)],
	["OSTRA FILM", Color(0.05, 0.24, 0.27), Color(0.95, 0.95, 0.9), Color(0.9, 0.7, 0.2)],
]

var parent: Node3D
var curve: Curve3D
var width := 12.0
var noise_tex: Texture2D
var half := 6.0

var centers: Array[Vector3] = []
var rights: Array[Vector3] = []
var tangents: Array[Vector3] = []
var corner: Array[float] = []
var n := 0

var mats := {}
var tools := {}
var uv := {} ## atlas regions, normalised Rect2 per key
var colliders: StaticBody3D
var no_trees: Array = [] ## [centre: Vector3, radius: float] kept clear of forest
var terrain: Terrain


static func build(p_parent: Node3D, p_curve: Curve3D, road_width: float, p_noise: Texture2D) -> void:
	var t := TrackProps.new()
	t.parent = p_parent
	t.curve = p_curve
	t.width = road_width
	t.half = road_width * 0.5
	t.noise_tex = p_noise
	t.terrain = p_parent.get_meta("terrain", null)
	t._run()


func _run() -> void:
	_sample()
	_make_materials()
	colliders = StaticBody3D.new()
	colliders.name = "PropColliders"
	colliders.set_meta("grip", 0.3)
	var slick := PhysicsMaterial.new()
	slick.friction = 0.1
	colliders.physics_material_override = slick
	parent.add_child(colliders)

	_start_finish()
	_pits_and_grandstand()
	_bridge()
	_corner_furniture()
	_ad_boards()
	_marshal_posts()
	_scatter()

	for key in tools:
		var st: SurfaceTool = tools[key]
		var mi := MeshInstance3D.new()
		mi.name = "Props_" + key
		mi.mesh = st.commit()
		mi.material_override = mats[key]
		if key in ["paint", "print_road"]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
	parent.set_meta("no_trees", no_trees)


# ---------------------------------------------------------------- sampling

func _sample() -> void:
	var length := curve.get_baked_length()
	n = int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var ahead := curve.sample_baked(fmod(off + 1.0, length))
		var behind := curve.sample_baked(fmod(off - 1.0 + length, length))
		var t := (ahead - behind).normalized()
		centers.append(p)
		tangents.append(t)
		rights.append(t.cross(Vector3.UP).normalized())
	corner = TrackBuilder._corner_factors(centers)


func _i(k: int) -> int:
	return posmod(k, n)


## Distance from the centreline to the guardrail on `side` (+1 right, -1 left),
## matching TrackBuilder's rail placement.
func rail_dist(i: int, side: float) -> float:
	var c: float = corner[_i(i)]
	var outside := c * side > 0.0
	var depth := TrackBuilder.GRAVEL_MAX * absf(c) if outside else 0.0
	return half + RAIL_FROM_EDGE + maxf(TrackBuilder.RAIL_GAP, depth + 3.0)


## Point `lateral` metres off the centreline. On the road it's road height,
## beyond the kerbs it sits on the terrain.
func at(i: int, lateral: float, height := 0.0) -> Vector3:
	var k := _i(i)
	var p := centers[k] + rights[k] * lateral
	if terrain and absf(lateral) > half + 1.5:
		p.y = terrain.height_at(p.x, p.z)
	return p + Vector3.UP * height


## Longest run of near-straight samples around index `i` (each way, in samples).
func straight_extent(i: int, dir: int, max_samples: int) -> int:
	var k := 0
	while k < max_samples and absf(corner[_i(i + k * dir)]) < 0.1:
		k += 1
	return k


# ---------------------------------------------------------------- materials

func _mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_materials() -> void:
	var atlas := _build_atlas()
	var printed := _mat(Color.WHITE, 0.65)
	printed.albedo_texture = atlas
	printed.cull_mode = BaseMaterial3D.CULL_BACK
	printed.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats.print = printed
	var road_print := printed.duplicate()
	road_print.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats.print_road = road_print
	var paint := _mat(Color(0.82, 0.82, 0.78), 0.6)
	mats.paint = paint
	# Photographic PBR sets (Mats, world-space mapped; shared instances).
	mats.metal = Mats.mat("steel") # galvanised poles, rails, fence posts
	mats.dark_metal = Mats.mat("painted_metal", Color(0.11, 0.12, 0.12)) # gantry, frames, columns
	mats.concrete = Mats.mat("concrete")
	mats.render = Mats.mat("plaster", Color(0.86, 0.83, 0.76)) # painted building walls
	mats.roof = Mats.mat("concrete_tint", Color(0.5, 0.5, 0.5)) # flat felt / concrete roofs
	mats.glass = Mats.mat("glass")
	mats.door = Mats.mat("corrugated", Color(0.42, 0.46, 0.47)) # roller shutters
	mats.seat = Mats.mat("painted_wood", Color(0.3, 0.38, 0.5))
	mats.tyre = Mats.mat("rubber", Color(0.05, 0.05, 0.05))
	var straw := _mat(Color(0.72, 0.6, 0.36), 0.95)
	straw.albedo_texture = noise_tex
	straw.uv1_scale = Vector3(3, 3, 3)
	mats.straw = straw
	var fence := _mat(Color(0.5, 0.52, 0.52), 0.5, 0.7)
	fence.albedo_texture = _chainlink_texture()
	fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	fence.alpha_scissor_threshold = 0.5
	fence.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	fence.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats.fence = fence
	var weather = parent.get("weather") # bushes rustle, get wet and snowed on
	var wx: Dictionary = weather.preset if weather is Weather else {}
	mats.foliage = Vegetation.broadleaf_material(noise_tex, 0.45, wx.get("snow", 0.0) * 0.8, wx.get("wet", 0.0))
	mats.rock = _rock_meshes()[0][1]
	var flag := ShaderMaterial.new()
	flag.shader = load("res://shaders/flag.gdshader")
	var circuit_weather = parent.get("weather")
	var wind := 0.45
	if circuit_weather:
		wind = [0.45, 1.0, 0.7, 0.35, 0.25, 0.15][circuit_weather.kind]
	flag.set_shader_parameter("wind", wind)
	flag.set_shader_parameter("flag_length", 2.4)
	flag.set_shader_parameter("atlas", atlas)
	mats.flag = flag
	for key in mats:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[key] = st


func _flag_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
void vertex() {
	// UV2.x = 0 at the pole, 1 at the free end: wave grows along the flag.
	float free_end = UV2.x;
	float wave = sin(TIME * 5.0 + VERTEX.x * 1.7 + VERTEX.z * 1.7) * 0.18 + sin(TIME * 8.3 + VERTEX.y * 3.0) * 0.05;
	VERTEX += NORMAL * wave * free_end;
}
void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.9;
}
"""
	return s


## Printed graphics (sponsors, brake boards, chevrons, flags, banners) drawn
## once into a SubViewport, then copied into a mipmapped texture.
func _build_atlas() -> Texture2D:
	var vp := SubViewport.new()
	vp.size = ATLAS_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	var root := Control.new()
	root.size = Vector2(ATLAS_SIZE)
	vp.add_child(root)
	var bold: Font = load(UiTheme.FONT_BOLD)
	var cell := Vector2(512, 128)
	for i in BRANDS.size():
		var b: Array = BRANDS[i]
		var r := Rect2(Vector2(i % 4, i / 4) * cell, cell)
		_draw_panel(root, r, b[1], b[0], b[2], b[3], bold, 76)
		uv["brand%d" % i] = r
	_draw_panel(root, Rect2(0, 256, 1024, 128), Color(0.05, 0.05, 0.055), "START  ·  FINISH", Color(0.94, 0.94, 0.9), Color(0.62, 0.1, 0.08), bold, 84)
	uv.start = Rect2(0, 256, 1024, 128)
	_draw_panel(root, Rect2(1024, 256, 1024, 128), Color(0.9, 0.86, 0.75), "GRAND PRIX", Color(0.06, 0.06, 0.06), Color(0.08, 0.12, 0.25), bold, 84)
	uv.gp = Rect2(1024, 256, 1024, 128)
	for k in 3:
		var r := Rect2(k * 256, 384, 256, 256)
		_draw_panel(root, r, Color(0.94, 0.94, 0.91), str((3 - k) * 100), Color(0.04, 0.04, 0.04), Color(0, 0, 0, 0), bold, 130)
		uv["brake%d" % ((3 - k) * 100)] = r
	# Chevron board: white arrows on black, pointing right.
	var chev := Rect2(768, 384, 256, 256)
	_rect(root, chev, Color(0.03, 0.03, 0.03))
	for k in 2:
		var x0 := chev.position.x + 40 + k * 95
		var y0 := chev.position.y + 40
		var poly := Polygon2D.new()
		poly.color = Color(0.95, 0.95, 0.92)
		poly.polygon = PackedVector2Array([Vector2(x0, y0), Vector2(x0 + 45, y0), Vector2(x0 + 110, y0 + 88),
			Vector2(x0 + 45, y0 + 176), Vector2(x0, y0 + 176), Vector2(x0 + 65, y0 + 88)])
		root.add_child(poly)
	uv.chevron = chev
	# Tricolour-style flags (invented clubs), and a checker for the finish line.
	var flag_cols := [[Color(0.1, 0.2, 0.45), Color(0.92, 0.9, 0.85), Color(0.6, 0.08, 0.07)],
		[Color(0.1, 0.3, 0.16), Color(0.92, 0.9, 0.85), Color(0.75, 0.6, 0.15)],
		[Color(0.05, 0.05, 0.05), Color(0.8, 0.6, 0.12), Color(0.6, 0.08, 0.07)],
		[Color(0.92, 0.9, 0.85), Color(0.08, 0.2, 0.4), Color(0.92, 0.9, 0.85)]]
	for k in flag_cols.size():
		var r := Rect2(1024 + k * 256, 384, 256, 160)
		for band in 3:
			_rect(root, Rect2(r.position + Vector2(0, band * 160.0 / 3.0), Vector2(256, 160.0 / 3.0 + 1)), flag_cols[k][band])
		uv["flag%d" % k] = r
	var check := Rect2(0, 640, 512, 64)
	for cx in 32:
		for cy in 4:
			_rect(root, Rect2(check.position + Vector2(cx, cy) * 16, Vector2(16, 16)),
				Color(0.9, 0.9, 0.87) if (cx + cy) % 2 == 0 else Color(0.05, 0.05, 0.05))
	uv.checker = check
	_rect(root, Rect2(512, 640, 64, 64), Color(0.9, 0.9, 0.86)) # plain white paint
	uv.white = Rect2(516, 644, 56, 56)
	for key in uv:
		var r: Rect2 = uv[key]
		uv[key] = Rect2(r.position / Vector2(ATLAS_SIZE), r.size / Vector2(ATLAS_SIZE))

	parent.add_child(vp)
	var baker := AtlasBaker.new()
	baker.viewport = vp
	parent.add_child(baker)
	return baker.texture


func _rect(root: Control, r: Rect2, c: Color) -> void:
	var cr := ColorRect.new()
	cr.position = r.position
	cr.size = r.size
	cr.color = c
	root.add_child(cr)


func _draw_panel(root: Control, r: Rect2, bg: Color, text: String, ink: Color, accent: Color, font: Font, size: int) -> void:
	_rect(root, r, bg)
	if accent.a > 0.0:
		_rect(root, Rect2(r.position + Vector2(0, r.size.y - 14), Vector2(r.size.x, 8)), accent)
	var l := Label.new()
	l.text = text
	l.position = r.position
	l.size = r.size - Vector2(0, 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ink)
	root.add_child(l)


func _chainlink_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for t in s:
		for w in 2:
			img.set_pixel((t + w) % s, t, Color(1, 1, 1, 1))
			img.set_pixel((s - 1 - t + w) % s, t, Color(1, 1, 1, 1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Copies the atlas SubViewport into a mipmapped ImageTexture after it renders.
class AtlasBaker:
	extends Node
	var viewport: SubViewport
	var texture := ImageTexture.new()

	func _init() -> void:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.5, 0.5, 0.5))
		texture.set_image(img)

	func _ready() -> void:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := viewport.get_texture().get_image()
		if img and not img.is_empty():
			img.convert(Image.FORMAT_RGBA8)
			img.generate_mipmaps()
			texture.set_image(img)
		viewport.queue_free()
		queue_free()


# ---------------------------------------------------------------- geometry helpers

func _prim(key: String, mesh: PrimitiveMesh, xf: Transform3D) -> void:
	tools[key].append_from(mesh, 0, xf)


func _box(key: String, centre: Vector3, size: Vector3, basis := Basis(), collide := false) -> void:
	var b := BoxMesh.new()
	b.size = size
	_prim(key, b, Transform3D(basis, centre))
	if collide:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = Transform3D(basis, centre)
		colliders.add_child(cs)


func _cyl(key: String, centre: Vector3, radius: float, height: float, basis := Basis(), segments := 12) -> void:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	_prim(key, c, Transform3D(basis, centre))


## A printed rectangle facing `normal`, `right` = the viewer's right.
func _face(key: String, centre: Vector3, right: Vector3, up: Vector3, w: float, h: float, region: Rect2, flip := false) -> void:
	var st: SurfaceTool = tools[key]
	var r := right.normalized() * w * 0.5
	var u := up.normalized() * h * 0.5
	var nrm := right.cross(up).normalized()
	var u0 := region.position.x
	var u1 := region.end.x
	if flip:
		var tmp := u0
		u0 = u1
		u1 = tmp
	var corners := [[centre - r + u, Vector2(u0, region.position.y)], [centre + r + u, Vector2(u1, region.position.y)],
		[centre + r - u, Vector2(u1, region.end.y)], [centre - r - u, Vector2(u0, region.end.y)]]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(nrm)
		st.set_uv(corners[k][1])
		st.set_uv2(Vector2(0, 0))
		st.add_vertex(corners[k][0])


## Board on a post: printed face plus a plain back and two legs.
func _board(centre: Vector3, facing: Vector3, w: float, h: float, region: Rect2, flip := false, legs := true) -> void:
	facing = Vector3(facing.x, 0, facing.z).normalized()
	var right := Vector3.UP.cross(facing).normalized() # viewer's right when looking against `facing`
	_face("print", centre, right, Vector3.UP, w, h, region, flip)
	_box("dark_metal", centre - facing * 0.04, Vector3(w + 0.06, h + 0.06, 0.06), Basis.looking_at(-facing, Vector3.UP))
	if legs:
		var ground := centre.y - h * 0.5
		for sx: float in [-0.38, 0.38]:
			var leg := centre + right * w * sx - facing * 0.07
			leg.y = ground * 0.5
			_box("dark_metal", leg, Vector3(0.08, ground, 0.08))


# ---------------------------------------------------------------- start / finish

func _start_finish() -> void:
	var t := tangents[0]
	var r := rights[0]
	# Checkered band across the road, just past the line.
	_face("print_road", centers[0] + Vector3.UP * 0.03 + t * 0.8, r, t, width - 0.4, 1.6, uv.checker)
	_face("print_road", centers[0] + Vector3.UP * 0.03 - t * 0.12, r, t, width - 0.4, 0.24, uv.white)
	# Grid boxes, matching Circuit.grid_transform (12 m + 8 m per slot back, ±2.8 m).
	for slot in 12:
		var back := 12.0 + slot * 8.0
		var k := -int(round(back / STEP))
		var lat := -2.8 if slot % 2 == 0 else 2.8
		var c := at(k, lat, 0.03)
		var tk := tangents[_i(k)]
		var rk := rights[_i(k)]
		_face("print_road", c + tk * 2.5, rk, tk, 2.4, 0.15, uv.white) # front line
		_face("print_road", c + tk * 0.3 - rk * 1.15, rk, tk, 0.12, 4.4, uv.white)
		_face("print_road", c + tk * 0.3 + rk * 1.15, rk, tk, 0.12, 4.4, uv.white)

	# Gantry with five start lights spanning the track.
	var d := maxf(rail_dist(0, 1.0), rail_dist(0, -1.0)) + 0.8
	var basis := Basis.looking_at(t, Vector3.UP)
	for side: float in [-1.0, 1.0]:
		_box("dark_metal", at(0, d * side, 3.7), Vector3(0.6, 7.4, 0.6), basis, true)
	var beam := at(0, 0, 7.0)
	_box("dark_metal", beam, Vector3(d * 2.0 + 0.6, 1.1, 0.8), basis)
	_face("print", beam - t * 0.42 + Vector3.UP * 1.25, r, Vector3.UP, 9.0, 1.1, uv.start)
	_box("dark_metal", beam + Vector3.UP * 1.25 - t * 0.3, Vector3(9.1, 1.2, 0.1), basis)
	var lights := []
	for k in 5:
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(0.12, 0.02, 0.02)
		lamp.emission_enabled = true
		lamp.emission = Color(1.0, 0.06, 0.03)
		lamp.emission_energy_multiplier = 0.0
		lamp.roughness = 0.2
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.22
		sphere.height = 0.44
		sphere.radial_segments = 16
		sphere.rings = 8
		mi.mesh = sphere
		mi.material_override = lamp
		mi.position = beam - t * 0.45 + r * (k - 2) * 0.75
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		lights.append(lamp)
	parent.set_meta("start_lights", lights)


func _pits_and_grandstand() -> void:
	var back := straight_extent(0, -1, 75)
	var fwd := straight_extent(0, 1, 40)
	if back + fwd < 20:
		return
	var i0 := -back + 2
	var i1 := fwd - 2
	var mid := (i0 + i1) / 2
	var length := (i1 - i0) * STEP
	var t := tangents[_i(mid)]
	var r := rights[_i(mid)]
	var basis := Basis(r, Vector3.UP, -t) # x across the track, -z along travel

	# Pit building on the right: garages at the bottom, glazed floor above, flat roof.
	var pd := rail_dist(mid, 1.0) + 14.0 # pit lane between wall and garages
	var pc := at(mid, pd, 0.0)
	var depth := 12.0
	_box("render", pc + Vector3.UP * 3.5, Vector3(depth, 7.0, length), basis, true)
	_box("roof", pc + Vector3.UP * 7.15 - r * 1.2, Vector3(depth + 2.8, 0.3, length + 1.0), basis)
	_box("glass", pc - r * (depth * 0.5 + 0.02) + Vector3.UP * 5.4, Vector3(0.05, 1.8, length - 1.0), basis)
	var doors := int(length / 7.0)
	for k in doors:
		var z := (k + 0.5) / doors - 0.5
		var door_c := pc - r * (depth * 0.5 + 0.03) + t * z * length + Vector3.UP * 1.7
		_box("door", door_c, Vector3(0.05, 3.3, 5.2), basis)
	_box("concrete", at(mid, rail_dist(mid, 1.0) + 2.0, 0.55), Vector3(0.4, 1.1, length), basis) # pit wall
	# Control tower at the far end of the pits.
	var tower := at(i1 - 3, pd - 1.0, 0.0)
	_box("render", tower + Vector3.UP * 6.0, Vector3(5, 12, 5), basis, true)
	_box("glass", tower + Vector3.UP * 13.4, Vector3(5.6, 2.6, 5.6), basis)
	_box("roof", tower + Vector3.UP * 14.9, Vector3(6.6, 0.4, 6.6), basis)
	no_trees.append([pc, length * 0.5 + 20.0])

	# Grandstand on the left: stepped terraces, seats, crowd, roof on columns.
	var gd := rail_dist(mid, -1.0) + 5.0
	var glen := minf(length * 0.8, 110.0)
	var tiers := 9
	var crowd_xf: Array[Transform3D] = []
	var crowd_col: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var shirt := [Color(0.55, 0.52, 0.48), Color(0.2, 0.25, 0.35), Color(0.45, 0.12, 0.1), Color(0.16, 0.2, 0.16),
		Color(0.7, 0.66, 0.55), Color(0.12, 0.12, 0.13), Color(0.5, 0.42, 0.25), Color(0.32, 0.35, 0.42)]
	for k in tiers:
		var c := at(mid, -(gd + k * 1.0 + 0.5), 0.0)
		_box("concrete", c + Vector3.UP * (k * 0.55 + 0.3), Vector3(1.0, k * 1.1 + 0.6, glen), basis, k == 0)
		_box("seat", c + Vector3.UP * (k * 1.1 + 0.68) + r * 0.25, Vector3(0.45, 0.16, glen - 0.4), basis)
		var people := int(glen / 0.62)
		for p in people:
			if rng.randf() < 0.25:
				continue
			var along := (p + 0.5) / people - 0.5
			var pos := c + t * along * glen + Vector3.UP * (k * 1.1 + 0.76) + r * 0.1
			var s := rng.randf_range(0.9, 1.1)
			crowd_xf.append(Transform3D(Basis.looking_at(r, Vector3.UP).scaled(Vector3(s, s, s)), pos))
			crowd_col.append(shirt[rng.randi() % shirt.size()])
	var top := at(mid, -(gd + tiers + 0.5), 0.0)
	_box("render", top + Vector3.UP * (tiers * 0.55 + 1.6), Vector3(0.4, tiers * 1.1 + 3.2, glen), basis)
	for k in 6:
		var along := k / 5.0 - 0.5
		_box("dark_metal", at(mid, -(gd - 0.3), 0.0) + t * along * glen + Vector3.UP * (tiers * 0.55 + 1.7), Vector3(0.3, tiers * 1.1 + 3.4, 0.3), basis)
	_box("roof", at(mid, -(gd + tiers * 0.5), tiers * 1.1 + 3.4), Vector3(tiers + 2.5, 0.25, glen + 2.0), basis)
	_face("print", at(mid, -(gd - 0.35), tiers * 1.1 + 2.6), -t, Vector3.UP, 16.0, 2.0, uv.gp)
	_crowd(crowd_xf, crowd_col)
	no_trees.append([at(mid, -(gd + tiers * 0.5)), glen * 0.5 + 18.0])

	# Flags along the back of the straight.
	for k in 8:
		var along := i0 + (i1 - i0) * (k + 0.5) / 8.0
		_flagpole(at(int(along), pd - depth * 0.5 - 1.5, 0.0), k % 4)


## Spectators: torso + head as one merged mesh, vertex coloured.
func _crowd(xfs: Array[Transform3D], cols: Array[Color]) -> void:
	var custom: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in xfs.size():
		custom.append(Color(rng.randf(), rng.randf_range(0.0, 0.6), 0.0, 0.0))
	if OS.get_cmdline_user_args().has("--debug-people") and not xfs.is_empty():
		var m := xfs[xfs.size() / 2]
		print("grandstand mid ", m.origin, " facing ", -m.basis.z.normalized())
	parent.add_child(PeopleKit.crowd("Grandstand", PeopleKit.Role.SEATED, xfs, cols, custom, false))


func _flagpole(base: Vector3, flag_idx: int) -> void:
	_cyl("metal", base + Vector3.UP * 4.5, 0.05, 9.0, Basis(), 8)
	var st: SurfaceTool = tools["flag"]
	var region: Rect2 = uv["flag%d" % flag_idx]
	var w := 2.4
	var h := 1.5
	var cols := 12
	var rows := 6
	# All flags blow roughly downwind, each a little differently.
	var yaw := 0.3 + randf_range(-0.25, 0.25)
	var dir := Vector3(cos(yaw), 0, sin(yaw))
	var top := base + Vector3.UP * 8.8
	var tag := Color(dir.x * 0.5 + 0.5, dir.z * 0.5 + 0.5, randf(), 1.0) # per-flag data for the shader
	var nrm := dir.cross(Vector3.UP).normalized()
	for c in cols:
		for r in rows:
			var x0 := float(c) / cols
			var x1 := float(c + 1) / cols
			var y0 := float(r) / rows
			var y1 := float(r + 1) / rows
			var quad := [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
			for k in [0, 1, 2, 0, 2, 3]:
				var q: Array = quad[k]
				st.set_color(tag)
				st.set_normal(nrm)
				st.set_uv(Vector2(lerpf(region.position.x, region.end.x, q[0]), lerpf(region.position.y, region.end.y, q[1])))
				st.set_uv2(Vector2(q[0], q[1]))
				st.add_vertex(top + dir * w * q[0] + Vector3.DOWN * h * q[1])


# ---------------------------------------------------------------- bridge

func _bridge() -> void:
	# Middle of the longest straight in the second half of the lap.
	var best := -1
	var best_len := 0
	var k := n / 3
	while k < n - 20:
		var run := straight_extent(k, 1, 200)
		if run > best_len:
			best_len = run
			best = k
		k += maxi(run, 1)
	if best < 0 or best_len < 30:
		return
	var i := _i(best + best_len / 2)
	var t := tangents[i]
	var basis := Basis.looking_at(t, Vector3.UP)
	var d := maxf(rail_dist(i, 1.0), rail_dist(i, -1.0)) + 1.2
	for side: float in [-1.0, 1.0]:
		var foot := at(i, d * side, 0.0)
		_box("concrete", foot + Vector3.UP * 4.0, Vector3(2.4, 8.0, 3.0), basis, true)
		_box("concrete", foot + Vector3.UP * 4.5 + rights[i] * side * 3.0, Vector3(4.0, 0.3, 2.2), basis) # stair landing
	var deck := at(i, 0.0, 7.4)
	_box("concrete", deck, Vector3(d * 2.0 + 2.4, 0.7, 3.0), basis)
	_box("metal", deck + Vector3.UP * 0.95, Vector3(d * 2.0 + 2.4, 0.08, 3.0), basis)
	for face_dir: float in [-1.0, 1.0]:
		var face_t := t * face_dir
		var right := Vector3.UP.cross(-face_t).normalized()
		for b in 3:
			var off := (b - 1) * 8.4
			_face("print", deck - face_t * 1.52 + right * off + Vector3.UP * 0.35, right, Vector3.UP, 8.0, 2.0, uv["brand%d" % ((b + (2 if face_dir > 0 else 5)) % BRANDS.size())])
	no_trees.append([deck, d + 6.0])


# ---------------------------------------------------------------- corners

func _corner_furniture() -> void:
	var tyre_xf: Array[Transform3D] = []
	var in_corner := false
	var entry := 0
	for i in n:
		var c: float = absf(corner[i])
		if not in_corner and c > 0.35:
			in_corner = true
			entry = i
			_brake_boards(i)
		elif in_corner and c < 0.25:
			in_corner = false
			_corner_run(entry, i, tyre_xf)
	_tyre_walls(tyre_xf)


func _brake_boards(entry: int) -> void:
	# Only before real braking zones: a long enough straight before the corner.
	# Corner strength is smoothed, so first walk back to where the straight ends.
	var k0 := entry
	while absf(corner[_i(k0)]) >= 0.1 and entry - k0 < 60:
		k0 -= 1
	var run := (entry - k0) + straight_extent(k0, -1, 160)
	if run < 70:
		return
	var turn: float = corner[_i(entry + 6)]
	var side := -1.0 if turn > 0.0 else 1.0 # outside of the coming corner
	for m in [100, 200, 300]:
		if m / STEP > run:
			continue
		var k := entry - int(m / STEP)
		var p := at(k, side * (rail_dist(k, side) - 0.6), 1.3)
		_board(p, -tangents[_i(k)], 1.1, 1.1, uv["brake%d" % m])


func _corner_run(entry: int, exit: int, tyre_xf: Array[Transform3D]) -> void:
	var peak := 0.0
	var apex := entry
	for i in range(entry, exit + 1):
		if absf(corner[_i(i)]) > peak:
			peak = absf(corner[_i(i)])
			apex = i
	var turn: float = corner[_i(apex)]
	var outside := 1.0 if turn > 0.0 else -1.0 # a left turn's outside is on the right
	# Chevrons along the outside, angled to face oncoming cars.
	var every := 5
	var i := entry
	while i <= apex + (exit - apex) / 2:
		var k := _i(i)
		var p := at(k, outside * (rail_dist(k, outside) - 0.5), 1.05)
		var facing := (-tangents[k] - rights[k] * outside * 0.5).normalized()
		_board(p, facing, 0.9, 0.9, uv.chevron, turn > 0.0)
		i += every
	# Tyre wall in front of the rail through the heart of tight corners.
	if peak > 0.55:
		for j in range(apex - 12, apex + 13):
			var k := _i(j)
			var d := rail_dist(k, outside) - 0.55
			for row in 3:
				var p := at(k, outside * d, 0.14 + row * 0.26)
				tyre_xf.append(Transform3D(Basis(), p))
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.7, 0.8, STEP + 0.1)
			cs.shape = shape
			cs.transform = Transform3D(Basis.looking_at(tangents[k], Vector3.UP), at(k, outside * d, 0.4))
			colliders.add_child(cs)
		# Catch fence behind the rail on the outside.
		_catch_fence(apex - 25, apex + 25, outside)
	# Hay bales on the inside at the apex, well clear of the kerb.
	if peak > 0.45:
		var inside := -outside
		for b in 3:
			var k := _i(apex - 4 + b * 4)
			var p := at(k, inside * (half + TrackBuilder.CURB_WIDTH + 3.5 + (b % 2) * 1.6), 0.7)
			var basis := Basis.looking_at(tangents[k], Vector3.UP) * Basis(Vector3.BACK, PI * 0.5)
			_cyl("straw", p, 0.7, 1.3, basis, 14)
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.7
			shape.height = 1.3
			cs.shape = shape
			cs.transform = Transform3D(basis, p)
			colliders.add_child(cs)


func _tyre_walls(xfs: Array[Transform3D]) -> void:
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.3
	tyre.bottom_radius = 0.3
	tyre.height = 0.25
	tyre.radial_segments = 10
	tyre.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tyre
	mm.instance_count = xfs.size()
	for k in xfs.size():
		mm.set_instance_transform(k, xfs[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TyreWalls"
	mmi.multimesh = mm
	mmi.material_override = mats.tyre
	parent.add_child(mmi)


func _catch_fence(i0: int, i1: int, side: float) -> void:
	var st: SurfaceTool = tools["fence"]
	var h := 3.2
	var u := 0.0
	for i in range(i0, i1):
		var a := at(i, side * (rail_dist(i, side) + 1.6))
		var b := at(i + 1, side * (rail_dist(i + 1, side) + 1.6))
		var seg := a.distance_to(b)
		var nrm := (b - a).cross(Vector3.UP).normalized()
		var quad := [[a, u, 0.0], [b, u + seg, 0.0], [b + Vector3.UP * h, u + seg, h], [a + Vector3.UP * h, u, h]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(nrm)
			st.set_uv(Vector2(quad[k][1], quad[k][2]) * 3.0)
			st.add_vertex(quad[k][0])
		u += seg
		if i % 2 == 0:
			_box("metal", a + Vector3.UP * h * 0.5, Vector3(0.07, h, 0.07))
	no_trees.append([at((i0 + i1) / 2, side * (rail_dist((i0 + i1) / 2, side) + 2.0)), (i1 - i0) * STEP * 0.5 + 6.0])


# ---------------------------------------------------------------- advertising & marshals

func _ad_boards() -> void:
	var brand := 0
	var i := 30
	while i < n - 10:
		if absf(corner[_i(i)]) < 0.15 and absf(corner[_i(i + 3)]) < 0.15:
			for side: float in [-1.0, 1.0]:
				if (i / 30 + int(side > 0)) % 2 == 0:
					continue
				var k := _i(i)
				var p := at(k, side * (rail_dist(k, side) + 0.35), 1.35)
				var facing := (-rights[k] * side - tangents[k] * 0.55).normalized()
				_board(p, facing, 4.2, 1.05, uv["brand%d" % (brand % BRANDS.size())])
				brand += 1
		i += 30


func _marshal_posts() -> void:
	var i := 90
	var side := 1.0
	while i < n - 40:
		var k := _i(i)
		var base := at(k, side * (rail_dist(k, side) + 3.0))
		var basis := Basis.looking_at(tangents[k], Vector3.UP)
		_box("render", base + Vector3.UP * 1.1, Vector3(1.8, 2.2, 1.6), basis, true)
		_box("roof", base + Vector3.UP * 2.3, Vector3(2.4, 0.15, 2.2), basis)
		_box("glass", base + Vector3.UP * 1.5 - rights[k] * side * 0.82, Vector3(0.05, 0.6, 1.2), basis)
		_flagpole(base + tangents[k] * 1.6 - rights[k] * side * 0.6, (i / 90) % 4)
		no_trees.append([base, 6.0])
		i += 220
		side = -side


# ---------------------------------------------------------------- vegetation & rocks

func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var bush_meshes: Array[ArrayMesh] = []
	for v in 3:
		bush_meshes.append(Vegetation.bush(rng, 1.0))
	# Ferns, nettles and weeds where the verge meets the trees.
	var weather = parent.get("weather")
	var wx: Dictionary = weather.preset if weather is Weather else {}
	var floor_mat := Grass.material(noise_tex, 0.3, wx.get("wet", 0.0), wx.get("snow", 0.0))
	var floor_meshes: Array[ArrayMesh] = []
	for v in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for c in 7:
			var cell: int = Grass.FERNS[rng.randi() % Grass.FERNS.size()] if rng.randf() < 0.7 else Grass.WEEDS[rng.randi() % Grass.WEEDS.size()]
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * 1.4
			Grass.clump(st, Vector3(cos(a) * d, -0.05, sin(a) * d), cell, Grass.SIZES[cell] * rng.randf_range(1.1, 1.6), rng.randf() * PI, 2)
		floor_meshes.append(st.commit())
	var rocks := _rock_meshes()
	var groups := {bush = [], rock = [], floor = []}
	for i in range(0, n, 2):
		for side: float in [-1.0, 1.0]:
			var d := rail_dist(i, side)
			if rng.randf() < 0.35:
				var p := at(i + rng.randi_range(-1, 1), side * (d + rng.randf_range(2.5, 26.0)), -0.1)
				if _clear(p):
					var s := rng.randf_range(0.6, 1.4)
					groups.bush.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.1), s)), p))
			if rng.randf() < 0.3:
				var p := at(i + rng.randi_range(-1, 1), side * (d + rng.randf_range(12.0, 30.0)))
				if _clear(p):
					var s := rng.randf_range(0.8, 1.3)
					groups.floor.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
			if rng.randf() < 0.05:
				var p := at(i, side * (d + rng.randf_range(3.0, 30.0)), -0.12)
				if _clear(p):
					groups.rock.append([rng.randi() % rocks.size(), rng.randf_range(0.5, 1.8), rng.randf() * TAU, p])
	_multimesh(bush_meshes, groups.bush, mats.foliage, 450.0)
	_multimesh(floor_meshes, groups.floor, floor_mat, 90.0, false) # ground cover: no shadow pass
	# Rocks: Poly Haven scans, scaled so 1.0 = about a metre across.
	for r in rocks.size():
		var mesh: Mesh = rocks[r][0]
		var aabb: AABB = mesh.get_aabb()
		var unit := 1.0 / maxf(aabb.size.x, aabb.size.z)
		var xfs := []
		for g: Array in groups.rock:
			if g[0] != r:
				continue
			var s: float = g[1] * unit
			var b := Basis(Vector3.UP, g[2]).scaled(Vector3(s, s * 0.9, s))
			xfs.append(Transform3D(b, g[3] - b * Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)))
		var one: Array[ArrayMesh] = [mesh]
		_multimesh(one, xfs, rocks[r][1], 500.0)


## [mesh, material] of each simplified rock scan.
func _rock_meshes() -> Array:
	var out := []
	for id in ["rock_07", "rock_09", "stone_01"]:
		var node := (load("res://assets/vegetation/rocks/%s.glb" % id) as PackedScene).instantiate()
		var mi: MeshInstance3D = node.find_children("*", "MeshInstance3D", true, false)[0]
		out.append([mi.mesh, mi.mesh.surface_get_material(0)])
		node.free()
	return out


func _clear(p: Vector3) -> bool:
	for z in no_trees:
		if p.distance_to(z[0]) < z[1]:
			return false
	return true


## Instances of `meshes` (round robin) in square cells, each cell one
## MultiMesh. Godot measures the visibility range to the centre of the
## MultiMesh AABB, so the range end is pushed out by the cell's half-diagonal:
## nothing within `vis_range` of the camera is ever culled with its cell.
func _multimesh(meshes: Array[ArrayMesh], xfs: Array, mat: Material, vis_range: float, shadow := true) -> void:
	var cell_size := clampf(vis_range * 0.75, 60.0, 400.0) # few draw calls; the range end grows with it
	for v in meshes.size():
		var cells := {}
		for k in xfs.size():
			if k % meshes.size() == v:
				var o: Vector3 = (xfs[k] as Transform3D).origin
				var key := Vector2i(floori(o.x / cell_size), floori(o.z / cell_size))
				if not cells.has(key):
					cells[key] = []
				cells[key].append(xfs[k])
		for key: Vector2i in cells:
			var mine: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[v]
			mm.instance_count = mine.size()
			for k in mine.size():
				mm.set_instance_transform(k, mine[k])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			var lo := Vector2(INF, INF)
			var hi := -lo
			for xf: Transform3D in mine:
				lo = lo.min(Vector2(xf.origin.x, xf.origin.z))
				hi = hi.max(Vector2(xf.origin.x, xf.origin.z))
			mmi.visibility_range_end = vis_range + (hi - lo).length() * 0.5 + 3.0
			mmi.visibility_range_end_margin = vis_range * 0.1
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if not shadow:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(mmi)
