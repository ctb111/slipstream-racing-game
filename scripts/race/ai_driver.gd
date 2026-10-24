class_name AIDriver
extends Node
## Drives its parent Car along the racing line with the same controls a player
## has (throttle / brake / steer), so bots obey the same physics and assists.

var line: RacingLine
var skill := 0.92 ## fraction of the ideal corner speed this driver dares
var enabled := false
var index := -1
var others: Array = [] ## every car in the race (set by the race)

var _car: Car
var _stuck_time := 0.0
var _rng := RandomNumberGenerator.new()
var _wobble := 0.0
var _pass_lat := 0.0 ## lateral lane while overtaking, blended in/out
var _pass_weight := 0.0
var _follow_speed := INF
var _held := false ## last tick a slower car ahead set our speed
var tier := -1 ## difficulty this bot was made for (debug stats)
static var debug_stats := false ## print early-race contacts (test runs)
var _race_t := 0.0
var launches := 0 ## airborne > 0.3 s (debug stats)
var _air_t := 0.0
var crashes := 0 ## hard impacts (debug stats)
var stuck_count := 0
var peak_lat_g := 0.0 ## highest cornering force held for ~0.5 s (debug stats)
var _lat_g := 0.0
var off_time := 0.0 ## seconds with the car's centre off the tarmac (debug stats)
var _was_blocked := false

signal stuck(car: Car)


func _ready() -> void:
	_car = get_parent()
	_car.player_controlled = false
	_rng.randomize()


func _physics_process(dt: float) -> void:
	if line == null:
		return
	index = line.closest_index(_car.global_position, index)
	if not enabled:
		return
	var v := maxf(_car.speed, 0.0)
	_race_t += dt

	# Steering: pure pursuit on a look-ahead point that moves out with speed.
	_wobble = lerpf(_wobble, _rng.randf_range(-1.0, 1.0), dt * 0.5) # small human imprecision
	var look := 6.0 + v * 0.36
	_racecraft(dt, v)
	var target := line.point_ahead(index, look) + line.rights[index] * _wobble * maxf(1.0 - skill, 0.0) * 6.0
	if _pass_weight > 0.01:
		target = target.lerp(line.lane_point(index, look, _pass_lat), _pass_weight)
	var local := _car.global_transform.affine_inverse() * target
	var angle := atan2(local.x, -local.z)
	if _car.turn_assist > 0.0 and _car.assist_max_yaw > 0.01 and v > 4.0:
		# The arcade steering sets a yaw rate: ask for exactly the path's
		# curvature (pure pursuit: 2 sin(angle) / distance) at this speed.
		var dist := maxf(Vector2(local.x, local.z).length(), 1.0)
		var yaw := 2.0 * sin(angle) / dist * v
		_car.steer_input = clampf(yaw / _car.assist_max_yaw, -1.0, 1.0)
	else:
		_car.steer_input = clampf(angle / maxf(_car.current_max_steer(), 0.05), -1.0, 1.0)

	# Speed: the slowest target just ahead (the profile already has the
	# braking zones; the short horizon covers pedal and tyre lag), by skill.
	var target_speed := INF
	var horizon := 2.0 + v * 0.15
	var m := 0.0
	while m <= horizon:
		target_speed = minf(target_speed, line.speed_ahead(index, m))
		m += 2.0
	target_speed *= skill
	# Weather changed since the line was planned: corner and brake to today's grip
	# (v ~ sqrt(grip) for both cornering and braking distance).
	target_speed *= sqrt(Car.weather_road_grip / line.built_grip)
	_held = _follow_speed < target_speed - 0.5
	target_speed = minf(target_speed, _follow_speed)
	# Back off if the car is already sliding.
	target_speed *= 1.0 - clampf(absf(_car.body_slip) - 0.1, 0.0, 0.3)
	# Off the road at walking pace (spun into gravel / grass, reset sideways):
	# always pull away and rejoin; no follow gap or corner limit may hold it at 0.
	if v < 10.0 and absf(line.lateral_of(_car.global_position, index)) > line.half_width + 2.0:
		target_speed = maxf(target_speed, 12.0)
	var err := target_speed - v
	if err > 0.0:
		_car.throttle = clampf(0.5 + err * 0.5, 0.0, 1.0)
		_car.brake = 0.0
	elif err > -0.4:
		_car.throttle = 0.0 # lift: engine braking trims the last bit
		_car.brake = 0.0
	else:
		_car.throttle = 0.0
		_car.brake = clampf(-err * 0.45, 0.0, 1.0)
	_car.handbrake = false

	_lat_g = lerpf(_lat_g, absf(_car.angular_velocity.y) * v / 9.81, dt * 2.0)
	peak_lat_g = maxf(peak_lat_g, _lat_g)
	if absf(line.lateral_of(_car.global_position, index)) > line.half_width + 2.1:
		off_time += dt
	if _car._grounded_count() == 0:
		_air_t += dt
	elif _air_t > 0.0:
		if _air_t > 0.3:
			launches += 1
			if debug_stats:
				print("launch %s t=%.1f air=%.2fs v=%.0f" % [get_parent().name, _race_t, _air_t, v * 3.6])
		_air_t = 0.0
	var blocked: bool = _car._blocked_t > 2.4
	if blocked and not _was_blocked:
		crashes += 1
		if debug_stats and _race_t < 30.0:
			print("early_hit %s t=%.1f v=%.0f" % [get_parent().name, _race_t, v * 3.6])
	_was_blocked = blocked
	# Stuck against something? Hand it to the race to put back on track.
	if v < 1.5:
		_stuck_time += dt
		if _stuck_time > 3.0:
			_stuck_time = 0.0
			stuck_count += 1
			stuck.emit(_car)
	else:
		_stuck_time = 0.0


## Look for traffic ahead: pull out to pass a slower car if there's room
## (the inside of the next corner by preference), otherwise follow it at a
## safe gap. Braver drivers (higher skill) pass with less room and follow
## closer; Hard drivers also cover the inside when someone is right behind.
func _racecraft(dt: float, v: float) -> void:
	_follow_speed = INF
	var aggr := clampf((skill - 0.80) / 0.30, 0.0, 1.0) # Easy 0, Medium 0.5, Hard 1
	# The opening lap's first corners: the pack is three-wide, so no dive-bombs.
	aggr *= clampf(_race_t / 25.0, 0.2, 1.0)
	var inv := _car.global_transform.affine_inverse()
	var fwd := -_car.global_basis.z
	var blocker: Car = null
	var blocker_gap := INF
	var beside_x := 0.0
	var chaser := false
	for other in others:
		if other == _car or not is_instance_valid(other):
			continue
		var local: Vector3 = inv * other.global_position
		var ahead := -local.z
		if ahead > 0.0 and ahead < 30.0 + v * 0.6 and absf(local.x) < 3.2 and ahead < blocker_gap:
			blocker = other
			blocker_gap = ahead
		elif absf(ahead) < 5.0 and absf(local.x) < 3.0:
			beside_x = local.x
		elif ahead < -5.0 and ahead > -14.0 and absf(local.x) < 3.0 and other.velocity().dot(fwd) > v + 0.5:
			chaser = true
	# Inside of the next corner (the racing line's side at the slowest point ahead).
	var apex_m := 0.0
	var apex_v := INF
	var m := 10.0
	while m < 90.0:
		var sv := line.speed_ahead(index, m)
		if sv < apex_v:
			apex_v = sv
			apex_m = m
		m += 10.0
	var corner_soon := apex_v < v * 0.85
	var inside := signf(line.lateral[(index + int(apex_m / (line.length / line.count()))) % line.count()])
	var want := 0.0
	if blocker:
		var their_v := blocker.velocity().dot(fwd)
		var closing := v - their_v
		# Closing in, close behind, or stuck behind someone slower: go for a gap.
		if closing > lerpf(1.0, 0.3, aggr) or blocker_gap < 12.0 or (_held and blocker_gap < 45.0):
			var their_lat := line.lateral_of(blocker.global_position, index)
			var left_room := their_lat + line.half_width
			var right_room := line.half_width - their_lat
			if _pass_weight < 0.1:
				# Commit to one side: the inside of a corner coming up, else the roomier side.
				var side := 1.0 if right_room > left_room else -1.0
				var need := lerpf(3.4, 2.6, aggr)
				if corner_soon and inside != 0.0 and (right_room if inside > 0.0 else left_room) > need:
					side = inside
				_pass_lat = their_lat + side * 3.5
			var room := right_room if _pass_lat > their_lat else left_room
			if room > lerpf(3.4, 2.6, aggr):
				want = 1.0
			# Never closer than a safe gap: brake down to their speed in the room left.
			var safe := 5.5 + maxf(their_v, 0.0) * lerpf(0.45, 0.2, aggr)
			var room_m := blocker_gap - safe
			var cap := sqrt(maxf(their_v, 0.0) ** 2 + 2.0 * 7.0 * maxf(room_m, 0.0)) if room_m > 0.0 else maxf(their_v - (safe - blocker_gap) * 0.5, 0.0)
			if want < 0.5 or _pass_weight < 0.6:
				_follow_speed = cap
	if beside_x != 0.0:
		# Someone alongside: keep a car's width away.
		_pass_lat = line.lateral_of(_car.global_position, index) - signf(beside_x) * 1.0
		want = maxf(want, 0.6)
	elif chaser and want == 0.0 and corner_soon and aggr > 0.6 and inside != 0.0:
		# Cover the inside line into the braking zone (one move, no weaving).
		_pass_lat = clampf(line.lateral_of(_car.global_position, index) + inside * 1.5, -line.half_width, line.half_width)
		want = 0.5
	_pass_weight = move_toward(_pass_weight, want, dt * (1.5 if want > _pass_weight else 0.4))
