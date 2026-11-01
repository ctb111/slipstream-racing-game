class_name Ambience
extends Node3D
## Trackside ambient sound: crowds that murmur and cheer as cars pass, a
## distant PA announcer on the start straight, birds and wind in the trees,
## storm gusts, the odd crow or creaking branch in the snow, and rain drumming
## on the roof in the roof camera.
##
## Like CarAudio, every sound is synthesised once into short AudioStreamWAVs
## (on a worker thread, so loading never hitches) and cached statically; at
## run time the node only starts, stops and re-levels a handful of players.
## Weather's own rain hiss, thunder and snow wind are not duplicated here.
##
## Debug: `-- --debug-audio` prints the synthesis time and emitter counts.

enum Cond { CLEAR, STORM, SNOW }

const LO := 11025 ## crowd, PA and wind: distant, band-limited
const MID := 16000 ## rain on the roof, crow, creak
const HI := CarAudio.RATE ## birdsong needs the top octave
const CULL := 150.0 ## emitters further than this from the camera are stopped
const CHECK_EVERY := 0.2 ## seconds between car-near-crowd checks
const CHEER_RADIUS := 38.0
const BATTLE_GAP := 14.0 ## m: a car this close to the player counts as a fight for position
const BIRDS := 14
## Vowel formants (F1, F2) for babble.
const VOWELS: Array[Vector2] = [Vector2(730, 1090), Vector2(270, 2290), Vector2(530, 1840),
	Vector2(570, 840), Vector2(300, 870), Vector2(660, 1720), Vector2(490, 1350), Vector2(400, 2000)]

static var _cache := {}
static var synth_ms := 0.0 ## time the last synthesis job took
static var timings := {} ## ms per sound, for --debug-audio

## One group of spectators.
class Spot:
	var pos: Vector3
	var heads := 0
	var big := false ## the main grandstand
	var murmur: AudioStreamPlayer3D
	var cheer: AudioStreamPlayer3D
	var base_db := -14.0
	var excite := 0.0 ## 0..1, lifts the murmur while cars are about
	var cool := 0.0 ## seconds until the next cheer for any car
	var player_cool := 0.0 ## ...and for the local player
	var live := false

var cond := Cond.CLEAR
var night := false ## clear night: crickets and an owl instead of birdsong
var _curve: Curve3D
var _road_width := 12.0
var _terrain = null
var _crowd_meta: Array = []
var _task := -1
var _debug := false
var _race: Node = null
var _cars: Array[Car] = []
var _player_car: Car = null
var _spots: Array[Spot] = []
var _stands: Array[Spot] = []
var _birds: Array[AudioStreamPlayer3D] = []
var _bird_wait: Array[float] = []
var _bed: AudioStreamPlayer ## wind in the trees / storm gusts
var _roof: AudioStreamPlayer
var _pa: AudioStreamPlayer3D
var _pa_wait := 2.5 ## first call while the grid forms
var _distant: AudioStreamPlayer3D ## snow: crow or creak
var _distant_wait := 12.0
var _check_t := 0.0
var _last_roar := -100.0
var _finishers := 0
var _pending: Array = [] ## [time_left, Spot, strength] staggered cheers
var _clock := 0.0
var _stats := {cheers = 0, roars = 0, pa = 0, birds = 0, distant = 0, overtakes = 0}
var _player_place := 0 ## player's race position at the last check
var _overtake_t := 0.0 ## seconds left in which the crowd is still excited by a pass


## Adds the ambience for a circuit (called by Circuit via EXTRA_BUILDERS).
static func build(parent: Node3D, curve: Curve3D, road_width: float, preset: Dictionary) -> void:
	var a := Ambience.new()
	a.name = "Ambience"
	a._curve = curve
	a._road_width = road_width
	a.cond = cond_for(preset)
	a.night = float(preset.get("night", 0.0)) > 0.0
	a._terrain = parent.get_meta("terrain", null)
	a._crowd_meta = parent.get_meta("crowd_spots", []).duplicate()
	parent.add_child(a)


static func cond_for(preset: Dictionary) -> Cond:
	if float(preset.get("snow", 0.0)) > 0.0:
		return Cond.SNOW
	if float(preset.get("wet", 0.0)) > 0.5:
		return Cond.STORM
	return Cond.CLEAR


func _ready() -> void:
	_debug = OS.get_cmdline_user_args().has("--debug-audio")
	_task = WorkerThreadPool.add_task(_synth_job, false, "ambience synthesis")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _synth_job() -> void:
	synthesise(cond, night)


# ---------------------------------------------------------------- set-up

func _setup() -> void:
	var length := _curve.get_baked_length()
	for s in _crowd_meta:
		_add_spot(s[0], int(s[1]), false)
	# Main grandstand: left of the start straight, spread along it.
	for along in [-22.0, 10.0]:
		var xf := _frame(along)
		var p: Vector3 = xf.origin - xf.basis.x * (_road_width * 0.5 + 15.0)
		p.y = _ground(p) + 4.0
		_stands.append(_add_spot(p, 520, true))
	# PA speakers on the pit side of the straight.
	var pa_xf := _frame(-8.0)
	var pa_pos: Vector3 = pa_xf.origin + pa_xf.basis.x * (_road_width * 0.5 + 20.0)
	pa_pos.y = _ground(pa_pos) + 9.0
	_pa = _player3d(pa_pos, 16.0, -13.0)
	_pa.attenuation_filter_cutoff_hz = 3500.0

	var rng := RandomNumberGenerator.new()
	rng.seed = int(length)
	match cond:
		Cond.CLEAR when night:
			_bed = _player2d(_cache.crickets, -25.0)
			_distant = _player3d(Vector3.ZERO, 8.0, -12.0) # owl
			_distant.attenuation_filter_cutoff_hz = 3000.0
		Cond.CLEAR:
			for k in BIRDS:
				var xf := _frame(rng.randf() * length)
				var side := 1.0 if rng.randf() < 0.5 else -1.0
				var p: Vector3 = xf.origin + xf.basis.x * side * rng.randf_range(24.0, 60.0)
				p.y = _ground(p) + rng.randf_range(5.0, 12.0)
				var b := _player3d(p, 5.0, -9.0)
				b.max_distance = 115.0
				b.attenuation_filter_cutoff_hz = 9000.0
				_birds.append(b)
				_bird_wait.append(rng.randf_range(0.5, 9.0))
			_bed = _player2d(_cache.leaves, -27.0)
		Cond.STORM:
			_bed = _player2d(_cache.gusts, -14.0)
			_roof = _player2d(_cache.roof_rain, -80.0)
			_roof.stop()
		Cond.SNOW:
			_distant = _player3d(Vector3.ZERO, 7.0, -11.0)
			_distant.attenuation_filter_cutoff_hz = 2500.0
	if _debug:
		print("ambience: %s, synthesised in %.0f ms; %d crowd spots, %d birds" % [Cond.keys()[cond], synth_ms, _spots.size(), _birds.size()])


func _add_spot(p: Vector3, heads: int, big: bool) -> Spot:
	var s := Spot.new()
	s.pos = p
	s.heads = heads
	s.big = big
	# Power sum: ten times the people is +10 dB.
	s.base_db = -15.0 + 10.0 * log(maxf(heads, 5) / 40.0) / log(10.0)
	if big:
		s.base_db -= 3.0 # two emitters share the grandstand
	s.murmur = _player3d(p, 14.0 if big else 8.0, s.base_db)
	s.murmur.stream = _cache.murmur_big if big else _cache.murmur
	s.murmur.pitch_scale = randf_range(0.95, 1.05)
	s.cheer = _player3d(p, 14.0 if big else 9.0, s.base_db)
	_spots.append(s)
	return s


func _player3d(p: Vector3, unit: float, db: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = &"Ambience"
	a.unit_size = unit
	a.max_distance = CULL + 20.0
	a.attenuation_filter_cutoff_hz = 5000.0
	a.attenuation_filter_db = -14.0
	a.volume_db = db
	add_child(a)
	a.global_position = p
	return a


func _player2d(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.bus = &"Ambience"
	a.stream = stream
	a.volume_db = db
	add_child(a)
	a.play(randf() * 2.0)
	return a


## Curve frame at `offset` metres past the start line (basis.x points right).
func _frame(offset: float) -> Transform3D:
	var length := _curve.get_baked_length()
	var o := fposmod(offset, length)
	var p := _curve.sample_baked(o)
	var t := (_curve.sample_baked(fposmod(o + 1.0, length)) - _curve.sample_baked(fposmod(o - 1.0, length))).normalized()
	var r := t.cross(Vector3.UP).normalized()
	return Transform3D(Basis(r, Vector3.UP, -t), p)


func _ground(p: Vector3) -> float:
	return _terrain.surface_at(p.x, p.z) if _terrain else p.y


## Finds the Race (grandparent, or the current scene) and hooks its signals.
func _find_race() -> void:
	var cands: Array[Node] = []
	var gp := get_parent().get_parent() if get_parent() else null
	if gp:
		cands.append(gp)
	if get_tree().current_scene:
		cands.append(get_tree().current_scene)
	for c in cands:
		if c.has_signal("lights_changed") and "entries" in c:
			_race = c
			break
	if not _race:
		return
	if _race.has_signal("lights_changed"):
		_race.lights_changed.connect(_on_lights)
	if _race.has_signal("lap_completed"):
		_race.lap_completed.connect(_on_lap)
	if _race.has_signal("race_finished"):
		_race.race_finished.connect(_on_finished)


func _refresh_cars() -> void:
	_cars.clear()
	for e in _race.entries:
		if e.car and is_instance_valid(e.car):
			_cars.append(e.car)
	var pl = _race.get("player")
	_player_car = pl.car if pl and is_instance_valid(pl.car) else null


# ---------------------------------------------------------------- run time

func _process(dt: float) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_setup()
	if _spots.is_empty() and _birds.is_empty() and not _pa:
		return
	_clock += dt
	if not _race:
		_find_race()
	elif _cars.is_empty() or fmod(_clock, 2.0) < dt:
		_refresh_cars() # network cars come and go
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var cp := cam.global_position

	_check_t -= dt
	if _check_t <= 0.0:
		_check_t = CHECK_EVERY
		_cull(cp)
		_check_cars()
	for s in _spots:
		s.cool -= dt
		s.player_cool -= dt
		if s.live:
			s.excite = maxf(s.excite - dt * 0.12, 0.0)
			s.murmur.volume_db = s.base_db + 6.0 * s.excite
	for k in range(_pending.size() - 1, -1, -1):
		_pending[k][0] -= dt
		if _pending[k][0] <= 0.0:
			var item: Array = _pending[k]
			_pending.remove_at(k)
			_cheer(item[1], item[2], item[3])

	_nature(dt, cp)
	_pa_wait -= dt
	if _pa_wait <= 0.0:
		_pa_wait = randf_range(28.0, 60.0)
		if cp.distance_to(_pa.global_position) < CULL and not _pa.playing:
			_pa.stream = _cache.pa_a if randf() < 0.5 else _cache.pa_b
			_pa.pitch_scale = randf_range(0.96, 1.04)
			_pa.play()
			_stats.pa += 1
	if _roof:
		var on := cam is ChaseCamera and (cam as ChaseCamera).mode == ChaseCamera.Mode.ROOF
		var want := -9.0 if on else -60.0
		_roof.volume_db = move_toward(_roof.volume_db, want, dt * 60.0)
		if on and not _roof.playing:
			_roof.play(randf() * 2.0)
		elif not on and _roof.playing and _roof.volume_db <= -59.0:
			_roof.stop()


func _cull(cp: Vector3) -> void:
	for s in _spots:
		var near := cp.distance_to(s.pos) < CULL
		if near == s.live:
			continue
		s.live = near
		if near:
			s.murmur.play(randf() * 3.5)
		else:
			s.murmur.stop()
			s.cheer.stop()
	if _pa and _pa.playing and cp.distance_to(_pa.global_position) > CULL:
		_pa.stop()


func _check_cars() -> void:
	if _cars.is_empty():
		return
	var r2 := CHEER_RADIUS * CHEER_RADIUS
	# Close racing and overtakes by the player get the crowd going.
	var battle := 0.0 ## 0..1: another car within BATTLE_GAP of the player
	var overtook := false
	if _player_car and is_instance_valid(_player_car):
		for c in _cars:
			if c != _player_car and is_instance_valid(c):
				var d := c.global_position.distance_to(_player_car.global_position)
				battle = maxf(battle, 1.0 - d / BATTLE_GAP)
		var pl = _race.get("player") if _race else null
		if pl and "position" in pl:
			var pos := int(pl.position)
			if _player_place > 0 and pos < _player_place and _race.get("state") != 0:
				_overtake_t = 3.0
				overtook = true
			_player_place = pos
	_overtake_t = maxf(_overtake_t - CHECK_EVERY, 0.0)
	for s in _spots:
		if not s.live:
			continue
		for c in _cars:
			if not is_instance_valid(c) or absf(c.speed) < 12.0:
				continue
			var d2 := s.pos.distance_squared_to(c.global_position)
			if d2 > r2:
				continue
			var near := 1.0 - sqrt(d2) / CHEER_RADIUS
			var fast := clampf(absf(c.speed) / 50.0, 0.4, 1.0)
			if c == _player_car:
				var hype := maxf(battle, 1.0 if _overtake_t > 0.0 else 0.0)
				if overtook and d2 < r2 * 2.5:
					# Passed someone in front of these people: they erupt.
					s.player_cool = 4.0
					s.cool = 3.0
					_cheer(s, 1.0, true)
					_stats.overtakes += 1
				elif s.player_cool <= 0.0:
					s.player_cool = 6.0 - 2.0 * hype
					s.cool = 3.0
					var strength := (0.75 + 0.25 * near) * fast
					_cheer(s, minf(strength + 0.45 * hype, 1.0), hype > 0.6 and near > 0.3)
			elif s.cool <= 0.0:
				s.cool = randf_range(2.5, 4.5)
				if randf() < 0.75:
					_cheer(s, (0.35 + 0.25 * near) * fast)


func _cheer(s: Spot, strength: float, roar := false) -> void:
	s.excite = maxf(s.excite, clampf(strength, 0.0, 1.0))
	if not s.live:
		return
	# Don't cut off a louder cheer that is still building.
	if s.cheer.playing and s.cheer.get_playback_position() < 1.2 and not roar:
		return
	s.cheer.stream = _cache.roar if roar else (_cache.cheer_a if randf() < 0.5 else _cache.cheer_b)
	s.cheer.pitch_scale = randf_range(0.94, 1.06)
	s.cheer.volume_db = s.base_db + 3.0 + linear_to_db(maxf(strength, 0.05))
	s.cheer.play()
	_stats.cheers += 1


func _roar() -> void:
	if _clock - _last_roar < 4.0:
		return
	_last_roar = _clock
	_stats.roars += 1
	for s in _stands:
		_cheer(s, 1.0, true)
	for s in _spots:
		if not s.big and s.live:
			_pending.append([randf_range(0.1, 0.6), s, 0.8, false])


func _on_lights(count: int) -> void:
	if count < 0:
		_roar()
	elif count > 0:
		for s in _stands:
			s.excite = maxf(s.excite, count / 5.0 * 0.6) # anticipation builds


func _on_lap(entry, _time: float) -> void:
	if not _race or entry == null:
		return
	var laps := int(_race.get("laps")) if _race.get("laps") != null else 0
	if laps <= 0 or int(entry.lap) < laps:
		return
	_finishers += 1
	if _finishers == 1 or entry == _race.get("player"):
		_roar()
	else:
		for s in _stands:
			_cheer(s, 0.7)


func _on_finished() -> void:
	_roar()
	if _debug:
		print("ambience: %s" % _stats)


func _nature(dt: float, cp: Vector3) -> void:
	for k in _birds.size():
		_bird_wait[k] -= dt
		if _bird_wait[k] > 0.0:
			continue
		_bird_wait[k] = randf_range(3.0, 12.0)
		var b := _birds[k]
		if b.playing or cp.distance_to(b.global_position) > 105.0:
			continue
		b.stream = _cache["bird%d" % (randi() % 4)]
		b.pitch_scale = randf_range(0.93, 1.08)
		b.play()
		_stats.birds += 1
	if _distant:
		_distant_wait -= dt
		if _distant_wait <= 0.0:
			_distant_wait = randf_range(16.0, 40.0)
			var crow := randf() < 0.6 and not night
			var ang := randf() * TAU
			var d := randf_range(60.0, 110.0) if crow else randf_range(25.0, 55.0)
			var p := cp + Vector3(cos(ang), 0.0, sin(ang)) * d
			p.y = _ground(p) + (12.0 if crow else 5.0)
			_distant.global_position = p
			_distant.stream = _cache.owl if night and cond == Cond.CLEAR else (_cache.crow if crow else _cache.creak)
			_distant.pitch_scale = randf_range(0.92, 1.08)
			_distant.volume_db = -9.0 if crow else -13.0
			_distant.play()
			_stats.distant += 1


# ---------------------------------------------------------------- synthesis

## Builds (once) every sound this weather needs. Thread-safe to call from a
## worker as long as nothing reads the cache meanwhile. Returns the ms spent.
static func synthesise(k: Cond, is_night := false) -> float:
	var t0 := Time.get_ticks_usec()
	if not _cache.has("murmur"):
		var t1 := Time.get_ticks_usec()
		var m := _murmurs(3.6, 4, 11)
		_cache.murmur = m[0]
		_cache.murmur_big = m[1]
		timings.murmur = (Time.get_ticks_usec() - t1) / 1000.0
	_make("cheer_a", func(): return _cheer_sound(3.4, 7, 31))
	_make("cheer_b", func(): return _cheer_sound(3.0, 6, 47))
	_make("roar", func(): return _roar_sound())
	_make("pa_a", func(): return _pa_sound(5.5, 5))
	_make("pa_b", func(): return _pa_sound(4.5, 9))
	match k:
		Cond.CLEAR when is_night:
			_make("crickets", func(): return _crickets())
			_make("owl", func(): return _owl())
		Cond.CLEAR:
			for b in 4:
				_make("bird%d" % b, func(): return _bird_song(b))
			_make("leaves", func(): return _leaves())
		Cond.STORM:
			_make("gusts", func(): return _gusts())
			_make("roof_rain", func(): return _roof_rain())
		Cond.SNOW:
			_make("crow", func(): return _crow())
			_make("creak", func(): return _creak())
	synth_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return synth_ms


static func _make(key: String, f: Callable) -> void:
	if not _cache.has(key):
		var t0 := Time.get_ticks_usec()
		_cache[key] = f.call()
		timings[key] = (Time.get_ticks_usec() - t0) / 1000.0


## Read access for tests and tools.
static func cached() -> Dictionary:
	return _cache


static func _wav(buf: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var w := CarAudio._to_wav(buf, loop)
	w.mix_rate = rate
	return w


static func _zeros(n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	b.fill(0.0)
	return b


static func _noise(n: int, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n)
	for j in n:
		b[j] = rng.randf_range(-1.0, 1.0)
	return b


## Equal-power crossfade of the tail (raw[n..]) into the head: a seamless loop of n.
static func _seam(raw: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var fade := raw.size() - n
	var buf := raw.slice(0, n)
	for j in fade:
		var w := float(j) / fade * PI * 0.5
		buf[j] = raw[j] * sin(w) + raw[n + j] * cos(w)
	return buf


static func _lp(buf: PackedFloat32Array, cutoff: float, rate: int) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	for j in buf.size():
		y += a * (buf[j] - y)
		buf[j] = y
	return buf


static func _hp(buf: PackedFloat32Array, cutoff: float, rate: int) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var y := 0.0
	for j in buf.size():
		y += a * (buf[j] - y)
		buf[j] -= y
	return buf


## RBJ band-pass (0 dB peak).
static func _bp(buf: PackedFloat32Array, centre: float, q: float, rate: int) -> PackedFloat32Array:
	var w := TAU * centre / rate
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for j in buf.size():
		var x := buf[j]
		var y := b0 * (x - x2) - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[j] = y
	return buf


## Adds `echoes` feedback-free delayed copies ([seconds, gain] pairs).
static func _echo(buf: PackedFloat32Array, rate: int, taps: Array) -> PackedFloat32Array:
	var out := buf.duplicate()
	for tap in taps:
		var d := int(tap[0] * rate)
		var g: float = tap[1]
		for j in range(d, buf.size()):
			out[j] += buf[j - d] * g
	return out


## Babbling voice: sawtooth glottal pulses plus breath through two vowel
## formants that glide from syllable to syllable. `syll` is the mean syllable
## length, `pause` the chance a syllable is silent, `fk` scales the formants
## (1.15 ~ a woman's voice).
static func _voice(out: PackedFloat32Array, gain: float, rate: int, f0: float, rng: RandomNumberGenerator,
		syll: float, pause: float, fk: float, breath := 0.3) -> void:
	var n := out.size()
	var j := 0
	var phase := rng.randf()
	var f1 := 500.0 * fk
	var f2 := 1500.0 * fk
	var r1 := exp(-PI * 90.0 / rate)
	var r2 := exp(-PI * 130.0 / rate)
	var a1a := 0.0
	var a1b := 0.0
	var ya1 := 0.0
	var ya2 := 0.0
	var yb1 := 0.0
	var yb2 := 0.0
	var ga := 1.0 - r1
	var gb := 1.0 - r2
	while j < n:
		var seg := int(rng.randf_range(0.55, 1.5) * syll * rate)
		var amp := 0.0 if rng.randf() < pause else rng.randf_range(0.45, 1.0) * gain
		var v: Vector2 = VOWELS[rng.randi() % VOWELS.size()] * fk
		var p0 := f0 * rng.randf_range(0.88, 1.18)
		var p1 := p0 * rng.randf_range(0.85, 1.08)
		var k := 0
		while k < seg and j < n:
			if k % 32 == 0:
				f1 += (v.x - f1) * 0.3
				f2 += (v.y - f2) * 0.3
				a1a = 2.0 * r1 * cos(TAU * f1 / rate)
				a1b = 2.0 * r2 * cos(TAU * f2 / rate)
			var u := float(k) / seg
			phase += lerpf(p0, p1, u) / rate
			if phase >= 1.0:
				phase -= 1.0
			var e := sin(PI * u) * amp
			var src := ((1.0 - 2.0 * phase) + rng.randf_range(-breath, breath)) * e
			var ya := ga * src + a1a * ya1 - r1 * r1 * ya2
			ya2 = ya1
			ya1 = ya
			var yb := gb * src + a1b * yb1 - r2 * r2 * yb2
			yb2 = yb1
			yb1 = yb
			out[j] += ya + 0.7 * yb
			k += 1
			j += 1


## Crowd murmur loops (normal and grandstand) from one bed of a few babbling
## voices over a soft noise wash, folded onto itself at fractions of the loop
## to sound like many more people, with slow swells.
static func _murmurs(dur: float, voices: int, seed: int) -> Array[AudioStreamWAV]:
	var rate := LO
	var n := int(dur * rate)
	var raw := _zeros(n + int(0.3 * rate))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for v in voices:
		var female := v % 3 == 2
		var f0 := rng.randf_range(185.0, 235.0) if female else rng.randf_range(95.0, 140.0)
		_voice(raw, rng.randf_range(0.5, 1.0), rate, f0, rng, 0.16, 0.3, 1.15 if female else 1.0)
	var wash := _bp(_noise(raw.size(), rng), 520.0, 0.6, rate)
	for j in raw.size():
		raw[j] += wash[j] * 0.6
	var one := _seam(_lp(raw, 2600.0, rate), n)
	# Doubled loop so the folded reads need no wrap-around.
	var two := one.duplicate()
	two.append_array(one)
	var a := n / 3
	var b := (n * 2) / 3
	var c := n / 2 + 1234
	var d := n / 6 + 777
	var e := (n * 5) / 6 - 555
	var small := _zeros(n)
	var big := _zeros(n)
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var q1 := rng.randf() * TAU
	for j in n:
		var t := TAU * j / n
		var x := two[j] + 0.8 * two[j + a] + 0.65 * two[j + b]
		small[j] = x * (1.0 + 0.16 * sin(t + p1) + 0.08 * sin(3.0 * t + p2))
		big[j] = (x + 0.6 * two[j + c] + 0.5 * two[j + d] + 0.45 * two[j + e]) * (1.0 + 0.14 * sin(t + q1))
	return [_wav(CarAudio._normalise(small, 0.75), rate, true), _wav(CarAudio._normalise(big, 0.75), rate, true)]


## Crowd cheer one-shot: swells in over ~0.4 s, holds, and dies away.
## Breathy "aah" roar, shouting voices, a whistle or two and clapping.
static func _cheer_sound(dur: float, shouts: int, seed: int) -> AudioStreamWAV:
	var rate := LO
	var n := int(dur * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var att := 0.45
	var hold := dur * 0.36
	var env := PackedFloat32Array()
	env.resize(n)
	for j in n:
		var t := float(j) / rate
		var a := smoothstep(0.0, att, t)
		env[j] = a if t < hold else a * exp(-(t - hold) / (dur * 0.26))
	# "Aah": two formant bands of noise.
	var nz := _noise(n, rng)
	var lo := _bp(nz.duplicate(), 780.0, 0.8, rate)
	var hi := _bp(nz, 1850.0, 1.4, rate)
	var buf := _zeros(n)
	for j in n:
		buf[j] = (lo[j] + 0.55 * hi[j]) * env[j]
	# Shouts: short raised voices with a rising-then-falling pitch.
	var shout_vowels: Array[Vector2] = [Vector2(800, 1250), Vector2(620, 1800), Vector2(560, 950), Vector2(700, 1650)]
	for s in shouts:
		var st := int(rng.randf_range(0.05, dur * 0.4) * rate)
		var ln := mini(int(rng.randf_range(0.45, 1.3) * rate), n - st)
		var v: Vector2 = shout_vowels[rng.randi() % shout_vowels.size()] * rng.randf_range(0.95, 1.12)
		var f0 := rng.randf_range(170.0, 330.0)
		var r1 := exp(-PI * 160.0 / rate)
		var r2 := exp(-PI * 220.0 / rate)
		var c1 := 2.0 * r1 * cos(TAU * v.x / rate)
		var c2 := 2.0 * r2 * cos(TAU * v.y / rate)
		var ya1 := 0.0
		var ya2 := 0.0
		var yb1 := 0.0
		var yb2 := 0.0
		var ph := 0.0
		var g := rng.randf_range(0.8, 1.6)
		for k in ln:
			var u := float(k) / ln
			ph += f0 * (1.0 + 0.25 * sin(PI * u)) / rate
			ph -= floorf(ph)
			var e := minf(u * 8.0, 1.0) * (1.0 - u) * g
			var src := ((1.0 - 2.0 * ph) + rng.randf_range(-0.5, 0.5)) * e
			var ya := (1.0 - r1) * src + c1 * ya1 - r1 * r1 * ya2
			ya2 = ya1
			ya1 = ya
			var yb := (1.0 - r2) * src + c2 * yb1 - r2 * r2 * yb2
			yb2 = yb1
			yb1 = yb
			buf[st + k] += (ya + 0.6 * yb) * 3.0
	# Two-finger whistles.
	for w in rng.randi_range(1, 2):
		var st := int(rng.randf_range(0.2, dur * 0.45) * rate)
		var ln := mini(int(rng.randf_range(0.35, 0.7) * rate), n - st)
		var f := rng.randf_range(2300.0, 3100.0)
		var ph := 0.0
		for k in ln:
			var u := float(k) / ln
			ph += f * (1.0 + 0.12 * u - 0.2 * u * u + 0.006 * sin(TAU * 6.0 * k / rate)) / rate
			buf[st + k] += sin(TAU * ph) * sin(PI * u) * 0.09
	# Clapping: short bright noise bursts, densest at the peak.
	var j := int(0.3 * rate)
	while j < n - 80:
		var burst := rng.randf_range(0.2, 0.5) * env[j]
		for k in 60:
			buf[j + k] += rng.randf_range(-1.0, 1.0) * burst * exp(-k / 14.0)
		j += int(rate / (25.0 + 45.0 * env[j]) * rng.randf_range(0.4, 1.6))
	return _wav(CarAudio._normalise(_lp(buf, 5200.0, rate), 0.85), rate, false)


## Lights-out / finish roar: both cheers stacked and staggered so it holds longer.
static func _roar_sound() -> AudioStreamWAV:
	var a := _pcm(_cache.cheer_a)
	var b := _pcm(_cache.cheer_b)
	var rate := LO
	var n := int(5.2 * rate)
	var buf := _zeros(n)
	var offs := [[a, 0, 1.0], [b, int(0.35 * rate), 0.9], [a, int(1.3 * rate), 0.75], [b, int(2.1 * rate), 0.6]]
	for o in offs:
		var src: PackedFloat32Array = o[0]
		var st: int = o[1]
		var g: float = o[2]
		for k in mini(src.size(), n - st):
			buf[st + k] += src[k] * g
	# Fade the tail so nothing is cut off.
	var tail := int(0.8 * rate)
	for k in tail:
		buf[n - tail + k] *= 1.0 - float(k) / tail
	return _wav(CarAudio._normalise(buf, 0.9), rate, false)


static func _pcm(w: AudioStreamWAV) -> PackedFloat32Array:
	var d := w.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for j in out.size():
		out[j] = d.decode_s16(j * 2) / 32767.0
	return out


## PA announcer: phrases of speech-like babble through a tannoy horn (narrow
## band, overdriven), echoing off the other speakers down the straight.
static func _pa_sound(dur: float, seed: int) -> AudioStreamWAV:
	var rate := LO
	var n := int(dur * rate)
	var speech := int((dur - 1.1) * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := _zeros(speech)
	_voice(v, 1.0, rate, rng.randf_range(105.0, 125.0), rng, 0.15, 0.08, 1.0, 0.15)
	# Words grouped into phrases with breaths between.
	var gate := 0.0
	var j := 0
	while j < speech:
		var talk := int(rng.randf_range(0.7, 1.8) * rate)
		var rest := int(rng.randf_range(0.25, 0.6) * rate)
		for k in talk + rest:
			if j >= speech:
				break
			var want := 1.0 if k < talk else 0.0
			gate += (want - gate) * 0.004
			v[j] *= gate * (1.0 - 0.25 * float(k) / talk if k < talk else 1.0)
			j += 1
	var buf := _zeros(n)
	for k in speech:
		buf[k] = v[k]
	buf = _hp(_hp(buf, 420.0, rate), 420.0, rate)
	var peak := _bp(buf.duplicate(), 1700.0, 1.1, rate)
	for k in n:
		buf[k] = tanh((buf[k] * 0.4 + peak[k]) * 6.0)
	buf = _lp(_lp(buf, 3600.0, rate), 3600.0, rate)
	buf = _echo(buf, rate, [[0.19, 0.4], [0.41, 0.24], [0.66, 0.12]])
	return _wav(CarAudio._normalise(buf, 0.8), rate, false)


## Birdsong, four species-like patterns: 0 finch-like descending trill with a
## flourish, 1 fluty blackbird-like warble, 2 two-note "tea-cher" call,
## 3 irregular twittering.
static func _bird_song(kind: int) -> AudioStreamWAV:
	var rate := HI
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + kind
	var buf := _zeros(int(2.0 * rate))
	var t := 0.05
	match kind:
		0:
			var notes := rng.randi_range(8, 11)
			var gap := 0.085
			for k in notes:
				var f := lerpf(5200.0, 3600.0, float(k) / notes)
				_chirp(buf, t, 0.035, f * 1.08, f * 0.9, 0.6, rate, 0.0, 0.0)
				t += gap
				gap *= 0.95
			_chirp(buf, t + 0.03, 0.09, 4700.0, 2300.0, 0.9, rate, 0.0, 0.0)
			_chirp(buf, t + 0.14, 0.12, 4300.0, 2000.0, 0.8, rate, 0.0, 0.0)
		1:
			for k in rng.randi_range(4, 6):
				var f := rng.randf_range(1700.0, 2800.0)
				var d := rng.randf_range(0.12, 0.24)
				_chirp(buf, t, d, f, f * rng.randf_range(0.8, 1.25), rng.randf_range(0.6, 1.0), rate, 22.0, 0.025)
				t += d + rng.randf_range(0.03, 0.09)
			for k in 3:
				_chirp(buf, t, 0.03, 6200.0, 5200.0, 0.2, rate, 0.0, 0.0)
				t += 0.045
		2:
			for k in rng.randi_range(2, 4):
				_chirp(buf, t, 0.09, 5300.0, 5000.0, 0.8, rate, 0.0, 0.0)
				_chirp(buf, t + 0.13, 0.11, 3700.0, 3350.0, 0.9, rate, 0.0, 0.0)
				t += 0.36
		_:
			for k in rng.randi_range(6, 10):
				var f := rng.randf_range(2600.0, 6500.0)
				var d := rng.randf_range(0.03, 0.08)
				var up := rng.randf() < 0.5
				_chirp(buf, t, d, f * (0.75 if up else 1.25), f, rng.randf_range(0.4, 1.0), rate, 0.0, 0.0)
				t += d + rng.randf_range(0.02, 0.16)
	var n := mini(int((t + 0.35) * rate), buf.size())
	buf = _echo(buf.slice(0, n), rate, [[0.07, 0.18], [0.13, 0.1]])
	return _wav(CarAudio._normalise(buf, 0.7), rate, false)


## One bird note: a pitch sweep with a soft envelope and a faint harmonic.
static func _chirp(buf: PackedFloat32Array, start: float, dur: float, f_from: float, f_to: float,
		amp: float, rate: int, vib_hz: float, vib: float) -> void:
	var s := int(start * rate)
	var ln := mini(int(dur * rate), buf.size() - s)
	var ph := 0.0
	for k in ln:
		var u := float(k) / ln
		var f := lerpf(f_from, f_to, u * u * (3.0 - 2.0 * u)) * (1.0 + vib * sin(TAU * vib_hz * k / rate))
		ph += f / rate
		var e := sin(PI * u)
		buf[s + k] += amp * e * e * (sin(TAU * ph) + 0.12 * sin(TAU * 2.0 * ph))


## Gentle breeze through leaves: band-limited noise with slow gusts and a
## faster flutter.
static func _leaves() -> AudioStreamWAV:
	var rate := LO
	var dur := 6.0
	var n := int(dur * rate)
	var m := n + int(0.4 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61
	var hiss := _lp(_hp(_noise(m, rng), 350.0, rate), 2200.0, rate)
	var air := _lp(_noise(m, rng), 140.0, rate)
	var flutter := 0.0
	var fa := 1.0 - exp(-TAU * 5.0 / rate)
	for j in m:
		flutter += fa * (rng.randf_range(-1.0, 1.0) - flutter)
		hiss[j] = hiss[j] * (1.0 + 6.0 * flutter) + air[j] * 2.5
	var buf := _seam(hiss, n)
	var p := rng.randf() * TAU
	for j in n:
		var t := float(j) / n
		buf[j] *= 0.6 + 0.25 * sin(TAU * t + p) + 0.15 * sin(TAU * 3.0 * t + p * 2.0)
	return _wav(CarAudio._normalise(buf, 0.7), rate, true)


## Storm wind: low roar plus trees hissing, both following strong gusts.
static func _gusts() -> AudioStreamWAV:
	var rate := LO
	var dur := 8.0
	var n := int(dur * rate)
	var m := n + int(0.5 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var roar := _lp(_lp(_noise(m, rng), 320.0, rate), 320.0, rate)
	var hiss := _bp(_noise(m, rng), 2300.0, 0.6, rate)
	var roar_s := _seam(roar, n)
	var hiss_s := _seam(hiss, n)
	var buf := _zeros(n)
	var p := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	for j in n:
		var t := float(j) / n
		var g := 0.5 + 0.28 * sin(TAU * t + p[0]) + 0.16 * sin(TAU * 2.0 * t + p[1]) + 0.1 * sin(TAU * 5.0 * t + p[2])
		g = clampf(g, 0.05, 1.0)
		buf[j] = roar_s[j] * 4.0 * (0.45 + 0.55 * g) + hiss_s[j] * g * g * 1.6
	return _wav(CarAudio._normalise(buf, 0.75), rate, true)


## Heavy rain on a steel roof: dense drops ringing two panel modes, over a hiss.
static func _roof_rain() -> AudioStreamWAV:
	var rate := MID
	var dur := 3.0
	var n := int(dur * rate)
	var m := n + int(0.25 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 89
	var drops := _zeros(m)
	for j in m:
		if rng.randf() < 0.06: # ~1000 drops a second
			var a := rng.randf()
			drops[j] = a * a * (1.0 if rng.randf() < 0.5 else -1.0)
	var ping := _bp(drops.duplicate(), 2900.0, 4.0, rate)
	var tap := _bp(drops.duplicate(), 1150.0, 2.5, rate)
	var body := _lp(drops, 380.0, rate)
	var hiss := _hp(_noise(m, rng), 4000.0, rate)
	for j in m:
		drops[j] = ping[j] * 1.2 + tap[j] * 1.4 + body[j] * 2.0 + hiss[j] * 0.06
	return _wav(CarAudio._normalise(_seam(drops, n), 0.75), rate, true)


## Distant carrion crow: two or three hoarse caws echoing across the snow.
## Summer night: a field of crickets, each chirping in short pulse trains at
## its own rate and pitch, with a faint air bed under them. Loops seamlessly.
static func _crickets() -> AudioStreamWAV:
	var rate := HI
	var dur := 5.0
	var n := int(dur * rate)
	var m := n + int(0.3 * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var buf := _lp(_noise(m, rng), 180.0, rate)
	for j in m:
		buf[j] *= 0.35
	for c in 9:
		var f := rng.randf_range(3900.0, 5200.0)
		var period := rng.randf_range(0.45, 0.9) # seconds between chirps
		var pulses := rng.randi_range(2, 4)
		var gain := rng.randf_range(0.08, 0.3) * (1.0 if c < 3 else 0.5) # a few close, most far
		var t := rng.randf() * period
		while t < float(m) / rate:
			for k in pulses:
				var s := int((t + k * 0.028) * rate)
				var ln := int(0.017 * rate)
				for j in ln:
					if s + j >= m:
						break
					var u := float(j) / ln
					buf[s + j] += sin(TAU * f * j / rate) * sin(PI * u) * gain
			t += period * rng.randf_range(0.9, 1.1)
	return _wav(CarAudio._normalise(_seam(buf, n), 0.5), rate, true)


## Tawny owl: a soft "hoo ... hoo-hoo-hooo" with a little room echo.
static func _owl() -> AudioStreamWAV:
	var rate := MID
	var buf := _zeros(int(3.2 * rate))
	var notes := [[0.05, 0.42, 1.0], [0.95, 0.14, 0.7], [1.15, 0.16, 0.75], [1.36, 0.7, 0.9]]
	for note: Array in notes:
		var s := int(float(note[0]) * rate)
		var ln := int(float(note[1]) * rate)
		var ph := 0.0
		for j in ln:
			var u := float(j) / ln
			var f := 400.0 * (1.0 + 0.06 * sin(PI * u) - 0.05 * u)
			ph += f / rate
			var e := minf(u * 8.0, 1.0) * pow(1.0 - u, 1.5)
			buf[s + j] += (sin(TAU * ph) + 0.18 * sin(TAU * ph * 2.0)) * e * float(note[2])
	buf = _echo(buf, rate, [[0.19, 0.25], [0.41, 0.12]])
	return _wav(CarAudio._normalise(buf, 0.8), rate, false)


static func _crow() -> AudioStreamWAV:
	var rate := MID
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	var buf := _zeros(int(2.4 * rate))
	var t := 0.05
	var r1 := exp(-PI * 320.0 / rate)
	var r2 := exp(-PI * 450.0 / rate)
	for c in rng.randi_range(2, 3):
		var s := int(t * rate)
		var ln := int(rng.randf_range(0.26, 0.36) * rate)
		var f0 := rng.randf_range(300.0, 360.0)
		var c1 := 2.0 * r1 * cos(TAU * 1150.0 / rate)
		var c2 := 2.0 * r2 * cos(TAU * 1900.0 / rate)
		var y1 := 0.0
		var y2 := 0.0
		var z1 := 0.0
		var z2 := 0.0
		var ph := 0.0
		for k in ln:
			var u := float(k) / ln
			ph += f0 * (1.0 - 0.18 * u) * (1.0 + rng.randf_range(-0.08, 0.08)) / rate
			ph -= floorf(ph)
			var e := minf(u * 12.0, 1.0) * (1.0 - u) * (1.0 - u)
			var src := ((1.0 - 2.0 * ph) + rng.randf_range(-0.9, 0.9)) * e
			var y := (1.0 - r1) * src + c1 * y1 - r1 * r1 * y2
			y2 = y1
			y1 = y
			var z := (1.0 - r2) * src + c2 * z1 - r2 * r2 * z2
			z2 = z1
			z1 = z
			buf[s + k] += tanh((y + 0.8 * z) * 4.0)
		t += ln / float(rate) + rng.randf_range(0.2, 0.32)
	var n := mini(int((t + 0.7) * rate), buf.size())
	buf = _echo(buf.slice(0, n), rate, [[0.34, 0.22], [0.62, 0.1]])
	return _wav(CarAudio._normalise(_lp(buf, 3000.0, rate), 0.7), rate, false)


## Snow-laden branch creaking: stick-slip pulses, slowing and speeding,
## ringing a few wooden modes.
static func _creak() -> AudioStreamWAV:
	var rate := MID
	var dur := 1.4
	var n := int(dur * rate)
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var exc := _zeros(n)
	var t := 0.05
	while t < dur - 0.25:
		var u := t / dur
		var hz := 18.0 + 40.0 * sin(PI * u) # slow, faster, slow
		exc[int(t * rate)] = sin(PI * u) * rng.randf_range(0.6, 1.0)
		t += 1.0 / hz * rng.randf_range(0.8, 1.2)
	var modes := [[380.0, 7.0, 1.0], [1120.0, 9.0, 0.6], [2450.0, 10.0, 0.3]]
	var buf := _zeros(n)
	for md in modes:
		var r := _bp(exc.duplicate(), md[0], md[1], rate)
		for j in n:
			buf[j] += r[j] * md[2]
	return _wav(CarAudio._normalise(buf, 0.6), rate, false)
