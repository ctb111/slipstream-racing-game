class_name UiSounds
extends RefCounted
## Menu sounds: soft mechanical switch clicks rather than beeps, synthesised
## once and cached like CarAudio. Nothing uses this yet; to hook up a menu:
##   UiSounds.wire(self)            # every Button under this node
##   UiSounds.play(self, "click")   # or by hand: "hover", "click", "back", "confirm"

const RATE := CarAudio.RATE
const POOL := 4

static var _cache := {}
static var _pool: Array[AudioStreamPlayer] = []
static var _next := 0
static var volume_db := -8.0


## Plays one of the sounds. `from` is any node in the tree (used to reach the root).
static func play(from: Node, kind: String, db := 0.0) -> void:
	if not from or not from.is_inside_tree():
		return
	_warm_up()
	if not _cache.has(kind):
		return
	var p := _player(from)
	p.stream = _cache[kind]
	p.volume_db = volume_db + db + (-10.0 if kind == "hover" else 0.0)
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()


## Connects hover / press sounds to every BaseButton under `root` (recursive).
static func wire(root: Node) -> void:
	for c in root.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.has_meta("ui_sounds"):
			continue
		b.set_meta("ui_sounds", true)
		b.mouse_entered.connect(func(): if not b.disabled: play(b, "hover"))
		b.focus_entered.connect(func(): if not b.disabled: play(b, "hover"))
		b.pressed.connect(func(): play(b, "back" if _is_back(b) else "click"))


static func _is_back(b: BaseButton) -> bool:
	var t := (b as Button).text.to_lower() if b is Button else ""
	return t.begins_with("back") or t.begins_with("cancel") or t.begins_with("quit")


static func _player(from: Node) -> AudioStreamPlayer:
	# Drop players freed with an old scene tree.
	_pool = _pool.filter(func(p): return is_instance_valid(p) and p.is_inside_tree())
	if _pool.size() < POOL:
		var p := AudioStreamPlayer.new()
		p.bus = &"Effects"
		p.name = "UiSound%d" % _pool.size()
		from.get_tree().root.add_child(p)
		_pool.append(p)
		return p
	_next = (_next + 1) % _pool.size()
	return _pool[_next]


static func _warm_up() -> void:
	if not _cache.is_empty():
		return
	_cache.hover = _tick(2600.0, 0.018, 0.25, 1)
	_cache.click = _switch(1900.0, 150.0, 1.0, 2)
	_cache.back = _switch(1300.0, 120.0, 0.9, 3)
	_cache.confirm = _confirm()


## A faint tick: a very short damped resonance.
static func _tick(hz: float, tau: float, noise: float, seed: int) -> AudioStreamWAV:
	var n := int(0.06 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buf := PackedFloat32Array()
	buf.resize(n)
	for j in n:
		var t := float(j) / RATE
		buf[j] = exp(-t / tau) * (sin(TAU * hz * t) + rng.randf_range(-noise, noise) * exp(-t / 0.002))
	return CarAudio._to_wav(CarAudio._normalise(buf, 0.6), false)


## Toggle-switch "clack": a bright contact click, then a low body thump a few
## milliseconds later as the lever seats.
static func _switch(hz: float, body_hz: float, amp: float, seed: int) -> AudioStreamWAV:
	return CarAudio._to_wav(CarAudio._normalise(_switch_pcm(hz, body_hz, seed), 0.7 * amp), false)


static func _switch_pcm(hz: float, body_hz: float, seed: int) -> PackedFloat32Array:
	var n := int(0.1 * RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lag := 0.007
	for j in n:
		var t := float(j) / RATE
		var click := exp(-t / 0.004) * (sin(TAU * hz * t) * 0.6 + rng.randf_range(-1.0, 1.0) * exp(-t / 0.0015))
		var body := 0.0
		if t > lag:
			var u := t - lag
			body = exp(-u / 0.018) * (sin(TAU * body_hz * u) + 0.3 * sin(TAU * body_hz * 2.7 * u)) * 0.7 \
				+ exp(-u / 0.003) * rng.randf_range(-0.4, 0.4)
		buf[j] = click + body
	return CarAudio._lowpass(buf, 7000.0)


## Confirm / start race: the click followed by a heavier second clack.
static func _confirm() -> AudioStreamWAV:
	var a := _switch_pcm(1900.0, 150.0, 4)
	var b := _switch_pcm(1100.0, 95.0, 5)
	var gap := int(0.07 * RATE)
	var out := PackedFloat32Array()
	out.resize(gap + b.size())
	out.fill(0.0)
	for j in a.size():
		out[j] += a[j] * 0.8
	for j in b.size():
		out[gap + j] += b[j]
	return CarAudio._to_wav(CarAudio._normalise(out, 0.75), false)
