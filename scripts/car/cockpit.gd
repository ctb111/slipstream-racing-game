class_name Cockpit
extends Node3D
## The in-car view for the local driver's car. It keeps the model's own
## interior (dash, seats, pillars, glass) and adds the things that have to move
## or be read:
##  - a steering wheel that turns with the front wheels (the model's own, static
##    wheel is cut out of a cockpit-only copy of the body mesh)
##  - working gauges (rev counter, speedometer, a few lively minor dials) with
##    backlit needles, drawn once into textures
##  - a rear-view mirror that really reflects (small SubViewport, low rate)
##  - rain drops / snow flakes on the windscreen, streaking at speed, cleared by
##    two wipers
##  - gloved hands on the wheel, forearms to the shoulders
##  - for a model with no dashboard, a procedural one
##  - an interior reflection probe so the closed cabin isn't lit like open sky
## Built lazily by ChaseCamera the first time the cockpit camera is selected;
## `active` shows / hides everything and swaps the body mesh.
## Debug (after `--`): --nomirror, --nohands, --noprobe, --nocockpitfx (no
## windscreen drops), --showcut (removed model triangles in magenta + logs).
## Visual check: tests/cockpit_preview.tscn.
##
## Coordinates in SPECS are car-local (Car's space: -Z forward, +X right,
## hubs at y = -0.225, ground ~ -0.54).

const RAIN_SHADER := preload("res://shaders/windscreen.gdshader")
const FONT_PATH := "res://assets/fonts/BarlowSemiCondensed-Medium.ttf"

## Per car:
##  eye            driver's eye point
##  wheel          hub of the steering wheel; wheel_r rim radius; wheel_tilt column
##                 angle above horizontal (deg); spokes 2..4; wheel_style
##  cut            [radius, half-depth] around the hub (or cut_at): model triangles removed there
##  gauges         [kind, centre (car-local), radius]; kinds: tach speed oil temp fuel clock volt boost
##  needle         needle colour
##  glass          windscreen material key (surface_keys) to fit the rain plane to
##  mirror         rear-view mirror centre (default: under the windscreen header)
##  dash           true: build a procedural dashboard (model has none)
const SPECS := {
	"porsche930": {
		eye = Vector3(-0.26, 0.5, 0.24), wheel = Vector3(-0.25, 0.21, -0.22), wheel_r = 0.19, wheel_tilt = 24.0,
		spokes = 4, wheel_style = "porsche", cut = [0.25, 0.08],
		dash = true, seats = true, binnacle_w = 0.6,
		cluster = [["clock", -0.235, -0.006, 0.036], ["speed", -0.12, 0.0, 0.048], ["tach", 0.0, 0.004, 0.056],
			["oil", 0.12, 0.0, 0.048], ["fuel", 0.235, -0.006, 0.036]],
		needle = Color(1.0, 0.45, 0.12), glass = "glass",
	},
	"bmw_e30_m3": {
		eye = Vector3(-0.28, 0.55, 0.2), wheel = Vector3(-0.275, 0.25, -0.26), wheel_r = 0.195, wheel_tilt = 22.0,
		spokes = 3, wheel_style = "sport", cut = [0.26, 0.08],
		dash = true, seats = true, binnacle_w = 0.44,
		cluster = [["speed", -0.09, 0.0, 0.058], ["tach", 0.09, 0.0, 0.058], ["temp", -0.185, -0.02, 0.022], ["fuel", 0.185, -0.02, 0.022]],
		needle = Color(1.0, 0.35, 0.1), glass = "BMW_E30_M3_WINDOWS", mirror = Vector3(-0.02, 0.645, -0.17),
	},
	"datsun_240k": {
		eye = Vector3(-0.3, 0.49, 0.14), wheel = Vector3(-0.3, 0.23, -0.26), wheel_r = 0.19, wheel_tilt = 20.0,
		spokes = 3, wheel_style = "wood", cut = [0.0, 0.0], dash = true, seats = true, binnacle_w = 0.4,
		cluster = [["tach", -0.075, 0.0, 0.052], ["speed", 0.075, 0.0, 0.052]],
		needle = Color(0.95, 0.95, 0.9), glass = "glass",
	},
	"toyota_ae86": {
		eye = Vector3(0.36, 0.45, 0.26), wheel = Vector3(0.36, 0.18, -0.13), wheel_r = 0.185, wheel_tilt = 22.0,
		spokes = 3, wheel_style = "sport", cut = [0.26, 0.08], cut_at = Vector3(0.42, 0.05, -0.54), dash = true, binnacle_w = 0.44,
		cluster = [["speed", -0.085, 0.0, 0.05], ["tach", 0.085, 0.0, 0.055], ["fuel", -0.185, -0.015, 0.024], ["temp", 0.19, -0.015, 0.024]],
		needle = Color(1.0, 0.4, 0.12), glass = "ae_glass",
	},
	"mazda_rx7_fc": {
		eye = Vector3(0.3, 0.45, 0.32), wheel = Vector3(0.3, 0.18, -0.07), wheel_r = 0.185, wheel_tilt = 22.0,
		spokes = 3, wheel_style = "sport", cut = [0.0, 0.0], dash = true, seats = true, binnacle_w = 0.46,
		cluster = [["temp", -0.15, -0.01, 0.034], ["tach", 0.0, 0.004, 0.058], ["speed", 0.14, 0.0, 0.048]],
		needle = Color(1.0, 0.35, 0.1), glass = "Material.002",
	},
	"ferrari_f40": {
		eye = Vector3(-0.3, 0.38, 0.06), wheel = Vector3(-0.29, 0.12, -0.445), wheel_r = 0.165, wheel_tilt = 27.0,
		spokes = 3, wheel_style = "momo", cut = [0.2, 0.07],
		gauges = [["speed", Vector3(-0.39, 0.2, -0.66), 0.042], ["tach", Vector3(-0.29, 0.2, -0.66), 0.042],
			["boost", Vector3(-0.06, 0.115, -0.625), 0.028], ["oil", Vector3(0.02, 0.115, -0.625), 0.028],
			["temp", Vector3(0.095, 0.115, -0.625), 0.028]],
		needle = Color(1.0, 0.4, 0.12), glass = ["F40_Glass", "F40_Window"], rear_glass = 2.9,
	},
}

const WHEEL_RATIO := 13.0 ## steering wheel turns this much more than the road wheels
const MIRROR_SIZE := Vector2(0.19, 0.058)
const MIRROR_RES := Vector2i(384, 112)

var car: Car
var spec: Dictionary
var active := false
var eye := Vector3.ZERO
var has_glass := false ## found a windscreen for the rain plane
var mirror_enabled := true
var _mirror_cheap := false ## Medium: 10 Hz, 256x80, 60 m, no grass / crowds / particles
var hands_enabled := true
var show_cut := false ## debug: draw the removed model triangles in magenta
var probe_enabled := true ## cabin reflection probe (`--noprobe` for A/B)
var fx_enabled := true ## windscreen drops (`--nocockpitfx` for A/B)

var _wheel_root: Node3D ## hub, Y = column axis towards the driver
var _wheel_spin: Node3D ## turns with the steering
var _hands: Array = [] ## [hand node, arm nodes, side]
var _needles: Array = [] ## [node, kind, radius]
var _gauge_mats: Array[StandardMaterial3D] = []
var _model: MeshInstance3D
var _body_full: Mesh
var _body_cut: Mesh
var _screen: MeshInstance3D
var _screen_mat: ShaderMaterial
var _wipers: Array[Node3D] = []
var _wiper_t := 0.0
var _wiping := false
var _idle := 0.0
var _wipe_dir := 1.0 ## 1: blades park pointing right and sweep anticlockwise; -1 mirrored (RHD)
var _mirror_vp: SubViewport
var _mirror_cam: Camera3D
var _mirror_glass: MeshInstance3D
var _mirror_frame := 0
var _fuel := 0.8
var _temp := 0.2
var _wheel_angle := 0.0
var _faces: Array[Control] = []
var _lit := false
var _ambient_t := 0.0


static func spec_for(model_id: String) -> Dictionary:
	return SPECS.get(model_id, SPECS[CarCatalog.DEFAULT])


func _ready() -> void:
	name = "Cockpit"
	spec = spec_for(car.model_id)
	eye = spec.eye
	# Costly extras follow the graphics preset (or a Game setting when one exists):
	# the live mirror and the cabin probe from High up; arms are opt-in.
	var q: int = Game.quality
	# Rear-view mirror: live and full on High+, live but cheap on Medium, a static
	# reflection on Low or with Settings > Game > Rear-view mirror off.
	# A live mirror re-renders the scene incl. its shadow cascades (no per-viewport
	# shadow switch): ~6 ms spikes even at 10 Hz on an M1. So: live on High+,
	# the static reflection on Medium / Low. `--mirror` = cheap live mirror anyway.
	mirror_enabled = _setting("cockpit_mirror", true) and q >= 2
	_mirror_cheap = q <= 1
	probe_enabled = false # replaced by the material dimming (see _dim_cabin); `--probe` for A/B
	hands_enabled = _setting("cockpit_hands", false)
	for arg in OS.get_cmdline_user_args():
		match arg:
			"--nomirror": mirror_enabled = false
			"--mirror": mirror_enabled = true
			"--fullmirror":
				mirror_enabled = true
				_mirror_cheap = false
			"--nohands": hands_enabled = false
			"--hands": hands_enabled = true
			"--probe": probe_enabled = true
			"--showcut": show_cut = true
			"--noprobe": probe_enabled = false
			"--nocockpitfx": fx_enabled = false
	_model = car.get_node_or_null("Body/Model") as MeshInstance3D
	_fuel = randf_range(0.55, 0.9)
	_build_wheel()
	_build_windscreen()
	_cut_body()
	if spec.get("dash", false):
		_build_dash()
	_build_gauges()
	if hands_enabled:
		_build_hands()
	_build_mirror()
	_build_cabin_light()
	_merge_static()
	_dim_cabin(true)
	_cabin_tris = PackedVector3Array()
	set_active(false)


static func _setting(key: String, fallback: bool) -> bool:
	var v = Game.get(key)
	return fallback if v == null else bool(v)


func set_active(on: bool) -> void:
	active = on
	visible = on
	if _model and _body_cut:
		_model.mesh = _body_cut if on else _body_full
	_clear_glass(on)
	_shield(on)
	if on and _probe: # re-capture the cabin now that it's showing
		_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	if _mirror_vp:
		_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(on)


## The driver's eye in car space, looking forward (and a touch down at the road).
func eye_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-5.0)), eye)


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_update_wheel(dt)
	_update_gauges(dt)
	_update_windscreen(dt)
	_update_mirror()


# ---------------------------------------------------------------- steering wheel

func _column_basis() -> Basis:
	var t := deg_to_rad(float(spec.wheel_tilt))
	var axis := Vector3(0.0, sin(t), cos(t)) # towards the driver, rising
	var x := Vector3.RIGHT
	return Basis(x, axis, x.cross(axis)) # local Y = column axis, -Z = up the wheel face


func _build_wheel() -> void:
	var r: float = spec.wheel_r
	_wheel_root = Node3D.new()
	_wheel_root.name = "SteeringWheel"
	_wheel_root.transform = Transform3D(_column_basis(), spec.wheel)
	add_child(_wheel_root)
	_wheel_spin = Node3D.new()
	_wheel_root.add_child(_wheel_spin)

	var style: String = spec.get("wheel_style", "sport")
	var rim_mat := _mat(Color(0.08, 0.072, 0.066), 0.42, 0.0) # worn leather: a little sheen on top
	if style == "wood":
		rim_mat = _mat(Color(0.2, 0.09, 0.035), 0.32, 0.0)
		rim_mat.clearcoat_enabled = true
		rim_mat.clearcoat = 0.6
	rim_mat.normal_enabled = true
	rim_mat.normal_texture = _grain_normal()
	rim_mat.normal_scale = 0.35
	rim_mat.uv1_scale = Vector3(6, 1, 1)
	var spoke_mat := _mat(Color(0.55, 0.56, 0.58), 0.32, 0.9) if style in ["momo", "wood"] else _mat(Color(0.03, 0.03, 0.03), 0.5, 0.2)
	var dark := _mat(Color(0.02, 0.02, 0.02), 0.45, 0.1)

	var thick := 0.016 if style != "porsche" else 0.018
	var rim := TorusMesh.new()
	rim.inner_radius = r - thick
	rim.outer_radius = r + thick
	rim.rings = 48
	rim.ring_segments = 12
	_mesh(_wheel_spin, rim, rim_mat)

	# Spokes in the wheel plane (X right, -Z up); angles from 3 o'clock, CCW seen by the driver.
	var angles: Array = [0.0, 180.0, 270.0] if spec.spokes == 3 else ([0.0, 180.0] if spec.spokes == 2 else [35.0, 145.0, 215.0, 325.0])
	for a in angles:
		var d := Vector3(cos(deg_to_rad(a)), 0.0, -sin(deg_to_rad(a)))
		var sp := BoxMesh.new()
		var len := r - 0.04
		if style == "porsche":
			sp.size = Vector3(len, 0.012, 0.03)
		elif style == "momo":
			sp.size = Vector3(len, 0.006, 0.042) # flat drilled alloy spoke
		else:
			sp.size = Vector3(len, 0.014, 0.036)
		var mi := _mesh(_wheel_spin, sp, spoke_mat)
		mi.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(a)), d * (0.04 + len * 0.5) + Vector3(0, -0.012, 0))
		if style == "momo": # lightening holes: dark discs on the spoke
			for k in 2:
				var hole := CylinderMesh.new()
				hole.top_radius = 0.008
				hole.bottom_radius = 0.008
				hole.height = 0.008
				var h := _mesh(_wheel_spin, hole, dark)
				h.position = d * (0.075 + k * 0.045) + Vector3(0, -0.011, 0)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.052 if style != "porsche" else 0.075
	hub.bottom_radius = hub.top_radius + 0.006
	hub.height = 0.035
	_mesh(_wheel_spin, hub, dark).position = Vector3(0, -0.01, 0)
	var badge := CylinderMesh.new()
	badge.top_radius = 0.018
	badge.bottom_radius = 0.018
	badge.height = 0.004
	var badge_mat := _mat(Color(0.5, 0.42, 0.18), 0.55, 0.4) if style == "porsche" else _mat(Color(0.3, 0.3, 0.32), 0.55, 0.4)
	_mesh(_wheel_spin, badge, badge_mat).position = Vector3(0, 0.009, 0)
	# Column and shroud (static), running down into the dash.
	var col := CylinderMesh.new()
	col.top_radius = 0.035
	col.bottom_radius = 0.045
	col.height = 0.3
	var cm := _mesh(_wheel_root, col, dark)
	cm.position = Vector3(0, -0.17, 0)
	cm.set_meta("static", true)


func _update_wheel(dt: float) -> void:
	var want := -car.steer_angle() * WHEEL_RATIO
	_wheel_angle = lerpf(_wheel_angle, want, 1.0 - exp(-dt * 25.0))
	_wheel_spin.rotation.y = _wheel_angle
	for h in _hands:
		_pose_hand(h)


# ---------------------------------------------------------------- hands

func _build_hands() -> void:
	var glove := _mat(Color(0.03, 0.028, 0.027), 0.55, 0.0)
	glove.normal_enabled = true
	glove.normal_texture = _grain_normal()
	glove.normal_scale = 0.3
	var suit := _mat(Color(0.09, 0.1, 0.13), 0.88, 0.0) # race suit
	for side in [-1.0, 1.0]:
		var hand := Node3D.new()
		add_child(hand)
		var palm := SphereMesh.new()
		palm.radius = 0.042
		palm.height = 0.1
		palm.radial_segments = 16
		palm.rings = 8
		var p := _mesh(hand, palm, glove)
		p.scale = Vector3(0.8, 1.0, 0.95)
		var thumb := CapsuleMesh.new()
		thumb.radius = 0.012
		thumb.height = 0.055
		var th := _mesh(hand, thumb, glove)
		th.position = Vector3(-side * 0.012, 0.03, 0.028)
		th.rotation_degrees = Vector3(60, 0, side * 30.0)
		var cuff := CylinderMesh.new()
		cuff.top_radius = 0.034
		cuff.bottom_radius = 0.036
		cuff.height = 0.05
		var cf := _mesh(hand, cuff, glove)
		cf.position = Vector3(0, 0, 0.06)
		cf.rotation_degrees = Vector3(90, 0, 0)
		var fore := Node3D.new()
		add_child(fore)
		var fa := CylinderMesh.new() # height 1, stretched to the limb's length
		fa.bottom_radius = 0.036 # wrist end
		fa.top_radius = 0.046
		fa.height = 1.0
		fa.radial_segments = 16
		fa.rings = 1
		_mesh(fore, fa, suit)
		var upper := Node3D.new()
		add_child(upper)
		var ua := CylinderMesh.new()
		ua.bottom_radius = 0.047
		ua.top_radius = 0.055
		ua.height = 1.0
		ua.radial_segments = 16
		ua.rings = 1
		_mesh(upper, ua, suit)
		var joint := SphereMesh.new()
		joint.radius = 0.048
		joint.height = 0.096
		var elbow := _mesh(self, joint, suit)
		fore.set_meta("elbow", elbow)
		_hands.append([hand, fore, upper, side])


## Hands hold the rim at a quarter to three, follow the wheel for moderate
## lock and slide round the rim beyond that (a real driver would shuffle).
func _pose_hand(h: Array) -> void:
	var hand: Node3D = h[0]
	var side: float = h[3]
	var r: float = spec.wheel_r
	var turn := clampf(_wheel_angle, -deg_to_rad(110.0), deg_to_rad(110.0))
	var a := deg_to_rad(8.0) if side > 0.0 else deg_to_rad(172.0)
	a += turn # wheel-plane angle from 3 o'clock, counter-clockwise seen from the driver
	var col := _wheel_root.transform
	var on_rim := col * Vector3(cos(a) * r, 0.012, -sin(a) * r)
	var tangent := col.basis * Vector3(-sin(a), 0.0, -cos(a))
	var axis := col.basis.y
	# Hand frame: Y along the rim (fingers wrap it), Z back along the forearm.
	var out := (on_rim - col.origin).normalized()
	var back := (axis * 0.8 + out * 0.3).normalized()
	var y := tangent.normalized()
	var x := y.cross(back).normalized()
	hand.transform = Transform3D(Basis(x, y, x.cross(y)), on_rim + axis * 0.01)
	var wrist := on_rim + back * 0.085
	var shoulder := eye + Vector3(side * 0.2, -0.27, 0.2)
	var reach := shoulder.distance_to(wrist)
	var mid := (wrist + shoulder) * 0.5
	# Elbows drop and tuck out a little; the bend grows as the hand comes closer.
	var bend := sqrt(maxf(0.36 * 0.36 - reach * reach * 0.25, 0.0))
	var elbow := mid + (Vector3(side * 0.45, -1.0, 0.1)).normalized() * bend
	_limb(h[1], wrist, elbow)
	_limb(h[2], elbow, shoulder)
	(h[1].get_meta("elbow") as Node3D).position = elbow


func _limb(n: Node3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var len := d.length()
	var y := d / maxf(len, 0.001)
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.UP).normalized()
	n.transform = Transform3D(Basis(x, y * len, x.cross(y)), (a + b) * 0.5)


# ---------------------------------------------------------------- gauges

func _build_gauges() -> void:
	var needle_col: Color = spec.get("needle", Color(1.0, 0.4, 0.1))
	var top := float(CarCatalog.physics(car.model_id).get("top_speed_kmh", 250))
	var list: Array = spec.get("gauges", [])
	var on_dash := _fascia != Vector3.INF and spec.has("cluster")
	if on_dash: # procedural dash: [kind, dx, dy, r] around the binnacle centre
		list = []
		for g in spec.cluster:
			list.append([g[0], _fascia + Vector3(g[1], -0.072 + g[2], 0.034), g[3]])
	for g in list:
		var kind: String = g[0]
		var centre: Vector3 = g[1]
		var r: float = g[2]
		# Sit the dial on the model's dash: pull it in to where the eye ray meets the surface.
		var want := eye.distance_to(centre)
		var hit := -1.0 if on_dash else _ray_cabin(eye, (centre - eye) / want, want + 0.3)
		if hit > 0.05 and hit < want + 0.3:
			var k := (hit - 0.014) / want
			centre = eye + (centre - eye) * k
			r *= k
		if show_cut:
			print("gauge %s want %.3f hit %.3f -> %s r=%.3f" % [kind, want, hit, centre, r])
		var face := GaugeFace.new()
		face.kind = kind
		face.redline = car.redline_rpm
		face.top_kmh = top
		var root := Node3D.new()
		root.name = "Gauge_" + kind
		add_child(root)
		# +Z (the face normal) towards the eye.
		root.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), centre)
		# Face: a disc textured with the dial.
		var q := QuadMesh.new()
		q.size = Vector2(r * 2.0, r * 2.0)
		var fm := StandardMaterial3D.new()
		fm.albedo_texture = _face_texture(face)
		fm.roughness = 0.55
		fm.emission_enabled = true
		fm.emission_texture = fm.albedo_texture
		fm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY # backlit markings only (ADD would tint the whole face)
		fm.emission = Color(1.0, 0.93, 0.8)
		fm.emission_energy_multiplier = 0.9 if _lamps() else 0.18
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		fm.alpha_scissor_threshold = 0.5
		_gauge_mats.append(fm)
		_mesh(root, q, fm).position = Vector3(0, 0, -0.012)
		# Recessed can and a thin bezel ring.
		var can := CylinderMesh.new()
		can.top_radius = r * 1.04
		can.bottom_radius = r * 1.04
		can.height = 0.022
		can.cap_top = false
		can.cap_bottom = false
		var cm := _mat(Color(0.015, 0.015, 0.015), 0.6, 0.0)
		cm.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := _mesh(root, can, cm)
		c.set_meta("static", true)
		c.rotation_degrees.x = 90.0
		c.position = Vector3(0, 0, -0.001)
		var bez := TorusMesh.new()
		bez.inner_radius = r * 1.02
		bez.outer_radius = r * 1.1
		bez.rings = 32
		bez.ring_segments = 6
		var b := _mesh(root, bez, _mat(Color(0.25, 0.25, 0.26), 0.35, 0.8))
		b.set_meta("static", true)
		b.rotation_degrees.x = 90.0
		b.position = Vector3(0, 0, 0.009)
		b.scale = Vector3(1, 0.3, 1)
		# Needle: pivots at the centre, points along +X before rotation.
		var pivot := Node3D.new()
		root.add_child(pivot)
		pivot.position = Vector3(0, 0, -0.008)
		var nq := QuadMesh.new()
		nq.size = Vector2(r * 0.95, r * 0.045 + 0.0008)
		var nm := StandardMaterial3D.new()
		nm.albedo_color = needle_col
		nm.emission_enabled = true
		nm.emission = needle_col
		nm.emission_energy_multiplier = 1.2 if _lamps() else 0.5
		nm.roughness = 0.4
		_gauge_mats.append(nm)
		_mesh(pivot, nq, nm).position = Vector3(r * 0.95 * 0.5 - r * 0.15, 0, 0)
		var capm := CylinderMesh.new()
		capm.top_radius = r * 0.11
		capm.bottom_radius = r * 0.12
		capm.height = 0.004
		var cap := _mesh(pivot, capm, _mat(Color(0.02, 0.02, 0.02), 0.4, 0.3))
		cap.rotation_degrees.x = 90.0
		cap.position = Vector3(0, 0, 0.002)
		_needles.append([pivot, kind, face])


func _face_texture(face: GaugeFace) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	face.size = Vector2(512, 512)
	face.font = load(FONT_PATH)
	vp.add_child(face)
	add_child(vp)
	var tex := vp.get_texture()
	# Keep a static copy once drawn and drop the viewport.
	_bake(vp, tex)
	return tex


func _bake(vp: SubViewport, tex: ViewportTexture) -> void:
	await RenderingServer.frame_post_draw
	var img := tex.get_image()
	if img == null:
		return
	if show_cut:
		img.save_png("/tmp/cockpit_face_%d.png" % _faces.size())
	img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	for m in _gauge_mats:
		if m.albedo_texture == tex:
			m.albedo_texture = it
			m.emission_texture = it
	var face := vp.get_child(0)
	vp.remove_child(face) # needles keep asking it for angles
	_faces.append(face)
	vp.queue_free()


func _exit_tree() -> void:
	for f in _faces:
		f.free()
	_faces.clear()


var _mirror_flat: StandardMaterial3D ## the stand-in glass when the live mirror is off


## The stand-in mirror is unshaded: keep it about as bright as the world outside.
func _dim_flat_mirror() -> void:
	var k := clampf(_cabin_ambient() * 0.9, 0.04, 0.85)
	_mirror_flat.albedo_color = Color(k, k, k)


var _dim := -1.0


## Without the probe, the cabin's own materials are dimmed instead: the sky
## light that reaches inside a closed car is a fraction of what the open
## road gets (less in a storm, little at night). Plain albedo scaling: free.
func _dim_cabin(force: bool) -> void:
	if _probe:
		return
	var k := clampf(_cabin_ambient() * 0.6, 0.18, 0.7)
	if not force and absf(k - _dim) < 0.01:
		return
	_dim = k if _dim < 0.0 or force else lerpf(_dim, k, 0.5)
	for m: StandardMaterial3D in _mats.values():
		if not m.has_meta("base"):
			m.set_meta("base", m.albedo_color)
		var b: Color = m.get_meta("base")
		m.albedo_color = Color(b.r * _dim * 1.1, b.g * _dim * 1.1, b.b * _dim * 1.1, b.a) # ~0.6x base by day


static func _lamps() -> bool:
	return Car.headlights or Car.night


## Light inside the cabin follows the light outside (the sun's strength, which
## the weather and time of day set), well below it.
func _cabin_ambient() -> float:
	var w := Weather.current()
	var sun: float = w.sun.light_energy if w and is_instance_valid(w.sun) else 1.0
	return clampf(sun * 0.8, 0.15, 1.1) * (0.35 if Car.night else 1.0)


func _update_gauges(dt: float) -> void:
	_ambient_t -= dt
	if _ambient_t <= 0.0: # once a second: follow the light, keep the glass clear
		_ambient_t = 1.0
		if _probe:
			_probe.ambient_color_energy = lerpf(_probe.ambient_color_energy, _cabin_ambient(), 0.5)
		else:
			_dim_cabin(false)
		if _mirror_flat:
			_dim_flat_mirror()
		_clear_glass(true) # CarDirt may have swapped in its wet / dirty window material
	if _lamps() != _lit: # dusk or a storm: instrument lighting on
		_lit = _lamps()
		for m in _gauge_mats:
			var face := m.emission_texture != null
			m.emission_energy_multiplier = (0.9 if face else 1.2) if _lit else (0.18 if face else 0.5)
	var kmh := absf(car.speed) * 3.6
	_temp = move_toward(_temp, 0.55 + car.rpm / car.redline_rpm * 0.1, dt * 0.01)
	_fuel = maxf(_fuel - dt * 0.00012, 0.05)
	for n in _needles:
		var face: GaugeFace = n[2]
		var v := 0.0
		match n[1]:
			"tach": v = car.rpm / (face.max_value() * 1000.0)
			"speed": v = kmh / face.max_value()
			"oil": v = clampf(0.25 + car.rpm / car.redline_rpm * 0.6, 0.0, 1.0)
			"temp": v = _temp
			"fuel": v = _fuel
			"volt": v = 0.62 + 0.03 * sin(Time.get_ticks_msec() * 0.0007)
			"boost": v = clampf(car.throttle * smoothstep(2500.0, 5000.0, car.rpm), 0.0, 1.0) * 0.85 + 0.05
			"clock":
				var t := Time.get_time_dict_from_system()
				v = fmod(float(t.hour) + t.minute / 60.0, 12.0) / 12.0
		var pivot: Node3D = n[0]
		var want := -deg_to_rad(face.angle_at(clampf(v, 0.0, 1.02)))
		# Needles have a little mass: they chase the value instead of snapping.
		pivot.rotation.z = lerp_angle(pivot.rotation.z, want, 1.0 - exp(-dt * 18.0))


## One dial drawn in 2D: black face, white graduations, the red zone.
class GaugeFace extends Control:
	var kind := "tach"
	var redline := 7000.0
	var top_kmh := 250.0
	var font: Font
	const START := 135.0 ## degrees, screen space (clockwise from 3 o'clock)
	const SWEEP := 270.0

	func max_value() -> float:
		match kind:
			"tach": return ceilf((redline + 400.0) / 1000.0)
			"speed": return maxf(ceilf(top_kmh * 1.1 / 20.0) * 20.0, 200.0)
		return 1.0

	func sweep() -> float:
		return SWEEP if kind in ["tach", "speed", "clock"] else 90.0

	func start() -> float:
		match kind:
			"clock": return -90.0
			"tach", "speed": return START
		return 225.0 # minor dials: a 90-degree arc across the top

	## Screen angle (deg) of a 0..1 value.
	func angle_at(v: float) -> float:
		if kind == "clock":
			return -90.0 + v * 360.0
		return start() + v * sweep()

	func _draw() -> void:
		var c := size * 0.5
		var R := size.x * 0.5
		draw_circle(c, R * 0.995, Color(0.03, 0.03, 0.032))
		draw_arc(c, R * 0.97, 0.0, TAU, 96, Color(0.3, 0.3, 0.3), 3.0, true)
		var white := Color(0.94, 0.94, 0.9)
		match kind:
			"tach": _dial(c, R, max_value(), 1.0, 0.5, redline / 1000.0, "x1000/min")
			"speed": _dial(c, R, max_value(), 20.0 if max_value() <= 240.0 else 20.0, 10.0, INF, "km/h")
			"clock":
				for i in 60:
					var a := deg_to_rad(i * 6.0)
					var d := Vector2(cos(a), sin(a))
					var big := i % 5 == 0
					draw_line(c + d * R * (0.72 if big else 0.8), c + d * R * 0.88, white, 10.0 if big else 3.0, true)
				_label(c + Vector2(0, R * 0.42), "AUREL", 34, Color(0.7, 0.7, 0.7))
			_:
				var names := {oil = ["OEL", "bar"], temp = ["TEMP", "°C"], fuel = ["FUEL", "1/1"], volt = ["VOLT", "V"], boost = ["TURBO", "bar"]}
				var nm: Array = names.get(kind, ["", ""])
				for i in 5:
					var a := deg_to_rad(start() + i * sweep() / 4.0)
					var d := Vector2(cos(a), sin(a))
					draw_line(c + d * R * 0.66, c + d * R * 0.88, white, 9.0 if i % 2 == 0 else 5.0, true)
				if kind in ["temp", "oil"]:
					draw_arc(c, R * 0.83, deg_to_rad(start() + sweep() * 0.85), deg_to_rad(start() + sweep()), 16, Color(0.85, 0.08, 0.05), 18.0, true)
				_label(c + Vector2(0, R * 0.2), nm[0], 64, white)
				_label(c + Vector2(0, R * 0.5), nm[1], 40, Color(0.7, 0.7, 0.7))

	func _dial(c: Vector2, R: float, top: float, major: float, minor: float, red: float, unit: String) -> void:
		var white := Color(0.94, 0.94, 0.9)
		var red_col := Color(0.85, 0.08, 0.05)
		if red < top:
			draw_arc(c, R * 0.84, deg_to_rad(start() + red / top * sweep()), deg_to_rad(start() + sweep()), 32, red_col, 26.0, true)
		var n := int(round(top / minor))
		for i in n + 1:
			var v := i * minor
			var a := deg_to_rad(start() + v / top * sweep())
			var d := Vector2(cos(a), sin(a))
			var is_major := is_zero_approx(fmod(v, major)) or fmod(v, major) > major - 0.001
			var col := red_col if v >= red else white
			draw_line(c + d * R * (0.74 if is_major else 0.82), c + d * R * 0.9, col, 9.0 if is_major else 4.0, true)
			if is_major:
				var every := 2 if kind == "speed" and top > 200.0 else 1
				if int(round(v / major)) % every == 0:
					_label(c + d * R * 0.56, str(int(v)), 58 if kind == "tach" else 44, col)
		_label(c + Vector2(0, R * 0.36), unit, 26, Color(0.65, 0.65, 0.65))

	func _label(p: Vector2, text: String, fsize: int, col: Color) -> void:
		if font == null:
			return
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		draw_string(font, p + Vector2(-w * 0.5, fsize * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


# ---------------------------------------------------------------- dashboard (models without one)

var _glass_top := Vector3.INF ## top-centre of the windscreen
var _glass_n := Vector3.FORWARD
var _glass_w := 1.3
var _cowl := Vector3.INF ## bottom-centre of the windscreen (car space), from the glass fit
var _fascia := Vector3.INF ## driver-side top edge of the procedural dash's instrument face


## [cowl, half width]; sets _fascia (driver-side top edge of the instrument face).
func _dash_geom() -> Array:
	var w: Vector3 = spec.wheel
	var cowl := _cowl if _cowl != Vector3.INF else w + Vector3(0, 0.2, -0.42)
	var half := float(spec.get("dash_half", 0.7))
	var ze: float = w.z - float(spec.get("fascia_back", 0.2)) # instrument face, towards the driver
	var ye: float = minf(cowl.y + float(spec.get("dash_rise", 0.035)), eye.y - 0.1)
	_fascia = Vector3(w.x, ye, ze)
	return [cowl, half]


## An 80s dashboard: a vinyl top pad under the windscreen rolling over into
## an upright fascia, a hooded binnacle for the dials, a centre stack and the
## gear lever. Fitted to the windscreen base, so it meets the glass.
func _build_dash() -> void:
	var first := get_child_count()
	var vinyl := _mat(Color(0.052, 0.052, 0.055), 0.7, 0.0)
	vinyl.normal_enabled = true
	vinyl.normal_texture = _grain_normal()
	vinyl.normal_scale = 0.22
	vinyl.uv1_triplanar = true
	vinyl.uv1_scale = Vector3(10, 10, 10)
	var trim := _mat(Color(0.075, 0.075, 0.078), 0.6, 0.0)
	var dark := _mat(Color(0.012, 0.012, 0.012), 0.85, 0.0)
	var w: Vector3 = spec.wheel
	var g := _dash_geom()
	var cowl: Vector3 = g[0]
	var half: float = g[1]
	var ze: float = _fascia.z
	var ye: float = _fascia.y
	# The top pad runs right up under the glass base, so no scuttle panel of the
	# model peeks over it.
	var body := PackedVector2Array([
		Vector2(cowl.z - 0.06, cowl.y - 0.04), Vector2(cowl.z + 0.05, cowl.y + 0.025), Vector2(ze - 0.07, ye), Vector2(ze - 0.02, ye - 0.01),
		Vector2(ze + 0.0, ye - 0.04), Vector2(ze + 0.01, ye - 0.21), Vector2(ze + 0.045, ye - 0.27),
		Vector2(ze + 0.04, ye - 0.33), Vector2(cowl.z - 0.03, ye - 0.33)])
	_extrude(body, -half, half, vinyl)
	# Binnacle hood over the dials: a thin curved shell.
	var gw := float(spec.get("binnacle_w", 0.42))
	# A low brow: enough to shade the glass, not a box on the dash.
	var hood := PackedVector2Array([
		Vector2(ze - 0.06, ye - 0.004), Vector2(ze - 0.03, ye + 0.028), Vector2(ze + 0.02, ye + 0.032),
		Vector2(ze + 0.042, ye + 0.02), Vector2(ze + 0.032, ye + 0.016), Vector2(ze + 0.012, ye + 0.022),
		Vector2(ze - 0.02, ye + 0.018), Vector2(ze - 0.04, ye - 0.004)])
	_extrude(hood, w.x - gw * 0.5, w.x + gw * 0.5, vinyl)
	# Instrument panel: a matt black plate on the fascia behind the dials, under the hood.
	var panel := PackedVector2Array([
		Vector2(ze + 0.002, ye + 0.012), Vector2(ze + 0.01, ye + 0.012), Vector2(ze + 0.014, ye - 0.14), Vector2(ze + 0.006, ye - 0.14)])
	_extrude(panel, w.x - gw * 0.5 + 0.005, w.x + gw * 0.5 - 0.005, dark)
	# Centre stack with a radio and heater controls, down to the tunnel.
	var stack := PackedVector2Array([
		Vector2(ze - 0.05, ye - 0.05), Vector2(ze + 0.02, ye - 0.05), Vector2(ze + 0.06, ye - 0.45),
		Vector2(ze + 0.5, ye - 0.62), Vector2(ze + 0.5, ye - 0.75), Vector2(ze - 0.05, ye - 0.75)])
	_extrude(stack, -0.14, 0.14, vinyl)
	var radio := BoxMesh.new()
	radio.size = Vector3(0.18, 0.05, 0.01)
	var rm := _mesh(self, radio, dark)
	rm.position = Vector3(0, ye - 0.14, ze + 0.028)
	rm.rotation.x = -atan2(0.4, 0.04) + PI * 0.5
	var knob := CylinderMesh.new()
	knob.top_radius = 0.009
	knob.bottom_radius = 0.01
	knob.height = 0.012
	var chrome := _mat(Color(0.6, 0.6, 0.62), 0.3, 0.9)
	for kx in [-0.075, 0.075]:
		var k := _mesh(self, knob, chrome)
		k.position = Vector3(kx, ye - 0.14, ze + 0.036)
		k.rotation_degrees.x = 90.0 - rad_to_deg(atan2(0.04, 0.4))
	for i in 3:
		var hk := _mesh(self, knob, trim)
		hk.position = Vector3(-0.06 + i * 0.06, ye - 0.24, ze + 0.047)
		hk.rotation_degrees.x = 84.0
	# Air vents: dark slots with slats, both ends of the dash and centre.
	for vx in [-0.06, 0.06, -half + 0.12, half - 0.12]:
		var v := BoxMesh.new()
		v.size = Vector3(0.085, 0.04, 0.012)
		var vm := _mesh(self, v, dark)
		vm.position = Vector3(vx, ye - 0.07, ze + 0.008 + (0.0 if absf(vx) < 0.2 else -0.004))
		for k in 3:
			var slat := BoxMesh.new()
			slat.size = Vector3(0.08, 0.003, 0.012)
			_mesh(self, slat, trim).position = vm.position + Vector3(0, -0.012 + k * 0.012, 0.004)
	# Glovebox seam on the passenger side.
	var gx := -signf(w.x) * 0.38
	var seam := BoxMesh.new()
	seam.size = Vector3(0.36, 0.004, 0.004)
	_mesh(self, seam, dark).position = Vector3(gx, ye - 0.2, ze + 0.013)
	_mesh(self, seam, dark).position = Vector3(gx, ye - 0.08, ze + 0.005)
	# Gear lever in a leather boot on the tunnel.
	var boot := CylinderMesh.new()
	boot.top_radius = 0.02
	boot.bottom_radius = 0.07
	boot.height = 0.08
	var lever_base := Vector3(0.0, ye - 0.6, eye.z - 0.3)
	_mesh(self, boot, vinyl).position = lever_base
	var stick := CylinderMesh.new()
	stick.top_radius = 0.007
	stick.bottom_radius = 0.009
	stick.height = 0.24
	var st := _mesh(self, stick, chrome)
	st.position = lever_base + Vector3(0, 0.12, 0.01)
	st.rotation_degrees.x = 6.0
	var ball := SphereMesh.new()
	ball.radius = 0.024
	ball.height = 0.048
	_mesh(self, ball, dark).position = lever_base + Vector3(0, 0.245, 0.024)
	_build_trim(cowl, vinyl)
	for i in range(first, get_child_count()):
		get_child(i).set_meta("static", true)


## Door cards (the shell's doors are bare painted metal inside) and a pair of
## plain bucket seats, for models that come without them.
func _build_trim(cowl: Vector3, vinyl: Material) -> void:
	var cloth := _mat(Color(0.05, 0.048, 0.046), 0.95, 0.0)
	var inner := float(spec.get("door_x", _glass_w * 0.5 + 0.015))
	var belt := cowl.y + 0.02
	for side in [-1.0, 1.0]:
		var card := PackedVector2Array([
			Vector2(cowl.z + 0.12, belt), Vector2(eye.z + 0.45, belt), Vector2(eye.z + 0.45, belt - 0.55),
			Vector2(cowl.z + 0.2, belt - 0.55)])
		var x0: float = side * inner
		_extrude(card, minf(x0, x0 + side * 0.03), maxf(x0, x0 + side * 0.03), vinyl)
		# Armrest / pull.
		var rest := PackedVector2Array([Vector2(eye.z - 0.35, belt - 0.2), Vector2(eye.z + 0.1, belt - 0.2),
			Vector2(eye.z + 0.1, belt - 0.25), Vector2(eye.z - 0.3, belt - 0.26)])
		_extrude(rest, minf(side * (inner - 0.06), side * inner), maxf(side * (inner - 0.06), side * inner), vinyl)
	if not spec.get("seats", false):
		return
	for sx in [eye.x, -eye.x]:
		var seat_z := eye.z + 0.2
		var floor_y := eye.y - 0.85
		var cushion := BoxMesh.new()
		cushion.size = Vector3(0.48, 0.12, 0.48)
		_mesh(self, cushion, cloth).position = Vector3(sx, floor_y + 0.26, seat_z - 0.3)
		var back := BoxMesh.new()
		back.size = Vector3(0.48, 0.62, 0.12)
		var b := _mesh(self, back, cloth)
		b.position = Vector3(sx, floor_y + 0.62, seat_z + 0.02)
		b.rotation_degrees.x = 14.0
		for bx in [-0.21, 0.21]: # side bolsters
			var bol := BoxMesh.new()
			bol.size = Vector3(0.07, 0.5, 0.16)
			var bm := _mesh(self, bol, cloth)
			bm.position = Vector3(sx + bx, floor_y + 0.6, seat_z)
			bm.rotation_degrees.x = 14.0
		var head := BoxMesh.new()
		head.size = Vector3(0.26, 0.17, 0.09)
		var h := _mesh(self, head, cloth)
		h.position = Vector3(sx, floor_y + 1.02, seat_z + 0.12)
		h.rotation_degrees.x = 10.0


## Extrudes a closed (z, y) profile across x0..x1 with end caps, smooth sides.
func _extrude(profile: PackedVector2Array, x0: float, x1: float, m: Material) -> MeshInstance3D:
	var n := profile.size()
	var area := 0.0
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	# Per-edge outward normals, averaged at corners gentler than ~50 degrees.
	var en: Array[Vector2] = []
	for i in n:
		var d := profile[(i + 1) % n] - profile[i]
		en.append(Vector2(d.y, -d.x).normalized() * sgn)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var a := profile[i]
		var b := profile[(i + 1) % n]
		var na := en[i]
		var nb := en[i]
		var prev := en[(i - 1 + n) % n]
		var next := en[(i + 1) % n]
		if prev.dot(na) > 0.64:
			na = (prev + na).normalized()
		if next.dot(nb) > 0.64:
			nb = (next + nb).normalized()
		var pa0 := Vector3(x0, a.y, a.x)
		var pa1 := Vector3(x1, a.y, a.x)
		var pb0 := Vector3(x0, b.y, b.x)
		var pb1 := Vector3(x1, b.y, b.x)
		var n3a := Vector3(0, na.y, na.x)
		var n3b := Vector3(0, nb.y, nb.x)
		_quad(st, [pa0, pb0, pb1, pa1], [n3a, n3b, n3b, n3a])
	var tris := Geometry2D.triangulate_polygon(profile)
	for cap in [[x0, -1.0], [x1, 1.0]]:
		var nx := Vector3(cap[1], 0, 0)
		for t in range(0, tris.size(), 3):
			var p := [profile[tris[t]], profile[tris[t + 1]], profile[tris[t + 2]]]
			var v := [Vector3(cap[0], p[0].y, p[0].x), Vector3(cap[0], p[1].y, p[1].x), Vector3(cap[0], p[2].y, p[2].x)]
			var fn: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
			if fn.dot(nx) < 0.0: # counter-clockwise seen from outside = front face here
				v = [v[0], v[2], v[1]]
			for k in 3:
				st.set_normal(nx)
				st.set_uv(Vector2(v[k].z, v[k].y))
				st.add_vertex(v[k])
	# Normal-mapped materials need tangents (a mesh without them isn't drawn on Metal).
	st.generate_tangents()
	var mi := _mesh(self, st.commit(), m)
	return mi


func _quad(st: SurfaceTool, p: Array, nrm: Array) -> void:
	# Wind so the face points along its normals.
	var fn: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	var order := [0, 1, 2, 0, 2, 3] if fn.dot(nrm[0] + nrm[2]) > 0.0 else [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_normal(nrm[k])
		st.set_uv(Vector2(p[k].x, p[k].y + p[k].z))
		st.add_vertex(p[k])


# ---------------------------------------------------------------- body cut

var _cabin_tris := PackedVector3Array() ## body triangles around the dash (car space), for rays


## Distance along a ray (car space) to the first body triangle, or -1.
func _ray_cabin(from: Vector3, dir: Vector3, max_d: float) -> float:
	if _cabin_tris.is_empty():
		var mesh: Mesh = _body_cut if _body_cut else (_model.mesh if _model else null)
		if mesh == null:
			return -1.0
		var off := _model.position
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var mat := mesh.surface_get_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue # glass
			for t in range(0, idx.size(), 3):
				var a := v[idx[t]] + off
				if a.z > eye.z or a.z < eye.z - 1.3 or a.y < eye.y - 0.6 or a.y > eye.y + 0.1:
					continue
				_cabin_tris.append_array([a, v[idx[t + 1]] + off, v[idx[t + 2]] + off])
	var best := -1.0
	for i in range(0, _cabin_tris.size(), 3):
		var a := _cabin_tris[i]
		var e1 := _cabin_tris[i + 1] - a
		var e2 := _cabin_tris[i + 2] - a
		var pv := dir.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-9:
			continue
		var inv := 1.0 / det
		var tv := from - a
		var u := tv.dot(pv) * inv
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var w := dir.dot(qv) * inv
		if w < 0.0 or u + w > 1.0:
			continue
		var d := e2.dot(qv) * inv
		if d > 0.0 and d < max_d and (best < 0.0 or d < best):
			best = d
	return best

## A copy of the body without the model's own (static) steering wheel.
func _cut_body() -> void:
	if _model == null or not (_model.mesh is ArrayMesh):
		return
	_body_full = _model.mesh
	var cut: Array = spec.get("cut", [0.0, 0.0])
	# The model's own rear-view mirror: ours hangs in its place.
	var mirror_box := AABB()
	if _glass_top != Vector3.INF:
		mirror_box = AABB(Vector3(-0.22, _glass_top.y - 0.26, _glass_top.z - 0.15), Vector3(0.44, 0.28, 0.45))
		mirror_box.position -= _model.position
	# A procedural dash replaces the model's: clear what would poke through it.
	var dash_box := AABB()
	if spec.get("dash", false):
		var g := _dash_geom()
		var cowl: Vector3 = g[0]
		var hw: float = g[1] - 0.1
		dash_box = AABB(Vector3(-hw, _fascia.y - 0.5, cowl.z - 0.03), Vector3(hw * 2.0, cowl.y + 0.12 - (_fascia.y - 0.5), _fascia.z + 0.1 - (cowl.z - 0.03)))
		dash_box.position -= _model.position
	if float(cut[0]) <= 0.0 and not mirror_box.has_volume() and not dash_box.has_volume():
		return
	var src := _body_full as ArrayMesh
	# The model's own wheel may sit elsewhere than ours: spec cut_at = its hub.
	var hub_frame := Transform3D(_column_basis(), spec.get("cut_at", spec.wheel))
	var inv := _model.transform.affine_inverse() * hub_frame # hub frame in model space
	var hub := inv.origin
	var axis := inv.basis.y.normalized()
	var rad: float = cut[0]
	var half: float = cut[1]
	var out := ArrayMesh.new()
	var removed := PackedVector3Array()
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx.resize(v.size())
			for k in v.size():
				idx[k] = k
		var keep := PackedInt32Array()
		var sm := src.surface_get_material(s)
		var glassy := sm is BaseMaterial3D and (sm as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		for t in range(0, idx.size(), 3):
			var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0 - hub
			var a := c.dot(axis)
			var radial := (c - axis * a).length()
			if (absf(a) < half and radial < rad) or (not glassy and (mirror_box.has_point(c + hub) or dash_box.has_point(c + hub))):
				if show_cut:
					removed.append_array([v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]])
				continue
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
		if keep.is_empty():
			keep = PackedInt32Array([0, 0, 0])
		arr[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, src.surface_get_material(s))
	_body_cut = out
	if show_cut and removed.size() > 0:
		var dbg := ArrayMesh.new()
		var a2 := []
		a2.resize(Mesh.ARRAY_MAX)
		a2[Mesh.ARRAY_VERTEX] = removed
		dbg.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1, 0, 1)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := _mesh(self, dbg, m)
		mi.transform = _model.transform
	print("cockpit %s: cut %d tris" % [car.model_id, removed.size() / 3])


# ---------------------------------------------------------------- windscreen rain / snow

## Fits a plane to the model's windscreen glass and lays a drop layer just
## inside it. The shader draws only where the scene behind is far away (the
## world through the glass), so pillars and the dash stay dry.
func _build_windscreen() -> void:
	var d := CarModel.data(car.model_id)
	var keys = spec.get("glass", "")
	if keys is String:
		keys = [keys]
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for key in keys:
		var si: int = d.surface_keys.find(key)
		if si < 0:
			continue
		var arr: Array = (d.body as ArrayMesh).surface_get_arrays(si)
		var base := v.size()
		v.append_array(arr[Mesh.ARRAY_VERTEX])
		for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)
	if idx.is_empty() or _model == null:
		return
	var off := _model.position
	var n_sum := Vector3.ZERO
	var pts := PackedVector3Array()
	var area_sum := 0.0
	var c_sum := Vector3.ZERO
	for t in range(0, idx.size(), 3):
		var a := v[idx[t]] + off
		var b := v[idx[t + 1]] + off
		var c := v[idx[t + 2]] + off
		var n := (b - a).cross(c - a)
		var area := n.length() * 0.5
		if area < 1e-6:
			continue
		n = n.normalized()
		if n.z > 0.0:
			n = -n # face forward-up
		var ctr := (a + b + c) / 3.0
		# The windscreen: ahead of the eye, above the dash, facing forward and up.
		if ctr.z > eye.z - 0.25 or ctr.z < eye.z - 1.2 or ctr.y < eye.y - 0.3 or n.z > -0.15 or absf(n.x) > 0.5 or absf(ctr.x) > 0.75:
			continue
		n_sum += n * area
		c_sum += ctr * area
		area_sum += area
		pts.append_array([a, b, c])
	if area_sum < 0.05:
		print("cockpit %s: no windscreen found (%.3f m2)" % [car.model_id, area_sum])
		return
	var normal := n_sum.normalized() # points out of the car (forward/up)
	var centre := c_sum / area_sum
	var right := Vector3.RIGHT
	var up := normal.cross(right).normalized() # along the glass, towards the roof
	if up.y < 0.0:
		up = -up
	right = up.cross(normal).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := Vector2((p - centre).dot(right), (p - centre).dot(up))
		lo = lo.min(q)
		hi = hi.max(q)
	var size := hi - lo
	var mid := centre + right * (lo.x + hi.x) * 0.5 + up * (lo.y + hi.y) * 0.5 - normal * 0.012
	has_glass = true
	_cowl = mid - up * size.y * 0.5
	_glass_w = size.x
	_glass_top = mid + up * size.y * 0.5
	_glass_n = normal
	if show_cut:
		print("cockpit %s: glass %s x %s, cowl %s, top %s" % [car.model_id, mid.snapped(Vector3.ONE * 0.01), size.snapped(Vector2.ONE * 0.01), _cowl.snapped(Vector3.ONE * 0.01), _glass_top.snapped(Vector3.ONE * 0.01)])
	var frame := Node3D.new()
	frame.name = "Windscreen"
	# Local: X right, Y up the glass, Z = into the cabin.
	frame.transform = Transform3D(Basis(right, up, -normal), mid)
	add_child(frame)
	var q := QuadMesh.new()
	q.size = size
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = RAIN_SHADER
	_screen_mat.set_shader_parameter("glass_size", size)
	_screen_mat.render_priority = 1
	_screen = _mesh(frame, q, _screen_mat)
	_screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# QuadMesh faces +Z: flip it to face the driver (local +Z is into the cabin already).
	# Wipers: two arms parked along the bottom edge, pivots below the glass.
	var bottom := -size.y * 0.5
	var rhd := eye.x > 0.0
	var pivots := [Vector2(-size.x * 0.28, bottom - 0.04), Vector2(size.x * 0.2, bottom - 0.04)]
	if rhd:
		pivots = [Vector2(size.x * 0.28, bottom - 0.04), Vector2(-size.x * 0.2, bottom - 0.04)] # mirrored: park to the left
	var arm_len := size.x * 0.44
	_screen_mat.set_shader_parameter("wiper_a", pivots[0] / size + Vector2(0.5, 0.5))
	_screen_mat.set_shader_parameter("wiper_b", pivots[1] / size + Vector2(0.5, 0.5))
	_screen_mat.set_shader_parameter("wiper_len", arm_len)
	_screen_mat.set_shader_parameter("wipe_dir", -1.0 if rhd else 1.0)
	_wipe_dir = -1.0 if rhd else 1.0
	var blade_mat := _mat(Color(0.02, 0.02, 0.02), 0.5, 0.3)
	for p in pivots:
		var piv := Node3D.new()
		frame.add_child(piv)
		piv.position = Vector3(p.x, p.y, 0.0)
		var arm := BoxMesh.new()
		arm.size = Vector3(arm_len * 0.98, 0.012, 0.012)
		_mesh(piv, arm, blade_mat).position = Vector3(arm_len * 0.49 * _wipe_dir, 0.0, -0.004)
		var blade := BoxMesh.new()
		blade.size = Vector3(arm_len * 0.85, 0.01, 0.016)
		_mesh(piv, blade, blade_mat).position = Vector3(arm_len * 0.55 * _wipe_dir, 0.0, 0.0)
		piv.set_meta("park", 0.0)
		_wipers.append(piv)
	for wp in _wipers:
		wp.visible = true


## The wiper cycle (shared with the shader, which clears what a blade has passed).
const WIPE_PERIOD := 1.25
const WIPE_SWEEP := 1.0 ## seconds of the period the blades move; the rest they rest
const WIPE_ANGLE := 1.9 ## radians swept from the parked position


func _update_windscreen(dt: float) -> void:
	if _screen_mat == null:
		return
	var w := Weather.current() if Weather.current() else null
	var rain := 0.0
	var snow := 0.0
	if w:
		rain = w.rain
		snow = w.snowfall
	elif Car.weather_road_grip < 0.9:
		if Car.weather_off_grip < 0.6:
			snow = 1.0
		else:
			rain = 1.0
	var kmh := absf(car.speed) * 3.6
	_wiping = rain > 0.05 or snow > 0.05
	if _wiping:
		_wiper_t += dt
	elif fmod(_wiper_t, WIPE_PERIOD) > 0.001: # finish the stroke, then park
		var c := fmod(_wiper_t, WIPE_PERIOD)
		_wiper_t += minf(dt, WIPE_PERIOD - c) if c < WIPE_SWEEP else WIPE_PERIOD - c
	_idle = 0.0 if _wiping else _idle + dt
	var s := _wipe_pos(_wiper_t)
	for k in _wipers.size():
		_wipers[k].rotation.z = s * WIPE_ANGLE * _wipe_dir
	_screen_mat.set_shader_parameter("wipe_time", _wiper_t)
	_screen_mat.set_shader_parameter("wiping", 1.0 if _wiping else 0.0)
	_screen_mat.set_shader_parameter("idle", _idle)
	_screen_mat.set_shader_parameter("rain", rain)
	_screen_mat.set_shader_parameter("snow", snow)
	_screen_mat.set_shader_parameter("speed", clampf(kmh / 150.0, 0.0, 1.0))
	_screen.visible = fx_enabled and (rain > 0.01 or snow > 0.01)
	if show_cut and Engine.get_process_frames() % 120 == 0:
		print("windscreen rain=%.2f snow=%.2f visible=%s wipe=%.2f kmh=%d" % [rain, snow, _screen.visible, _wiper_t, kmh])


## 0 parked .. 1 fully swept, for a cycle time t.
static func _wipe_pos(t: float) -> float:
	var c := fmod(t, WIPE_PERIOD)
	if c >= WIPE_SWEEP:
		return 0.0
	return 0.5 - 0.5 * cos(TAU * c / WIPE_SWEEP)


# ---------------------------------------------------------------- rear-view mirror

func _build_mirror() -> void:
	var p: Vector3 = spec.get("mirror", eye + Vector3(-eye.x, 0.2, -0.55))
	if not spec.has("mirror") and _glass_top != Vector3.INF:
		# Hangs from the top of the windscreen, just inside the glass and slightly
		# towards the driver, but never so high it leaves the driver's view.
		var y := minf(_glass_top.y - 0.07, eye.y + 0.15)
		var k := clampf((y - _cowl.y) / maxf(_glass_top.y - _cowl.y, 0.01), 0.0, 1.0)
		var on_glass := _cowl.lerp(_glass_top, k)
		p = Vector3(signf(eye.x) * 0.03, y, on_glass.z + 0.05)
	var root := Node3D.new()
	root.name = "Mirror"
	add_child(root)
	# Angle the glass so the driver sees straight back through the rear window.
	var to_eye := (eye - p).normalized()
	var behind := Vector3(0, -0.05, 1).normalized()
	var n := (to_eye + behind).normalized()
	root.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), p) # -Z away from the driver
	var housing := BoxMesh.new()
	housing.size = Vector3(MIRROR_SIZE.x + 0.02, MIRROR_SIZE.y + 0.018, 0.035)
	_mesh(root, housing, _mat(Color(0.03, 0.03, 0.03), 0.6, 0.0)).position = Vector3(0, 0, -0.02)
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.008
	stalk.bottom_radius = 0.01
	stalk.height = 0.07
	_mesh(root, stalk, _mat(Color(0.03, 0.03, 0.03), 0.5, 0.0)).position = Vector3(0, 0.06, -0.03)
	var q := QuadMesh.new()
	q.size = MIRROR_SIZE
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(0.82, 0.83, 0.85)
	_mirror_glass = _mesh(root, q, gm)
	_mirror_glass.position = Vector3(0, 0, 0.0)
	_mirror_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not mirror_enabled:
		# No live view: a plain silvered glass with a hint of bright rear window
		# above a darker cabin, never a black hole.
		# Static, softly blurred: the rear window frame, sky, horizon, road.
		var g := Gradient.new()
		g.set_color(0, Color(0.1, 0.1, 0.11))
		g.set_color(1, Color(0.2, 0.2, 0.21))
		g.add_point(0.12, Color(0.62, 0.68, 0.76))
		g.add_point(0.5, Color(0.8, 0.82, 0.84))
		g.add_point(0.6, Color(0.42, 0.43, 0.44))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		gt.width = 4
		gt.height = 32
		gm.albedo_texture = gt
		_mirror_flat = gm
		_dim_flat_mirror()
		return
	_mirror_vp = SubViewport.new()
	_mirror_vp.size = Vector2i(256, 80) if _mirror_cheap else MIRROR_RES
	_mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	_mirror_vp.positional_shadow_atlas_size = 0
	_mirror_vp.mesh_lod_threshold = 6.0
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mirror_vp)
	_mirror_cam = Camera3D.new()
	_mirror_cam.far = 60.0 if _mirror_cheap else 120.0 # a glance back: near traffic, not the scenery
	# Grass, crowds and particles stay out of the mirror (and our own cabin).
	_mirror_cam.cull_mask = 0xFFFFF & ~MIRROR_SKIP & ~CABIN_LAYER
	_tag_mirror_skip()
	_mirror_vp.add_child(_mirror_cam)
	var env := _mirror_env()
	if env:
		_mirror_cam.environment = env
	gm.albedo_texture = _mirror_vp.get_texture()
	gm.uv1_scale = Vector3(-1, 1, 1) # a mirror flips left and right
	gm.uv1_offset = Vector3(1, 0, 0)


const MIRROR_SKIP := 1 << 18 ## render layer 19: things the mirror leaves out


## Grass, spectators and particles get an extra layer the mirror camera skips
## (the main camera sees every layer, so nothing changes there).
func _tag_mirror_skip() -> void:
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var skip := gi is GPUParticles3D or gi is CPUParticles3D
		if not skip and gi is MultiMeshInstance3D: # grass tufts and crowds, by their shaders
			var sm := gi.material_override as ShaderMaterial
			if sm and sm.shader:
				var path := sm.shader.resource_path
				skip = path.contains("grass") or path.contains("people")
		if skip:
			gi.layers = (gi.layers & ~1) | MIRROR_SKIP


## The race environment without the expensive screen-space passes.
func _mirror_env() -> Environment:
	var cam := get_viewport().get_camera_3d()
	var src: Environment = cam.environment if cam and cam.environment else null
	if src == null:
		var we := get_tree().current_scene.find_child("WorldEnvironment", true, false) as WorldEnvironment if get_tree().current_scene else null
		if we == null:
			for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
				we = n
				break
		src = we.environment if we else null
	if src == null:
		return null
	var e: Environment = src.duplicate()
	e.ssao_enabled = false
	e.ssr_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.glow_enabled = false
	e.volumetric_fog_enabled = false
	return e


func _update_mirror() -> void:
	if _mirror_vp == null:
		return
	# ~20 Hz (Medium: ~10 Hz) is plenty for a glance in the mirror.
	_mirror_frame += 1
	if _mirror_frame % (6 if _mirror_cheap else 3) != 0:
		return
	var root: Node3D = _mirror_glass.get_parent()
	var g := root.global_transform
	var n := g.basis.z.normalized() # glass normal, towards the driver
	var cam_eye := car.global_transform * eye
	var virt := cam_eye - n * 2.0 * (cam_eye - g.origin).dot(n) # the eye seen through the glass
	var fwd := (g.origin - virt).normalized()
	_mirror_cam.global_transform = Transform3D(Basis.looking_at(fwd, g.basis.y), virt)
	var dist := virt.distance_to(g.origin)
	# Start past our own cabin and rear glass: the mirror shows the road behind.
	_mirror_cam.near = dist + float(spec.get("rear_glass", 1.5))
	_mirror_cam.fov = rad_to_deg(2.0 * atan(MIRROR_SIZE.y * 0.5 / dist)) * 1.25
	_mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


var _glass_saved := {} ## surface -> override material before the cockpit took over
var _clean_glass: StandardMaterial3D


## Seen from inside, some models' tinted glass is nearly black: while in the
## cockpit the windows are clean, lightly tinted glass.
func _clear_glass(on: bool) -> void:
	if _model == null:
		return
	var d := CarModel.data(car.model_id)
	var keys = spec.get("glass", "")
	if keys is String:
		keys = [keys]
	if on:
		if _clean_glass == null:
			_clean_glass = StandardMaterial3D.new()
			_clean_glass.albedo_color = Color(0.82, 0.88, 0.9, 0.1)
			_clean_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_clean_glass.roughness = 0.04
			_clean_glass.metallic_specular = 0.6
			_clean_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		for key in keys:
			var si: int = d.surface_keys.find(key)
			if si < 0 or si >= _model.get_surface_override_material_count():
				continue
			var cur := _model.get_surface_override_material(si)
			if cur == _clean_glass:
				continue
			# CarDirt swaps in its wet / dirty glass when the car picks something
			# up: keep that for when we leave the cockpit, and stay clear inside
			# (the windscreen layer draws the drops the wipers clear).
			_glass_saved[si] = cur
			_model.set_surface_override_material(si, _clean_glass)
	else:
		for si in _glass_saved:
			_model.set_surface_override_material(si, _glass_saved[si])
		_glass_saved.clear()


# ---------------------------------------------------------------- cabin light

const CABIN_LAYER := 1 << 19 ## render layer 20: the cockpit and our own shell while inside


## Other cars' lamps (and trackside lamps) cast no shadows, so they'd shine
## straight through our roof and doors and floodlight the cabin at night. While
## we're inside, our shell and cockpit sit on their own layer that those
## omni/spot lights skip; the sun / moon still reach in through the glass.
func _shield(on: bool) -> void:
	var layer := CABIN_LAYER if on else 1
	if _model:
		_model.layers = layer
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).layers = layer
	if not on:
		return
	var root := get_tree().current_scene if get_tree().current_scene else get_tree().root
	for n in root.find_children("*", "Light3D", true, false):
		if n is OmniLight3D or n is SpotLight3D:
			(n as Light3D).light_cull_mask &= ~CABIN_LAYER
	if not _reshield_pending and _reshields < 3: # lamps made a little later (race start, dusk)
		_reshield_pending = true
		_reshields += 1
		get_tree().create_timer(3.0).timeout.connect(func():
			_reshield_pending = false
			if active and is_inside_tree():
				_shield(true))

var _probe: ReflectionProbe
var _reshield_pending := false
var _reshields := 0


## An interior reflection probe over the cabin: inside it the ambient light and
## reflections come from the dim cabin itself, not the open sky, so a closed
## car doesn't glow from within (the sun still comes in through the glass).
func _build_cabin_light() -> void:
	if not probe_enabled:
		return
	var cowl := _cowl if _cowl != Vector3.INF else eye + Vector3(0, -0.2, -0.75)
	var top := _glass_top.y if _glass_top != Vector3.INF else eye.y + 0.25
	var half_w := _glass_w * 0.5 + 0.04
	var z0 := cowl.z - 0.02
	var z1 := eye.z + 0.6
	var y0 := eye.y - 0.95
	var y1 := top + 0.08
	_probe = ReflectionProbe.new()
	_probe.name = "CabinProbe"
	_probe.position = Vector3(0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	_probe.size = Vector3(half_w * 2.0, y1 - y0, z1 - z0)
	_probe.origin_offset = eye - _probe.position # capture from the driver's head
	_probe.interior = true
	_probe.box_projection = true
	_probe.blend_distance = 0.05
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.max_distance = 6.0
	_probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	_probe.ambient_color = Color(0.66, 0.69, 0.74)
	_probe.ambient_color_energy = _cabin_ambient()
	# It moves with the car, so it keeps re-capturing: capture nothing (cheap).
	# What matters is the interior ambient; reflections in the cabin stay dark.
	_probe.cull_mask = 0
	add_child(_probe)


# ---------------------------------------------------------------- helpers

## Fewer draw calls: everything that never moves becomes one mesh per material.
func _merge_static() -> void:
	if OS.get_cmdline_user_args().has("nomerge"):
		return
	var list: Array = []
	for n in find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("static"):
			list.append(n)
	_merge_into(self, list)
	# Moving groups: each becomes one mesh per material under its own node.
	var movers: Array = [_wheel_spin] + _wipers
	if _mirror_glass:
		movers.append(_mirror_glass.get_parent())
	for g in movers:
		if g == null:
			continue
		var kids: Array = []
		for c in g.get_children():
			if c is MeshInstance3D and c != _mirror_glass:
				kids.append(c)
		_merge_into(g, kids)


## Merges `list` (MeshInstance3Ds under `parent`) into one mesh per material.
func _merge_into(parent: Node3D, list: Array) -> void:
	var groups := {} ## material -> SurfaceTool
	for mi: MeshInstance3D in list:
		if mi.mesh == null:
			continue
		var m := mi.material_override
		var xf := _rel_xf(mi, parent)
		if not groups.has(m):
			var nst := SurfaceTool.new()
			nst.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[m] = nst
		var st: SurfaceTool = groups[m]
		var nb := xf.basis.inverse().transposed()
		for sidx in mi.mesh.get_surface_count():
			# Copied by hand: append_from() drops surfaces whose formats differ.
			var arr := mi.mesh.surface_get_arrays(sidx)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nr = arr[Mesh.ARRAY_NORMAL]
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			var count: int = idx.size() if idx != null and idx.size() > 0 else v.size()
			for k in count:
				var i: int = idx[k] if idx != null and idx.size() > 0 else k
				st.set_normal((nb * (nr[i] if nr != null and nr.size() > i else Vector3.UP)).normalized())
				st.set_uv(uv[i] if uv != null and uv.size() > i else Vector2.ZERO)
				st.add_vertex(xf * v[i])
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	for m in groups:
		var st: SurfaceTool = groups[m]
		if m is BaseMaterial3D and (m as BaseMaterial3D).normal_enabled:
			st.generate_tangents()
		var merged := _mesh(parent, st.commit(), m) # receives shadows, casts none
		merged.name = "Merged"


func _rel_xf(n: Node3D, ancestor: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != ancestor and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## A descendant's transform in the cockpit's own space.
func _local_xf(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p != self and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _mesh(parent: Node, m: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	# The cabin receives shadows (the car's shadow proxy casts the roof's) but
	# casts none: interior shadow passes cost draws for little to see.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


var _mats := {}


## Plain materials, shared when identical (so merging groups them).
func _mat(col: Color, rough: float, metal: float) -> StandardMaterial3D:
	var key := "%s|%.3f|%.3f" % [col.to_html(), rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_mats[key] = m
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static var _grain: NoiseTexture2D


## Fine leather / plastic grain as a normal map.
static func _grain_normal() -> NoiseTexture2D:
	if _grain == null:
		_grain = NoiseTexture2D.new()
		_grain.width = 256
		_grain.height = 256
		_grain.seamless = true
		_grain.as_normal_map = true
		_grain.bump_strength = 4.0
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.frequency = 0.08
		_grain.noise = n
	return _grain
