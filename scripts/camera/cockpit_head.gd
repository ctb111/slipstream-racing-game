class_name CockpitHead
extends RefCounted
## The driver's head for the cockpit camera. The view is locked to the car
## (any lag would make the interior swim), and the head adds what a body
## does on top: it is pushed outwards and back/forwards by g, keeps the
## horizon a bit more level than the rolling / pitching shell, glances
## towards the apex, and turns with the look keys (look_left / look_right /
## look_back, see InputSetup).

const LEAN_LAT := 0.028 ## metres of sideways head shift per g
const LEAN_LONG := 0.03 ## metres back per g of acceleration (forwards under braking)
const LEVEL := 0.35 ## share of body roll / pitch the neck takes out
const NECK := 0.1 ## the head turns about a point this far behind the eyes

var _lean := Vector3.ZERO
var _yaw := 0.0
var _look := 0.0
var _level := Vector2.ZERO


func place(car: Car, cockpit: Cockpit, t: Transform3D, dt: float, surge: float, lat_g: float) -> Transform3D:
	var eye := cockpit.eye_transform() if cockpit else Transform3D(Basis(), Vector3(-0.36, 0.45, 0.15))
	var b := t.basis.orthonormalized()
	var k := 1.0 - exp(-dt * 6.0)
	# g: the body sinks into the seat bolsters and belts.
	var want := Vector3(-clampf(lat_g, -1.6, 1.6) * LEAN_LAT, 0.0, clampf(surge, -1.3, 1.0) * LEAN_LONG)
	want.y = -absf(lat_g) * 0.006
	_lean = _lean.lerp(want, k)
	# Glance at the apex: towards where the car is rotating / sliding.
	var yaw_rate := car.angular_velocity.dot(b.y)
	var moving := clampf(absf(car.speed) / 12.0, 0.0, 1.0)
	var apex := clampf(yaw_rate * 0.07 - car.body_slip * 0.25, -0.1, 0.1) * moving
	_yaw = lerpf(_yaw, apex, 1.0 - exp(-dt * 2.5))
	# Look keys: to either side, or over the inboard shoulder for a look back.
	var look := 0.0
	if _pressed("look_left"):
		look += 1.3
	if _pressed("look_right"):
		look -= 1.3
	if _pressed("look_back"):
		look = 2.7 * (-1.0 if eye.origin.x < 0.0 else 1.0)
	_look = lerpf(_look, look, 1.0 - exp(-dt * 10.0))
	# Keep the horizon calmer than the shell: take out part of its roll and pitch.
	var fwd := -b.z
	var roll := asin(clampf(b.x.y, -1.0, 1.0))
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	_level = _level.lerp(Vector2(roll, pitch) * LEVEL, 1.0 - exp(-dt * 8.0))

	var turn := _yaw + _look
	var head := Basis(Vector3.UP, turn) * eye.basis
	head = Basis(Vector3.BACK, _level.x) * head # counter-roll
	head = Basis(Vector3.RIGHT, -_level.y * 0.6) * head
	var neck := Vector3(0, 0, NECK)
	var pos := eye.origin + _lean + (Basis(Vector3.UP, turn) * -neck + neck)
	if absf(_look) > 1.6: # looking back: lean across and up to see past the seat
		pos += Vector3(signf(_look) * -0.12, 0.05, 0.05) * smoothstep(1.6, 2.7, absf(_look))
	return Transform3D(b * head, t * pos)


static func _pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)
