class_name Weather
extends Node3D
## Weather for a race: sky and light presets, rain or snow falling around the
## camera, lightning with thunder, ambience, and the grip each surface loses.

enum Kind { CLEAR, STORM, SNOW, GOLDEN, DAWN, FOG }
const NAMES := ["Clear", "Storm", "Snow", "Golden hour", "Night", "Night rain", "Night snow", "Changeable", "Changeable night", "Dawn", "Fog"]
## A "condition" (menu choice, track default, --weather=N, Game.weather_override)
## is a Kind (0..3) or a night variant of one: 4 = clear night, 5 = storm at
## night, 6 = snow at night, 7 = changeable (WeatherCycle scenario, seeded per
## race), 8 = changeable at night, 9 = dawn (Kind.DAWN: low cool sun, valley
## mist, dew), 10 = fog (Kind.FOG: ~150 m visibility, damp, lamps on).
## NAMES is indexed by condition.
const NIGHT_KINDS := [Kind.CLEAR, Kind.STORM, Kind.SNOW]
const CONDITIONS := 11
const CHANGEABLE := 7
const DAWN := 9 ## the condition index of Kind.DAWN (its enum value 4 is "Night")
const FOG := 10 ## the condition index of Kind.FOG


static func cond_kind(c: int) -> Kind:
	if c == DAWN:
		return Kind.DAWN
	if c == FOG:
		return Kind.FOG
	if c >= CHANGEABLE:
		return Kind.CLEAR # the scenario decides
	return NIGHT_KINDS[c - 4] if c >= 4 else c as Kind


static func cond_night(c: int) -> bool:
	return c >= 4 and c != CHANGEABLE and c != DAWN and c != FOG


## Weather that changes during the race (conditions 7 and 8).
static func cond_changeable(c: int) -> bool:
	return c == CHANGEABLE or c == CHANGEABLE + 1


static func condition(k: Kind, is_night: bool) -> int:
	if k == Kind.DAWN:
		return DAWN
	if k == Kind.FOG:
		return FOG
	return 4 + NIGHT_KINDS.find(k) if is_night and NIGHT_KINDS.has(k) else int(k)

## Everything that changes with the weather, in one place.
const PRESETS := {
	Kind.CLEAR: {
		hdri = "res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr", sun_u = 0.5947, sun_elev = 48.0,
		sun_energy = 2.2, sun_color = Color(1.0, 0.95, 0.88), sky_energy = 1.0, exposure = 1.0,
		fog = 0.0007, fog_color = Color(0.68, 0.74, 0.82), sky_fog = 0.15,
		road_grip = 1.0, off_grip = 1.0, wet = 0.0, snow = 0.0, saturation = 0.92,
		clouds = 0.42, cloud_soft = 0.16, cloud_wind = Vector2(0.005, 0.002), cloud_bright = 1.6,
		cloud_lit = Color(1.0, 0.98, 0.95), cloud_shadow = Color(0.5, 0.54, 0.62),
		mist = 0.0, haze = 0.6,
	},
	Kind.STORM: {
		hdri = "res://assets/hdri/kloofendal_overcast_puresky_2k.hdr", sun_u = 0.3, sun_elev = 35.0,
		sun_energy = 0.35, sun_color = Color(0.75, 0.8, 0.9), sky_energy = 0.45, exposure = 1.1,
		fog = 0.0045, fog_color = Color(0.3, 0.33, 0.37), sky_fog = 0.55,
		road_grip = 0.8, off_grip = 0.75, wet = 1.0, snow = 0.0, saturation = 0.75,
		clouds = 0.82, cloud_soft = 0.28, cloud_wind = Vector2(0.03, 0.012), cloud_bright = 0.55,
		cloud_lit = Color(0.62, 0.65, 0.7), cloud_shadow = Color(0.14, 0.15, 0.18),
	},
	Kind.GOLDEN: {
		hdri = "res://assets/hdri/qwantani_sunset_puresky_2k.hdr", sun_u = 0.5996, sun_elev = 9.0,
		sun_energy = 1.7, sun_color = Color(1.0, 0.74, 0.48), sky_energy = 1.0, exposure = 1.05,
		fog = 0.0009, fog_color = Color(0.78, 0.62, 0.5), sky_fog = 0.2,
		road_grip = 1.0, off_grip = 1.0, wet = 0.0, snow = 0.0, saturation = 0.97,
		clouds = 0.36, cloud_soft = 0.2, cloud_wind = Vector2(0.004, 0.002), cloud_bright = 1.3,
		cloud_lit = Color(1.0, 0.76, 0.52), cloud_shadow = Color(0.36, 0.3, 0.36),
		mist = 0.35, haze = 1.0,
	},
	# Dawn: the sun just up behind a pink haze, cool blue shade, mist lying in
	# the valleys and dew on the tarmac (looks damp, grips like dry).
	Kind.DAWN: {
		hdri = "res://assets/hdri/qwantani_dawn_puresky_2k.hdr", sun_u = 0.5957, sun_elev = 7.0,
		sun_energy = 1.2, sun_color = Color(1.0, 0.64, 0.58), sky_energy = 0.8, exposure = 1.0,
		fog = 0.0008, fog_color = Color(0.5, 0.5, 0.66), sky_fog = 0.15,
		road_grip = 1.0, off_grip = 1.0, wet = 0.12, snow = 0.0, saturation = 1.0,
		sky_tint_low = Color(1.0, 0.8, 0.84), sky_tint_high = Color(0.78, 0.86, 1.08),
		clouds = 0.22, cloud_soft = 0.22, cloud_wind = Vector2(0.003, 0.0015), cloud_bright = 1.1,
		cloud_lit = Color(1.0, 0.72, 0.7), cloud_shadow = Color(0.4, 0.4, 0.54),
		mist = 1.0, haze = 0.3,
	},
	# Fog: a still, grey, dripping morning; ~150 m to the wall of white, the sun
	# a pale disc at most. Damp tarmac, a touch less grip.
	Kind.FOG: {
		hdri = "res://assets/hdri/kloofendal_overcast_puresky_2k.hdr", sun_u = 0.55, sun_elev = 22.0,
		sun_energy = 0.4, sun_color = Color(0.92, 0.92, 0.9), sky_energy = 0.7, exposure = 1.05,
		fog = 0.02, fog_color = Color(0.6, 0.62, 0.64), sky_fog = 1.0,
		road_grip = 0.95, off_grip = 0.9, wet = 0.35, snow = 0.0, saturation = 0.82,
		clouds = 0.95, cloud_soft = 0.35, cloud_wind = Vector2(0.002, 0.001), cloud_bright = 0.8,
		cloud_lit = Color(0.8, 0.8, 0.8), cloud_shadow = Color(0.55, 0.56, 0.58),
		mist = 0.8, haze = 0.0,
	},
	Kind.SNOW: {
		hdri = "res://assets/hdri/snow_field_puresky_2k.hdr", sun_u = 0.55, sun_elev = 25.0,
		sun_energy = 0.7, sun_color = Color(0.92, 0.95, 1.0), sky_energy = 0.8, exposure = 1.0,
		fog = 0.0055, fog_color = Color(0.78, 0.81, 0.86), sky_fog = 0.6,
		road_grip = 0.62, off_grip = 0.5, wet = 0.3, snow = 1.0, saturation = 0.8,
		clouds = 0.72, cloud_soft = 0.3, cloud_wind = Vector2(0.012, 0.006), cloud_bright = 1.0,
		cloud_lit = Color(0.95, 0.96, 0.98), cloud_shadow = Color(0.55, 0.57, 0.62),
	},
}

## Night keys laid over a day preset (grip, wetness and snow stay the day's).
## (FOG only appears at night as the heavy end of "fog_lifting" after dark.)
## The sky is a dim CC0 night HDRI with its photographed moon clipped, plus
## procedural stars and moon disc; the "sun" becomes cool, low moonlight.
const NIGHT := {
	Kind.CLEAR: {
		hdri = "res://assets/hdri/kloppenheim_02_puresky_2k.hdr", sun_u = 0.5986, sun_elev = 17.2,
		sun_energy = 0.16, sun_color = Color(0.62, 0.72, 1.0), sky_energy = 0.07, exposure = 1.25,
		fog = 0.0012, fog_color = Color(0.035, 0.045, 0.07), sky_fog = 0.15, saturation = 0.85,
		clouds = 0.26, cloud_bright = 0.35, cloud_lit = Color(0.55, 0.62, 0.8), cloud_shadow = Color(0.05, 0.06, 0.09),
		stars = 1.0, moon = 1.0,
	},
	Kind.STORM: {
		hdri = "res://assets/hdri/kloppenheim_07_puresky_2k.hdr", sun_u = 0.5986, sun_elev = 38.0,
		sun_energy = 0.03, sun_color = Color(0.6, 0.68, 0.85), sky_energy = 0.05, exposure = 1.3,
		fog = 0.006, fog_color = Color(0.03, 0.033, 0.04), sky_fog = 0.7, saturation = 0.75,
		cloud_bright = 0.5, cloud_lit = Color(0.4, 0.4, 0.44), cloud_shadow = Color(0.08, 0.08, 0.1),
		stars = 0.0, moon = 0.0,
	},
	Kind.FOG: {
		hdri = "res://assets/hdri/kloppenheim_07_puresky_2k.hdr", sun_u = 0.5986, sun_elev = 38.0,
		sun_energy = 0.03, sun_color = Color(0.6, 0.65, 0.8), sky_energy = 0.05, exposure = 1.3,
		fog = 0.012, fog_color = Color(0.035, 0.038, 0.045), sky_fog = 0.9, saturation = 0.8,
		cloud_bright = 0.4, cloud_lit = Color(0.4, 0.4, 0.44), cloud_shadow = Color(0.08, 0.08, 0.1),
		stars = 0.0, moon = 0.0,
	},
	Kind.SNOW: {
		hdri = "res://assets/hdri/kloppenheim_07_puresky_2k.hdr", sun_u = 0.5986, sun_elev = 38.0,
		sun_energy = 0.05, sun_color = Color(0.65, 0.72, 0.9), sky_energy = 0.06, exposure = 1.25,
		fog = 0.0065, fog_color = Color(0.05, 0.055, 0.07), sky_fog = 0.75, saturation = 0.8,
		cloud_bright = 0.6, cloud_lit = Color(0.45, 0.46, 0.52), cloud_shadow = Color(0.1, 0.1, 0.12),
		stars = 0.0, moon = 0.0,
	},
}

var kind := Kind.CLEAR
var night := false
var preset: Dictionary
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D

var _precip: GPUParticles3D
var _flash: DirectionalLight3D
var _next_strike := 6.0
var _strike_t := -1.0
var _thunder_in := -1.0
var _thunder: AudioStreamPlayer
var _ambience: AudioStreamPlayer

# --- Live state (0..1). Constant for a fixed preset; WeatherCycle drives it
# for changeable weather. Read it with Weather.current().
var clouds := 0.0 ## sky gloom: 0 fair .. 1 full overcast
var rain := 0.0 ## falling rain intensity
var snowfall := 0.0 ## falling snow intensity
var wetness := 0.0 ## water on the track: lags behind the rain, dries slowly
var wetness_line := 0.0 ## the same on the racing line (dries first); drives grip
var snow_cover := 0.0 ## snow lying on the ground
var wind := 0.3 ## 0 calm .. 1 storm (also the wx_wind shader global)
var clock := 0.0 ## race clock (s) the changeable weather follows; set by Race
var cycle: WeatherCycle ## null for a fixed preset
static var _current: Weather
var _timeline := {}
var _rain_fx: GPUParticles3D
var _snow_fx: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _wind_audio: AudioStreamPlayer
var _clock_seen := 0.0
var _pushed := PackedFloat32Array([-1, -1, -1, -1, -1])


## The race's Weather (null in menus).
static func current() -> Weather:
	return _current if is_instance_valid(_current) else null


static func preset_for(k: Kind, is_night := false) -> Dictionary:
	if not is_night or not NIGHT.has(k):
		return PRESETS[k]
	var p: Dictionary = (PRESETS[k] as Dictionary).duplicate()
	p.merge(NIGHT[k], true)
	p.night = 1.0
	return p


## Sets up sky, light and fog on `parent`, returns the Weather node (already added).
## `k` may be a condition (4..6 = night) or a Kind with `is_night`.
## Changeable (7, 8): `timeline` from WeatherCycle.make_timeline (the host's,
## online); empty = a random scenario.
static func create(parent: Node3D, k: int, is_night := false, timeline := {}) -> Weather:
	var w := Weather.new()
	w.name = "Weather"
	w.kind = cond_kind(k)
	w.night = is_night or cond_night(k)
	if cond_changeable(k):
		w._timeline = timeline if not timeline.is_empty() else WeatherCycle.make_timeline(randi())
		if w.night and int(w._timeline.get("base", 0)) == Kind.DAWN: # no dawn at night
			w._timeline = w._timeline.duplicate()
			w._timeline.base = int(Kind.CLEAR)
		w.kind = int(w._timeline.get("base", 0)) as Kind
	w.preset = preset_for(w.kind, w.night)
	parent.add_child(w)
	_current = w
	w._build_environment(parent)
	# Tyres read these: a wet or snowy surface simply has less grip.
	Car.weather_road_grip = w.preset.road_grip
	Car.weather_off_grip = w.preset.off_grip
	if w._timeline.is_empty():
		w._fixed_state()
	else:
		w.cycle = WeatherCycle.new()
		w.cycle.name = "Cycle"
		w.add_child(w.cycle)
		w.cycle.setup(w, w._timeline)
	w._push_globals()
	return w


func _fixed_state() -> void:
	clouds = 1.0 if kind == Kind.STORM or kind == Kind.SNOW or kind == Kind.FOG else 0.1
	rain = 1.0 if kind == Kind.STORM else 0.0
	snowfall = 1.0 if kind == Kind.SNOW else 0.0
	wetness = float(preset.wet)
	wetness_line = wetness
	snow_cover = float(preset.snow)
	wind = [0.3, 0.9, 0.45, 0.3, 0.15, 0.08][kind]
	Car.lamps_on = true


## wx_* global shader parameters (shaders/weather.gdshaderinc), when they change.
func _push_globals() -> void:
	var v := PackedFloat32Array([wetness, wetness_line, snow_cover, rain, wind])
	var names := ["wx_wet", "wx_wet_line", "wx_snow", "wx_rain", "wx_wind"]
	for i in v.size():
		if absf(v[i] - _pushed[i]) > 0.001:
			_pushed[i] = v[i]
			RenderingServer.global_shader_parameter_set(names[i], v[i])


func _exit_tree() -> void:
	if _current == self:
		_current = null
		for n in ["wx_wet", "wx_wet_line", "wx_snow", "wx_rain", "wx_wind"]:
			RenderingServer.global_shader_parameter_set(n, 0.0)


## Rain / snow emitters and their sound follow the live intensities (changeable).
func set_precipitation(r: float, s: float, wnd: float) -> void:
	if _rain_fx:
		_rain_fx.amount_ratio = clampf(r, 0.0, 1.0)
		_rain_fx.emitting = r > 0.003
	if _snow_fx:
		_snow_fx.amount_ratio = clampf(s, 0.0, 1.0)
		_snow_fx.emitting = s > 0.003
	if _rain_audio:
		_rain_audio.volume_db = -9.0 + 12.0 * log(maxf(r, 0.001)) / log(10.0)
	if _wind_audio:
		_wind_audio.volume_db = -16.0 + 14.0 * log(maxf(maxf(s, wnd - 0.3), 0.001)) / log(10.0)


func _build_environment(parent: Node3D) -> void:
	var p := preset
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("panorama", load(p.hdri))
	sky_mat.set_shader_parameter("panorama_energy", p.sky_energy)
	sky_mat.set_shader_parameter("cloud_noise", _cloud_noise())
	sky_mat.set_shader_parameter("coverage", p.clouds)
	sky_mat.set_shader_parameter("softness", p.cloud_soft)
	sky_mat.set_shader_parameter("wind", p.cloud_wind)
	sky_mat.set_shader_parameter("cloud_brightness", p.cloud_bright * p.sky_energy)
	sky_mat.set_shader_parameter("cloud_lit", p.cloud_lit)
	sky_mat.set_shader_parameter("cloud_shadow", p.cloud_shadow)
	if night:
		_night_sky(p)
	# Distant mountain ranges on the horizon, snow-capped above the tree line.
	sky_mat.set_shader_parameter("ridge_strength", 0.0 if kind == Kind.FOG else 1.0) # nothing shows through fog
	sky_mat.set_shader_parameter("tint_low", p.get("sky_tint_low", Color.WHITE))
	sky_mat.set_shader_parameter("tint_high", p.get("sky_tint_high", Color.WHITE))
	sky_mat.set_shader_parameter("ridge_snow", 1.0 if kind == Kind.SNOW else 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	# The clouds move, so lighting from the sky is refreshed a little every frame
	# instead of all at once (a full rebuild per frame costs ~10 ms on an M1).
	# 512 is sharp enough for paint and chrome to reflect clouds; the animated sky
	# re-renders it every frame, so Low/Medium use 256.
	sky.radiance_size = Sky.RADIANCE_SIZE_512 if Game.quality >= 2 else Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = p.exposure * 0.88
	# The HDRI sky alone lit shaded areas almost as brightly as the sun, so cast
	# shadows (cars, gantries, buildings) vanished. Mix the sky ambient down with
	# a dimmer sky-tinted colour and let the sun carry more of the light.
	if not night:
		env.ambient_light_sky_contribution = 0.6
		env.ambient_light_color = p.fog_color
		env.ambient_light_energy = 0.5
	var q := Game.quality
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.25 if kind == Kind.CLEAR else 0.45
	env.glow_bloom = 0.03
	if night: # lamps and headlights bloom softly, dark areas stay black
		env.glow_intensity = 0.6
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.2
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_strength = 0.9
		env.ambient_light_energy = 1.0
		# Ambient occlusion of near-black moonlit ambient is invisible; on Medium
		# and below the frame time goes to lights instead.
		if q <= 1:
			env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_light_color = p.fog_color
	env.fog_density = p.fog
	env.fog_aerial_perspective = 0.6 if not night else 0.25 # the black sky mustn't paint distant hills
	env.fog_sky_affect = p.sky_fog
	env.ssr_enabled = kind == Kind.STORM and q >= 2 # wet tarmac mirrors the cars and sky (High+: ~3 ms on an M1)
	env.ssil_enabled = q >= 3
	env.ssr_max_steps = 48
	env.adjustment_enabled = true
	env.adjustment_saturation = p.saturation
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	var phi := TAU * float(p.sun_u)
	var e := deg_to_rad(p.sun_elev)
	var dir := Vector3(sin(phi) * cos(e), sin(e), -cos(phi) * cos(e)).normalized()
	sun.basis = Basis.looking_at(-dir, Vector3.UP)
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy * (1.0 if night else 1.4)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2 if kind == Kind.CLEAR else (2.0 if kind == Kind.DAWN else 4.0) # overcast: soft, faint shadows
	if (kind == Kind.STORM or kind == Kind.FOG) and _timeline.is_empty():
		sun.shadow_enabled = false # closed storm overcast: no sun shadows to see, skip the pass
	if night:
		sun.name = "Sun" # (the moon) CameraPost finds it by name; glare stays off below 0.9 energy
		# Moon shadows only under a clear sky, and only on High+: the low moon's shadow
		# pass takes in far more casters (~300 draw calls on kiefernring).
		sun.shadow_enabled = kind == Kind.CLEAR and Game.quality >= 2
		sun.shadow_blur = 2.0
		sun.light_specular = 0.6
	# Low / Medium: one shadow map, not split cascades, so the scene is drawn into it
	# once per frame. Shadows only have to be there (contact, cars, gantries), not
	# reach far: frame rate first on integrated GPUs.
	sun.directional_shadow_max_distance = [70.0, 80.0, 160.0, 250.0][q]
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if q <= 1 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = q >= 2
	# Fade shadows in over the far half of their range instead of the last 20 %:
	# a bridge's or tree's shadow grows in as you approach rather than popping on.
	sun.directional_shadow_fade_start = 0.4 if q <= 1 else 0.6
	parent.add_child(sun)

	# Changeable weather builds everything its scenario can need up front (idle
	# until then), so nothing is created or compiled mid-race.
	var heavy_kind: int = int(_timeline.get("heavy", -1))
	if kind == Kind.STORM or heavy_kind == Kind.STORM:
		_flash = DirectionalLight3D.new()
		_flash.rotation_degrees = Vector3(-60, 40, 0)
		_flash.light_color = Color(0.85, 0.9, 1.0)
		_flash.light_energy = 0.0
		_flash.shadow_enabled = false
		_flash.visible = false # only while a strike flickers: an idle light still costs shading
		parent.add_child(_flash)
		_rain_fx = _rain()
		_thunder = AudioStreamPlayer.new()
		_thunder.stream = _thunder_sound()
		_thunder.bus = &"Ambience"
		add_child(_thunder)
		_rain_audio = _loop_player(_noise_ambience(0.9, 2600.0, 0.55), -9.0) # rain hiss
	if kind == Kind.SNOW or heavy_kind == Kind.SNOW:
		_snow_fx = _snowfall()
		_wind_audio = _loop_player(_noise_ambience(2.0, 300.0, 0.0), -16.0) # muffled wind
	_precip = _rain_fx if _rain_fx else _snow_fx
	_ambience = _rain_audio if _rain_audio else _wind_audio
	for fx: GPUParticles3D in [_rain_fx, _snow_fx]:
		if fx:
			add_child(fx)
			if night:
				_night_precip(fx)
	if not _timeline.is_empty():
		sky_mat.set_shader_parameter("panorama_b", load(preset_for(heavy_kind as Kind, night).hdri))
		sky_mat.set_shader_parameter("wind", Vector2.ZERO) # WeatherCycle integrates cloud_drift instead


func _process(dt: float) -> void:
	if cycle:
		cycle.apply(dt)
		_push_globals()
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Keep the rain/snow volume around (and a bit ahead of) the camera.
		var ahead := -cam.global_basis.z
		ahead.y = 0.0
		for fx: GPUParticles3D in [_rain_fx, _snow_fx]:
			if fx and fx.emitting:
				fx.global_position = cam.global_position + ahead * 18.0 + Vector3.UP * 14.0
	if _flash == null:
		return
	if cycle:
		# Strikes come from the shared timeline, so everyone sees the same flash.
		if cycle.strike_between(_clock_seen, clock):
			_strike_t = 0.0
			_thunder_in = randf_range(0.6, 3.0)
		_clock_seen = clock
	else:
		_next_strike -= dt
		if _next_strike <= 0.0:
			_next_strike = randf_range(7.0, 16.0)
			_strike_t = 0.0
			_thunder_in = randf_range(0.6, 3.0)
	if _strike_t >= 0.0:
		_strike_t += dt
		# Two or three quick flickers, then darkness again.
		var flick := 0.0
		for k in 3:
			var t0 := k * 0.11
			if _strike_t > t0 and _strike_t < t0 + 0.07:
				flick = 1.0 - k * 0.3
		_flash.visible = true
		_flash.light_energy = flick * 3.0
		sky_mat.set_shader_parameter("flash", flick)
		if _strike_t > 0.45:
			_strike_t = -1.0
			_flash.light_energy = 0.0
			_flash.visible = false
			sky_mat.set_shader_parameter("flash", 0.0)
	if _thunder_in >= 0.0:
		_thunder_in -= dt
		if _thunder_in < 0.0:
			_thunder.pitch_scale = randf_range(0.8, 1.15)
			_thunder.volume_db = randf_range(-6.0, 0.0)
			_thunder.play()


## Soft, puffy fBm noise for the cloud deck (tiles seamlessly).
static func _cloud_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.008
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	var t := NoiseTexture2D.new()
	t.noise = n
	t.width = 512
	t.height = 512
	t.seamless = true
	t.generate_mipmaps = true
	return t


## Night sky: clip the HDRI's photographed moon, draw stars and a moon disc
## where the moonlight comes from.
func _night_sky(p: Dictionary) -> void:
	sky_mat.set_shader_parameter("panorama_clamp", 3.0)
	sky_mat.set_shader_parameter("star_strength", float(p.get("stars", 0.0)) * 0.9)
	if float(p.get("moon", 0.0)) > 0.0:
		var phi := TAU * float(p.sun_u)
		var e := deg_to_rad(p.sun_elev)
		sky_mat.set_shader_parameter("moon_dir", Vector3(sin(phi) * cos(e), sin(e), -cos(phi) * cos(e)))
		sky_mat.set_shader_parameter("moon_size", deg_to_rad(0.75))
		sky_mat.set_shader_parameter("moon_energy", 7.0)


## Night: drops and flakes are lit (per vertex, cheap) instead of glowing on
## their own, so they only sparkle in headlights and under the lamps.
func _night_precip(fx: GPUParticles3D) -> void:
	var m := (fx.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	if m:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.roughness = 1.0


# ---------------------------------------------------------------- precipitation

func _rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	# Per quality: the drops are tiny, so fewer of them hardly shows, but each
	# costs particle processing and overdraw near the camera.
	p.amount = [5000, 9000, 16000, 20000][clampi(Game.quality, 0, 3)]
	p.lifetime = 1.1
	p.preprocess = 1.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 60, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 2, 38)
	pm.direction = Vector3(0.18, -1, 0.08)
	pm.spread = 3.0
	pm.initial_velocity_min = 24.0
	pm.initial_velocity_max = 30.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT # roofs (GxWarehouse collision boxes)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.75)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.79, 0.85, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	quad.material = m
	p.draw_pass_1 = quad
	return p


func _snowfall() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = [7000, 12000, 18000, 22000][clampi(Game.quality, 0, 3)]
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 60, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(40, 4, 40)
	pm.direction = Vector3(0.3, -1, 0.1)
	pm.spread = 25.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.4, -0.8, 0.2)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT # roofs (GxWarehouse collision boxes)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	m.albedo_texture = tex
	m.albedo_color = Color(0.97, 0.98, 1.0, 0.9)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	p.draw_pass_1 = quad
	return p


# ---------------------------------------------------------------- sound

func _loop_player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = db
	a.bus = &"Ambience"
	a.autoplay = true
	add_child(a)
	return a


## Filtered-noise loop (rain hiss when high, wind when low), crossfaded seam.
func _noise_ambience(dur: float, cutoff: float, crackle: float) -> AudioStreamWAV:
	var rate := CarAudio.RATE
	var n := int(dur * rate)
	var fade := int(0.2 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cutoff)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	var gust := 0.0
	for j in raw.size():
		var x := rng.randf_range(-1.0, 1.0)
		if crackle > 0.0 and rng.randf() < 0.002:
			x += rng.randf_range(-3.0, 3.0) * crackle # individual heavy drops
		y += a * (x - y)
		gust = 0.7 + 0.3 * sin(TAU * j / (dur * rate) * 2.0)
		raw[j] = y * gust
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		buf[j] = raw[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = raw[j] * w + raw[n + j] * (1.0 - w)
	return CarAudio._to_wav(CarAudio._normalise(buf, 0.7), true)


## Rolling thunder: a sharp crack decaying into a long low rumble.
func _thunder_sound() -> AudioStreamWAV:
	var rate := CarAudio.RATE
	var n := int(4.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lo := 0.0
	var mid := 0.0
	for j in n:
		var t := float(j) / rate
		var x := rng.randf_range(-1.0, 1.0)
		lo += 0.012 * (x - lo)
		mid += 0.08 * (x - mid)
		var rumble := lo * 6.0 * exp(-t / 1.6) * (0.6 + 0.4 * sin(TAU * 0.9 * t + sin(TAU * 0.37 * t) * 2.0))
		var crack := mid * exp(-t / 0.18) * 1.5
		buf[j] = rumble + crack
	return CarAudio._to_wav(CarAudio._normalise(buf, 0.9), false)
