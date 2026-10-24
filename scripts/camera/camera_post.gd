class_name CameraPost
extends CanvasLayer
## The in-race lens: one full-screen pass drawn under the HUD (colour grade,
## vignette, speed blur, edge aberration, film grain, sun glare, rain on the
## lens). Owned and fed every frame by ChaseCamera via update_fx().
## Low quality keeps only the grade, vignette and glare. Debug: `--postq=0..3`.

const SHADER := preload("res://shaders/post_process.gdshader")
## Per-weather grade: [S-curve, saturation, shadow tint, highlight tint].
const GRADES := {
	Weather.Kind.CLEAR: [0.16, 1.0, Vector3(-0.006, 0.0, 0.012), Vector3(0.014, 0.006, -0.01)],
	Weather.Kind.GOLDEN: [0.2, 1.0, Vector3(-0.006, -0.002, 0.016), Vector3(0.022, 0.008, -0.016)],
	Weather.Kind.STORM: [0.12, 0.96, Vector3(-0.006, 0.002, 0.012), Vector3(0.0, 0.003, 0.006)],
	Weather.Kind.SNOW: [0.1, 0.97, Vector3(-0.004, 0.0, 0.014), Vector3(0.004, 0.004, 0.007)],
	Weather.Kind.FOG: [0.06, 0.95, Vector3(-0.002, 0.0, 0.006), Vector3(0.002, 0.002, 0.002)],
	Weather.Kind.DAWN: [0.2, 1.0, Vector3(-0.004, -0.002, 0.018), Vector3(0.016, 0.004, 0.002)], # blue shade, rose highlights
}
## Night: a gentle curve (keeps detail in the dark), moonlit blue shadows,
## warm lamp-lit highlights.
const NIGHT_GRADE := [0.08, 0.95, Vector3(-0.004, 0.0, 0.016), Vector3(0.016, 0.008, -0.01)]

var mat: ShaderMaterial
var quality := 1
var rain_weather := false ## raining (not snowing): drops can land on the lens
var _rect: ColorRect
var _sun: DirectionalLight3D
var _sun_energy := 1.0
var _sun_vis := 1.0 ## smoothed, from the occlusion ray
var _sun_target := 1.0
var _ray_frame := 0
var _center := Vector2(0.5, 0.5)
var _rain := 0.0
var _shaft_gain := 0.0 ## sun shafts for this weather (0 = none)
var _shaft := 0.0
var _shaft_target := 1.0
var _shaft_vis := 1.0


func _ready() -> void:
	layer = -1 # under every HUD layer: the HUD is not seen through the lens
	quality = clampi(Game.quality, 0, 3)
	for arg in OS.get_cmdline_user_args(): # debug: --postq=0..3 overrides for the lens only
		if arg.begins_with("--postq="):
			quality = clampi(arg.trim_prefix("--postq=").to_int(), 0, 3)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	_rect = ColorRect.new()
	_rect.name = "Lens"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = mat
	add_child(_rect)
	mat.set_shader_parameter("blur_taps", [0, 6, 8, 10][quality])
	mat.set_shader_parameter("grain", 0.0 if quality == 0 else 0.018)
	rain_weather = Car.weather_road_grip < 0.9 and Car.weather_off_grip >= 0.6
	var scene := get_tree().current_scene
	_sun = scene.find_child("Sun", true, false) as DirectionalLight3D if scene else null
	var kind := Weather.Kind.CLEAR
	var night := Car.night
	if _sun:
		_sun_energy = _sun.light_energy
		kind = _guess_kind()
		for n in _sun.get_parent().get_children(): # the Weather sits next to its Sun
			if n is Weather:
				kind = (n as Weather).kind
				night = (n as Weather).night
	else:
		kind = _guess_kind()
	var g: Array = NIGHT_GRADE if night else GRADES[kind]
	# Sun shafts: strongest with a low sun; 6 taps on Medium, off on Low. Only
	# evaluated while the sun is in or near the frame.
	if not night:
		_shaft_gain = {Weather.Kind.GOLDEN: 0.6, Weather.Kind.DAWN: 0.6, Weather.Kind.CLEAR: 0.25}.get(kind, 0.0)
	for arg in OS.get_cmdline_user_args(): # debug A/B
		if arg.begins_with("--shafts="):
			_shaft_gain *= arg.trim_prefix("--shafts=").to_float()
	mat.set_shader_parameter("shaft_taps", [0, 0, 10, 14][quality] if _shaft_gain > 0.0 else 0)
	mat.set_shader_parameter("curve", g[0])
	mat.set_shader_parameter("saturation", g[1])
	mat.set_shader_parameter("shadow_tint", g[2])
	mat.set_shader_parameter("highlight_tint", g[3])


## Weather from the grip it leaves (when the Weather node can't be found).
func _guess_kind() -> Weather.Kind:
	if Car.weather_off_grip < 0.6:
		return Weather.Kind.SNOW
	if Car.weather_road_grip < 0.9:
		return Weather.Kind.STORM
	return Weather.Kind.CLEAR


## speed_fx 0..1 drives blur and fringe; rain_amount is this camera's share of
## the drops (0 = none); streak 0..1 is how hard the air pushes them; `exclude`
## are physics bodies the sun ray ignores.
func update_fx(cam: Camera3D, speed_fx: float, move_dir: Vector3, rain_amount: float, streak: float, exclude: Array[RID], dt: float) -> void:
	var size := cam.get_viewport().get_visible_rect().size
	if size.x < 1.0:
		return
	mat.set_shader_parameter("aspect", size.x / size.y)
	var fancy := quality > 0
	mat.set_shader_parameter("blur_amount", speed_fx if fancy else 0.0)
	mat.set_shader_parameter("aberration", (0.0025 + speed_fx * 0.006) if fancy else 0.0)
	mat.set_shader_parameter("vignette", 0.26 + speed_fx * 0.08)
	# The blur converges where the car is heading, not just the frame centre.
	var want := Vector2(0.5, 0.5)
	if move_dir.length() > 0.5:
		var p := cam.global_position + move_dir.normalized() * 50.0
		if not cam.is_position_behind(p):
			want = (cam.unproject_position(p) / size).clamp(Vector2(0.25, 0.25), Vector2(0.75, 0.75))
	_center = _center.lerp(want, 1.0 - exp(-dt * 6.0))
	mat.set_shader_parameter("blur_center", _center)
	var wx := Weather.current()
	if wx and wx.cycle: # changeable weather: drops and sun glare follow the live sky
		rain_weather = wx.rain > 0.05
		rain_amount *= clampf(wx.rain * 1.3, 0.0, 1.0)
		if _sun and is_instance_valid(_sun):
			_sun_energy = _sun.light_energy
	_update_sun(cam, size, exclude, dt)
	_rain = move_toward(_rain, rain_amount if (rain_weather and fancy) else 0.0, dt * 1.5)
	mat.set_shader_parameter("rain", _rain)
	mat.set_shader_parameter("rain_streak", clampf(streak, 0.0, 1.0))


func _update_sun(cam: Camera3D, size: Vector2, exclude: Array[RID], dt: float) -> void:
	if _sun == null or not is_instance_valid(_sun) or _sun_energy < 0.9:
		mat.set_shader_parameter("sun_strength", 0.0) # overcast: no hard sun to flare
		mat.set_shader_parameter("shaft_strength", 0.0)
		return
	var to_sun := _sun.global_basis.z.normalized() # the light shines along -Z
	var facing := to_sun.dot(-cam.global_basis.z)
	var sun_pt := cam.global_position + to_sun * 1000.0
	if facing < 0.2 or cam.is_position_behind(sun_pt):
		_sun_vis = 0.0
		_shaft = 0.0
		mat.set_shader_parameter("sun_strength", 0.0)
		mat.set_shader_parameter("shaft_strength", 0.0)
		return
	# Hills, buildings and cars hide the sun (trees and clouds are caught in the
	# shader, which checks the frame is actually bright where the sun is).
	_ray_frame += 1
	if _ray_frame % 3 == 0:
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + to_sun * 1500.0)
		q.exclude = exclude
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		_sun_target = 0.0 if not hit.is_empty() else 1.0
		# A tree trunk hides the glare but not the beams through the forest.
		var trunk: bool = not hit.is_empty() and hit.collider is Node and (hit.collider as Node).name == &"TreeTrunks"
		_shaft_target = 1.0 if hit.is_empty() or trunk else 0.0
	_sun_vis = move_toward(_sun_vis, _sun_target, dt * 4.0)
	_shaft_vis = move_toward(_shaft_vis, _shaft_target, dt * 2.0)
	var uv := cam.unproject_position(sun_pt) / size
	var onscreen := uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0
	# Fade in as the sun nears the frame; strongest looking straight into it.
	var edge := maxf(maxf(-uv.x, uv.x - 1.0), maxf(-uv.y, uv.y - 1.0))
	var near := 1.0 - smoothstep(0.0, 0.35, edge)
	var s := near * smoothstep(0.2, 0.9, facing) * _sun_vis * clampf(_sun_energy / 2.0, 0.5, 1.0)
	mat.set_shader_parameter("sun_uv", uv)
	mat.set_shader_parameter("sun_onscreen", 1.0 if onscreen else 0.0)
	mat.set_shader_parameter("sun_strength", s)
	# Shafts reach further off-frame than the glare (beams fan in from the side).
	var shaft_near := 1.0 - smoothstep(0.0, 0.6, edge)
	_shaft = move_toward(_shaft, shaft_near * smoothstep(0.25, 0.75, facing) * _shaft_vis * _shaft_gain, dt * 2.0)
	mat.set_shader_parameter("shaft_strength", _shaft)
	mat.set_shader_parameter("sun_color", Vector3(_sun.light_color.r, _sun.light_color.g, _sun.light_color.b))

