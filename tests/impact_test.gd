extends Node3D
## Headless: fires a car at a guardrail at a shallow angle, then another car
## into it, and prints what CarImpacts heard (impacts, scrape levels).
##   godot --headless --path . res://tests/impact_test.tscn -- --debug-impacts

var _car: Car
var _t := 0.0


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Road"
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	gs.shape = box
	gs.position.y = -0.5
	ground.add_child(gs)
	add_child(ground)
	var rail := StaticBody3D.new()
	rail.name = "Guardrail"
	var rs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(0.3, 1.0, 300)
	rs.shape = rb
	rail.add_child(rs)
	rail.position = Vector3(4, 0.5, -100)
	add_child(rail)
	_car = Car.new()
	add_child(_car)
	_car.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-12.0)), Vector3(0, 0.6, 0))
	await get_tree().physics_frame
	_car.linear_velocity = -_car.global_basis.z * 30.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 3, 6)


func _physics_process(dt: float) -> void:
	_t += dt
	if _car:
		_car.throttle = 0.6
	var imp: CarImpacts = _car.find_children("*", "CarImpacts", true, false).front() if _car else null
	if imp and fmod(_t, 0.5) < dt:
		print("pos=%s t=%.1f speed=%.1f scrape=%.2f rub=%.2f contacts=%d mon=%s coll=%s" % [_car.global_position.snapped(Vector3.ONE * 0.1),
			_t, _car.speed, imp._scrape_level, imp._rub_level, PhysicsServer3D.body_get_direct_state(_car.get_rid()).get_contact_count(),
			_car.contact_monitor, _car.get_colliding_bodies()])
	if _t > 4.0:
		get_tree().quit()
