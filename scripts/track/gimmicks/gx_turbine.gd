class_name GxTurbine
extends RefCounted
## Modern 3-blade wind turbines (tubular tower, nacelle, twisted lofted blades)
## whose rotors turn with the weather's wind. Landmark scale (~120 m tip height),
## always drawn; small triangle counts so a row of them is cheap.
##   GxTurbine.place(c, Gx.frame(c, 1200.0, Gx.LEFT, 90.0), {count = 4})
## opts:
##   count    turbines in the row (default 1), spaced along the frame's x
##   spacing  metres between them (default 150)
##   height   hub height (default 80), blade (default 40)
##   yaw      rotor facing in radians (default: one wind direction per circuit)
## Turbines whose blades would come within 10 m of the road are skipped.

const WHITE := Color(0.92, 0.92, 0.9)


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var count: int = int(opts.get("count", 1))
	var spacing: float = float(opts.get("spacing", 150.0))
	var hub: float = float(opts.get("height", 80.0))
	var blade: float = float(opts.get("blade", 40.0))
	var rng := Gx.rng(c, "turbine")
	var yaw: float = float(opts.get("yaw", rng.randf() * TAU))
	var wx = c.get("weather")
	var wind: float = float(wx.wind) if wx is Weather else 0.3
	for k in count:
		var p := xf * Vector3((k - (count - 1) * 0.5) * spacing, 0, rng.randf_range(-12.0, 12.0))
		if not Gx.clear_of_road(c, p, blade + 10.0):
			continue
		p.y = Gx.ground(c, p) - 0.3
		_one(c, p, yaw + rng.randf_range(-0.08, 0.08), hub, blade, wind, rng.randf() * TAU)
		Gx.reserve(c, p, 14.0)


static func _one(c: Node3D, p: Vector3, yaw: float, hub: float, blade: float, wind: float, phase: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var g := GxGeo.new(Transform3D(b, p))
	# foundation, tower with flange rings and a door
	g.col = Color(0.8, 0.79, 0.76)
	g.lathe("concrete", Vector3.ZERO, PackedVector2Array([Vector2(7.0, -0.5), Vector2(7.0, 0.35), Vector2(3.0, 0.9), Vector2(0.0, 0.9)]), 20)
	g.col = WHITE
	var prof := PackedVector2Array()
	var n := 8
	for i in n + 1:
		var t := float(i) / n
		prof.append(Vector2(lerpf(2.25, 1.35, t), 0.9 + (hub - 2.7) * t))
	g.lathe("painted_metal", Vector3.ZERO, prof, 20)
	for i in range(1, 4):
		var t := i / 4.0
		g.lathe("painted_metal", Vector3(0, 0.9 + (hub - 2.7) * t - 0.1, 0), PackedVector2Array([Vector2(lerpf(2.25, 1.35, t) + 0.04, 0), Vector2(lerpf(2.25, 1.35, t) + 0.04, 0.2)]), 20)
	g.col = Color(0.35, 0.37, 0.38)
	g.box("painted_metal", Vector3(0, 2.2, 2.2), Vector3(1.0, 2.2, 0.12), 0.02)
	g.box("painted_metal", Vector3(0, 1.0, 2.9), Vector3(1.4, 0.12, 1.4), 0.0) # step
	g.collide(Vector3(0, hub * 0.5, 0), Vector3(3.6, hub, 3.6))
	# nacelle: long rounded box, hub forward (+z local after yaw)
	g.col = WHITE
	g.box("painted_metal", Vector3(0, hub + 0.3, -1.6), Vector3(3.4, 3.6, 10.5), 0.9)
	g.box("painted_metal", Vector3(0, hub + 2.15, -4.5), Vector3(1.0, 0.5, 2.2), 0.2) # cooler
	g.col = Color(0.8, 0.12, 0.08)
	g.box("props", Vector3(0, hub + 2.35, -6.0), Vector3(0.3, 0.3, 0.3), 0.08) # aviation light
	var root := g.commit(c, "GxTurbine", 0.0, true)
	# rotor on its own spinning pivot
	var pivot := Spin.new()
	pivot.name = "rotor"
	pivot.speed = 0.6 + 1.5 * wind
	pivot.transform = Transform3D(b, p + b * Vector3(0, hub + 0.3, 4.0))
	pivot.rotate_object_local(Vector3.BACK, phase)
	root.add_child(pivot)
	var r := GxGeo.new()
	r.col = WHITE
	_spinner(r)
	for k in 3:
		_blade(r, TAU * k / 3.0, blade)
	r.commit(pivot, "blades", 0.0, false)


## Nose cone along local +z (rotor axis).
static func _spinner(r: GxGeo) -> void:
	var prof := PackedVector2Array([Vector2(1.75, -1.4), Vector2(1.85, 0.3), Vector2(1.55, 1.5), Vector2(0.95, 2.4), Vector2(0.0, 2.9)])
	var save := r.xf
	r.xf = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO) # lathe +y -> +z
	r.lathe("painted_metal", Vector3.ZERO, prof, 16)
	r.xf = save


## One blade at rotor angle `ang`: lofted airfoil, chord tapering, twisted, slight sweep.
static func _blade(r: GxGeo, ang: float, length: float) -> void:
	var foil := []
	var m := 12
	for i in m:
		var a := TAU * i / m
		# thick leading edge (+x), thin trailing edge (-x)
		var x := cos(a) * (0.55 if cos(a) > 0.0 else 0.45)
		var y := sin(a) * 0.11 * (1.0 if cos(a) > 0.0 else (1.0 + cos(a)) * 0.8 + 0.2)
		foil.append(Vector2(x, y))
	var st := 14
	var rings := []
	for j in st + 1:
		var t := float(j) / st
		var rad := 1.6 + t * (length - 1.6)
		var chord := 3.2 * (1.0 - t * 0.78) if t > 0.15 else lerpf(1.6, 3.0, t / 0.15)
		var round_root := clampf(1.0 - t / 0.12, 0.0, 1.0) # circular near the hub
		var twist := deg_to_rad(lerpf(16.0, 0.0, sqrt(t)))
		var sweep := -0.6 * t * t * chord
		var ring := []
		for i in m:
			var f: Vector2 = foil[i]
			var q := Vector2(f.x * chord + sweep, f.y * chord * (1.0 - round_root) + f.y / 0.11 * 0.5 * round_root * 1.0)
			if round_root > 0.0:
				var aa := TAU * i / m
				q = q.lerp(Vector2(cos(aa), sin(aa)) * 0.85, round_root)
			q = q.rotated(twist)
			# blade frame: radial direction along `ang` in the rotor plane (x, y), chord in-plane, thickness along z
			var radial := Vector3(cos(ang), sin(ang), 0)
			var chordv := Vector3(-sin(ang), cos(ang), 0)
			ring.append(radial * rad + chordv * q.x + Vector3(0, 0, q.y))
		rings.append(ring)
	for j in st:
		for i in m:
			var a: Vector3 = rings[j][i]
			var b: Vector3 = rings[j][(i + 1) % m]
			var cc: Vector3 = rings[j + 1][(i + 1) % m]
			var d: Vector3 = rings[j + 1][i]
			var ctr: Vector3 = (rings[j][0] + rings[j][m / 2]) * 0.5
			r.quad_n("painted_metal", a, b, cc, d, (a + b) * 0.5 - ctr - Vector3(cos(ang), sin(ang), 0) * ((a + b) * 0.5 - ctr).dot(Vector3(cos(ang), sin(ang), 0)))
	# tip cap
	var tip: Array = rings[st]
	var tc := Vector3.ZERO
	for v: Vector3 in tip:
		tc += v
	tc /= m
	for i in m:
		r.tri_f("painted_metal", tc, tip[i], tip[(i + 1) % m], Vector3(cos(ang), sin(ang), 0))


class Spin:
	extends Node3D
	var speed := 1.0

	func _process(delta: float) -> void:
		rotate_object_local(Vector3.BACK, speed * delta)


## gx_test framing: the row from a distance.
static func views(_c: Node3D, xf: Transform3D, _opts: Dictionary) -> Array:
	var o := xf.origin
	return [["row", o - xf.basis.z * 260.0 - xf.basis.x * 60.0 + Vector3.UP * 4.0, o + Vector3.UP * 60.0],
		["near", o - xf.basis.z * 70.0 + Vector3.UP * 3.0, o + Vector3.UP * 75.0]]
