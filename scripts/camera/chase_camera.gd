class_name ChaseCamera
extends Camera3D
## In-race camera. Press C (or Y on a gamepad) to cycle: chase, cockpit (see
## Cockpit), far chase, bumper, bonnet, roof, trackside TV. Adds grounded motion (road rumble,
## impact jolts, lateral-g roll, surge pull-back, FOV kick) and owns the lens
## post pass (CameraPost). Debug: `--cam=chase|cockpit|far|bumper|bonnet|roof|tv`,
## `--nopost` (no lens pass), `--camstats` (prints frame stats), `--cam_look=sun`
## (look past the sun from above the car, to check the glare) or `--cam_look=x,y,z`.

enum Mode { CHASE, COCKPIT, FAR, BUMPER, BONNET, ROOF, TV }
const MODE_NAMES := ["chase", "cockpit", "far", "bumper", "bonnet", "roof", "tv"]
## How rigidly each camera is fixed to the car (shake scale).
const MOUNT_SHAKE := [0.55, 0.3, 0.4, 1.0, 0.85, 0.75, 0.0]
## Share of lens drops each camera gets in the rain (cockpit: the windscreen has its own).
const MOUNT_RAIN := [0.35, 0.0, 0.3, 1.0, 0.9, 0.9, 0.25]

const HeadRig := preload("res://scripts/camera/cockpit_head.gd")

## True while the driver's-eye view is showing (the HUD hides its rev counter).
static var cockpit_view := false

var target: Car
var mode := Mode.CHASE
var debug_offset := Vector3.ZERO ## car-local position for screenshot framing; ZERO = off
var debug_world := [] ## [position, look_at] in world space for screenshots; empty = off
var debug_look_dir := Vector3.ZERO ## world direction to look along from above the car; ZERO = off
var post: CameraPost ## null with --nopost
var shake := CameraShake.new()

var _back := Vector3(0, 0, 1)
var _last_speed := 0.0
var _surge := 0.0
var _mounts := {} ## Mode -> car-local position (bumper, bonnet), from the body's size
var _mount_basis := Basis()
var _mount_mode := -1 ## which mounted camera _mount_basis belongs to
var _tv := TvDirector.new()
var _line: RacingLine
var _line_looked := false
var _stats := false
var _look_arg := ""
var _stats_t := 0.0
var _stats_ms := 0.0
var _stats_n := 0
var _cockpit: Cockpit
var _head := HeadRig.new()


func _ready() -> void:
	# The camera follows the car's already-interpolated transform every frame;
	# letting the engine interpolate the camera again makes everything judder.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
	fov = 68.0
	near = 0.05
	far = 4000.0
	var nopost := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cam="):
			var i := MODE_NAMES.find(arg.trim_prefix("--cam="))
			if i >= 0:
				mode = i as Mode
		elif arg == "--nopost":
			nopost = true
		elif arg == "--camstats":
			_stats = true
		elif arg.begins_with("--cam_look="):
			_look_arg = arg.trim_prefix("--cam_look=")
	if not nopost:
		post = CameraPost.new()
		add_child(post)
	if _stats:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _physics_process(dt: float) -> void:
	if target != null and is_instance_valid(target):
		shake.sample(target, dt)


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if Input.is_action_just_pressed("camera"):
		mode = ((mode + 1) % Mode.size()) as Mode
	if _look_arg != "":
		_apply_look_arg()
	var t := target.get_global_transform_interpolated()
	var debug_view := true
	if not debug_world.is_empty():
		global_position = debug_world[0]
		look_at(debug_world[1], Vector3.UP)
	elif debug_look_dir != Vector3.ZERO:
		global_position = t.origin + Vector3.UP * 1.5
		look_at(global_position + debug_look_dir, Vector3.UP if absf(debug_look_dir.y) < 0.99 else Vector3.BACK)
	elif debug_offset != Vector3.ZERO:
		global_position = t * debug_offset
		look_at(t.origin + Vector3.UP * 0.1, Vector3.UP)
	else:
		debug_view = false
		_place(t, dt)
	_update_post(debug_view, dt)
	_tick_stats(dt)


func _place(t: Transform3D, dt: float) -> void:
	var speed_t := clampf(absf(target.speed) / 60.0, 0.0, 1.0)
	# Pull back under acceleration, lean in under braking: you feel the thrust.
	var accel := (target.speed - _last_speed) / maxf(dt, 0.001)
	_last_speed = target.speed
	_surge = lerpf(_surge, clampf(accel / 9.81, -1.2, 1.0), 1.0 - exp(-dt * 4.0))
	var base_fov := 72.0 if mode == Mode.BUMPER else 66.0
	# Widens up to ~200 km/h, then keeps opening a little more towards top speed
	# so 250+ still feels faster than 200 (handling tune).
	var fast_t := smoothstep(50.0, 80.0, absf(target.speed))
	var want_fov := base_fov + 12.0 * clampf(absf(target.speed) / 55.0, 0.0, 1.0) + 7.0 * fast_t + maxf(_surge, 0.0) * 2.5
	if mode == Mode.COCKPIT:
		want_fov = 60.0 + 5.0 * speed_t
	_set_cockpit(mode == Mode.COCKPIT)
	fov = lerpf(fov, want_fov, 1.0 - exp(-dt * 3.0))

	if mode != Mode.ROOF and mode != Mode.BUMPER and mode != Mode.BONNET:
		_mount_mode = -1
	match mode:
		Mode.ROOF, Mode.BUMPER, Mode.BONNET:
			_place_mounted(t, dt)
		Mode.COCKPIT:
			global_transform = _head.place(target, _cockpit, t, dt, _surge, shake.lat_g)
		Mode.TV:
			if not _place_tv(t, dt):
				_place_chase(t, dt, Mode.CHASE)
			return # a tripod: no shake, no roll
		_:
			_place_chase(t, dt, mode)
	var s := shake.offsets(dt, MOUNT_SHAKE[mode])
	var off: Vector3 = s[0]
	var rot: Vector3 = s[1]
	var jolt_scale := 1.0 if mode == Mode.CHASE or mode == Mode.FAR else (0.12 if mode == Mode.COCKPIT else 0.3)
	global_position += global_basis * off + shake.jolt * jolt_scale
	rotate_object_local(Vector3.RIGHT, rot.x)
	rotate_object_local(Vector3.UP, rot.y)
	var roll := rot.z
	if mode == Mode.CHASE or mode == Mode.FAR:
		# The body leans out of the turn; the chase rig leans a touch with it.
		roll += clampf(shake.lat_g * deg_to_rad(1.3), -deg_to_rad(2.2), deg_to_rad(2.2))
	rotate_object_local(Vector3.BACK, roll)


## The driver's-eye view: builds the car's Cockpit the first time and shows
## it only while this camera is selected.
func _set_cockpit(on: bool) -> void:
	cockpit_view = on
	if on and (_cockpit == null or not is_instance_valid(_cockpit) or _cockpit.car != target):
		if _cockpit and is_instance_valid(_cockpit):
			_cockpit.queue_free()
		_cockpit = Cockpit.new()
		_cockpit.car = target
		target.add_child(_cockpit)
	if _cockpit and is_instance_valid(_cockpit) and _cockpit.active != on:
		_cockpit.set_active(on)
		near = 0.03 if on else 0.05


func _place_chase(t: Transform3D, dt: float, m: Mode) -> void:
	# Look partly along the direction of travel, not just the nose, so slides
	# stay readable instead of the camera whipping round with the car.
	var back := t.basis.z
	back.y = 0.0
	var vel := target.linear_velocity
	vel.y = 0.0
	if vel.length() > 4.0 and target.speed > 0.0:
		back = back.normalized().slerp(-vel.normalized(), 0.3)
	if back.length() > 0.01:
		# A touch more lag at speed: the view stays planted through fast sweepers.
		var follow := lerpf(7.0, 5.0, clampf(absf(target.speed) / 60.0, 0.0, 1.0))
		_back = _back.slerp(back.normalized(), 1.0 - exp(-dt * follow)).normalized()
	# Fast: sit a little lower and closer and look further down the road.
	var hi := smoothstep(25.0, 65.0, absf(target.speed))
	var dist := (5.6 - 0.35 * hi if m == Mode.CHASE else 8.5) + _surge * 0.7
	var height := 1.65 - 0.1 * hi if m == Mode.CHASE else 2.6
	global_position = t.origin + _back * dist + Vector3.UP * height
	look_at(t.origin + Vector3.UP * 0.7 - _back * (2.5 + 3.0 * hi), Vector3.UP)


## Cameras bolted to the car: bumper, bonnet, roof. The rotation is smoothed a
## hair so physics micro-jitter doesn't buzz the whole frame (shake adds the
## intended vibration back).
func _place_mounted(t: Transform3D, dt: float) -> void:
	if _mounts.is_empty():
		_measure_mounts()
	var local: Vector3 = Vector3(0, 0.62, 0.1) if mode == Mode.ROOF else _mounts[mode]
	if _mount_mode != mode: # just switched: no swing-in from the last camera
		_mount_basis = t.basis.orthonormalized()
		_mount_mode = mode
	_mount_basis = _mount_basis.slerp(t.basis.orthonormalized(), 1.0 - exp(-dt * 30.0)).orthonormalized()
	global_transform = Transform3D(_mount_basis, t * local)
	# Bonnet view looks slightly down so the nose sits at the bottom of the frame.
	if mode == Mode.BONNET:
		rotate_object_local(Vector3.RIGHT, deg_to_rad(-2.5))


## Bumper and bonnet spots from the car's visual bounds (car-local, -Z = front).
func _measure_mounts() -> void:
	var box := AABB(Vector3(-0.85, -0.6, -2.2), Vector3(1.7, 1.3, 4.4))
	var body := target.get_node_or_null("Body")
	if body:
		var inv := target.global_transform.affine_inverse()
		var first := true
		for n in body.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				continue # the car's ShadowProxy (includes the wheels)
			var bb := (inv * mi.global_transform) * mi.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
	var front := box.position.z
	var bottom := box.position.y
	_mounts[Mode.BUMPER] = Vector3(0.0, bottom + 0.36, front - 0.03)
	_mounts[Mode.BONNET] = Vector3(0.0, bottom + box.size.y * 0.72, front + box.size.z * 0.36)


func _place_tv(t: Transform3D, dt: float) -> bool:
	if not _line_looked:
		_line_looked = true
		var scene := get_tree().current_scene
		var c := scene.find_child("Circuit", true, false) if scene else null
		if c is Circuit:
			_line = (c as Circuit).line
	if not _tv.update(_line, target, t, get_world_3d().direct_space_state, dt):
		return false
	global_position = _tv.position
	if _tv.position.distance_to(_tv.look) > 0.1:
		look_at(_tv.look, Vector3.UP)
	fov = _tv.fov
	return true


func _update_post(debug_view: bool, dt: float) -> void:
	if post == null:
		return
	var kmh := absf(target.speed) * 3.6
	var fx := 0.0
	var rain := 0.0
	var streak := 0.0
	if not debug_view:
		fx = smoothstep(120.0, 260.0, kmh)
		if mode == Mode.TV:
			fx *= 0.0 # a panning tripod shot: no radial speed blur
		else:
			fx *= 1.0 if mode in [Mode.BUMPER, Mode.BONNET] else 0.8
		rain = MOUNT_RAIN[mode]
		if mode == Mode.COCKPIT and (_cockpit == null or not _cockpit.has_glass):
			rain = 0.5
		streak = 0.0 if mode == Mode.TV else smoothstep(25.0, 140.0, kmh)
	var exclude: Array[RID] = [target.get_rid()]
	post.update_fx(self, fx, target.linear_velocity, rain, streak, exclude, dt)


func _apply_look_arg() -> void:
	if _look_arg == "sun":
		var scene := get_tree().current_scene
		var sun := scene.find_child("Sun", true, false) as DirectionalLight3D if scene else null
		if sun:
			# Just off the sun, horizon in frame: how you'd meet it driving.
			var d := sun.global_basis.z.rotated(Vector3.UP, deg_to_rad(22.0))
			d.y *= 0.55
			debug_look_dir = d.normalized()
	else:
		var v := _look_arg.split_floats(",")
		if v.size() == 3:
			debug_look_dir = Vector3(v[0], v[1], v[2]).normalized()
	_look_arg = ""


func _tick_stats(dt: float) -> void:
	if not _stats:
		return
	var rid := get_viewport().get_viewport_rid()
	_stats_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	_stats_n += 1
	_stats_t += dt
	if _stats_t > 2.0:
		print("camstats mode=%s gpu_ms=%.2f fps=%d kmh=%d rumble=%.2f post=%s" % [MODE_NAMES[mode],
			_stats_ms / maxi(_stats_n, 1), Engine.get_frames_per_second(), absf(target.speed) * 3.6, shake.rumble, post != null])
		_stats_t = 0.0
		_stats_ms = 0.0
		_stats_n = 0
