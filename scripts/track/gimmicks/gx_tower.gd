class_name GxTower
extends RefCounted
## Landmark towers seen from far round the lap.
##   GxTower.place(c, Gx.frame(c, 900.0, Gx.RIGHT, 40.0), {kind = "water_tower"})
## kinds:
##   "water_tower"   concrete mushroom water tower (~44 m), railing, sponsor print
##   "radio_mast"    guyed triangular lattice mast (~110 m), red/white bands, dishes,
##                   aviation lights, guy wires to concrete anchors
##   "fire_lookout"  timber forest fire lookout (~22 m) with stair flights and a glazed cab
##   "church_spire"  stone church tower with belfry, clock faces and a slate spire (~50 m),
##                   with a short nave
## opts: height (scales the main dimension), sponsor (TracksideUV.SIGNS key, water tower)
## Two LOD tiers: the silhouette is always drawn, small details fade at 450 m.
## Place it well off the road (it checks its footprint and skips if on the road).

static var _beacon: StandardMaterial3D


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var kind: String = opts.get("kind", "water_tower")
	var foot: float = {water_tower = 10.0, radio_mast = 4.0, fire_lookout = 5.0, church_spire = 12.0}.get(kind, 8.0)
	if not Gx.clear_of_road(c, xf.origin, foot + 2.0):
		push_warning("GxTower: %s at %s is on the road, skipped" % [kind, xf.origin])
		return
	var p := xf.origin
	p.y = Gx.ground(c, p)
	var m := Transform3D(xf.basis.orthonormalized(), p)
	var g := GxGeo.new(m) # silhouette, always drawn
	var d := GxGeo.new(m) # details, fade out
	var lights: Array = []
	match kind:
		"radio_mast":
			_mast(c, g, d, m, float(opts.get("height", 110.0)), lights)
		"fire_lookout":
			_lookout(g, d, float(opts.get("height", 22.0)))
		"church_spire":
			_church(g, d, float(opts.get("height", 26.0)))
		_:
			_water(g, d, float(opts.get("height", 30.0)), str(opts.get("sponsor", "")))
	var root := g.commit(c, "GxTower", 0.0, true)
	d.commit(root, "details", 450.0, false)
	if not lights.is_empty():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for lp: Vector3 in lights:
			var sm := SphereMesh.new()
			sm.radius = 0.35
			sm.height = 0.7
			sm.radial_segments = 8
			sm.rings = 4
			st.append_from(sm, 0, Transform3D(Basis(), lp))
		if _beacon == null:
			_beacon = StandardMaterial3D.new()
			_beacon.albedo_color = Color(1.0, 0.1, 0.05)
			_beacon.emission_enabled = true
			_beacon.emission = Color(1.0, 0.08, 0.04)
			_beacon.emission_energy_multiplier = 6.0
			_beacon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mi := Gx.add_mesh(c, st, _beacon, "beacons", 0.0)
		mi.reparent(root)
	Gx.reserve(c, p, foot + 6.0)
	GxGeo.ab(root, m * Vector3(-60.0, 2.0, -40.0), m * Vector3(0, 20.0, 0))


# ---------------------------------------------------------------- water tower

static func _water(g: GxGeo, d: GxGeo, h: float, sponsor: String) -> void:
	g.col = Color(0.86, 0.85, 0.82)
	g.lathe("concrete", Vector3.ZERO, PackedVector2Array([Vector2(3.6, -1.0), Vector2(3.6, 0.6), Vector2(2.7, 0.9), Vector2(2.45, h)]), 24)
	g.col = Color(0.94, 0.92, 0.86)
	var bowl := PackedVector2Array([Vector2(2.45, h), Vector2(4.5, h + 2.2), Vector2(8.2, h + 6.0), Vector2(9.0, h + 7.2), Vector2(9.0, h + 11.0),
		Vector2(9.25, h + 11.2), Vector2(9.25, h + 11.6), Vector2(8.4, h + 11.8), Vector2(3.0, h + 14.2), Vector2(1.2, h + 14.6)])
	g.lathe("plaster", Vector3.ZERO, bowl, 32)
	# lantern on the roof
	g.col = Color(0.5, 0.52, 0.52)
	g.lathe("painted_metal", Vector3(0, h + 14.5, 0), PackedVector2Array([Vector2(1.3, 0.0), Vector2(1.3, 1.6), Vector2(1.6, 1.7), Vector2(0.0, 2.6)]), 12)
	# vertical window slits on the shaft, door
	d.col = Color(0.15, 0.16, 0.17)
	for k in 5:
		var y := 4.0 + k * (h - 6.0) / 5.0
		d.box("glass", Vector3(0, y, -2.5), Vector3(0.45, 1.6, 0.12))
	d.box("painted_metal", Vector3(0, 1.9, -2.62), Vector3(1.4, 2.4, 0.1), 0.02)
	# gallery railing on the rim
	d.col = Color(0.7, 0.72, 0.72)
	var n := 40
	var ring := []
	for i in n + 1:
		var a := TAU * i / n
		ring.append(Vector3(cos(a), 0, sin(a)) * 9.15 + Vector3(0, h + 12.7, 0))
		if i < n:
			d.bar("steel", Vector3(cos(a) * 9.15, h + 11.6, sin(a) * 9.15), Vector3(cos(a) * 9.15, h + 12.7, sin(a) * 9.15), 0.03, 4)
	d.tube("steel", ring, 0.035, 6, false)
	# antennas on the rim
	for a: float in [0.6, 2.4, 4.1]:
		d.bar("steel", Vector3(cos(a) * 8.6, h + 11.6, sin(a) * 8.6), Vector3(cos(a) * 8.6, h + 16.5, sin(a) * 8.6), 0.05, 6)
		d.box("painted_metal", Vector3(cos(a) * 8.6, h + 15.6, sin(a) * 8.6), Vector3(0.35, 1.4, 0.2), 0.03, Basis(Vector3.UP, -a))
	# printed name/sponsor bands on the bowl wall (several facets)
	var key := sponsor if sponsor != "" else "p_kronen"
	for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
		var nrm := Vector3(-sin(a), 0, -cos(a))
		g.sign(nrm * 9.05 + Vector3(0, h + 9.1, 0), nrm, 7.0, 0.0, key)


# ---------------------------------------------------------------- radio mast

static func _mast(c: Node3D, g: GxGeo, d: GxGeo, m: Transform3D, h: float, lights: Array) -> void:
	var w := 1.6 # triangle side
	var rr := w / sqrt(3.0)
	var cs := []
	for k in 3:
		var a := TAU * k / 3.0
		cs.append(Vector3(cos(a) * rr, 0, sin(a) * rr))
	g.col = Color(0.78, 0.77, 0.74)
	g.box("concrete", Vector3(0, 0.2, 0), Vector3(3.5, 1.0, 3.5), 0.1)
	g.collide(Vector3(0, h * 0.5, 0), Vector3(w, h, w))
	var bands := 7
	var panel := 1.6
	var n := int(h / panel)
	for i in n:
		var y0 := 0.7 + i * panel
		var band := int(float(i) / n * bands)
		g.col = Color(0.85, 0.12, 0.08) if band % 2 == 0 else Color(0.95, 0.95, 0.93)
		for k in 3:
			var a: Vector3 = cs[k]
			var b: Vector3 = cs[(k + 1) % 3]
			g.bar("painted_metal", a + Vector3(0, y0, 0), a + Vector3(0, y0 + panel, 0), 0.07, 5)
			g.bar("painted_metal", a + Vector3(0, y0, 0), b + Vector3(0, y0 + panel, 0), 0.03, 4)
			g.bar("painted_metal", a + Vector3(0, y0 + panel, 0), b + Vector3(0, y0 + panel, 0), 0.03, 4)
	# antennas: dishes at 2/3, panel antennas at the top, top pole
	d.col = Color(0.88, 0.88, 0.86)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		var cpos := Vector3(cos(a) * 1.4, h * 0.62, sin(a) * 1.4)
		var save := d.xf
		d.xf = m * Transform3D(Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI * 0.5), cpos)
		d.lathe("painted_metal", Vector3.ZERO, PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.6, 0.12), Vector2(1.0, 0.35), Vector2(1.05, 0.45)]), 14)
		d.xf = save
	for k in 3:
		var a := TAU * k / 3.0
		g.col = Color(0.9, 0.9, 0.88)
		g.box("painted_metal", Vector3(cos(a) * 1.1, h - 3.0, sin(a) * 1.1), Vector3(0.35, 2.6, 0.35), 0.05, Basis(Vector3.UP, -a))
	g.col = Color(0.85, 0.12, 0.08)
	g.bar("painted_metal", Vector3(0, h + 0.7, 0), Vector3(0, h + 6.0, 0), 0.12, 6)
	lights.append(m * Vector3(0, h + 6.2, 0))
	lights.append(m * Vector3(0, h * 0.5, 0) + m.basis * (cs[0] as Vector3) * 1.3)
	# guy wires: 3 directions x 3 levels to concrete anchors on the ground
	d.col = Color(0.35, 0.36, 0.37)
	for k in 3:
		var a := TAU * k / 3.0 + PI / 3.0
		var dir := Vector3(cos(a), 0, sin(a))
		var dist := h * 0.55
		var anchor := m * (dir * dist)
		while dist > h * 0.25 and not Gx.clear_of_road(c, anchor, 3.0):
			dist -= 6.0
			anchor = m * (dir * dist)
		var ay := Gx.ground(c, anchor) - m.origin.y
		var al := dir * dist + Vector3(0, ay, 0)
		g.col = Color(0.75, 0.74, 0.7)
		g.box("concrete", al + Vector3(0, 0.3, 0), Vector3(2.0, 1.0, 2.0), 0.1)
		for f: float in [0.35, 0.62, 0.9]:
			var top := dir * rr + Vector3(0, h * f, 0)
			var mid := (top + al) * 0.5 - Vector3(0, h * 0.008, 0)
			d.tube("steel", [al + Vector3(0, 0.8, 0), mid, top], 0.03, 4, false)


# ---------------------------------------------------------------- fire lookout

static func _lookout(g: GxGeo, d: GxGeo, h: float) -> void:
	var wood := Color(0.55, 0.45, 0.36)
	g.col = wood
	var bw := 3.4
	var tw := 1.8
	var legs := [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
	var lv := 5
	for k in 4:
		var a: Array = legs[k]
		var b: Array = legs[(k + 1) % 4]
		g.beam("wood", Vector3(a[0] * bw, -0.5, a[1] * bw), Vector3(a[0] * tw, h, a[1] * tw), 0.3)
		g.col = Color(0.72, 0.71, 0.68)
		g.box("concrete", Vector3(a[0] * bw, 0.1, a[1] * bw), Vector3(0.8, 0.6, 0.8), 0.05)
		g.col = wood
		for i in lv:
			var t0 := float(i) / lv
			var t1 := float(i + 1) / lv
			var w0 := lerpf(bw, tw, t0)
			var w1 := lerpf(bw, tw, t1)
			var pa0 := Vector3(a[0] * w0, h * t0, a[1] * w0)
			var pa1 := Vector3(a[0] * w1, h * t1, a[1] * w1)
			var pb0 := Vector3(b[0] * w0, h * t0, b[1] * w0)
			var pb1 := Vector3(b[0] * w1, h * t1, b[1] * w1)
			d.col = wood * 0.95
			d.beam("wood", pa0, pb1, 0.14)
			d.beam("wood", pb0, pa1, 0.14)
			g.beam("wood", pa1, pb1, 0.18)
	# zig-zag stair flights inside the frame with landings
	d.col = wood * 0.9
	var flights := lv
	for i in flights:
		var y0 := h * float(i) / flights
		var y1 := h * float(i + 1) / flights
		var s := 1.0 if i % 2 == 0 else -1.0
		var a := Vector3(-s * 1.0, y0, 0.3)
		var b := Vector3(s * 1.0, y1, 0.3)
		d.beam("wood", a, b, 0.12, 0.3)
		var steps := int((y1 - y0) / 0.25)
		for k in steps:
			var t := (k + 0.5) / steps
			d.box("wood", a.lerp(b, t) + Vector3(0, 0.1, 0), Vector3(0.28, 0.05, 0.9))
		d.bar("wood", a + Vector3(0, 1.0, 0.75), b + Vector3(0, 1.0, 0.75), 0.04, 4)
	# cab: floor, low walls, glazing band, hip roof, catwalk
	g.col = wood
	g.box("wood", Vector3(0, h + 0.1, 0), Vector3(5.0, 0.25, 5.0), 0.02)
	g.box("wood", Vector3(0, h + 0.65, 0), Vector3(3.6, 1.0, 3.6), 0.02)
	g.col = Color(0.2, 0.24, 0.26)
	g.box("glass", Vector3(0, h + 1.85, 0), Vector3(3.5, 1.4, 3.5))
	g.col = wood * 0.85
	for cx: float in [-1.75, 1.75]:
		for cz: float in [-1.75, 1.75]:
			g.box("wood", Vector3(cx, h + 1.85, cz), Vector3(0.14, 1.4, 0.14))
	g.col = Color(0.42, 0.36, 0.32)
	var e := h + 2.6
	var ex := 2.4
	var ridge := e + 1.6
	g.tri_f("roof_tiles", Vector3(-ex, e, -ex), Vector3(ex, e, -ex), Vector3(0, ridge, 0), Vector3(0, 1, -1))
	g.tri_f("roof_tiles", Vector3(ex, e, -ex), Vector3(ex, e, ex), Vector3(0, ridge, 0), Vector3(1, 1, 0))
	g.tri_f("roof_tiles", Vector3(ex, e, ex), Vector3(-ex, e, ex), Vector3(0, ridge, 0), Vector3(0, 1, 1))
	g.tri_f("roof_tiles", Vector3(-ex, e, ex), Vector3(-ex, e, -ex), Vector3(0, ridge, 0), Vector3(-1, 1, 0))
	g.quad_n("roof_tiles", Vector3(-ex, e, -ex), Vector3(ex, e, -ex), Vector3(ex, e, ex), Vector3(-ex, e, ex), Vector3.DOWN)
	d.col = wood
	for s in 4:
		var a := Basis(Vector3.UP, PI * 0.5 * s)
		d.beam("wood", a * Vector3(-2.45, h + 1.15, -2.45), a * Vector3(2.45, h + 1.15, -2.45), 0.08)
		for k in 6:
			d.box("wood", a * Vector3(-2.45 + k * 0.98, h + 0.65, -2.45), Vector3(0.08, 1.0, 0.08))
	d.col = Color(0.85, 0.2, 0.1)
	d.bar("wood", Vector3(0, ridge, 0), Vector3(0, ridge + 3.0, 0), 0.04, 5)
	d.box("props", Vector3(0.5, ridge + 2.6, 0), Vector3(1.0, 0.6, 0.02)) # flag (red)


# ---------------------------------------------------------------- church

static func _church(g: GxGeo, d: GxGeo, h: float) -> void:
	var tw := 7.0
	var hw := tw * 0.5
	g.col = Color(0.95, 0.93, 0.9)
	g.box("stone", Vector3(0, h * 0.5 - 1.0, 0), Vector3(tw, h + 2.0, tw))
	g.collide(Vector3(0, h * 0.5, 0), Vector3(tw, h, tw))
	# string courses, corner buttresses
	g.col = Color(1.0, 0.98, 0.95)
	for y: float in [h * 0.35, h * 0.7, h]:
		g.box("stone", Vector3(0, y, 0), Vector3(tw + 0.3, 0.3, tw + 0.3), 0.06)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			g.box("stone", Vector3(cx * (hw + 0.2), h * 0.25, cz * (hw + 0.2)), Vector3(1.0, h * 0.55, 1.0), 0.08)
	# belfry openings (dark, louvred) and clock faces on all 4 sides
	for s in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * s)
		g.col = Color(0.1, 0.09, 0.08)
		for ox: float in [-1.2, 1.2]:
			g.box("props", b * Vector3(ox, h * 0.85, -hw - 0.01), Vector3(1.0, 2.6, 0.06), 0.0, b)
		d.col = Color(0.35, 0.3, 0.25)
		for ox: float in [-1.2, 1.2]:
			for k in 6:
				d.box("wood", b * Vector3(ox, h * 0.85 - 1.1 + k * 0.4, -hw - 0.05), Vector3(0.95, 0.06, 0.12), 0.0, b * Basis(Vector3.RIGHT, 0.5))
		var fp := b * Vector3(0, h * 0.58, -hw - 0.03)
		var save := g.xf
		g.xf = g.xf * Transform3D(b * Basis(Vector3.UP, PI * 0.5), fp)
		GxArch._clock(g, Vector3.ZERO, 1.0)
		g.xf = save
		g.col = Color(0.95, 0.93, 0.9)
	# octagonal slate spire with lucarnes, cross on top
	var sh := h * 0.95
	var r0 := hw + 0.15
	var n := 8
	g.col = Color(0.75, 0.78, 0.82)
	for i in n:
		var a0 := TAU * (i + 0.5) / n
		var a1 := TAU * (i + 1.5) / n
		var p0 := Vector3(cos(a0) * r0, h + 0.15, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, h + 0.15, sin(a1) * r0)
		var am := (a0 + a1) * 0.5
		g.tri_f("slate", p0, p1, Vector3(0, h + sh, 0), Vector3(cos(am), 0.3, sin(am)))
	g.col = Color(0.55, 0.45, 0.25)
	g.bar("painted_metal", Vector3(0, h + sh - 0.2, 0), Vector3(0, h + sh + 2.4, 0), 0.06, 6)
	g.bar("painted_metal", Vector3(-0.6, h + sh + 1.7, 0), Vector3(0.6, h + sh + 1.7, 0), 0.05, 6)
	# nave behind the tower (along +z), gable roof
	var nl := 16.0
	var nw := 9.0
	var nh := h * 0.45
	g.col = Color(0.95, 0.93, 0.9)
	g.box("stone", Vector3(0, nh * 0.5 - 1.0, hw + nl * 0.5), Vector3(nw, nh + 2.0, nl))
	g.collide(Vector3(0, nh * 0.5, hw + nl * 0.5), Vector3(nw, nh, nl))
	g.col = Color(0.66, 0.34, 0.24)
	var ridge := nh + nw * 0.45
	for s: float in [-1.0, 1.0]:
		g.quad_n("roof_tiles", Vector3(s * (nw * 0.5 + 0.5), nh - 0.3, hw), Vector3(s * (nw * 0.5 + 0.5), nh - 0.3, hw + nl + 0.5),
			Vector3(0, ridge, hw + nl + 0.5), Vector3(0, ridge, hw), Vector3(s, 1, 0))
	g.col = Color(0.95, 0.93, 0.9)
	g.tri_f("stone", Vector3(-nw * 0.5, nh, hw + nl), Vector3(nw * 0.5, nh, hw + nl), Vector3(0, ridge - 0.2, hw + nl), Vector3(0, 0, 1))
	# tall arched windows on the nave
	for s: float in [-1.0, 1.0]:
		for k in 3:
			var z := hw + 3.5 + k * 4.5
			g.col = Color(0.12, 0.14, 0.16)
			g.box("glass", Vector3(s * (nw * 0.5 + 0.01), nh * 0.55, z), Vector3(0.05, nh * 0.5, 1.4))
			d.col = Color(1.0, 0.98, 0.95)
			_window_arch(d, s * nw * 0.5, nh * 0.8, z, s)


## Small round arch over a nave window (voussoirs proud of the x = const wall).
static func _window_arch(d: GxGeo, x: float, y: float, z: float, s: float) -> void:
	var save := d.xf
	d.xf = d.xf * Transform3D(Basis(), Vector3(0, 0, z))
	GxArch._voussoir_ring(d, "stone", x, x + 0.08 * s, y, 0.7, 0.95, 7)
	d.xf = save


## gx_test framing: from the road side, whole tower in view.
static func views(_c: Node3D, xf: Transform3D, opts: Dictionary) -> Array:
	var o := xf.origin
	var h: float = {radio_mast = 60.0, church_spire = 25.0, water_tower = 22.0}.get(str(opts.get("kind", "")), 12.0)
	return [["landmark", o - xf.basis.z * (h * 2.2 + 20.0) - xf.basis.x * h + Vector3.UP * 2.0, o + Vector3.UP * h]]
