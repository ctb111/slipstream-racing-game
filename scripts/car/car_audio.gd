class_name CarAudio
extends Node3D
## Engine, turbo, tyre and wind sound for its parent Car.
##
## Every engine type (CarCatalog `engine` sub-dictionary) is synthesised once,
## lazily on a WorkerThreadPool task the first time a car of that model
## appears, into short seamless loops at a few rpm points (on and off load)
## plus its own turbo whistle, blow-off / wastegate one-shot and overrun pops.
## Each car only crossfades and re-pitches players, so eight cars cost next to
## nothing. Tyre, wind and gear sounds are shared by all engines. Reads only
## public Car fields (model_id, rpm, throttle, gear, speed, wheels) so it works
## for local, AI and network cars alike.
##
## Engine synthesis is a source-filter model: one exhaust pulse per firing
## event (timing / strength per cylinder from the engine's irregularity,
## a decaying ring at the exhaust resonance plus grit and induction noise;
## a rotary adds the buzzy step of its abrupt exhaust port), overlap-added into
## a loop that is a whole number of engine cycles long, plus the engine's
## low-order harmonic body and any mechanical whine, then muffled and
## softly saturated.

const RATE := 22050
## Legacy default rpm points (kept for callers; engines now derive their own).
const ENGINE_RPMS: Array[float] = [1100.0, 2600.0, 4300.0, 6300.0]
const CULL_DISTANCE := 160.0
## Target engine-loop length; rounded to whole engine cycles.
const LOOP_SEC := 0.55
## Engine players below this linear gain are paused so they cost no mixing.
const SILENT := 0.0005

## Synthesis / behaviour defaults. A catalog `engine` dictionary overrides any
## of these; see CarCatalog for what each engine sets.
const ENGINE_DEFAULTS := {
	type = "",
	cylinders = 6, ## cylinders, or rotors when `rotary`
	rotary = false, ## Wankel: every rotor fires once per eccentric-shaft turn
	rpm_points = [], ## loop rpms; empty = derived from idle / redline
	firing_irregularity = 0.05, ## fixed per-cylinder pulse-arrival offset, fraction of the spacing
	cyl_variation = 0.1, ## fixed per-cylinder strength spread
	pulse_jitter = 0.06, ## random per-pulse strength / timing spread
	bank_split = 1.0, ## alternate pulses ring this much higher (two banks / collectors)
	exhaust_resonance_hz = [150.0, 430.0], ## pulse ring at idle .. redline
	resonance2 = 0.5, ## second (inharmonic) ring level
	resonance2_ratio = 2.31,
	pulse_decay = 1.1, ## ring time in firing periods
	attack = 0.0004, ## pulse rise time, s (sharper = buzzier)
	saw = 0.0, ## rotary: abrupt port-opening step, decays over `saw_decay` of the spacing
	saw_decay = 0.35,
	thump = 0.6, ## low pressure bump of each firing (fraction of the spacing wide): the firing-order body
	thump_width = 0.6,
	harmonics = [[1.5, 0.18], [3.0, 0.35], [6.0, 0.1]], ## [crank order, level] tonal body
	induction_noise = 0.15, ## intake gulp level
	induction_hz = 900.0,
	induction_tone = 0.3, ## 0 = rasp (noise) .. 1 = honk (tone)
	grit = 0.5, ## combustion noise in each pulse
	grit_hz = 3500.0,
	mech_order = 0.0, ## mechanical whine (fan, cam gears) in crank orders; 0 = none
	mech_level = 0.0,
	lope = 0.0, ## idle roughness: misfire-and-catch "brap"
	brightness = [900.0, 3200.0], ## muffler low-pass at idle .. redline
	drive = 1.6, ## saturation
	overrun_level = 0.5,
	cam_rpm = 0.0, ## cam / induction change point (0 = none)
	cam_bright = 1.0, ## brightness and induction multipliers above cam_rpm
	cam_induction = 1.0,
	turbo = false,
	turbo_pitch = 2900.0,
	turbo_whoosh = 0.4,
	turbo_level = 0.22,
	spool_rpm = 2800.0, ## boost starts building here
	spool_span = 3500.0, ## rpm over which it reaches full boost
	spool_rate = 2.5, ## 1/s; lower = more lag
	blowoff = "bov", ## "bov" / "soft" / "wastegate" / ""
	backfire_rate = 0.0, ## overrun pops per second at high rpm (fades while coasting)
	pop_min = 0.55, ## pops only above this fraction of redline
	pop_hz = 110.0, ## boom pitch of a pop
	pop_crack = 0.6, ## crack level of a pop
	pop_cluster = 2, ## up to this many bangs per pop
	limiter_hz = 16.0, ## ignition-cut stutter rate at redline
	volume_db = 0.0,
}

@export var volume_db := 0.0

## An overrun pop / backfire fired (CarFx flashes a flame with it).
signal popped(level: float)

static var _cache := {} ## shared: tyres, wind, clunk
static var _banks := {} ## engine type -> finished bank
static var _jobs := {} ## engine type -> WorkerThreadPool task id (main thread only)
static var _done := {} ## engine type -> bank written by a worker, collected on the main thread
static var _lock := Mutex.new()

var _car: Car
var _model := ""
var _spec := {}
var _bank := {}
var _on: Array[AudioStreamPlayer3D] = [] ## engine under load, one per rpm point
var _off: Array[AudioStreamPlayer3D] = [] ## engine on overrun
var _squeal: AudioStreamPlayer3D
var _scrub: AudioStreamPlayer3D ## gravel crunch
var _grass: AudioStreamPlayer3D ## tyres through grass: soft swish and thump
var _wind: AudioStreamPlayer3D
var _whistle: AudioStreamPlayer3D
var _oneshot: AudioStreamPlayer3D
var _pop_players: Array[AudioStreamPlayer3D] = []
var _pop_next := 0
var _load := 0.0
var _boost := 0.0
var _last_gear := 1
var _last_throttle := 0.0
var _lift_time := 99.0 ## seconds since the throttle was last released
var _lim_phase := 0.0
var _culled := false
var _rng := RandomNumberGenerator.new()


## Build the shared sound bank (call during loading to avoid a hitch later).
## Engines for `models` are synthesised right away too (blocking); otherwise
## each engine is built on a worker the first time a car needs it.
static func warm_up(models: Array = []) -> void:
	if not _cache.has("squeal"):
		_cache.squeal = _noise_loop(1.2, 950.0, 7.0, 0.35, 830.0)
		_cache.scrub = _noise_loop(1.0, 220.0, 0.9, 0.0, 0.0, true)
		_cache.wind = _noise_loop(2.0, 380.0, 0.6, 0.0, 0.0)
		_cache.clunk = _clunk()
	if not _cache.has("grass"):
		_cache.grass = _grass_loop()
	for m in models:
		var s := engine_spec(m)
		if not _banks.has(s.type):
			_collect(s.type, true)
			if not _banks.has(s.type):
				_banks[s.type] = synth_engine(s)


## Catalog engine parameters for a model, merged over ENGINE_DEFAULTS, with
## the model's idle / redline and a resolved `type` and `rpm_points`.
static func engine_spec(model_id: String) -> Dictionary:
	var car := CarCatalog.get_car(model_id)
	var s := ENGINE_DEFAULTS.duplicate(true)
	s.merge(car.get("engine", {}), true)
	var phys: Dictionary = car.get("physics", {})
	s.idle_rpm = float(phys.get("idle_rpm", 900.0))
	s.redline_rpm = float(phys.get("redline_rpm", 7000.0))
	if s.type == "":
		s.type = model_id if CarCatalog.has(model_id) else CarCatalog.DEFAULT
	if (s.rpm_points as Array).is_empty():
		var r: float = s.redline_rpm
		s.rpm_points = [maxf(s.idle_rpm * 1.25, 1000.0), r * 0.38, r * 0.62, r * 0.9]
	return s


## Start synthesising a model's engine in the background (no-op if built or queued).
static func request_engine(model_id: String) -> void:
	var s := engine_spec(model_id)
	var type: String = s.type
	if _banks.has(type) or _jobs.has(type):
		return
	_jobs[type] = WorkerThreadPool.add_task(func() -> void:
		var b := synth_engine(s)
		_lock.lock()
		_done[type] = b
		_lock.unlock(), false, "engine synthesis " + type)


## The engine bank for a model, or {} while it is still being synthesised.
static func engine_bank(model_id: String) -> Dictionary:
	var type: String = engine_spec(model_id).type
	if not _banks.has(type):
		_collect(type, false)
	return _banks.get(type, {})


## Main thread: pick up a worker's finished bank (optionally waiting for it).
static func _collect(type: String, block: bool) -> void:
	if not _jobs.has(type):
		return
	var id: int = _jobs[type]
	if not block and not WorkerThreadPool.is_task_completed(id):
		return
	WorkerThreadPool.wait_for_task_completion(id)
	_jobs.erase(type)
	_lock.lock()
	if _done.has(type):
		_banks[type] = _done[type]
		_done.erase(type)
	_lock.unlock()


## Synthesise everything one engine needs. Pure (safe on a worker thread).
## Returns {type, rpms, on, off, fire_hz, whistle, blowoff, pops, nans, ms}.
static func synth_engine(s: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var bank := {type = s.type, rpms = [], on = [], off = [], fire_hz = [], nans = 0}
	var seed := hash(s.type)
	var k := 0
	for r in s.rpm_points:
		var on := _engine_loop(s, float(r), true, seed + k * 17)
		var off := _engine_loop(s, float(r), false, seed + k * 17 + 5)
		bank.rpms.append(on.rpm)
		bank.fire_hz.append(on.fire_hz)
		bank.on.append(on.wav)
		bank.off.append(off.wav)
		bank.nans += on.nans + off.nans
		k += 1
	if s.turbo:
		bank.whistle = _turbo_loop(s.turbo_pitch, s.turbo_whoosh, seed)
	match String(s.blowoff) if s.turbo else "":
		"bov":
			bank.blowoff = _blowoff(0.55, 3400.0, 900.0, 24.0, 0.35, 0.16, seed)
		"soft":
			bank.blowoff = _blowoff(0.35, 2300.0, 800.0, 0.0, 0.0, 0.09, seed)
		"wastegate":
			bank.blowoff = _chatter(seed)
	var pops: Array[AudioStreamWAV] = []
	if s.backfire_rate > 0.0:
		for i in 4:
			pops.append(_pop_wav(s, seed + i * 31))
	bank.pops = pops
	bank.ms = (Time.get_ticks_usec() - t0) / 1000.0
	return bank


func _ready() -> void:
	_car = get_parent()
	_rng.randomize()
	warm_up()
	_squeal = _player(_cache.squeal, 10.0)
	_scrub = _player(_cache.scrub, 8.0)
	_wind = _player(_cache.wind, 6.0)
	_whistle = _player(null, 6.0)
	_oneshot = _player(null, 8.0)
	for i in 2:
		_pop_players.append(_player(null, 10.0))
	_grass = _player(_cache.grass, 7.0)
	for p in [_squeal, _scrub, _grass, _wind]:
		p.bus = &"Effects"
	add_child(CarImpacts.new()) # wall / rail / car contact sounds
	AudioSpace.ensure(self) # engine echo off walls, bridges and buildings
	_set_model(_car.model_id)


func _exit_tree() -> void:
	# Don't leave a synthesis task running past the scene (it would be orphaned on quit).
	if _spec.has("type"):
		_collect(_spec.type, true)


func _set_model(id: String) -> void:
	_model = id
	_spec = engine_spec(id)
	_bank = {}
	for p in _on + _off:
		p.queue_free()
	_on.clear()
	_off.clear()
	_whistle.stream = null
	request_engine(id)
	_attach_engine()


## Once the bank is ready, make one on/off player pair per rpm point.
func _attach_engine() -> void:
	_bank = engine_bank(_model)
	if _bank.is_empty():
		return
	for i in _bank.on.size():
		_on.append(_player(_bank.on[i], 12.0))
		_off.append(_player(_bank.off[i], 12.0))
	if _bank.has("whistle"):
		_whistle.stream = _bank.whistle
		if not _culled:
			_whistle.play(randf() * 0.3)
	if _culled:
		for p in _on + _off:
			p.stop()


func _player(stream: AudioStream, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = unit
	p.max_distance = CULL_DISTANCE + 40.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.volume_db = -80.0
	p.bus = &"Engine" # tyres / wind are moved to Effects in _ready
	add_child(p)
	if stream is AudioStreamWAV and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		p.play(randf() * 0.3)
	return p


func _process(dt: float) -> void:
	if _car.model_id != _model:
		_set_model(_car.model_id)
	elif _bank.is_empty():
		_attach_engine()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var far := cam.global_position.distance_to(global_position) > CULL_DISTANCE
		if far != _culled:
			_culled = far
			for p in _all_loops():
				if far:
					p.stop()
				else:
					p.stream_paused = false
					p.play(randf() * 0.3)
		if far:
			return

	var rpm := _car.rpm
	var red := _car.redline_rpm
	var gas := _car.throttle if _car.gear >= 0 else _car.brake
	var want_load := clampf(gas * 1.2, 0.0, 1.0) if _car.gear != 0 or rpm > 1500.0 else 0.3
	_load = lerpf(_load, want_load, 1.0 - exp(-dt * 10.0))
	var eng_gain := db_to_linear(_spec.volume_db)

	# Rev limiter: ignition cut stutters the engine and dips the revs.
	var cut := 1.0
	var dip := 1.0
	if rpm >= red * 0.985 and gas > 0.5:
		var before := _lim_phase
		_lim_phase += dt * float(_spec.limiter_hz)
		if fmod(_lim_phase, 1.0) < 0.45:
			cut = 0.3
			dip = 0.975
		if int(_lim_phase) != int(before) and _rng.randf() < float(_spec.backfire_rate) * 0.06:
			_pop(0.5)
	else:
		_lim_phase = 0.0

	# Crossfade the two recordings nearest this rpm, re-pitched to match.
	if not _bank.is_empty():
		var rpms: Array = _bank.rpms
		for k in rpms.size():
			var w := _rpm_weight(rpm, k, rpms)
			var pitch := clampf(rpm * dip / float(rpms[k]), 0.5, 2.0)
			_mix(_on[k], w * lerpf(0.25, 1.0, _load) * cut * eng_gain, pitch)
			_mix(_off[k], w * (1.0 - _load) * 0.75 * eng_gain, pitch)

	# Turbo builds with load and revs, whistles, and dumps when you lift.
	var lifted := _last_throttle > 0.7 and gas < 0.25
	if _spec.turbo:
		var target_boost := _load * clampf((rpm - float(_spec.spool_rpm)) / float(_spec.spool_span), 0.0, 1.0)
		var rate: float = _spec.spool_rate if target_boost > _boost else 6.0
		_boost = lerpf(_boost, target_boost, 1.0 - exp(-dt * rate))
		if _whistle.stream:
			_mix(_whistle, _boost * float(_spec.turbo_level) * eng_gain, 0.55 + _boost * 0.75)
		if lifted and _boost > 0.35 and _bank.has("blowoff"):
			_oneshot.stream = _bank.blowoff
			_oneshot.volume_db = linear_to_db(0.35 + _boost * 0.4) + volume_db
			_oneshot.pitch_scale = _rng.randf_range(0.94, 1.06)
			_oneshot.play()

	# Overrun pops: a burst right after lifting at high revs, then sporadic
	# crackle that dies away as the exhaust cools.
	if gas > 0.4:
		_lift_time = -1.0 # on the gas: not coasting
	elif _lift_time < 0.0:
		_lift_time = 0.0
	else:
		_lift_time += dt
	var bf: float = _spec.backfire_rate
	var hot := clampf((rpm / red - float(_spec.pop_min)) / (1.0 - float(_spec.pop_min)), 0.0, 1.0)
	if bf > 0.0 and gas < 0.15 and _car.gear != 0 and hot > 0.0 and _lift_time >= 0.0:
		if lifted and _rng.randf() < 0.7:
			_pop(0.7 + hot * 0.3)
		elif _rng.randf() < bf * hot * exp(-_lift_time / 2.5) * dt * (2.0 if _lift_time < 0.6 else 1.0):
			_pop(0.35 + hot * 0.5)
	_last_throttle = gas

	# Upshift at high revs: the ignition cut can light a bang in the exhaust.
	if _car.gear > _last_gear and _last_gear > 0 and bf > 0.0 and rpm > red * 0.55 and _rng.randf() < clampf(bf * 0.35, 0.15, 0.8):
		_pop(0.5 + 0.3 * hot)
	if _car.gear != _last_gear and _car.gear > 0 and _last_gear > 0:
		if not _oneshot.playing:
			_oneshot.stream = _cache.clunk
			_oneshot.volume_db = linear_to_db(0.5) + volume_db
			_oneshot.pitch_scale = 1.0
			_oneshot.play()
	_last_gear = _car.gear

	# Tyres: squeal on tarmac, rumble and crunch off it.
	# Off the tarmac: gravel traps (grip ~0.62) crunch, grass / earth (lower) swishes.
	var slip := 0.0
	var rough := 0.0
	var grass := 0.0
	for w in _car.wheels:
		if not w.grounded:
			continue
		if w.surface_grip >= 0.9:
			slip = maxf(slip, w.slip)
		elif w.surface_grip > 0.58:
			rough += 0.25
		else:
			grass += 0.25 + 0.15 * clampf(w.slip, 0.0, 1.0)
	var speed := absf(_car.speed)
	var squeal := clampf((slip - 0.08) * 2.2, 0.0, 1.0) * clampf(speed / 8.0, 0.0, 1.0)
	_mix(_squeal, squeal * 0.55, 0.92 + slip * 0.15)
	_mix(_scrub, rough * clampf(speed / 20.0, 0.0, 1.0) * 0.8, 0.8 + speed / 60.0)
	_mix(_grass, minf(grass, 1.0) * clampf(speed / 16.0, 0.0, 1.0) * 0.6, 0.75 + speed / 70.0)
	# Wind rush: quiet at town speeds, building steeply towards top speed.
	var air := clampf(speed / 75.0, 0.0, 1.0)
	_mix(_wind, (air * 0.3 + air * air * 0.35) * _wind_gain(), 0.75 + speed / 80.0)


## Wind is heard from the camera's own car only when close (it's the air
## rushing past *you*); in the cockpit the shell muffles it a bit.
func _wind_gain() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam is ChaseCamera and (cam as ChaseCamera).target == _car:
		return 0.75 if ChaseCamera.cockpit_view else 1.0
	return 0.35


## Fire one random overrun pop at `level` (0..1).
func _pop(level: float) -> void:
	var pops: Array = _bank.get("pops", [])
	if pops.is_empty():
		return
	var p := _pop_players[_pop_next]
	_pop_next = (_pop_next + 1) % _pop_players.size()
	p.stream = pops[_rng.randi() % pops.size()]
	p.pitch_scale = _rng.randf_range(0.85, 1.15)
	p.volume_db = linear_to_db(level * _rng.randf_range(0.6, 1.0)) + volume_db + float(_spec.volume_db)
	p.play()
	popped.emit(level)


static func _rpm_weight(rpm: float, k: int, r: Array) -> float:
	if k > 0 and rpm < r[k]:
		return clampf((rpm - r[k - 1]) / (r[k] - r[k - 1]), 0.0, 1.0) if rpm > r[k - 1] else 0.0
	if k < r.size() - 1 and rpm >= r[k]:
		return clampf((r[k + 1] - rpm) / (r[k + 1] - r[k]), 0.0, 1.0)
	# Below the first / above the last recording: that one alone.
	return 1.0 if (k == 0 and rpm < r[0]) or (k == r.size() - 1 and rpm >= r[k]) else 0.0


func _mix(p: AudioStreamPlayer3D, linear: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(linear, 0.0001)) + volume_db
	p.pitch_scale = pitch
	# Inaudible loops are paused so they cost no mixing (resumed where they were).
	var mute := linear < SILENT
	if p.stream_paused != mute:
		p.stream_paused = mute


func _all_loops() -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	out.append_array(_on)
	out.append_array(_off)
	out.append_array([_squeal, _scrub, _grass, _wind])
	if _whistle.stream:
		out.append(_whistle)
	return out


# ---------------------------------------------------------------- engine synthesis

## One engine loop at a fixed rpm. Returns {wav, rpm (exact, after rounding the
## loop to whole cycles), fire_hz, cycles, nans}.
static func _engine_loop(s: Dictionary, rpm: float, on_load: bool, seed: int) -> Dictionary:
	var rotary: bool = s.rotary
	var cyl: int = s.cylinders
	var revs_per_cycle := 1.0 if rotary else 2.0 # four-stroke: each cylinder fires every other turn
	var cycle := revs_per_cycle * 60.0 / rpm
	var cycles := maxi(2, int(round(LOOP_SEC / cycle)))
	var n := int(round(cycles * cycle * RATE))
	var dur := float(n) / RATE
	var real_rpm := cycles * revs_per_cycle / dur * 60.0
	var crank := real_rpm / 60.0
	var fires := cycles * cyl
	var fire_hz := fires / dur
	var spacing := float(n) / fires
	var idle: float = s.idle_rpm
	var red: float = s.redline_rpm
	var x := clampf((real_rpm - idle) / (red - idle), 0.0, 1.0)
	var cam := 0.0
	if s.cam_rpm > 0.0:
		cam = smoothstep(s.cam_rpm - 250.0, s.cam_rpm + 250.0, real_rpm)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buf := PackedFloat32Array()
	buf.resize(n)

	var load_f := 1.0 if on_load else 0.0
	var res: float = lerpf(s.exhaust_resonance_hz[0], s.exhaust_resonance_hz[1], x) * lerpf(0.85, 1.0, load_f)
	var tau := clampf(float(s.pulse_decay) / fire_hz, 0.0012, 0.016)
	var attack := maxf(float(s.attack), 0.00003)
	var grit: float = s.grit * lerpf(0.45, 1.0, load_f)
	var ind: float = s.induction_noise * lerpf(1.0, s.cam_induction, cam) * lerpf(0.25, 1.0, load_f)
	var ind_tone: float = s.induction_tone
	var saw: float = s.saw * lerpf(0.7, 1.0, load_f)
	var saw_tau: float = spacing / RATE * float(s.saw_decay)
	var res2: float = s.resonance2
	var res2_ratio: float = s.resonance2_ratio
	var bank_split: float = s.bank_split
	var thump: float = s.thump * lerpf(0.6, 1.0, load_f)
	var thump_n := maxi(int(spacing * float(s.thump_width)), 4)
	var win := maxi(int(maxf(tau * 5.0, saw_tau * 5.0 if saw > 0.0 else 0.0) * RATE), thump_n + 1)
	win = clampi(win, 32, n)
	var fade := maxi(win / 8, 8)
	var ga := 1.0 - exp(-TAU * float(s.grit_hz) / RATE)
	var ia := 1.0 - exp(-TAU * 2500.0 / RATE)

	# Pulse kernels: one per cylinder (bank / collector alternates), reused with
	# per-pulse gain so the noise doesn't repeat every firing.
	var nk := mini(cyl, 6) * (2 if cyl <= 2 else 1)
	var kernels: Array[PackedFloat32Array] = []
	for v in nk:
		var kern := PackedFloat32Array()
		kern.resize(win)
		var ph := rng.randf() * TAU
		var r1 := res * (bank_split if v % 2 == 1 else 1.0) * rng.randf_range(0.97, 1.03)
		var w1 := TAU * r1 / RATE
		var w2 := w1 * res2_ratio
		var wi := TAU * float(s.induction_hz) * rng.randf_range(0.96, 1.04) / RATE
		var decay := exp(-1.0 / (tau * RATE))
		var rise := exp(-1.0 / (attack * RATE))
		var saw_d := exp(-1.0 / (saw_tau * RATE))
		var ind_d := exp(-1.0 / (tau * 1.6 * RATE))
		var env := 1.0
		var ienv := 1.0
		var senv := 1.0
		var att := 1.0
		var gl := 0.0
		var il := 0.0
		var p1 := ph
		var p2 := ph * 1.7
		var pind := ph * 0.6
		for k in win:
			att *= rise
			var a := 1.0 - att
			gl += ga * (rng.randf_range(-1.0, 1.0) - gl)
			var val := (sin(p1) + res2 * sin(p2) + grit * 2.0 * gl) * env * a
			if saw > 0.0:
				val += saw * senv * a
				senv *= saw_d
			if ind > 0.0:
				il += ia * (rng.randf_range(-1.0, 1.0) - il)
				val += ind * ienv * a * (ind_tone * sin(pind) + (1.0 - ind_tone) * 2.5 * il)
				ienv *= ind_d
				pind += wi
			if k >= win - fade:
				val *= float(win - k) / fade
			if k < thump_n:
				var q := sin(PI * k / thump_n)
				val += thump * q * q
			kern[k] = val
			env *= decay
			p1 += w1
			p2 += w2
		kernels.append(kern)

	# Fixed per-cylinder character, then lay down every firing.
	var cyl_amp := PackedFloat32Array()
	var cyl_off := PackedFloat32Array()
	for c in cyl:
		cyl_amp.append(1.0 + float(s.cyl_variation) * rng.randf_range(-1.0, 1.0))
		cyl_off.append(float(s.firing_irregularity) * spacing * rng.randf_range(-1.0, 1.0))
	var jitter: float = s.pulse_jitter
	var lope: float = s.lope * pow(1.0 - x, 2.0) * lerpf(1.6, 1.0, load_f)
	var misfire := lope * 0.35 + (0.0 if on_load else 0.08 + 0.1 * minf(s.backfire_rate, 3.0) / 3.0)
	var carry := 0.0
	var gain := lerpf(s.overrun_level, 1.0, load_f)
	for i in fires:
		var c := i % cyl
		# (+0.37: keep a pulse onset off the loop seam)
		var start := int(round((i + 0.37) * spacing + cyl_off[c] + rng.randf_range(-1.0, 1.0) * jitter * 0.15 * spacing))
		var a := cyl_amp[c] * gain * rng.randf_range(1.0 - jitter, 1.0 + jitter)
		# Misfire-and-catch: a weak pulse, then the unburnt charge fattens the next ("brap").
		if rng.randf() < misfire:
			carry = a * 0.6
			a *= 0.3
		elif carry > 0.0:
			a += carry
			carry = 0.0
		var kern := kernels[(c + (cyl * (rng.randi() % 2) if nk > cyl else 0)) % nk]
		start = posmod(start, n)
		var first := mini(win, n - start)
		for k in first:
			buf[start + k] += a * kern[k]
		for k in range(first, win):
			buf[k - first] += a * kern[k]

	# Tonal body: low crank orders (whole numbers of cycles fit the loop exactly).
	var body_gain := lerpf(0.6, 1.0, load_f)
	var tones: Array = []
	for h in s.harmonics:
		tones.append([float(h[0]), float(h[1]) * body_gain])
	if s.mech_order > 0.0:
		var level: float = s.mech_level * lerpf(0.4, 1.0, x)
		tones.append([float(s.mech_order), level])
		tones.append([float(s.mech_order) * 2.0, level * 0.3])
	for tone in tones:
		var f := roundf(tone[0] * crank * dur) / dur
		if f <= 0.0 or f > RATE * 0.45:
			continue
		var amp: float = tone[1]
		var w := TAU * f / RATE
		var cw := cos(w)
		var sw := sin(w)
		var ph := rng.randf() * TAU
		var re := cos(ph)
		var im := sin(ph)
		for j in n:
			buf[j] += amp * im
			var nr := re * cw - im * sw
			im = re * sw + im * cw
			re = nr

	var cutoff: float = lerpf(s.brightness[0], s.brightness[1], x) * lerpf(1.0, s.cam_bright, cam) * lerpf(0.6, 1.0, load_f)
	buf = _lowpass_loop(buf, minf(cutoff, RATE * 0.45))
	_normalise(buf, 1.0)
	var drive: float = s.drive * lerpf(0.7, 1.0, load_f)
	var norm := 1.0 / tanh(drive)
	var nans := 0
	for j in n:
		var v := buf[j]
		if is_nan(v):
			nans += 1
			v = 0.0
		buf[j] = tanh(v * drive) * norm
	return {wav = _to_wav(_normalise(buf, 0.85), true), rpm = real_rpm, fire_hz = fire_hz, cycles = cycles, nans = nans}


## Turbo: a whistle whose pitch follows boost, over a band of rushing air.
static func _turbo_loop(hz: float, whoosh: float, seed: int) -> AudioStreamWAV:
	var dur := 0.5
	var n := int(dur * RATE)
	var fade := int(0.1 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 99
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	for j in raw.size():
		raw[j] = rng.randf_range(-1.0, 1.0)
	raw = _bandpass(raw, hz * 0.55, 1.4)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		buf[j] = raw[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = raw[j] * w + raw[n + j] * (1.0 - w)
	_normalise(buf, 1.0)
	var f := roundf(hz * dur) / dur
	for j in n:
		var t := float(j) / RATE
		buf[j] = buf[j] * whoosh + (1.0 - whoosh) * (sin(TAU * f * t) + 0.2 * sin(TAU * f * 2.0 * t))
	return _to_wav(_normalise(_lowpass_loop(buf, 7000.0), 0.6), true)


## Overrun pop: one or a few bangs, each a low boom plus a sharp crack.
static func _pop_wav(s: Dictionary, seed: int) -> AudioStreamWAV:
	var n := int(0.3 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buf := PackedFloat32Array()
	buf.resize(n)
	var bangs := 1 + rng.randi() % maxi(int(s.pop_cluster), 1)
	var at := 0
	for b in bangs:
		var amp := rng.randf_range(0.6, 1.0) * (1.0 if b == 0 else 0.7)
		var boom := float(s.pop_hz) * rng.randf_range(0.85, 1.2)
		var crack: float = s.pop_crack
		var lp := 0.0
		var span := mini(int(0.09 * RATE), n - at)
		for k in span:
			var t := float(k) / RATE
			lp += 0.55 * (rng.randf_range(-1.0, 1.0) - lp)
			var v := sin(TAU * boom * t * (1.0 - t * 2.0)) * exp(-t / 0.022) * minf(t / 0.0008, 1.0)
			v += crack * lp * 2.0 * exp(-t / 0.005)
			buf[at + k] += amp * v
		at += int(rng.randf_range(0.03, 0.07) * RATE)
		if at >= n - 64:
			break
	return _to_wav(_normalise(_lowpass(buf, 5000.0), 0.85), false)


## Wastegate / compressor chatter on lift: rapid stuttering bursts of air.
static func _chatter(seed: int) -> AudioStreamWAV:
	var n := int(0.6 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var bp := 0.0
	for j in n:
		var t := float(j) / RATE
		var env := minf(t / 0.008, 1.0) * exp(-t / 0.2)
		var rate := lerpf(26.0, 15.0, t / 0.6) # stutter slows as pressure falls
		var g := fmod(t * rate, 1.0)
		var gate := exp(-g / 0.18) # each flap: sharp onset, quick decay
		var centre := lerpf(2100.0, 1100.0, t / 0.6)
		var f := 2.0 * sin(PI * centre / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		lp += f * bp
		var hp := x - lp - 0.5 * bp
		bp += f * hp
		buf[j] = bp * env * (0.15 + 0.85 * gate)
	return _to_wav(_normalise(buf, 0.8), false)


# ---------------------------------------------------------------- shared sounds

## Filtered noise loop; optional tonal component (tyre squeal) or crackle (gravel).
static func _noise_loop(dur: float, centre: float, q: float, tone_mix: float, tone_hz: float, crackle := false) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var fade := int(0.15 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centre)
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	for j in raw.size():
		raw[j] = rng.randf_range(-1.0, 1.0)
		if crackle and rng.randf() < 0.004:
			raw[j] += rng.randf_range(-6.0, 6.0)
	raw = _bandpass(raw, centre, q) if q > 1.0 else _lowpass(raw, centre)
	if tone_mix > 0.0:
		var f := roundf(tone_hz * dur) / dur
		for j in raw.size():
			var t := float(j) / RATE
			var wobble := 1.0 + 0.012 * sin(TAU * 3.0 / dur * t)
			raw[j] = raw[j] * (1.0 - tone_mix) + tone_mix * 0.4 * sin(TAU * f * t * wobble)
	# Crossfade the tail into the head for a seamless loop.
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		buf[j] = raw[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = raw[j] * w + raw[n + j] * (1.0 - w)
	return _to_wav(_normalise(buf, 0.8), true)


## Tyres through grass: low swish with irregular soft thumps (clods, bumps).
static func _grass_loop() -> AudioStreamWAV:
	var dur := 1.3
	var n := int(dur * RATE)
	var fade := int(0.15 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var env := 0.6
	for j in raw.size():
		if rng.randf() < 12.0 / RATE: # a bump every ~80 ms on average
			env = rng.randf_range(0.8, 1.6)
		env = lerpf(env, 0.55, 0.0006)
		raw[j] = rng.randf_range(-1.0, 1.0) * env
	var swish := _bandpass(raw.duplicate(), 650.0, 0.7)
	var body := _lowpass(raw, 160.0)
	for j in raw.size():
		raw[j] = swish[j] + body[j] * 2.5
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		buf[j] = raw[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = raw[j] * w + raw[n + j] * (1.0 - w)
	return _to_wav(_normalise(buf, 0.8), true)


static func _tone_loop(hz: float, dur: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var f := roundf(hz * dur) / dur
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		var t := float(j) / RATE
		buf[j] = sin(TAU * f * t) + 0.2 * sin(TAU * f * 2.0 * t) + rng.randf_range(-0.15, 0.15)
	return _to_wav(_normalise(_lowpass_loop(buf, 7000.0), 0.6), true)


## Blow-off valve: a hissing burst with falling pitch and an optional flutter.
static func _blowoff(dur: float, c0: float, c1: float, flutter_hz: float, flutter: float, decay: float, seed: int) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 11
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var bp := 0.0
	for j in n:
		var t := float(j) / RATE
		var env := minf(t / 0.015, 1.0) * exp(-t / decay)
		var fl := 1.0 - flutter + flutter * sin(TAU * flutter_hz * t)
		var centre := lerpf(c0, c1, t / dur)
		var f := 2.0 * sin(PI * centre / RATE)
		var x := rng.randf_range(-1.0, 1.0)
		lp += f * bp
		var hp := x - lp - 0.7 * bp
		bp += f * hp
		buf[j] = bp * env * fl
	return _to_wav(_normalise(buf, 0.8), false)


static func _clunk() -> AudioStreamWAV:
	var n := int(0.12 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		var t := float(j) / RATE
		buf[j] = exp(-t / 0.025) * (sin(TAU * 85.0 * t) + 0.4 * sin(TAU * 230.0 * t)) + exp(-t / 0.004) * rng.randf_range(-0.6, 0.6)
	return _to_wav(_normalise(buf, 0.7), false)


# ---------------------------------------------------------------- DSP helpers

static func _lowpass(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for j in buf.size():
		y += a * (buf[j] - y)
		buf[j] = y
	return buf


## Low-pass that wraps around so the loop seam stays continuous.
static func _lowpass_loop(buf: PackedFloat32Array, cutoff: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for j in buf.size(): # warm-up pass: settle the filter on the loop's own tail
		y += a * (buf[j] - y)
	for j in buf.size():
		y += a * (buf[j] - y)
		buf[j] = y
	return buf


static func _bandpass(buf: PackedFloat32Array, centre: float, q: float) -> PackedFloat32Array:
	# RBJ biquad band-pass.
	var w := TAU * centre / RATE
	var alpha := sin(w) / (2.0 * q)
	var b0 := alpha
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos(w)
	var a2 := 1.0 - alpha
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for j in buf.size():
		var x := buf[j]
		var y := (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[j] = y
	return buf


static func _normalise(buf: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var mean := 0.0
	for v in buf:
		mean += v
	mean /= maxf(buf.size(), 1)
	var hi := 0.0001
	for j in buf.size():
		buf[j] -= mean
		hi = maxf(hi, absf(buf[j]))
	var g := peak / hi
	for j in buf.size():
		buf[j] *= g
	return buf


static func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for j in buf.size():
		bytes.encode_s16(j * 2, int(clampf(buf[j], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w
