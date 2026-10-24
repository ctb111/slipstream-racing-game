extends Node3D
## A race on one circuit: grid, start lights, laps, positions, results.
## Reads its setup from the Game autoload (filled in by the menu / lobby).
##
## Debug options (after `--`): --track=<id> --laps=N --bots=N --allbots
## --loadprof (print load timings) --hold_loading[=0..1] (loading screen stays up)
## (player car driven by AI too), --car=<id>, --screenshot=<png> --shotcam=x,y,z --spawn=<m>

enum State { COUNTDOWN, RACING, FINISHED }
const LIGHT_INTERVAL := 0.9
const RESULTS_GRACE := 30.0 ## after the player finishes, others get this long

signal lights_changed(count: int) ## 0..5 red lights lit; -1 = lights out, go!
signal lap_completed(entry: Entry, lap_time: float)
signal race_finished

class Entry:
	var name := ""
	var car: Car
	var ai: AIDriver
	var peer := 1
	var bot := false
	var local := true ## simulated on this machine
	var index := -1
	var lap := 0 ## lap currently being driven (0 = on the grid, before the line)
	var armed := false ## passed the far side of the lap since the last crossing
	var lap_start := 0.0
	var last_lap := 0.0
	var best_lap := INF
	var progress := -INF ## metres covered since the start line, for ranking
	var position := 0
	var finished := false
	var finish_time := 0.0

var circuit: Circuit
var mode_ctl: RaceMode ## championship round / time trial controller, or null
var entries: Array[Entry] = []
var player: Entry
var state := State.COUNTDOWN
var laps := 3
var race_time := 0.0 ## seconds since lights out
var lights := 0

var _countdown := 0.0
var _hold := 0.0
var _player_done_at := -1.0
var _camera: ChaseCamera
var _args := {}
var _screenshot_t := 0.0
var _telemetry_t := 0.0
var _loaded := false ## false while the loading screen is up (circuit and cars building)
var _loading: LoadingScreen


func _ready() -> void:
	InputSetup.ensure_actions()
	_parse_args()
	if _args.has("car") and CarCatalog.has(str(_args.car)): # debug: --car=<CarCatalog id> for the player
		Game.car_id = str(_args.car)
	if _args.has("shadow_probe"): # debug: a box over a plain plane near the start
		_shadow_probe_pending = true
	if _args.has("quality"): # perf tests: 0 Low .. 3 Ultra
		Game.quality = clampi(int(_args.quality), 0, 3)
	Game.apply_viewport_quality(get_viewport())
	if not _args.has("nodynres"):
		add_child(DynamicRes.new()) # only acts on Auto render resolution, Low / Medium
	var track_id: String = _args.get("track", Game.track_id)
	if _args.has("weather"):
		Game.weather_override = int(_args.weather)
	if _args.has("difficulty"): # debug: 0 Easy .. 2 Hard
		Game.difficulty = clampi(int(_args.difficulty), 0, 2)
	# Changeable weather: offline, roll this race's scenario; online it came from the host.
	if Weather.cond_changeable(Game.weather_override) and not _online():
		Game.weather_timeline = WeatherCycle.roll()
	laps = int(_args.get("laps", Game.laps))
	# Game mode (championship round / time trial): may override track, laps, grid
	# and some Game settings, the latter only while the race sets itself up.
	var mo := _make_mode()
	track_id = mo.get("track", track_id)
	if not _args.has("laps"):
		laps = int(mo.get("laps", laps))
	var saved := {}
	var mo_game: Dictionary = mo.get("game", {})
	for k in mo_game:
		saved[k] = Game.get(k)
		Game.set(k, mo_game[k])
	var tdef := TrackDefs.get_track(track_id)
	var cond: int = Game.weather_override if Game.weather_override >= 0 else int(tdef.get("weather", 0))
	_loading = LoadingScreen.new(tdef, cond, laps, _loading_title())
	add_child(_loading)
	var t_load := Time.get_ticks_msec()
	AssetPreload.start(tdef, _grid_models())
	await get_tree().process_frame # let the loading screen draw before the heavy work
	circuit = Circuit.new()
	circuit.name = "Circuit"
	circuit.async_build = true
	circuit.build_progress.connect(func(f: float, label: String): _loading.set_progress(0.02 + 0.86 * f, label))
	add_child(circuit)
	await circuit.build(tdef)
	var t_circuit := Time.get_ticks_msec()
	_loading.set_progress(0.9, "Cars")
	await get_tree().process_frame

	if mo.has("grid"):
		Game.grid = mo.grid
	elif Game.grid.is_empty() or Game.mode == Game.Mode.SINGLE:
		Game.grid = _single_player_grid(int(_args.get("bots", Game.bots)))
	if _args.has("mixdiff"): # debug: reference car (AI, skill 1.0) on pole, all cars the same model
		Game.grid.push_front(Game.grid.pop_back())
		AIDriver.debug_stats = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var spawn_ms := []
	for slot in Game.grid.size():
		var ts := Time.get_ticks_usec()
		_spawn(slot, Game.grid[slot], rng)
		spawn_ms.append(roundi((Time.get_ticks_usec() - ts) / 1000.0))
		if slot % 2 == 1:
			_loading.set_progress(0.9 + 0.06 * slot / maxf(Game.grid.size(), 1.0), "Cars")
			await get_tree().process_frame
	for k in saved:
		Game.set(k, saved[k])
	if mode_ctl:
		add_child(mode_ctl)
		mode_ctl.attach(self)

	_camera = ChaseCamera.new()
	_camera.target = player.car
	if player.car.lights:
		player.car.lights.add_road_fill() # night: the driver's own pool of light on the road
	if player.car.lights and Game.quality >= 2: # shadow map redrawn every frame: High+
		player.car.lights.enable_shadows() # only the driver's own beam throws shadows
	if _args.has("shotcam"):
		var v: PackedFloat64Array = _args.shotcam.split_floats(",")
		_camera.debug_offset = Vector3(v[0], v[1], v[2])
		_camera.fov = 40.0
	if _args.has("worldcam"):
		var w: PackedFloat64Array = _args.worldcam.split_floats(",")
		_camera.debug_world = [Vector3(w[0], w[1], w[2]), Vector3(w[3], w[4], w[5])]
		_camera.fov = 50.0
	if _args.has("cam"): # media capture: --cam=chase|cockpit|far|bumper|bonnet|roof|tv
		var cm: int = ChaseCamera.MODE_NAMES.find(str(_args.cam))
		if cm >= 0:
			_camera.mode = cm as ChaseCamera.Mode
	add_child(_camera)
	_camera.make_current()

	var all_cars: Array = entries.map(func(x: Entry) -> Car: return x.car)
	for e in entries:
		if e.ai:
			e.ai.others = all_cars
	var hud := Hud.new()
	hud.car = player.car
	add_child(hud)
	var race_hud := RaceHud.new()
	race_hud.race = self
	add_child(race_hud)
	if _args.has("nohud"): # media capture: clean frames
		hud.visible = false
		race_hud.visible = false
	if state == State.COUNTDOWN:
		_set_locked(true)
	# A few frames with everything in view behind the loading screen, so shader
	# pipelines compile now rather than as a hitch on the grid.
	var t_cars := Time.get_ticks_msec()
	_loading.set_progress(0.97, "Warming up")
	for i in 3:
		await get_tree().process_frame
	if _args.has("hold_loading"): # debug: keep the loading screen up (screenshots)
		_loading.hold(float(_args.hold_loading) if str(_args.hold_loading).is_valid_float() else 0.6, "Scenery")
		return
	_loaded = true
	_loading.finish()
	AssetPreload.finish()
	if _args.has("loadprof") or _args.has("telemetry") or _args.has("screenshot"):
		print("race ready after %d ms (load %d ms)" % [Time.get_ticks_msec(), Time.get_ticks_msec() - t_load])
	if _args.has("loadprof"):
		print("  circuit %d ms, cars+hud %d ms, warm-up %d ms" % [t_circuit - t_load, t_cars - t_circuit, Time.get_ticks_msec() - t_cars])
		print("  circuit: ", circuit.load_times)
		print("  car spawns (ms): ", spawn_ms)
	multiplayer.peer_disconnected.connect(_on_peer_left)
	lights_changed.connect(_on_gantry_lights)
	if _args.has("perf"):
		_apply_perf_flags(str(_args.perf).split(","))
	if _args.has("pop-audit"):
		add_child(load("res://tools/pop_audit.gd").new())
	if _args.has("perf-ab"):
		add_child(load("res://tools/perf_ab.gd").new())
	if _args.has("allbots"):
		race_finished.connect(func():
			for e in standings():
				print("%d. %-14s %s  best %s  tier %d skill %.3f crashes %d stuck %d off %.1fs latg %.2f launches %d" % [e.position, e.name, RaceHud.fmt_time(e.finish_time) if e.finished else "running", RaceHud.fmt_time(e.best_lap),
					e.ai.tier if e.ai else -1, e.ai.skill if e.ai else 0.0, e.ai.crashes if e.ai else 0, e.ai.stuck_count if e.ai else 0, e.ai.off_time if e.ai else 0.0, e.ai.peak_lat_g if e.ai else 0.0, e.ai.launches if e.ai else 0])
			get_tree().quit())


## Eyebrow for the loading screen.
func _loading_title() -> String:
	if _online():
		return "ONLINE RACE"
	if mode_ctl is Championship:
		return "CHAMPIONSHIP  ·  ROUND %d" % (Championship.round_index() + 1)
	if mode_ctl is TimeTrial:
		return "TIME TRIAL"
	return "QUICK RACE"


## Car models the grid will use (so they load in the background during the build).
func _grid_models() -> Array:
	var out := [Game.car_id]
	var ids: Array = CarCatalog.available_ids()
	var n: int = Game.grid.size() if not Game.grid.is_empty() else int(_args.get("bots", Game.bots)) + 1
	for slot in n:
		if not ids.is_empty():
			var m: String = ids[(slot + 1) % ids.size()]
			if not out.has(m):
				out.append(m)
	return out


## Single player only: the controller for Game.session (or `--mode=championship|timetrial`).
func _make_mode() -> Dictionary:
	if Game.mode != Game.Mode.SINGLE:
		return {}
	match str(_args.get("mode", "")):
		"championship": Game.session = Game.Session.CHAMPIONSHIP
		"timetrial": Game.session = Game.Session.TIME_TRIAL
		"race": Game.session = Game.Session.RACE
	if Game.session == Game.Session.CHAMPIONSHIP:
		if _args.has("champ_new"):
			Championship.start(str(_args.champ_new), Game.difficulty, Game.laps, int(_args.get("bots", 7)))
		if Championship.active() and not Championship.complete():
			mode_ctl = Championship.new()
	elif Game.session == Game.Session.TIME_TRIAL:
		mode_ctl = TimeTrial.new()
	if mode_ctl == null:
		return {}
	mode_ctl.name = "Mode"
	return mode_ctl.setup_overrides()


func _single_player_grid(bot_count: int) -> Array:
	var grid := []
	var names := Game.BOT_NAMES.duplicate()
	names.shuffle()
	for i in bot_count:
		grid.append({peer = 1, name = names[i % names.size()], bot = true})
	grid.append({peer = 1, name = Game.player_name, bot = false}) # player starts at the back
	return grid


func _spawn(slot: int, info: Dictionary, rng: RandomNumberGenerator) -> void:
	var e := Entry.new()
	e.name = info.name
	e.bot = info.bot
	e.peer = info.peer
	e.car = Car.new()
	# Drivers race what they picked; bots get a varied field.
	var ids: Array = CarCatalog.available_ids()
	var model: String = info.get("car", "")
	if not info.bot and info.peer == multiplayer.get_unique_id():
		model = Game.car_id
	elif _args.has("mixdiff"):
		model = Game.car_id
	elif model == "" or (info.bot and not ids.has(model)): # championship bots keep their car
		model = ids[(slot + 1) % ids.size()] if not ids.is_empty() else CarCatalog.DEFAULT
	e.car.model_id = model
	e.car.name = "Car%d" % slot
	# Local driver: their chosen paint. Everyone else: slot colours, skipping that paint.
	# Drivers get their chosen paint (sent through the lobby online); bots use
	# slot colours, skipping the local driver's colour.
	var chosen: int = info.get("paint", -1)
	if not info.bot and info.peer == multiplayer.get_unique_id():
		chosen = Game.paint_index
	e.car.paint_color = CarPalette.pick(chosen) if chosen >= 0 else CarPalette.pick(slot + int(slot % CarPalette.COLORS.size() >= Game.paint_index))
	var xf := circuit.grid_transform(slot)
	if _args.has("spawn") and not e.bot:
		xf = circuit.line.transform_at(float(_args.spawn))
	e.car.transform = xf
	add_child(e.car)
	var is_me: bool = not e.bot and e.peer == multiplayer.get_unique_id()
	# Each machine simulates its own driver; the host (or single player) also runs the bots.
	e.local = is_me or (e.bot and _is_authority())
	if not e.local:
		e.car.set_remote()
	elif e.bot or (is_me and _args.has("allbots")):
		e.ai = AIDriver.new()
		e.ai.line = circuit.line
		if _args.has("mixdiff") and e.bot: # debug: Hard at the front, then Medium, then Easy
			Game.difficulty = 2 if slot <= 2 else (1 if slot <= 4 else 0)
			e.ai.tier = Game.difficulty
		e.ai.skill = Game.bot_skill(rng) if e.bot else (float(_args.get("refskill", 1.3)) if _args.has("mixdiff") else 0.95)
		if _args.has("skill"): # debug: every AI car at this skill
			e.ai.skill = float(_args.skill)
		e.ai.stuck.connect(_on_stuck)
		e.car.add_child(e.ai)
	else:
		e.car.player_controlled = true
		e.car.set_assists(Game.assists)
	if is_me:
		player = e
	entries.append(e)


func _physics_process(dt: float) -> void:
	if not _loaded:
		return
	match state:
		State.COUNTDOWN:
			if _is_authority(): # clients get the lights from the host
				_run_countdown(dt)
		State.RACING, State.FINISHED:
			race_time += dt
			if _shadow_probe_pending and player and player.car:
				_place_shadow_probe()
			if _args.has("steer_log") and race_time > 8.0 and race_time < 10.0:
				for e in entries.slice(0, 3): # debug: front-wheel angle per tick
					print("steerlog %s t=%.3f input=%.3f steer=%.3f angle=%.2fdeg slip=%.2fdeg v=%.0f" % [e.name, race_time,
						e.car.steer_input, e.car.steer, rad_to_deg(e.car.steer_angle()), rad_to_deg(e.car.body_slip), e.car.speed * 3.6])
			if _args.has("offtrack_test"):
				_offtrack_test()
	# Changeable weather follows the race clock (clients get it from the host).
	# Debug: --weather_speed=10 fast-forwards, --weather_at=<s> starts later on.
	var wx := circuit.weather
	if wx.cycle:
		var t := race_time if state != State.COUNTDOWN else 0.0
		wx.clock = float(_args.get("weather_at", 0.0)) + t * float(_args.get("weather_speed", 1.0))
	_update_progress()
	_network_tick(dt)
	_debug_tick(dt)


func _run_countdown(dt: float) -> void:
	_countdown += dt
	var lit := mini(int(_countdown / LIGHT_INTERVAL), 5)
	if lit != lights and lights >= 0:
		lights = lit
		lights_changed.emit(lights)
		if _online():
			_net_lights.rpc(lights)
		if lights == 5:
			_hold = randf_range(0.4, 1.3)
	if lights == 5:
		_hold -= dt
		if _hold <= 0.0:
			_go()
			if _online():
				_net_lights.rpc(-1)


func _debug_tick(dt: float) -> void:
	if _args.has("telemetry"):
		_telemetry_t += dt
		if _telemetry_t > 2.0:
			_telemetry_t = 0.0
			var parts := []
			for e in entries:
				parts.append("%s:i%d L%d %.0fkm/h p%d" % [e.name.substr(0, 6), e.index, e.lap, e.car.speed * 3.6, e.position])
			print("t=%.0f %s | %s" % [race_time, State.keys()[state], " ".join(parts)])
	if Input.is_action_just_pressed("reset_car") and state != State.COUNTDOWN and not player.finished:
		_reset_to_track(player.car)
	_maybe_screenshot(dt)


## Mirror the countdown on the start gantry built by TrackProps.
func _on_gantry_lights(count: int) -> void:
	var lamps: Array = circuit.get_meta("start_lights", [])
	for k in lamps.size():
		lamps[k].emission_energy_multiplier = 6.0 if count > k else 0.0


func _online() -> bool:
	return Game.mode != Game.Mode.SINGLE and multiplayer.has_multiplayer_peer()


## Single player, or the host of an online race: decides lights, laps, results.
func _is_authority() -> bool:
	return not _online() or multiplayer.is_server()


func _go() -> void:
	state = State.RACING
	lights = -1
	lights_changed.emit(-1)
	race_time = 0.0
	for e in entries:
		e.lap_start = 0.0
	_set_locked(false)


func _set_locked(on: bool) -> void:
	for e in entries:
		if e.car == null:
			continue
		e.car.locked = on
		if not on:
			e.car.brake = 0.0
			e.car.handbrake = false
		if e.ai:
			e.ai.enabled = not on


func _update_progress() -> void:
	var line := circuit.line
	var length := line.length
	for e in entries:
		if e.car == null:
			continue
		if e.ai:
			e.index = e.ai.index # the driver already tracks it
		else:
			e.index = line.closest_index(e.car.global_position, e.index)
		var rel := fposmod(line.offset_of(e.index) - circuit.start_offset, length)
		if rel > length * 0.4 and rel < length * 0.6:
			e.armed = true
		var crossed := rel < length * 0.15 and (e.armed or e.lap == 0) and e.progress > -INF \
				and fposmod(e.progress, length) > length * 0.85
		if crossed and state != State.COUNTDOWN and not e.finished:
			_on_line_crossed(e)
		if e.finished:
			continue
		e.progress = (e.lap - 1) * length + rel if e.lap > 0 else rel - length
	_rank()
	_slipstream()


## Directly behind another car within ~25 m: less drag, like a real tow.
## Also: a soft push between our cars and other players' puppet cars.
func _slipstream() -> void:
	for e in entries:
		if e.car == null:
			continue
		if e.local and _online():
			_soft_contact(e)
		var best := 1.0
		var inv := e.car.global_transform.affine_inverse()
		for o in entries:
			if o == e:
				continue
			var local := inv * o.car.global_position
			var ahead := -local.z
			if ahead > 3.0 and ahead < 25.0 and absf(local.x) < 1.6:
				best = minf(best, lerpf(0.6, 1.0, ahead / 25.0))
		e.car.draft = best


func _soft_contact(e: Entry) -> void:
	var me := e.car
	for o in entries:
		if o == e or o.local or o.car == null:
			continue
		var d := me.global_position - o.car.global_position
		if absf(d.y) > 1.5:
			continue
		d.y = 0.0
		var dist := d.length()
		if dist < 3.2 and dist > 0.01:
			var push := d / dist * (3.2 - dist) * me.mass * 9.0
			var rel := me.linear_velocity - o.car.velocity()
			rel.y = 0.0
			me.apply_central_force(push - rel * me.mass * 1.5 * (1.0 - dist / 3.2))


func _on_line_crossed(e: Entry) -> void:
	e.armed = false
	if not _is_authority():
		return # the host keeps the official lap count and times
	if e.lap >= 1:
		var lap_time := race_time - e.lap_start
		e.last_lap = lap_time
		e.best_lap = minf(e.best_lap, lap_time)
		lap_completed.emit(e, lap_time)
		if _args.has("allbots") or DisplayServer.get_name() == "headless":
			print("%-14s lap %d  %s" % [e.name, e.lap, RaceHud.fmt_time(lap_time)])
	e.lap_start = race_time
	e.lap += 1
	if e.lap > laps and _is_authority():
		e.finished = true
		e.finish_time = race_time
		e.progress = laps * circuit.line.length + 1000.0 - e.finish_time # keep finish order
		if e.ai:
			e.ai.skill *= 0.7 # cool-down lap
		if e == player:
			_player_done_at = race_time
			player.car.set_assists(true)
			var ai := AIDriver.new() # autopilot after the flag
			ai.line = circuit.line
			ai.skill = 0.6
			ai.enabled = true
			player.car.add_child(ai)
			player.ai = ai
	if not _is_authority():
		return
	if entries.all(func(x: Entry) -> bool: return x.finished) or \
			(_player_done_at >= 0.0 and race_time - _player_done_at > RESULTS_GRACE):
		if state != State.FINISHED:
			state = State.FINISHED
			race_finished.emit()
	elif e == player and e.finished and not _online():
		state = State.FINISHED
		race_finished.emit()
	if _online() and state == State.FINISHED:
		_net_finished.rpc()


func _rank() -> void:
	var order := entries.duplicate()
	order.sort_custom(func(a: Entry, b: Entry) -> bool: return a.progress > b.progress)
	for i in order.size():
		order[i].position = i + 1


func standings() -> Array[Entry]:
	var order: Array[Entry] = entries.duplicate()
	order.sort_custom(func(a: Entry, b: Entry) -> bool: return a.position < b.position)
	return order


func _on_stuck(car: Car) -> void:
	if _args.has("allbots"):
		print("stuck reset: %s at %s" % [car.name, car.global_position.snapped(Vector3.ONE)])
	if state == State.RACING or state == State.FINISHED:
		_reset_to_track(car)


func _reset_to_track(car: Car) -> void:
	var idx := circuit.line.closest_index(car.global_position)
	car.reset_to(circuit.line.transform_at(circuit.line.offset_of(idx)))


# ---------------------------------------------------------------- network

var _send_t := 0.0
var _sync_t := 0.0


func _network_tick(dt: float) -> void:
	if not _online():
		return
	# Our own cars' states, 30 times a second.
	_send_t += dt
	if _send_t >= 1.0 / 30.0:
		_send_t = 0.0
		var states := {}
		for i in entries.size():
			if entries[i].local and entries[i].car:
				states[i] = entries[i].car.net_pack()
		if not states.is_empty():
			_net_cars.rpc(states)
	# Host: race standings for everyone, 5 times a second.
	if multiplayer.is_server():
		_sync_t += dt
		if _sync_t >= 0.2:
			_sync_t = 0.0
			var data := []
			for e in entries:
				data.append([e.lap, e.last_lap, e.best_lap, e.finished, e.finish_time, e.lap_start])
			_net_race.rpc(race_time, int(state), data)


@rpc("any_peer", "unreliable_ordered")
func _net_cars(states: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	for slot in states:
		if slot < 0 or slot >= entries.size():
			continue
		var e := entries[slot]
		# Only the machine that owns a car may move it (the host owns bots).
		if e.local or not (e.peer == sender or (e.bot and sender == 1)):
			continue
		e.car.net_push(states[slot])


@rpc("authority", "unreliable_ordered")
func _net_race(t: float, host_state: int, data: Array) -> void:
	race_time = t
	for i in mini(data.size(), entries.size()):
		var e := entries[i]
		var d: Array = data[i]
		if e == player and d[0] > e.lap and e.lap >= 1:
			e.lap = d[0]
			e.best_lap = d[2]
			lap_completed.emit(e, d[1])
		e.lap = maxi(e.lap, d[0])
		e.last_lap = d[1]
		e.best_lap = d[2]
		e.finished = d[3]
		e.finish_time = d[4]
		e.lap_start = d[5]
		if e.finished:
			e.progress = laps * circuit.line.length + 1000.0 - e.finish_time
	if host_state == State.FINISHED and state != State.FINISHED:
		state = State.FINISHED
		race_finished.emit()


@rpc("authority", "reliable")
func _net_lights(count: int) -> void:
	if count == lights:
		return
	if count < 0:
		_go()
	else:
		lights = count
		lights_changed.emit(count)


@rpc("authority", "reliable")
func _net_finished() -> void:
	if state != State.FINISHED:
		state = State.FINISHED
		race_finished.emit()


func _on_peer_left(id: int) -> void:
	for e in entries:
		if e.peer == id and not e.bot and e.car:
			e.car.queue_free()
			e.car = null
			e.name += " (left)"
	entries = entries.filter(func(x: Entry) -> bool: return x.car != null or x.finished)


func quit_to_menu() -> void:
	if multiplayer.has_multiplayer_peer() and Game.mode != Game.Mode.SINGLE:
		Net.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# ---------------------------------------------------------------- debug

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.trim_prefix("--").split("=", true, 1)
			_args[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			_args[arg.trim_prefix("--")] = true


## Debug: switch features off to find what costs frame time (--perf=nomsaa,nossao,...).
func _apply_perf_flags(flags: PackedStringArray) -> void:
	var env: Environment = circuit.weather.env
	for f in flags:
		if f.begins_with("envset:") or f.begins_with("sunset:"): # envset:prop=value (debug tuning)
			var kv := f.substr(7).split("=")
			var target: Object = env if f.begins_with("envset:") else circuit.weather.sun
			target.set(kv[0], float(kv[1]))
			continue
		if f.begins_with("hide:"): # hide:<node or parent name part>, e.g. hide:Terrain
			var part2 := f.substr(5)
			for g in circuit.find_children("*", "GeometryInstance3D", true, false):
				if part2 in str(g.name) or part2 in str(g.get_parent().name):
					(g as GeometryInstance3D).visible = false
			continue
		if f.begins_with("noproc:"): # noproc:<script name part> stops _process on matching nodes
			var part := f.substr(7)
			for n in get_tree().root.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				if sc and part in sc.resource_path:
					n.set_process(false)
					n.set_physics_process(false)
			continue
		match f:
			"nomsaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"fsr2":
				get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
				get_viewport().scaling_3d_scale = 1.0
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"taa":
				get_viewport().use_taa = true
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"msaa2": get_viewport().msaa_3d = Viewport.MSAA_2X
			"nossao": env.ssao_enabled = false
			"nossr": env.ssr_enabled = false
			"noglow": env.glow_enabled = false
			"noshadow": circuit.weather.sun.shadow_enabled = false
			"nosun": circuit.weather.sun.light_energy = 0.0
			"nofog": env.fog_enabled = false
			"nossao2": env.ssao_enabled = false
			"noenv":
				for we in get_tree().root.find_children("*", "WorldEnvironment", true, false):
					(we as WorldEnvironment).environment = null
			"nopost":
				for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
					if n is CameraPost:
						n.visible = false
			"noambient": env.ambient_light_energy = 0.0
			"nobeamshadow": # night: the driver's headlight shadows
				if player.car.lights:
					player.car.lights.beam.shadow_enabled = false
			"nolamps": # night: trackside lamps (NightLights)
				var nl := circuit.get_node_or_null("NightLights")
				if nl:
					nl.queue_free()
			"nocarlights":
				for e in entries:
					if e.car.lights:
						e.car.lights.visible = false
			"noprecip":
				for c in circuit.weather.get_children():
					if c is GPUParticles3D:
						c.visible = false
			"tick60": Engine.physics_ticks_per_second = 60
			"half": get_viewport().scaling_3d_scale = 0.5
			"bil75": get_viewport().scaling_3d_scale = 0.75
			"fsr75":
				get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				get_viewport().scaling_3d_scale = 0.75
			"sky256": env.sky.radiance_size = Sky.RADIANCE_SIZE_256
			"skyq": env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
			"nofade":
				for g in circuit.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			"nofar":
				for g in circuit.find_children("*", "GeometryInstance3D", true, false):
					if (g as GeometryInstance3D).visibility_range_begin > 0.0:
						g.visible = false
			"fsr80":
				get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
				get_viewport().scaling_3d_scale = 0.8
			"nocars":
				for e in entries:
					if e != player and e.car:
						e.car.visible = false
			"nocarshadow":
				for e in entries:
					if e.car:
						for mi in e.car.find_children("*", "MeshInstance3D", true, false):
							mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"nomm":
				for c in circuit.get_children():
					if c is MultiMeshInstance3D:
						c.visible = false


var _ot_stage := 0
var _ot_start := Vector3.ZERO
var _ot_min_lat := INF
var _ot_reported := false


## Debug --offtrack_test: at 4 s the (AI-driven) player is dropped 3.5 m off the
## road edge on the grass, angled back in; at 12 s it must be back on tarmac.
var _shadow_probe_pending := false


func _place_shadow_probe() -> void:
	_shadow_probe_pending = false
	var car := player.car
	var f := -car.global_basis.z
	f.y = 0.0
	f = f.normalized()
	var base := car.global_position + f * 12.0
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	plane.mesh = pm
	plane.position = base + Vector3(-4.0, -0.25, 0)
	get_tree().current_scene.add_child(plane)
	for k in 2:
		var box := MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.position = base + Vector3(-4.0 + k * 6.0, 1.5, 0)
		get_tree().current_scene.add_child(box)


func _offtrack_test() -> void:
	var car := player.car
	var curve := circuit.curve
	var half := TrackDefs.ROAD_WIDTH * 0.5
	if _ot_stage == 0 and race_time > 4.0 and str(_args.offtrack_test) == "gravel":
		# Parked in the deepest gravel trap (outside of the tightest corner), nose
		# pointing at the road: the hard case, pulling away from a standstill.
		_ot_stage = 1
		var cs: PackedVector3Array = circuit.line.centers
		var arr: Array[Vector3] = []
		for c in cs:
			arr.append(c)
		var corner := TrackBuilder._corner_factors(arr)
		var bi := 0
		for i in corner.size():
			if absf(corner[i]) > absf(corner[bi]):
				bi = i
		var side := signf(corner[bi])
		var c0: Vector3 = cs[bi]
		var t := (cs[(bi + 1) % cs.size()] - cs[(bi - 1 + cs.size()) % cs.size()]).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var depth := TrackBuilder.GRAVEL_MAX * absf(corner[bi])
		var at := c0 + r * side * (half + TrackBuilder.CURB_WIDTH + depth * 0.5) + Vector3.UP * 0.6
		var heading := (t * 0.5 - r * side).normalized()
		car.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at)
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		print("offtrack_test: parked in gravel %.1f m deep at corner %.2f" % [depth, corner[bi]])
	elif _ot_stage == 0 and race_time > 4.0 and str(_args.offtrack_test).begins_with("kerb"):
		# A human-style approach: on the grass inside the tightest corner, 3 m
		# off the kerb, driving straight at it at 15 km/h with no AI steering.
		_ot_stage = 1
		if player.ai:
			player.ai.set_physics_process(false)
			player.ai.process_mode = Node.PROCESS_MODE_DISABLED
		var cs: PackedVector3Array = circuit.line.centers
		var arr: Array[Vector3] = []
		for c in cs:
			arr.append(c)
		var corner := TrackBuilder._corner_factors(arr)
		var bi := 0
		for i in corner.size():
			if absf(corner[i]) > absf(corner[bi]):
				bi = i
		var side := -signf(corner[bi]) # the inside
		if str(_args.offtrack_test) == "kerb_out":
			side = -side
		var c0: Vector3 = cs[bi]
		var t := (cs[(bi + 1) % cs.size()] - cs[(bi - 1 + cs.size()) % cs.size()]).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var dist := half + TrackBuilder.CURB_WIDTH + 3.0
		if side * signf(corner[bi]) > 0.0:
			dist += TrackBuilder.GRAVEL_MAX * absf(corner[bi]) * 0.5
		var at := c0 + r * side * dist
		at.y = (circuit.terrain.height_at(at.x, at.z) if circuit.terrain else c0.y) + 0.6
		var heading := (-r * side).normalized()
		car.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at)
		car.linear_velocity = heading * 4.2
		car.angular_velocity = Vector3.ZERO
		_ot_start = at
	elif _ot_stage == 1 and str(_args.offtrack_test).begins_with("kerb"):
		car.throttle = 0.5
		car.brake = 0.0
		car.steer_input = 0.0
		var qq := curve.get_closest_point(car.global_position)
		var lat := Vector2(car.global_position.x - qq.x, car.global_position.z - qq.z).length()
		_ot_min_lat = minf(_ot_min_lat, lat)
		if car.speed < 0.5 and race_time > 5.0 and not _ot_reported:
			_ot_reported = true
			var st := car.get_world_3d().direct_space_state
			var q2 := PhysicsShapeQueryParameters3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(2.2, 1.2, 5.0)
			q2.shape = box
			q2.transform = car.global_transform
			q2.exclude = [car.get_rid()]
			var hits := st.intersect_shape(q2, 8)
			var names := []
			for h in hits:
				names.append(str(h.collider.name) + "<" + str(h.collider.get_parent().name))
			print("offtrack_test: STOPPED at lateral %.1f, height above road %.2f, touching: %s" % [lat, car.global_position.y - qq.y, names])
		if race_time > 10.0:
			_ot_stage = 2
			var q := curve.get_closest_point(car.global_position)
			var lateral := Vector2(car.global_position.x - q.x, car.global_position.z - q.z).length()
			print("offtrack_test %s: moved %.1f m, lateral now %.1f m, speed %.0f km/h -> %s" % [_args.offtrack_test,
				car.global_position.distance_to(_ot_start), lateral, car.speed * 3.6, "REACHED ROAD (min lateral %.1f)" % _ot_min_lat if _ot_min_lat < half - 0.5 else "BLOCKED (min lateral %.1f)" % _ot_min_lat])
		return
	elif _ot_stage == 0 and race_time > 4.0:
		_ot_stage = 1
		var off := curve.get_closest_offset(car.global_position)
		var p := curve.sample_baked(off)
		var t := (curve.sample_baked(off + 2.0) - p).normalized()
		var r := t.cross(Vector3.UP).normalized()
		var at := p + r * (half + 3.5) # on the grass, inside the guardrail
		at.y = circuit.terrain.height_at(at.x, at.z) + 0.6 if circuit.terrain else p.y + 0.6
		var heading := (t - r * 0.5).normalized() # pointing back towards the road
		car.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), at)
		car.linear_velocity = heading * 8.0
		car.angular_velocity = Vector3.ZERO
	elif _ot_stage == 1 and race_time > 12.0:
		_ot_stage = 2
		var q := curve.get_closest_point(car.global_position)
		var lateral := Vector2(car.global_position.x - q.x, car.global_position.z - q.z).length()
		print("offtrack_test: lateral %.1f m (road half %.1f)  speed %.0f km/h  -> %s" % [lateral, half, car.speed * 3.6,
			"BACK ON TRACK" if lateral < half + 0.5 and car.speed > 8.0 else "STUCK"])


var _perf_on := false
var _frame_times: Array[float] = []


var _split := PackedFloat64Array([0, 0, 0, 0]) ## sums over the perf window: gpu, render cpu, process, physics (ms)


func _process(delta: float) -> void:
	if _perf_on:
		_frame_times.append(delta)
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		_split[0] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_split[1] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_split[2] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		_split[3] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0


func _maybe_screenshot(dt: float) -> void:
	if not _args.has("screenshot"):
		return
	_screenshot_t += dt
	var at := float(_args.get("shot_at", 3.0))
	# Real frame times over the 6 s before the shot (collected in _process):
	# average fps, 1% low and the worst frame.
	_perf_on = _screenshot_t > at - 6.0
	if _screenshot_t > at:
		var ft := _frame_times.duplicate()
		ft.sort()
		var n := ft.size()
		if n > 0:
			var total := 0.0
			for x: float in ft:
				total += x
			var low1: float = ft[mini(n - 1, int(n * 0.99))]
			print("perf avg_fps=%.1f low1_fps=%.1f worst_ms=%.1f frames=%d" % [n / total, 1.0 / low1, ft[n - 1] * 1000.0, n])
			print("perf split gpu_ms=%.2f render_cpu_ms=%.2f process_ms=%.2f physics_ms=%.2f" % [_split[0] / n, _split[1] / n, _split[2] / n, _split[3] / n])
		print("fps=", Engine.get_frames_per_second(), " scale=", get_viewport().scaling_3d_scale, " draw_calls=",
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" primitives=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		if _args.has("sun_info"): # debug: what the sun is really doing
			for l in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
				var dl := l as DirectionalLight3D
				print("sun_info %s visible=%s shadow=%s energy=%.2f opacity=%.2f blur=%.2f maxdist=%.0f mode=%d cull=%d dir=%s" % [dl.name, dl.is_visible_in_tree(), dl.shadow_enabled, dl.light_energy, dl.shadow_opacity, dl.shadow_blur, dl.directional_shadow_max_distance, dl.directional_shadow_mode, dl.light_cull_mask, -dl.global_basis.z])
			var vrid := get_viewport().get_viewport_rid()
			print("sun_info shadow-pass draw_calls=%d objects=%d prims=%d | visible pass draw_calls=%d" % [
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				RenderingServer.viewport_get_render_info(vrid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
			var cm: Node = player.car if player else null
			if cm:
				for mi in cm.find_children("*", "MeshInstance3D", true, false):
					if mi.name == "ShadowProxy":
						print("sun_info proxy mesh=%s cast=%d visible=%s" % [(mi as MeshInstance3D).mesh, (mi as MeshInstance3D).cast_shadow, mi.is_visible_in_tree()])
		if _args.has("probe_meshes"): # debug: which visible meshes cover the road around the player
			var here: Vector3 = player.car.global_position if player and player.car else Vector3.ZERO
			for g in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				if not gi.is_visible_in_tree():
					continue
				var bb := gi.global_transform * gi.get_aabb()
				if bb.grow(1.0).has_point(here) and bb.size.length() < 2000.0:
					var mat = gi.material_override
					print("probe: %s  parent=%s  aabb=%s  mat=%s" % [gi.name, gi.get_parent().name, bb.size, (mat.shader.resource_path if mat is ShaderMaterial and mat.shader else str(mat))])
		get_viewport().get_texture().get_image().save_png(_args.screenshot)
		get_tree().quit()
