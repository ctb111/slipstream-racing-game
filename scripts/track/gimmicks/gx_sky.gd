class_name GxSky
extends Node3D
## Things in the sky over the circuit: hot-air balloons drifting slowly with
## the wind (classic teardrop envelopes with coloured gores, load tapes, a
## wicker basket and a burner that flares now and then) and an advertising
## blimp circling high with a brand on both flanks.
##
##   GxSky.place(c, Transform3D.IDENTITY, {})                      # 3 balloons + blimp
##   GxSky.place(c, Transform3D.IDENTITY, {balloons = 5, blimp = false})
##   GxSky.place(c, Gx.frame(c, 800.0, Gx.RIGHT, 40.0), {balloons = 1, blimp = false, hover = 30})  # one low, tethered/hovering
## Options: balloons (3), blimp (true), brand (atlas key "b_helios", "b_kronen",
##   "b_nordlicht", "b_aurel", "b_falke", "b_marzelli", "b_valter"), blimp_alt (260),
##   alt_min/alt_max for balloons (140/420), wind (Vector3, default from a seed), hover (m).
## Cosmetic, local, no collision. Each balloon / the blimp is one node with
## 2-4 merged meshes; all always visible (they are big and far).

const GORE_SETS := [
	[Color(0.75, 0.10, 0.08), Color(0.95, 0.80, 0.20)],
	[Color(0.10, 0.25, 0.60), Color(0.92, 0.92, 0.90), Color(0.85, 0.15, 0.10)],
	[Color(0.15, 0.45, 0.25), Color(0.95, 0.95, 0.92)],
	[Color(0.95, 0.55, 0.10), Color(0.55, 0.10, 0.35), Color(0.95, 0.85, 0.30)],
	[Color(0.20, 0.20, 0.25), Color(0.90, 0.75, 0.15)],
	[Color(0.35, 0.65, 0.85), Color(0.95, 0.95, 0.95)],
]

var kind := "balloon"
var centre := Vector3.ZERO
var radius := 600.0
var wind := Vector3(3, 0, 1)
var speed := 13.0
var _a := 0.0
var _t := 0.0
var _base_y := 0.0
var _flame: MeshInstance3D
var _next_burn := 0.0
var _hover := false


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(opts.get("seed", hash(str(c.get("def").get("id", "")) if c.get("def") is Dictionary else "sky")))
	var b := _bounds(c)
	var ctr: Vector3 = b[0]
	var rad: float = b[1]
	var wind: Vector3 = opts.get("wind", Vector3(cos(r.randf() * TAU), 0, sin(r.randf() * TAU)) * r.randf_range(1.6, 3.2))
	var n := int(opts.get("balloons", 3))
	for i in n:
		var s := GxSky.new()
		s.name = "GxBalloon"
		s.kind = "balloon"
		s.centre = ctr
		s.radius = rad * 1.3
		s.wind = wind * r.randf_range(0.85, 1.15)
		s._build_balloon(r, GORE_SETS[(i + r.randi()) % GORE_SETS.size()], r.randf() < 0.3)
		if opts.has("hover"):
			s._hover = true
			s.position = xf.origin + Vector3.UP * float(opts.hover) + xf.basis.z * 15.0 * (i + 1)
		else:
			var a := r.randf() * TAU
			s.position = ctr + Vector3(cos(a), 0, sin(a)) * rad * r.randf_range(0.2, 1.1)
			s.position.y = ctr.y + r.randf_range(float(opts.get("alt_min", 140.0)), float(opts.get("alt_max", 420.0)))
		s._base_y = s.position.y
		s.rotation.y = r.randf() * TAU
		s._t = r.randf() * 100.0
		c.add_child(s)
	if GxCamp._b(opts.get("blimp", true)):
		var bl := GxSky.new()
		bl.name = "GxBlimp"
		bl.kind = "blimp"
		bl.centre = ctr + Vector3.UP * float(opts.get("blimp_alt", 260.0))
		bl.radius = maxf(rad * 0.75, 250.0)
		bl._a = r.randf() * TAU
		bl._build_blimp(str(opts.get("brand", ["b_helios", "b_kronen", "b_nordlicht", "b_falke"][r.randi() % 4])))
		c.add_child(bl)


## Centre (at the highest centreline point) and radius of the circuit.
static func _bounds(c: Node3D) -> Array:
	var cv := Gx.curve(c)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var l := cv.get_baked_length()
	for i in 64:
		var p := cv.sample_baked(l * i / 64.0)
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return [Vector3((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5), maxf(hi.x - lo.x, hi.z - lo.z) * 0.5]


func _process(delta: float) -> void:
	_t += delta
	if kind == "blimp":
		_a = fmod(_a + speed / radius * delta, TAU)
		var p := centre + Vector3(cos(_a) * radius, sin(_a * 2.0) * 8.0, sin(_a) * radius * 0.8)
		var ahead := centre + Vector3(cos(_a + 0.02) * radius, 0, sin(_a + 0.02) * radius * 0.8)
		ahead.y = p.y
		var b := Basis.looking_at((ahead - p).normalized(), Vector3.UP) * Basis(Vector3.FORWARD, 0.04) # leans out of the turn a touch
		transform = Transform3D(b, p)
		return
	# balloon: drift, gentle bob and spin, wrap back upwind
	if not _hover:
		position += wind * delta
		var d := Vector2(position.x - centre.x, position.z - centre.z)
		if d.length() > radius:
			var back := -Vector2(wind.x, wind.z).normalized() * radius * 0.95
			position.x = centre.x + back.x + d.normalized().orthogonal().x * 50.0
			position.z = centre.z + back.y
	position.y = _base_y + sin(_t * 0.11) * 6.0 + sin(_t * 0.37) * 1.5
	rotate_y(delta * 0.02)
	if _flame:
		if _t > _next_burn:
			_flame.visible = not _flame.visible
			_next_burn = _t + (randf_range(1.5, 3.5) if _flame.visible else randf_range(6.0, 18.0))
		if _flame.visible:
			_flame.scale = Vector3.ONE * (0.85 + 0.25 * sin(_t * 31.0) * sin(_t * 17.0))


# ---------------------------------------------------------------- balloon

## Envelope ~22 m tall, 17 m across; basket hangs ~5 m under the mouth.
func _build_balloon(r: RandomNumberGenerator, cols: Array, band: bool) -> void:
	var g := GxGeo.new()
	# profile (radius, height) from the mouth up to the crown
	var prof := [Vector2(2.0, 0.0), Vector2(3.2, 2.0), Vector2(5.2, 5.0), Vector2(7.2, 9.0), Vector2(8.4, 13.0),
		Vector2(8.6, 15.5), Vector2(8.2, 18.0), Vector2(6.8, 20.5), Vector2(4.6, 22.2), Vector2(2.2, 23.2), Vector2(0.0, 23.5)]
	var gores := 16
	var sub := 3 # subdivisions per gore: the fabric bulges between load tapes
	var n := gores * sub
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		for j in n:
			var a0 := TAU * j / n
			var a1 := TAU * (j + 1) / n
			var f0 := fmod(float(j), sub) / sub
			var f1 := fmod(float(j), sub) / sub + 1.0 / sub
			var b0 := 1.0 + 0.035 * sin(PI * f0)
			var b1 := 1.0 + 0.035 * sin(PI * f1)
			var v00 := Vector3(cos(a0) * p0.x * b0, p0.y, sin(a0) * p0.x * b0)
			var v01 := Vector3(cos(a1) * p0.x * b1, p0.y, sin(a1) * p0.x * b1)
			var v10 := Vector3(cos(a0) * p1.x * b0, p1.y, sin(a0) * p1.x * b0)
			var v11 := Vector3(cos(a1) * p1.x * b1, p1.y, sin(a1) * p1.x * b1)
			var gi := j / sub
			var col: Color = cols[gi % cols.size()]
			if band and i >= 4 and i <= 5:
				col = cols[(gi + 1) % cols.size()]
			if i == 0:
				col = Color(0.12, 0.12, 0.12) # scoop / skirt, heat-resistant black
			var shade := 0.85 + 0.15 * float(i) / prof.size()
			g.col = Color(col.r * shade, col.g * shade, col.b * shade)
			var n00 := Vector3(cos(a0), 0.25, sin(a0)).normalized()
			var n01 := Vector3(cos(a1), 0.25, sin(a1)).normalized()
			g.tri_n("canvas", v00, v11, v01, n00, n01, n01) # outward: viewed from outside
			g.tri_n("canvas", v00, v10, v11, n00, n00, n01)
	# load tapes (thin dark lines on the gore seams)
	g.col = Color(0.15, 0.13, 0.12)
	for k in gores:
		var a := TAU * k / gores
		var pts := []
		for q: Vector2 in prof:
			pts.append(Vector3(cos(a) * (q.x + 0.03), q.y, sin(a) * (q.x + 0.03)))
		g.tube("steel", pts.slice(0, prof.size() - 1), 0.035, 3, false)
	# cables down to the basket, burner frame, basket
	var by := -5.2
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		g.bar("steel", Vector3(cos(a) * 2.0, 0.0, sin(a) * 2.0), Vector3(cos(a) * 0.62, by + 1.5, sin(a) * 0.62), 0.02, 3)
		g.bar("steel", Vector3(cos(a) * 0.62, by + 1.5, sin(a) * 0.62), Vector3(cos(a) * 0.62, by + 1.1, sin(a) * 0.62), 0.025, 4)
	g.col = Color(0.3, 0.3, 0.32)
	g.box("steel", Vector3(0, by + 1.6, 0), Vector3(0.7, 0.18, 0.7), 0.04)
	g.col = Color(0.62, 0.48, 0.30)
	g.box("wood", Vector3(0, by + 0.55, 0), Vector3(1.3, 1.1, 1.3), 0.08)
	g.col = Color(0.35, 0.22, 0.12)
	g.box("wood", Vector3(0, by + 1.12, 0), Vector3(1.38, 0.08, 1.38), 0.03) # leather rim
	_commit(g, true)
	# burner flame (shown in bursts)
	_flame = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.28
	cm.height = 2.4
	cm.radial_segments = 8
	cm.rings = 1
	_flame.mesh = cm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.55, 0.15, 0.8)
	_flame.material_override = fm
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0, by + 2.9, 0)
	_flame.visible = false
	add_child(_flame)


# ---------------------------------------------------------------- blimp

## ~58 m long airship: smooth hull, cruciform tail, gondola, brand panels.
func _build_blimp(brand: String) -> void:
	var g := GxGeo.new()
	var len := 58.0
	var rad := 8.2
	var ns := 22
	var na := 24
	var rings := []
	for i in ns + 1:
		var t := float(i) / ns
		var z := lerpf(-len * 0.5, len * 0.5, t) # nose at -z
		# fat nose, long tapering tail
		var rr := rad * pow(sin(PI * pow(t, 0.8)), 0.62)
		var ring := []
		for j in na:
			var a := TAU * j / na
			ring.append([Vector3(cos(a) * rr, sin(a) * rr, z), Vector3(cos(a), sin(a), 0)])
		rings.append(ring)
	var white := Color(0.88, 0.88, 0.86)
	var stripe := Color(0.1, 0.2, 0.45) if brand != "b_kronen" else Color(0.55, 0.08, 0.08)
	for i in ns:
		for j in na:
			var j2 := (j + 1) % na
			var a: Array = rings[i][j]
			var b: Array = rings[i][j2]
			var cc: Array = rings[i + 1][j2]
			var d: Array = rings[i + 1][j]
			var ang := TAU * (j + 0.5) / na
			g.col = stripe if absf(sin(ang) + 0.62) < 0.08 else white
			# slope-corrected normals
			var na0: Vector3 = a[1]
			var na1: Vector3 = b[1]
			g.tri_n("painted_metal", a[0], b[0], cc[0], na0, na1, na1)
			g.tri_n("painted_metal", a[0], cc[0], d[0], na0, na1, na0)
	# tail fins (cruciform)
	g.col = white
	for k in 4:
		var rot := Basis(Vector3.BACK, PI * 0.5 * k)
		g.box("painted_metal", rot * Vector3(0, 5.5, 22.5), Vector3(0.35, 6.0, 7.5), 0.12, rot * Basis(Vector3.RIGHT, 0.35))
		g.col = stripe
		g.box("painted_metal", rot * Vector3(0, 6.2, 25.3), Vector3(0.38, 4.5, 1.6), 0.08, rot * Basis(Vector3.RIGHT, 0.35))
		g.col = white
	# gondola + engines
	g.col = Color(0.85, 0.85, 0.83)
	g.box("painted_metal", Vector3(0, -rad - 0.9, -3.0), Vector3(2.4, 2.0, 9.0), 0.6)
	g.col = Color.WHITE
	g.box("glass", Vector3(0, -rad - 0.7, -7.2), Vector3(2.2, 1.0, 1.2), 0.3)
	for sx: float in [-1.0, 1.0]:
		g.box("glass", Vector3(sx * 1.21, -rad - 0.6, -3.0), Vector3(0.05, 0.7, 6.0), 0.1)
		g.col = Color(0.3, 0.3, 0.32)
		g.tube("painted_metal", [Vector3(sx * 3.0, -rad - 0.5, -0.5), Vector3(sx * 3.0, -rad - 0.5, 1.6)], 0.55, 10)
		g.bar("steel", Vector3(sx * 1.2, -rad - 0.5, 0.5), Vector3(sx * 3.0, -rad - 0.5, 0.5), 0.12, 6)
		g.col = Color.WHITE
	# brand panels on both flanks (printed signs atlas)
	for sx: float in [-1.0, 1.0]:
		g.sign(Vector3(sx * (rad * 0.98 + 0.05), 0.8, -2.0), Vector3(sx, 0, 0), 30.0, 0.0, brand)
	_commit(g, false)


func _commit(g: GxGeo, _shadows: bool) -> void:
	var holder := Node3D.new()
	holder.name = "Mesh"
	add_child(holder)
	g.commit(holder, name, 0.0, false)
	# fabric: calmer canvas (and weather-bound)
	var cv := holder.get_node_or_null(name + "_canvas") as MeshInstance3D
	if cv:
		cv.material_override = GxCamp.canvas_material(cv.material_override)
