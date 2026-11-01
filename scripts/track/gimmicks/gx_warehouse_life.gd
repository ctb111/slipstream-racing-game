class_name GxWarehouseLife
extends Node3D
## Dynamic life inside drive-through warehouses and barns (GxWarehouse):
##   - Forklift patrolling slowly behind the safety barrier with a rotating amber beacon.
##   - Sliding overhead hoist / crane trolley traversing the roof girder.
##   - Slowly spinning ceiling fans / ventilators under the roof trusses.
##
## Optimized for 60 fps on M1:
##   - Merged geometry (GxGeo), no shadows, unshaded emissive materials (no Light3D).
##   - Culls processing and rendering when camera is > 110 m away.
##   - Zero per-frame allocations.

var _forklift: Node3D = null
var _beacon: Node3D = null
var _hoist: Node3D = null
var _fans: Array[Node3D] = []

var _fl_min_x := -12.0
var _fl_max_x := 12.0
var _fl_x := 0.0
var _fl_dir := 1.0
var _fl_speed := 1.5
var _fl_wait := 0.0
var _fl_turn := 0.0

var _hoist_min_z := -8.5
var _hoist_max_z := 8.5
var _hoist_z := 0.0
var _hoist_dir := 1.0
var _hoist_speed := 0.45

var _beacon_rot := 0.0
var _fan_rot := 0.0


static func place(holder: Node3D, F: Transform3D, L: float, eave: float, ridge: float, barn: bool, floor_y: float) -> void:
	var life := GxWarehouseLife.new()
	life.name = "GxWarehouseLife"
	life.transform = F
	life._setup(L, eave, ridge, barn, floor_y)
	holder.add_child(life)


func _setup(L: float, eave: float, ridge: float, barn: bool, floor_y: float) -> void:
	var hl := L * 0.5
	var patrol_half := minf(hl * 0.55, 15.0)
	_fl_min_x = -patrol_half
	_fl_max_x = patrol_half
	_fl_x = -patrol_half * 0.5
	var side_z := 14.4 # behind barrier at z = 12.1 + yellow line at 13.5

	# 1. Forklift with rotating amber beacon
	_build_forklift(barn, floor_y, side_z)

	# 2. Sliding overhead hoist / crane
	_build_hoist(eave, hl * 0.2)

	# 3. Ceiling fans
	_build_ceiling_fans(L, eave, ridge, barn)


# ---------------------------------------------------------------- forklift

func _build_forklift(barn: bool, floor_y: float, side_z: float) -> void:
	_forklift = Node3D.new()
	_forklift.name = "Forklift"
	_forklift.position = Vector3(_fl_x, floor_y, side_z)
	add_child(_forklift)

	var g := GxGeo.new()
	var paint := Color(0.86, 0.58, 0.08) if not barn else Color(0.75, 0.22, 0.12)
	# Chassis, hood, counterweight
	g.col = paint
	g.box("in_painted_metal", Vector3(0.0, 0.55, 0), Vector3(1.9, 0.55, 1.05), 0.08)
	g.col = paint * 0.88
	g.box("in_painted_metal", Vector3(-0.85, 0.68, 0), Vector3(0.55, 0.82, 1.06), 0.15)
	# Seat & steering column
	g.col = Color(0.12, 0.12, 0.12)
	g.box("rubber", Vector3(-0.38, 1.15, 0), Vector3(0.42, 0.1, 0.44), 0.04)
	g.box("rubber", Vector3(-0.58, 1.42, 0), Vector3(0.08, 0.45, 0.42), 0.04)
	g.bar("in_steel", Vector3(0.32, 0.9, 0), Vector3(0.12, 1.45, 0), 0.03)
	# Overhead guard
	g.col = Color(0.12, 0.12, 0.12)
	for zz: float in [-0.44, 0.44]:
		g.tube("in_painted_metal", [Vector3(-0.9, 0.9, zz), Vector3(-0.75, 2.15, zz), Vector3(0.42, 2.18, zz), Vector3(0.52, 0.9, zz)], 0.035, 6, false)
	for i in 5:
		var xx := lerpf(-0.7, 0.38, i / 4.0)
		g.box("in_painted_metal", Vector3(xx, 2.18, 0), Vector3(0.05, 0.035, 0.92), 0.0)
	# Mast and forks
	g.col = Color(0.16, 0.16, 0.18)
	for zz: float in [-0.34, 0.34]:
		g.box("in_steel", Vector3(0.96, 1.15, zz), Vector3(0.08, 2.15, 0.07), 0.01)
	g.box("in_steel", Vector3(0.96, 2.2, 0), Vector3(0.08, 0.08, 0.74), 0.0)
	# Carriage & forks
	g.box("in_steel", Vector3(1.02, 0.4, 0), Vector3(0.05, 0.5, 0.65), 0.01)
	for zz: float in [-0.22, 0.22]:
		g.box("in_steel", Vector3(1.5, 0.12, zz), Vector3(1.0, 0.04, 0.1), 0.01)
	# Wheels (solid rubber)
	g.col = Color(0.08, 0.08, 0.08)
	for xx: float in [-0.62, 0.62]:
		for zz: float in [-0.54, 0.54]:
			g.tube("rubber", [Vector3(xx, 0.24, zz - 0.06), Vector3(xx, 0.24, zz + 0.06)], 0.24, 12, true)
	# Beacon base (on top of guard)
	g.box("rubber", Vector3(-0.16, 2.22, 0), Vector3(0.16, 0.05, 0.16), 0.02)

	var root := g.commit(_forklift, "ForkliftMesh", 140.0, false)
	_set_no_shadows(root)

	# Rotating amber beacon
	_beacon = Node3D.new()
	_beacon.name = "Beacon"
	_beacon.position = Vector3(-0.16, 2.27, 0)
	_forklift.add_child(_beacon)

	var gb := GxGeo.new()
	gb.col = Color.WHITE
	# 4-facet cross rotor
	gb.box("emit_amber", Vector3.ZERO, Vector3(0.12, 0.09, 0.035))
	gb.box("emit_amber", Vector3.ZERO, Vector3(0.035, 0.09, 0.12))
	var root_b := gb.commit(_beacon, "BeaconMesh", 140.0, false)
	_set_no_shadows(root_b)

	# Apply bright unshaded amber emission
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.65, 0.05)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.65, 0.05)
	em.emission_energy_multiplier = 6.0
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for ch in root_b.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).material_override = em


# ---------------------------------------------------------------- overhead hoist

func _build_hoist(eave: float, beam_x: float) -> void:
	# Fixed runway I-beam spanning across the building
	var gb := GxGeo.new()
	var by := eave - 0.22
	gb.col = Color(0.85, 0.72, 0.08)
	gb.box("in_painted_metal", Vector3(beam_x, by, 0), Vector3(0.35, 0.45, 23.0), 0.02)
	gb.col = Color(0.18, 0.18, 0.2)
	for zz: float in [-11.0, 0.0, 11.0]:
		gb.box("in_steel", Vector3(beam_x, by + 0.35, zz), Vector3(0.4, 0.3, 0.4))
	var root_beam := gb.commit(self, "HoistBeam", 140.0, false)
	_set_no_shadows(root_beam)

	# Moving hoist trolley
	_hoist = Node3D.new()
	_hoist.name = "HoistTrolley"
	_hoist.position = Vector3(beam_x, by - 0.25, 0)
	add_child(_hoist)

	var gh := GxGeo.new()
	# Trolley frame + motor body
	gh.col = Color(0.85, 0.72, 0.08)
	gh.box("in_painted_metal", Vector3(0, -0.22, 0), Vector3(0.7, 0.38, 0.75), 0.03)
	gh.col = Color(0.2, 0.22, 0.25)
	gh.box("in_steel", Vector3(0.4, -0.22, 0), Vector3(0.25, 0.32, 0.45), 0.02) # motor
	# Wire ropes hanging down to hook block
	gh.col = Color(0.15, 0.15, 0.15)
	for rz: float in [-0.12, 0.12]:
		gh.bar("in_steel", Vector3(0, -0.4, rz), Vector3(0, -2.8, rz), 0.012, 3)
	# Bottom hook block
	gh.col = Color(0.9, 0.75, 0.05)
	gh.box("in_painted_metal", Vector3(0, -2.95, 0), Vector3(0.32, 0.35, 0.38), 0.03)
	gh.col = Color(0.18, 0.18, 0.18)
	gh.tube("in_steel", [Vector3(0, -3.15, 0), Vector3(0, -3.4, 0), Vector3(0.15, -3.5, 0), Vector3(0.2, -3.38, 0)], 0.035, 6, false)

	var root_h := gh.commit(_hoist, "HoistMesh", 140.0, false)
	_set_no_shadows(root_h)


# ---------------------------------------------------------------- ceiling fans

func _build_ceiling_fans(L: float, eave: float, ridge: float, barn: bool) -> void:
	var n_fans := 3
	var fan_ys := eave + (ridge - eave) * 0.4
	for i in n_fans:
		var fx := -L * 0.3 + i * (L * 0.6 / (n_fans - 1))
		var fan := Node3D.new()
		fan.name = "CeilingFan_%d" % i
		fan.position = Vector3(fx, fan_ys, 0.0)
		add_child(fan)
		_fans.append(fan)

		var gf := GxGeo.new()
		# Downrod & motor hub
		gf.col = Color(0.15, 0.15, 0.15)
		gf.bar("in_steel", Vector3(0, 0.8, 0), Vector3(0, 0, 0), 0.03, 4)
		gf.box("in_painted_metal", Vector3(0, 0, 0), Vector3(0.36, 0.18, 0.36), 0.03)
		# 4 blades
		var bmat := "painted_wood" if barn else "in_painted_metal"
		gf.col = Color(0.35, 0.25, 0.18) if barn else Color(0.2, 0.22, 0.25)
		var blade_len := 1.25
		for k in 4:
			var ang := float(k) * PI * 0.5
			var rot := Basis(Vector3.UP, ang)
			gf.box(bmat, rot * Vector3(blade_len * 0.5 + 0.18, 0.0, 0.0), Vector3(blade_len, 0.02, 0.2), 0.0, rot)

		var root_f := gf.commit(fan, "FanMesh", 120.0, false)
		_set_no_shadows(root_f)


# ---------------------------------------------------------------- animation & culling

func _process(dt: float) -> void:
	# Culling: only animate when camera is near the warehouse (< 120 m)
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	if cam.global_position.distance_squared_to(global_position) > 125.0 * 125.0:
		return

	# 1. Forklift patrol along local X
	if _forklift:
		if _fl_wait > 0.0:
			_fl_wait -= dt
			if _fl_turn > 0.0:
				_fl_turn -= dt
				var target_yaw := 0.0 if _fl_dir > 0.0 else PI
				_forklift.rotation.y = lerp_angle(_forklift.rotation.y, target_yaw, 5.0 * dt)
		else:
			_fl_x += _fl_dir * _fl_speed * dt
			_forklift.position.x = _fl_x
			if (_fl_dir > 0.0 and _fl_x >= _fl_max_x) or (_fl_dir < 0.0 and _fl_x <= _fl_min_x):
				_fl_dir = -_fl_dir
				_fl_wait = 1.6
				_fl_turn = 0.8

	# 2. Rotating amber beacon
	if _beacon:
		_beacon_rot = fmod(_beacon_rot + 14.0 * dt, TAU)
		_beacon.rotation.y = _beacon_rot

	# 3. Overhead hoist sliding along Z
	if _hoist:
		_hoist_z += _hoist_dir * _hoist_speed * dt
		_hoist.position.z = _hoist_z
		if (_hoist_dir > 0.0 and _hoist_z >= _hoist_max_z) or (_hoist_dir < 0.0 and _hoist_z <= _hoist_min_z):
			_hoist_dir = -_hoist_dir

	# 4. Ceiling fans spinning
	_fan_rot = fmod(_fan_rot + 2.6 * dt, TAU)
	for fan in _fans:
		fan.rotation.y = _fan_rot


static func _set_no_shadows(node: Node) -> void:
	for ch in node.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(ch as GeometryInstance3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
