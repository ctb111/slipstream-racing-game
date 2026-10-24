class_name GxCamp
extends RefCounted
## WRC spectator camp in the forest: dome and tunnel tents, a caravan with an
## awning, a gazebo with national flags, camping chairs, coolers, a washing
## line, firewood, a campfire (smoke by day, flames + flickering light at
## night), a kettle barbecue, Poly Haven CC0 props (monobloc chairs, stools,
## picnic table, jerrycans, thermos, basket, water bottles, fire pit) and
## PeopleKit spectators (front row facing the road, seated, round the fire).
##
##   GxCamp.place(c, Gx.frame(c, 900.0, Gx.RIGHT, 5.0), {size = "large"})
##
## Frame: Gx.frame (x along the track, +z away from the road); the camp fills
## x in [-w/2, w/2], z in [0, depth] (small 16 x 11 m, large 26 x 16 m) and its
## front row stands at z ~ 0..1.5 facing the road.
## Options: size "small" | "large", night (bool, default: the weather's night),
##   people (default true), cars (large: 2 parked cars behind, default false),
##   seed (int), smoke (default true).
## Everything procedural is merged per material (GxGeo, Mats photo PBR).

const PROPS := {
	chair = "res://assets/camp/plastic_monobloc_chair_01/plastic_monobloc_chair_01.gltf",
	stool = "res://assets/camp/folding_wooden_stool/folding_wooden_stool.gltf",
	table = "res://assets/camp/wooden_picnic_table/wooden_picnic_table.gltf",
	firepit = "res://assets/camp/stone_fire_pit/stone_fire_pit.gltf",
	jerry = "res://assets/camp/metal_jerrycan/metal_jerrycan.gltf",
	jerry_p = "res://assets/camp/plastic_jerrycan/plastic_jerrycan.gltf",
	thermos = "res://assets/camp/modified_thermos/modified_thermos.gltf",
	basket = "res://assets/camp/wicker_basket_01/wicker_basket_01.gltf",
	bottle = "res://assets/camp/plastic_bottle_gallon/plastic_bottle_gallon.gltf",
	table_set = "res://assets/camp/outdoor_table_chair_set_01/outdoor_table_chair_set_01.gltf",
	barrel = "res://assets/camp/Barrel_02/Barrel_02.gltf",
}
const PROP_VIS := 170.0
const GEO_VIS := 380.0

## Tent fabric colours (sRGB): faded outdoor nylon, not toy colours.
const TENT_COLS := [Color(0.24, 0.33, 0.22), Color(0.17, 0.26, 0.38), Color(0.62, 0.30, 0.12), Color(0.42, 0.43, 0.40),
	Color(0.52, 0.14, 0.12), Color(0.30, 0.36, 0.30), Color(0.68, 0.58, 0.30), Color(0.20, 0.22, 0.25)]
const CHAIR_COLS := [Color(0.12, 0.20, 0.35), Color(0.10, 0.10, 0.11), Color(0.25, 0.32, 0.20), Color(0.55, 0.12, 0.10), Color(0.35, 0.36, 0.38)]
const JACKETS := [Color(0.10, 0.10, 0.12), Color(0.13, 0.18, 0.32), Color(0.55, 0.10, 0.08), Color(0.22, 0.28, 0.20),
	Color(0.85, 0.42, 0.05), Color(0.75, 0.80, 0.10), Color(0.40, 0.40, 0.42), Color(0.08, 0.25, 0.45), Color(0.62, 0.62, 0.60)]
## Flags in the atlas (index -> drawn in _flag_atlas).
const N_FLAGS := 12

static var _props := {} ## key -> [mesh, xf]
static var _flag_mat: ShaderMaterial
static var _fx_tex := {}


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var large := str(opts.get("size", opts.get("kind", "small"))) == "large"
	var r := RandomNumberGenerator.new()
	r.seed = int(opts.get("seed", hash(xf.origin.snapped(Vector3.ONE))))
	var night: bool = _b(opts.get("night", _is_night(c)))
	var w := 26.0 if large else 16.0
	var depth := 16.0 if large else 11.0
	var root := Node3D.new()
	root.name = "GxCamp"
	c.add_child(root)
	var cam := Camp.new(c, root, xf, r)
	Gx.reserve(c, xf * Vector3(0, 0, depth * 0.5), maxf(w, depth) * 0.62)

	# --- layout: back row of tents/caravan, middle social area, front row of chairs
	var fire := Vector3(r.randf_range(-1.5, 1.5), 0, depth * 0.45)
	cam.fire(fire, night, _b(opts.get("smoke", true)))
	if large:
		cam.caravan(Vector3(-w * 0.28, 0, depth * 0.78), r.randf_range(-0.15, 0.15))
		cam.gazebo(Vector3(w * 0.12, 0, depth * 0.30), r.randf_range(-0.2, 0.2), r.randi() % 3)
		var tents := [Vector3(w * 0.05, 0, depth * 0.86), Vector3(w * 0.22, 0, depth * 0.80), Vector3(w * 0.38, 0, depth * 0.70),
			Vector3(-w * 0.06, 0, depth * 0.95), Vector3(w * 0.36, 0, depth * 0.30), Vector3(-w * 0.45, 0, depth * 0.42)]
		for i in tents.size():
			var p: Vector3 = tents[i] + Vector3(r.randf_range(-0.6, 0.6), 0, r.randf_range(-0.5, 0.5))
			var face := atan2(fire.x - p.x, -(fire.z - p.z)) + r.randf_range(-0.5, 0.5) # door towards the fire
			if i == 2 or i == 5:
				cam.tunnel_tent(p, face, TENT_COLS[r.randi() % TENT_COLS.size()])
			else:
				cam.dome_tent(p, face, TENT_COLS[r.randi() % TENT_COLS.size()], r.randf_range(0.9, 1.25))
		cam.washing_line(Vector3(-w * 0.05, 0, depth * 0.62), r.randf_range(-0.3, 0.3), 4.5)
		cam.bbq(Vector3(-w * 0.12, 0, depth * 0.24))
		cam.woodpile(Vector3(fire.x + 2.8, 0, fire.z + 2.2), r.randf() * TAU)
	else:
		var tents := [Vector3(-w * 0.28, 0, depth * 0.78), Vector3(w * 0.02, 0, depth * 0.88), Vector3(w * 0.30, 0, depth * 0.72)]
		for i in tents.size():
			var p: Vector3 = tents[i] + Vector3(r.randf_range(-0.5, 0.5), 0, r.randf_range(-0.4, 0.4))
			var face := atan2(fire.x - p.x, -(fire.z - p.z)) + r.randf_range(-0.4, 0.4)
			if i == 2 and r.randf() < 0.5:
				cam.tunnel_tent(p, face, TENT_COLS[r.randi() % TENT_COLS.size()])
			else:
				cam.dome_tent(p, face, TENT_COLS[r.randi() % TENT_COLS.size()], r.randf_range(0.85, 1.15))
		cam.gazebo(Vector3(-w * 0.22, 0, depth * 0.30), r.randf_range(-0.2, 0.2), r.randi() % 3)
		cam.washing_line(Vector3(w * 0.18, 0, depth * 0.52), r.randf_range(-0.4, 0.4), 3.5)
		if r.randf() < 0.6:
			cam.bbq(Vector3(w * 0.24, 0, depth * 0.24))
		cam.woodpile(Vector3(fire.x - 2.4, 0, fire.z + 1.8), r.randf() * TAU)

	# --- chairs round the fire (camping chairs + plastic ones), some occupied
	var n_ring := 7 if large else 5
	for i in n_ring:
		var a := TAU * (i + r.randf_range(-0.2, 0.2)) / n_ring
		var p := fire + Vector3(cos(a), 0, sin(a)) * r.randf_range(2.1, 2.6)
		var yaw := atan2(p.x - fire.x, p.z - fire.z) # -Z (the chair's front) towards the fire
		var seated := r.randf() < 0.55
		if r.randf() < 0.65:
			cam.camp_chair(p, yaw, CHAIR_COLS[r.randi() % CHAIR_COLS.size()], seated)
		else:
			cam.prop("chair", p, yaw + PI, 1.0)
			if seated:
				cam.person_seated(p + Vector3(0, 0.43, 0), yaw)
	# --- front row on the bank: chairs facing the road, standing fans, coolers
	var n_front := 9 if large else 5
	for i in n_front:
		var x := lerpf(-w * 0.42, w * 0.42, (i + r.randf_range(0.1, 0.9)) / n_front)
		var p := Vector3(x, 0, r.randf_range(0.6, 1.8))
		var yaw := r.randf_range(-0.35, 0.35)
		var k := r.randf()
		if k < 0.35:
			cam.camp_chair(p, yaw, CHAIR_COLS[r.randi() % CHAIR_COLS.size()], r.randf() < 0.7)
		elif k < 0.5:
			cam.prop("stool", p, yaw, 1.0)
			cam.person_seated(p + Vector3(0, 0.42, 0), yaw)
		if _b(opts.get("people", true)):
			for j in (1 if k < 0.5 else r.randi_range(1, 2)):
				var q := p + Vector3(r.randf_range(-0.9, 0.9), 0, r.randf_range(0.4, 1.4))
				cam.person(q, yaw + r.randf_range(-0.3, 0.3), r.randf())
		if r.randf() < 0.45:
			cam.cooler(p + Vector3(r.randf_range(0.5, 0.9), 0, r.randf_range(-0.2, 0.3)), r.randf() * TAU)
	# --- people milling round the camp
	if _b(opts.get("people", true)):
		for i in (4 if large else 2):
			var a := r.randf() * TAU
			var p := fire + Vector3(cos(a), 0, sin(a)) * r.randf_range(3.2, 4.5)
			cam.person(p, atan2(p.x - fire.x, p.z - fire.z) + r.randf_range(-0.6, 0.6), r.randf() * 0.5)
	# --- clutter
	cam.prop("table", Vector3(fire.x + r.randf_range(-4.5, -3.5), 0, fire.z - r.randf_range(0.5, 1.5)), r.randf_range(-0.4, 0.4), 1.0)
	for i in (5 if large else 3):
		var p := Vector3(r.randf_range(-w * 0.45, w * 0.45), 0, r.randf_range(depth * 0.2, depth * 0.95))
		var key: String = ["jerry_p", "bottle", "jerry_p", "bottle"][r.randi() % 4]
		cam.prop(key, p, r.randf() * TAU, 1.0)
		cam.cooler(p + Vector3(r.randf_range(-1.0, 1.0), 0, r.randf_range(0.5, 1.0)), r.randf() * TAU)
	cam.prop("bottle", fire + Vector3(1.6, 0, -1.1), r.randf() * TAU, 1.0)
	cam.commit()
	GxCamp.maybe_ab(root, xf * Vector3(-w * 0.55, 1.7, -6.0), xf * Vector3(0, 1.2, depth * 0.5))

	if large and _b(opts.get("cars", false)) and ResourceLoader.exists("res://scripts/track/gimmicks/gx_parked_cars.gd"):
		var cx := xf * Transform3D(Basis(), Vector3(w * 0.30, 0, depth + 3.0))
		load("res://scripts/track/gimmicks/gx_parked_cars.gd").place(c, cx, {count = 2, spacing = 3.4, people = false, variety = 1, seed = r.randi()})


## Caps every GeometryInstance3D under `n` at `dist` metres (crowds: people
## are cut at ~80 m, the far tier is not worth drawing for a camp).
static func limit(n: Node, dist: float) -> Node:
	for ch in n.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).visibility_range_end = dist
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		limit(ch, dist)
	return n


static func _b(v) -> bool:
	if v is String:
		return v != "false" and v != "0" and v != ""
	return bool(v)


static func _is_night(c: Node3D) -> bool:
	var wx = c.get("weather")
	return wx != null and bool(wx.get("night"))


## Mesh + node transform of the first MeshInstance3D in a prop scene (cached).
static func prop_mesh(key: String) -> Array:
	if _props.has(key):
		return _props[key]
	var out := []
	if ResourceLoader.exists(PROPS[key]):
		var n: Node = (load(PROPS[key]) as PackedScene).instantiate()
		var stack: Array = [[n, Transform3D.IDENTITY]]
		while not stack.is_empty():
			var e: Array = stack.pop_back()
			var nd: Node = e[0]
			var t: Transform3D = e[1]
			if nd is Node3D:
				t = t * (nd as Node3D).transform
			if nd is MeshInstance3D and (nd as MeshInstance3D).mesh is ArrayMesh:
				# Poly Haven props are dense (a 13k-triangle bottle): decimate to a
				# few thousand tris at most, then auto LODs for distance
				var budget := 2500 if key in ["table", "table_set", "firepit"] else 1200
				out = [CarModel._with_lods(GxParkedCars._decimate((nd as MeshInstance3D).mesh, budget)), t]
				break
			for ch in nd.get_children():
				stack.append([ch, t])
		n.free()
	_props[key] = out
	return out


## Mats canvas, calmer: the photo weave is too contrasty on big pale panels.
static var _canvas: Material
static func canvas_material(base: Material) -> Material:
	if _canvas == null and base is ShaderMaterial:
		_canvas = base.duplicate()
		(_canvas as ShaderMaterial).set_shader_parameter("contrast", 0.22)
		(_canvas as ShaderMaterial).set_shader_parameter("normal_strength", 0.35)
		(_canvas as ShaderMaterial).set_shader_parameter("streaks", 0.1)
		Mats._cache["gx_canvas_calm"] = _canvas # so Mats.bind_world gives it the weather (snow, rain)
	return _canvas if _canvas else base


## Flag / laundry material: a printed atlas, gently waving in the wind.
static func flag_material() -> ShaderMaterial:
	if _flag_mat:
		return _flag_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float amp = 0.07;
varying float wave;
void vertex() {
	// UV2.x = distance from the fixed edge (0..1), UV2.y = phase
	float k = UV2.x;
	float s = sin(TIME * 3.1 + k * 7.0 + UV2.y * 6.28) + 0.4 * sin(TIME * 5.3 + k * 13.0 + UV2.y * 3.1);
	VERTEX += NORMAL * s * amp * k;
	wave = s * k;
}
void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb * (0.85 + 0.15 * wave);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = vec3(0.1);
}
"""
	_flag_mat = ShaderMaterial.new()
	_flag_mat.shader = sh
	_flag_mat.set_shader_parameter("atlas", _flag_atlas())
	return _flag_mat


## 4 x 4 atlas of 64 x 40 cells: 12 national flags (rally nations), then plain
## laundry colours. Cell i -> UV rect (i % 4 / 4, i / 4 / 4, 1/4, 1/4).
static func _flag_atlas() -> ImageTexture:
	var img := Image.create(256, 160, false, Image.FORMAT_RGB8)
	var cw := 64
	var ch := 40
	var draw := func(i: int, f: Callable) -> void:
		var ox := (i % 4) * cw
		var oy := (i / 4) * ch
		for y in ch:
			for x in cw:
				img.set_pixel(ox + x, oy + y, f.call(float(x) / cw, float(y) / ch))
	var nordic := func(bg: Color, cr: Color, inner := Color(0, 0, 0, 0)) -> Callable:
		return func(u: float, v: float) -> Color:
			var cu := absf(u - 0.36) < 0.09
			var cv := absf(v - 0.5) < 0.14
			if inner.a > 0.0 and (absf(u - 0.36) < 0.045 or absf(v - 0.5) < 0.07):
				return inner
			return cr if cu or cv else bg
	var hstripes := func(cols: Array) -> Callable:
		return func(_u: float, v: float) -> Color: return cols[mini(int(v * cols.size()), cols.size() - 1)]
	var vstripes := func(cols: Array) -> Callable:
		return func(u: float, _v: float) -> Color: return cols[mini(int(u * cols.size()), cols.size() - 1)]
	var white := Color(0.92, 0.92, 0.9)
	draw.call(0, nordic.call(white, Color(0.0, 0.21, 0.5)))                                   # Finland
	draw.call(1, hstripes.call([Color(0.0, 0.45, 0.8), Color(0.02, 0.02, 0.02), white]))      # Estonia
	draw.call(2, hstripes.call([Color(0.02, 0.02, 0.02), Color(0.85, 0.0, 0.0), Color(1.0, 0.8, 0.0)])) # Germany
	draw.call(3, vstripes.call([Color(0.0, 0.14, 0.58), white, Color(0.93, 0.16, 0.22)]))     # France
	draw.call(4, nordic.call(Color(0.0, 0.42, 0.66), Color(1.0, 0.8, 0.0)))                   # Sweden
	draw.call(5, nordic.call(Color(0.73, 0.05, 0.18), white, Color(0.0, 0.13, 0.4)))          # Norway
	draw.call(6, hstripes.call([white, Color(0.86, 0.08, 0.24)]))                             # Poland
	draw.call(7, vstripes.call([Color(0.0, 0.57, 0.27), white, Color(0.81, 0.17, 0.15)]))     # Italy
	draw.call(8, vstripes.call([Color(0.09, 0.61, 0.38), white, Color(1.0, 0.53, 0.24)]))     # Ireland
	draw.call(9, vstripes.call([Color(0.02, 0.02, 0.02), Color(0.99, 0.85, 0.13), Color(0.94, 0.2, 0.25)])) # Belgium
	draw.call(10, hstripes.call([Color(0.67, 0.08, 0.11), Color(0.95, 0.75, 0.0), Color(0.95, 0.75, 0.0), Color(0.67, 0.08, 0.11)])) # Spain
	draw.call(11, func(u: float, v: float) -> Color: # Czechia
		if u < 0.5 * (1.0 - absf(v - 0.5) * 2.0):
			return Color(0.07, 0.27, 0.49)
		return white if v < 0.5 else Color(0.84, 0.08, 0.12))
	var cloth := [Color(0.85, 0.85, 0.82), Color(0.18, 0.28, 0.5), Color(0.62, 0.15, 0.12), Color(0.35, 0.45, 0.3)]
	for k in 4:
		var base: Color = cloth[k]
		draw.call(12 + k, func(u: float, v: float) -> Color: # towel weave + a hem stripe
			var hem := 0.75 if (v > 0.82 and v < 0.9) else 1.0
			return base * hem * (0.93 + 0.07 * sin(u * 120.0) * sin(v * 90.0)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Soft round puff (smoke) or flame tongue texture, cached.
static func fx_texture(kind: String) -> ImageTexture:
	if _fx_tex.has(kind):
		return _fx_tex[kind]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var nz := FastNoiseLite.new()
	nz.frequency = 0.09
	nz.seed = 7 if kind == "smoke" else 3
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var a := 0.0
			if kind == "smoke":
				var d := sqrt(u * u + v * v)
				a = clampf(1.0 - d, 0.0, 1.0)
				a = a * a * (0.65 + 0.35 * nz.get_noise_2d(x, y))
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
			else:
				var w := 0.55 * (1.0 - (v * 0.5 + 0.5)) + 0.08 # wider at the bottom (v = +1)
				w = 0.15 + 0.5 * (v * 0.5 + 0.5)
				var d := absf(u) / maxf(w, 0.01)
				a = clampf(1.0 - d, 0.0, 1.0) * clampf((v + 1.0) * 1.2, 0.0, 1.0) * clampf((1.0 - v) * 3.0, 0.0, 1.0)
				a *= 0.75 + 0.25 * nz.get_noise_2d(x * 2.0, y)
				var hot := clampf(1.0 - d * 1.4, 0.0, 1.0) * (v * 0.5 + 0.5)
				img.set_pixel(x, y, Color(1.0, 0.45 + 0.45 * hot, 0.12 + 0.5 * hot * hot, clampf(a, 0.0, 1.0)))
	img.generate_mipmaps()
	_fx_tex[kind] = ImageTexture.create_from_image(img)
	return _fx_tex[kind]


## Builder for one camp: merged procedural geometry, prop MultiMeshes, people.
class Camp:
	var c: Node3D
	var root: Node3D
	var xf: Transform3D
	var r: RandomNumberGenerator
	var g: GxGeo
	var flags := [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedVector2Array()] # v, n, uv, uv2
	var props := {} ## key -> Array[Transform3D] (world)
	var ppl := {} ## role -> [xfs, cols, custom]
	var shadow: GxGeo ## low-poly shadow-only proxy (tents, caravan, gazebo roof)

	func _init(p_c: Node3D, p_root: Node3D, p_xf: Transform3D, p_r: RandomNumberGenerator) -> void:
		c = p_c
		root = p_root
		xf = p_xf
		r = p_r
		g = GxGeo.new(xf)
		shadow = GxGeo.new(xf)

	## Local frame standing on the terrain at local (x, z), turned by yaw.
	func at(p: Vector3, yaw: float, sink := 0.0) -> Transform3D:
		var w := xf * Vector3(p.x, 0, p.z)
		var y := Gx.ground(c, w) - xf.origin.y - sink
		return Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y + p.y, p.z))

	func use(t: Transform3D) -> void:
		g.xf = xf * t

	func done() -> void:
		g.xf = xf
		g.col = Color.WHITE

	# ------------------------------------------------------------- tents

	## Four-pole dome tent: squarish superellipse dome, fabric sagging between
	## the poles, pole sleeves, dark bathtub floor, D-door with a zip and a
	## vestibule bulge on the front (-z).
	func dome_tent(p: Vector3, yaw: float, col: Color, s := 1.0) -> void:
		use(at(p, yaw, 0.04))
		var a := 1.15 * s
		var b := 1.05 * s
		var hh := 1.25 * s
		var nt := 32
		var nr := 9
		var grid := []
		for i in nr + 1:
			var phi := PI * 0.5 * float(i) / nr
			var row := []
			for j in nt:
				var th := TAU * float(j) / nt
				var ct := cos(th)
				var st := sin(th)
				var sup := pow(pow(absf(ct), 3.0) + pow(absf(st), 3.0), -1.0 / 3.0)
				var sag := 1.0 - 0.07 * (1.0 - absf(sin(2.0 * th))) * sin(phi * 2.0) # panels dip between the poles
				var rr := cos(phi) * sup * sag
				var x := a * rr * ct
				var z := b * rr * st
				var y := hh * sin(phi) * (1.0 - 0.04 * (1.0 - absf(sin(2.0 * th))))
				if st < -0.55 and i < nr - 2: # vestibule on the front
					z -= 0.38 * s * pow((-st - 0.55) / 0.45, 1.5) * cos(phi * 1.2)
				row.append(Vector3(x, y + 0.04, z))
			grid.append(row)
		var dark := col.darkened(0.35)
		for i in nr:
			for j in nt:
				var j2 := (j + 1) % nt
				var v00: Vector3 = grid[i][j]
				var v01: Vector3 = grid[i][j2]
				var v10: Vector3 = grid[i + 1][j]
				var v11: Vector3 = grid[i + 1][j2]
				var cc := col
				var th := TAU * (j + 0.5) / nt
				var phi := PI * 0.5 * (i + 0.5) / nr
				if absf(absf(sin(2.0 * th)) - 1.0) < 0.02:
					cc = dark # pole sleeve
				elif sin(th) < -0.86 and phi < 1.0 and absf(cos(th)) < 0.4:
					cc = col.darkened(0.18) if absf(cos(th)) > 0.06 else Color(0.08, 0.08, 0.08) # door + zip
				if i == 0:
					cc = Color(0.16, 0.17, 0.17) # bathtub floor edge
				cc = cc * (0.82 + 0.18 * float(i) / nr) # AO towards the ground
				cc.a = 1.0
				_smooth_quad("canvas", v00, v10, v11, v01, cc)
		shadow.xf = g.xf
		shadow.lathe("steel", Vector3.ZERO, PackedVector2Array([Vector2(a, 0.0), Vector2(a * 0.75, hh * 0.7), Vector2(0.0, hh)]), 6)
		# guy-line pegs: small dark tabs at the pole feet
		for k in 4:
			var th := PI * 0.25 + k * PI * 0.5
			var q := Vector3(cos(th) * a * 0.95, 0.05, sin(th) * b * 0.95)
			g.col = Color(0.1, 0.1, 0.1)
			g.box("steel", q, Vector3(0.05, 0.1, 0.05), 0.01)
		done()

	## Tunnel tent: three hoops, tapering to the back, sagging between hoops.
	func tunnel_tent(p: Vector3, yaw: float, col: Color) -> void:
		use(at(p, yaw, 0.04))
		var length := 3.6
		var nz := 12
		var na := 14
		var hoops := [0.0, 0.45, 1.0]
		var grid := []
		for i in nz + 1:
			var t := float(i) / nz
			var z := lerpf(-length * 0.5, length * 0.5, t)
			var wdt := lerpf(1.25, 0.95, t)
			var ht := lerpf(1.35, 0.95, t)
			var sag := 1.0
			for k in hoops.size() - 1:
				if t >= hoops[k] and t <= hoops[k + 1]:
					sag = 1.0 - 0.07 * sin(PI * (t - hoops[k]) / (hoops[k + 1] - hoops[k]))
			var row := []
			for j in na + 1:
				var an := PI * float(j) / na
				var cx := cos(an)
				var sy := sin(an)
				var sup := pow(pow(absf(cx), 2.6) + pow(absf(sy), 2.6), -1.0 / 2.6)
				row.append(Vector3(cx * sup * wdt * sag, 0.04 + sy * sup * ht * sag, z))
			grid.append(row)
		var dark := col.darkened(0.35)
		for i in nz:
			for j in na:
				var t := (i + 0.5) / nz
				var cc := col
				for hk in hoops:
					if absf(t - hk) < 0.045:
						cc = dark
				cc = cc * (0.82 + 0.18 * sin(PI * (j + 0.5) / na))
				cc.a = 1.0
				_smooth_quad("canvas", grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], cc)
		# end panels (front with a door outline)
		for e: int in [0, nz]:
			var cen: Vector3 = (grid[e][0] + grid[e][na]) * 0.5
			for j in na:
				var cc := col.darkened(0.12) if e == 0 else col.darkened(0.2)
				g.col = cc
				var a0: Vector3 = grid[e][j]
				var a1: Vector3 = grid[e][j + 1]
				if e == 0:
					g.tri("canvas", cen, a1, a0)
				else:
					g.tri("canvas", cen, a0, a1)
		shadow.xf = g.xf
		shadow.box("steel", Vector3(0, 0.55, 0), Vector3(1.9, 1.1, length))
		g.col = Color(0.07, 0.07, 0.07)
		var fz: float = grid[0][0].z - 0.005
		g.box("canvas", Vector3(0, 0.55, fz), Vector3(0.025, 1.0, 0.01))
		done()

	# ------------------------------------------------------------- caravan

	## 80s touring caravan: cream shell with a sloped nose, a brown stripe,
	## tinted acrylic windows, door, roof light, A-frame drawbar with gas box
	## and jockey wheel, single axle, corner steadies and a side awning.
	func caravan(p: Vector3, yaw: float) -> void:
		use(at(p, yaw, 0.0))
		var hw := 1.1
		var cream := Color(0.86, 0.84, 0.76)
		var stripe: Color = [Color(0.42, 0.24, 0.12), Color(0.70, 0.35, 0.08), Color(0.18, 0.28, 0.45)][r.randi() % 3]
		# side profile (x, y), convex, nose at +x
		var prof := PackedVector2Array([Vector2(-2.55, 0.42), Vector2(2.25, 0.42), Vector2(2.62, 0.85), Vector2(2.72, 1.25),
			Vector2(2.60, 2.15), Vector2(2.42, 2.40), Vector2(2.15, 2.52), Vector2(-2.30, 2.52), Vector2(-2.50, 2.44), Vector2(-2.58, 2.30)])
		_side_shell("painted_metal", prof, hw, 0.09, cream)
		# stripe band and lower skirt
		g.col = stripe
		for sz: float in [-1.0, 1.0]:
			g.box("painted_metal", Vector3(-0.1, 1.08, sz * (hw + 0.004)), Vector3(4.95, 0.13, 0.01))
			g.box("painted_metal", Vector3(-0.1, 1.23, sz * (hw + 0.004)), Vector3(4.95, 0.035, 0.01))
			g.col = Color(0.25, 0.25, 0.25)
			g.box("painted_metal", Vector3(-0.15, 0.47, sz * (hw + 0.006)), Vector3(4.8, 0.09, 0.012)) # rubbing strip
			g.col = stripe
		# windows (dark acrylic with grey frames)
		var wins := [[-1.65, 1.75, 1.3, 0.62, 1.0], [0.55, 1.75, 1.0, 0.62, 1.0], [-1.65, 1.75, 1.1, 0.62, -1.0], [1.2, 1.75, 1.1, 0.62, -1.0]]
		for wv: Array in wins:
			var sz: float = wv[4]
			g.col = Color(0.3, 0.3, 0.3)
			g.box("painted_metal", Vector3(wv[0], wv[1], sz * (hw + 0.012)), Vector3(wv[2] + 0.08, wv[3] + 0.08, 0.02), 0.03)
			g.col = Color.WHITE
			g.box("glass", Vector3(wv[0], wv[1], sz * (hw + 0.024)), Vector3(wv[2], wv[3], 0.012), 0.04)
		# front window on the slanted nose
		g.col = Color.WHITE
		g.box("glass", Vector3(2.665, 1.72, 0), Vector3(0.02, 0.5, 1.7), 0.05, Basis(Vector3.BACK, 0.13))
		g.box("glass", Vector3(-2.575, 1.75, 0), Vector3(0.02, 0.45, 1.2), 0.04)
		# door on the +z side (towards the camp) with a handle and step
		g.col = cream.darkened(0.06)
		g.box("painted_metal", Vector3(-0.35, 1.25, hw + 0.012), Vector3(0.62, 1.7, 0.02), 0.02)
		g.col = Color(0.2, 0.2, 0.2)
		g.box("glass", Vector3(-0.35, 1.78, hw + 0.026), Vector3(0.36, 0.42, 0.01), 0.03)
		g.box("steel", Vector3(-0.1, 1.2, hw + 0.03), Vector3(0.12, 0.03, 0.03))
		g.box("steel", Vector3(-0.35, 0.28, hw + 0.22), Vector3(0.55, 0.04, 0.32), 0.01)
		# roof light and vent
		g.col = Color(0.9, 0.9, 0.88)
		g.box("painted_metal", Vector3(0.2, 2.56, 0), Vector3(0.7, 0.08, 0.6), 0.03)
		g.col = Color(0.75, 0.78, 0.8)
		g.box("glass", Vector3(0.2, 2.61, 0), Vector3(0.6, 0.04, 0.5), 0.02)
		g.col = Color(0.9, 0.9, 0.88)
		g.box("painted_metal", Vector3(-1.5, 2.58, 0.3), Vector3(0.35, 0.1, 0.35), 0.03)
		# rear lamps
		for sz: float in [-1.0, 1.0]:
			g.col = Color(0.55, 0.05, 0.03)
			g.box("glass", Vector3(-2.57, 0.68, sz * 0.82), Vector3(0.03, 0.14, 0.24), 0.02)
		# chassis, axle, wheels, mudguards
		g.col = Color(0.12, 0.12, 0.12)
		g.box("steel", Vector3(0.0, 0.34, 0), Vector3(4.6, 0.12, 1.5))
		for sz: float in [-1.0, 1.0]:
			_wheel(Vector3(0.1, 0.30, sz * 0.98), 0.30, 0.17)
			g.col = Color(0.15, 0.15, 0.15)
			g.box("painted_metal", Vector3(0.1, 0.62, sz * 1.0), Vector3(0.82, 0.04, 0.25), 0.01)
		# A-frame drawbar, gas box, jockey wheel
		g.col = Color(0.15, 0.15, 0.15)
		for sz: float in [-1.0, 1.0]:
			g.beam("steel", Vector3(2.2, 0.36, sz * 0.7), Vector3(3.55, 0.38, 0), 0.08)
		g.box("steel", Vector3(3.62, 0.42, 0), Vector3(0.3, 0.12, 0.14), 0.02)
		g.col = Color(0.82, 0.8, 0.74)
		g.box("painted_metal", Vector3(2.85, 0.62, 0), Vector3(0.55, 0.42, 1.05), 0.04)
		g.col = Color(0.15, 0.15, 0.15)
		g.bar("steel", Vector3(3.3, 0.05, 0.22), Vector3(3.3, 0.5, 0.22), 0.03)
		_wheel(Vector3(3.3, 0.08, 0.22), 0.08, 0.06)
		# corner steadies down to the ground
		for sx: float in [-2.3, 2.0]:
			for sz: float in [-0.75, 0.75]:
				g.col = Color(0.2, 0.2, 0.2)
				g.beam("steel", Vector3(sx, 0.34, sz), Vector3(sx + 0.18, 0.0, sz), 0.04)
				g.box("steel", Vector3(sx + 0.18, 0.01, sz), Vector3(0.14, 0.02, 0.14))
		# side awning (canvas roof + front curtain + poles)
		var awc: Color = [Color(0.25, 0.33, 0.45), Color(0.45, 0.30, 0.18), Color(0.28, 0.36, 0.26)][r.randi() % 3]
		var depth_aw := 2.4
		var xa := -2.1
		var xb := 1.4
		for k in 6:
			var t0 := float(k) / 6.0
			var t1 := float(k + 1) / 6.0
			var x0 := lerpf(xa, xb, t0)
			var x1 := lerpf(xa, xb, t1)
			var cc := awc if k % 2 == 0 else awc.lightened(0.55)
			cc.a = 1.0
			_smooth_quad("canvas", Vector3(x0, 2.35, hw + 0.05), Vector3(x1, 2.35, hw + 0.05),
				Vector3(x1, 2.02, hw + depth_aw), Vector3(x0, 2.02, hw + depth_aw), cc, true)
			# valance
			_smooth_quad("canvas", Vector3(x0, 2.02, hw + depth_aw), Vector3(x1, 2.02, hw + depth_aw),
				Vector3(x1, 1.82, hw + depth_aw + 0.01), Vector3(x0, 1.82, hw + depth_aw + 0.01), cc.darkened(0.15), true)
		g.col = Color(0.6, 0.6, 0.6)
		for x in [xa, (xa + xb) * 0.5, xb]:
			g.bar("steel", Vector3(x, 0.0, hw + depth_aw), Vector3(x, 2.04, hw + depth_aw), 0.016)
		g.collide(Vector3(0.1, 1.45, 0), Vector3(5.3, 2.1, 2.25))
		shadow.xf = g.xf
		shadow.box("steel", Vector3(0.1, 1.45, 0), Vector3(5.3, 2.1, 2.2))
		shadow.box("steel", Vector3(-0.35, 2.2, hw + 1.25), Vector3(3.5, 0.05, 2.4))
		done()

	# ------------------------------------------------------------- gazebo

	func gazebo(p: Vector3, yaw: float, style: int) -> void:
		use(at(p, yaw, 0.0))
		var hs := 1.5
		var eave := 2.1
		var apex := 2.85
		var cols := [Color(0.85, 0.85, 0.82), Color(0.15, 0.25, 0.48), Color(0.25, 0.3, 0.22)]
		var cc: Color = cols[style]
		# legs + truss
		g.col = Color(0.55, 0.56, 0.58)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				g.bar("steel", Vector3(sx * hs, 0, sz * hs), Vector3(sx * hs, eave, sz * hs), 0.022)
				g.box("steel", Vector3(sx * hs, 0.01, sz * hs), Vector3(0.14, 0.02, 0.14))
		for k in 4:
			var a := Vector3(-hs, eave - 0.12, -hs).rotated(Vector3.UP, k * PI * 0.5)
			var b := Vector3(hs, eave - 0.12, -hs).rotated(Vector3.UP, k * PI * 0.5)
			var m := (a + b) * 0.5 + Vector3(0, -0.28, 0)
			g.bar("steel", a, m, 0.012)
			g.bar("steel", m, b, 0.012)
		# roof: 4 sagging panels to the apex + valance
		var top := Vector3(0, apex, 0)
		for k in 4:
			var a := Vector3(-hs - 0.05, eave, -hs - 0.05).rotated(Vector3.UP, -k * PI * 0.5)
			var b := Vector3(hs + 0.05, eave, -hs - 0.05).rotated(Vector3.UP, -k * PI * 0.5)
			# subdivided triangle with sag
			var rows := 6
			for i in rows:
				var t0 := float(i) / rows
				var t1 := float(i + 1) / rows
				var l0 := a.lerp(top, t0)
				var r0 := b.lerp(top, t0)
				var l1 := a.lerp(top, t1)
				var r1 := b.lerp(top, t1)
				var sag0 := -0.07 * sin(PI * t0)
				var sag1 := -0.07 * sin(PI * t1)
				var m0 := (l0 + r0) * 0.5 + Vector3(0, sag0, 0)
				var m1 := (l1 + r1) * 0.5 + Vector3(0, sag1, 0)
				var c0 := cc * (0.92 + 0.08 * t0)
				c0.a = 1.0
				_smooth_quad("canvas", l0, m0, m1, l1, c0, true)
				_smooth_quad("canvas", m0, r0, r1, m1, c0, true)
			var vc := cc.darkened(0.08)
			vc.a = 1.0
			_smooth_quad("canvas", a, b, b + Vector3(0, -0.24, 0), a + Vector3(0, -0.24, 0), vc, true)
		shadow.xf = g.xf
		shadow.box("steel", Vector3(0, eave + 0.3, 0), Vector3(hs * 2.0, 0.1, hs * 2.0))
		# flags: one hung along the front valance, two on tall poles
		var f1 := r.randi() % N_FLAGS
		_flag(Vector3(-0.7, eave - 0.25, -hs - 0.07), Vector3(1, 0, 0), Vector3(0, -1, 0), 1.4, 0.85, f1, false)
		for sx: float in [-1.0, 1.0]:
			var base := Vector3(sx * (hs + 0.25), 0, -hs - 0.25)
			g.col = Color(0.3, 0.3, 0.3)
			g.bar("steel", base, base + Vector3(0, 4.2, 0), 0.02, 5)
			var fi := (f1 + 1 + r.randi() % (N_FLAGS - 1)) % N_FLAGS
			_flag(base + Vector3(0, 4.15, 0), Vector3(sx, 0, 0.25).normalized(), Vector3(0, -1, 0), 1.5, 0.95, fi, true)
		# table + people under it
		done()
		prop("table", p + Vector3(0, 0, 0.2), yaw, 1.0)
		person(p + Vector3(-0.9, 0, -0.8).rotated(Vector3.UP, yaw), yaw + r.randf_range(-0.4, 0.4), 0.2)

	## Flag quad (atlas cell `idx`) from `o`, `u` along the fly, `v` down the hoist.
	func _flag(o: Vector3, u: Vector3, v: Vector3, w: float, h: float, idx: int, free_fly: bool) -> void:
		var nu := 8
		var nv := 3
		var cell := Vector2((idx % 4) * 0.25, (idx / 4) * 0.25)
		var ph := r.randf()
		var n := u.cross(v).normalized()
		var pts := []
		for j in nv + 1:
			var row := []
			for i in nu + 1:
				var s := float(i) / nu
				var t := float(j) / nv
				var droop := (0.12 * s * s * h) if free_fly else 0.0
				var bulge := (0.03 * sin(PI * s) * sin(PI * t)) if not free_fly else 0.0
				var q := o + u * s * w + v * (t * h + droop) + n * bulge
				var k := s if free_fly else 0.35 * sin(PI * t) * (0.4 + 0.6 * sin(PI * s)) + 0.0
				row.append([g.xf * q, Vector2(cell.x + (0.01 + s * 0.23), cell.y + (0.01 + t * 0.23)), Vector2(k, ph)])
			pts.append(row)
		var nw := (g.xf.basis * n).normalized()
		for j in nv:
			for i in nu:
				var a: Array = pts[j][i]
				var b: Array = pts[j][i + 1]
				var cpt: Array = pts[j + 1][i + 1]
				var d: Array = pts[j + 1][i]
				for e: Array in [a, cpt, b, a, d, cpt]:
					flags[0].append(e[0])
					flags[1].append(nw)
					flags[2].append(e[1])
					flags[3].append(e[2])

	# ------------------------------------------------------------- small stuff

	## Folding camping chair: steel X-legs, sagging fabric seat and back, armrests.
	func camp_chair(p: Vector3, yaw: float, col: Color, seated: bool) -> void:
		var t := at(p, yaw)
		use(t)
		var hw := 0.27
		g.col = Color(0.12, 0.12, 0.12)
		for sx: float in [-1.0, 1.0]:
			g.bar("steel", Vector3(sx * hw, 0, -0.25), Vector3(sx * hw, 0.42, 0.2), 0.011, 5)
			g.bar("steel", Vector3(sx * hw, 0, 0.2), Vector3(sx * hw, 0.42, -0.25), 0.011, 5)
			g.bar("steel", Vector3(sx * hw, 0.42, 0.2), Vector3(sx * hw * 1.05, 0.95, 0.32), 0.011, 5)
			g.bar("steel", Vector3(sx * (hw + 0.02), 0.62, -0.22), Vector3(sx * (hw + 0.02), 0.62, 0.22), 0.012, 5)
			g.bar("steel", Vector3(sx * (hw + 0.02), 0.42, -0.25), Vector3(sx * (hw + 0.02), 0.62, -0.22), 0.011, 5)
		var cc := col
		cc.a = 1.0
		# seat: 4 x 2 grid, sagging in the middle
		for i in 4:
			var x0 := lerpf(-hw, hw, i / 4.0)
			var x1 := lerpf(-hw, hw, (i + 1) / 4.0)
			var s0 := -0.05 * sin(PI * i / 4.0)
			var s1 := -0.05 * sin(PI * (i + 1) / 4.0)
			_smooth_quad("canvas", Vector3(x0, 0.43 + s0, -0.24), Vector3(x1, 0.43 + s1, -0.24), Vector3(x1, 0.42 + s1, 0.2), Vector3(x0, 0.42 + s0, 0.2), cc, true)
			_smooth_quad("canvas", Vector3(x0, 0.45 + s0 * 0.5, 0.21 - s0 * 0.6), Vector3(x1, 0.45 + s1 * 0.5, 0.21 - s1 * 0.6),
				Vector3(x1, 0.93, 0.31 - s1 * 0.6), Vector3(x0, 0.93, 0.31 - s0 * 0.6), cc.darkened(0.08), true)
		done()
		if seated:
			person_seated(p + Vector3(0, 0.4, 0), yaw)

	func cooler(p: Vector3, yaw: float) -> void:
		use(at(p, yaw))
		var body: Color = [Color(0.12, 0.3, 0.6), Color(0.7, 0.12, 0.1), Color(0.2, 0.42, 0.3), Color(0.85, 0.85, 0.82)][r.randi() % 4]
		g.col = body
		g.box("painted_metal", Vector3(0, 0.17, 0), Vector3(0.6, 0.32, 0.38), 0.035)
		g.col = Color(0.9, 0.9, 0.88)
		g.box("painted_metal", Vector3(0, 0.355, 0), Vector3(0.62, 0.06, 0.4), 0.025)
		g.col = Color(0.15, 0.15, 0.15)
		for sx: float in [-1.0, 1.0]:
			g.box("painted_metal", Vector3(sx * 0.31, 0.27, 0), Vector3(0.03, 0.04, 0.16), 0.01)
		done()

	func washing_line(p: Vector3, yaw: float, span: float) -> void:
		var t := at(p, yaw)
		use(t)
		var a := Vector3(-span * 0.5, 0, 0)
		var b := Vector3(span * 0.5, 0, 0)
		var ya := Gx.ground(c, xf * (t * a)) - (xf * t).origin.y
		var yb := Gx.ground(c, xf * (t * b)) - (xf * t).origin.y
		g.col = Color(0.35, 0.3, 0.22)
		g.bar("wood", a + Vector3(0, ya - 0.1, 0), a + Vector3(0, ya + 1.95, 0), 0.03, 6)
		g.bar("wood", b + Vector3(0, yb - 0.1, 0), b + Vector3(0, yb + 1.95, 0), 0.03, 6)
		var pts := []
		var n := 10
		for i in n + 1:
			var s := float(i) / n
			pts.append(Vector3(lerpf(a.x, b.x, s), lerpf(ya, yb, s) + 1.9 - 0.18 * sin(PI * s), 0))
		g.col = Color(0.85, 0.85, 0.8)
		g.tube("steel", pts, 0.006, 4, false)
		# laundry: towels, shirts and a flag over the line
		var x := a.x + 0.35
		while x < b.x - 0.5:
			var w := r.randf_range(0.35, 0.75)
			var s := (x + w * 0.5 - a.x) / span
			var y := lerpf(ya, yb, s) + 1.9 - 0.18 * sin(PI * s)
			var idx := 12 + r.randi() % 4 if r.randf() < 0.75 else r.randi() % N_FLAGS
			_flag(Vector3(x, y, 0.0), Vector3(1, 0, 0), Vector3(0, -1, 0), w, r.randf_range(0.45, 0.8), idx, false)
			x += w + r.randf_range(0.08, 0.3)
		done()

	func woodpile(p: Vector3, yaw: float) -> void:
		use(at(p, yaw, 0.02))
		for row in 3:
			for k in 5 - row:
				var z := (k - (4 - row) * 0.5) * 0.17
				var y := 0.08 + row * 0.15
				var l := r.randf_range(0.8, 1.0)
				g.col = Color(0.75, 0.62, 0.5) * r.randf_range(0.8, 1.1)
				g.col.a = 1.0
				g.tube("wood", [Vector3(-l * 0.5, y, z), Vector3(l * 0.5, y, z)], 0.075, 7)
		done()

	## Kettle barbecue on three legs, lid hooked on the side, a wisp of smoke.
	func bbq(p: Vector3) -> void:
		var t := at(p, r.randf() * TAU)
		use(t)
		g.col = Color(0.08, 0.08, 0.08)
		g.lathe("painted_metal", Vector3(0, 0.62, 0), PackedVector2Array([Vector2(0.02, 0.0), Vector2(0.15, 0.03), Vector2(0.24, 0.12), Vector2(0.27, 0.24), Vector2(0.272, 0.26)]), 16)
		g.col = Color(0.5, 0.5, 0.5)
		g.tube("steel", _ring(Vector3(0, 0.875, 0), 0.25, 16), 0.005, 4, false)
		for k in 3:
			var a := TAU * k / 3.0
			g.col = Color(0.1, 0.1, 0.1)
			g.bar("steel", Vector3(cos(a) * 0.2, 0.68, sin(a) * 0.2), Vector3(cos(a) * 0.33, 0.0, sin(a) * 0.33), 0.012, 5)
		g.col = Color(0.08, 0.08, 0.08)
		g.lathe("painted_metal", Vector3(0.0, 0.0, 0.0), PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.24, 0.12), Vector2(0.15, 0.2), Vector2(0.02, 0.23)]), 14)
		done()
		# move the lid: rebuild it hanging on the side (simple: second lathe above, tilted)
		var lt := t * Transform3D(Basis(Vector3.BACK, 1.25), Vector3(0.36, 0.55, 0))
		use(lt)
		g.col = Color(0.08, 0.08, 0.08)
		g.lathe("painted_metal", Vector3.ZERO, PackedVector2Array([Vector2(0.27, 0.0), Vector2(0.24, 0.12), Vector2(0.15, 0.2), Vector2(0.02, 0.23)]), 14)
		done()
		_smoke(xf * (t * Vector3(0, 0.95, 0)), 4, 0.35, 0.35)

	func fire(p: Vector3, night: bool, smoke: bool) -> void:
		var t := at(p, r.randf() * TAU)
		prop("firepit", p, r.randf() * TAU, 1.0)
		use(t)
		for k in 5: # half-burnt logs in a tipi
			var a := TAU * k / 5.0 + r.randf_range(-0.2, 0.2)
			g.col = Color(0.25, 0.2, 0.17) if not night else Color(0.18, 0.12, 0.1)
			g.tube("wood", [Vector3(cos(a) * 0.38, 0.1, sin(a) * 0.38), Vector3(cos(a) * 0.05, 0.38, sin(a) * 0.05)], 0.045, 6)
		done()
		var wp := xf * (t * Vector3(0, 0.15, 0))
		if smoke:
			_smoke(wp + Vector3(0, 0.4, 0), 8, 0.5, 0.6)
		_flames(wp, night)
		if night:
			var l := OmniLight3D.new()
			l.name = "CampfireLight"
			l.light_color = Color(1.0, 0.55, 0.22)
			l.light_energy = 2.2
			l.omni_range = 9.0
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.position = wp + Vector3(0, 0.7, 0)
			l.distance_fade_enabled = true
			l.distance_fade_begin = 45.0
			l.distance_fade_length = 15.0
			l.set_script(_flicker_script())
			root.add_child(l)

	# ------------------------------------------------------------- people + props

	func person(p: Vector3, yaw: float, excite: float) -> void:
		var t := at(p, yaw)
		_ppl(PeopleKit.Role.SPECTATOR, xf * t, JACKETS[r.randi() % JACKETS.size()], Color(r.randf(), excite, 0.0, 0.0))

	func person_seated(p: Vector3, yaw: float) -> void:
		var t := at(Vector3(p.x, 0, p.z), yaw)
		t.origin.y += p.y
		_ppl(PeopleKit.Role.SEATED, xf * t, JACKETS[r.randi() % JACKETS.size()], Color(r.randf(), 0.0, 0.0, 0.0))

	func _ppl(role: int, t: Transform3D, col: Color, cu: Color) -> void:
		if not ppl.has(role):
			ppl[role] = [[], [], []]
		ppl[role][0].append(t)
		ppl[role][1].append(col)
		ppl[role][2].append(cu)

	func prop(key: String, p: Vector3, yaw: float, s: float) -> void:
		var t := at(p, yaw)
		t.basis = t.basis.scaled(Vector3.ONE * s)
		if not props.has(key):
			props[key] = []
		props[key].append(xf * t)

	# ------------------------------------------------------------- helpers

	## Quad with per-vertex normals from its plane; `two` adds the back face.
	func _smooth_quad(mat: String, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, two := false) -> void:
		g.col = col
		var n := (b - a).cross(d - a).normalized()
		if n.length_squared() < 0.5:
			n = (cc - b).cross(a - b).normalized()
		g.tri_n(mat, a, b, cc, n, n, n)
		g.tri_n(mat, a, cc, d, n, n, n)
		if two:
			g.tri_n(mat, a, cc, b, -n, -n, -n)
			g.tri_n(mat, a, d, cc, -n, -n, -n)

	## Shell from a convex side profile (x, y) extruded across z in [-hw, hw],
	## with rounded side edges (`round` m) so it doesn't read as a box.
	func _side_shell(mat: String, prof: PackedVector2Array, hw: float, rnd: float, col: Color) -> void:
		g.col = col
		var n := prof.size()
		var cen := Vector2.ZERO
		for q in prof:
			cen += q
		cen /= n
		# inset profile for the side faces (rounded edge goes from the full profile at z = hw - rnd to the inset at z = hw)
		var steps := 3
		var rings := []
		for k in steps + 1:
			var a := PI * 0.5 * float(k) / steps
			var zz := hw - rnd + sin(a) * rnd
			var ins := rnd * (1.0 - cos(a))
			var ring := PackedVector2Array()
			for q in prof:
				ring.append(q + (cen - q).normalized() * ins)
			rings.append([zz, ring])
		for sz: float in [-1.0, 1.0]:
			# rounded strip from the full profile outwards to the side face
			for k in steps + 1:
				var cur: Array = rings[k]
				if k > 0:
					var p0: PackedVector2Array = rings[k - 1][1]
					var p1: PackedVector2Array = cur[1]
					var z0: float = rings[k - 1][0] * sz
					var z1: float = cur[0] * sz
					for i in n:
						var j := (i + 1) % n
						_quad_out(mat, Vector3(p0[i].x, p0[i].y, z0), Vector3(p0[j].x, p0[j].y, z0), Vector3(p1[j].x, p1[j].y, z1), Vector3(p1[i].x, p1[i].y, z1), Vector3(cen.x, cen.y, 0))
			# flat side face
			var last: PackedVector2Array = rings[steps][1]
			var zf: float = rings[steps][0] * sz
			for i in n:
				var j := (i + 1) % n
				var a3 := Vector3(cen.x, cen.y, zf)
				var b3 := Vector3(last[i].x, last[i].y, zf)
				var c3 := Vector3(last[j].x, last[j].y, zf)
				_tri_out(mat, a3, b3, c3, Vector3(cen.x, cen.y, 0))
		# the band across the width (roof, nose, floor, back)
		var z0 := -(hw - rnd)
		var z1 := hw - rnd
		for i in n:
			var j := (i + 1) % n
			_quad_out(mat, Vector3(prof[i].x, prof[i].y, z0), Vector3(prof[j].x, prof[j].y, z0), Vector3(prof[j].x, prof[j].y, z1), Vector3(prof[i].x, prof[i].y, z1), Vector3(cen.x, cen.y, 0))

	func _quad_out(mat: String, a: Vector3, b: Vector3, cc: Vector3, d: Vector3, inside: Vector3) -> void:
		_tri_out(mat, a, b, cc, inside)
		_tri_out(mat, a, cc, d, inside)

	func _tri_out(mat: String, a: Vector3, b: Vector3, cc: Vector3, inside: Vector3) -> void:
		var n := (b - a).cross(cc - a)
		if n.length_squared() < 1e-10:
			return
		var mid := (a + b + cc) / 3.0
		var out := mid - inside
		if n.dot(out) < 0.0:
			g.tri(mat, a, cc, b)
		else:
			g.tri(mat, a, b, cc)

	func _wheel(cen: Vector3, rad: float, wdt: float) -> void:
		g.col = Color(0.06, 0.06, 0.06)
		g.tube("rubber", [cen + Vector3(0, 0, -wdt * 0.5), cen + Vector3(0, 0, wdt * 0.5)], rad, 14)
		g.col = Color(0.7, 0.7, 0.7)
		var sz := signf(cen.z) if cen.z != 0.0 else 1.0
		g.tube("steel", [cen + Vector3(0, 0, sz * wdt * 0.5), cen + Vector3(0, 0, sz * (wdt * 0.5 + 0.005))], rad * 0.6, 12)

	func _ring(cen: Vector3, rad: float, n: int) -> Array:
		var out := []
		for i in n + 1:
			var a := TAU * i / n
			out.append(cen + Vector3(cos(a), 0, sin(a)) * rad)
		return out

	func _smoke(wp: Vector3, amount: int, size: float, rise: float) -> void:
		var ps := GPUParticles3D.new()
		ps.name = "Smoke"
		ps.amount = amount
		ps.lifetime = 7.0
		ps.preprocess = 7.0
		ps.position = wp
		ps.visibility_range_end = 220.0
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ps.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 14, 12))
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.15, 1, 0.05)
		pm.spread = 12.0
		pm.initial_velocity_min = rise * 0.8
		pm.initial_velocity_max = rise * 1.3
		var wd := Vector2(0.85, 0.35).normalized() # WX_DIR (shaders/weather.gdshaderinc)
		var wind := 0.35
		var wx = c.get("weather")
		if wx != null and wx.get("wind") != null:
			wind = float(wx.get("wind"))
		pm.gravity = Vector3(wd.x, 0.25, wd.y) * (0.6 + 3.0 * wind) # bends downwind
		pm.damping_min = 0.05
		pm.damping_max = 0.1
		pm.scale_min = size * 0.8
		pm.scale_max = size * 1.2
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4))
		sc.add_point(Vector2(1, 3.2))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -12.0
		pm.angular_velocity_max = 12.0
		var gr := Gradient.new()
		gr.set_color(0, Color(0.62, 0.62, 0.6, 0.0))
		gr.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
		gr.add_point(0.12, Color(0.55, 0.55, 0.53, 0.32))
		gr.add_point(0.5, Color(0.65, 0.65, 0.64, 0.16))
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
		ps.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = GxCamp.fx_texture("smoke")
		m.disable_receive_shadows = true
		q.material = m
		ps.draw_pass_1 = q
		root.add_child(ps)

	func _flames(wp: Vector3, night: bool) -> void:
		var ps := GPUParticles3D.new()
		ps.name = "Flames"
		ps.amount = 10 if night else 6
		ps.lifetime = 0.7
		ps.position = wp
		ps.visibility_range_end = 160.0
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ps.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.15
		pm.direction = Vector3.UP
		pm.spread = 8.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 0.9
		pm.gravity = Vector3(0, 0.4, 0)
		pm.scale_min = 0.45 if night else 0.3
		pm.scale_max = 0.7 if night else 0.45
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.7))
		sc.add_point(Vector2(0.4, 1.0))
		sc.add_point(Vector2(1, 0.2))
		var sct := CurveTexture.new()
		sct.curve = sc
		pm.scale_curve = sct
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 0.0))
		gr.set_color(1, Color(1, 0.6, 0.3, 0.0))
		gr.add_point(0.15, Color(1, 1, 1, 1))
		gr.add_point(0.6, Color(1, 0.8, 0.6, 0.7))
		var gt := GradientTexture1D.new()
		gt.gradient = gr
		pm.color_ramp = gt
		ps.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.9)
		q.center_offset = Vector3(0, 0.35, 0)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = GxCamp.fx_texture("flame")
		m.albedo_color = Color(2.2, 2.2, 2.2) if night else Color(1.2, 1.2, 1.2)
		m.disable_receive_shadows = true
		q.material = m
		ps.draw_pass_1 = q
		root.add_child(ps)

	func _flicker_script() -> GDScript:
		var s := GDScript.new()
		s.source_code = """extends OmniLight3D
var _t := randf() * 10.0
var _base := 2.2
func _ready() -> void:
	_base = light_energy
func _process(d: float) -> void:
	_t += d
	light_energy = _base * (0.82 + 0.1 * sin(_t * 9.1) + 0.06 * sin(_t * 23.7) + 0.05 * sin(_t * 3.3))
"""
		s.reload()
		return s

	# ------------------------------------------------------------- commit

	func commit() -> void:
		done()
		g.commit(root, "Camp", GEO_VIS, false)
		for ch in root.get_children():
			if ch is MeshInstance3D and str(ch.name).begins_with("Camp_"):
				var mi := ch as MeshInstance3D
				mi.mesh = CarModel._with_lods(mi.mesh) # cheap far LOD for tents / caravan
		shadow.commit(root, "CampShadow", 90.0, true)
		for ch in root.get_children():
			if ch is MeshInstance3D and str(ch.name).begins_with("CampShadow"):
				(ch as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var cv := root.get_node_or_null("Camp_canvas") as MeshInstance3D
		if cv:
			cv.material_override = GxCamp.canvas_material(cv.material_override)
		if not flags[0].is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = flags[0]
			arrays[Mesh.ARRAY_NORMAL] = flags[1]
			arrays[Mesh.ARRAY_TEX_UV] = flags[2]
			arrays[Mesh.ARRAY_TEX_UV2] = flags[3]
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "CampFlags"
			mi.mesh = mesh
			mi.material_override = GxCamp.flag_material()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 260.0
			root.add_child(mi)
		for key: String in props:
			var pm := GxCamp.prop_mesh(key)
			if pm.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pm[0]
			var list: Array = props[key]
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i] * (pm[1] as Transform3D))
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "Prop_" + key
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = PROP_VIS + mm.get_aabb().size.length() * 0.5
			mmi.visibility_range_end_margin = 12.0
			root.add_child(mmi)
		for role: int in ppl:
			var d: Array = ppl[role]
			var xfs: Array[Transform3D] = []
			xfs.assign(d[0])
			var cols: Array[Color] = []
			cols.assign(d[1])
			var cus: Array[Color] = []
			cus.assign(d[2])
			root.add_child(GxCamp.limit(PeopleKit.crowd("CampPeople", role as PeopleKit.Role, xfs, cols, cus, false), 200.0)) # far tier is ~320 tris a figure: cheap


## Debug (`--gx_ab`, with --gx_test=<one piece> and --disable-vsync): points
## the camera at `root`'s piece and toggles it on/off every 1.2 s, printing
## the mean frame time with and without it (CPU+GPU cost of the piece).
static var _ab_done := false
static func maybe_ab(root: Node3D, eye: Vector3, target: Vector3) -> void:
	if not OS.get_cmdline_user_args().has("--gx_ab") or _ab_done:
		return
	_ab_done = true # only the first piece placed (gx_test runs before the dressing)
	var ab := AB.new()
	ab.target_node = root
	ab.eye = eye
	ab.look = target
	root.get_parent().add_child.call_deferred(ab)


class AB:
	extends Node
	var target_node: Node3D
	var eye: Vector3
	var look: Vector3
	var _t := -1.5
	var _seg := 0
	var _acc := [0.0, 0.0]
	var _n := [0, 0]

	func _process(delta: float) -> void:
		var cam := get_viewport().get_camera_3d()
		if cam and "debug_world" in cam:
			cam.debug_world = [eye, look]
		_t += delta
		if _t < 0.0:
			return
		var on := _seg % 2 == 0
		if _t > 0.3: # skip the switch frames
			_acc[0 if on else 1] += delta
			_n[0 if on else 1] += 1
		if _t > 1.2:
			_t = 0.0
			_seg += 1
			target_node.visible = _seg % 2 == 0
			if _seg == 6:
				var a: float = _acc[0] / maxi(_n[0], 1) * 1000.0
				var b: float = _acc[1] / maxi(_n[1], 1) * 1000.0
				print("gx_ab: %s on %.3f ms, off %.3f ms, cost %.3f ms" % [target_node.name, a, b, a - b])
