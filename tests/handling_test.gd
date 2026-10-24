extends Node3D
## Headless handling test rig. Drives several cars on a flat asphalt pad with
## keyboard-style (digital) inputs and prints stability / response metrics.
##   godot --headless --path . res://tests/handling_test.tscn

const DURATION := 7.0
const SETTLE := 0.5

## name, start speed km/h, input function(t) -> [throttle, brake, steer, handbrake]
var scenarios := [
	["launch", 0.0, func(t): return [1.0, 0.0, 0.0, false]],
	["brake 100-0 straight", 100.0, func(t): return [0.0, 1.0 if t > 0.5 else 0.0, 0.0, false]],
	["full lock 80 steady", 80.0, func(t): return [0.45, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["full lock 140 steady", 140.0, func(t): return [0.6, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["turn 80 part-throttle", 80.0, func(t): return [0.3, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["turn 120 full-throttle", 120.0, func(t): return [1.0, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["lift-off mid-corner", 100.0, func(t): return [0.5 if t < 2.5 else 0.0, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["brake + turn from 130", 130.0, func(t): return [0.0, 1.0 if t > 0.5 else 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["slalom 100", 100.0, func(t): return [0.5, 0.0, (1.0 if int(t) % 2 == 0 else -1.0) if t > 0.5 else 0.0, false]],
	["corner exit 50 full-gas", 50.0, func(t): return [1.0 if t > 0.5 else 0.3, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["tap-steer 150", 150.0, func(t): return [0.6, 0.0, 1.0 if t > 0.5 and t < 0.8 else 0.0, false]],
	["full lock 160", 160.0, func(t): return [0.5, 0.0, -1.0 if t > 0.5 else 0.0, false]],
	["handbrake drift 80", 80.0, func(t): return [0.2 if t < 1.0 else 0.85, 0.0, 1.0 if t > 0.5 else 0.0, t > 0.5 and t < 0.9]],
	["drift then lift 80", 80.0, func(t): return [0.2 if t < 1.0 else (0.85 if t < 3.5 else 0.0), 0.0, 1.0 if t > 0.5 and t < 4.5 else 0.0, t > 0.5 and t < 0.9]],
	["handbrake turn 70", 70.0, func(t): return [0.4, 0.0, 1.0 if t > 0.5 else 0.0, t > 0.5 and t < 1.3]],
	# High-speed set (indices referenced by the KEY METRICS lines below).
	["brake 200-0 straight", 200.0, func(t): return [0.0, 1.0 if t > 0.5 else 0.0, 0.0, false]],
	["brake 200 + steer wobble", 200.0, func(t): return [0.0, 1.0 if t > 0.5 else 0.0, (0.25 if int(t * 2.0) % 2 == 0 else -0.25) if t > 0.7 and t < 3.5 else 0.0, false]],
	["brake into corner 180", 180.0, func(t): return [0.0, 1.0 if t > 0.5 and t < 2.5 else 0.0, 1.0 if t > 1.0 else 0.0, false]],
	["lane change 200", 200.0, func(t): return [0.8, 0.0, 1.0 if t > 0.5 and t < 0.85 else (-1.0 if t > 0.85 and t < 1.2 else 0.0), false]],
	["lane change 120", 120.0, func(t): return [0.6, 0.0, 1.0 if t > 0.5 and t < 0.85 else (-1.0 if t > 0.85 and t < 1.2 else 0.0), false]],
	["step steer 60", 60.0, func(t): return [0.35, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["step steer 120", 120.0, func(t): return [0.5, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["step steer 200", 200.0, func(t): return [0.8, 0.0, 1.0 if t > 0.5 else 0.0, false]],
	["sweeper 220 half-steer", 220.0, func(t): return [1.0, 0.0, 0.45 if t > 0.5 else 0.0, false]],
	["slide catch 120", 120.0, func(t): return [0.5 if t < 0.9 else 0.3, 0.0, 1.0 if t > 0.5 and t < 0.9 else 0.0, t > 0.5 and t < 0.8]],
]
const I_CATCH := 24
const I_BRAKE200 := 15
const I_WOBBLE := 16
const I_BRAKE_CORNER := 17
const I_LANE200 := 18
const I_LANE120 := 19
const I_STEP60 := 20
const I_STEP120 := 21
const I_STEP200 := 22
const I_SWEEP := 23

var cars: Array[Car] = []
var stats: Array[Dictionary] = []
var _t := 0.0
var _done := false


func _ready() -> void:
	InputSetup.ensure_actions()
	var ground := StaticBody3D.new()
	ground.set_meta("grip", 1.0)
	ground.set_meta("drag", 0.0)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	add_child(ground)
	for i in scenarios.size():
		var car := Car.new()
		car.player_controlled = false
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--car="):
				car.model_id = a.trim_prefix("--car=")
		car.transform = Transform3D(Basis(), Vector3((i - 12) * 400.0, 0.7, 0))
		add_child(car)
		cars.append(car)
		stats.append({max_beta = 0.0, spun_at = -1.0, heading0 = 0.0, yaw_peak = 0.0, t90 = -1.0,
			yaw_trace = [], min_speed = 999.0, max_lat_g = 0.0, max_dheading = 0.0})


func _physics_process(dt: float) -> void:
	_t += dt
	for i in cars.size():
		var car := cars[i]
		var st: Dictionary = stats[i]
		if _t < SETTLE:
			continue
		var t := _t - SETTLE
		if is_equal_approx(t, dt) or (t <= dt * 1.5 and not st.has("started")):
			st.started = true
			var v: float = scenarios[i][1] / 3.6
			car.linear_velocity = -car.global_basis.z * v
			st.heading0 = car.rotation.y
			car.gear = 1
			for g in range(1, car.gear_ratios.size() + 1):
				car.gear = g
				if car._rpm_for_gear(g) < car.redline_rpm * 0.8:
					break
		var inp: Array = scenarios[i][2].call(t)
		car.throttle = inp[0]
		car.brake = inp[1]
		car.steer_input = inp[2]
		car.handbrake = inp[3]

		var v := car.linear_velocity
		var flat := Vector3(v.x, 0, v.z)
		var fwd := -car.global_basis.z
		fwd.y = 0
		var spd := flat.length()
		var beta := 0.0
		if spd > 3.0:
			beta = rad_to_deg(fwd.normalized().signed_angle_to(flat.normalized(), Vector3.UP))
		st.max_beta = maxf(st.max_beta, absf(beta))
		if absf(beta) > 15.0 and absf(beta) < 60.0:
			st.drift_time = st.get("drift_time", 0.0) + dt
		st.end_beta = beta
		if absf(beta) > 75.0 and st.spun_at < 0.0:
			st.spun_at = t
		st.min_speed = minf(st.min_speed, spd * 3.6)
		if spd * 3.6 >= 100.0 and not st.has("t100"):
			st.t100 = t
		if t > 0.5 and not st.has("brake_from"):
			st.brake_from = car.global_position
		if spd < 0.5 and st.has("brake_from") and not st.has("stop_dist"):
			st.stop_dist = st.brake_from.distance_to(car.global_position)
		if t > 1.0 and t < 2.0:
			st.yaw_1s = maxf(st.get("yaw_1s", 0.0), absf(car.angular_velocity.y))
		# Lane change settling: any yaw / slip left well after the wheel is straight.
		if t > 2.2 and t < 4.0:
			st.residual_yaw = maxf(st.get("residual_yaw", 0.0), absf(car.angular_velocity.y))
			st.residual_slip = maxf(st.get("residual_slip", 0.0), absf(beta))
		# Straight-line braking: how far the nose wanders off the start heading.
		st.max_dheading = maxf(st.max_dheading, absf(rad_to_deg(wrapf(car.rotation.y - st.heading0, -PI, PI))))
		if t > 0.9 and absf(beta) < 3.0 and not st.has("caught_at"):
			st.caught_at = t - 0.9
		if OS.get_cmdline_user_args().has("--trace=%d" % i) and (fmod(t, 0.25) < dt or (t > 0.45 and t < 1.0 and fmod(t, 0.05) < dt)):
			var w := car.wheels
			print("t=%.2f v=%.0f beta=%.1f yaw=%.2f steer=%.2f ang=%.1f° loads=%s slips=%s" % [t, spd * 3.6, beta, car.angular_velocity.y, car.steer, rad_to_deg(car.steer_angle()),
				w.map(func(x): return roundi(x.load)), w.map(func(x): return snappedf(x.slip, 0.01))])
		var yaw := absf(car.angular_velocity.y)
		st.yaw_trace.append([t, yaw])
		st.max_lat_g = maxf(st.max_lat_g, flat.length() * absf(car.angular_velocity.y) / 9.81 if spd > 3.0 else 0.0)
	if _t > DURATION + SETTLE and not _done:
		_done = true
		print("\nKEY METRICS  0-100: %.2fs   100-0: %.1f m   yaw@80 full lock: %.0f deg/s   yaw@140: %.0f deg/s" % [
			stats[0].get("t100", -1.0), stats[1].get("stop_dist", -1.0),
			rad_to_deg(stats[2].get("yaw_1s", 0.0)), rad_to_deg(stats[3].get("yaw_1s", 0.0))])
		print("HIGH SPEED   200-0: %.1f m (nose wander %.1f°)   200-0 w/ wobble: %.1f m slip %.1f°   brake-into-corner 180: max slip %.1f° %s" % [
			stats[I_BRAKE200].get("stop_dist", -1.0), stats[I_BRAKE200].max_dheading,
			stats[I_WOBBLE].get("stop_dist", -1.0), stats[I_WOBBLE].max_beta,
			stats[I_BRAKE_CORNER].max_beta, "SPUN" if stats[I_BRAKE_CORNER].spun_at >= 0.0 else "ok"])
		print("LANE CHANGE  200: max slip %.1f°, residual yaw %.0f°/s, residual slip %.1f°   120: max slip %.1f°, residual yaw %.0f°/s" % [
			stats[I_LANE200].max_beta, rad_to_deg(stats[I_LANE200].get("residual_yaw", 0.0)), stats[I_LANE200].get("residual_slip", 0.0),
			stats[I_LANE120].max_beta, rad_to_deg(stats[I_LANE120].get("residual_yaw", 0.0))])
		print("STEER RESP   t63 / t90 (s) @60: %s  @120: %s  @200: %s   sweeper 220 half-steer: %.0f km/h, slip %.1f°" % [
			_resp(I_STEP60), _resp(I_STEP120), _resp(I_STEP200), cars[I_SWEEP].linear_velocity.length() * 3.6, stats[I_SWEEP].max_beta])
		print("SLIDE CATCH  120 (handbrake flick, then wheel straight): max slip %.1f°, back under 3° after %.2f s, %s" % [
			stats[I_CATCH].max_beta, stats[I_CATCH].get("caught_at", -1.0), "SPUN" if stats[I_CATCH].spun_at >= 0.0 else "ok"])
		_report()
		get_tree().quit()


## Time from the steer key going down to 63% / 90% of the yaw rate it has 1.5 s later.
func _resp(i: int) -> String:
	var tr: Array = stats[i].yaw_trace
	var ref := 0.0
	for s in tr:
		if s[0] >= 1.95 and s[0] <= 2.05:
			ref = maxf(ref, s[1])
	var t63 := -1.0
	var t90 := -1.0
	for s in tr:
		if s[0] > 0.5 and ref > 0.02:
			if t63 < 0.0 and s[1] >= ref * 0.63:
				t63 = s[0] - 0.5
			if t90 < 0.0 and s[1] >= ref * 0.9:
				t90 = s[0] - 0.5
	return "%.2f/%.2f (%.0f°/s)" % [t63, t90, rad_to_deg(ref)]


func _report() -> void:
	print("\n%-26s %8s %8s %9s %9s %8s %8s %7s %8s" % ["scenario", "end km/h", "min km/h", "max slip°", "spun at", "yaw 90%", "heading°", "drift s", "end slip"])
	for i in cars.size():
		var st: Dictionary = stats[i]
		var car := cars[i]
		# Steering response: time from steer input (t=0.5) to 90% of peak yaw rate in the first 2 s.
		var peak := 0.0
		for s in st.yaw_trace:
			if s[0] > 0.5 and s[0] < 2.5:
				peak = maxf(peak, s[1])
		var t90 := -1.0
		for s in st.yaw_trace:
			if s[0] > 0.5 and s[1] >= peak * 0.9 and peak > 0.05:
				t90 = s[0] - 0.5
				break
		var heading := rad_to_deg(wrapf(car.rotation.y - st.heading0, -PI, PI))
		print("%-26s %8.0f %8.0f %9.1f %9s %8s %8.0f %7.1f %8.1f" % [scenarios[i][0], car.linear_velocity.length() * 3.6,
			st.min_speed, st.max_beta, ("%.2fs" % st.spun_at) if st.spun_at >= 0.0 else "-",
			("%.2fs" % t90) if t90 >= 0.0 else "-", heading, st.get("drift_time", 0.0), st.end_beta])
