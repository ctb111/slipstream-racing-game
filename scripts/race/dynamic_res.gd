class_name DynamicRes
extends Node
## Keeps every preset near 60 fps: when frames run long, the 3D view
## renders a little below native resolution (FSR upscaled, the HUD stays
## sharp); when there is headroom again it creeps back up.
## Only active while the Render resolution setting is Auto;
## it re-checks that every second, so changing it from the pause menu works.

const TARGET_FPS := 62.0 ## vsync off: a little over 60 so the average lands at or above it
const MIN_SCALE := 0.7 ## floor at ~1080p (FSR upscaled); bigger screens may go lower (see _min_scale). Only reached when frames run long, e.g. a hot, throttling MacBook Air
const MIN_PIXELS := 1.6e6 ## never render fewer pixels than this (~1690x950)
const STEP := 0.05

var _max_scale := 1.0
var _t := 0.0
var _frames := 0
var _good := 0.0 ## seconds spent on target
var _hold := 4.0 ## wait before raising again; doubles when a raise had to be undone
var _raised_at := -100.0
var _clock := 0.0


var _active := false
## Second step once the resolution is at its floor and frames still run long
## (a hot, throttling MacBook Air): SSAO off (~2-3 ms on an M1). Back on first
## when there is clear headroom again.
var _ssao_cut := false
var _no_freeze := OS.get_cmdline_user_args().has("--dynres_nofreeze") ## debug: A/B the countdown freeze
var _slow_at_floor := 0.0
var _fast := 0.0
var _start_cut := false ## the last race here ended with SSAO cut: start with it cut
var _ssao_locked := false
var _restored_at := -100.0
var _gpu_ms := 0.0 ## summed measured GPU time this second
var _frames_gpu := 0


static func wanted() -> bool:
	return Game.render_scale == 0


## With vsync on the frame rate is capped at the refresh rate, so 62 can never be
## reached there: aim just under the refresh instead (one missed frame a second is fine).
static func target_fps() -> float:
	var hz := DisplayServer.screen_get_refresh_rate()
	if Game.vsync and hz > 0.0:
		return minf(TARGET_FPS, hz - 1.5)
	return TARGET_FPS


## GPU headroom: with vsync on the fps can't show it, the measured GPU time can.
## True when the GPU is well inside the frame budget (or can't be measured).
func _gpu_spare() -> bool:
	var gpu := _gpu_ms / maxf(_frames_gpu, 1.0)
	_gpu_ms = 0.0
	_frames_gpu = 0
	if gpu <= 0.0:
		return true
	return gpu < 0.78 * 1000.0 / target_fps()


func _ready() -> void:
	_max_scale = Game.render_scale_now()
	# Start where the last race here settled: the grid start (8 cars bunched, frozen
	# scale during the countdown) is the heaviest moment, and stepping down from
	# native takes seconds.
	if wanted():
		var h = Game.auto_scales.get(_key(), _max_scale) # [scale, ssao cut] (or an older plain scale)
		_set_scale(get_viewport(), float(h[0] if h is Array else h))
		_start_cut = h is Array and bool(h[1])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(dt: float) -> void:
	# Loading-screen frames (the race builds for several seconds) say nothing
	# about race frame rate: don't let them drop the resolution.
	if get_parent() and get_parent().get("_loaded") == false:
		_t = 0.0
		_frames = 0
		if _start_cut and Weather.current() != null: # behind the loading screen, so the start looks like the race
			_set_ssao_cut(true)
			_start_cut = false
		return
	# Nor the countdown and the first seconds of racing: shaders and pipelines
	# are still being compiled then, and stepping the resolution (and SSAO/glow)
	# up and down on the grid read as the cars and terrain flickering.
	var race := get_parent()
	if race and race.get("state") != null and race.get("race_time") != null and not _no_freeze:
		if int(race.get("state")) == 0 or float(race.get("race_time")) < 2.0: # 0 = COUNTDOWN
			_t = 0.0
			_frames = 0
			return
	_clock += dt
	_t += dt
	_frames += 1
	_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_frames_gpu += 1
	if _t < 1.0:
		return
	var fps := _frames / _t
	_t = 0.0
	_frames = 0
	var vp := get_viewport()
	var target := target_fps()
	var spare := _gpu_spare()
	if wanted() != _active:
		_active = wanted()
		_max_scale = Game.render_scale_now()
		_good = 0.0
		if not _active:
			Game.apply_viewport_quality(vp) # back to the fixed scale
			if _ssao_cut:
				_set_ssao_cut(false)
	if not _active or get_tree().paused:
		return
	var s := vp.scaling_3d_scale
	var at_floor := s <= _min_scale(vp) + 0.001
	# Slow seconds at the floor, decaying (fps hovering around the target must not reset it).
	_slow_at_floor = _slow_at_floor + 1.0 if fps < target and at_floor else maxf(_slow_at_floor - 0.5, 0.0)
	if _slow_at_floor >= 3.0 and not _ssao_cut:
		_set_ssao_cut(true)
		_ssao_locked = _clock - _restored_at < 15.0 # turning it back on didn't hold: leave it off this race
	_fast = _fast + 1.0 if fps >= target and spare and (Game.vsync or fps >= target + 10.0) else 0.0
	if _ssao_cut and _fast >= 5.0 and not _ssao_locked:
		_set_ssao_cut(false)
		_restored_at = _clock
		_fast = 0.0
		_good = 0.0
		return
	if fps < target and s > _min_scale(vp) + 0.001:
		if _clock - _raised_at < 3.0:
			_hold = minf(_hold * 2.0, 60.0) # that raise was too much: wait longer next time
		_set_scale(vp, s - (STEP if fps > target * 0.9 else STEP * 2.0)) # far off: bigger steps
		_good = 0.0
	elif fps >= target and spare:
		_good += 1.0
		if _good >= _hold and s < _max_scale - 0.001:
			_set_scale(vp, s + STEP)
			_raised_at = _clock
			_good = 0.0


var _glow_levels := PackedFloat32Array()


func _key() -> String:
	return "%s:%d" % [Game.track_id, Game.quality]


func _exit_tree() -> void:
	# Remember the settled scale for the next race (not from test runs, which pass game args).
	if _active and OS.get_cmdline_user_args().is_empty():
		Game.auto_scales[_key()] = [snappedf(get_viewport().scaling_3d_scale, 0.01), _ssao_cut]
		Game.save_settings()


## SSAO off and glow down to its three widest levels (or both back).
func _set_ssao_cut(cut: bool) -> void:
	var w := Weather.current()
	if w == null or w.env == null or cut == _ssao_cut:
		return
	var env := w.env
	_ssao_cut = cut
	if cut:
		env.set_meta("dynres_ssao", env.ssao_enabled)
		env.ssao_enabled = false
		_glow_levels.clear()
		for i in 7:
			_glow_levels.append(env.get_glow_level(i))
			if i < 4:
				env.set_glow_level(i, 0.0)
	else:
		env.ssao_enabled = env.get_meta("dynres_ssao", env.ssao_enabled)
		for i in mini(_glow_levels.size(), 7):
			env.set_glow_level(i, _glow_levels[i])


func _set_scale(vp: Viewport, s: float) -> void:
	s = clampf(snappedf(s, 0.01), _min_scale(vp), _max_scale)
	vp.scaling_3d_mode = Game.scaling_mode(s)
	vp.scaling_3d_scale = s


## Big screens (1440p, ultrawide, 4K) can drop further and still render
## plenty of pixels for FSR to upscale.
func _min_scale(vp: Viewport) -> float:
	var px := float(vp.get_visible_rect().size.x * vp.get_visible_rect().size.y)
	return clampf(sqrt(MIN_PIXELS / maxf(px, 1.0)), 0.5, MIN_SCALE)
