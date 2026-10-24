class_name CameraShake
extends RefCounted
## Grounded camera motion read off the car: a fine rumble from the suspension
## working (kerbs, bumps, grass), a sprung jolt on impacts and landings, and
## smoothed lateral g for a gentle roll. Sample in physics, apply per frame.

const IMPACT_ACCEL := 28.0 ## m/s² beyond what tyres and brakes can do: a hit

var rumble := 0.0 ## 0..1 envelope
var kick := 0.0 ## 0..1, rotational shake after an impact, decays
var jolt := Vector3.ZERO ## world-space offset of the sprung jolt (m)
var lat_g := 0.0 ## smoothed car-local lateral acceleration, in g (+ = to the right)
var _jolt_vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _primed := false
var _t := 0.0
var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = 7


## Once per physics tick.
func sample(car: Car, dt: float) -> void:
	var v := car.linear_velocity
	if not _primed:
		_prev_vel = v
		_primed = true
	var dv := v - _prev_vel
	_prev_vel = v
	var acc := dv / maxf(dt, 0.0001)
	lat_g = lerpf(lat_g, clampf(acc.dot(car.global_basis.x) / 9.81, -1.5, 1.5), 1.0 - exp(-dt * 3.0))
	var excess := acc.length() - IMPACT_ACCEL
	if excess > 0.0:
		var k := clampf(excess / 160.0, 0.0, 1.0)
		_jolt_vel -= dv.normalized() * k * 1.8 # the camera keeps going while the car stops
		kick = minf(kick + k * 1.5, 1.0)
	# Sprung, damped return (~2.3 Hz, slightly under-damped).
	_jolt_vel += (-jolt * 210.0 - _jolt_vel * 15.0) * dt
	jolt = (jolt + _jolt_vel * dt).limit_length(0.3)
	kick = move_toward(kick, 0.0, dt * 1.6)

	var comp := 0.0
	var rough := 0.0
	var grounded := 0
	for w in car.wheels:
		if w.grounded:
			comp += absf(w.compression - w.prev_compression) / maxf(dt, 0.0001)
			rough += clampf(1.0 - w.surface_grip, 0.0, 1.0)
			grounded += 1
	var spd := clampf(absf(car.speed) / 40.0, 0.0, 1.0)
	# Kerbs and bumps through the suspension, plus a fine buzz that builds at
	# high speed (above ~190 km/h) so flat-out feels alive, never wobbly.
	var want := clampf((comp - 0.08) * 0.9, 0.0, 1.0) + 0.05 * spd
	want += 0.14 * smoothstep(52.0, 80.0, absf(car.speed))
	if grounded > 0:
		want += rough / grounded * spd * 1.1 # grass and gravel shake more than tarmac
	want = clampf(want, 0.0, 1.0)
	rumble = lerpf(rumble, want, 1.0 - exp(-dt * (22.0 if want > rumble else 5.0)))


## Positional and rotational shake for this frame, scaled by `amount`
## (how rigidly the camera is fixed to the car). Returns [offset (Vector3,
## camera-local), rotation (Vector3 radians: pitch, yaw, roll)].
func offsets(dt: float, amount: float) -> Array:
	_t += dt
	var r := rumble * amount
	var k := kick * amount
	var off := Vector3(_n(0.0, 27.0), _n(40.0, 31.0), 0.0) * r * 0.012
	var rot := Vector3(_n(80.0, 24.0) * r * 0.004, _n(120.0, 20.0) * r * 0.002, _n(160.0, 22.0) * r * 0.002)
	rot += Vector3(_n(200.0, 9.0), _n(240.0, 8.0), _n(280.0, 7.0)) * k * 0.025
	return [off, rot]


func _n(y: float, hz: float) -> float:
	return _noise.get_noise_2d(_t * hz, y)
