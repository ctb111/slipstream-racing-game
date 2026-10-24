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
		load(path).dress(parent)
	if ResourceLoader.exists("res://scripts/track/gimmicks/fill_landscape.gd"):
		load("res://scripts/track/gimmicks/fill_landscape.gd").fill(parent) # fields, farms, infra 20-300 m out (fill agent)
	if ResourceLoader.exists("res://scripts/track/gimmicks/gx_fans.gd"):
		load("res://scripts/track/gimmicks/gx_fans.gd").flush(parent) # builds the crowd pieces placed above (one merged batch)
