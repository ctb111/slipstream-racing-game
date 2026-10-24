class_name HarbourTheme
extends RefCounted
## "harbour" theme (Hafenstadt street circuit), built by TrackThemes with its
## batching helpers (everything merged per material and 320 m cell):
##  - continuous city blocks behind the barriers: brick Speicherstadt warehouses
##    in the east, concrete offices and glass towers along the motorway, plaster
##    apartments over neon-lit shops downtown and on the waterfront; facades are
##    plain boxes with the FacadeKit photo facades (windows lit at night);
##  - second-row blocks and a skyline of towers on every side (always drawn:
##    cheap boxes, so nothing pops in);
##  - the waterfront: paved promenade, quay wall, railing, bollards, trees in
##    planters, moored boats and a container ship, the harbour basin;
##  - the container port: walls of stacked containers, two rail-mounted gantry
##    cranes straddling the road, floodlight masts;
##  - the rail level crossing with lights, raised booms and a parked freight train;
##  - the elevated motorway: retaining walls where the road runs above the city;
##  - neon shop signs, rooftop signs, balconies with spectators.
## Gimmick pieces (drive-through warehouse, tunnel, flyover, gantries, graffiti,
## billboards, fans) are placed by dress_hafenstadt.gd at the SITES below, which
## the buildings keep clear of.

## World XZ points + radius kept free of buildings for the dressing's set pieces.
const SITES := [
	[Vector2(350, 190), 44.0], # drive-through warehouse (BC)
	[Vector2(-420, -150), 62.0], # tunnel (HI)
	[Vector2(-370, 120), 26.0], # flyover piers (KL)
	[Vector2(-300, 300), 20.0], # footbridge (waterfront)
]
## Container port: no city blocks, containers and cranes instead.
const PORT := Rect2(385, -170, 260, 300)
const PORT_RAIL_Z := -60.0 ## the railway crossing the road in the port (DE)
const NEON := ["HOTEL ATLANTIK", "BAR", "PIZZA", "IMBISS", "KAFFEE", "24 H", "SUSHI", "CLUB NOVA",
	"KIOSK", "DÖNER", "CASINO", "APOTHEKE", "SEEMANNSHEIM", "FISCH", "TATTOO", "KINO"]
const NEON_INK := [Color(1.0, 0.25, 0.55), Color(0.3, 0.85, 1.0), Color(1.0, 0.55, 0.12), Color(0.55, 1.0, 0.35),
	Color(1.0, 0.92, 0.5), Color(0.75, 0.4, 1.0), Color(1.0, 0.2, 0.15)]
const LIVERIES := [Color(0.62, 0.12, 0.08), Color(0.1, 0.24, 0.45), Color(0.15, 0.4, 0.3), Color(0.85, 0.55, 0.1),
	Color(0.55, 0.56, 0.56), Color(0.85, 0.85, 0.82), Color(0.35, 0.18, 0.1), Color(0.05, 0.35, 0.55), Color(0.7, 0.3, 0.1)]
const BRICK := [Color(0.95, 0.85, 0.8), Color(0.85, 0.75, 0.7), Color(1.0, 0.9, 0.82), Color(0.8, 0.7, 0.66)]
const CONC := [Color(0.85, 0.85, 0.83), Color(0.75, 0.75, 0.74), Color(0.9, 0.88, 0.82), Color(0.66, 0.68, 0.7)]
const PLASTER := [Color(0.92, 0.88, 0.8), Color(0.85, 0.78, 0.66), Color(0.78, 0.82, 0.84), Color(0.9, 0.8, 0.72),
	Color(0.7, 0.74, 0.7), Color(0.95, 0.93, 0.9), Color(0.82, 0.7, 0.62)]

var t: TrackThemes
var body: StaticBody3D
var quay := 1e9
var night := false
var _neon_uv := []
var _balcony_people := 0 ## capped (PeopleKit crowds cost CPU)


static func build(themes: TrackThemes) -> void:
	var h := HarbourTheme.new()
	h.t = themes
	h._run()


func _run() -> void:
	quay = float(t.def.get("quay_z", 1e9))
	night = float(t.preset.get("night", 0.0)) > 0.0
	body = StaticBody3D.new()
	body.name = "HarbourColliders"
	t.parent.add_child(body)
	_materials()
	# The set-piece sites (gimmicks come later): occupy them so no block lands there.
	for s: Array in SITES:
		var p: Vector2 = s[0]
		var r: float = s[1]
		t._mark(Vector3(p.x, 0, p.y), Vector3.RIGHT, Vector3.BACK, r * 2.0, r * 2.0)
	_pavements()
	_catch_fence()
	_retaining_walls()
	_waterfront()
	_port()
	_rail_crossing()
	for side: float in [-1.0, 1.0]:
		_frontage(side)
	_second_row()
	_skyline()
	_city_ground()
	_street_trees()
	_crossings()
	# No forest in the city (street trees are placed above).
	var bb := AABB(t.centers[0], Vector3.ZERO)
	for c in t.centers:
		bb = bb.expand(c)
	t.no_trees.append([bb.get_center(), maxf(bb.size.x, bb.size.z) * 0.5 + 700.0])


func _materials() -> void:
	# Real photo facades (FacadeKit: ambientCG brick block, photo windows,
	# doors and shopfronts; lit windows from the photo glass mask at night).
	var wet := float(t.preset.get("wet", 0.0))
	t.mats.city = FacadeKit.material(FacadeKit.NORTH, 0.8 if night else (0.3 if wet > 0.5 else 0.0), wet * 0.6)
	t.mats.roof = Mats.mat("concrete_tint", Color(0.42, 0.42, 0.42))
	t.mats.conc = Mats.mat("concrete")
	t.mats.box = Mats.mat("corrugated") # containers: vertex colour livery
	t.mats.steel = Mats.mat("painted_metal")
	t.mats.rail = Mats.mat("steel")
	t.mats.pave = Mats.mat("concrete_tint", Color(0.62, 0.61, 0.6))
	t.mats.asphalt = Mats.mat("concrete_tint", Color(0.3, 0.3, 0.31))
	var fence: StandardMaterial3D = (GxProps.material("fence_wire") as StandardMaterial3D).duplicate()
	fence.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF # lap-long fence: plain scissor is cheaper
	t.mats.fence = fence
	# Shop light spilling onto the pavement (additive, fades away from the glass).
	var spill := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;\nuniform float strength = 0.0;\nvoid fragment() {\n\tfloat e = 1.0 - smoothstep(0.0, 1.0, UV.y);\n\tfloat s = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);\n\tALBEDO = COLOR.rgb * strength * e * e * s;\n}\n"
	spill.shader = ssh
	spill.set_shader_parameter("strength", 0.55 if night else 0.0)
	t.mats.spill = spill
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.86, 0.86, 0.82)
	paint.roughness = 0.6
	t.mats.paint = paint
	t.mats.glass = Mats.mat("glass", Color.WHITE, false)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.02, 0.045, 0.05)
	water.roughness = 0.06
	water.metallic_specular = 0.7
	water.normal_enabled = true
	var wn := NoiseTexture2D.new()
	wn.as_normal_map = true
	wn.bump_strength = 3.0
	wn.seamless = true
	var nz := FastNoiseLite.new()
	nz.frequency = 0.05
	wn.noise = nz
	water.normal_texture = wn
	water.uv1_scale = Vector3(60, 60, 60)
	t.mats.water = water
	# Neon: an atlas of glowing tube lettering on dark backing boards.
	var entries := []
	_neon_uv = []
	for k in NEON.size():
		var col := k % 4
		var row := k / 4
		var r := Rect2(col * 512, row * 128, 512, 128)
		var ink: Color = NEON_INK[k % NEON_INK.size()]
		entries.append(["neon%d" % k, r, Color(0.03, 0.03, 0.035), ink, NEON[k], 70 if NEON[k].length() < 10 else 52, ink.darkened(0.35)])
	var atlas := t._atlas(entries)
	for k in NEON.size():
		_neon_uv.append(t.uv["neon%d" % k])
	var neon := StandardMaterial3D.new()
	neon.albedo_texture = atlas
	neon.emission_enabled = true
	neon.emission_texture = atlas
	neon.emission_energy_multiplier = 3.2 if night else 0.5
	neon.roughness = 0.4
	neon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	t.mats.sign = neon
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.85, 0.6)
	glow.emission_energy_multiplier = 4.0 if night else 0.3
	t.mats.glow = glow
	var blink := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded;\nvoid fragment() {\n\tfloat on = step(0.5, fract(TIME * 0.85 + UV2.x * 0.5));\n\tALBEDO = COLOR.rgb * mix(0.08, 3.0, on);\n}\n"
	blink.shader = sh
	t.mats.blink = blink
	t.vis.merge({city = 0.0, roof = 0.0, conc = 1200.0, box = 0.0, steel = 0.0, rail = 600.0, pave = 0.0,
		asphalt = 0.0, fence = 500.0, paint = 450.0, glass = 600.0, spill = 300.0, water = 0.0, sign = 0.0, glow = 0.0, blink = 900.0}, true)


# ---------------------------------------------------------------- helpers

func _in_port(p: Vector3) -> bool:
	return PORT.has_point(Vector2(p.x, p.z))


func _sea(p: Vector3) -> bool:
	return p.z > quay - 2.0


func _zone(p: Vector3) -> String:
	if p.z > 230.0:
		return "front"
	if p.x > 250.0:
		return "brick"
	if p.z < -190.0:
		return "office"
	return "down"


## A city block: four facade walls (style, variant) and a flat roof.
func _block(c: Vector3, ax: Vector3, az: Vector3, w: float, d: float, h: float, style: int, col: Color, street: float) -> void:
	var variant := t.rng.randi() % 10
	var y0 := street - 1.5
	var y1 := street + h
	var faces := [[c - az * d * 0.5, -az, w], [c + az * d * 0.5, az, w], [c + ax * w * 0.5, ax, d], [c - ax * w * 0.5, -ax, d]]
	# Internal styles (0 brick, 1 office, 2 tower, 3 apartments over shops) to FacadeKit styles.
	# BLOCK (tiled brick photo) only for the brick warehouses near the street; its window
	# grid reads blotchy at night from afar, so towers and offices use TOWN photo windows.
	var kit := FacadeKit.BLOCK if style == 0 and h < 26.0 else FacadeKit.TOWN # brick warehouses: tiled photo block
	for k in faces.size():
		var f: Array = faces[k]
		var fw: float = f[2]
		var fs := FacadeKit.SHOP if style == 3 and k == 0 else kit
		t._wall("city", f[0], f[1], fw, y0, y1, street, col, Vector2(fw + 1000.0 * fs, minf(h, 99.0) + 100.0 * variant))
	var hx := ax * w * 0.5
	var hz := az * d * 0.5
	var top := Vector3(c.x, y1, c.z)
	t._quad("roof", top - hx - hz, top + hx - hz, top + hx + hz, top - hx + hz, Color.WHITE, Vector3.UP)
	# Rooftop plant: a lift house / AC box on the bigger roofs.
	if w * d > 220.0 and t.rng.randf() < 0.6:
		var rp := top + ax * t.rng.randf_range(-0.25, 0.25) * w + az * t.rng.randf_range(0.0, 0.25) * d + Vector3.UP * 1.3
		t._box("conc", rp, ax, Vector3.UP, az, Vector3(t.rng.randf_range(3.0, 6.0), 2.6, t.rng.randf_range(3.0, 5.0)), Color(0.8, 0.8, 0.78))
	# Engine-echo footprints only for blocks on the street (audio scans these).
	if t._tdist(c, 40.0) < 32.0:
		var boxes: Array = t.parent.get_meta("sound_boxes", [])
		boxes.append([c, ax, az, w, d])
		t.parent.set_meta("sound_boxes", boxes)
	t._mark(c, ax, az, w, d)


func _neon(c: Vector3, out: Vector3, w: float, h: float) -> void:
	var k := t.rng.randi() % _neon_uv.size()
	t._sign(c, out, w, h, _neon_uv[k])


# ---------------------------------------------------------------- street level

## Paved pavements from the road edge to the building line (13 m from the
## centreline), holding points on the inside of tight corners.
func _pavements() -> void:
	for side: float in [-1.0, 1.0]:
		var prev_in := Vector3.ZERO
		var prev_out := Vector3.ZERO
		for k in t.n + 1:
			var i := t._i(k)
			var a := t._on_ground(t.centers[i] + t.rights[i] * side * (t.half + 1.15), 0.07)
			var b := t._on_ground(t.centers[i] + t.rights[i] * side * 13.0, 0.07)
			b.y = a.y
			if k > 0:
				var tn := t.tangents[i]
				if Vector2(b.x - prev_out.x, b.z - prev_out.z).dot(Vector2(tn.x, tn.z)) < 0.05:
					b = Vector3(prev_out.x, b.y, prev_out.z)
				t._quad("pave", prev_in, a, b, prev_out, Color(0.8, 0.79, 0.77), Vector3.UP)
			prev_in = a
			prev_out = b


## Debris fence on top of the barriers (street-circuit style): galvanised
## posts every 4 m leaning slightly in, chain-link panels from 1.0 to 3.6 m.
func _catch_fence() -> void:
	for side: float in [-1.0, 1.0]:
		var prev := Vector3.INF
		var since := 99.0
		for k in t.n + 1:
			var i := t._i(k)
			var lat := t.rail_dist(i, side) + 0.45
			var p := t.centers[i] + t.rights[i] * side * lat
			p.y = t._ground(p)
			var skip := false
			for s: Array in SITES:
				var sp: Vector2 = s[0]
				if Vector2(p.x, p.z).distance_to(sp) < float(s[1]) * 0.7:
					skip = true
			if skip:
				prev = Vector3.INF
				continue
			since += TrackThemes.STEP
			if since >= 4.0:
				since = 0.0
				t._box("steel", p + Vector3.UP * 2.3, t.tangents[i], Vector3.UP, t.rights[i], Vector3(0.08, 2.7, 0.08), Color(0.7, 0.72, 0.72))
			if prev != Vector3.INF:
				var out := t.rights[i] * side
				t._quad("fence", prev + Vector3.UP * 1.0, p + Vector3.UP * 1.0, p + Vector3.UP * 3.6, prev + Vector3.UP * 3.6, Color.WHITE, -out)
				t._box("steel", (prev + p) * 0.5 + Vector3.UP * 3.62, (p - prev).normalized(), Vector3.UP, out, Vector3(prev.distance_to(p), 0.05, 0.05), Color(0.7, 0.72, 0.72))
			prev = p


## Where the road runs above the city (the motorway), concrete retaining walls
## drop from the pavement edge to the street below.
func _retaining_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var prev := Vector3.INF
		for k in t.n + 1:
			var i := t._i(k)
			var y := t.centers[i].y
			var p := t.centers[i] + t.rights[i] * side * 13.0
			if y < 0.8:
				prev = Vector3.INF
				continue
			if prev != Vector3.INF:
				var out := t.rights[i] * side
				var a := Vector3(prev.x, -0.5, prev.z)
				var b := Vector3(p.x, -0.5, p.z)
				t._quad("conc", a, b, Vector3(p.x, y, p.z), Vector3(prev.x, prev.y, prev.z), Color(0.82, 0.82, 0.8), out)
				# Coping lip
				var lift := Vector3.UP * 0.25
				t._quad("conc", Vector3(prev.x, prev.y, prev.z) + lift, Vector3(p.x, y, p.z) + lift,
					Vector3(p.x, y, p.z) + lift + out * 0.4, Vector3(prev.x, prev.y, prev.z) + lift + out * 0.4, Color(0.75, 0.75, 0.73), Vector3.UP)
			prev = Vector3(p.x, y, p.z)
			# Street lamps of the road below, their heads level with the deck.
			if y > 3.0 and k % 15 == 0:
				var lp := t.centers[i] + t.rights[i] * side * 18.5
				lp.y = 0.0
				var lh := y + 0.2
				t._cyl("steel", lp, 0.12, 0.08, lh, 6, Color(0.2, 0.21, 0.22))
				t._box("steel", lp + Vector3.UP * lh - t.rights[i] * side * 0.9, t.rights[i], Vector3.UP, t.tangents[i], Vector3(1.9, 0.1, 0.12), Color(0.2, 0.21, 0.22))
				t._box("glow", lp + Vector3.UP * (lh - 0.12) - t.rights[i] * side * 1.7, t.rights[i], Vector3.UP, t.tangents[i], Vector3(0.6, 0.12, 0.3), Color(1.0, 0.6, 0.25))


## Rows of city blocks along the street, just behind the pavement.
func _frontage(side: float) -> void:
	var i := 0
	var misses := 0
	while i < t.n:
		var zone := _zone(t.centers[i])
		var w := t.rng.randf_range(11.0, 24.0) if zone != "brick" else t.rng.randf_range(18.0, 34.0)
		var dep := t.rng.randf_range(14.0, 22.0)
		var mid := t._i(i + int(w * 0.5 / TrackThemes.STEP))
		var az := t.rights[mid] * side
		var ax := t.tangents[mid]
		var front := 13.4
		if t.centers[mid].y > 2.0: # on the motorway: the city stands back, below the road
			front = 24.0 + t.rng.randf_range(0.0, 8.0)
		var c := t.centers[mid] + az * (front + dep * 0.5)
		var street := 0.0
		c.y = street
		if not _sea(c + az * dep * 0.5) and not _in_port(c) and t._fits(c, ax, az, w, dep, 1.0):
			var style := 3
			var col: Color = PLASTER[t.rng.randi() % PLASTER.size()]
			var h := t.rng.randf_range(12.0, 22.0)
			match zone:
				"brick":
					style = 0
					col = BRICK[t.rng.randi() % BRICK.size()]
					h = t.rng.randf_range(14.0, 22.0)
				"office":
					style = 1 if t.rng.randf() < 0.6 else 2
					col = CONC[t.rng.randi() % CONC.size()]
					h = t.rng.randf_range(18.0, 34.0)
				"down":
					var r := t.rng.randf()
					style = 3 if r < 0.55 else (1 if r < 0.8 else 0)
					col = PLASTER[t.rng.randi() % PLASTER.size()] if style == 3 else (CONC[t.rng.randi() % CONC.size()] if style == 1 else BRICK[t.rng.randi() % BRICK.size()])
					h = t.rng.randf_range(13.0, 28.0)
				"front":
					style = 3 if t.rng.randf() < 0.7 else 0
					col = PLASTER[t.rng.randi() % PLASTER.size()] if style == 3 else BRICK[t.rng.randi() % BRICK.size()]
					h = t.rng.randf_range(11.0, 19.0)
			if t.rng.randf() < 0.08 and zone != "front":
				style = 2
				col = CONC[t.rng.randi() % CONC.size()]
				h = t.rng.randf_range(40.0, 70.0)
			_block(c, ax, az, w, dep, h, style, col, street)
			var fc := c - az * (dep * 0.5 + 0.12)
			# Neon over the shops; blade-free (flat fascia signs).
			if style != 2 and t.rng.randf() < (0.75 if zone == "down" or zone == "front" else 0.3):
				var sw := minf(w * 0.55, 7.5)
				_neon(Vector3(fc.x, street + 3.95, fc.z) + ax * t.rng.randf_range(-0.2, 0.2) * w, -az, sw, sw * 0.25)
			# Warm shop light on the pavement in front of the shopfronts.
			if style == 3 and night and front < 14.0:
				var sy := t._ground(fc) + 0.1
				var a0 := Vector3(fc.x, sy, fc.z) - ax * w * 0.45
				var a1 := Vector3(fc.x, sy, fc.z) + ax * w * 0.45
				var col2 := Color(1.0, 0.7, 0.42) if t.rng.randf() < 0.75 else Color(0.75, 0.85, 1.0)
				t._quad("spill", a0, a1, a1 - az * 4.5, a0 - az * 4.5, col2, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			# Projecting blade sign facing the approaching traffic (and one facing away).
			if (zone == "down" or zone == "front") and style != 2 and t.rng.randf() < 0.4:
				var bc := Vector3(fc.x, street + t.rng.randf_range(5.0, 8.0), fc.z) - az * 1.3 + ax * t.rng.randf_range(-0.35, 0.35) * w
				_neon(bc - ax * 0.03, -ax, 2.6, 0.65)
				_neon(bc + ax * 0.03, ax, 2.6, 0.65)
				t._box("steel", bc + az * 0.75 + Vector3.UP * 0.4, az, Vector3.UP, ax, Vector3(1.4, 0.05, 0.05), Color(0.15, 0.15, 0.15))
			# Balconies with spectators on the apartment blocks.
			if style == 3 or (style == 0 and t.rng.randf() < 0.3):
				_balconies(fc, ax, az, w, street, h)
			# A big rooftop sign facing the street now and then.
			if h < 26.0 and t.rng.randf() < 0.14:
				var sw2 := minf(w * 0.8, 14.0)
				var top := Vector3(fc.x, street + h + 0.4 + sw2 * 0.125, fc.z) + az * 1.2
				_neon(top, -az, sw2, sw2 * 0.25)
				for s: float in [-0.35, 0.35]:
					t._box("steel", top + ax * s * sw2 + az * 0.15 - Vector3.UP * sw2 * 0.06, ax, Vector3.UP, az, Vector3(0.15, sw2 * 0.25 + 0.8, 0.15), Color(0.2, 0.2, 0.2))
			i += int(ceil(w / TrackThemes.STEP))
			misses = 0
		else:
			i += 1
			misses += 1
			# Gap (tight corner, set piece): a concrete yard wall closes it.
			var wp := t.centers[t._i(i)] + t.rights[t._i(i)] * side * 13.6
			if misses % 3 == 0 and not _sea(wp) and not _in_port(wp) and t._off_track(wp, 0.2) and not t._occ.has(t._okey(wp)):
				wp.y = 1.6
				t._hbox("conc", wp, t.tangents[t._i(i)], Vector3(0.35, 3.2, 6.4), Color(0.7, 0.7, 0.68))


func _balconies(fc: Vector3, ax: Vector3, az: Vector3, w: float, street: float, h: float) -> void:
	var floors := int((h - 4.4) / 3.1)
	var bays := int(w / 2.8)
	if bays < 2 or floors < 1:
		return
	var bay_w := w / bays
	for fl in mini(floors, 5):
		var y := street + 4.4 + fl * 3.1 + 0.75
		for b in bays:
			if (b + fl) % 3 != 0 or t.rng.randf() < 0.3:
				continue
			var bc := fc + ax * ((b + 0.5) * bay_w - w * 0.5) - az * 0.6
			bc.y = y
			t._box("conc", bc, ax, Vector3.UP, az, Vector3(bay_w * 0.85, 0.18, 1.2), Color(0.85, 0.85, 0.83), false)
			# Railing front (solid glass-look panel in steel colour)
			t._box("steel", bc - az * 0.58 + Vector3.UP * 0.55, ax, Vector3.UP, az, Vector3(bay_w * 0.85, 0.06, 0.06), Color(0.15, 0.15, 0.16))
			t._box("steel", bc - az * 0.58 + Vector3.UP * 0.28, ax, Vector3.UP, az, Vector3(bay_w * 0.85, 0.5, 0.02), Color(0.25, 0.27, 0.28))
			if fl < 4 and t.rng.randf() < 0.75 and _balcony_people < 160:
				var people := 1 + int(t.rng.randf() < 0.5)
				for k in people:
					var pp := bc + ax * (k - 0.5 * (people - 1)) * 0.8 + az * 0.1 + Vector3.UP * 0.09
					t._person(Transform3D(Basis.looking_at(-az, Vector3.UP), pp), PeopleKit.Role.SPECTATOR)
					_balcony_people += 1


## Blocks behind the street fronts, taller further out.
func _second_row() -> void:
	var bb := AABB(t.centers[0], Vector3.ZERO)
	for c in t.centers:
		bb = bb.expand(c)
	bb = bb.grow(150.0)
	var step := 24.0
	var x := bb.position.x
	while x < bb.end.x:
		var z := bb.position.z
		while z < bb.end.z:
			var p := Vector3(x + t.rng.randf_range(-3, 3), 0, z + t.rng.randf_range(-3, 3))
			z += step
			if _sea(p + Vector3(0, 0, 14)) or _in_port(p):
				continue
			var d := t._tdist(p, 160.0)
			if d < 30.0:
				continue
			var i := t._nearest(p, 160.0)
			var az := t.rights[i] if i >= 0 else Vector3.BACK
			if i >= 0 and (p - t.centers[i]).dot(az) < 0.0:
				az = -az
			var ax := Vector3.UP.cross(az).normalized()
			var w := t.rng.randf_range(16.0, 26.0)
			var dep := t.rng.randf_range(16.0, 24.0)
			if not t._fits(p, ax, az, w, dep, 3.0):
				continue
			var zone := _zone(p)
			var far := clampf((d - 30.0) / 130.0, 0.0, 1.0)
			var style := 1
			var col: Color = CONC[t.rng.randi() % CONC.size()]
			if zone == "brick" and t.rng.randf() < 0.7:
				style = 0
				col = BRICK[t.rng.randi() % BRICK.size()]
			elif t.rng.randf() < 0.45:
				style = 3
				col = PLASTER[t.rng.randi() % PLASTER.size()]
			var h := t.rng.randf_range(16.0, 30.0) + far * t.rng.randf_range(0.0, 24.0)
			if t.rng.randf() < 0.12 + far * 0.15:
				style = 2
				h = t.rng.randf_range(40.0, 85.0)
			_block(p, ax, az, w, dep, h, style, col, 0.0)
		x += step


## Distant towers all round, so the horizon is city, not hills.
func _skyline() -> void:
	var bb := AABB(t.centers[0], Vector3.ZERO)
	for c in t.centers:
		bb = bb.expand(c)
	var ctr := bb.get_center()
	var rx := bb.size.x * 0.5 + 230.0
	var rz := bb.size.z * 0.5 + 230.0
	for k in 70:
		var a := TAU * k / 70.0 + t.rng.randf_range(-0.03, 0.03)
		var sc := t.rng.randf_range(1.0, 1.35)
		var p := ctr + Vector3(cos(a) * rx * sc, 0, sin(a) * rz * sc)
		if _sea(p):
			continue
		var w := t.rng.randf_range(22.0, 40.0)
		var dep := t.rng.randf_range(22.0, 40.0)
		var ax := Vector3(cos(a + 1.3), 0, sin(a + 1.3))
		var az := Vector3.UP.cross(ax).normalized()
		if t._occ.has(t._okey(p)):
			continue
		_block(p, ax, az, w, dep, t.rng.randf_range(35.0, 95.0), 2 if t.rng.randf() < 0.6 else 1, CONC[t.rng.randi() % CONC.size()], 0.0)
		if t.rng.randf() < 0.5:
			# Red aviation light on top
			t._box("glow", p + Vector3.UP * 96.0, ax, Vector3.UP, az, Vector3(0.6, 0.6, 0.6), Color(1.0, 0.1, 0.05))


## Asphalt / paving over the whole city (no grass in town).
func _city_ground() -> void:
	var bb := AABB(t.centers[0], Vector3.ZERO)
	for c in t.centers:
		bb = bb.expand(c)
	bb = bb.grow(420.0)
	var cell := 12.0
	var x := bb.position.x
	while x < bb.end.x:
		var z := bb.position.z
		while z < bb.end.z:
			var c := Vector3(x + cell * 0.5, 0, z + cell * 0.5)
			z += cell
			if c.z + cell * 0.5 > quay:
				continue
			if t._tdist(c, 20.0) < 15.0:
				continue
			var y := 0.03
			var col := Color(0.85, 0.85, 0.85) if int(floor(c.x / 48.0) + floor(c.z / 48.0)) % 3 != 0 else Color(1.1, 1.1, 1.08)
			var h := cell * 0.5
			t._quad("asphalt", Vector3(c.x - h, y, c.z - h), Vector3(c.x + h, y, c.z - h), Vector3(c.x + h, y, c.z + h), Vector3(c.x - h, y, c.z + h), col, Vector3.UP)
		x += cell


func _street_trees() -> void:
	var garden := t._tree_mesh(2.4, 5.0, 2.0, [Color(0.1, 0.18, 0.08), Color(0.26, 0.38, 0.14)], 0.35, 0.1, 10)
	t._tree_set("street_tree", "maple_0", false, 600.0, garden)
	# Waterfront: an avenue between the barrier and the quay.
	var x := -560.0
	while x < 600.0:
		var p := Vector3(x, 0.0, quay - 5.0)
		x += 16.0
		if not t._off_track(p, 1.0) or t._occ.has(t._okey(p)):
			continue
		p.y = t._ground(p) + 0.1
		var s := t.rng.randf_range(0.85, 1.15)
		t._mm_add("street_tree", Transform3D(Basis(Vector3.UP, t.rng.randf() * TAU).scaled(Vector3(s, s, s)), p))
		t._box("conc", p + Vector3.UP * 0.25, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1.8, 0.5, 1.8), Color(0.7, 0.7, 0.68))


# ---------------------------------------------------------------- street furniture

## Zebra crossings with traffic lights (flashing amber: the streets are closed
## for the race) every ~170 m on the city straights, a bus shelter at some.
func _crossings() -> void:
	var since := 0.0
	var k := 0
	for i in t.n:
		since += TrackThemes.STEP
		var c := t.centers[i]
		if since < 170.0 or absf(t.corner[i]) > 0.08 or _in_port(c) or c.y > 1.0:
			continue
		var near_site := false
		for s: Array in SITES:
			if Vector2(c.x, c.z).distance_to(s[0]) < float(s[1]) + 20.0:
				near_site = true
		if near_site or t._i(i) < 40:
			continue
		since = 0.0
		k += 1
		var ax := t.tangents[i]
		var az := t.rights[i]
		# Stripes: 0.5 m wide, 3 m long, 0.5 m apart, across the whole road.
		var y := c.y + 0.036
		var x := -t.half + 0.5
		while x < t.half - 0.3:
			var m := Vector3(c.x, y, c.z) + az * (x + 0.25)
			var hx := ax * 1.5
			var hz := az * 0.25
			t._quad("paint", m - hx - hz, m + hx - hz, m + hx + hz, m - hx + hz, Color.WHITE, Vector3.UP)
			x += 1.0
		# Stop lines
		for d: float in [-1.0, 1.0]:
			var m := Vector3(c.x, y, c.z) + ax * d * 4.5
			t._quad("paint", m - az * t.half - ax * 0.2, m + az * t.half - ax * 0.2, m + az * t.half + ax * 0.2, m - az * t.half + ax * 0.2, Color.WHITE, Vector3.UP)
		for side: float in [-1.0, 1.0]:
			var base := c + az * side * (t.rail_dist(i, side) + 1.1) - ax * side * 2.5
			base.y = t._ground(base)
			t._cyl("steel", base, 0.07, 0.06, 3.4, 6, Color(0.15, 0.16, 0.17))
			var face := -ax * side if side > 0.0 else ax # towards the approaching cars on that side
			var hp := base + Vector3.UP * 3.0 - az * side * 0.05
			t._box("steel", hp, Vector3.UP.cross(face).normalized(), Vector3.UP, face, Vector3(0.32, 0.95, 0.25), Color(0.08, 0.08, 0.08))
			t._box("blink", hp + face * 0.14, Vector3.UP.cross(face).normalized(), Vector3.UP, face, Vector3(0.18, 0.18, 0.04), Color(1.0, 0.55, 0.05))
			# Bus shelter on one side at every other crossing.
			if k % 2 == 0 and side > 0.0:
				var sc := c + az * side * 12.3 + ax * 9.0
				sc.y = t._ground(sc)
				var sx := ax
				var sz := az * side
				t._box("steel", sc + Vector3.UP * 2.45, sx, Vector3.UP, sz, Vector3(4.6, 0.12, 1.7), Color(0.2, 0.22, 0.24))
				t._box("glass", sc + Vector3.UP * 1.2 + sz * 0.75, sx, Vector3.UP, sz, Vector3(4.4, 2.3, 0.04), Color(0.7, 0.75, 0.78))
				for e: float in [-1.0, 1.0]:
					t._box("steel", sc + sx * e * 2.25 + Vector3.UP * 1.2, sx, Vector3.UP, sz, Vector3(0.08, 2.4, 1.6), Color(0.2, 0.22, 0.24))
				_neon(sc + sx * 2.32 + Vector3.UP * 1.3, sx, 1.4, 1.6) # lit poster panel
				t._box("steel", sc + Vector3.UP * 0.45 + sz * 0.4, sx, Vector3.UP, sz, Vector3(3.0, 0.08, 0.4), Color(0.3, 0.3, 0.3))


# ---------------------------------------------------------------- waterfront

func _waterfront() -> void:
	if quay > 1e8:
		return
	var x0 := -900.0
	var x1 := 950.0
	# Promenade paving from the pavement to the quay edge.
	var z0 := 313.0
	var seg := 20.0
	var x := x0
	while x < x1:
		var a := Vector3(x, 0.08, z0)
		var b := Vector3(x + seg, 0.08, z0)
		t._quad("pave", a, b, Vector3(b.x, 0.08, quay), Vector3(a.x, 0.08, quay), Color(0.72, 0.68, 0.62), Vector3.UP)
		# Quay wall (dark wet concrete) and granite coping.
		t._quad("conc", Vector3(a.x, -7.0, quay), Vector3(b.x, -7.0, quay), Vector3(b.x, 0.08, quay), Vector3(a.x, 0.08, quay), Color(0.42, 0.42, 0.41), Vector3.BACK)
		t._box("conc", Vector3(a.x + seg * 0.5, 0.15, quay - 0.4), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(seg, 0.18, 0.8), Color(0.72, 0.7, 0.68))
		x += seg
	# Railing: posts and two rails.
	x = x0
	while x < x1:
		t._box("steel", Vector3(x, 0.6, quay - 0.6), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.06, 1.05, 0.06), Color(0.12, 0.2, 0.22))
		x += 2.5
	for y: float in [1.1, 0.6]:
		t._box("steel", Vector3((x0 + x1) * 0.5, y, quay - 0.6), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(x1 - x0, 0.05, 0.05), Color(0.12, 0.2, 0.22))
	var shape := BoxShape3D.new()
	shape.size = Vector3(x1 - x0, 2.0, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3((x0 + x1) * 0.5, 1.0, quay - 0.5)
	body.add_child(cs)
	# The basin.
	var y := -1.1
	var w0 := -1800.0
	var w1 := 1800.0
	var zf := quay + 1600.0
	t._quad("water", Vector3(w0, y, quay), Vector3(w1, y, quay), Vector3(w1, y, zf), Vector3(w0, y, zf), Color.WHITE, Vector3.UP)
	# Moored boats along the quay, a container ship further out, a breakwater light.
	x = -600.0
	while x < 600.0:
		if t.rng.randf() < 0.55:
			var l := t.rng.randf_range(7.0, 14.0)
			t._boat(Vector3(x, y + 0.1, quay + l * 0.22 + 1.5), Vector3.RIGHT, l, t.rng.randf() < 0.3)
		x += t.rng.randf_range(14.0, 26.0)
	_ship(Vector3(-120, y, quay + 70.0), 190.0)
	_ship(Vector3(420, y, quay + 160.0), 230.0)
	# Quay lamps: tall harbour lanterns with glowing heads (emissive only; the
	# road lamps light the promenade).
	x = -560.0
	while x < 600.0:
		var lp := Vector3(x, 0.0, quay - 1.6)
		t._cyl("steel", lp, 0.09, 0.06, 5.2, 6, Color(0.1, 0.16, 0.18))
		t._box("steel", lp + Vector3(0, 5.25, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.5, 0.12, 0.5), Color(0.1, 0.16, 0.18))
		t._box("glow", lp + Vector3(0, 4.95, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.36, 0.5, 0.36), Color(1.0, 0.78, 0.5))
		x += 22.0
	for k in 14:
		var bp := Vector3(-520.0 + k * 75.0, 0.4, quay - 1.4)
		t._box("steel", bp, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.45, 0.65, 0.45), Color(0.08, 0.08, 0.08))


## A container ship: hull, bridge superstructure, deck stacks.
func _ship(at: Vector3, length: float) -> void:
	var beam := length * 0.15
	var hull_col: Color = [Color(0.12, 0.13, 0.15), Color(0.45, 0.08, 0.06), Color(0.08, 0.16, 0.3)][t.rng.randi() % 3]
	t._box("steel", at + Vector3(0, 4.0, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(length, 12.0, beam), hull_col)
	t._box("steel", at + Vector3(0, -1.6, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(length + 0.2, 1.4, beam + 0.2), Color(0.45, 0.1, 0.08))
	# Bow taper
	var bow := at + Vector3(length * 0.5, 0, 0)
	t._quad("steel", bow + Vector3(0, -2, -beam * 0.5), bow + Vector3(beam * 0.9, -2, 0), bow + Vector3(beam * 0.9, 10, 0), bow + Vector3(0, 10, -beam * 0.5), hull_col, Vector3(1, 0, -1).normalized())
	t._quad("steel", bow + Vector3(0, -2, beam * 0.5), bow + Vector3(beam * 0.9, -2, 0), bow + Vector3(beam * 0.9, 10, 0), bow + Vector3(0, 10, beam * 0.5), hull_col, Vector3(1, 0, 1).normalized())
	var bridge := at + Vector3(-length * 0.38, 10.0 + 9.0, 0)
	t._box("conc", bridge, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(14.0, 18.0, beam * 0.9), Color(0.92, 0.92, 0.9))
	t._box("glow", bridge + Vector3(-7.05, 6.5, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.1, 1.2, beam * 0.8), Color(0.9, 0.85, 0.6))
	var x := -length * 0.3
	while x < length * 0.42:
		for row in int(beam / 2.6) - 1:
			var hgt := t.rng.randi_range(2, 6)
			for lv in hgt:
				var cp := at + Vector3(x, 10.0 + 1.3 + lv * 2.6, -beam * 0.5 + 2.6 + row * 2.6)
				t._box("box", cp, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(12.0, 2.55, 2.4), LIVERIES[t.rng.randi() % LIVERIES.size()])
		x += 12.6


# ---------------------------------------------------------------- container port

func _container(p: Vector3, ax: Vector3, col: Color) -> void:
	var az := Vector3.UP.cross(ax).normalized()
	t._box("box", p + Vector3.UP * 1.29, ax, Vector3.UP, az, Vector3(12.19, 2.58, 2.44), col)


func _port() -> void:
	var i0 := t._nearest(Vector3(PORT.position.x, 0, 80.0), 60.0)
	if i0 < 0:
		return
	# Walls of stacked containers along both sides of the port road (CD and DE).
	for k in t.n:
		if k % 7 != 0:
			continue
		var c := t.centers[k]
		if not _in_port(c) and not _in_port(c + t.rights[k] * 30.0) and not _in_port(c - t.rights[k] * 30.0):
			continue
		if absf(c.z - PORT_RAIL_Z) < 16.0: # the railway
			continue
		for side: float in [-1.0, 1.0]:
			for row in 4:
				var p := c + t.rights[k] * side * (15.0 + row * 2.8)
				p.y = 0.0
				if not _in_port(p) or not t._off_track(p, 2.0) or t._occ.has(t._okey(p)):
					continue
				var hgt: int = [3, 2, 4, 3][(row + k / 7) % 4] - (1 if t.rng.randf() < 0.2 else 0)
				for lv in hgt:
					_container(p + Vector3.UP * (lv * 2.6), t.tangents[k], LIVERIES[t.rng.randi() % LIVERIES.size()])
				t._mark(p, t.tangents[k], t.rights[k], 12.0, 2.6)
		# Collider: one wall per side for the container rows.
	for side: float in [-1.0, 1.0]:
		_port_wall(side)
	# Inner yard: big blocks of containers filling the port.
	var x := PORT.position.x + 8.0
	while x < PORT.end.x - 6.0:
		var z := PORT.position.y + 6.0
		while z < PORT.end.y - 6.0:
			var p := Vector3(x, 0, z)
			z += 3.0
			if absf(z - PORT_RAIL_Z) < 18.0 or t._tdist(p, 60.0) < 30.0 or t._occ.has(t._okey(p)):
				continue
			var hgt := t.rng.randi_range(1, 5)
			for lv in hgt:
				_container(p + Vector3.UP * (lv * 2.6), Vector3.RIGHT, LIVERIES[t.rng.randi() % LIVERIES.size()])
		x += 13.0
	# Two gantry cranes straddling the road on CD.
	for a: Vector3 in [Vector3(450, 0, 80), Vector3(560, 0, 80)]:
		var ci := t._nearest(a, 30.0)
		if ci >= 0:
			_gantry(t.centers[ci], t.tangents[ci], t.rights[ci])
	# Floodlight masts.
	for m: Vector3 in [Vector3(420, 0, 40), Vector3(590, 0, 125), Vector3(590, 0, -120), Vector3(660, 0, 20)]:
		if t._off_track(m, 3.0):
			_mast(m)


func _port_wall(side: float) -> void:
	var faces := PackedVector3Array()
	var prev := Vector3.INF
	for k in t.n + 1:
		var i := t._i(k)
		var c := t.centers[i]
		var p := c + t.rights[i] * side * 14.0
		var inside := _in_port(c + t.rights[i] * side * 20.0) and absf(c.z - PORT_RAIL_Z) > 16.0
		if not inside:
			prev = Vector3.INF
			continue
		if prev != Vector3.INF:
			for v in [prev, prev + Vector3.UP * 4.0, p + Vector3.UP * 4.0, prev, p + Vector3.UP * 4.0, p]:
				faces.append(v)
		prev = p
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## Rail-mounted gantry crane over the road: legs beyond the container rows,
## box girder 24 m up, trolley with a container hanging from the spreader.
func _gantry(c: Vector3, ax: Vector3, az: Vector3) -> void:
	var span := 27.0
	var hgt := 24.0
	var paint := Color(0.82, 0.18, 0.08) if t.rng.randf() < 0.5 else Color(0.1, 0.32, 0.62)
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			var lp := c + az * s * span + ax * f * 7.0
			lp.y = 0.0
			t._box("steel", lp + Vector3.UP * hgt * 0.5, ax, Vector3.UP, az, Vector3(1.4, hgt, 1.4), paint)
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.6, hgt, 1.6)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = Transform3D(Basis(ax, Vector3.UP, az), lp + Vector3.UP * hgt * 0.5)
			body.add_child(cs)
		# Sill beam (wheels) and diagonal-looking side frame
		var sp := c + az * s * span
		sp.y = 0.0
		t._box("steel", sp + Vector3.UP * 1.0, ax, Vector3.UP, az, Vector3(17.0, 2.0, 1.8), Color(0.2, 0.2, 0.2))
		t._box("steel", sp + Vector3.UP * (hgt - 1.5), ax, Vector3.UP, az, Vector3(15.4, 2.2, 1.6), paint)
		t._box("steel", sp + Vector3.UP * (hgt * 0.5), ax, Vector3.UP, az, Vector3(14.0, 0.8, 0.8), paint)
		# Cab
		t._box("conc", sp + Vector3.UP * (hgt - 4.0) - az * s * 2.0, ax, Vector3.UP, az, Vector3(3.0, 2.6, 2.6), Color(0.9, 0.9, 0.88))
	# Main girders across the road
	var top := Vector3(c.x, hgt + 1.2, c.z)
	for f: float in [-1.0, 1.0]:
		t._box("steel", top + ax * f * 6.2, ax, Vector3.UP, az, Vector3(1.6, 2.6, span * 2.0 + 4.0), paint)
	t._box("steel", top + Vector3.UP * 1.6, ax, Vector3.UP, az, Vector3(13.0, 0.4, span * 2.0 + 4.0), Color(0.3, 0.3, 0.3))
	# Trolley + hanging spreader with a container, over the stacks (never over the road)
	var tz := t.rng.randf_range(16.0, 22.0) * (1.0 if t.rng.randf() < 0.5 else -1.0)
	var tp := top + az * tz + Vector3.UP * 2.2
	t._box("steel", tp, ax, Vector3.UP, az, Vector3(13.0, 2.2, 6.0), Color(0.85, 0.85, 0.83))
	t._box("rail", tp - Vector3.UP * 5.0, ax, Vector3.UP, az, Vector3(0.1, 8.0, 0.1), Color(0.3, 0.3, 0.3))
	_container(tp - Vector3.UP * 12.6, ax, LIVERIES[t.rng.randi() % LIVERIES.size()])
	# Floodlights under the girders and warning lamps on top.
	for f: float in [-0.6, 0.0, 0.6]:
		t._box("glow", top - Vector3.UP * 1.45 + az * f * span, ax, Vector3.UP, az, Vector3(1.6, 0.15, 0.9), Color(1.0, 0.95, 0.85))
	for s: float in [-1.0, 1.0]:
		t._box("blink", top + az * s * (span + 1.5) + Vector3.UP * 1.8, ax, Vector3.UP, az, Vector3(0.5, 0.5, 0.5), Color(1.0, 0.15, 0.05))
	if night:
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.93, 0.82)
		l.light_energy = 14.0
		l.spot_range = 48.0
		l.spot_angle = 62.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 160.0
		l.distance_fade_length = 40.0
		t.parent.add_child(l)
		l.transform = Transform3D(Basis.looking_at(Vector3.DOWN, ax), top - Vector3.UP * 1.6)
	t.no_trees.append([c, span + 6.0])


## Port floodlight mast: 30 m lattice-ish pole, a ring of lamp heads.
func _mast(p: Vector3) -> void:
	var h := 30.0
	t._cyl("steel", p, 0.45, 0.25, h, 8, Color(0.6, 0.62, 0.62))
	t._box("steel", p + Vector3.UP * (h + 0.3), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(4.2, 0.4, 4.2), Color(0.3, 0.3, 0.3))
	for k in 8:
		var a := TAU * k / 8.0
		var q := p + Vector3(cos(a) * 1.8, h + 0.9, sin(a) * 1.8)
		t._box("glow", q, Vector3(cos(a), 0, sin(a)), Vector3.UP, Vector3(-sin(a), 0, cos(a)), Vector3(0.25, 0.8, 0.9), Color(1.0, 0.92, 0.75))
	if night:
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.65)
		l.light_energy = 18.0
		l.spot_range = 70.0
		l.spot_angle = 70.0
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 200.0
		l.distance_fade_length = 50.0
		t.parent.add_child(l)
		l.transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), p + Vector3.UP * (h - 0.5))
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = h
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = p + Vector3.UP * h * 0.5
	body.add_child(cs)


# ---------------------------------------------------------------- rail crossing

func _rail_crossing() -> void:
	var ci := -1
	for k in t.n:
		if t.centers[k].x > 560.0 and absf(t.centers[k].z - PORT_RAIL_Z) < 2.0:
			ci = k
			break
	if ci < 0:
		return
	var c := t.centers[ci]
	t.parent.set_meta("rail_crossing", c)
	var x0 := PORT.position.x - 20.0
	var x1 := c.x + 320.0
	for tz: float in [-2.4, 2.4]:
		var z := PORT_RAIL_Z + tz
		# Sleepers (off the road), ballast bed, rails.
		var x := x0
		while x < x1:
			var sp := Vector3(x, 0.08, z)
			if absf(x - c.x) > t.half + 1.0:
				t._box("conc", sp, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.26, 0.16, 2.6), Color(0.55, 0.53, 0.5))
			x += 0.75
		t._quad("asphalt", Vector3(x0, 0.045, z - 1.7), Vector3(c.x - t.half - 1.0, 0.045, z - 1.7), Vector3(c.x - t.half - 1.0, 0.045, z + 1.7), Vector3(x0, 0.045, z + 1.7), Color(0.55, 0.5, 0.45), Vector3.UP)
		t._quad("asphalt", Vector3(c.x + t.half + 1.0, 0.045, z - 1.7), Vector3(x1, 0.045, z - 1.7), Vector3(x1, 0.045, z + 1.7), Vector3(c.x + t.half + 1.0, 0.045, z + 1.7), Color(0.55, 0.5, 0.45), Vector3.UP)
		for g: float in [-0.72, 0.72]:
			# On the road the rails are flush with the tarmac (a thin steel strip).
			var y_off := 0.2
			t._box("rail", Vector3((x0 + c.x - t.half - 1.0) * 0.5, y_off, z + g), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(c.x - t.half - 1.0 - x0, 0.15, 0.08), Color(0.6, 0.58, 0.55))
			t._box("rail", Vector3((x1 + c.x + t.half + 1.0) * 0.5, y_off, z + g), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(x1 - c.x - t.half - 1.0, 0.15, 0.08), Color(0.6, 0.58, 0.55))
			var ry := c.y + 0.04
			t._quad("rail", Vector3(c.x - t.half - 1.0, ry, z + g - 0.05), Vector3(c.x + t.half + 1.0, ry, z + g - 0.05), Vector3(c.x + t.half + 1.0, ry, z + g + 0.05), Vector3(c.x - t.half - 1.0, ry, z + g + 0.05), Color(0.75, 0.73, 0.7), Vector3.UP)
	# Crossing lights + St Andrew's crosses + raised booms, both sides of the road.
	var ax := t.tangents[ci]
	var az := t.rights[ci]
	for s: float in [-1.0, 1.0]:
		var base := c + az * s * 11.2 + ax * (-6.0 * s)
		base.y = 0.0
		t._box("steel", base + Vector3.UP * 2.0, ax, Vector3.UP, az, Vector3(0.14, 4.0, 0.14), Color(0.85, 0.85, 0.85))
		var face := -ax * s # faces approaching traffic on that side
		var fx := Vector3.UP.cross(face).normalized()
		for d: float in [-1.0, 1.0]:
			var arm := Basis(fx.rotated(face, d * 0.6), Vector3.UP.rotated(face, d * 0.6), face)
			t._box("steel", base + Vector3.UP * 3.6 + face * 0.1, arm.x, arm.y, arm.z, Vector3(1.3, 0.2, 0.03), Color(0.75, 0.08, 0.06))
		for d: float in [-0.35, 0.35]:
			var lp := base + Vector3.UP * 2.7 + fx * d + face * 0.12
			t._box("blink", lp, fx, Vector3.UP, face, Vector3(0.28, 0.28, 0.08), Color(1.0, 0.08, 0.03))
			t._quad("blink", lp - fx * 0.1 + Vector3.UP * 0.1 + face * 0.05, lp + fx * 0.1 + Vector3.UP * 0.1 + face * 0.05, lp + fx * 0.1 - Vector3.UP * 0.1 + face * 0.05, lp - fx * 0.1 - Vector3.UP * 0.1 + face * 0.05,
				Color(1.0, 0.08, 0.03), face, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(1.0 if d > 0.0 else 0.0, 0))
		# Boom raised almost vertical, red/white stripes.
		var bp := base + az * s * 0.8 + Vector3.UP * 1.0
		t._box("steel", bp, ax, Vector3.UP, az, Vector3(0.5, 1.0, 0.5), Color(0.9, 0.9, 0.88))
		for k in 5:
			var col := Color(0.85, 0.08, 0.06) if k % 2 == 0 else Color(0.95, 0.95, 0.93)
			var tilt := Basis(ax, deg_to_rad(-8.0) * s)
			t._box("steel", bp + Vector3.UP * (0.6 + k * 1.2 + 0.6) - az * s * (k * 0.17), tilt * ax, tilt * Vector3.UP, tilt * az, Vector3(0.12, 1.2, 0.12), col)
	# A parked freight train on the far track, east of the road.
	var x := c.x + 30.0
	for w in 9:
		var wp := Vector3(x, 0.0, PORT_RAIL_Z + 2.4)
		t._box("steel", wp + Vector3.UP * 1.1, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(15.5, 0.5, 2.8), Color(0.18, 0.16, 0.14))
		for b: float in [-5.5, 5.5]:
			t._box("steel", wp + Vector3(b, 0.55, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(2.4, 0.7, 2.4), Color(0.1, 0.1, 0.1))
		if w == 0:
			t._box("steel", wp + Vector3.UP * 2.9, Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(15.0, 3.2, 3.0), Color(0.8, 0.45, 0.08)) # loco
			t._box("glow", wp + Vector3(-7.55, 2.2, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.1, 0.3, 1.8), Color(1.0, 0.95, 0.85))
		else:
			_container(wp + Vector3(-3.1, 1.35, 0), Vector3.RIGHT, LIVERIES[t.rng.randi() % LIVERIES.size()])
			if t.rng.randf() < 0.6:
				_container(wp + Vector3(3.1, 1.35, 0), Vector3.RIGHT, LIVERIES[t.rng.randi() % LIVERIES.size()])
		x += 16.5
