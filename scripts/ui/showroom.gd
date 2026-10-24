class_name Showroom
extends Node3D
## Menu backdrop: the 930 on a slowly turning platform in a dark studio.
## Glossy floor (SSR), a key spot, a cool rim light and an overhead softbox,
## light haze, AgX. Display-only car built from CarModel (no physics / audio).

const CAR_LAYER := 2 ## kept out of the reflection probe so the car doesn't reflect itself
const TURN_SPEED := 0.1 ## rad/s

var _car_node: Node3D
var camera: Camera3D
var _turntable: Node3D
var _paint: BaseMaterial3D
var _t := 0.0
var _frame_from := Vector2.ZERO
var _frame_to := Vector2.ZERO
var _frame_k := 1.0


func _ready() -> void:
	_build_environment()
	_build_studio()
	_turntable = Node3D.new()
	_turntable.rotation.y = deg_to_rad(-35.0)
	add_child(_turntable)
	_build_platform()
	_build_car()
	camera = Camera3D.new()
	camera.fov = 30.0
	camera.near = 0.1
	camera.far = 120.0
	camera.cull_mask = 0xFFFFF & ~4 # hide the softbox strips
	add_child(camera)
	camera.make_current()
	_process(0.0)


## Paint shown on the display car.
func set_paint(c: Color) -> void:
	if _paint:
		var tw := create_tween()
		tw.tween_property(_paint, "albedo_color", c, 0.35).set_trans(Tween.TRANS_SINE)


## Shifts the car in frame (camera lens offset in metres) so the UI has room.
func set_framing(offset: Vector2, instant := false) -> void:
	_frame_from = Vector2(camera.h_offset, camera.v_offset) if camera else offset
	_frame_to = offset
	_frame_k = 1.0 if instant else 0.0


func _process(dt: float) -> void:
	_t += dt
	_turntable.rotation.y += TURN_SPEED * dt
	# Slow drift: the camera breathes around the car instead of sitting still.
	var yaw := deg_to_rad(28.0 + sin(_t * 0.07) * 9.0)
	var dist := 9.0 + sin(_t * 0.05) * 0.35
	var height := 1.25 + sin(_t * 0.09) * 0.12
	var target := Vector3(0, 0.55, 0)
	camera.position = target + Vector3(sin(yaw) * dist, height, cos(yaw) * dist)
	camera.look_at(target)
	if _frame_k < 1.0:
		_frame_k = minf(_frame_k + dt / 0.8, 1.0)
		var e := 1.0 - pow(1.0 - _frame_k, 3.0)
		var f := _frame_from.lerp(_frame_to, e)
		camera.h_offset = f.x
		camera.v_offset = f.y
	else:
		camera.h_offset = _frame_to.x
		camera.v_offset = _frame_to.y


func _build_environment() -> void:
	var env := Environment.new()
	# Background: near black above, a faint haze band at floor level the fog melts into.
	var sky_sh := Shader.new()
	sky_sh.code = """
shader_type sky;
void sky() {
	float h = EYEDIR.y;
	vec3 haze = vec3(0.014, 0.015, 0.018);
	COLOR = mix(haze, vec3(0.003, 0.0033, 0.0038), smoothstep(0.0, 0.3, h));
}
"""
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_sh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.17, 0.19)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.ssr_enabled = Game.quality >= 1
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.5
	env.ssr_depth_tolerance = 0.3
	env.fog_enabled = true
	env.fog_light_color = Color(0.014, 0.015, 0.018)
	env.fog_density = 0.035
	env.fog_sky_affect = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _build_studio() -> void:
	# Floor: dark, glossy, fading to black away from the platform.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mi.mesh = plane
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = length(wpos.xz);
	float pool = exp(-r * r / 60.0);
	ALBEDO = vec3(0.018, 0.019, 0.021) * (0.35 + 0.65 * pool);
	ROUGHNESS = mix(0.32, 0.12, pool);
	METALLIC = 0.0;
	SPECULAR = 0.5 * (0.4 + 0.6 * pool);
}
"""
	var fm := ShaderMaterial.new()
	fm.shader = sh
	floor_mi.material_override = fm
	add_child(floor_mi)

	# Overhead softbox strips: they are what the paint reflects (via the probe).
	for i in 3:
		var strip := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.7, 6.0)
		strip.mesh = q
		strip.rotation_degrees.x = 90.0
		strip.position = Vector3((i - 1) * 1.5, 5.2, 0)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = Color(1, 1, 1)
		sm.emission_enabled = true
		sm.emission = Color(1, 1, 1)
		sm.emission_energy_multiplier = 8.0
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		strip.material_override = sm
		strip.layers = 4 # probe only: never seen directly by the camera
		add_child(strip)

	# Key: warm spot from front-left, the only shadow caster.
	var key := SpotLight3D.new()
	key.position = Vector3(-4.5, 6.5, 5.0)
	key.look_at_from_position(key.position, Vector3(0, 0.3, 0))
	key.spot_range = 20.0
	key.spot_angle = 30.0
	key.spot_angle_attenuation = 1.6
	key.light_energy = 28.0
	key.light_color = Color(1.0, 0.94, 0.86)
	key.shadow_enabled = true
	key.shadow_blur = 2.0
	add_child(key)
	# Rim: cool, from behind-right, draws the silhouette.
	var rim := SpotLight3D.new()
	rim.position = Vector3(5.5, 3.5, -6.5)
	rim.look_at_from_position(rim.position, Vector3(0, 0.6, 0))
	rim.spot_range = 20.0
	rim.spot_angle = 28.0
	rim.light_energy = 16.0
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)
	# Top: soft pool on the floor right under the car.
	var top := SpotLight3D.new()
	top.position = Vector3(0, 8.0, 0)
	top.rotation_degrees.x = -90.0
	top.spot_range = 14.0
	top.spot_angle = 26.0
	top.spot_angle_attenuation = 2.2
	top.light_energy = 12.0
	top.light_color = Color(0.95, 0.95, 1.0)
	add_child(top)

	var probe := ReflectionProbe.new()
	probe.size = Vector3(30, 12, 30)
	probe.position = Vector3(0, 1.0, 0)
	probe.origin_offset = Vector3(0, -0.4, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.cull_mask = 0xFFFFF & ~(1 << (CAR_LAYER - 1))
	probe.box_projection = false
	probe.intensity = 1.0
	add_child(probe)


func _build_platform() -> void:
	var disc := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 2.95
	c.bottom_radius = 2.98
	c.height = 0.06
	c.radial_segments = 96
	disc.mesh = c
	disc.position.y = 0.03
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.012, 0.012, 0.014)
	m.metallic = 0.0
	m.roughness = 0.07
	disc.material_override = m
	_turntable.add_child(disc)
	# Thin lit ring around the edge: the one sharp detail in the room.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.955
	tm.outer_radius = 2.968
	tm.rings = 128
	ring.mesh = tm
	ring.position.y = 0.055
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(1.0, 0.72, 0.25) * 0.45
	ring.material_override = rm
	_turntable.add_child(ring)


## Swap the car on the turntable (menu car picker).
func set_car(model_id: String) -> void:
	if _car_node:
		_car_node.queue_free()
		_car_node = null
	_build_car(model_id)


func _build_car(model_id := "") -> void:
	if model_id == "":
		model_id = Game.car_id
	if not CarModel.available(model_id):
		return
	var d := CarModel.data(model_id)
	var hub_y := 0.0
	var mid_z := 0.0
	for w in d.wheels:
		hub_y += w.centre.y * 0.25
		mid_z += w.centre.z * 0.25
	var car := Node3D.new()
	car.position = Vector3(0, 0.06 + d.wheel_radius - hub_y, -mid_z)
	_turntable.add_child(car)
	_car_node = car
	var body := MeshInstance3D.new()
	body.mesh = d.body
	body.layers = 1 << (CAR_LAYER - 1)
	for i in d.surface_mats.size():
		var m: Material = d.surface_mats[i]
		if i == d.paint_surface and m is BaseMaterial3D:
			_paint = m.duplicate()
			_paint.albedo_color = CarPalette.pick(Game.paint_index)
			_paint.metallic = 0.3
			_paint.roughness = 0.3
			_paint.clearcoat_enabled = true
			_paint.clearcoat = 1.0
			_paint.clearcoat_roughness = 0.05
			m = _paint
		body.set_surface_override_material(i, m)
	car.add_child(body)
	for w in d.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = w.mesh
		wm.position = w.centre
		wm.layers = body.layers
		for k in w.mats.size():
			wm.set_surface_override_material(k, w.mats[k])
		car.add_child(wm)
