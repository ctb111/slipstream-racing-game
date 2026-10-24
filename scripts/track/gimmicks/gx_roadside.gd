class_name GxRoadside
extends RefCounted
## Roadside businesses beside the track: a petrol station (canopy with lit
## soffit, pump islands, shop with glazed front, price pylon) or a diner (chrome
## and glass, neon roof sign, striped awning, terrace with parasols). Both get
## parked cars with owners (GxParkedCars) and Poly Haven clutter.
##
##   GxRoadside.place(c, Gx.frame(c, 700.0, Gx.RIGHT, 6.0), {kind = "petrol"})
##
## kind: "petrol" (default) | "diner".  brand: petrol brand name ("HELIOS").
## name: diner name ("ROSIE'S").  cars: false to skip the parked cars.
## Frame from Gx.frame: -z faces the road; footprint ~40 m along x, ~32 m deep.
## Keep lateral >= 4 so the forecourt clears the rails. One real light at night.

const BRANDS := {HELIOS = Color(0.9, 0.55, 0.05), VALTER = Color(0.1, 0.35, 0.65), KRONEN = Color(0.7, 0.08, 0.06), NORDLICHT = Color(0.1, 0.45, 0.25)}
const LAMP := "res://assets/gimmicks/street_lamp_01/street_lamp_01.gltf"


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind := str(opts.get("kind", "petrol"))
	var holder := Node3D.new()
	holder.name = "GxRoadside_" + kind
	c.add_child(holder)
	var rng := Gx.rng(c, "roadside%d" % int(xf.origin.x * 3.0 + xf.origin.z))
	var g := GxGeo.new(xf)
	var labels: Array = []
	var gy := func(x: float, z: float) -> float:
		var w := xf * Vector3(x, 0, z)
		return Gx.ground(c, w) - xf.origin.y
	# Level pad: the highest ground under the footprint (clamped), so buildings sit flat.
	var pad := -INF
	for x: float in [-18.0, 0.0, 18.0]:
		for z: float in [2.0, 16.0, 30.0]:
			pad = maxf(pad, gy.call(x, z))
	pad = clampf(pad, -1.0, 2.0) + 0.05
	var body := StaticBody3D.new()
	body.name = "GxRoadsideCol"
	holder.add_child(body)
	var ob := xf.basis.orthonormalized()
	var col := func(cen: Vector3, size: Vector3) -> void:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.transform = Transform3D(ob, xf * cen)
		body.add_child(cs)
	# forecourt slab with kerb edge
	g.col = Color(0.78, 0.77, 0.74)
	g.box("concrete", Vector3(0, pad - 0.6, 16.0), Vector3(40.0, 1.2, 30.0))
	g.col = Color(0.85, 0.85, 0.82)
	g.box("concrete", Vector3(0, pad + 0.02, 1.1), Vector3(40.0, 0.14, 0.3), 0.03)
	var models := {}
	if kind == "diner":
		_diner(g, rng, pad, labels, col, models, opts)
	else:
		_petrol(g, rng, pad, labels, col, models, opts)
	# street lamps along the front (Poly Haven lamp post)
	models[LAMP] = []
	for x: float in [-17.0, 17.0]:
		models[LAMP].append(Transform3D(ob, xf * Vector3(x, pad, 1.8)))
	GxProps.commit(g, holder, "GxRoad", 900.0, true)
	for id: String in models:
		GxProps.scatter(holder, id, models[id], 200.0 if id != LAMP else 400.0)
	for lb: Array in labels:
		var l := Label3D.new()
		l.text = lb[0]
		l.font_size = int(lb[3])
		l.pixel_size = 0.01
		l.modulate = lb[4]
		l.outline_size = 0
		l.shaded = lb.size() < 6 or not lb[5]
		l.double_sided = false
		var t: Transform3D = lb[1]
		l.transform = Transform3D((xf.basis * t.basis).orthonormalized(), xf * t.origin)
		l.visibility_range_end = float(lb[2])
		holder.add_child(l)
	# night light: one warm/cool omni under the canopy or over the terrace
	var om := OmniLight3D.new()
	om.light_color = Color(0.95, 0.97, 1.0) if kind != "diner" else Color(1.0, 0.75, 0.5)
	om.light_energy = 4.0 if Car.night else 0.0
	om.visible = Car.night
	om.omni_range = 16.0
	om.shadow_enabled = false
	om.distance_fade_enabled = true
	om.distance_fade_begin = 150.0
	om.distance_fade_length = 30.0
	om.position = xf * Vector3(0, pad + 4.6, 11.0 if kind != "diner" else 7.0)
	holder.add_child(om)
	if opts.get("cars", true) and ResourceLoader.exists("res://scripts/track/gimmicks/gx_parked_cars.gd"):
		var cx := 13.0 if kind != "diner" else -12.0
		var sub := xf * Transform3D(Basis(), Vector3(cx, pad, 21.0 if kind != "diner" else 12.0))
		load("res://scripts/track/gimmicks/gx_parked_cars.gd").place(c, sub, {count = 3 if kind != "diner" else 4, layout = "angled", dirt = 0.25, people = true})
	for k in 3:
		Gx.reserve(c, xf * Vector3(-14.0 + k * 14.0, 0, 16.0), 16.0)


# --------------------------------------------------------------- petrol station
static func _petrol(g: GxGeo, rng: RandomNumberGenerator, y: float, labels: Array, col: Callable, models: Dictionary, opts: Dictionary) -> void:
	var brand := str(opts.get("brand", BRANDS.keys()[rng.randi() % BRANDS.size()]))
	var bc: Color = BRANDS.get(brand, Color(0.9, 0.55, 0.05))
	# canopy: 22 x 13 m, soffit at 5.2 m, 1.1 m fascia with brand stripe
	var cz := 11.5
	var ch := 5.2
	g.col = Color(0.88, 0.88, 0.86)
	g.box("painted_metal", Vector3(0, y + ch + 0.55, cz), Vector3(22.0, 1.1, 13.0), 0.05)
	g.col = bc
	for s: float in [-1.0, 1.0]:
		g.box("painted_metal", Vector3(0, y + ch + 0.35, cz + s * 6.52), Vector3(22.04, 0.32, 0.04))
		g.box("painted_metal", Vector3(s * 11.02, y + ch + 0.35, cz), Vector3(0.04, 0.32, 13.04))
	labels.append([brand, Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + ch + 0.8, cz - 6.56)), 500.0, 70, Color(0.15, 0.15, 0.15)])
	# soffit light panels (emissive) in a 5 x 3 grid
	g.col = Color(1, 1, 1)
	for i in 5:
		for j in 3:
			g.box("emit", Vector3(-8.0 + i * 4.0, y + ch - 0.06, cz - 4.0 + j * 4.0), Vector3(1.2, 0.04, 1.2), 0.01)
	g.col = Color(0.75, 0.76, 0.77)
	g.box("painted_metal", Vector3(0, y + ch + 0.0, cz), Vector3(21.9, 0.04, 12.9)) # soffit sheet
	# columns
	for x: float in [-7.0, 7.0]:
		for z: float in [cz - 3.0, cz + 3.0]:
			g.col = Color(0.85, 0.85, 0.83)
			g.box("painted_metal", Vector3(x, y + ch * 0.5, z), Vector3(0.45, ch, 0.45), 0.04)
			col.call(Vector3(x, y + ch * 0.5, z), Vector3(0.5, ch, 0.5))
	# pump islands (between the column rows) with two dispensers each
	for i in 3:
		var ix := -7.0 + i * 7.0
		g.col = Color(0.8, 0.8, 0.78)
		g.box("concrete", Vector3(ix, y + 0.12, cz), Vector3(1.4, 0.24, 5.6), 0.05)
		g.col = Color(0.9, 0.7, 0.05)
		for z: float in [cz - 2.9, cz + 2.9]:
			for st in 4:
				g.col = Color(0.9, 0.7, 0.05) if st % 2 == 0 else Color(0.06, 0.06, 0.06)
				g.tube("painted_metal", [Vector3(ix, y + 0.24 + st * 0.22, z), Vector3(ix, y + 0.24 + (st + 1) * 0.22, z)], 0.09, 10, st == 3)
		for z: float in [cz - 1.2, cz + 1.2]:
			_pump(g, Vector3(ix, y + 0.24, z), bc)
		col.call(Vector3(ix, y + 1.0, cz), Vector3(1.4, 2.0, 5.6))
	# shop: 18 x 9 m, glazed front facing the road
	var sz := 22.0
	var sw := 18.0
	var sd := 8.5
	var sh := 4.0
	g.col = Color(0.82, 0.8, 0.76)
	g.box("plaster", Vector3(0, y + sh * 0.5, sz + sd * 0.5), Vector3(sw, sh, sd))
	g.col = Color(0.3, 0.31, 0.32)
	g.box("painted_metal", Vector3(0, y + sh + 0.45, sz + sd * 0.5), Vector3(sw + 0.4, 0.9, sd + 0.4), 0.04) # fascia/roof edge
	g.col = bc
	g.box("painted_metal", Vector3(0, y + sh + 0.3, sz - 0.19), Vector3(sw + 0.42, 0.18, 0.04))
	labels.append(["SHOP  ·  CAFÉ  ·  24 h", Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + sh + 0.62, sz - 0.23)), 300.0, 48, Color(0.95, 0.95, 0.92), true])
	# glazing: lit interior behind, glass, mullions
	g.col = Color(1, 1, 1)
	g.box("emit_dim", Vector3(0, y + 1.6, sz + 1.6), Vector3(sw - 1.2, 2.6, 0.05)) # back-lit shelves
	g.col = Color(0.45, 0.5, 0.52)
	g.box("glass", Vector3(0, y + 1.55, sz - 0.02), Vector3(sw - 1.0, 2.9, 0.04))
	g.col = Color(0.22, 0.22, 0.23)
	for k in 9:
		g.box("painted_metal", Vector3(-sw * 0.5 + 0.5 + k * (sw - 1.0) / 8.0, y + 1.55, sz - 0.05), Vector3(0.08, 2.9, 0.1))
	g.box("painted_metal", Vector3(0, y + 3.05, sz - 0.05), Vector3(sw - 1.0, 0.1, 0.12))
	g.box("painted_metal", Vector3(0, y + 0.1, sz - 0.05), Vector3(sw - 1.0, 0.2, 0.12))
	col.call(Vector3(0, y + sh * 0.5, sz + sd * 0.5), Vector3(sw, sh, sd))
	# shelves silhouettes inside
	g.col = Color(0.5, 0.45, 0.4)
	for k in 4:
		g.box("painted_metal", Vector3(-6.0 + k * 4.0, y + 0.8, sz + 3.2), Vector3(2.6, 1.6, 0.6))
	# price pylon near the road
	var px := -15.5
	g.col = Color(0.3, 0.31, 0.32)
	g.box("painted_metal", Vector3(px, y + 3.6, 3.0), Vector3(0.45, 7.2, 0.45), 0.03)
	g.col = Color(0.9, 0.9, 0.88)
	g.box("painted_metal", Vector3(px, y + 5.2, 3.0), Vector3(2.2, 4.4, 0.35), 0.04)
	g.col = bc
	g.box("painted_metal", Vector3(px, y + 6.75, 2.81), Vector3(2.1, 1.1, 0.04))
	g.col = Color(0.05, 0.05, 0.05)
	g.box("painted_metal", Vector3(px, y + 4.8, 2.81), Vector3(2.0, 2.6, 0.03))
	labels.append([brand, Transform3D(Basis(Vector3.UP, PI), Vector3(px, y + 6.75, 2.78)), 500.0, 44, Color(1, 1, 1), true])
	var prices := [["SUPER", "1.%02d9" % rng.randi_range(65, 95)], ["DIESEL", "1.%02d9" % rng.randi_range(55, 85)], ["LPG", "0.%02d9" % rng.randi_range(85, 99)]]
	for k in 3:
		var yy := y + 5.7 - k * 0.8
		labels.append([prices[k][0], Transform3D(Basis(Vector3.UP, PI), Vector3(px + 0.5, yy, 2.78)), 200.0, 26, Color(0.9, 0.9, 0.85), true])
		labels.append([prices[k][1], Transform3D(Basis(Vector3.UP, PI), Vector3(px - 0.45, yy, 2.78)), 250.0, 40, Color(1.6, 0.5, 0.1), true])
	col.call(Vector3(px, y + 3.6, 3.0), Vector3(0.6, 7.2, 0.6))
	# clutter: air post, propane cage, bins, aircon units on the roof
	g.col = Color(0.15, 0.3, 0.6)
	g.box("painted_metal", Vector3(9.5, y + 0.7, sz - 1.0), Vector3(0.4, 1.4, 0.3), 0.04)
	g.col = Color(0.6, 0.62, 0.62)
	g.box("steel", Vector3(-11.0, y + 0.9, sz - 0.8), Vector3(2.2, 1.8, 0.9), 0.02) # gas cage frame
	models["propane_tank"] = []
	models["exterior_aircon_unit"] = []
	models["metal_trash_can"] = []
	var ob := g.xf.basis.orthonormalized()
	for k in 6:
		models["propane_tank"].append(Transform3D(ob, g.xf * Vector3(-11.8 + (k % 3) * 0.6, y + 0.02, sz - 0.6 - floorf(k / 3.0) * 0.45)))
	for k in 2:
		models["exterior_aircon_unit"].append(Transform3D(ob, g.xf * Vector3(-4.0 + k * 6.0, y + sh + 0.9, sz + 5.0)))
	models["metal_trash_can"].append(Transform3D(ob * Basis(Vector3.UP, PI), g.xf * Vector3(sw * 0.5 + 1.6, y, sz + 6.0)))


static func _pump(g: GxGeo, p: Vector3, bc: Color) -> void:
	g.col = Color(0.88, 0.88, 0.86)
	g.box("painted_metal", p + Vector3(0, 0.95, 0), Vector3(0.5, 1.9, 0.9), 0.04)
	g.col = bc
	g.box("painted_metal", p + Vector3(0, 1.75, 0), Vector3(0.52, 0.3, 0.92), 0.02)
	g.col = Color(0.1, 0.1, 0.1)
	for s: float in [-1.0, 1.0]:
		g.box("painted_metal", p + Vector3(s * 0.26, 1.3, 0), Vector3(0.02, 0.35, 0.6)) # display bezel
		g.col = Color(1, 1, 1)
		g.box("emit_dim", p + Vector3(s * 0.27, 1.32, 0), Vector3(0.01, 0.2, 0.45))
		g.col = Color(0.08, 0.08, 0.08)
		for k in 3: # nozzles in holsters + hoses
			var z := -0.3 + k * 0.3
			g.box("painted_metal", p + Vector3(s * 0.28, 0.85, z), Vector3(0.06, 0.18, 0.08))
			g.tube("rubber", [p + Vector3(s * 0.3, 0.95, z), p + Vector3(s * 0.42, 0.6, z), p + Vector3(s * 0.32, 0.3, z), p + Vector3(s * 0.26, 0.5, z)], 0.015, 4, false)


# ------------------------------------------------------------------- diner
static func _diner(g: GxGeo, rng: RandomNumberGenerator, y: float, labels: Array, col: Callable, models: Dictionary, opts: Dictionary) -> void:
	var dname := str(opts.get("name", ["ROSIE'S", "DINER 66", "LUCKY STAR", "MOTOR CAFÉ"][rng.randi() % 4]))
	var bz := 12.0 # front face
	var bw := 20.0
	var bd := 10.0
	var bh := 4.2
	var red := Color(0.65, 0.07, 0.06)
	# body: brushed steel cladding with a red band, rounded-ish corners (chamfer)
	g.col = Color(0.85, 0.86, 0.87)
	g.box("steel", Vector3(0, y + bh * 0.5, bz + bd * 0.5), Vector3(bw, bh, bd), 0.6)
	g.col = red
	g.box("painted_metal", Vector3(0, y + 0.55, bz - 0.02), Vector3(bw - 1.0, 0.5, 0.06))
	g.box("painted_metal", Vector3(0, y + bh - 0.35, bz - 0.02), Vector3(bw - 1.0, 0.35, 0.06))
	# window band, lit interior, booths
	g.col = Color(1, 1, 1)
	g.box("emit_dim", Vector3(0, y + 2.0, bz + 1.5), Vector3(bw - 2.0, 2.0, 0.05))
	g.col = Color(0.45, 0.5, 0.52)
	g.box("glass", Vector3(0, y + 2.0, bz - 0.04), Vector3(bw - 1.6, 1.9, 0.04))
	g.col = Color(0.75, 0.76, 0.77)
	for k in 11:
		g.box("steel", Vector3(-bw * 0.5 + 0.8 + k * (bw - 1.6) / 10.0, y + 2.0, bz - 0.07), Vector3(0.07, 1.9, 0.08))
	g.col = red * 0.8
	for k in 5:
		g.box("canvas", Vector3(-7.0 + k * 3.5, y + 0.9, bz + 0.8), Vector3(1.6, 0.9, 0.5), 0.08) # booth backs
	col.call(Vector3(0, y + bh * 0.5, bz + bd * 0.5), Vector3(bw, bh, bd))
	# roof sign: frame + neon name + OPEN
	g.col = Color(0.12, 0.12, 0.13)
	g.box("painted_metal", Vector3(0, y + bh + 1.0, bz + 0.6), Vector3(9.0, 1.8, 0.25), 0.05)
	g.bar("steel", Vector3(-3.5, y + bh, bz + 0.8), Vector3(-3.5, y + bh + 0.2, bz + 0.8), 0.06)
	g.bar("steel", Vector3(3.5, y + bh, bz + 0.8), Vector3(3.5, y + bh + 0.2, bz + 0.8), 0.06)
	var neon := Color(2.6, 0.35, 0.3) if Car.night else Color(1.0, 0.25, 0.2)
	labels.append([dname, Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + bh + 1.05, bz + 0.46)), 500.0, 110, neon, true])
	labels.append(["OPEN", Transform3D(Basis(Vector3.UP, PI), Vector3(bw * 0.5 - 2.0, y + 2.6, bz - 0.09)), 150.0, 40, Color(0.4, 2.2, 2.4) if Car.night else Color(0.2, 0.8, 0.9), true])
	labels.append(["EAT · COFFEE · BURGERS", Transform3D(Basis(Vector3.UP, PI), Vector3(0, y + bh - 0.35, bz - 0.06)), 200.0, 30, Color(0.95, 0.92, 0.85)])
	# awning over the terrace: red/white stripes on a steel frame
	var az0 := bz - 5.0
	for k in 16:
		g.col = red if k % 2 == 0 else Color(0.9, 0.88, 0.82)
		var x := -bw * 0.5 + 0.6 + (k + 0.5) * (bw - 1.2) / 16.0
		var a := Vector3(x, y + 3.3, bz)
		var b := Vector3(x, y + 2.7, az0)
		g.beam("canvas", a, b, (bw - 1.2) / 16.0 + 0.01, 0.04)
	g.col = Color(0.3, 0.3, 0.3)
	for x: float in [-bw * 0.5 + 0.8, 0.0, bw * 0.5 - 0.8]:
		g.bar("steel", Vector3(x, y, az0 + 0.1), Vector3(x, y + 2.7, az0 + 0.1), 0.04)
	# terrace: tables, chairs, parasols at the ends
	for k in 5:
		var tx := -8.0 + k * 4.0
		var tz := bz - 2.6
		g.col = Color(0.75, 0.76, 0.77)
		g.lathe("steel", Vector3(tx, y, tz), PackedVector2Array([Vector2(0.3, 0.0), Vector2(0.05, 0.05), Vector2(0.04, 0.72), Vector2(0.4, 0.74), Vector2(0.4, 0.77), Vector2(0.01, 0.78)]), 12)
		for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var cp := Vector3(tx + cos(a + 0.3) * 0.65, y, tz + sin(a + 0.3) * 0.65)
			g.col = red * 0.9
			g.box("painted_metal", cp + Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42), 0.01, Basis(Vector3.UP, a))
			g.col = Color(0.2, 0.2, 0.2)
			g.bar("steel", cp, cp + Vector3(0, 0.45, 0), 0.02, 4)
	# lamp posts are added by place(); bins
	models["metal_trash_can"] = [Transform3D(g.xf.basis.orthonormalized(), g.xf * Vector3(bw * 0.5 + 2.0, y, bz + 7.0))]
	models["exterior_aircon_unit"] = [Transform3D(g.xf.basis.orthonormalized(), g.xf * Vector3(5.0, y + bh, bz + 6.0))]
