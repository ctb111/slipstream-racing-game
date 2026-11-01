class_name CrowdReact
extends Node
## Makes the trackside crowd react to the race (EXTRA_BUILDERS entry). Pushes a
## few shader globals (shaders/crowd_react.gdshaderinc) that people.gdshader,
## trackside_glow and trackside_smoke read; nothing touches a MultiMesh buffer.
##   crowd_hot0..3   leader, player and tight battles (< BATTLE s apart), as a
##                   point lagging LAG s behind the car: fans within ~85 m cheer,
##                   jump and clap harder, flashes pop, flares burn brighter.
##   marshal_yellow0..1  a car stopped / crawling / spun / reset mid-race: the
##                   marshals up to ~150 m before it wave yellow (held SETTLE s).
##   marshal_chequer the finish marshal (placed here, INSTANCE_CUSTOM.a = 1) waves
##                   the chequered flag from the leader's final lap on.
## Cars are re-read from the race's `entries` at SCAN Hz; only the hotspot
## positions are interpolated every frame (7 global vec4 sets per frame).

const SCAN := 0.2
const LAG := 0.6
const BATTLE := 1.0
const CRAWL := 8.0 ## m/s
const SETTLE := 6.0
const YELLOW_BACK := 70.0 ## metres: the yellow sector centre sits this far before the incident
const HOT := [&"crowd_hot0", &"crowd_hot1", &"crowd_hot2", &"crowd_hot3"]
const YEL := [&"marshal_yellow0", &"marshal_yellow1"]

var _race: Node
var _t := 0.0
var _hot: Array = [] ## [Car, strength]
var _last := {} ## Car -> position at the previous scan
var _incidents: Array = [] ## [centre, time left, w]
var _chequer := 0.0
var _finish := Vector3.ZERO
## Debug --crowd_force=hot,yellow,chequer: pin those reactions on around the camera (screenshots).
var _force := ""
var _debugged := false


static func build(parent: Node3D, _curve: Curve3D, road_width: float, _preset: Dictionary) -> void:
	var r := CrowdReact.new()
	r.name = "CrowdReact"
	parent.add_child(r)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--crowd_force="):
			r._force = a.get_slice("=", 1)
	if OS.get_cmdline_user_args().has("--no-people") or not (parent.get("curve") is Curve3D):
		return
	# The finish marshal, beside the line on whichever side is clear.
	var kit := TracksideKit.new(parent, parent.get("curve"), road_width, {})
	for side: float in [1.0, -1.0]:
		var i := kit.idx(6.0)
		var p := kit.at(i, side * (kit.rail_dist(i, side) + 1.2))
		if kit.road_clear(p, 0.8): # (the line sits in the pit / grandstand no-tree zones: no is_free)
			var face := -kit.rights[i] * side - kit.tangents[i] * 0.5
			parent.add_child(PeopleKit.figure(PeopleKit.Role.MARSHAL, kit.frame_facing(p, face),
				Color(0.9, 0.9, 0.9), Color(0.37, 0.0, 0.0, 1.0)))
			r._finish = p
			break
	if OS.get_cmdline_user_args().has("--debug-crowd"):
		print("crowd: finish marshal at %s" % r._finish)


func _exit_tree() -> void:
	for n: StringName in HOT + YEL + [&"marshal_chequer"]:
		RenderingServer.global_shader_parameter_set(n, Vector4(0, -1000, 0, 0))


func _process(dt: float) -> void:
	if _race == null:
		var root := get_tree().current_scene
		if root == null or not ("entries" in root):
			return
		_race = root
	_t -= dt
	if _t <= 0.0:
		_t = SCAN
		_scan()
	for k in HOT.size():
		var v := Vector4(0, -1000, 0, 0)
		if k < _hot.size() and is_instance_valid(_hot[k][0]):
			var car: Car = _hot[k][0]
			var p := car.global_position - car.linear_velocity * LAG
			v = Vector4(p.x, p.y, p.z, _hot[k][1])
		RenderingServer.global_shader_parameter_set(HOT[k], v)
	for k in YEL.size():
		var v := Vector4(0, -1000, 0, 0)
		if k < _incidents.size():
			var inc: Array = _incidents[k]
			inc[2] = move_toward(inc[2], 1.0 if inc[1] > 0.0 else 0.0, dt * 2.0)
			var c: Vector3 = inc[0]
			v = Vector4(c.x, c.y, c.z, inc[2])
		RenderingServer.global_shader_parameter_set(YEL[k], v)
	RenderingServer.global_shader_parameter_set(&"marshal_chequer", Vector4(_finish.x, _finish.y, _finish.z, _chequer))
	if _force != "":
		var cam := get_viewport().get_camera_3d()
		var c := cam.global_position if cam else Vector3.ZERO
		if "hot" in _force:
			RenderingServer.global_shader_parameter_set(HOT[0], Vector4(c.x, c.y, c.z, 1.0))
		if "yellow" in _force:
			RenderingServer.global_shader_parameter_set(YEL[0], Vector4(c.x, c.y, c.z, 1.0))
		if "chequer" in _force:
			RenderingServer.global_shader_parameter_set(&"marshal_chequer", Vector4(_finish.x, _finish.y, _finish.z, 1.0))


func _scan() -> void:
	var racing: bool = _race.state == 1 # race.gd State.RACING (no class_name)
	if racing and not _debugged and OS.get_cmdline_user_args().has("--debug-crowd"):
		_debugged = true
		for cr in get_parent().find_children("*", "", true, false):
			if cr is PeopleKit.Crowd and cr.total > 0 and cr.name != "Grandstand":
				print("crowd: %s %d figures at %s" % [cr.name, cr.total, cr._cells.values()[0][0]])
	var entries: Array = _race.entries
	# Hotspots: battles first, then the leader, then the player.
	_hot.clear()
	var order: Array = entries.filter(func(e) -> bool: return e.car != null and is_instance_valid(e.car) and not e.finished)
	order.sort_custom(func(a, b) -> bool: return a.progress > b.progress)
	if racing:
		for k in range(1, order.size()):
			var a: Car = order[k - 1].car
			var b: Car = order[k].car
			var gap: float = order[k - 1].progress - order[k].progress
			if gap < maxf(b.linear_velocity.length(), 10.0) * BATTLE:
				_push_hot(b, 1.0)
	if not order.is_empty():
		_push_hot(order[0].car, 1.0)
	var pl = _race.get("player")
	if pl != null and pl.car != null and is_instance_valid(pl.car):
		_push_hot(pl.car, 0.8)
	# Incidents (mid-race only: not on the grid, not after the flag).
	for inc: Array in _incidents:
		inc[1] -= SCAN
	_incidents = _incidents.filter(func(inc: Array) -> bool: return inc[1] > 0.0 or inc[2] > 0.0)
	var line = _race.circuit.line if _race.circuit else null
	for e in entries:
		var car: Car = e.car
		if car == null or not is_instance_valid(car):
			continue
		var p := car.global_position
		var prev: Vector3 = _last.get(car, p)
		_last[car] = p
		if not racing or e.finished or _race.race_time < 4.0 or e.lap < 1 or line == null:
			continue
		var vel := (p - prev) / SCAN # works for network puppets too
		var spd := vel.length()
		var fwd := -car.global_basis.z
		var spun := spd > 4.0 and fwd.dot(vel / spd) < 0.35
		var reset := spd > 120.0 # teleported (respawn): the incident was where it left
		if spd < CRAWL or spun or reset:
			var at := prev if reset else p
			var i: int = line.closest_index(at, e.index)
			_flag(line.point_ahead(i, line.length - YELLOW_BACK), at)
	# Chequered flag from the leader's final lap on.
	var final := false
	for e in entries:
		final = final or e.finished or (racing and e.lap >= int(_race.laps))
	if final and _chequer == 0.0 and OS.get_cmdline_user_args().has("--debug-crowd"):
		print("crowd: chequered flag at %s" % _finish)
	_chequer = move_toward(_chequer, 1.0 if final else 0.0, SCAN * 2.0)


func _push_hot(car: Car, w: float) -> void:
	if _hot.size() >= HOT.size():
		return
	for h: Array in _hot:
		if (h[0] as Car).global_position.distance_to(car.global_position) < 30.0:
			h[1] = maxf(h[1], w)
			return
	_hot.append([car, w])


func _flag(centre: Vector3, at: Vector3) -> void:
	for inc: Array in _incidents:
		if (inc[0] as Vector3).distance_to(centre) < 40.0:
			inc[1] = SETTLE
			return
	if _incidents.size() < YEL.size():
		_incidents.append([centre, SETTLE, 0.0])
	if OS.get_cmdline_user_args().has("--debug-crowd"):
		print("crowd: yellow at %s" % at)
