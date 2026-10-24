class_name GxHospitality
extends RefCounted
## Spectator village by the track: food vans with their serving hatches propped
## open and queues of people, a white hospitality marquee with clear-window
## walls and tables, a merch gazebo with shirts on a rail, a row of portable
## toilets, bins, and a big LED screen on a truck showing the race (it shows
## the live picture: the screen samples the frame being rendered, so it costs
## no extra camera).
##
##   GxHospitality.place(c, Gx.frame(c, 120.0, Gx.RIGHT, 6.0), {})
##
## Frame: Gx.frame (x along, +z away from the road). Footprint x in [-16, 16],
## z in [0, 18]. Options: vans (2), marquee (true), screen (true), toilets (4),
## merch (true), people (true), seed. Reuses GxCamp's builder (PBR materials,
## PeopleKit, Poly Haven props: outdoor table sets, bins).

const VAN_COLS := [[Color(0.86, 0.82, 0.70), Color(0.62, 0.10, 0.08)], [Color(0.55, 0.78, 0.70), Color(0.15, 0.32, 0.28)],
	[Color(0.88, 0.88, 0.86), Color(0.12, 0.25, 0.50)], [Color(0.95, 0.75, 0.20), Color(0.18, 0.18, 0.18)]]
const MENUS := ["b_marzelli", "b_aurel", "b_falke", "b_valter"]

static var _screen_mat: ShaderMaterial


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(opts.get("seed", hash(xf.origin.snapped(Vector3.ONE) + Vector3(0, 3, 0))))
	var root := Node3D.new()
	root.name = "GxHospitality"
	c.add_child(root)
	var cam := GxCamp.Camp.new(c, root, xf, r)
	var people := GxCamp._b(opts.get("people", true))
	Gx.reserve(c, xf * Vector3(0, 0, 9), 19.0)
	# food vans along the back, hatches towards the road
	var nv := int(opts.get("vans", 2))
	for i in nv:
		var x := lerpf(-11.0, -1.0, (i + 0.5) / maxf(nv, 1)) if nv > 1 else -6.0
		var p := Vector3(x, 0, 11.5 + r.randf_range(-0.5, 0.5))
		var yaw := r.randf_range(-0.08, 0.08)
		var cols: Array = VAN_COLS[(i + r.randi()) % VAN_COLS.size()]
		_food_van(cam, p, yaw, cols[0], cols[1], MENUS[(i + r.randi()) % MENUS.size()])
		if people:
			var qn := r.randi_range(3, 6)
			for k in qn: # queue snaking towards the road, facing the hatch
				var q := p + Vector3(r.randf_range(-0.3, 0.3) + k * 0.15, 0, -1.9 - k * 0.75)
				cam.person(q, PI + r.randf_range(-0.3, 0.3), 0.0)
		cam.prop("barrel", p + Vector3(2.4, 0, -1.6), r.randf() * TAU, 1.0)
	# tables in front of the vans
	for i in 3:
		cam.prop("table_set", Vector3(-12.0 + i * 4.0 + r.randf_range(-0.5, 0.5), 0, 5.5 + r.randf_range(-0.8, 0.8)), r.randf() * TAU, 1.0)
		if people and r.randf() < 0.7:
			cam.person(Vector3(-12.0 + i * 4.0 + 0.9, 0, 6.3), r.randf() * TAU, 0.1)
	if GxCamp._b(opts.get("marquee", true)):
		_marquee(cam, Vector3(8.5, 0, 11.0), r.randf_range(-0.05, 0.05), people)
	if GxCamp._b(opts.get("merch", true)):
		_merch(cam, Vector3(3.0, 0, 3.5), r.randf_range(-0.15, 0.15))
		if people:
			for k in 3:
				cam.person(Vector3(3.0 + r.randf_range(-1.2, 1.2), 0, 1.2 + r.randf_range(-0.3, 0.3)), PI + r.randf_range(-0.5, 0.5), 0.0)
	var nt := int(opts.get("toilets", 4))
	for i in nt:
		_toilet(cam, Vector3(-15.0, 0, 3.0 + i * 1.35), PI * 0.5 + r.randf_range(-0.04, 0.04), r.randf() < 0.5)
	if GxCamp._b(opts.get("screen", true)):
		_screen_truck(cam, root, Vector3(13.5, 0, 3.0), -0.35)
	cam.commit()


static func _food_van(cam: GxCamp.Camp, p: Vector3, yaw: float, body: Color, trim: Color, menu: String) -> void:
	cam.use(cam.at(p, yaw))
	var g := cam.g
	var hw := 1.05
	# side profile (x, y): boxy-but-rounded step van, cab at +x
	var prof := PackedVector2Array([Vector2(-2.7, 0.42), Vector2(2.45, 0.42), Vector2(2.72, 0.75), Vector2(2.75, 1.25),
		Vector2(2.45, 2.05), Vector2(2.05, 2.62), Vector2(-2.55, 2.66), Vector2(-2.72, 2.48)])
	cam._side_shell("painted_metal", prof, hw, 0.14, body)
	# trim band, bumpers
	g.col = trim
	for sz: float in [-1.0, 1.0]:
		g.box("painted_metal", Vector3(0.0, 0.62, sz * (hw + 0.004)), Vector3(5.2, 0.26, 0.01))
	g.col = Color(0.15, 0.15, 0.15)
	g.box("painted_metal", Vector3(2.78, 0.5, 0), Vector3(0.12, 0.2, 2.05), 0.04)
	g.box("painted_metal", Vector3(-2.75, 0.5, 0), Vector3(0.1, 0.2, 2.0), 0.04)
	# cab glass: windscreen + side windows
	g.col = Color.WHITE
	g.box("glass", Vector3(2.27, 1.95, 0), Vector3(0.03, 0.75, 1.85), 0.06, Basis(Vector3.BACK, 0.62))
	for sz: float in [-1.0, 1.0]:
		g.box("glass", Vector3(1.9, 1.8, sz * (hw + 0.006)), Vector3(0.75, 0.6, 0.01), 0.05)
	# headlamps
	g.col = Color(0.9, 0.9, 0.85)
	for sz: float in [-0.7, 0.7]:
		g.box("glass", Vector3(2.76, 0.88, sz), Vector3(0.03, 0.16, 0.28), 0.03)
	# serving hatch on -z: dark interior, counter, flap propped up as an awning
	var hx := -0.6
	g.col = Color(0.05, 0.05, 0.05)
	g.box("painted_metal", Vector3(hx, 1.6, -hw - 0.003), Vector3(2.6, 0.95, 0.01))
	g.col = Color(0.75, 0.75, 0.75)
	g.box("steel", Vector3(hx, 1.12, -hw - 0.18), Vector3(2.7, 0.05, 0.38), 0.01)
	g.col = trim
	g.box("painted_metal", Vector3(hx, 2.28, -hw - 0.45), Vector3(2.75, 0.04, 0.95), 0.01, Basis(Vector3.RIGHT, 0.32))
	g.col = Color(0.3, 0.3, 0.3)
	for sx: float in [-1.3, 1.3]:
		g.bar("steel", Vector3(hx + sx, 2.08, -hw), Vector3(hx + sx, 2.15, -hw - 0.88), 0.012, 4)
	# menu board on the side + roof sign
	g.sign(Vector3(-2.1, 1.6, -hw - 0.012), Vector3(0, 0, -1), 0.9, 0.0, menu, Vector3.UP)
	g.col = trim
	g.box("painted_metal", Vector3(-0.4, 2.95, 0), Vector3(2.8, 0.55, 0.08), 0.02)
	g.sign(Vector3(-0.4, 2.95, -0.045), Vector3(0, 0, -1), 2.6, 0.0, menu)
	g.sign(Vector3(-0.4, 2.95, 0.045), Vector3(0, 0, 1), 2.6, 0.0, menu)
	# wheels, gas bottles at the back
	for x: float in [-1.7, 1.75]:
		for sz: float in [-1.0, 1.0]:
			cam._wheel(Vector3(x, 0.36, sz * 0.92), 0.36, 0.2)
	g.col = Color(0.85, 0.35, 0.1)
	for k in 2:
		g.tube("painted_metal", [Vector3(-2.95, 0.0, -0.3 + k * 0.35), Vector3(-2.95, 0.65, -0.3 + k * 0.35)], 0.14, 10)
	g.collide(Vector3(0, 1.5, 0), Vector3(5.4, 2.4, 2.1))
	cam.done()


static func _marquee(cam: GxCamp.Camp, p: Vector3, yaw: float, people: bool) -> void:
	cam.use(cam.at(p, yaw))
	var g := cam.g
	var hx := 5.5
	var hz := 3.5
	var eave := 2.4
	var ridge := 4.1
	var white := Color(0.92, 0.92, 0.9)
	# frame: aluminium uprights and rafters
	g.col = Color(0.7, 0.72, 0.74)
	for i in 5:
		var x := lerpf(-hx, hx, i / 4.0)
		for sz: float in [-1.0, 1.0]:
			g.box("steel", Vector3(x, eave * 0.5, sz * hz), Vector3(0.08, eave, 0.12))
			g.beam("steel", Vector3(x, eave, sz * hz), Vector3(x, ridge, 0), 0.08)
	# roof: two slopes with a gentle sag between rafters
	for i in 4:
		var x0 := lerpf(-hx, hx, i / 4.0)
		var x1 := lerpf(-hx, hx, (i + 1) / 4.0)
		for sz: float in [-1.0, 1.0]:
			var steps := 3
			for k in steps:
				var t0 := float(k) / steps
				var t1 := float(k + 1) / steps
				var y0 := lerpf(eave, ridge, t0)
				var y1 := lerpf(eave, ridge, t1)
				var z0 := sz * hz * (1.0 - t0)
				var z1 := sz * hz * (1.0 - t1)
				var xm := (x0 + x1) * 0.5
				var sag0 := -0.06 * sin(PI * t0)
				var sag1 := -0.06 * sin(PI * t1)
				var cc := white * (0.92 + 0.08 * t0)
				cc.a = 1.0
				cam._smooth_quad("canvas", Vector3(x0, y0 + 0.02, z0), Vector3(xm, y0 + sag0, z0), Vector3(xm, y1 + sag1, z1), Vector3(x0, y1 + 0.02, z1), cc, true)
				cam._smooth_quad("canvas", Vector3(xm, y0 + sag0, z0), Vector3(x1, y0 + 0.02, z0), Vector3(x1, y1 + 0.02, z1), Vector3(xm, y1 + sag1, z1), cc, true)
		# back wall (+z) with clear window strip, gable ends
		var wc := white * 0.95
		wc.a = 1.0
		cam._smooth_quad("canvas", Vector3(x0, 0, hz), Vector3(x1, 0, hz), Vector3(x1, 0.9, hz), Vector3(x0, 0.9, hz), wc, true)
		cam._smooth_quad("canvas", Vector3(x0, 1.9, hz), Vector3(x1, 1.9, hz), Vector3(x1, eave, hz), Vector3(x0, eave, hz), wc, true)
		g.col = Color(0.8, 0.85, 0.9)
		g.box("glass", Vector3((x0 + x1) * 0.5, 1.4, hz), Vector3(x1 - x0 - 0.15, 0.95, 0.01), 0.02)
	for sx: float in [-1.0, 1.0]:
		var wc := white * 0.9
		wc.a = 1.0
		g.col = wc
		cam._smooth_quad("canvas", Vector3(sx * hx, 0, -hz), Vector3(sx * hx, 0, hz), Vector3(sx * hx, eave, hz), Vector3(sx * hx, eave, -hz), wc, true)
		g.col = wc
		g.tri_n("canvas", Vector3(sx * hx, eave, -hz), Vector3(sx * hx, eave, hz), Vector3(sx * hx, ridge, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0), Vector3(sx, 0, 0))
		g.tri_n("canvas", Vector3(sx * hx, eave, -hz), Vector3(sx * hx, ridge, 0), Vector3(sx * hx, eave, hz), Vector3(-sx, 0, 0), Vector3(-sx, 0, 0), Vector3(-sx, 0, 0))
	# banner along the front valance
	g.sign(Vector3(0, eave - 0.05, -hz - 0.02), Vector3(0, 0, -1), 6.0, 0.0, "b_press")
	cam.done()
	for i in 4:
		var tx := lerpf(-hx + 1.4, hx - 1.4, i / 3.0)
		cam.prop("table_set", p + Vector3(tx, 0, 0.6 * (1 if i % 2 == 0 else -1)).rotated(Vector3.UP, yaw), yaw + i, 1.0)
		if people:
			cam.person(p + Vector3(tx + 0.8, 0, -1.4).rotated(Vector3.UP, yaw), PI + i, 0.05)


static func _merch(cam: GxCamp.Camp, p: Vector3, yaw: float) -> void:
	cam.gazebo(p, yaw, 1)
	cam.use(cam.at(p, yaw))
	# rail with shirts and scarves across the front
	cam.g.col = Color(0.6, 0.6, 0.6)
	cam.g.bar("steel", Vector3(-1.3, 1.95, -1.4), Vector3(1.3, 1.95, -1.4), 0.015, 5)
	var x := -1.2
	var k := 0
	while x < 1.1:
		var idx: int = [12, 13, 14, 15, 0, 2][k % 6]
		cam._flag(Vector3(x, 1.93, -1.4), Vector3(1, 0, 0), Vector3(0, -1, 0), 0.42, 0.62, idx, false)
		x += 0.5
		k += 1
	cam.done()


static func _toilet(cam: GxCamp.Camp, p: Vector3, yaw: float, blue: bool) -> void:
	cam.use(cam.at(p, yaw))
	var g := cam.g
	var body := Color(0.12, 0.3, 0.6) if blue else Color(0.2, 0.42, 0.25)
	g.col = body
	g.box("painted_metal", Vector3(0, 1.12, 0), Vector3(1.12, 2.2, 1.18), 0.06)
	g.col = Color(0.9, 0.9, 0.88)
	g.box("painted_metal", Vector3(0, 2.3, 0), Vector3(1.2, 0.18, 1.26), 0.08)
	g.col = body.darkened(0.12)
	g.box("painted_metal", Vector3(0, 1.08, -0.595), Vector3(0.82, 1.95, 0.02), 0.02)
	g.col = Color(0.85, 0.1, 0.08)
	g.box("painted_metal", Vector3(0.3, 1.15, -0.61), Vector3(0.1, 0.05, 0.01))
	g.col = Color(0.15, 0.15, 0.15)
	g.bar("painted_metal", Vector3(0.4, 2.2, 0.4), Vector3(0.4, 2.65, 0.4), 0.04, 6)
	g.box("painted_metal", Vector3(0, 0.03, 0), Vector3(1.2, 0.06, 1.26))
	g.collide(Vector3(0, 1.15, 0), Vector3(1.15, 2.3, 1.2))
	cam.done()


static func _screen_truck(cam: GxCamp.Camp, root: Node3D, p: Vector3, yaw: float) -> void:
	var t := cam.at(p, yaw)
	cam.use(t)
	var g := cam.g
	# small rigid truck: cab + box body, screen on a lifted frame above the box
	var cab := Color(0.85, 0.85, 0.83)
	g.col = cab
	g.box("painted_metal", Vector3(2.6, 1.45, 0), Vector3(1.6, 1.9, 2.2), 0.15)
	g.col = Color.WHITE
	g.box("glass", Vector3(3.41, 1.85, 0), Vector3(0.02, 0.75, 1.9), 0.05)
	g.col = Color(0.15, 0.15, 0.17)
	g.box("painted_metal", Vector3(-1.0, 1.55, 0), Vector3(5.4, 2.3, 2.35), 0.06)
	g.col = Color(0.12, 0.12, 0.12)
	g.box("steel", Vector3(0.3, 0.45, 0), Vector3(7.0, 0.25, 1.2))
	for x: float in [-2.6, 2.6]:
		for sz: float in [-1.0, 1.0]:
			cam._wheel(Vector3(x, 0.48, sz * 1.0), 0.48, 0.28)
	# mast + screen frame
	g.col = Color(0.2, 0.2, 0.2)
	g.box("steel", Vector3(-1.0, 3.3, 0), Vector3(0.3, 1.3, 0.3))
	g.box("painted_metal", Vector3(-1.0, 5.4, 0.05), Vector3(5.2, 3.1, 0.22), 0.05)
	g.collide(Vector3(0, 1.5, 0), Vector3(7.2, 2.6, 2.4))
	cam.done()
	var mi := MeshInstance3D.new()
	mi.name = "LEDScreen"
	var q := QuadMesh.new()
	q.size = Vector2(4.8, 2.7)
	mi.mesh = q
	mi.material_override = screen_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 160.0
	# QuadMesh faces +z: turn it to face -z (the road side of the frame)
	mi.transform = cam.xf * t * Transform3D(Basis(Vector3.UP, PI), Vector3(-1.0, 5.4, -0.08))
	root.add_child(mi)


## The live picture on an LED panel: samples the frame being drawn (no extra
## render), with a visible pixel grid and a slight bloom of the LEDs.
static func screen_material() -> ShaderMaterial:
	if _screen_mat:
		return _screen_mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform sampler2D scr : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = vec2(UV.x, UV.y);
	vec3 c = textureLod(scr, uv, 2.5).rgb;
	vec2 cell = fract(UV * vec2(192.0, 108.0));
	float led = smoothstep(0.0, 0.18, cell.x) * smoothstep(1.0, 0.82, cell.x) * smoothstep(0.0, 0.18, cell.y) * smoothstep(1.0, 0.82, cell.y);
	ALBEDO = c * (0.55 + 0.75 * led) * 1.1 + vec3(0.01);
	ALPHA = 1.0;
}
"""
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = sh
	return _screen_mat
