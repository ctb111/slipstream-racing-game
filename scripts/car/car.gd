class_name Car
extends RigidBody3D
## Arcade-sim car: raycast suspension, simplified Pacejka tire model,
## rear-wheel drive with a torque curve and a 5-speed gearbox.
##
## Driving inputs are plain fields (throttle / brake / steer_input / handbrake)
## so a network peer or AI can drive the car exactly like the local player.

# --- Chassis (roughly a late-70s rear-engined 911 Turbo) ---
@export var car_mass := 1300.0
@export var com_offset := Vector3(0.0, -0.2, 0.25) # +Z is rear: rear-biased weight
@export var axle_front_z := -1.13
@export var axle_rear_z := 1.14
@export var half_track := 0.74
@export var paint_color := Color(0.48, 0.045, 0.035) # muted Signal Red

# --- Suspension ---
@export var wheel_radius := 0.32
@export var suspension_travel := 0.30
@export var spring_front := 36000.0
@export var spring_rear := 48000.0
@export var damper_bump := 3000.0
@export var damper_rebound := 4200.0
@export var anti_roll_front := 14000.0
@export var anti_roll_rear := 7000.0

# --- Tires ---
@export var tire_grip := 1.4 # arcade-sim: grippier than a real 1975 tyre
@export var pacejka_b := 12.0
@export var pacejka_c := 1.4
@export var handbrake_grip_mult := 0.33
@export var drift_rear_grip := 0.72 ## rear side grip while power-drifting (wheelspin eats grip)
@export var drift_max_angle := 38.0 ## stability assist lets drifts go this far before catching

# --- Steering ---
@export var max_steer_deg := 34.0
@export var high_speed_steer_deg := 6.0
@export var steer_speed := 6.0
@export var steer_return := 9.0

# --- Engine / gearbox ---
@export var idle_rpm := 900.0
@export var redline_rpm := 7000.0
@export var gear_ratios := PackedFloat32Array([3.18, 2.06, 1.49, 1.16, 0.92])
@export var reverse_ratio := 3.2
@export var final_drive := 3.9
@export var drivetrain_eff := 0.85
@export var shift_time := 0.12
@export var automatic := true
var torque_rpm: Array = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0]
var torque_nm: Array = [330.0, 400.0, 470.0, 530.0, 545.0, 515.0, 440.0]
@export var model_id := CarCatalog.DEFAULT ## which car (see CarCatalog); set before adding to the tree
var drivetrain := "RWD"
const ENGINE_BRAKE_NM := 45.0

# --- Brakes / aero ---
@export var brake_force := 23000.0
@export var brake_bias_front := 0.7 ## static split; EBD moves it towards the loaded axle
@export var brake_ebd := 0.8 ## 0 = fixed bias, 1 = each wheel's brake follows its load
@export var brake_grip := 1.06 ## arcade: tyres hold this much more grip braking than cornering
@export var handbrake_force := 2600.0
@export var drag_coef := 0.40
@export var downforce_coef := 0.25
@export var rolling_resistance := 0.015

# --- Driver assists: invisible help so it's drivable on a keyboard (per-player toggles later) ---
@export var assist_abs := true ## brakes never lock; you can steer while braking
@export var assist_tc := true ## limits wheelspin so the tail doesn't step out on throttle
@export var assist_stability := true ## lets the car slide but catches a spin
@export var assist_countersteer := 0.6 ## front wheels help align with the direction of travel (0 = off)
@export var assist_steer_limit := true ## full lock = the grippiest angle for the current speed
@export var turn_assist := 1.0 ## holding a steer key keeps tightening the turn, arcade style (0 = off)

# --- Conditions (set by the race's Weather) ---
static var weather_road_grip := 1.0 ## multiplier on tarmac grip (wet / snow)
static var weather_off_grip := 1.0 ## multiplier on grass / gravel grip
static var headlights := false ## lamps on in storms and snow
static var night := false ## night race: full beams, tail lamps on (CarLights)
static var lamps_on := true ## changeable weather switches built lamps on/off (Weather)

# --- Controls (written by player input, network or AI) ---
var throttle := 0.0
var brake := 0.0
var steer_input := 0.0
var handbrake := false
var player_controlled := true
var remote := false ## driven by another machine: we only show what it sends
var net_velocity := Vector3.ZERO
var _net_states: Array = [] ## [receive time (s), PackedFloat32Array]
var _net_steer := 0.0
var _net_braking := false
var draft := 1.0 ## drag multiplier; < 1 when slipstreaming another car (set by the race)
var locked := false ## on the grid: brakes held, engine can still be revved

# --- Read-only state for HUD / camera / audio ---
var steer := 0.0
var gear := 1 # -1 reverse, 0 neutral, 1..n forward
var rpm := 900.0
var speed := 0.0 # signed forward speed, m/s
var wheels: Array[Wheel] = []

var _shift_timer := 0.0
var drifting := false ## handbrake-initiated slide being held with throttle
var body_slip := 0.0 ## angle between nose and travel direction, radians (+ = travelling right of the nose)
var _drift_timer := 0.0
var _reverse_armed := false
var _stopped_braking := 0.0 ## seconds held on the brake while (nearly) stopped
const REVERSE_HOLD := 0.35
## Turn assist: cornering force it asks for, in multiples of tire_grip (the
## tyres give ~1.0, ~1.4 with a held key; more than that only scrubs speed).
const LAT_ASK_LOW := 1.15
const LAT_ASK_HIGH := 1.05
const LAT_ASK_HOLD := 0.25
var _blocked_t := 0.0 ## > 0 shortly after a crash or while stuck against something
var _prev_speed := 0.0
var _steer_hold := 0.0 ## 0..1, how long a steer key has been held near full lock
var _assist_yaw := 0.0 ## yaw rate the turn assist is aiming for (rad/s, + = left)
var assist_max_yaw := 0.0 ## yaw rate full steer asks for this tick (the AI steers by it)
var _peak_slip := 0.17 # tire slip angle with the most grip, from the Pacejka curve
var _yaw_inertia := 2400.0
var _brake_light_mat: BaseMaterial3D
var _model_offset := Vector3.ZERO
var lights: CarLights ## lamps, when they are on


class Wheel:
	var mount: Vector3 # top of suspension, car-local
	var front: bool
	var driven: bool
	var grounded := false
	var compression := 0.0
	var prev_compression := 0.0
	var arb_force := 0.0
	var load := 0.0
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var surface_grip := 1.0
	var surface_drag := 0.0
	var long_speed := 0.0
	var slip := 0.0 # 0 = gripping, >0 = sliding (for skid sound/marks later)
	var pivot: Node3D # steers + moves with suspension
	var spinner: Node3D # rolls


func _ready() -> void:
	_apply_preset()
	mass = car_mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	continuous_cd = true
	can_sleep = false
	# Engine default damping acts like huge hidden drag; our aero model replaces it.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	# Scrape along walls and other cars instead of grabbing onto them.
	var body_mat := PhysicsMaterial.new()
	body_mat.friction = 0.12
	body_mat.bounce = 0.0
	physics_material_override = body_mat
	_build_body()
	_build_wheels()
	add_child(TireFx.new())
	add_child(CarDirt.new()) # dirt / mud / snow / water build-up (materials + sim)
	add_child(CarAudio.new())
	add_child(CarFx.new()) # backfire flames, brake glow, sparks, splashes
	_peak_slip = tan(PI / (2.0 * pacejka_c)) / pacejka_b


func _physics_process(dt: float) -> void:
	if remote:
		_remote_step(dt)
		return
	if player_controlled:
		_read_local_input(dt)
	if locked:
		# Neutral with the brakes on: the engine revs freely, the car stays put.
		gear = 0
		brake = 1.0
		handbrake = true
	elif gear == 0 and automatic:
		gear = 1
	var b := global_basis
	speed = linear_velocity.dot(-b.z)
	_update_steering(dt)
	_update_drift(dt, b)
	_update_gearbox(dt)
	var drive := _engine_drive_force(dt)
	_suspension(dt, b.y)
	_tires(dt, b, drive)
	_stability(b)
	_arcade_grip(dt, b)
	_aero(b)
	_update_visuals(dt, steer_angle(), _brake_amount() > 0.05 or handbrake)


func reset_to(xform: Transform3D) -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xform)
	global_transform = xform
	reset_physics_interpolation()
	gear = 1
	for w in wheels:
		w.grounded = false
		w.compression = 0.0


func current_max_steer() -> float:
	var lock := deg_to_rad(max_steer_deg)
	if not assist_steer_limit:
		var t := sqrt(clampf(absf(speed) / 45.0, 0.0, 1.0))
		return deg_to_rad(lerpf(max_steer_deg, high_speed_steer_deg, t))
	# Wheel angle for the tightest circle the tires can hold at this speed,
	# plus the slip angle where the front tires grip best. More lock than that
	# only scrubs speed, so a keyboard tap never asks for more than the car has.
	var v := maxf(absf(speed), 1.0)
	var tightest_radius := v * v / (tire_grip * 9.81)
	var geometric := atan((axle_rear_z - axle_front_z) / tightest_radius)
	# At 200+ the front never asks for its full peak slip in one go: precise, not darty.
	var slip_use := (1.35 + 0.6 * _steer_hold * turn_assist) * lerpf(1.0, 0.4, _high_speed_t())
	return minf(lock, geometric + _peak_slip * slip_use)


func set_assists(on: bool) -> void:
	assist_abs = on
	assist_tc = on
	assist_stability = on
	assist_countersteer = 0.6 if on else 0.0
	assist_steer_limit = on
	turn_assist = 1.0 if on else 0.0


## Space starts a drift; holding throttle while sliding keeps it alive.
## Lifting off (or straightening up) ends it and the normal assists return.
func _update_drift(dt: float, b: Basis) -> void:
	var v := linear_velocity
	body_slip = atan2(v.dot(b.x), v.dot(-b.z)) if speed > 3.0 else 0.0
	if handbrake and speed > 8.0:
		_drift_timer = 0.8
	elif _drift_timer > 0.0 and absf(body_slip) > deg_to_rad(6.0) and throttle > 0.35:
		_drift_timer = 0.5
	else:
		_drift_timer = maxf(_drift_timer - dt, 0.0)
	drifting = _drift_timer > 0.0 and speed > 6.0


## Actual front wheel angle (radians, + = right), including the countersteer assist.
func steer_angle() -> float:
	var angle := steer * current_max_steer()
	if assist_countersteer > 0.0 and speed > 5.0:
		# Only in real slides: normal cornering slip (a few degrees) is left alone,
		# otherwise the assist fights every turn and the steering feels dead.
		var amount := minf(assist_countersteer * 1.35, 0.9) if drifting else assist_countersteer
		var deadzone := deg_to_rad(2.0 if drifting else 6.0)
		var slide := signf(body_slip) * maxf(absf(body_slip) - deadzone, 0.0)
		angle += clampf(slide, -0.5, 0.5) * amount
	var lock := deg_to_rad(max_steer_deg)
	return clampf(angle, -lock, lock)


# ---------------------------------------------------------------- input

func _read_local_input(dt: float) -> void:
	# Keys are all-or-nothing; ramp them like a foot would so the rear-engined
	# car doesn't get a 0-100% throttle stab (gamepad triggers pass through smoothly).
	var gas := Input.get_action_strength("accelerate")
	var stop := Input.get_action_strength("brake")
	throttle = move_toward(throttle, gas, (8.0 if gas > throttle else 14.0) * dt)
	brake = move_toward(brake, stop, (20.0 if stop > brake else 14.0) * dt)
	steer_input = Input.get_axis("steer_left", "steer_right")
	handbrake = Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("toggle_gearbox"):
		automatic = not automatic
	if Input.is_action_just_pressed("shift_up") and gear < gear_ratios.size():
		_set_gear(gear + 1)
	if Input.is_action_just_pressed("shift_down") and gear > -1:
		_set_gear(gear - 1)


func _update_steering(dt: float) -> void:
	var returning := absf(steer_input) < absf(steer) or signf(steer_input) != signf(steer)
	# Speed-sensitive steering: quick hands up to ~55 km/h, then the wheel winds
	# on more gently towards 200+ so a key tap is a lane change, not a lurch.
	# Straightening up stays quick at any speed (that's what catches a car).
	var hs := _high_speed_t()
	var pace := lerpf(1.7, 0.4, hs) if not returning else lerpf(1.7, 1.1, hs)
	steer = move_toward(steer, steer_input, (steer_return if returning else steer_speed) * pace * dt)
	if absf(steer_input) > 0.8:
		_steer_hold = move_toward(_steer_hold, 1.0, dt / lerpf(0.45, 0.9, hs))
	else:
		_steer_hold = move_toward(_steer_hold, 0.0, dt * 3.0)


## 0 at town speeds, 1 from ~200 km/h: how "motorway calm" the steering is.
func _high_speed_t() -> float:
	return clampf((absf(speed) - 15.0) / 40.0, 0.0, 1.0)


# ---------------------------------------------------------------- drivetrain

func _set_gear(g: int) -> void:
	if g == gear:
		return
	gear = g
	_shift_timer = shift_time if g > 0 else 0.0


func _ratio(g: int) -> float:
	if g > 0:
		return gear_ratios[g - 1]
	if g < 0:
		return -reverse_ratio
	return 0.0


func _rpm_for_gear(g: int) -> float:
	return absf(speed) / wheel_radius * absf(_ratio(g)) * final_drive * 60.0 / TAU


func _gas() -> float:
	return brake if gear < 0 else throttle


func _brake_amount() -> float:
	return throttle if gear < 0 else brake


func _update_gearbox(dt: float) -> void:
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	if not automatic or locked:
		return
	# Classic arcade auto-reverse: at a standstill, a fresh brake press backs up
	# straight away; keeping the brake held (stopped at a hairpin, or pinned
	# against a wall after a crash) backs up after a short pause.
	if speed > 3.0:
		_reverse_armed = false
	elif absf(speed) < 0.8 and brake < 0.1:
		_reverse_armed = true # stopped and let go of the brake: next press backs up
	# A crash (sudden stop) or being stuck with the throttle on arms the
	# hold-to-reverse; an ordinary stop with the brake held stays put.
	if (absf(_prev_speed) - absf(speed)) / maxf(dt, 0.001) > 25.0: # > 2.5 g of sudden slowing
		_blocked_t = 2.5
	elif throttle > 0.3 and absf(speed) < 1.5:
		_blocked_t = maxf(_blocked_t, 1.5) # driving into something and not moving
	_prev_speed = speed
	_blocked_t = maxf(_blocked_t - dt, 0.0)
	if absf(speed) < 1.0 and brake > 0.3 and throttle < 0.1:
		_stopped_braking += dt
	else:
		_stopped_braking = 0.0
	if _stopped_braking > REVERSE_HOLD and _blocked_t > 0.0:
		_reverse_armed = true
	if gear > 0 and speed < 1.0 and brake > 0.3 and throttle < 0.1 and _reverse_armed:
		_set_gear(-1)
	elif gear <= 0 and speed > -0.8 and throttle > 0.3 and brake < 0.1:
		_set_gear(1)
	elif gear > 0 and _shift_timer == 0.0:
		if rpm > redline_rpm * 0.95 and gear < gear_ratios.size() and throttle > 0.1:
			_set_gear(gear + 1)
		elif gear > 1 and rpm < redline_rpm * 0.5 and _rpm_for_gear(gear - 1) < redline_rpm * 0.78:
			_set_gear(gear - 1)


func _torque_at(r: float) -> float:
	if r <= torque_rpm[0]:
		return torque_nm[0]
	for i in range(1, torque_rpm.size()):
		if r <= torque_rpm[i]:
			var t: float = (r - torque_rpm[i - 1]) / (torque_rpm[i] - torque_rpm[i - 1])
			return lerpf(torque_nm[i - 1], torque_nm[i], t)
	return torque_nm[-1]


func _engine_drive_force(dt: float) -> float:
	var gas := _gas()
	var target: float
	if gear == 0:
		target = lerpf(idle_rpm, redline_rpm, gas) # free revving in neutral
	elif _shift_timer > 0.0:
		target = maxf(_rpm_for_gear(gear), idle_rpm) # clutch in: revs fall to the new gear
	else:
		# Clutch slip lets the engine rev above wheel speed when launching.
		var launch := idle_rpm + gas * 2400.0 * clampf(1.0 - absf(speed) / 12.0, 0.0, 1.0)
		target = maxf(_rpm_for_gear(gear), launch)
	rpm = clampf(lerpf(rpm, target, 1.0 - exp(-dt * 14.0)), idle_rpm * 0.8, redline_rpm * 1.02)

	if gear == 0 or _shift_timer > 0.0:
		return 0.0
	var torque: float
	if gas < 0.05:
		# Engine braking only resists motion in the gear's direction; fades out at a standstill.
		var moving := clampf(speed * signf(_ratio(gear)) / 2.0, 0.0, 1.0)
		torque = -ENGINE_BRAKE_NM * rpm / redline_rpm * moving
	elif rpm >= redline_rpm:
		torque = 0.0 # limiter
	else:
		torque = _torque_at(rpm) * gas
	return torque * _ratio(gear) * final_drive * drivetrain_eff / wheel_radius


# ---------------------------------------------------------------- suspension

func _suspension(dt: float, up: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var ray_len := suspension_travel + wheel_radius
	for w in wheels:
		var origin := global_transform * w.mount
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * ray_len, 1)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		var was_grounded := w.grounded
		w.prev_compression = w.compression
		if hit.is_empty():
			w.grounded = false
			w.compression = 0.0
			w.load = 0.0
			continue
		w.grounded = true
		w.compression = ray_len - origin.distance_to(hit.position)
		if not was_grounded:
			w.prev_compression = w.compression
		w.contact = hit.position
		w.normal = hit.normal
		var col: Object = hit.collider
		w.surface_grip = col.get_meta("grip", 1.0) if col else 1.0
		w.surface_drag = col.get_meta("drag", 0.0) if col else 0.0

	_anti_roll(wheels[0], wheels[1], anti_roll_front)
	_anti_roll(wheels[2], wheels[3], anti_roll_rear)

	for w in wheels:
		if not w.grounded:
			continue
		var comp_vel := (w.compression - w.prev_compression) / dt
		var k := spring_front if w.front else spring_rear
		var damper := damper_bump if comp_vel > 0.0 else damper_rebound
		var f := k * w.compression + damper * comp_vel + w.arb_force
		var bump_start := suspension_travel * 0.85
		if w.compression > bump_start:
			f += (w.compression - bump_start) * k * 8.0
		w.load = maxf(f, 0.0)
		apply_force(up * w.load, w.contact - global_position)


func _anti_roll(left: Wheel, right: Wheel, stiffness: float) -> void:
	var diff := left.compression - right.compression
	left.arb_force = diff * stiffness if left.grounded else 0.0
	right.arb_force = -diff * stiffness if right.grounded else 0.0


# ---------------------------------------------------------------- tires

func _pacejka(slip_angle: float) -> float:
	return sin(pacejka_c * atan(pacejka_b * slip_angle))


func _tires(dt: float, b: Basis, drive_total: float) -> void:
	var up := b.y
	var com_world := global_position + b * center_of_mass
	var mass_share := mass * 0.25
	var steer_rad := steer_angle()
	var brake_in := _brake_amount()
	# EBD: share the brake force out by wheel load (weight moves forward as you
	# brake), keeping the rears a touch under their share so they never lock
	# first: hard braking stays straight instead of the tail stepping out.
	var load_sum := 0.0
	for w in wheels:
		load_sum += w.load
	for w in wheels:
		w.slip = 0.0
		if not w.grounded:
			continue
		var dir := -b.z
		if w.front:
			dir = dir.rotated(up, -steer_rad)
		var n := w.normal
		var fwd := (dir - n * dir.dot(n)).normalized()
		var right := fwd.cross(n).normalized()
		var v := linear_velocity + angular_velocity.cross(w.contact - com_world)
		var vl := v.dot(fwd)
		var vs := v.dot(right)
		w.long_speed = vl

		var grip := tire_grip * w.surface_grip * (weather_road_grip if w.surface_grip >= 0.9 else weather_off_grip)
		var lat_grip := 1.0
		if not w.front:
			if handbrake:
				lat_grip = handbrake_grip_mult
			elif drifting and throttle > 0.3:
				lat_grip = drift_rear_grip
		if turn_assist > 0.0 and not handbrake and not drifting:
			lat_grip *= 1.0 + 0.4 * _steer_hold * turn_assist # held turns bite harder
		var max_f := w.load * grip

		# Lateral: Pacejka curve, but never more than what cancels the slide
		# this step (keeps low-speed behaviour stable instead of jittery).
		var slip_angle := atan2(vs, maxf(absf(vl), 1.0))
		var f_lat := -_pacejka(slip_angle) * max_f * lat_grip
		var cancel := -vs * mass_share / dt
		if absf(cancel) < absf(f_lat):
			f_lat = cancel

		# Grip left over for accelerating/braking after cornering (friction circle),
		# with a floor so assists never kill drive or brakes completely.
		# Braking uses a friction ellipse: longitudinal capacity is brake_grip x lateral.
		var lg := brake_grip if brake_in > 0.05 and not (handbrake and not w.front) else 1.0
		var long_room := sqrt(maxf(max_f * max_f - f_lat * f_lat, 0.0)) * lg

		# Longitudinal: drive, brakes, rolling / off-road drag.
		var f_long := drive_total * 0.5 if w.driven else 0.0
		if assist_tc and w.driven and not drifting:
			var tc_cap := maxf(long_room, max_f * 0.35) * 0.95
			f_long = clampf(f_long, -tc_cap, tc_cap)
		var share := 0.5 * (brake_bias_front if w.front else 1.0 - brake_bias_front)
		if load_sum > 1.0:
			share = lerpf(share, w.load / load_sum * (1.0 if w.front else 0.9), brake_ebd)
		var brk := brake_force * brake_in * share
		if assist_abs:
			brk = minf(brk, maxf(long_room, max_f * 0.3 * lg))
		if handbrake and not w.front:
			brk += handbrake_force * 0.5
		brk += w.load * (rolling_resistance + w.surface_drag)
		f_long -= signf(vl) * minf(brk, absf(vl) * mass_share / dt)

		# Friction circle: combined grip can't exceed what the tire has.
		var total := Vector2(f_long / lg, f_lat)
		var total_len := total.length()
		if max_f <= 0.001:
			continue # wheel touching but unloaded: no grip at all
		if total_len > max_f:
			w.slip = total_len / max_f - 1.0
			total *= max_f / total_len
		total.x *= lg
		w.slip = maxf(w.slip, absf(slip_angle) - 0.2)
		apply_force(fwd * total.x + right * total.y, w.contact - global_position)


## Stability control: cap the yaw rate at what the tires can sustain, and
## nudge the nose back towards the direction of travel in a big slide.
func _stability(b: Basis) -> void:
	if not assist_stability or speed < 4.0:
		return
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	if state and state.inverse_inertia.y > 0.0:
		_yaw_inertia = 1.0 / state.inverse_inertia.y
	var up := b.y
	var yaw := angular_velocity.dot(up)
	_turn_assist(up)
	# Braking (not drifting): tighter yaw cap and an earlier catch, so a hard
	# stop into a corner turns where it's pointed and never swaps ends.
	var braking := _brake_amount() > 0.2 and not drifting
	var limit := maxf(tire_grip * 9.81 / speed * (1.8 if drifting else (1.1 if braking else 1.3)), absf(_assist_yaw) * 1.15)
	var excess := absf(yaw) - limit
	if excess > 0.0:
		apply_torque(-up * signf(yaw) * excess * _yaw_inertia * 8.0)
	if handbrake:
		return # let the handbrake rotate the car
	var catch_angle := deg_to_rad(drift_max_angle if drifting else (5.0 if braking else 12.0))
	var over := absf(body_slip) - catch_angle
	if over > 0.0:
		apply_torque(-up * signf(body_slip) * over * _yaw_inertia * 10.0)


## Arcade turn assist: help the car rotate towards the yaw rate the driver is
## asking for (more the longer the key is held), never against a slide.
## Arcade steering: the stick / keys set how fast the car rotates (more the
## longer a key is held), and the car is steered to that rate directly.
## Grip (see _arcade_grip) then makes the car go where its nose points.
func _turn_assist(up: Vector3) -> void:
	_assist_yaw = 0.0
	if turn_assist <= 0.0 or handbrake or drifting or _grounded_count() < 3:
		return
	var v := maxf(speed, 4.0)
	# Rotation rate for an arcade-believable cornering force (~1.7-2.4 g on a
	# dry road, less in the wet / snow), more the longer the key is held.
	var surface := weather_road_grip if wheels[2].surface_grip >= 0.9 else weather_off_grip
	# Most of the turn comes at once (crisp turn-in); holding adds a little more.
	# Fast, the ask is a bit lower so sweepers stay planted, and heavy braking
	# leaves the tyres less to turn with, so it asks less again (no rotation).
	var hs := _high_speed_t()
	var lat_g := (lerpf(LAT_ASK_LOW, LAT_ASK_HIGH, hs) + LAT_ASK_HOLD * _steer_hold) * tire_grip * 9.81 * surface
	lat_g *= 1.0 - 0.3 * clampf(_brake_amount(), 0.0, 1.0)
	var max_yaw := minf(2.0, lat_g / v)
	assist_max_yaw = max_yaw
	_assist_yaw = -steer * max_yaw * turn_assist
	var yaw := angular_velocity.dot(up)
	var gain := lerpf(9.0, 6.0, hs)
	apply_torque(up * clampf((_assist_yaw - yaw) * gain, -12.0, 12.0) * _yaw_inertia * turn_assist)


## Arcade grip: bleed off sideways velocity so the car follows its nose
## instead of sliding wide under steering or braking. Off in drifts.
func _arcade_grip(dt: float, b: Basis) -> void:
	if turn_assist <= 0.0 or handbrake or drifting or speed < 1.5 or _grounded_count() < 3:
		return
	# Turn the horizontal velocity towards the nose, keeping its speed.
	var v := linear_velocity
	var flat := Vector3(v.x, 0.0, v.z)
	var spd := flat.length()
	var nose := -b.z
	nose.y = 0.0
	if spd < 0.5 or nose.length() < 0.1:
		return
	nose = nose.normalized() * signf(flat.dot(nose))
	var surface := weather_road_grip if wheels[2].surface_grip >= 0.9 else weather_off_grip
	var t := 1.0 - exp(-dt * 5.0 * surface)
	var turned := flat.normalized().slerp(nose, t) * spd
	linear_velocity = Vector3(turned.x, v.y, turned.z)


func _grounded_count() -> int:
	var c := 0
	for w in wheels:
		if w.grounded:
			c += 1
	return c


func _aero(b: Basis) -> void:
	var v := linear_velocity
	apply_central_force(-v * v.length() * drag_coef * draft)
	apply_central_force(-b.y * downforce_coef * speed * speed)


# ---------------------------------------------------------------- visuals

func _update_visuals(dt: float, steer_rad: float, braking: bool) -> void:
	for w in wheels:
		var ext := suspension_travel - w.compression if w.grounded else suspension_travel
		w.pivot.position = w.mount + Vector3.DOWN * ext
		if w.front:
			w.pivot.rotation.y = -steer_rad
		var spin_speed := w.long_speed / wheel_radius
		if w.driven and w.slip > 0.0 and _gas() > 0.5:
			spin_speed += signf(_ratio(gear)) * w.slip * 40.0 # visible wheelspin
		w.spinner.rotate_x(-spin_speed * dt)
	_brake_light_mat.emission_energy_multiplier = (6.0 if braking else 1.6) if night else (4.0 if braking else 0.25)
	if lights:
		lights.set_braking(braking)
		if lights.visible != lamps_on:
			lights.set_on(lamps_on)


func _collider(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	add_child(cs)


## The catalog's physics preset for this model: mass, engine, gearing, grip...
func _apply_preset() -> void:
	var preset := CarCatalog.physics(model_id)
	for k in preset:
		if k == "top_speed_kmh":
			continue
		if k in self:
			set(k, preset[k])


const REST_DROP := 0.225 ## wheel centres sit this far below their mounts with the car at rest


func _build_body() -> void:
	var visual := Node3D.new()
	visual.name = "Body"
	add_child(visual)
	if CarModel.available(model_id):
		_build_model_body(visual)
		return
	# Fallback: the procedural body.
	_collider(Vector3(1.74, 0.52, 4.4), Vector3(0, -0.1, 0.02))
	_collider(Vector3(1.36, 0.42, 1.9), Vector3(0, 0.38, 0.3))
	_brake_light_mat = CarBodyBuilder.build(visual, paint_color)


## Real 930 model: fit axles, track and wheel size to it, recolour its paint.
func _build_model_body(visual: Node3D) -> void:
	var d := CarModel.data(model_id)
	var fz := 0.0
	var rz := 0.0
	var tx := 0.0
	var hub_y := 0.0
	for w in d.wheels:
		if w.front:
			fz += w.centre.z * 0.5
		else:
			rz += w.centre.z * 0.5
		tx += absf(w.centre.x) * 0.25
		hub_y += w.centre.y * 0.25
	var mid_z := (fz + rz) * 0.5
	axle_front_z = fz - mid_z
	axle_rear_z = rz - mid_z
	half_track = tx
	wheel_radius = d.wheel_radius
	_model_offset = Vector3(0, -REST_DROP - hub_y, -mid_z)

	var mi := MeshInstance3D.new()
	mi.name = "Model"
	mi.mesh = d.body
	mi.position = _model_offset
	for i in d.surface_mats.size():
		var m: Material = d.surface_mats[i]
		if i == d.paint_surface and m is BaseMaterial3D:
			var paint: BaseMaterial3D = m.duplicate()
			paint.albedo_color = paint_color
			# Deep, glossy showroom paint: a little metallic flake under a hard clearcoat.
			paint.metallic = 0.38
			paint.roughness = 0.22
			paint.clearcoat_enabled = true
			paint.clearcoat = 1.0
			paint.clearcoat_roughness = 0.03
			m = paint
		elif i == d.brake_surface and m is BaseMaterial3D:
			var lamp: BaseMaterial3D = m.duplicate()
			lamp.emission_enabled = true
			lamp.emission = Color(1.0, 0.05, 0.03)
			lamp.emission_energy_multiplier = 0.25
			_brake_light_mat = lamp
			m = lamp
		mi.set_surface_override_material(i, m)
	visual.add_child(mi)
	# Shadows come from one merged proxy (body + wheels at rest): one draw call
	# per shadow split instead of one per surface (8 cars: hundreds a frame).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := MeshInstance3D.new()
	sh.name = "ShadowProxy"
	sh.mesh = d.shadow
	sh.position = _model_offset
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	visual.add_child(sh)
	if _brake_light_mat == null:
		_brake_light_mat = StandardMaterial3D.new()
	if headlights:
		var box0: AABB = d.body_aabb
		lights = CarLights.build(self, mi, d, axle_front_z - 1.1, box0.end.z + _model_offset.z, _model_offset.y + 0.7, night)

	# Collision: a lower tub and a cabin, sized from the model.
	# Ground under the car: hubs sit REST_DROP below the mounts, tyres touch the
	# road one radius lower (models differ in where their own origin is).
	var ground := -REST_DROP - wheel_radius
	var box: AABB = d.body_aabb
	var len := box.size.z * 0.96
	var wid := minf(box.size.x, 1.8) * 0.95
	var z_mid := box.get_center().z + _model_offset.z
	# The body box starts 0.3 m up: the wheels (raycasts) handle the ground, the
	# box is for walls and other cars. Lower, it caught on kerb edges and steps
	# when driving back onto the track from the grass.
	_collider(Vector3(wid, 0.49, len), Vector3(0, ground + 0.30 + 0.245, z_mid))
	_collider(Vector3(wid * 0.76, 0.42, len * 0.42), Vector3(0, ground + 0.79 + 0.21, z_mid + len * 0.04))


func _build_wheels() -> void:
	var model := CarModel.available(model_id)
	var model_wheels: Array = CarModel.data(model_id).wheels if model else []
	var layout := [
		[-half_track, axle_front_z, true],
		[half_track, axle_front_z, true],
		[-half_track, axle_rear_z, false],
		[half_track, axle_rear_z, false],
	]
	for l in layout:
		var w := Wheel.new()
		w.mount = Vector3(l[0], 0.0, l[1])
		w.front = l[2]
		w.driven = (not w.front) if drivetrain == "RWD" else (w.front if drivetrain == "FWD" else true)
		w.pivot = Node3D.new()
		w.pivot.position = w.mount + Vector3.DOWN * suspension_travel
		add_child(w.pivot)
		w.spinner = Node3D.new()
		w.pivot.add_child(w.spinner)
		var left: bool = l[0] < 0.0
		var found := false
		for mw in model_wheels:
			if mw.front == w.front and mw.left == left:
				var mi := MeshInstance3D.new()
				mi.mesh = mw.mesh
				for k in mw.mats.size():
					mi.set_surface_override_material(k, mw.mats[k])
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # in the body's ShadowProxy
				w.spinner.add_child(mi)
				found = true
		if not found:
			CarBodyBuilder.build_wheel(w.spinner, wheel_radius, 0.2 if w.front else 0.26, left)
		wheels.append(w)


# ---------------------------------------------------------------- network

const NET_DELAY := 0.1 ## render remote cars this far in the past so there's always data to interpolate


func velocity() -> Vector3:
	return net_velocity if remote else linear_velocity


## Turn this car into a puppet of another machine: no local physics, it just
## follows the stream of states (and other cars still collide with it).
func set_remote() -> void:
	remote = true
	player_controlled = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	# Puppets live on their own layer: local cars don't hit them as solid walls
	# (they're drawn slightly in the past); the race applies a soft push instead.
	collision_layer = 2
	collision_mask = 0


func net_pack() -> PackedFloat32Array:
	var q := global_basis.get_rotation_quaternion()
	var p := global_position
	var v := linear_velocity
	var a := angular_velocity
	var skid := 0.0
	for w in wheels:
		skid = maxf(skid, w.slip)
	return PackedFloat32Array([p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, a.x, a.y, a.z,
		steer_angle(), rpm, throttle, 1.0 if (_brake_amount() > 0.05 or handbrake) else 0.0, gear, speed,
		wheels[0].compression, wheels[1].compression, wheels[2].compression, wheels[3].compression,
		skid, 1.0 if drifting else 0.0])


func net_push(state: PackedFloat32Array) -> void:
	if state.size() < 25:
		return
	_net_states.append([Time.get_ticks_usec() / 1e6, state])
	if _net_states.size() > 30:
		_net_states.pop_front()


func _remote_step(dt: float) -> void:
	if _net_states.is_empty():
		return
	var t := Time.get_ticks_usec() / 1e6 - NET_DELAY
	# Drop states we're already past (keep one before t).
	while _net_states.size() > 2 and _net_states[1][0] <= t:
		_net_states.pop_front()
	var a: PackedFloat32Array = _net_states[0][1]
	var s := a
	var f := 0.0
	if _net_states.size() > 1 and _net_states[1][0] > _net_states[0][0]:
		f = clampf((t - _net_states[0][0]) / (_net_states[1][0] - _net_states[0][0]), 0.0, 1.0)
		s = _net_states[1][1]
	var pos := Vector3(a[0], a[1], a[2]).lerp(Vector3(s[0], s[1], s[2]), f)
	var qa := Quaternion(a[3], a[4], a[5], a[6])
	var qb := Quaternion(s[3], s[4], s[5], s[6])
	net_velocity = Vector3(a[7], a[8], a[9]).lerp(Vector3(s[7], s[8], s[9]), f)
	if _net_states.size() == 1:
		# Starved: extrapolate a little from the last known velocity.
		var age := clampf(t - _net_states[0][0], 0.0, 0.25)
		pos += net_velocity * age
	global_transform = Transform3D(Basis(qa.slerp(qb, f)), pos)
	_net_steer = lerpf(a[13], s[13], f)
	rpm = lerpf(a[14], s[14], f)
	throttle = s[15]
	_net_braking = s[16] > 0.5
	gear = int(s[17])
	speed = lerpf(a[18], s[18], f)
	drifting = s[24] > 0.5
	for i in 4:
		wheels[i].grounded = true
		wheels[i].compression = lerpf(a[19 + i], s[19 + i], f)
		wheels[i].long_speed = speed
		wheels[i].slip = s[23] if not wheels[i].front else 0.0
	_update_visuals(dt, _net_steer, _net_braking)
