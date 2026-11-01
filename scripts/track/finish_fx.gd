class_name FinishFx
extends Node3D
## Finish celebration at the start/finish gantry: when the winner takes the
## flag, gold pyro fountains and white smoke plumes from both pillar tops and a
## confetti burst over the road. Five small GPUParticles3D built at track load
## and run once with amount_ratio 0 so their shaders compile behind the loading
## screen; afterwards idle (inactive particles are not drawn). The leader is
## polled at 2 Hz; nothing runs per frame.
##   FinishFx.add(parent, pillar_left_top, pillar_right_top, beam_top)

const PYRO_S := 3.2 ## seconds the fountains and smoke run
const CONFETTI := [Color(0.95, 0.12, 0.1), Color(0.98, 0.85, 0.15), Color(0.15, 0.4, 0.95), Color(0.95, 0.95, 0.95),
	Color(0.1, 0.75, 0.3), Color(0.95, 0.45, 0.8)]

var _fx: Array[GPUParticles3D] = []
var _race: Node
var _poll: Timer
var _stop_t: Timer


static func add(parent: Node3D, left: Vector3, right: Vector3, beam: Vector3) -> FinishFx:
	var f := FinishFx.new()
	f.name = "FinishFx"
	parent.add_child(f)
	for p: Vector3 in [left, right]:
		f._fx.append(f._sparks(p))
		f._fx.append(f._smoke(p))
	f._fx.append(f._confetti(beam, (right - left) * 0.5))
	for p in f._fx: # warm: process and draw with no live particles
		p.amount_ratio = 0.0
		p.emitting = true
	f._stop_t = Timer.new()
	f._stop_t.one_shot = true
	f._stop_t.wait_time = 4.0
	f._stop_t.autostart = true
	f._stop_t.timeout.connect(f._stop)
	f.add_child(f._stop_t)
	f._poll = GxLive.every(f, 0.5, f._check)
	if OS.get_cmdline_user_args().has("--finishfx"): # debug: fire 6 s after load
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = 6.0
		t.autostart = true
		t.timeout.connect(f.fire)
		f.add_child(t)
	return f


func _check() -> void:
	if _race == null:
		_race = GxLive.race(self)
		return
	var lead = GxLive.leader(_race)
	if lead and lead.finished:
		_poll.stop()
		fire()


func fire() -> void:
	for p in _fx:
		p.amount_ratio = 1.0
		p.emitting = true
		p.restart()
	_stop_t.wait_time = PYRO_S
	_stop_t.start()


func _stop() -> void:
	for p in _fx:
		if not p.one_shot:
			p.emitting = false


func _base(p: Vector3, amount: int, life: float) -> GPUParticles3D:
	var g := GPUParticles3D.new()
	g.amount = amount
	g.lifetime = life
	g.local_coords = false
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 40, 40))
	g.position = p
	add_child(g)
	return g


func _ramp(offsets: PackedFloat32Array, cols: PackedColorArray, hdr := false) -> GradientTexture1D:
	var gr := Gradient.new()
	gr.offsets = offsets
	gr.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = gr
	t.use_hdr = hdr
	return t


## Gold fountain (car_fx sparks look, pointing up).
func _sparks(p: Vector3) -> GPUParticles3D:
	var g := _base(p, 90, 1.5)
	g.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 14.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	pm.color_ramp = _ramp(PackedFloat32Array([0.0, 0.4, 1.0]),
		PackedColorArray([Color(3.0, 2.2, 0.9, 1.0), Color(2.4, 1.3, 0.3, 1.0), Color(0.9, 0.3, 0.05, 0.0)]), true)
	g.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.38)
	q.material = m
	g.draw_pass_1 = q
	return g


## White plume (car_fx exhaust smoke look, bigger and slower).
func _smoke(p: Vector3) -> GPUParticles3D:
	var g := _base(p, 48, 5.5)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.3, 0.5, 0) # warm, drifting
	pm.damping_min = 0.8
	pm.damping_max = 1.4
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -15.0
	pm.angular_velocity_max = 15.0
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.25))
	grow.add_point(Vector2(1, 4.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	pm.color_ramp = _ramp(PackedFloat32Array([0.0, 0.15, 1.0]),
		PackedColorArray([Color(0.9, 0.9, 0.9, 0.0), Color(0.92, 0.92, 0.93, 0.3), Color(0.85, 0.86, 0.88, 0.0)]))
	g.process_material = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit: grey at night
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = TireFx._puff_texture()
	m.roughness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(1.4, 1.4)
	q.material = m
	g.draw_pass_1 = q
	return g


## Paper confetti blown up off the beam, fluttering down over the road.
func _confetti(p: Vector3, half: Vector3) -> GPUParticles3D:
	var g := _base(p, 220, 6.0)
	g.one_shot = true
	g.explosiveness = 0.85
	g.randomness = 0.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(absf(half.x) * 0.8 + 0.3, 0.2, absf(half.z) * 0.8 + 0.3)
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -2.2, 0)
	pm.damping_min = 2.5 # paper: air brakes it, it drifts down slowly
	pm.damping_max = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var cols := PackedColorArray()
	var offs := PackedFloat32Array()
	for i in CONFETTI.size():
		offs.append(float(i) / CONFETTI.size())
		cols.append(CONFETTI[i])
	var ci := _ramp(offs, cols)
	ci.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	pm.color_initial_ramp = ci
	g.process_material = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.08)
	q.material = m
	g.draw_pass_1 = q
	return g
