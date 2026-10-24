class_name TireFx
extends Node3D
## Tyre smoke, dust off the tarmac, and skid marks for its parent Car.
## Skid marks from every car share one MultiMesh ring buffer, so they cost a
## single draw call no matter how many cars are sliding.

const MARK_WIDTH := 0.26
const MARK_STEP := 0.35 ## metres per skid segment
const MAX_MARKS := 4000

static var _marks: MultiMesh
static var _mark_node: MultiMeshInstance3D ## freed with the race scene; recreated on the next race
static var _next_mark := 0

var _car: Car
var _last_mark: Array[Vector3] = []
var _smoke: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _spray: Array[GPUParticles3D] = []
var _debris: Array[GPUParticles3D] = [] ## stones / grass bits thrown by the rear tyres off the tarmac
var _dust_tarmac: Array[bool] = [] ## which tint each dust emitter currently has
var _lod_t := 0.0
var _near80 := true ## within 80 m of the camera: dust, debris and launch smoke run


func _ready() -> void:
	_car = get_parent()
	if not is_instance_valid(_mark_node):
		_create_mark_layer()
	for i in _car.wheels.size():
		_last_mark.append(Vector3.INF)
		var w: Car.Wheel = _car.wheels[i]
		if not w.front:
			_smoke.append(_emitter(_smoke_material(), Color(0.82, 0.82, 0.8, 0.32), 32, 2.0))
		_dust.append(_emitter(_smoke_material(), Color(0.46, 0.39, 0.29, 0.28), 24, 1.6))
		_dust_tarmac.append(false)
		if not w.front:
			_debris.append(_debris_emitter())
		var wx := Weather.current()
		if not w.front and (Car.weather_road_grip < 0.95 or (wx and wx.cycle)):
			var snowy := Car.weather_off_grip < 0.6 or (wx != null and wx.cycle != null and float(wx.cycle.heavy.get("snow", 0.0)) > 0.5)
			_spray.append(_spray_emitter(snowy))


func _create_mark_layer() -> void:
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	_marks.mesh = quad
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	_next_mark = 0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.008, 0.008, 0.008)
	mat.vertex_color_use_as_albedo = false
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Instance colour alpha = mark strength.
	mat.vertex_color_use_as_albedo = true
	var mmi := MultiMeshInstance3D.new()
	_mark_node = mmi
	mmi.name = "SkidMarks"
	mmi.multimesh = _marks
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))
	# Marks reuse slots of a ring buffer: with physics interpolation a new mark
	# would be drawn sliding from the old mark's place for a frame.
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Lives in the scene, not the car, so marks stay when the car drives on.
	_car.get_parent().add_child.call_deferred(mmi)


func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # takes the scene light
	m.roughness = 1.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.6
	return m


static var _puff: Texture2D
const PUFF_PNG := "res://assets/fx/smoke_puff.png" ## baked soft smoke sprite (fbm x radial falloff, alpha 0 at the edge)


## A soft, wispy puff: noise under a radial falloff (shared by every emitter).
static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	if ResourceLoader.exists(PUFF_PNG):
		_puff = load(PUFF_PNG)
		return _puff
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.09
	n.fractal_octaves = 3
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			var fall := pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
			var a := fall * clampf(0.55 + n.get_noise_2d(x, y) * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
	return _puff


## Road spray thrown up behind a wheel in the wet: a fine, lit mist that
## streams back with the car and fades out before it reaches the camera.
func _spray_emitter(snowy: bool) -> GPUParticles3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX # lit, so it stays grey under storm clouds
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.8
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 2.0
	m.distance_fade_max_distance = 6.0
	var col := Color(0.85, 0.87, 0.9, 0.22) if snowy else Color(0.7, 0.72, 0.76, 0.14)
	if Car.night:
		col.a = 0.08 # lit (per vertex) but dim: in headlights it is a thin mist, not white puffs
		col = Color(col.r * 0.75, col.g * 0.75, col.b * 0.78, col.a)
	var p := _emitter(m, col, [14, 22, 36, 36][clampi(Game.quality, 0, 3)], 0.7) # big soft quads: overdraw
	var pm: ParticleProcessMaterial = p.process_material
	pm.inherit_velocity_ratio = 0.55 # mist trails the tyre instead of hanging in the air
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, -1.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.5))
	grow.add_point(Vector2(1, 2.6))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	(p.draw_pass_1 as QuadMesh).size = Vector2(1.0, 1.0)
	return p


static var _debris_mat: StandardMaterial3D


## Grit and grass cuttings flicked up behind a tyre: tiny lit chips that arc
## back and fall. The colour is set per surface (ParticleProcessMaterial.color).
func _debris_emitter() -> GPUParticles3D:
	if _debris_mat == null:
		_debris_mat = StandardMaterial3D.new()
		_debris_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_debris_mat.vertex_color_use_as_albedo = true
		_debris_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_debris_mat.roughness = 1.0
		_debris_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_debris_mat.albedo_texture = _puff_texture() # round, soft-edged specks, never squares
	var p := GPUParticles3D.new()
	p.amount = 8
	p.lifetime = 0.6
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-15, -4, -15), Vector3(30, 10, 30))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0.8, 1) # up and back (emitter takes the car's rotation)
	pm.spread = 30.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.inherit_velocity_ratio = 0.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = Color(0.35, 0.32, 0.28)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.045, 0.045)
	q.material = _debris_mat
	p.draw_pass_1 = q
	add_child(p)
	return p


func _emitter(mat: Material, color: Color, amount: int, life: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -5, -30), Vector3(60, 20, 60))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.angle_min = -180.0 # every puff turned differently, slowly rolling
	pm.angle_max = 180.0
	pm.angular_velocity_min = -30.0
	pm.angular_velocity_max = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.2
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 3.2))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, color)
	fade.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	pm.color_ramp = fade_tex
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	quad.material = mat
	p.draw_pass_1 = quad
	add_child(p)
	return p


func _physics_process(dt: float) -> void:
	var smoke_i := 0
	var moving := absf(_car.speed) > 3.0
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = 0.25
		var c := get_viewport().get_camera_3d()
		_near80 = c == null or c.global_position.distance_squared_to(_car.global_position) < 80.0 * 80.0
	# Launch / wheelspin: driven tyres spinning up under power smoke even before the car gets going.
	var spinning := _car.throttle > 0.5 and _car.gear > 0 and absf(_car.speed) < 20.0 and _near80
	var debris_i := 0
	var dry := _water() < 0.15 and Car.weather_road_grip > 0.9
	# Spray is mist a few metres long: cars far from the camera throw none.
	var near := true
	if not _spray.is_empty():
		var cam := get_viewport().get_camera_3d()
		near = cam == null or cam.global_position.distance_squared_to(_car.global_position) < 55.0 * 55.0
	for i in _car.wheels.size():
		var w: Car.Wheel = _car.wheels[i]
		var on_tarmac := w.surface_grip >= 0.9
		var sliding := w.grounded and w.slip > 0.15 and (moving or (spinning and w.driven))
		var contact := w.contact if w.grounded else _car.global_position
		if not w.front:
			var smoke := _smoke[smoke_i]
			smoke_i += 1
			smoke.global_position = contact + Vector3.UP * 0.15
			smoke.emitting = sliding and on_tarmac
			smoke.amount_ratio = clampf(w.slip * 1.5, 0.2, 1.0)
		if not w.front and not _spray.is_empty():
			var spray := _spray[smoke_i - 1]
			spray.global_position = contact + Vector3.UP * 0.25 + _car.global_basis.z * 0.3
			# Changeable weather: only once there's water (or slush) to throw up.
			var water := _water()
			spray.emitting = w.grounded and absf(_car.speed) > 10.0 and water > 0.12 and near
			spray.amount_ratio = clampf(absf(_car.speed) / 45.0, 0.2, 1.0) * clampf(water * 1.4, 0.25, 1.0)
		var dust := _dust[i]
		dust.global_position = contact + Vector3.UP * 0.1
		var spd := absf(_car.speed)
		# Off the tarmac: a proper brown trail. On dry tarmac at speed: the faintest grey haze.
		var tarmac_dust := on_tarmac and dry and spd > 30.0 and not w.front
		dust.emitting = w.grounded and _near80 and ((not on_tarmac and spd > 6.0) or tarmac_dust)
		if dust.emitting:
			if tarmac_dust != _dust_tarmac[i]:
				_dust_tarmac[i] = tarmac_dust
				(dust.process_material as ParticleProcessMaterial).color = Color(1.5, 1.6, 1.75, 0.3) if tarmac_dust else Color(1, 1, 1, 1)
			dust.amount_ratio = clampf((spd - 30.0) / 40.0, 0.06, 0.18) if tarmac_dust else clampf(spd / 20.0, 0.6, 1.0)
		if not w.front:
			var deb := _debris[debris_i]
			debris_i += 1
			var off := w.grounded and not on_tarmac and spd > 7.0 and _near80
			if off:
				deb.global_transform = Transform3D(_car.global_basis.orthonormalized(), contact + Vector3.UP * 0.08 + _car.global_basis.z * 0.25)
				var grassy := w.surface_grip <= 0.58
				(deb.process_material as ParticleProcessMaterial).color = Color(0.2, 0.3, 0.1) if grassy else Color(0.38, 0.35, 0.31)
				deb.amount_ratio = clampf(spd / 30.0, 0.3, 1.0)
			deb.emitting = off
		if sliding and on_tarmac:
			_lay_mark(i, contact, clampf(w.slip * 1.6, 0.35, 1.0))
		else:
			_last_mark[i] = Vector3.INF


## How much spray the surface gives: 1 for a fixed wet preset, else the live wetness.
func _water() -> float:
	var wx := Weather.current()
	if wx == null or wx.cycle == null:
		return 1.0
	return maxf(wx.wetness_line, wx.snow_cover * 0.6)


func _lay_mark(i: int, p: Vector3, strength: float) -> void:
	var last := _last_mark[i]
	if last == Vector3.INF:
		_last_mark[i] = p
		return
	var seg := p - last
	seg.y = 0.0
	var len := seg.length()
	if len < MARK_STEP:
		return
	if len > 3.0: # teleported / reset
		_last_mark[i] = p
		return
	var mid := (p + last) * 0.5 + Vector3.UP * 0.035
	var fwd := seg / len
	var right := fwd.cross(Vector3.UP)
	var basis := Basis(right * MARK_WIDTH, Vector3.UP, fwd * len)
	_marks.set_instance_transform(_next_mark, Transform3D(basis, mid))
	_marks.set_instance_color(_next_mark, Color(1, 1, 1, 0.85 * strength))
	_next_mark = (_next_mark + 1) % MAX_MARKS
	_marks.visible_instance_count = maxi(_marks.visible_instance_count, _next_mark if _next_mark > 0 else MAX_MARKS)
	_last_mark[i] = p
