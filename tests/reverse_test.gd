extends Node3D
## Auto-reverse check: (A) drive into a wall at 40 km/h and hold the brake,
## the car must back out; (B) brake to a stop from 60 km/h with the brake held,
## the car must stay put; (C) creep into the wall on throttle, then brake.
##   godot --headless --path . res://tests/reverse_test.tscn

var cars: Array[Car] = []
var _t := 0.0
## name, start km/h, input(t) -> [throttle, brake]
var cases := [
	["crash then hold brake", 40.0, func(t): return [1.0, 0.0] if t < 2.0 else [0.0, 1.0]],
	["stop and hold brake", 60.0, func(t): return [0.0, 1.0]],
	["stuck on throttle then brake", 5.0, func(t): return [0.6, 0.0] if t < 4.0 else [0.0, 1.0]],
]


func _ready() -> void:
	InputSetup.ensure_actions()
	var ground := StaticBody3D.new()
	ground.set_meta("grip", 1.0)
	ground.set_meta("drag", 0.0)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	ground.add_child(cs)
	add_child(ground)
	for i in cases.size():
		var x := (i - 1) * 60.0
		if i != 1:
			var wall := StaticBody3D.new()
			var ws := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(20, 3, 1)
			ws.shape = box
			wall.add_child(ws)
			wall.position = Vector3(x, 1.5, -12.0 if i == 0 else -6.0)
			add_child(wall)
		var car := Car.new()
		car.player_controlled = false
		car.transform = Transform3D(Basis(), Vector3(x, 0.7, 0))
		add_child(car)
		cars.append(car)


func _physics_process(dt: float) -> void:
	_t += dt
	if _t < 0.5:
		return
	var t := _t - 0.5
	for i in cars.size():
		var car := cars[i]
		if t <= dt * 1.5:
			car.linear_velocity = -car.global_basis.z * cases[i][1] / 3.6
		var inp: Array = cases[i][2].call(t)
		car.throttle = inp[0]
		car.brake = inp[1]
		car.steer_input = 0.0
	if t > 9.0:
		for i in cars.size():
			print("%-30s gear=%d speed=%.1f km/h  z=%.1f" % [cases[i][0], cars[i].gear, cars[i].speed * 3.6, cars[i].global_position.z])
		get_tree().quit()
