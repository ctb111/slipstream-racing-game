class_name WeatherCycle
extends Node
## Changeable weather: a timeline of targets (cloud gloom, rain, snowfall, wind)
## that the live weather follows during the race, e.g. a dry start with clouds
## building, drizzle, then a full thunderstorm, or a storm that clears and dries.
##
## The timeline is a plain Dictionary so the host can send it to every player
## (Net lobby "weather_timeline"); the state is then a pure function of the
## timeline and the race clock (Weather.clock), so all machines see the same sky.
## Track wetness and snow cover are integrated in fixed 0.25 s steps from t = 0,
## so they don't depend on frame rate either.
##
## Everything is driven through uniforms, light/env properties, particle
## amount_ratio and the wx_* global shader parameters: nothing is rebuilt and
## no shader recompiles while the weather changes.

## A change worth telling the driver about (race HUD banner).
signal news(text: String, sub: String)

const STEP := 0.25 ## integration step for wetness / snow cover (s)
const SCENARIOS := ["clear_to_storm", "storm_clearing", "passing_shower", "snow_arrives", "golden_storm", "drizzle_to_downpour", "fog_lifting"]
const SCENARIO_NAMES := {
	clear_to_storm = "Storm building", storm_clearing = "Clearing up", passing_shower = "Passing shower",
	snow_arrives = "Snow coming", golden_storm = "Sunset storm", drizzle_to_downpour = "Drizzle to downpour",
	fog_lifting = "Morning fog lifting",
}

var weather: Weather
var timeline: Dictionary
var base: Dictionary ## look at gloom 0 (fair weather preset)
var heavy: Dictionary ## look at gloom 1 (storm / snow preset)

var _keys: Array = [] ## [t, gloom, rain, snowfall, wind], sorted by t
var _sim_t := 0.0 ## integrated up to here
var _wet := 0.0
var _wet_line := 0.0
var _cover := 0.0
var _drift := Vector2.ZERO
var _strikes := PackedFloat32Array() ## lightning times (s), same on every machine
var _strike_i := 0
var _ssr_ok := false
var _log := false
var _phase := "" ## last announced condition
var _log_t := -INF
var _shadow_base := true
var _shadow_toggle := true
var _worst_dt := 0.0 ## longest frame since the last log line (hitch check)


## Host / single player: pick (or force) a scenario and lay out its timeline.
## Only plain types inside, so it goes over the network as is.
static func make_timeline(seed: int, force := "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var name: String = force if SCENARIOS.has(force) else SCENARIOS[rng.randi() % SCENARIOS.size()]
	var k: Array = []
	var b := Weather.Kind.CLEAR
	var h := Weather.Kind.STORM
	var wet0 := 0.0
	var snow0 := 0.0
	var t := 0.0
	match name:
		"clear_to_storm":
			k.append([0.0, 0.08, 0.0, 0.0, 0.25])
			t = rng.randf_range(20.0, 50.0); k.append([t, 0.12, 0.0, 0.0, 0.3]) # clouds start building
			t += rng.randf_range(50.0, 80.0); k.append([t, 0.72, 0.0, 0.0, 0.55])
			t += rng.randf_range(15.0, 30.0); k.append([t, 0.82, 0.22, 0.0, 0.6]) # drizzle
			t += rng.randf_range(35.0, 60.0); k.append([t, 0.88, 0.45, 0.0, 0.7])
			t += rng.randf_range(25.0, 45.0); k.append([t, 1.0, 1.0, 0.0, 1.0]) # thunderstorm
		"golden_storm":
			b = Weather.Kind.GOLDEN
			k.append([0.0, 0.05, 0.0, 0.0, 0.2])
			t = rng.randf_range(15.0, 40.0); k.append([t, 0.1, 0.0, 0.0, 0.25])
			t += rng.randf_range(45.0, 70.0); k.append([t, 0.75, 0.1, 0.0, 0.6])
			t += rng.randf_range(20.0, 35.0); k.append([t, 0.9, 0.5, 0.0, 0.8])
			t += rng.randf_range(20.0, 40.0); k.append([t, 1.0, 1.0, 0.0, 1.0])
		"storm_clearing":
			wet0 = 1.0
			k.append([0.0, 1.0, 1.0, 0.0, 0.95])
			t = rng.randf_range(40.0, 90.0); k.append([t, 1.0, 0.85, 0.0, 0.9])
			t += rng.randf_range(30.0, 50.0); k.append([t, 0.85, 0.3, 0.0, 0.65]) # easing off
			t += rng.randf_range(25.0, 40.0); k.append([t, 0.7, 0.0, 0.0, 0.5]) # stops
			t += rng.randf_range(50.0, 90.0); k.append([t, 0.15, 0.0, 0.0, 0.3]) # sun breaks through
		"passing_shower":
			k.append([0.0, 0.1, 0.0, 0.0, 0.3])
			t = rng.randf_range(25.0, 60.0); k.append([t, 0.15, 0.0, 0.0, 0.3])
			t += rng.randf_range(35.0, 55.0); k.append([t, 0.8, 0.0, 0.0, 0.6])
			t += rng.randf_range(12.0, 20.0); k.append([t, 0.9, 0.7, 0.0, 0.75]) # heavy shower
			t += rng.randf_range(50.0, 90.0); k.append([t, 0.88, 0.6, 0.0, 0.7])
			t += rng.randf_range(20.0, 35.0); k.append([t, 0.55, 0.0, 0.0, 0.45])
			t += rng.randf_range(40.0, 60.0); k.append([t, 0.12, 0.0, 0.0, 0.3]) # dries out
		"snow_arrives":
			h = Weather.Kind.SNOW
			wet0 = 0.1
			k.append([0.0, 0.4, 0.0, 0.0, 0.3])
			t = rng.randf_range(20.0, 50.0); k.append([t, 0.5, 0.0, 0.0, 0.35])
			t += rng.randf_range(30.0, 50.0); k.append([t, 0.75, 0.0, 0.25, 0.45]) # first flakes
			t += rng.randf_range(40.0, 70.0); k.append([t, 0.9, 0.0, 0.55, 0.5])
			t += rng.randf_range(40.0, 70.0); k.append([t, 1.0, 0.0, 1.0, 0.65]) # heavy snow
		"fog_lifting": # dawn fog that thins and burns off as the sun climbs
			b = Weather.Kind.DAWN
			h = Weather.Kind.FOG
			wet0 = 0.3
			k.append([0.0, 1.0, 0.0, 0.0, 0.05])
			t = rng.randf_range(40.0, 80.0); k.append([t, 0.95, 0.0, 0.0, 0.08])
			t += rng.randf_range(60.0, 90.0); k.append([t, 0.55, 0.0, 0.0, 0.15]) # thinning
			t += rng.randf_range(60.0, 90.0); k.append([t, 0.1, 0.0, 0.0, 0.2]) # burnt off
		"drizzle_to_downpour":
			wet0 = 0.35
			k.append([0.0, 0.8, 0.2, 0.0, 0.5])
			t = rng.randf_range(40.0, 90.0); k.append([t, 0.82, 0.25, 0.0, 0.5])
			t += rng.randf_range(30.0, 60.0); k.append([t, 0.95, 0.7, 0.0, 0.8])
			t += rng.randf_range(15.0, 30.0); k.append([t, 1.0, 1.0, 0.0, 1.0])
	return {name = name, seed = seed, base = int(b), heavy = int(h), wet0 = wet0, snow0 = snow0, keys = k}


## A fresh timeline for the next race: random, or from the debug args
## `--weather_script=<scenario>` and `--weather_seed=<n>`.
static func roll() -> Dictionary:
	var seed := randi()
	var force := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weather_seed="):
			seed = arg.trim_prefix("--weather_seed=").to_int()
		elif arg.begins_with("--weather_script="):
			force = arg.trim_prefix("--weather_script=")
	return make_timeline(seed, force)


## Attach to a Weather built from preset_for(timeline.base) with all the
## rain/snow/lightning parts present (see Weather.create).
func setup(w: Weather, tl: Dictionary) -> void:
	weather = w
	timeline = tl
	_keys = tl.get("keys", [[0.0, 0.1, 0.0, 0.0, 0.3]])
	base = Weather.preset_for(int(tl.get("base", 0)) as Weather.Kind, w.night)
	heavy = Weather.preset_for(int(tl.get("heavy", 1)) as Weather.Kind, w.night)
	_wet = float(tl.get("wet0", 0.0))
	_wet_line = _wet
	_cover = float(tl.get("snow0", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(tl.get("seed", 0)) + 77
	var s := 4.0
	while s < 3600.0:
		s += rng.randf_range(6.0, 15.0)
		_strikes.append(s)
	_ssr_ok = Game.quality >= 2 # same rule as a fixed storm
	_shadow_base = w.sun.shadow_enabled
	_shadow_toggle = not OS.get_cmdline_user_args().has("--weather_keep_shadows") # debug A/B
	_log = OS.get_cmdline_user_args().has("--weather_log") or OS.get_cmdline_user_args().has("--telemetry")
	if _log:
		print("weather: %s  keys %s" % [describe(), str(_keys)])
	_sample(0.0)
	apply(0.0)


## Target values at time t (smoothly interpolated keyframes).
func targets(t: float) -> Array:
	if _keys.is_empty():
		return [0.0, 0.0, 0.0, 0.3]
	var last: Array = _keys[-1]
	if t >= float(last[0]):
		return last.slice(1)
	var prev: Array = _keys[0]
	for i in range(1, _keys.size()):
		var nxt: Array = _keys[i]
		if t < float(nxt[0]):
			var u := smoothstep(float(prev[0]), float(nxt[0]), t)
			var out := []
			for j in range(1, 5):
				out.append(lerpf(float(prev[j]), float(nxt[j]), u))
			return out
		prev = nxt
	return last.slice(1)


## Advance the simulated surface (fixed steps) up to t, and read the targets.
func _sample(t: float) -> void:
	while _sim_t + STEP <= t:
		_sim_t += STEP
		var tg := targets(_sim_t)
		_integrate(STEP, tg[0], tg[1], tg[2], tg[3])
	var now := targets(maxf(t, 0.0))
	weather.clouds = now[0]
	weather.rain = now[1]
	weather.snowfall = now[2]
	weather.wind = now[3]
	weather.wetness = _wet
	weather.wetness_line = _wet_line
	weather.snow_cover = _cover


## Water on the track follows the rain with a lag and dries slowly (faster in
## sun and wind; the racing line, swept by tyres, dries about twice as fast).
func _integrate(h: float, gloom: float, rain: float, snowfall: float, wind: float) -> void:
	var eq := clampf(rain * 1.3, 0.0, 1.0)
	var slush := _cover * 0.3 # snow melting under the tyres
	eq = maxf(eq, slush)
	if _wet < eq:
		_wet = minf(eq, _wet + ((eq - _wet) / 40.0 + rain * 0.004) * h)
	else:
		var dry := (0.002 + 0.003 * (1.0 - gloom) + 0.002 * wind) * h # ~3-8 min from soaked
		_wet = maxf(eq, _wet - dry)
	if _wet_line < eq:
		_wet_line = minf(eq, _wet_line + ((eq - _wet_line) / 35.0 + rain * 0.005) * h)
	else:
		_wet_line = maxf(eq, _wet_line - (0.002 + 0.003 * (1.0 - gloom) + 0.002 * wind) * 1.8 * h)
	_wet_line = minf(_wet_line, _wet + 0.05)
	if _cover < snowfall:
		_cover = minf(snowfall, _cover + ((snowfall - _cover) / 60.0 + snowfall * 0.002) * h)
	else:
		_cover = maxf(snowfall, _cover - (0.0015 + rain * 0.02 + (1.0 - gloom) * 0.002) * h)


## Per frame: drive every visual and the grip from the state at Weather.clock.
func apply(dt: float) -> void:
	_sample(weather.clock)
	var w := weather
	var g := w.clouds
	var snowy := float(heavy.get("snow", 0.0)) > 0.5
	# Look: fair preset -> heavy preset with the gloom. Precipitation darkens a
	# little on top so a shower under a bright sky still reads as rain.
	var gl := clampf(g + (w.rain + w.snowfall) * 0.08, 0.0, 1.0)
	var sm := smoothstep(0.0, 1.0, gl)
	var sky := w.sky_mat
	sky.set_shader_parameter("coverage", lerpf(float(base.clouds), maxf(float(heavy.clouds), 0.9 if not snowy else 0.8), gl))
	sky.set_shader_parameter("softness", lerpf(float(base.cloud_soft), float(heavy.cloud_soft), gl))
	sky.set_shader_parameter("cloud_brightness", lerpf(float(base.cloud_bright) * float(base.sky_energy), float(heavy.cloud_bright) * float(heavy.sky_energy), sm))
	sky.set_shader_parameter("cloud_lit", (base.cloud_lit as Color).lerp(heavy.cloud_lit, sm))
	sky.set_shader_parameter("cloud_shadow", (base.cloud_shadow as Color).lerp(heavy.cloud_shadow, sm))
	sky.set_shader_parameter("panorama_energy", lerpf(float(base.sky_energy), float(heavy.sky_energy), sm))
	sky.set_shader_parameter("panorama_b_energy", float(heavy.sky_energy))
	sky.set_shader_parameter("pano_mix", smoothstep(0.35, 0.9, gl))
	if w.night:
		sky.set_shader_parameter("star_strength", float(base.get("stars", 0.0)) * 0.9 * (1.0 - smoothstep(0.2, 0.7, gl)))
	# Clouds drift with the wind; integrated so a change of wind never jumps.
	var cw: Vector2 = (base.cloud_wind as Vector2).lerp(heavy.cloud_wind, clampf(w.wind * 1.1 - 0.1, 0.0, 1.0))
	_drift += cw * dt
	sky.set_shader_parameter("cloud_drift", _drift)

	var env := w.env
	env.tonemap_exposure = lerpf(float(base.exposure), float(heavy.exposure), sm) * 0.88
	env.fog_density = lerpf(float(base.fog), float(heavy.fog), sm * sm) * (1.0 + w.rain * 0.3)
	env.fog_light_color = (base.fog_color as Color).lerp(heavy.fog_color, sm)
	env.fog_sky_affect = lerpf(float(base.sky_fog), float(heavy.sky_fog), sm)
	env.adjustment_saturation = lerpf(float(base.saturation), float(heavy.saturation), sm) + Weather.SAT_BOOST
	if not w.night:
		env.glow_intensity = lerpf(0.25, 0.45, sm)
	# Standing water mirrors the cars and sky: SSR only once the track is wet
	# (it's an effect toggle, not a material change; nothing recompiles).
	var want_ssr := _ssr_ok and w.wetness > 0.3
	if want_ssr != env.ssr_enabled and (want_ssr or w.wetness < 0.2):
		env.ssr_enabled = want_ssr

	var sun := w.sun
	sun.light_energy = lerpf(float(base.sun_energy), float(heavy.sun_energy), sm) * (1.0 - 0.15 * w.rain) * 1.4 # matches Weather (ambient mixed down)
	sun.light_color = (base.sun_color as Color).lerp(heavy.sun_color, sm)
	sun.shadow_blur = lerpf(1.2, 4.0, sm)
	# Under a closed overcast there are no sun shadows: fade them out, then skip
	# the whole shadow pass (the storm's biggest saving; no recompile).
	var so := (1.0 - smoothstep(0.55, 0.9, gl)) * lerpf(1.0, 0.55, sm)
	sun.shadow_opacity = so
	var want_shadow := _shadow_base and (so > 0.04 or not _shadow_toggle)
	if sun.shadow_enabled != want_shadow and (want_shadow == false or so > 0.07):
		sun.shadow_enabled = want_shadow

	# Falling rain / snow: same emitters all race, only how many drops are alive.
	w.set_precipitation(w.rain, w.snowfall, w.wind)

	# Grip: water on the racing line, then snow on top of that.
	var road := lerpf(1.0, 0.8, w.wetness_line)
	road = lerpf(road, 0.62, w.snow_cover)
	var off := lerpf(1.0, 0.75, w.wetness)
	off = lerpf(off, 0.5, w.snow_cover)
	Car.weather_road_grip = road
	Car.weather_off_grip = off
	_announce(w)
	# Trees and bushes follow the wx_* globals in their own shaders (trees agent).
	_worst_dt = maxf(_worst_dt, dt)
	if _log and w.clock - _log_t >= 10.0:
		_log_t = w.clock
		print("weather t=%.0f gloom %.2f rain %.2f snow %.2f wind %.2f | wet %.2f line %.2f cover %.2f | grip %.2f/%.2f lamps %s ssr %s shadows %s | worst frame %.1f ms" % [
			w.clock, g, w.rain, w.snowfall, w.wind, w.wetness, w.wetness_line, w.snow_cover, road, off, Car.lamps_on, env.ssr_enabled, sun.shadow_enabled, _worst_dt * 1000.0])
		_worst_dt = 0.0
	# Lamps on when it gets gloomy or wet (with a little hysteresis).
	if Car.lamps_on:
		Car.lamps_on = w.night or gl > 0.5 or w.rain > 0.15 or w.snowfall > 0.15
	else:
		Car.lamps_on = w.night or gl > 0.6 or w.rain > 0.25 or w.snowfall > 0.25


## Announce the condition when it crosses a threshold (with hysteresis via
## distinct thresholds per phase so it never flickers between two).
func _announce(w: Weather) -> void:
	var p := _phase
	if w.snowfall > 0.12:
		p = "snow_heavy" if w.snowfall > 0.8 else ("snow" if p != "snow_heavy" else p)
	elif w.rain > 0.08:
		if w.rain > 0.85 and w.clouds > 0.9:
			p = "storm"
		elif w.rain > 0.3:
			if p == "storm" and w.rain < 0.6:
				p = "easing"
			elif p != "storm" and p != "easing":
				p = "rain"
		elif p == "" or p == "dry" or p == "drying" or p == "clouds":
			p = "drizzle"
	elif w.rain < 0.02 and w.snowfall < 0.02:
		if w.wetness > 0.3 and (p == "rain" or p == "storm" or p == "drizzle" or p == "easing"):
			p = "drying"
		elif w.wetness < 0.08 and p == "drying":
			p = "dry"
		elif w.clouds > 0.6 and (p == "" or p == "dry"):
			p = "clouds"
	if p == _phase:
		return
	var first := _phase == ""
	_phase = p
	if first and w.clock < 1.0:
		return # the starting weather is what everyone sees on the grid
	var msg := {
		drizzle = ["LIGHT RAIN", "TRACK GETTING DAMP"], rain = ["RAIN", "TRACK WET"],
		storm = ["THUNDERSTORM", "STANDING WATER"], easing = ["RAIN EASING", "TRACK STILL WET"], drying = ["RAIN STOPPED", "TRACK DRYING"],
		dry = ["TRACK DRY", ""], clouds = ["CLOUDS BUILDING", "RAIN EXPECTED"],
		snow = ["SNOW", "GRIP FALLING"], snow_heavy = ["HEAVY SNOW", "VERY LOW GRIP"],
	}
	if msg.has(p):
		news.emit(msg[p][0], msg[p][1])
		if _log:
			print("weather news: %s" % msg[p][0])


## Storm strength for lightning, and whether a strike falls in (t0, t1].
func strike_between(t0: float, t1: float) -> bool:
	var hit := false
	while _strike_i < _strikes.size() and _strikes[_strike_i] <= t1:
		if _strikes[_strike_i] > t0:
			hit = true
		_strike_i += 1
	return hit and weather.rain > 0.7 and weather.clouds > 0.85


func describe() -> String:
	return "%s (seed %d)" % [SCENARIO_NAMES.get(timeline.get("name", ""), "?"), int(timeline.get("seed", 0))]
