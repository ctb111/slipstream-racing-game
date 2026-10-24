class_name CarFx
extends Node3D
## Visual car effects for its parent Car:
##  - exhaust backfire flames, flashed in sync with CarAudio's overrun pops
##  - brake discs glowing after hard braking (an additive ring inside each
##    wheel, so it shows through the spokes; mostly a night thing)
##  - sparks while grinding along a guardrail or wall (CarImpacts reports it)
##  - splashes through standing water once the track is soaked (puddles are
##    the road shader's: same noise, same threshold, sampled on the CPU)
## Every piece is hidden / not emitting when idle, so a calm car costs nothing.
## Debug: `--fxdebug` prints events, `--fxtest` fires flames, glow and sparks
## on the player car for screenshots.

const FLAME_SHADER := preload("res://shaders/exhaust_flame.gdshader")
const FLAME_TIME := 0.075 ## s a flash lasts
const LIGHT_RANGE := 45.0 ## cars nearer the camera than this light the ground with a flash
const PUDDLE_FROM := 0.45 ## track wetness where standing water appears (road.gdshader)

static var _circuit_ref: WeakRef
static var _noise_img: Image
static var _flame_mesh: QuadMesh
static var _spark_mat: StandardMaterial3D
static var _drop_mat: StandardMaterial3D
static var _ring_mesh: ArrayMesh
static var _splash_wav: AudioStreamWAV

var _car: Car
var _debug := false
var _test := false
# Flames
var _pipes: Array[Vector3] = [] ## car-local tailpipe tips
var _flames: Array[MeshInstance3D] = []
var _flash: OmniLight3D
var _flame_t := 0.0
var _flame_level := 0.0
# Exhaust smoke
var _smoke: Array[GPUParticles3D] = []
var _age := 0.0 ## s since this car was built: a cold engine smokes a little at idle
var _smoke_lod := 0.0
var _smoke_near := true
# Screenshots (--fxshots=<prefix>): launch, hard acceleration, off-track
var _shots := ""
var _move_t := -1.0
var _off_t := 0.0
var _shot_done := {}
# Brakes
var _heat: Array[float] = [0.0, 0.0] ## front, rear axle disc temperature 0..1+
var _glow: Array[MeshInstance3D] = []
var _glow_mats: Array[StandardMaterial3D] = []
var _glow_on := false
# Sparks
var _impacts: CarImpacts
var _sparks: GPUParticles3D
# Splashes
var _splash: Array[GPUParticles3D] = []
var _line_i := -1
var _wet_check := 0.0
var _water := 0.0
var _splash_snd: AudioStreamPlayer3D
var _splash_lvl := 0.0


func _ready() -> void:
	_car = get_parent()
	_debug = "--fxdebug" in OS.get_cmdline_user_args()
	_test = "--fxtest" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxshots="):
			_shots = a.trim_prefix("--fxshots=")
	_build_flames.call_deferred() # after the body is built
	_build_glow()
	_build_sparks()
	_build_splash()
	var audio := _car.get_node_or_null("CarAudio")
	if audio == null:
		for c in _car.get_children():
			if c is CarAudio:
				audio = c
	if audio and audio.has_signal("popped"):
		audio.popped.connect(_on_pop)


# ---------------------------------------------------------------- flames

func _build_flames() -> void:
	if not is_instance_valid(_car):
		return
	var spec := CarCatalog.get_car(_car.model_id)
	if spec.has("exhausts"):
		for p in spec.exhausts:
			_pipes.append(p)
	else:
		var box := _body_box()
		var x := -box.size.x * 0.26
		_pipes.append(Vector3(x, box.position.y + 0.2, box.end.z - 0.02))
	if _flame_mesh == null:
		_flame_mesh = QuadMesh.new()
		_flame_mesh.size = Vector2(1, 1)
		var m := ShaderMaterial.new()
		m.shader = FLAME_SHADER
		_flame_mesh.material = m
	for p in _pipes:
		var mi := MeshInstance3D.new()
		mi.mesh = _flame_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		# +Z = out of the pipe (the car's rear); x = width, z = length.
		mi.transform = Transform3D(Basis().scaled(Vector3(0.22, 1.0, 0.6)), p)
		mi.visible = false
		add_child(mi)
		_flames.append(mi)
	for p in _pipes:
		_smoke.append(_smoke_emitter(p))
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.55, 0.2)
	_flash.omni_range = 3.5
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.visible = false
	_flash.position = _pipes[0] + Vector3(0, 0, 0.35)
	add_child(_flash)


## Car-local bounds of the visible body.
func _body_box() -> AABB:
	var box := AABB(Vector3(-0.85, -0.6, -2.2), Vector3(1.7, 1.3, 4.4))
	var body := _car.get_node_or_null("Body")
	if body:
		var inv := _car.global_transform.affine_inverse()
		var first := true
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				continue
			var bb := (inv * mi.global_transform) * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
	return box


func _on_pop(level: float) -> void:
	if _flames.is_empty():
		return
	_flame_t = FLAME_TIME * randf_range(0.8, 1.5)
	_flame_level = clampf(level * randf_range(0.7, 1.15), 0.25, 1.0)
	for f in _flames:
		f.visible = true
		f.set_instance_shader_parameter("seed", randf() * 10.0)
	var cam := get_viewport().get_camera_3d()
	_flash.visible = cam != null and cam.global_position.distance_to(global_position) < LIGHT_RANGE
	if _debug:
		print("fx flame %.2f" % _flame_level)


func _tick_flames(dt: float) -> void:
	if _flame_t <= 0.0:
		return
	_flame_t -= dt
	var k := clampf(_flame_t / FLAME_TIME, 0.0, 1.0)
	var v := _flame_level * (0.4 + 0.6 * k)
	if _flame_t <= 0.0:
		v = 0.0
	for f in _flames:
		f.visible = v > 0.0
		f.set_instance_shader_parameter("flame", v)
	_flash.light_energy = v * (3.0 if Car.night else 1.2)
	if v <= 0.0:
		_flash.visible = false


## Exhaust smoke: soft grey-blue puffs that leave the pipe, swell and drift.
func _smoke_emitter(pipe: Vector3) -> GPUParticles3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit: dark at night, grey in the day
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = TireFx._puff_texture()
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.4
	var p := GPUParticles3D.new()
	p.amount = 6
	p.lifetime = 1.5
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 8, 20))
	p.position = pipe + Vector3(0, 0, 0.05)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.15, 1) # out of the pipe, backwards
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.spread = 12.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.inherit_velocity_ratio = 0.25
	pm.gravity = Vector3(0, 0.35, 0) # warm: it rises a little
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 0.25
	pm.scale_max = 0.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 3.0))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(0.62, 0.65, 0.72, 0.0), Color(0.66, 0.69, 0.75, 0.3), Color(0.72, 0.74, 0.78, 0.0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _tick_smoke(dt: float) -> void:
	_age += dt
	if _smoke.is_empty():
		return
	_smoke_lod -= dt
	if _smoke_lod <= 0.0:
		_smoke_lod = 0.25
		var cam := get_viewport().get_camera_3d()
		_smoke_near = cam == null or cam.global_position.distance_squared_to(_car.global_position) < 80.0 * 80.0
	var spd := absf(_car.speed)
	var gas := _car.throttle if _car.gear > 0 else 0.0
	# Thick on a launch / hard acceleration at low speed, thinning out as the
	# car gets going (it streams away too fast to build up); a wisp when cold.
	var slow := clampf(1.0 - spd / 28.0, 0.0, 1.0)
	var k := gas * gas * (0.25 + 0.75 * slow)
	var cold := clampf(1.0 - _age / 25.0, 0.0, 1.0) * 0.35 # first half-minute: a cold engine
	k = maxf(k, cold if spd < 5.0 else 0.0)
	var on := _smoke_near and k > 0.06
	for s in _smoke:
		if on:
			s.amount_ratio = clampf(k, 0.15, 1.0)
		if s.emitting != on:
			s.emitting = on


func _tick_shots(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not (cam is ChaseCamera) or (cam as ChaseCamera).target != _car:
		return
	if _move_t < 0.0 and absf(_car.speed) > 1.0:
		_move_t = 0.0
	if _move_t >= 0.0:
		_move_t += dt
	var off := false
	for w in _car.wheels:
		if w.grounded and w.surface_grip < 0.9:
			off = true
	_off_t = _off_t + dt if off else 0.0
	if _move_t > 0.5:
		_shot("launch")
	if _move_t > 2.4:
		_shot("accel")
	if _off_t > 0.5:
		_shot("offtrack")


func _shot(tag: String) -> void:
	if _shot_done.has(tag):
		return
	_shot_done[tag] = true
	var path := "%s_%s.png" % [_shots, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("fx shot %s speed %.0f km/h" % [path, absf(_car.speed) * 3.6])


# ---------------------------------------------------------------- brakes

func _build_glow() -> void:
	if _ring_mesh == null:
		_ring_mesh = _make_ring(0.22, 0.56, 28) # disc friction ring, inside the rim
	for axle in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.vertex_color_use_as_albedo = true
		m.disable_fog = true
		m.albedo_color = Color(0, 0, 0)
		_glow_mats.append(m)
	for w in _car.wheels:
		var mi := MeshInstance3D.new()
		mi.mesh = _ring_mesh
		mi.material_override = _glow_mats[0 if w.front else 1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var r := _car.wheel_radius
		var inboard := 0.03 if w.mount.x < 0.0 else -0.03
		mi.transform = Transform3D(Basis().scaled(Vector3(1, r, r)), Vector3(inboard, 0, 0))
		mi.visible = false
		w.pivot.add_child(mi) # steers and rides with the wheel, doesn't spin (the glow is even all round)
		_glow.append(mi)


## A flat annulus in the YZ plane (the disc's friction ring), radius 1 = wheel
## radius after scaling. Vertex alpha fades the inner and outer edges.
static func _make_ring(r0: float, r1: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rm := (r0 + r1) * 0.5
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		for band in 2:
			var ra := r0 if band == 0 else rm
			var rb := rm if band == 0 else r1
			var ca := Color(1, 1, 1, 0.0 if band == 0 else 1.0)
			var cb := Color(1, 1, 1, 1.0 if band == 0 else 0.0)
			var p := [Vector3(0, cos(a0) * ra, sin(a0) * ra), Vector3(0, cos(a1) * ra, sin(a1) * ra),
				Vector3(0, cos(a1) * rb, sin(a1) * rb), Vector3(0, cos(a0) * rb, sin(a0) * rb)]
			var c := [ca, ca, cb, cb]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(c[k])
				st.set_normal(Vector3.RIGHT)
				st.add_vertex(p[k])
	return st.commit()


func _tick_brakes(dt: float) -> void:
	var spd := absf(_car.speed)
	var braking := _car.brake if _car.gear >= 0 else 0.0
	if _test:
		braking = 1.0
		spd = maxf(spd, 40.0)
	for axle in 2:
		var bias := 1.0 if axle == 0 else 0.6 # the fronts do most of the work
		# Heat in ~ braking power; out ~ conduction + airflow.
		var gain := braking * bias * spd * 0.012
		var loss: float = _heat[axle] * (0.06 + spd * 0.004)
		_heat[axle] = clampf(_heat[axle] + (gain - loss) * dt, 0.0, 1.3)
	var front := smoothstep(0.45, 1.1, _heat[0])
	var rear := smoothstep(0.45, 1.1, _heat[1])
	var on := front > 0.01 or rear > 0.01
	if on: # a few pixels at distance: not worth four draws per car
		var cam := get_viewport().get_camera_3d()
		on = cam == null or cam.global_position.distance_squared_to(_car.global_position) < 60.0 * 60.0
	if on != _glow_on:
		_glow_on = on
		for g in _glow:
			g.visible = on
		if _debug:
			print("fx brake glow %s heat %.2f" % [on, _heat[0]])
	if not on:
		return
	# Cherry red when warm, orange when really hot. Daylight washes it out.
	var day := 1.0 if Car.night else (0.4 if Car.headlights else 0.2)
	for axle in 2:
		var k: float = front if axle == 0 else rear
		var col := Color(0.8, 0.05, 0.0).lerp(Color(1.0, 0.3, 0.03), k * k)
		var e := k * day * 1.1
		_glow_mats[axle].albedo_color = Color(col.r * e, col.g * e, col.b * e)


# ---------------------------------------------------------------- sparks

func _build_sparks() -> void:
	for c in _car.get_children():
		for cc in c.get_children():
			if cc is CarImpacts:
				_impacts = cc
	if _spark_mat == null:
		_spark_mat = StandardMaterial3D.new()
		_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spark_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_spark_mat.vertex_color_use_as_albedo = true
		_spark_mat.disable_fog = true
	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.32
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-15, -5, -15), Vector3(30, 10, 30))
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.18, 1) # emitter is turned so +Z is backwards along the slide
	pm.spread = 20.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.5
	pm.inherit_velocity_ratio = 0.75
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new() # white-hot, then orange, cooling to a dull red
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(2.6, 1.7, 0.6, 1.0), Color(2.0, 0.75, 0.12, 1.0), Color(0.8, 0.12, 0.0, 0.0)])
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	rt.use_hdr = true
	pm.color_ramp = rt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.11)
	q.material = _spark_mat
	p.draw_pass_1 = q
	p.top_level = true
	add_child(p)
	_sparks = p


func _tick_sparks() -> void:
	if _impacts == null and not _test:
		return
	var level := 0.0
	var at := Vector3.ZERO
	if _impacts:
		level = _impacts.spark_level
		at = _impacts.spark_pos
	if _test:
		level = 1.0
		at = _car.global_position + _car.global_basis.x * 0.9 + Vector3.UP * 0.3
	var on := level > 0.05 and absf(_car.speed) > 4.0
	if on:
		var back := -_car.linear_velocity
		back.y = 0.0
		if back.length() < 0.5:
			back = _car.global_basis.z
		_sparks.global_transform = Transform3D(Basis.looking_at(-back.normalized(), Vector3.UP), at)
		_sparks.amount_ratio = clampf(level, 0.3, 1.0)
	if on != _sparks.emitting:
		_sparks.emitting = on
		if _debug:
			print("fx sparks %s %.2f" % [on, level])


# ---------------------------------------------------------------- splashes

func _build_splash() -> void:
	var wx := Weather.current()
	var could_be_wet := Car.weather_road_grip < 0.95 or (wx != null and wx.cycle != null)
	if not could_be_wet or Car.weather_off_grip < 0.6:
		return # dry preset, or snow (slush spray is TireFx's)
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # water catches the sky: don't let storm light turn it to soot
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_drop_mat.vertex_color_use_as_albedo = true
		_drop_mat.albedo_texture = TireFx._puff_texture()
		_drop_mat.roughness = 0.2
	for w in _car.wheels:
		var p := GPUParticles3D.new()
		p.amount = 36
		p.lifetime = 0.5
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 8, 24))
		var pm := ParticleProcessMaterial.new()
		var out := -1.0 if w.mount.x < 0.0 else 1.0
		pm.direction = Vector3(out * 0.9, 1.0, 0.5) # sideways and up, a little back (car-local frame below)
		pm.spread = 22.0
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -25.0
		pm.angular_velocity_max = 25.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 7.0
		pm.inherit_velocity_ratio = 0.35
		pm.gravity = Vector3(0, -9.8, 0)
		pm.scale_min = 0.12
		pm.scale_max = 0.3
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.6))
		grow.add_point(Vector2(1, 1.8))
		var gt := CurveTexture.new()
		gt.curve = grow
		pm.scale_curve = gt
		var fade := Gradient.new()
		var a := 0.35 if Car.night else 0.55
		var lum := 0.22 if Car.night else 0.62
		fade.set_color(0, Color(lum, lum * 1.03, lum * 1.08, a))
		fade.set_color(1, Color(lum, lum * 1.03, lum * 1.08, 0.0))
		var ft := GradientTexture1D.new()
		ft.gradient = fade
		pm.color_ramp = ft
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		q.material = _drop_mat
		p.draw_pass_1 = q
		add_child(p)
		_splash.append(p)
	if _splash_wav == null:
		_splash_wav = CarAudio._noise_loop(1.2, 1700.0, 0.0, 0.0, 0.0) # broadband hiss of thrown water
	_splash_snd = AudioStreamPlayer3D.new()
	_splash_snd.stream = _splash_wav
	_splash_snd.bus = &"Effects"
	_splash_snd.unit_size = 7.0
	_splash_snd.max_distance = 80.0
	_splash_snd.volume_db = -80.0
	add_child(_splash_snd)


func _tick_splash(dt: float) -> void:
	if _splash.is_empty():
		return
	_wet_check -= dt
	if _wet_check <= 0.0:
		_wet_check = 0.5
		var wx := Weather.current()
		_water = 0.0
		if wx:
			var wet := wx.wetness if wx.cycle else float(wx.preset.get("wet", 0.0))
			_water = smoothstep(PUDDLE_FROM, 0.9, wet)
	var spd := absf(_car.speed)
	var circuit := _circuit()
	var active := _water > 0.01 and spd > 7.0 and circuit != null and _noise() != null
	if active:
		var cam := get_viewport().get_camera_3d()
		active = cam == null or cam.global_position.distance_squared_to(_car.global_position) < 70.0 * 70.0
	if active:
		_line_i = circuit.line.closest_index(_car.global_position, _line_i)
	var loud := 0.0
	for i in _splash.size():
		var w: Car.Wheel = _car.wheels[i]
		var p := _splash[i]
		var depth := 0.0
		if active and w.grounded:
			depth = _puddle_at(circuit.line, w.contact) * _water
		var on := depth > 0.25
		if on:
			loud = maxf(loud, depth * clampf(spd / 35.0, 0.3, 1.0))
		if on:
			p.global_transform = Transform3D(_car.global_basis.orthonormalized(), w.contact + Vector3.UP * 0.05)
			p.amount_ratio = clampf(depth * spd / 30.0, 0.3, 1.0)
		if on != p.emitting:
			p.emitting = on
			if _debug and on:
				print("fx splash wheel %d depth %.2f" % [i, depth])
	# Hiss of thrown water: swells quickly into a puddle, trails off after it.
	_splash_lvl = move_toward(_splash_lvl, loud, dt * (10.0 if loud > _splash_lvl else 3.0))
	if _splash_lvl > 0.01:
		if not _splash_snd.playing:
			_splash_snd.play(randf())
		_splash_snd.volume_db = linear_to_db(_splash_lvl * 0.7)
		_splash_snd.pitch_scale = 0.85 + spd / 120.0
	elif _splash_snd.playing:
		_splash_snd.stop()


func _circuit() -> Circuit:
	var c: Circuit = _circuit_ref.get_ref() if _circuit_ref else null
	if c == null or not is_instance_valid(c):
		var scene := get_tree().current_scene
		c = scene.find_child("Circuit", true, false) as Circuit if scene else null
		_circuit_ref = weakref(c) if c else null
		_noise_img = null
	if c == null or c.line == null:
		return null
	return c


func _noise() -> Image:
	if _noise_img == null:
		var c := _circuit()
		if c and c.noise_tex:
			var img := c.noise_tex.get_image()
			if img and not img.is_empty():
				if img.is_compressed():
					img.decompress()
				_noise_img = img
	return _noise_img


## Standing water at a world point, 0..1, as road.gdshader draws it.
func _puddle_at(line: RacingLine, pos: Vector3) -> float:
	var i := _line_i # the car's own sample: the wheels are within a couple of metres of it
	var c := line.centers[i]
	var r := line.rights[i]
	var fwd := r.cross(Vector3.DOWN).normalized() # tangent (right = tangent x up)
	var lat := (pos - c).dot(r)
	var half := TrackDefs.ROAD_WIDTH * 0.5
	var edge_m := half - absf(lat)
	if edge_m < 1.2:
		return 0.0
	var along := line.offset_of(i) + (pos - c).dot(fwd)
	var uv := Vector2(lat + half, along) * 0.02 + Vector2(0.3, 0.3)
	var img := _noise_img
	var px := int(fposmod(uv.x, 1.0) * img.get_width()) % img.get_width()
	var py := int(fposmod(uv.y, 1.0) * img.get_height()) % img.get_height()
	var v := img.get_pixel(px, py).r
	return smoothstep(0.58, 0.66, v) * smoothstep(1.2, 3.0, edge_m)


# ---------------------------------------------------------------- tick

func _physics_process(dt: float) -> void:
	_tick_brakes(dt)
	_tick_sparks()
	_tick_splash(dt)
	if _test and _flame_t <= 0.02:
		_on_pop(1.0) # screenshots: keep the flame lit


func _process(dt: float) -> void:
	_tick_flames(dt)
	_tick_smoke(dt)
	if _shots != "":
		_tick_shots(dt)
