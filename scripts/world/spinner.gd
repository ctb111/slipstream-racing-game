class_name Spinner
extends Node3D
## Turns around its local Z axis (windmill sails) or drifts in a slow circle
## with a gentle bob (hot-air balloon).

@export var spin_speed := 0.0 ## rad/s around local Z
@export var drift_radius := 0.0 ## metres; 0 = stay put
@export var drift_speed := 0.01 ## rad/s around the drift centre
@export var bob := 0.0

var _centre := Vector3.ZERO
var _t := 0.0


func _ready() -> void:
	_centre = position
	_t = randf() * TAU


func _process(dt: float) -> void:
	_t += dt
	if spin_speed != 0.0:
		rotate_object_local(Vector3.BACK, spin_speed * dt)
	if drift_radius > 0.0:
		var a := _t * drift_speed
		position = _centre + Vector3(cos(a), 0, sin(a)) * drift_radius + Vector3.UP * sin(_t * 0.2) * bob
		rotation.y = -a
