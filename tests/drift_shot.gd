extends "res://scripts/race/race.gd"
## Screenshot helper: after lights out the player car accelerates to ~75 km/h,
## then flicks into a handbrake drift and holds it on the throttle.

var _drift_t := -1.0


func _physics_process(dt: float) -> void:
	super(dt)
	if state != State.RACING:
		return
	var c := player.car
	c.player_controlled = false
	if _drift_t < 0.0:
		c.throttle = 1.0 if c.speed < 21.0 else 0.3
		c.steer_input = 0.0
		if c.speed >= 21.0:
			_drift_t = 0.0
		return
	_drift_t += dt
	c.steer_input = 1.0
	c.handbrake = _drift_t < 0.4
	c.throttle = 0.2 if _drift_t < 0.5 else 0.85
	if int(_drift_t * 10) % 5 == 0:
		print("drift t=%.1f slip=%.0f° speed=%.0f marks=%d" % [_drift_t, rad_to_deg(c.body_slip), c.speed * 3.6, TireFx._next_mark])
