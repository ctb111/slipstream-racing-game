class_name CarImpacts
extends Node3D
## Contact sounds for its parent Car: a crunch or thud when it hits a wall,
## rail or another car (louder and heavier with the impact speed), and a
## metallic scrape / rubbing loop while it grinds along a guardrail, wall or
## another car. Added by CarAudio; only local (physics-simulated) cars listen
## for contacts, puppets of other players' cars make their own sound on their
## own machine.
##
## All sounds are synthesised (CC0-free: no samples) once on a worker thread
## and cached statically, like CarAudio's engines:
##   heavy   low body thump with a pitch drop, a crunch of crackle and the ring
##           of a few inharmonic steel modes;
##   light   a short thud with a faint ring;
##   bump    car against car: a hollow, damped panel knock;
##   scrape  grinding steel: band-passed noise chopped by stick-slip grains,
##           each grain exciting a bright rail resonance;
##   rub     body against a concrete wall or a car: dull, low grinding.
##
## Debug: `-- --debug-impacts` prints every impact.

const RATE := CarAudio.RATE
const MIN_IMPACT := 1.2 ## m/s of speed change into the obstacle before anything sounds
const HEAVY_FROM := 6.0 ## m/s: from here on it's a crunch, not a knock
const SCRAPE_FROM := 1.5 ## m/s of sliding along the obstacle

enum Kind { NONE, WALL, RAIL, CAR, GROUND }

static var _cache := {}
static var _task := -1

var _car: Car
var _prev_v := Vector3.ZERO
var _touching := {} ## collider instance id -> seconds since the last impact sound from it
var _seen := {} ## colliders touched this tick (reused)
var _kinds := {} ## collider instance id -> Kind (names don't change)
var _hit: Array[AudioStreamPlayer3D] = []
var _hit_next := 0
var _scrape: AudioStreamPlayer3D
var _rub: AudioStreamPlayer3D
var _scrape_level := 0.0
var spark_level := 0.0 ## 0..1 metal-on-metal / wall grinding right now (CarFx sparks)
var spark_pos := Vector3.ZERO ## world point of the grinding contact
var _rub_level := 0.0
var _debug := false
var _rng := RandomNumberGenerator.new()


static func warm_up() -> void:
	if _cache.is_empty() and _task < 0:
		_task = WorkerThreadPool.add_task(func() -> void:
			var c := {
				heavy = [_heavy(11), _heavy(23), _heavy(37)],
				light = [_light(5), _light(9), _light(17)],
				bump = [_bump(3), _bump(8)],
				scrape = _scrape_loop(),
				rub = _rub_loop(),
			}
			_cache.merge(c) # read on the main thread only after the task completed
			, false, "impact sounds")


static func _ready_cache() -> bool:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return not _cache.is_empty()


func _ready() -> void:
	var n := get_parent()
	while n and not n is Car: # added by CarAudio, so the car is further up
		n = n.get_parent()
	_car = n as Car
	_rng.randomize()
	_debug = OS.get_cmdline_user_args().has("--debug-impacts")
	warm_up()
	for i in 3:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Effects"
		p.unit_size = 12.0
		p.max_distance = 220.0
		p.attenuation_filter_cutoff_hz = 7000.0
		p.attenuation_filter_db = -16.0
		add_child(p)
		_hit.append(p)
	_scrape = _loop_player(9.0)
	_rub = _loop_player(8.0)
	if _car and not _car.remote:
		_car.contact_monitor = true
		_car.max_contacts_reported = 8


func _loop_player(unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"Effects"
	p.unit_size = unit
	p.max_distance = 160.0
	p.volume_db = -80.0
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -16.0
	add_child(p)
	return p


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _physics_process(dt: float) -> void:
	if _car == null or _car.remote or not _ready_cache():
		return
	if _scrape.stream == null:
		_scrape.stream = _cache.scrape
		_rub.stream = _cache.rub
	var v := _car.linear_velocity
	var dv := v - _prev_v
	_prev_v = v
	if not _touching.is_empty():
		for id in _touching.keys():
			_touching[id] += dt
	var scrape := 0.0
	var rub := 0.0
	var sparks := 0.0
	var spark_at := spark_pos
	var state := PhysicsServer3D.body_get_direct_state(_car.get_rid())
	_seen.clear()
	if state:
		for i in state.get_contact_count():
			var col := state.get_contact_collider_object(i)
			var id := col.get_instance_id() if col else 0
			if not _kinds.has(id):
				_kinds[id] = _kind(col)
			var kind: Kind = _kinds[id]
			if kind == Kind.NONE or kind == Kind.GROUND:
				continue
			var n := state.get_contact_local_normal(i) # points from the obstacle into us
			var other_v := Vector3.ZERO
			if col is Car:
				other_v = (col as Car).linear_velocity
			var rel := v - other_v
			# Speed change into the obstacle this tick, or the impulse the solver applied.
			var into := maxf(absf(dv.dot(n)), state.get_contact_impulse(i).length() / maxf(_car.mass, 1.0))
			var slide := (rel - n * rel.dot(n)).length()
			_seen[id] = true
			if not _touching.has(id) or _touching[id] > 0.35:
				if into > MIN_IMPACT and (not _touching.has(id) or into > 3.0):
					_impact(kind, into, state.get_contact_collider_position(i))
					_touching[id] = 0.0
				elif not _touching.has(id):
					_touching[id] = 1.0
			if slide > SCRAPE_FROM:
				var k := clampf((slide - SCRAPE_FROM) / 22.0, 0.0, 1.0)
				if kind != Kind.CAR and slide > 5.0 and k >= sparks:
					sparks = k
					spark_at = state.get_contact_collider_position(i)
				if kind == Kind.RAIL:
					scrape = maxf(scrape, 0.25 + 0.75 * k)
				else:
					rub = maxf(rub, 0.25 + 0.75 * k)
	if not _touching.is_empty():
		for id in _touching.keys():
			if not _seen.has(id) and _touching[id] > 0.5:
				_touching.erase(id)
	spark_level = sparks
	spark_pos = spark_at
	_scrape_level = move_toward(_scrape_level, scrape, dt * (8.0 if scrape > _scrape_level else 5.0))
	_rub_level = move_toward(_rub_level, rub, dt * (8.0 if rub > _rub_level else 5.0))
	_loop(_scrape, _scrape_level, 0.8 + 0.5 * _scrape_level)
	_loop(_rub, _rub_level, 0.85 + 0.35 * _rub_level)


func _loop(p: AudioStreamPlayer3D, level: float, pitch: float) -> void:
	if level < 0.01:
		if p.playing:
			p.stop()
		return
	if not p.playing:
		p.play(_rng.randf() * 1.0)
	p.volume_db = linear_to_db(level * 0.8)
	p.pitch_scale = pitch * _rng.randf_range(0.98, 1.02)


## What the car touched. Barriers are named by the track builders.
static func _kind(col: Object) -> Kind:
	if col == null:
		return Kind.NONE
	if col is Car:
		return Kind.CAR
	if not col is Node:
		return Kind.NONE
	var n := String((col as Node).name).to_lower()
	if n.contains("guardrail") or n.contains("rail") or n.contains("armco") or n.contains("fence"):
		return Kind.RAIL
	if n.contains("terrain") or n.contains("ground") or n.contains("road") or n.contains("gravel") \
			or n.contains("grass") or n.contains("curb") or n.contains("kerb") or n.contains("runoff"):
		return Kind.GROUND
	if col is StaticBody3D or col is RigidBody3D:
		return Kind.WALL
	return Kind.NONE


func _impact(kind: Kind, speed: float, at: Vector3) -> void:
	var k := clampf((speed - MIN_IMPACT) / 14.0, 0.0, 1.0)
	var bank: Array
	if kind == Kind.CAR:
		bank = _cache.bump if speed < HEAVY_FROM * 1.3 else _cache.heavy
	else:
		bank = _cache.light if speed < HEAVY_FROM else _cache.heavy
	var p := _hit[_hit_next]
	_hit_next = (_hit_next + 1) % _hit.size()
	p.global_position = at
	p.stream = bank[_rng.randi() % bank.size()]
	p.volume_db = linear_to_db(0.18 + 0.82 * k) + (2.0 if kind == Kind.RAIL else 0.0)
	# Harder hits sound bigger: a touch lower. Car bumps are lighter bodies.
	p.pitch_scale = _rng.randf_range(0.92, 1.08) * (1.1 - 0.2 * k) * (1.08 if kind == Kind.CAR else 1.0)
	p.play()
	if _debug:
		print("impact %s %.1f m/s  vol %.1f dB" % [Kind.keys()[kind], speed, p.volume_db])


# ---------------------------------------------------------------- synthesis

static func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * RATE))
	return b


## Decaying sine partials: [hz, level, decay seconds].
static func _modes(b: PackedFloat32Array, modes: Array, start: int, rng: RandomNumberGenerator) -> void:
	for m in modes:
		var hz: float = m[0] * rng.randf_range(0.96, 1.04)
		var lvl: float = m[1]
		var tau: float = m[2]
		var ph := rng.randf() * TAU
		for j in range(start, b.size()):
			var t := float(j - start) / RATE
			var env := exp(-t / tau)
			if env < 0.001:
				break
			b[j] += lvl * env * sin(TAU * hz * t + ph)


static func _heavy(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := _buf(1.1)
	# Body thump: a low sine dropping in pitch.
	var ph := 0.0
	for j in int(0.35 * RATE):
		var t := float(j) / RATE
		var hz := lerpf(95.0, 48.0, minf(t / 0.2, 1.0))
		ph += TAU * hz / RATE
		b[j] += 0.9 * exp(-t / 0.09) * sin(ph)
	# Crunch: dense noise with crackle, fading over ~0.25 s; a second smaller crunch.
	var noise := _buf(1.1)
	for j in noise.size():
		var t := float(j) / RATE
		var env := exp(-t / 0.07) + 0.35 * exp(-maxf(t - 0.09, 0.0) / 0.05) * float(t > 0.09)
		var x := rng.randf_range(-1.0, 1.0)
		if rng.randf() < 0.02 * env:
			x += rng.randf_range(-5.0, 5.0)
		noise[j] = x * env
	noise = CarAudio._lowpass(noise, 3800.0)
	for j in b.size():
		b[j] += noise[j] * 0.8
	# Steel ringing (panels, rail): inharmonic modes, the higher ones die first.
	_modes(b, [[310.0, 0.12, 0.22], [587.0, 0.1, 0.18], [1130.0, 0.07, 0.14], [1873.0, 0.05, 0.1], [2650.0, 0.035, 0.07]], 0, rng)
	# Loose bits settling.
	for i in 5:
		var at := int(rng.randf_range(0.12, 0.6) * RATE)
		_modes(b, [[rng.randf_range(1500.0, 4200.0), 0.05, 0.02]], at, rng)
	return CarAudio._to_wav(CarAudio._normalise(_fade_tail(b), 0.95), false)


static func _light(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := _buf(0.45)
	var ph := 0.0
	for j in int(0.2 * RATE):
		var t := float(j) / RATE
		ph += TAU * lerpf(150.0, 90.0, minf(t / 0.08, 1.0)) / RATE
		b[j] += 0.8 * exp(-t / 0.035) * sin(ph)
	var noise := _buf(0.45)
	for j in noise.size():
		var t := float(j) / RATE
		noise[j] = rng.randf_range(-1.0, 1.0) * exp(-t / 0.018)
	noise = CarAudio._lowpass(noise, 2600.0)
	for j in b.size():
		b[j] += noise[j] * 0.7
	_modes(b, [[480.0, 0.05, 0.1], [1260.0, 0.03, 0.06]], 0, rng)
	return CarAudio._to_wav(CarAudio._normalise(_fade_tail(b), 0.85), false)


static func _bump(seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var b := _buf(0.5)
	_modes(b, [[135.0, 0.7, 0.05], [262.0, 0.45, 0.04], [415.0, 0.25, 0.03], [890.0, 0.08, 0.05]], 0, rng)
	var noise := _buf(0.5)
	for j in noise.size():
		noise[j] = rng.randf_range(-1.0, 1.0) * exp(-float(j) / RATE / 0.025)
	noise = CarAudio._bandpass(noise, 1400.0, 0.8)
	for j in b.size():
		b[j] += noise[j] * 0.8
	return CarAudio._to_wav(CarAudio._normalise(_fade_tail(b), 0.85), false)


## Grinding steel: stick-slip grains of bright noise, each ringing the rail.
static func _scrape_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dur := 1.6
	var n := int(dur * RATE)
	var fade := int(0.12 * RATE)
	var raw := _buf(dur + 0.12)
	var env := 0.0
	var next := 0
	for j in raw.size():
		if j >= next:
			env = rng.randf_range(0.4, 1.0)
			next = j + int(RATE / rng.randf_range(35.0, 90.0))
		env *= 0.9993
		raw[j] = rng.randf_range(-1.0, 1.0) * env
	var hi := CarAudio._bandpass(raw.duplicate(), 3200.0, 1.4)
	var mid := CarAudio._bandpass(raw.duplicate(), 1350.0, 2.5)
	var ring := CarAudio._bandpass(raw.duplicate(), 2270.0, 18.0) # the rail's own resonance
	var ring2 := CarAudio._bandpass(raw, 4480.0, 22.0)
	var mix := _buf(dur + 0.12)
	for j in mix.size():
		mix[j] = hi[j] * 0.7 + mid[j] * 0.5 + ring[j] * 2.2 + ring2[j] * 1.4
	var buf := _buf(dur)
	for j in n:
		buf[j] = mix[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = mix[j] * w + mix[n + j] * (1.0 - w)
	return CarAudio._to_wav(CarAudio._normalise(buf, 0.8), true)


## Body rubbing concrete or another car: low, rough grind.
static func _rub_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var dur := 1.4
	var n := int(dur * RATE)
	var fade := int(0.12 * RATE)
	var raw := _buf(dur + 0.12)
	var env := 0.0
	var next := 0
	for j in raw.size():
		if j >= next:
			env = rng.randf_range(0.3, 1.0)
			next = j + int(RATE / rng.randf_range(18.0, 45.0))
		env *= 0.9996
		raw[j] = rng.randf_range(-1.0, 1.0) * env
	var lo := CarAudio._bandpass(raw.duplicate(), 420.0, 1.2)
	var mid := CarAudio._bandpass(raw, 1100.0, 1.6)
	var buf := _buf(dur)
	var mix := _buf(dur + 0.12)
	for j in mix.size():
		mix[j] = lo[j] + mid[j] * 0.6
	for j in n:
		buf[j] = mix[j]
	for j in fade:
		var w := float(j) / fade
		buf[j] = mix[j] * w + mix[n + j] * (1.0 - w)
	return CarAudio._to_wav(CarAudio._normalise(buf, 0.8), true)


static func _fade_tail(b: PackedFloat32Array) -> PackedFloat32Array:
	var f := int(0.03 * RATE)
	for j in f:
		b[b.size() - 1 - j] *= float(j) / f
	return b
