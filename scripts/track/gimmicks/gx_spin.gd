class_name GxSpin
extends Node3D
## Turns itself about its local z axis at `speed` rad/s (wind turbine rotors).
## Purely cosmetic; stops processing when not visible to save CPU.

var speed := 1.2


func _ready() -> void:
	rotation.z = randf() * TAU


func _process(dt: float) -> void:
	rotate_object_local(Vector3.BACK, speed * dt)
