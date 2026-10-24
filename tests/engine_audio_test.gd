extends Node
## Headless check of every car's synthesised engine: synthesis time, level,
## clipping, NaN, loop-seam continuity, and a spectral sanity check that the
## strongest line at or below the firing frequency IS the firing frequency
## (cylinders / 2 per crank turn for a four-stroke, rotors per turn for a
## rotary). Also exercises the background (WorkerThreadPool) path and can dump
## every loop plus a rendered rev sweep per engine as .wav:
##   godot --headless --path . res://tests/engine_audio_test.tscn -- --dump=<dir>

const MAX_MS := 400.0

var _bad := 0


func _ready() -> void:
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump = a.substr(7)
	if dump != "":
		DirAccess.make_dir_recursive_absolute(dump)
	var t := Time.get_ticks_usec()
	CarAudio.warm_up()
	print("shared bank %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))

	var seen := {}
	for id in CarCatalog.ids():
		var s := CarAudio.engine_spec(id)
		if seen.has(s.type):
			continue
		seen[s.type] = true
		# Best of three: other processes on the machine skew a single timing.
		var bank := CarAudio.synth_engine(s)
		for i in 2:
			bank.ms = minf(bank.ms, CarAudio.synth_engine(s).ms)
		_check_engine(id, s, bank, dump)

	# Background path: request, poll like CarAudio._process does, get the bank.
	var id0: String = CarCatalog.ids()[-1]
	CarAudio._banks.clear()
	CarAudio.request_engine(id0)
	var waited := 0
	while CarAudio.engine_bank(id0).is_empty() and waited < 3000:
		OS.delay_msec(5)
		waited += 5
	var ok_async := not CarAudio.engine_bank(id0).is_empty()
	_expect(ok_async, "async synthesis of %s ready after ~%d ms" % [id0, waited])

	_start_runtime()


# ---------------------------------------------------------------- runtime

var _car: Car
var _audio: CarAudio
var _t := 0.0
var _saw := {}


## Drive a remote (script-controlled) car's public fields through a rev to the
## limiter and a lift, and watch CarAudio react.
func _start_runtime() -> void:
	_car = Car.new()
	_car.model_id = "mazda_rx7_fc"
	_car.remote = true
	_car.freeze = true
	add_child(_car)
	for c in _car.get_children():
		if c is CarAudio:
			_audio = c
	_expect(_audio != null, "car has a CarAudio")


func _process(dt: float) -> void:
	if not _car:
		return
	_t += dt
	var red := _car.redline_rpm
	_car.gear = 3
	if _t < 1.5:
		_car.rpm = lerpf(_car.idle_rpm, red, _t / 1.5)
		_car.throttle = 1.0
	elif _t < 2.5:
		_car.rpm = red
		_car.throttle = 1.0
	elif _t < 4.0:
		_car.rpm = lerpf(red * 0.95, red * 0.6, (_t - 2.5) / 1.5)
		_car.throttle = 0.0
	else:
		_finish_runtime()
		return
	if _audio._bank.is_empty():
		return
	_saw.attached = true
	if _t > 1.6 and _t < 2.5 and _audio._lim_phase > 0.0:
		_saw.limiter = true
	for p in _audio._pop_players:
		if p.playing:
			_saw.pops = int(_saw.get("pops", 0)) + 1
	if _audio._oneshot.playing and _audio._oneshot.stream == _audio._bank.get("blowoff"):
		_saw.blowoff = true
	var paused := 0
	for p in _audio._on + _audio._off:
		paused += int(p.stream_paused)
	_saw.max_paused = maxi(int(_saw.get("max_paused", 0)), paused)
	if _audio._whistle.volume_db > -20.0:
		_saw.boost = true


func _finish_runtime() -> void:
	_car = null
	print("\n== runtime (remote RX-7 driven by script): %s" % _saw)
	_expect(_saw.has("attached"), "engine bank attached to the car")
	_expect(_saw.has("limiter"), "limiter stutter engaged at redline")
	_expect(_saw.has("pops"), "overrun pops fired on lift")
	_expect(_saw.has("blowoff"), "blow-off on lift")
	_expect(_saw.has("boost"), "turbo whistle audible under boost")
	_expect(int(_saw.get("max_paused", 0)) >= 4, "inaudible engine loops paused")
	print("ENGINE AUDIO TEST %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	get_tree().quit(1 if _bad else 0)


func _check_engine(id: String, s: Dictionary, bank: Dictionary, dump: String) -> void:
	print("\n== %s (%s)  %s%s  synth %.0f ms" % [s.type, id,
		("%d-rotor rotary" % s.cylinders) if s.rotary else ("%d-cyl" % s.cylinders),
		" turbo" if s.turbo else "", bank.ms])
	# Wall-clock, so only a warning: a busy machine can blow any budget.
	print("  %s: synthesis %.0f ms (budget %.0f ms, on a worker thread)" % ["ok" if bank.ms < MAX_MS else "WARN", bank.ms, MAX_MS])
	_expect(bank.nans == 0, "no NaN (%d)" % bank.nans)
	var per_rev: float = float(s.cylinders) if s.rotary else s.cylinders / 2.0
	for k in bank.rpms.size():
		var rpm: float = bank.rpms[k]
		var expect_hz := rpm / 60.0 * per_rev
		for which in ["on", "off"]:
			var w: AudioStreamWAV = bank[which][k]
			var pcm := _pcm(w)
			var line := "%s %5.0f rpm " % [which, rpm] + _level(pcm, true)
			if which == "on":
				line += "  " + _spectrum(pcm, bank.fire_hz[k], expect_hz, per_rev)
			print(line)
			if dump != "":
				w.save_to_wav(dump.path_join("%s_%s_%04d.wav" % [s.type, which, int(rpm)]))
	var extras := {}
	for key in ["whistle", "blowoff"]:
		if bank.has(key):
			extras[key] = bank[key]
	for i in bank.pops.size():
		extras["pop%d" % i] = bank.pops[i]
	for key in extras:
		var w: AudioStreamWAV = extras[key]
		print("%-8s %s" % [key, _level(_pcm(w), w.loop_mode != AudioStreamWAV.LOOP_DISABLED)])
		if dump != "":
			w.save_to_wav(dump.path_join("%s_%s.wav" % [s.type, key]))
	if dump != "":
		_render_sweep(s, bank).save_to_wav(dump.path_join("%s_SWEEP.wav" % s.type))


## Level / clipping / seam; flags BAD.
func _level(pcm: PackedFloat32Array, looped: bool) -> String:
	var sum := 0.0
	var peak := 0.0
	var diff := 0.0
	var max_step := 0.0
	var clipped := 0
	for j in pcm.size():
		var v := pcm[j]
		sum += v * v
		peak = maxf(peak, absf(v))
		if absf(v) > 0.999:
			clipped += 1
		if j > 0:
			diff += absf(v - pcm[j - 1])
			max_step = maxf(max_step, absf(v - pcm[j - 1]))
	var rms := sqrt(sum / pcm.size())
	diff /= pcm.size()
	var seam := absf(pcm[0] - pcm[pcm.size() - 1]) if looped else 0.0
	var ok := rms > 0.05 and peak > 0.3 and clipped < pcm.size() / 1000 and (not looped or (seam < diff * 6.0 + 0.02 and seam <= max_step))
	_expect(ok, "")
	return "%.2fs rms %.3f peak %.2f clip %d %s%s" % [pcm.size() / float(CarAudio.RATE), rms, peak, clipped,
		("seam %.4f/step %.4f " % [seam, diff]) if looped else "", "ok" if ok else "BAD"]


## The loop is a whole number of cycles, so DFT bins at multiples of the
## loop's base frequency are exact. The firing frequency must be the strongest
## line in 0.3..1.45 x itself (sub-orders from irregularity may exist, but
## must not dominate), and we report the strongest crank order up to 20.
func _spectrum(pcm: PackedFloat32Array, fire_hz: float, expect_hz: float, per_rev: float) -> String:
	var n := pcm.size()
	var dur := float(n) / CarAudio.RATE
	var fire_bin := int(round(fire_hz * dur))
	var best_bin := 0
	var best := 0.0
	for b in range(maxi(1, int(fire_bin * 0.3)), int(fire_bin * 1.45) + 1):
		var m := _dft(pcm, b)
		if m > best:
			best = m
			best_bin = b
	var found := best_bin / dur
	var ok := absf(found - expect_hz) < expect_hz * 0.03
	_expect(ok, "")
	# Order spectrum (half orders) for character: dominant order and centroid.
	var per_order := fire_hz / per_rev * dur # bins per crank order
	var top_o := 0.0
	var top_m := 0.0
	var wsum := 0.0
	var msum := 0.0
	var o := 0.5
	while o <= 20.0:
		var b := int(round(o * per_order))
		if b > 0 and b / dur < CarAudio.RATE * 0.45:
			var m := _dft(pcm, b)
			wsum += m * b / dur
			msum += m
			if m > top_m:
				top_m = m
				top_o = o
		o += 0.5
	return "fire %.1f Hz (expect %.1f) -> peak %.1f Hz %s | top order %.1f, centroid %.0f Hz" % [fire_hz, expect_hz,
		found, "ok" if ok else "BAD", top_o, wsum / maxf(msum, 1e-9)]


func _dft(pcm: PackedFloat32Array, b: int) -> float:
	var w := TAU * b / pcm.size()
	var cw := cos(w)
	var sw := sin(w)
	var re := 1.0
	var im := 0.0
	var sr := 0.0
	var si := 0.0
	for j in pcm.size():
		var v := pcm[j]
		sr += v * re
		si += v * im
		var nr := re * cw - im * sw
		im = re * sw + im * cw
		re = nr
	return sqrt(sr * sr + si * si) / pcm.size()


## Offline mix of the bank the way CarAudio does it: 4 s full-throttle rev
## from idle to redline, 0.6 s on the limiter, then a 2 s lift with pops.
func _render_sweep(s: Dictionary, bank: Dictionary) -> AudioStreamWAV:
	var rate := CarAudio.RATE
	var n := int(6.6 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var loops_on: Array[PackedFloat32Array] = []
	var loops_off: Array[PackedFloat32Array] = []
	for k in bank.rpms.size():
		loops_on.append(_pcm(bank.on[k]))
		loops_off.append(_pcm(bank.off[k]))
	var pos := PackedFloat64Array()
	pos.resize(bank.rpms.size())
	var idle: float = s.idle_rpm
	var red: float = s.redline_rpm
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var pops: Array = bank.pops
	var next_pop := 0.0
	var ld := 0.0
	var whistle := _pcm(bank.whistle) if bank.has("whistle") else PackedFloat32Array()
	var wpos := 0.0
	var boost := 0.0
	for j in n:
		var t := float(j) / rate
		var rpm: float
		var gas: float
		if t < 4.0:
			rpm = lerpf(idle, red, pow(t / 4.0, 0.8))
			gas = 1.0
		elif t < 4.6:
			rpm = red
			gas = 1.0
		else:
			rpm = lerpf(red, idle * 1.4, clampf((t - 4.6) / 2.0, 0.0, 1.0))
			gas = 0.0
		ld = lerpf(ld, gas, 1.0 - exp(-10.0 / rate))
		var cut := 0.3 if t >= 4.0 and t < 4.6 and fmod((t - 4.0) * float(s.limiter_hz), 1.0) < 0.45 else 1.0
		var v := 0.0
		for k in bank.rpms.size():
			var wgt := CarAudio._rpm_weight(rpm, k, bank.rpms)
			if wgt <= 0.0:
				continue
			var pitch := clampf(rpm / float(bank.rpms[k]), 0.5, 2.0)
			var a: PackedFloat32Array = loops_on[k]
			var b: PackedFloat32Array = loops_off[k]
			var i := int(pos[k]) % a.size()
			v += wgt * (a[i] * lerpf(0.25, 1.0, ld) * cut + b[i % b.size()] * (1.0 - ld) * 0.75)
			pos[k] += pitch
		if not whistle.is_empty():
			var tb := ld * clampf((rpm - float(s.spool_rpm)) / float(s.spool_span), 0.0, 1.0)
			boost = lerpf(boost, tb, 1.0 - exp(-(float(s.spool_rate) if tb > boost else 6.0) / rate))
			v += whistle[int(wpos) % whistle.size()] * boost * float(s.turbo_level)
			wpos += 0.55 + boost * 0.75
		out[j] = v * 0.6
	if bank.has("blowoff"):
		_add(out, _pcm(bank.blowoff), int(4.62 * rate), 0.5)
	if not pops.is_empty():
		next_pop = 4.62
		while next_pop < 6.3:
			var hot := clampf(((red - (red - idle * 1.4) * (next_pop - 4.6) / 2.0) / red - float(s.pop_min)) / (1.0 - float(s.pop_min)), 0.0, 1.0)
			if hot > 0.0:
				_add(out, _pcm(pops[rng.randi() % pops.size()]), int(next_pop * rate), 0.25 + 0.4 * hot)
			next_pop += 1.0 / maxf(float(s.backfire_rate) * 1.5, 0.5) * rng.randf_range(0.4, 1.6)
	return CarAudio._to_wav(CarAudio._normalise(out, 0.9), false)


func _add(out: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	for k in src.size():
		if at + k < out.size():
			out[at + k] += src[k] * gain


func _pcm(w: AudioStreamWAV) -> PackedFloat32Array:
	var d := w.data
	var out := PackedFloat32Array()
	out.resize(d.size() / 2)
	for j in out.size():
		out[j] = d.decode_s16(j * 2) / 32768.0
	return out


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
		if what != "":
			print("  FAIL: " + what)
	elif what != "":
		print("  ok: " + what)
