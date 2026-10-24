extends Node
## Debug (`--perf-ab[=feat1,feat2,...]`): measures what each feature costs
## within ONE run, so machine load and run-to-run noise cancel out. For each
## feature it alternates OFF/ON segments of SEG seconds (REPS times each, the
## first 0.4 s of a segment discarded) and prints the mean frame time with the
## feature on and off. Quits when done. Start it once the race runs (`--allbots`).

const SEG := 1.6
const SKIP := 0.4
const REPS := 5
const ALL := ["ssao", "glow", "shadow", "fog", "sky", "post", "forest", "grass", "people", "themes", "props", "cars", "particles", "half"]

var feats: Array = []
var _i := 0 ## feature index
var _seg := 0 ## segment within the feature (even = on, odd = off)
var _t := 0.0
var _acc := [0.0, 0.0] ## frame time sums: on, off
var _dc := [0, 0] ## draw call sums: on, off
var _ph := [0.0, 0.0] ## physics ms sums: on, off
var _n := [0, 0]
var _res := []
var _state := {}
var _warm := 8.0


func _ready() -> void:
	process_priority = 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-ab="):
			feats = Array(a.trim_prefix("--perf-ab=").split(","))
	if feats.is_empty():
		feats = ALL.duplicate()


var _hitch_t := 0.0
var _last_scale := 0.0


## `--perf-ab=hitch`: logs every frame over 28 ms for 45 s (with the 3D scale,
## so DynamicRes changes show), then quits.
func _hitches(dt: float) -> void:
	_hitch_t += dt
	var sc := get_viewport().scaling_3d_scale
	if sc != _last_scale:
		print("perf-ab t=%.2f scale -> %.2f" % [_hitch_t, sc])
		_last_scale = sc
	if dt > 0.028:
		print("perf-ab t=%.2f HITCH %.1f ms  scale %.2f  draw %d" % [_hitch_t, dt * 1000.0, sc,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
	if _hitch_t > 45.0:
		print("perf-ab DONE")
		get_tree().quit()


func _process(dt: float) -> void:
	if feats == ["hitch"]:
		_hitches(dt)
		return
	if _warm > 0.0:
		_warm -= dt # let the race start and shaders settle
		return
	if _i >= feats.size():
		return
	_t += dt
	var on := _seg % 2 == 0
	if _t > SKIP:
		_acc[0 if on else 1] += dt
		_dc[0 if on else 1] += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		_ph[0 if on else 1] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_n[0 if on else 1] += 1
	if _t >= SEG:
		_t = 0.0
		_seg += 1
		if _seg >= REPS * 2:
			_apply(feats[_i], true)
			var t_on: float = _acc[0] / maxf(_n[0], 1) * 1000.0
			var t_off: float = _acc[1] / maxf(_n[1], 1) * 1000.0
			var d_on: int = _dc[0] / maxi(_n[0], 1)
			var d_off: int = _dc[1] / maxi(_n[1], 1)
			_res.append("%-10s on %6.2f ms  off %6.2f ms  cost %+6.2f ms   draws %4d / %4d (%+d)  physics/tick %.2f / %.2f ms" % [feats[_i], t_on, t_off, t_on - t_off, d_on, d_off, d_on - d_off, _ph[0] / maxi(_n[0], 1), _ph[1] / maxi(_n[1], 1)])
			print("perf-ab ", _res[-1])
			_i += 1
			_seg = 0
			_acc = [0.0, 0.0]
			_dc = [0, 0]
			_ph = [0.0, 0.0]
			_n = [0, 0]
			if _i >= feats.size():
				print("perf-ab DONE")
				get_tree().quit()
				return
		_apply(feats[_i], _seg % 2 == 0)


func _nodes(filter: Callable) -> Array:
	var out := []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		if filter.call(n):
			out.append(n)
	return out


func _apply(f: String, on: bool) -> void:
	var w := Weather.current()
	var env: Environment = w.env if w else null
	match f:
		"ssao": env.ssao_enabled = on if _keep(f, env.ssao_enabled) else false
		"glow": env.glow_enabled = on if _keep(f, env.glow_enabled) else false
		"fog": env.fog_enabled = on if _keep(f, env.fog_enabled) else false
		"shadow": w.sun.shadow_enabled = on if _keep(f, w.sun.shadow_enabled) else false
		"sky": # the sky background pass (radiance keeps updating)
			env.background_mode = Environment.BG_SKY if on else Environment.BG_COLOR
		"half":
			var base: float = _keep(f, get_viewport().scaling_3d_scale)
			get_viewport().scaling_3d_scale = base if on else base * 0.5
		"ssaolow": # "off" = the cheapest SSAO instead of Medium's
			if on:
				RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50, 300)
			else:
				RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW, true, 0.5, 1, 50, 300)
		"glowlvl": # "off" = only the two widest glow levels
			if not _state.has(f):
				var lv := []
				for i in 7:
					lv.append(env.get_glow_level(i))
				_state[f] = lv
			for i in 7:
				env.set_glow_level(i, _state[f][i] if on else (_state[f][i] if i >= 4 else 0.0))
		"glowup": # "off" = linear instead of bicubic glow upscale
			RenderingServer.environment_glow_set_use_bicubic_upscale(on)
		"tick60": # "off" = physics at 60 Hz instead of the project's rate
			var hz: int = _keep(f, Engine.physics_ticks_per_second)
			Engine.physics_ticks_per_second = hz if on else 60
		"audio", "ai", "dirt", "impacts", "tirefx", "ambience", "carfx", "space":
			var part: String = {"audio": "car_audio", "ai": "ai_driver", "dirt": "car_dirt", "impacts": "car_impacts", "tirefx": "tire_fx", "ambience": "ambience", "carfx": "car_fx", "space": "audio_space"}[f]
			for n in get_tree().root.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				if sc and part in sc.resource_path:
					n.set_process(on)
					n.set_physics_process(on)
		"pshadow":
			for n in get_tree().root.find_children("shadows", "MultiMeshInstance3D", true, false):
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"carshadow":
			for c in get_tree().root.find_children("*", "Car", true, false):
				for mi in c.find_children("*", "GeometryInstance3D", true, false):
					if on:
						mi.cast_shadow = mi.get_meta("_cs", mi.cast_shadow)
					else:
						mi.set_meta("_cs", mi.cast_shadow)
						mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"shafts": # sun shafts in the lens pass ("off" = 0 taps)
			for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
				if n is CameraPost:
					var cp := n as CameraPost
					if not cp.has_meta("_taps"):
						cp.set_meta("_taps", cp.mat.get_shader_parameter("shaft_taps"))
					cp.mat.set_shader_parameter("shaft_taps", cp.get_meta("_taps") if on else 0)
		"popfix": # "off" = the pre-2026-10-19 hard cuts: no distance fades, shorter parked cars / interiors / camp people
			if not _state.has(f):
				var rows := []
				for g: GeometryInstance3D in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					var nm := String(g.name)
					var pn := String(g.get_parent().name) if g.get_parent() else ""
					if nm.begins_with("Theme") or nm.begins_with("Forest"):
						continue
					var old_end := g.visibility_range_end
					if nm.begins_with("Cars_"):
						old_end -= 230.0
					elif nm == "CarContactShadows":
						old_end = 120.0
					elif nm.begins_with("WhInside"):
						old_end = 220.0
					elif pn == "CampPeople" and old_end > 0.0:
						old_end = 80.0
					elif pn == "CarOwners" and old_end > 0.0:
						old_end = 60.0
					var fade := g.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and g.visibility_range_begin <= 0.0
					if fade or old_end != g.visibility_range_end:
						rows.append([g, g.visibility_range_end, old_end, g.visibility_range_fade_mode])
				_state[f] = rows
				print("perf-ab popfix: %d instances changed" % rows.size())
			for r: Array in _state[f]:
				var g: GeometryInstance3D = r[0]
				if is_instance_valid(g):
					g.visibility_range_end = r[1] if on else r[2]
					g.visibility_range_fade_mode = r[3] if on else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		"post":
			for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
				if n is CameraPost:
					n.visible = on
		_:
			if not _state.has(f):
				_state[f] = _nodes(_filter(f))
			for n: Node3D in _state[f]:
				n.visible = on


func _keep(f: String, v) -> Variant:
	if not _state.has(f):
		_state[f] = v
	return _state[f]


func _filter(f: String) -> Callable:
	match f:
		"forest": return func(n: Node) -> bool: return String(n.name).begins_with("Forest")
		"grass": return func(n: Node) -> bool: return n is MultiMeshInstance3D and (n as MultiMeshInstance3D).visibility_range_end > 0.0 and (n as MultiMeshInstance3D).visibility_range_end < 120.0
		"people": return func(n: Node) -> bool: return n.has_method("stats") and n.get("_far") is Dictionary
		"themes": return func(n: Node) -> bool: return String(n.name).begins_with("Theme")
		"props": return func(n: Node) -> bool: return n is MultiMeshInstance3D and not String(n.name).begins_with("Forest") and not String(n.name).begins_with("Theme") and String(n.get_parent().name) == "Circuit" and ((n as MultiMeshInstance3D).visibility_range_end == 0.0 or (n as MultiMeshInstance3D).visibility_range_end >= 120.0)
		"cars": return func(n: Node) -> bool: return n is Car
		"setdress": return func(n: Node) -> bool: return String(n.name) == "SetDressing"
		"trackmesh": return func(n: Node) -> bool: return n is MeshInstance3D and String(n.get_parent().name) == "Circuit" and not String(n.name).begins_with("Forest") and not String(n.name).begins_with("Theme")
		"particles": return func(n: Node) -> bool: return n is GPUParticles3D
		"atmos": return func(n: Node) -> bool: return String(n.name) == "Atmosphere" # mist, motes, debris, windsocks, devil
		"leaves": return func(n: Node) -> bool: return String(n.name) == "RoadLeaves"
	if f.begins_with("name:"): # any node whose name starts with the given prefix, e.g. name:Gx
		var pre := f.trim_prefix("name:")
		return func(n: Node) -> bool: return String(n.name).begins_with(pre)
	return func(_n: Node) -> bool: return false
