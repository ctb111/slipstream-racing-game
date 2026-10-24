class_name AudioSpace
extends Node
## Acoustic surroundings of the listener: a few times a second it casts rays
## sideways and overhead from the camera. Walls, grandstands, town buildings,
## bridges and tunnels close by turn up a reverb on the Engine and Effects
## buses: a short slap-back between near walls, a longer boomy tail under a
## roof. Out in the open the reverb is bypassed (no DSP cost).
## One per scene; CarAudio creates it. Debug: `--spacedebug` prints readings.

const EVERY := 0.2 ## s between ray sweeps (one ray per frame, round-robin)
const REACH := 32.0 ## m: walls further than this don't colour the sound
const BUSES := [&"Engine", &"Effects"]
## Ray directions in the camera's yaw frame (x = right, y = up, -z = ahead).
const DIRS: Array[Vector3] = [Vector3(1, 0.05, 0), Vector3(-1, 0.05, 0), Vector3(0, 1, 0),
	Vector3(0.7, 0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0.75, 0.05, -0.65), Vector3(-0.75, 0.05, -0.65),
	Vector3(0.75, 0.05, 0.65), Vector3(-0.75, 0.05, 0.65)]

static var instance: AudioSpace

var _hits: Array[float] = [] ## per ray: distance to a wall (REACH = open)
var _hall: Array[float] = [] ## per ray: 1 if it hit a tagged hall (group "echo": warehouse / barn / tunnel)
var _ray := 0
var _t := 0.0
var _wet := 0.0
var _room := 0.3
var _pre := 30.0
var _verbs: Array[AudioEffectReverb] = []
var _idx: Array[int] = []
var _enabled := false
var _debug := false
var _grid := {} ## Vector2i cell (CELL m) -> house footprints [centre, along, across, w, d] (themes.gd: no colliders)
var _grid_ready := false
const CELL := 40.0
var _dbg_t := 0.0


static func ensure(from: Node) -> void:
	if is_instance_valid(instance) and instance.is_inside_tree():
		return
	var scene := from.get_tree().current_scene
	if scene == null:
		return
	instance = AudioSpace.new()
	instance.name = "AudioSpace"
	scene.add_child.call_deferred(instance)


func _ready() -> void:
	_debug = "--spacedebug" in OS.get_cmdline_user_args()
	_hits.resize(DIRS.size())
	_hits.fill(REACH)
	_hall.resize(DIRS.size())
	_hall.fill(0.0)
	for b in BUSES:
		var bus := AudioServer.get_bus_index(b)
		if bus < 0:
			continue
		var verb: AudioEffectReverb = null
		var at := -1
		for k in AudioServer.get_bus_effect_count(bus): # left from an earlier race
			if AudioServer.get_bus_effect(bus, k) is AudioEffectReverb and AudioServer.get_bus_effect(bus, k).resource_name == "space":
				verb = AudioServer.get_bus_effect(bus, k)
				at = k
		if verb == null:
			verb = AudioEffectReverb.new()
			verb.resource_name = "space"
			AudioServer.add_bus_effect(bus, verb)
			at = AudioServer.get_bus_effect_count(bus) - 1
		verb.dry = 1.0
		verb.wet = 0.0
		verb.hipass = 0.15 # keep the low rumble dry, reflect the bark
		verb.spread = 0.8
		AudioServer.set_bus_effect_enabled(bus, at, false)
		_verbs.append(verb)
		_idx.append(at)


func _exit_tree() -> void:
	_set_enabled(false)
	if instance == self:
		instance = null


func _set_enabled(on: bool) -> void:
	if on == _enabled:
		return
	_enabled = on
	for k in _verbs.size():
		var bus := AudioServer.get_bus_index(BUSES[k])
		if bus >= 0 and _idx[k] < AudioServer.get_bus_effect_count(bus):
			AudioServer.set_bus_effect_enabled(bus, _idx[k], on)


func _physics_process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not (cam is ChaseCamera): # race cameras only (not the showroom)
		return
	# Spread the sweep over frames: one ray every EVERY / DIRS.size() seconds.
	_t += dt
	if _t < EVERY / DIRS.size():
		return
	_t = 0.0
	var yaw := cam.global_basis
	var fwd := -yaw.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var d := DIRS[_ray]
	var dir := (right * d.x + Vector3.UP * d.y - fwd * d.z).normalized()
	var from := cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH)
	var target = cam.get("target")
	if target is CollisionObject3D:
		q.exclude = [(target as CollisionObject3D).get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var dist := REACH
	if not hit.is_empty() and not (hit.collider is Car):
		# Ground hits (rays tilt down on hills) don't count as walls.
		if (hit.normal as Vector3).y < 0.6 or d.y > 0.5:
			dist = from.distance_to(hit.position)
	if d.y < 0.5:
		dist = minf(dist, _house_hit(from, dir))
	_hits[_ray] = dist
	var hall := 0.0
	if not hit.is_empty() and hit.collider is Node and (hit.collider as Node).is_in_group("echo"):
		hall = 1.0 if str((hit.collider as Node).get_meta("echo_kind", "")) != "barn" else 0.6
	_hall[_ray] = hall
	_ray = (_ray + 1) % DIRS.size()


## Town houses are visual only: intersect the ray (flattened) with their
## footprints from the themes builder. Returns the distance, REACH if none.
func _house_hit(from: Vector3, dir: Vector3) -> float:
	if not _grid_ready:
		_grid_ready = true
		var scene := get_tree().current_scene
		var c := scene.find_child("Circuit", true, false) if scene else null
		if c:
			for b: Array in c.get_meta("sound_boxes", []):
				var p: Vector3 = b[0]
				var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(b)
	if _grid.is_empty():
		return REACH
	var d2 := Vector2(dir.x, dir.z)
	if d2.length() < 0.1:
		return REACH
	d2 = d2.normalized()
	var o := Vector2(from.x, from.z)
	var best := REACH
	var home := Vector2i(floori(from.x / CELL), floori(from.z / CELL))
	for gx in range(-1, 2):
		for gz in range(-1, 2):
			for b: Array in _grid.get(home + Vector2i(gx, gz), []):
				var c: Vector3 = b[0]
				var ax := Vector2((b[1] as Vector3).x, (b[1] as Vector3).z).normalized()
				var az := Vector2(-ax.y, ax.x)
				var rel := o - Vector2(c.x, c.z)
				# Slab test in the house's own frame.
				var lo := 0.0
				var hi := best
				var ok := true
				for axis in 2:
					var a: Vector2 = ax if axis == 0 else az
					var half: float = (b[3] if axis == 0 else b[4]) * 0.5
					var p0 := rel.dot(a)
					var dv := d2.dot(a)
					if absf(dv) < 0.0001:
						if absf(p0) > half:
							ok = false
							break
						continue
					var t1 := (-half - p0) / dv
					var t2 := (half - p0) / dv
					lo = maxf(lo, minf(t1, t2))
					hi = minf(hi, maxf(t1, t2))
					if lo > hi:
						ok = false
						break
				if ok and lo > 0.0:
					best = minf(best, lo)
	return best


func _process(dt: float) -> void:
	if _verbs.is_empty():
		return
	# Sides: how boxed-in we are and how far the walls are. Roof: tunnel / bridge.
	var side := 0.0
	var near := REACH
	var n := 0
	for k in DIRS.size():
		if DIRS[k].y > 0.5:
			continue
		n += 1
		var c := 1.0 - _hits[k] / REACH
		side += c
		near = minf(near, _hits[k])
	side /= maxf(n, 1)
	var roof := 0.0
	for r in [2, 3, 4]:
		roof = maxf(roof, (1.0 - _hits[r] / 18.0) if _hits[r] < 18.0 else 0.0)
	roof = clampf(roof * 1.6, 0.0, 1.0)
	var enclosed := clampf(side * 2.6, 0.0, 1.0)
	# Inside a warehouse / tunnel built as one (tagged by the gimmick builders): a big hard hall.
	var hall := 0.0
	for h in _hall:
		hall += h
	hall = clampf(hall / 3.0, 0.0, 1.0)
	roof = maxf(roof, hall)
	enclosed = maxf(enclosed, hall)
	var want_wet := clampf(enclosed * 0.28 + roof * 0.3, 0.0, 0.42)
	var want_room := clampf(0.25 + roof * 0.55 + enclosed * 0.15, 0.0, 0.95)
	# Pre-delay = round trip to the nearest wall: the slap-back you hear between buildings.
	var want_pre := clampf(near * 2.0 / 343.0 * 1000.0, 8.0, 180.0)
	var rate := 1.0 - exp(-dt * 3.0)
	_wet = lerpf(_wet, want_wet, rate)
	_room = lerpf(_room, want_room, rate)
	_pre = lerpf(_pre, want_pre, rate)
	_set_enabled(_wet > 0.01)
	if _enabled and absf(_verbs[0].wet - _wet) + absf(_verbs[0].room_size - _room) > 0.004:
		for v in _verbs:
			v.wet = _wet
			v.room_size = _room
			v.damping = 0.35 + 0.3 * (1.0 - roof)
			if absf(v.predelay_msec - _pre) > 4.0: # the delay line jumps: move it in coarse, rare steps
				v.predelay_msec = _pre
			v.predelay_feedback = 0.25 + 0.2 * enclosed
	if _debug:
		_dbg_t += dt
		if _dbg_t > 1.0:
			_dbg_t = 0.0
			print("space side=%.2f roof=%.2f near=%.1f wet=%.2f room=%.2f pre=%.0f" % [side, roof, near, _wet, _room, _pre])
