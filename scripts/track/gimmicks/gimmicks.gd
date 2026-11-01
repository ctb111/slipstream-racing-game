extends RefCounted
## Circuit EXTRA_BUILDER: runs the per-track dressing dress_<track_id>.gd (if
## present) which places Gx pieces. See gx.gd for the kit.


static func build(parent: Node3D, _curve: Curve3D, _road_width: float, _preset: Dictionary) -> void:
	var def = parent.get("def")
	if not def is Dictionary:
		return
	GxTest.maybe_run(parent) # debug only: --gx_test=<piece>:<kind>,... (see gx_test.gd)
	var path := "res://scripts/track/gimmicks/dress_%s.gd" % def.get("id", "")
	if ResourceLoader.exists(path):
		await load(path).dress(parent) # dress files yield now and then (Gx.breath)
	await _yield(parent, "Roadside")
	GxCorridor.build(parent) # near-road tree wall, catch fences, hoardings (see gx_corridor.gd)
	await _yield(parent, "Landscape")
	if ResourceLoader.exists("res://scripts/track/gimmicks/fill_landscape.gd"):
		load("res://scripts/track/gimmicks/fill_landscape.gd").fill(parent) # fields, farms, infra 20-300 m out (fill agent)
	await _yield(parent, "Crowds")
	if ResourceLoader.exists("res://scripts/track/gimmicks/gx_fans.gd"):
		load("res://scripts/track/gimmicks/gx_fans.gd").flush(parent) # builds the crowd pieces placed above (one merged batch)
	load("res://scripts/track/gimmicks/dress_shots.gd").attach(parent) # debug only: --dress_shots=... (see dress_shots.gd)


## A new loading step between the phases: the loading screen redraws instead of
## freezing for the whole dressing (seconds on the bigger tracks).
static func _yield(c: Node3D, label: String) -> void:
	if c.has_method("_step"):
		await c._step(label)
