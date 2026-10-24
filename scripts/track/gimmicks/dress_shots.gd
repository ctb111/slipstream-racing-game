extends Node
## Debug helper for track dressers: many screenshots from ONE windowed run.
##   --dress_shots=/tmp/prefix         where to save (<prefix>_<n>.png)
##   --dress_at=120,640,1300           driver-height views: 1.3 m above the road
##                                      `along` m round the lap, looking 70 m ahead
##   --dress_cam=x,y,z,lx,ly,lz;...     free views (world position ; look-at)
##   --dress_t0=8                       seconds to wait before the first shot
##   --dress_side=300,-640               close-ups of the roadside: from the road edge `along`
##                                      m round the lap, looking at the right (+) / left (-) side
## Added by dress_<track>.gd via DressShots.attach(c); does nothing without the args.

var views: Array = [] ## [Vector3 pos, Vector3 look]
var prefix := ""
var t0 := 8.0
var _t := 0.0
var _i := -1
var _hold := 0.0
var _cam: Camera3D


static func attach(c: Node3D) -> void:
	var prefix_arg := ""
	var at := PackedFloat64Array()
	var cams: Array = []
	var sides := PackedFloat64Array()
	var t0 := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dress_shots="):
			prefix_arg = a.get_slice("=", 1)
		elif a.begins_with("--dress_at="):
			at = a.get_slice("=", 1).split_floats(",")
		elif a.begins_with("--dress_cam="):
			for v in a.get_slice("=", 1).split(";"):
				var f := v.split_floats(",")
				if f.size() == 6:
					cams.append([Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5])])
		elif a.begins_with("--dress_side="):
			sides = a.get_slice("=", 1).split_floats(",")
		elif a.begins_with("--dress_t0="):
			t0 = float(a.get_slice("=", 1))
	if prefix_arg == "":
		return
	var n = load("res://scripts/track/gimmicks/dress_shots.gd").new()
	n.prefix = prefix_arg
	n.t0 = t0
	for along in at:
		var p := Gx.centre(c, along) + Vector3.UP * 1.3
		var q := Gx.centre(c, along + 70.0) + Vector3.UP * 1.0
		n.views.append([p, q])
	for sa in sides:
		var sd := Gx.RIGHT if sa >= 0.0 else Gx.LEFT
		var p := Gx.frame(c, absf(sa), -sd, -1.0).origin + Vector3.UP * 1.8
		var q := Gx.frame(c, absf(sa) + 6.0, sd, 14.0).origin + Vector3.UP * 4.0
		n.views.append([p, q])
	n.views.append_array(cams)
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	c.add_child(n)


func _process(dt: float) -> void:
	_t += dt
	if _t < t0:
		return
	if _cam == null:
		_cam = Camera3D.new()
		_cam.fov = 60.0
		_cam.far = 4000.0
		get_parent().add_child(_cam)
	if _i < 0 or _hold > 0.9:
		if _i >= 0:
			var path := "%s_%d.png" % [prefix, _i]
			get_viewport().get_texture().get_image().save_png(path)
			print("dress_shots: saved ", path)
		_i += 1
		_hold = 0.0
		if _i >= views.size():
			get_tree().quit()
			return
		var v: Array = views[_i]
		_cam.look_at_from_position(v[0], v[1], Vector3.UP)
		_cam.make_current()
	_hold += dt
