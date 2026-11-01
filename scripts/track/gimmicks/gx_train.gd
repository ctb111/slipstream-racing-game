class_name GxTrain
extends Node3D
## A moving European train (electric Bo-Bo locomotive + 4 passenger coaches)
## crossing the railway overpass.
##
##   GxTrain.place(c, xf, opts)
##
## Features:
##   - Realistic, period-plausible European train with bogies, pantographs,
##     buffers, gangways and passenger coaches.
##   - Continuous ballast bed, sleepers, rails and catenary masts extending
##     150-250 m beyond bridge ends, clear of the track and reserved from trees.
##   - Emissive lit passenger windows and headlights at night (no Light3D).
##   - Runs on a loop timer AND triggers when a car / player approaches the bridge.
##   - Merged meshes (GxGeo), 1 node moved in _process, distance culling, no shadows.

const SPEED := 22.0 ## ~80 km/h regional/express train speed
const EXT := 240.0 ## metres of rail bed beyond each bridge abutment
const LOCO_LEN := 16.0
const COACH_LEN := 22.0
const COACH_GAP := 0.6
const COACHES := 4
const CONSIST_LEN := LOCO_LEN + COACHES * (COACH_LEN + COACH_GAP) ## ~106.4 m

var rail_y := 0.0
var z_start := -250.0
var z_end := 250.0
var speed := SPEED
var _z := -999.0
var _active := false
var _cooldown := 0.0
var _timer := 0.0
var _race: Node = null
var _bridge_along := 0.0
var _lap_length := 1000.0
var _train_body: Node3D = null
var _ze := 18.0
var _top := 0.0
var _profile_z: PackedFloat32Array = PackedFloat32Array()
var _profile_y: PackedFloat32Array = PackedFloat32Array()


static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var soffit: float = float(opts.get("soffit", 7.7))
	var ze: float = float(opts.get("ze", 18.0))
	var top: float = float(opts.get("top", soffit + 1.9))
	var ry := top + 0.15

	# 1. Extended static track (ballast embankment, sleepers, rails, catenary)
	var profile: Array = _build_track(c, xf, ze, top, ry, opts)

	# 2. Moving train instance
	var train := GxTrain.new()
	train.name = "GxTrain"
	train.rail_y = ry
	train._ze = ze
	train._top = top
	train.z_start = -ze - EXT + 10.0
	train.z_end = ze + EXT - 10.0
	train.transform = xf
	# Set profile for vertical terrain tracking
	if profile.size() >= 2:
		for p: Vector2 in profile:
			train._profile_z.append(p.x)
			train._profile_y.append(p.y)
	var start_off: float = float(c.get("start_offset")) if c.get("start_offset") != null else 0.0
	train._bridge_along = fposmod(Gx.curve(c).get_closest_offset(xf.origin) - start_off, Gx.length(c))
	train._lap_length = Gx.length(c)
	# Schedule initial crossing (default 3.5 s so train crosses early in view)
	train._timer = float(opts.get("timer", 3.5))

	var night := is_night(c)
	train._build_consist(c, night)
	c.add_child(train)


# ---------------------------------------------------------------- static track

static func _build_track(c: Node3D, xf: Transform3D, ze: float, top: float, ry: float, _opts: Dictionary) -> Array:
	var g := GxGeo.new(xf)
	var step := 4.0
	var col_ballast := Color(0.50, 0.46, 0.42)
	var col_wood := Color(0.36, 0.30, 0.25)
	var all_pts: Array = [] # Vector2(z, y)

	# Track grade: railway transition slope (~0.04 m/m descent towards ground)
	var grade := 0.040

	for dir: float in [-1.0, 1.0]:
		var stations: Array = [] # [z, y, gy]
		var cur_y: float = top
		var steps := int(EXT / step)
		for k in steps:
			var z: float = dir * (ze + 0.7 + float(k) * step)
			var wp: Vector3 = xf * Vector3(0, 0, z)
			if not Gx.clear_of_road(c, wp, 6.0):
				break
			var gy: float = Gx.ground(c, wp) - xf.origin.y
			var tgt_y: float = maxf(gy + 0.45, gy)
			cur_y = move_toward(cur_y, tgt_y, grade * step)
			# Ensure rail bed never buries into the ground
			cur_y = maxf(cur_y, gy + 0.45)
			stations.append([z, cur_y, gy])
			all_pts.append(Vector2(z, cur_y))
			if k % 5 == 0:
				Gx.reserve(c, wp, 14.0)

		if stations.size() < 2:
			continue

		# Sort stations by absolute distance along dir
		for i in stations.size() - 1:
			var z0: float = stations[i][0]
			var z1: float = stations[i + 1][0]
			var y0: float = stations[i][1]
			var y1: float = stations[i + 1][1]
			var gy0: float = stations[i][2]
			var gy1: float = stations[i + 1][2]
			var b_bot0 := minf(gy0 - 0.5, y0 - 0.5)
			var b_bot1 := minf(gy1 - 0.5, y1 - 0.5)
			var w_top := 1.7 # half-width of ballast crown
			var w_bot0 := w_top + maxf(y0 - b_bot0, 0.3) * 1.5
			var w_bot1 := w_top + maxf(y1 - b_bot1, 0.3) * 1.5

			# Ballast top surface (always faces UP)
			g.col = col_ballast
			g.quad_n("concrete", Vector3(-w_top, y0 - 0.08, z0), Vector3(w_top, y0 - 0.08, z0),
				Vector3(w_top, y1 - 0.08, z1), Vector3(-w_top, y1 - 0.08, z1), Vector3.UP)

			# Ballast shoulders (embankment side slopes extending deep into terrain)
			g.col = col_ballast * 0.88
			g.quad_n("concrete", Vector3(-w_bot0, b_bot0, z0), Vector3(-w_top, y0 - 0.08, z0),
				Vector3(-w_top, y1 - 0.08, z1), Vector3(-w_bot1, b_bot1, z1), Vector3(-1.0, 0.5, 0.0))
			g.quad_n("concrete", Vector3(w_top, y0 - 0.08, z0), Vector3(w_bot0, b_bot0, z0),
				Vector3(w_bot1, b_bot1, z1), Vector3(w_top, y1 - 0.08, z1), Vector3(1.0, 0.5, 0.0))

			# Sleepers spaced ~0.65 m
			var dz := absf(z1 - z0)
			var n_sleepers := maxi(int(dz / 0.65), 1)
			g.col = col_wood
			for s in n_sleepers:
				var t := (s + 0.5) / n_sleepers
				var sz := lerpf(z0, z1, t)
				var sy := lerpf(y0, y1, t)
				g.box("wood", Vector3(0, sy - 0.02, sz), Vector3(2.5, 0.14, 0.24), 0.01)

			# Rails (two standard-gauge rails at x = +-0.72)
			g.col = Color.WHITE
			for rx: float in [-0.72, 0.72]:
				g.quad_n("steel", Vector3(rx - 0.035, y0 + 0.14, z0), Vector3(rx + 0.035, y0 + 0.14, z0),
					Vector3(rx + 0.035, y1 + 0.14, z1), Vector3(rx - 0.035, y1 + 0.14, z1), Vector3.UP)
				g.quad_n("steel", Vector3(rx - 0.015, y0 + 0.02, z0), Vector3(rx - 0.015, y0 + 0.14, z0),
					Vector3(rx - 0.015, y1 + 0.14, z1), Vector3(rx - 0.015, y1 + 0.02, z1), Vector3(-1, 0, 0))
				g.quad_n("steel", Vector3(rx + 0.015, y0 + 0.14, z0), Vector3(rx + 0.015, y0 + 0.02, z0),
					Vector3(rx + 0.015, y1 + 0.02, z1), Vector3(rx + 0.015, y1 + 0.14, z1), Vector3(1, 0, 0))

			# Catenary masts every ~40 m
			if i % 10 == 0:
				var mast_x: float = dir * 2.8
				var my_base: float = minf(gy0, y0 - 0.5)
				g.col = Color(0.5, 0.52, 0.5)
				g.box("painted_metal", Vector3(mast_x, (my_base + y0 + 6.2) * 0.5, z0), Vector3(0.2, y0 + 6.2 - my_base, 0.2))
				g.bar("steel", Vector3(mast_x, y0 + 5.6, z0), Vector3(0, y0 + 5.4, z0), 0.04)
				g.bar("steel", Vector3(mast_x, y0 + 4.6, z0), Vector3(0, y0 + 5.25, z0), 0.03)

			# Contact wire spanning between stations
			g.col = Color(0.2, 0.2, 0.2)
			g.bar("steel", Vector3(0, y0 + 5.2, z0), Vector3(0, y1 + 5.2, z1), 0.012, 4)

	# Include bridge deck points (-ze and +ze)
	all_pts.append(Vector2(-ze, top))
	all_pts.append(Vector2(ze, top))
	all_pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	g.commit(c, "GxTrainTrack", 850.0, false)
	return all_pts


# ---------------------------------------------------------------- consist model

func _build_consist(c: Node3D, night: bool) -> void:
	_train_body = Node3D.new()
	_train_body.name = "Consist"
	_train_body.visible = false
	add_child(_train_body)

	var g := GxGeo.new()
	# Locomotive at front (offset 0.0)
	_build_locomotive(g, 0.0, night)

	# 4 Passenger Coaches behind locomotive
	for i in COACHES:
		var coach_center := -LOCO_LEN * 0.5 - COACH_GAP - COACH_LEN * 0.5 - i * (COACH_LEN + COACH_GAP)
		_build_coach(g, coach_center, night, i == COACHES - 1)
		# Bellows between coaches / loco
		var bellow_z := coach_center + COACH_LEN * 0.5 + COACH_GAP * 0.5
		g.col = Color(0.12, 0.12, 0.12)
		g.box("rubber", Vector3(0, 2.1, bellow_z), Vector3(1.5, 2.3, COACH_GAP), 0.04)

	# Commit train into _train_body (no shadows, pure moving proxy)
	var root := g.commit(_train_body, "TrainMesh", 800.0, false)
	for ch in root.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(ch as GeometryInstance3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			var mat_name := str(ch.name)
			if mat_name == "emit":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.96, 0.88)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.96, 0.88)
				em.emission_energy_multiplier = 6.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em
			elif mat_name == "emit_warm":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.84, 0.52)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.84, 0.52)
				em.emission_energy_multiplier = 4.5
				(ch as MeshInstance3D).material_override = em
			elif mat_name == "emit_red":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.1, 0.05)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.08, 0.04)
				em.emission_energy_multiplier = 5.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em


## European electric Bo-Bo locomotive (16 m long, 3 m wide, 3.8 m high).
static func _build_locomotive(g: GxGeo, cz: float, night: bool) -> void:
	var hl := LOCO_LEN * 0.5
	var red := Color(0.74, 0.14, 0.14)
	var cream := Color(0.90, 0.88, 0.82)
	var dark_roof := Color(0.32, 0.33, 0.35)
	var skirt := Color(0.18, 0.18, 0.20)

	# Bogies & Wheels (two 2-axle bogies at +-4.8m)
	g.col = Color(0.2, 0.2, 0.22)
	for bz: float in [cz - 4.8, cz + 4.8]:
		g.box("steel", Vector3(0, 0.5, bz), Vector3(2.5, 0.35, 3.8), 0.05)
		for wz: float in [bz - 1.2, bz + 1.2]:
			for wx: float in [-0.72, 0.72]:
				g.col = Color(0.55, 0.56, 0.58)
				g.box("steel", Vector3(wx, 0.48, wz), Vector3(0.12, 0.95, 0.95), 0.08)
				g.col = Color(0.15, 0.15, 0.16)
				g.box("steel", Vector3(wx * 1.15, 0.48, wz), Vector3(0.15, 0.35, 0.35), 0.05) # axlebox

	# Underframe skirt & buffer beams
	g.col = skirt
	g.box("painted_metal", Vector3(0, 0.65, cz), Vector3(2.9, 0.35, LOCO_LEN), 0.04)
	for end: float in [cz - hl, cz + hl]:
		g.box("steel", Vector3(0, 0.75, end), Vector3(2.95, 0.4, 0.3), 0.04)
		# Buffers
		for bx: float in [-0.85, 0.85]:
			g.col = Color(0.3, 0.3, 0.32)
			g.box("steel", Vector3(bx, 0.75, end + signf(end - cz) * 0.25), Vector3(0.42, 0.32, 0.35), 0.05)

	# Main locomotive body (red)
	g.col = red
	g.box("painted_metal", Vector3(0, 2.05, cz), Vector3(2.96, 2.4, LOCO_LEN - 0.4), 0.1)

	# Cream accent waist band
	g.col = cream
	g.box("painted_metal", Vector3(0, 1.55, cz), Vector3(3.0, 0.35, LOCO_LEN - 0.3), 0.02)

	# Curved roof
	g.col = dark_roof
	g.box("painted_metal", Vector3(0, 3.35, cz), Vector3(2.78, 0.45, LOCO_LEN - 0.8), 0.12)
	g.col = Color(0.45, 0.46, 0.48)
	g.box("steel", Vector3(0, 3.65, cz), Vector3(1.4, 0.2, 7.5), 0.04) # roof resistor housings

	# Cab front windshields (tilted)
	var win_mat := "glass"
	g.col = Color(0.85, 0.9, 0.95)
	for end: float in [cz - hl + 0.2, cz + hl - 0.2]:
		g.box(win_mat, Vector3(0, 2.5, end), Vector3(2.4, 0.75, 0.08), 0.02)
		# Cab side windows
		for sx: float in [-1.49, 1.49]:
			g.box(win_mat, Vector3(sx, 2.5, end - signf(end - cz) * 1.2), Vector3(0.06, 0.65, 0.9), 0.02)

	# Headlights & tail markers at front (cz + hl)
	var fz := cz + hl + 0.02
	if night:
		# Triple warm headlights at front
		g.col = Color(1.0, 0.95, 0.85)
		g.box("emit", Vector3(-0.95, 1.35, fz), Vector3(0.24, 0.22, 0.06))
		g.box("emit", Vector3(0.95, 1.35, fz), Vector3(0.24, 0.22, 0.06))
		g.box("emit", Vector3(0.0, 3.25, fz - 0.05), Vector3(0.24, 0.22, 0.06))
		# Red tail markers at rear
		g.col = Color(1.0, 0.1, 0.05)
		g.box("emit_red", Vector3(-0.95, 1.35, cz - hl - 0.02), Vector3(0.18, 0.16, 0.06))
		g.box("emit_red", Vector3(0.95, 1.35, cz - hl - 0.02), Vector3(0.18, 0.16, 0.06))
	else:
		g.col = Color(0.95, 0.95, 0.9)
		g.box("glass", Vector3(-0.95, 1.35, fz), Vector3(0.24, 0.22, 0.06))
		g.box("glass", Vector3(0.95, 1.35, fz), Vector3(0.24, 0.22, 0.06))
		g.box("glass", Vector3(0.0, 3.25, fz - 0.05), Vector3(0.24, 0.22, 0.06))

	# Pantographs on roof: rear raised to wire (5.2m), front folded
	g.col = Color(0.65, 0.66, 0.68)
	# Rear pantograph (cz - 4.2)
	var pz := cz - 4.2
	g.box("painted_metal", Vector3(0, 3.75, pz), Vector3(1.2, 0.08, 1.6))
	g.bar("steel", Vector3(-0.5, 3.8, pz - 0.6), Vector3(0, 4.45, pz + 0.3), 0.035)
	g.bar("steel", Vector3(0.5, 3.8, pz - 0.6), Vector3(0, 4.45, pz + 0.3), 0.035)
	g.bar("steel", Vector3(0, 4.45, pz + 0.3), Vector3(0, 5.2, pz - 0.2), 0.03)
	g.box("steel", Vector3(0, 5.2, pz - 0.2), Vector3(1.9, 0.04, 0.14)) # collector head
	# Front pantograph (folded at cz + 4.2)
	g.box("steel", Vector3(0, 3.82, cz + 4.2), Vector3(1.2, 0.08, 1.6))
	g.bar("steel", Vector3(0, 3.88, cz + 3.6), Vector3(0, 3.96, cz + 4.8), 0.03)


## European express passenger coach (22 m long, 2.85 m wide, 3.75 m high).
static func _build_coach(g: GxGeo, cz: float, night: bool, is_last: bool = false) -> void:
	var hl := COACH_LEN * 0.5
	var cream := Color(0.90, 0.88, 0.82)
	var red := Color(0.65, 0.12, 0.12)
	var roof := Color(0.30, 0.31, 0.33)

	# Bogies at +-7.5 m
	g.col = Color(0.2, 0.2, 0.22)
	for bz: float in [cz - 7.5, cz + 7.5]:
		g.box("steel", Vector3(0, 0.48, bz), Vector3(2.4, 0.3, 3.6), 0.04)
		for wz: float in [bz - 1.1, bz + 1.1]:
			for wx: float in [-0.72, 0.72]:
				g.col = Color(0.52, 0.53, 0.55)
				g.box("steel", Vector3(wx, 0.46, wz), Vector3(0.11, 0.92, 0.92), 0.06)

	# Underframe equipment boxes
	g.col = Color(0.18, 0.18, 0.20)
	g.box("painted_metal", Vector3(0, 0.6, cz), Vector3(2.6, 0.4, 8.5), 0.05)

	# Lower body (red)
	g.col = red
	g.box("painted_metal", Vector3(0, 1.45, cz), Vector3(2.85, 1.2, COACH_LEN - 0.2), 0.06)

	# Upper body (cream)
	g.col = cream
	g.box("painted_metal", Vector3(0, 2.55, cz), Vector3(2.85, 1.0, COACH_LEN - 0.2), 0.06)

	# Roof (dark grey curved)
	g.col = roof
	g.box("painted_metal", Vector3(0, 3.42, cz), Vector3(2.72, 0.55, COACH_LEN - 0.3), 0.12)

	# Passenger compartment windows (9 windows per side)
	var win_mat := "emit_warm" if night else "glass"
	var win_col := Color(1.0, 0.85, 0.60) if night else Color(0.85, 0.9, 0.95)
	for sx: float in [-1.43, 1.43]:
		for k in 9:
			var wz := cz - 7.2 + k * 1.8
			g.col = win_col
			g.box(win_mat, Vector3(sx, 2.52, wz), Vector3(0.04, 0.82, 1.25), 0.01)

	# Passenger doors near ends
	for end_z: float in [cz - hl + 1.4, cz + hl - 1.4]:
		for sx: float in [-1.435, 1.435]:
			g.col = red * 0.9
			g.box("painted_metal", Vector3(sx, 1.9, end_z), Vector3(0.03, 1.9, 0.9), 0.02)
			g.col = win_col
			g.box(win_mat, Vector3(sx + signf(sx) * 0.01, 2.4, end_z), Vector3(0.02, 0.6, 0.4), 0.01)

	# Tail markers on the very rear coach
	if is_last and night:
		g.col = Color(1.0, 0.1, 0.05)
		g.box("emit_red", Vector3(-0.95, 1.35, cz - hl - 0.02), Vector3(0.18, 0.16, 0.06))
		g.box("emit_red", Vector3(0.95, 1.35, cz - hl - 0.02), Vector3(0.18, 0.16, 0.06))


# ---------------------------------------------------------------- run time

func track_y_at(z: float) -> float:
	if absf(z) <= _ze:
		return _top + 0.15
	if _profile_z.is_empty():
		return rail_y
	if z <= _profile_z[0]:
		return _profile_y[0] + 0.15
	var last := _profile_z.size() - 1
	if z >= _profile_z[last]:
		return _profile_y[last] + 0.15
	var idx := _profile_z.bsearch(z)
	idx = clampi(idx, 1, last)
	var z0 := _profile_z[idx - 1]
	var z1 := _profile_z[idx]
	var t := (z - z0) / (z1 - z0) if absf(z1 - z0) > 1e-4 else 0.0
	return lerpf(_profile_y[idx - 1], _profile_y[idx], t) + 0.15


func _process(dt: float) -> void:
	if not _race:
		_find_race()

	if _active:
		_z += speed * dt
		var ty := track_y_at(_z)
		_train_body.position = Vector3(0, ty, _z)
		var dy := track_y_at(_z + 8.0) - track_y_at(_z - 8.0)
		_train_body.rotation.x = -atan2(dy, 16.0)

		if _z > z_end + CONSIST_LEN:
			_active = false
			_train_body.visible = false
			_cooldown = 40.0
			_timer = randf_range(50.0, 75.0)
		else:
			# Stop rendering when camera is far
			var cam := get_viewport().get_camera_3d()
			if cam:
				var cp := cam.global_position
				var tp := global_position + transform.basis * Vector3(0, ty, _z)
				_train_body.visible = cp.distance_squared_to(tp) < 650.0 * 650.0
	else:
		_cooldown = maxf(_cooldown - dt, 0.0)
		_timer -= dt
		if _timer <= 0.0:
			_trigger()
		elif _cooldown <= 0.0 and _race:
			_check_approach()


func _trigger() -> void:
	_active = true
	_z = z_start
	var ty := track_y_at(_z)
	_train_body.position = Vector3(0, ty, _z)
	var dy := track_y_at(_z + 8.0) - track_y_at(_z - 8.0)
	_train_body.rotation.x = -atan2(dy, 16.0)
	_train_body.visible = true
	_cooldown = 40.0
	_timer = randf_range(50.0, 75.0)


func _check_approach() -> void:
	if not _race or not ("entries" in _race):
		return
	var entries: Array = _race.entries
	for e in entries:
		if not e or not is_instance_valid(e.car):
			continue
		var car_along: float = float(e.get("lap_distance")) if "lap_distance" in e else 0.0
		var dist := fposmod(_bridge_along - car_along, _lap_length)
		# Lead car is 180..340 m before the bridge: trigger so train meets car at bridge
		if dist > 180.0 and dist < 340.0:
			_trigger()
			break


func _find_race() -> void:
	var cands: Array[Node] = []
	var p := get_parent()
	if p:
		var gp := p.get_parent()
		if gp:
			cands.append(gp)
			var ggp := gp.get_parent()
			if ggp:
				cands.append(ggp)
	if get_tree().current_scene:
		cands.append(get_tree().current_scene)
	for cand in cands:
		if cand.has_signal("lights_changed") and "entries" in cand:
			_race = cand
			_race.lights_changed.connect(_on_lights)
			break


func _on_lights(count: int) -> void:
	# At lights out (race start), if the bridge is on the start straight, trigger immediately
	if count < 0 and _bridge_along < 220.0 and not _active:
		_trigger()


static func is_night(c: Node3D) -> bool:
	var w = c.get("weather")
	if w != null:
		var preset: Dictionary = w.get("preset") if "preset" in w else {}
		if float(preset.get("night", 0.0)) > 0.0 or bool(w.get("night")):
			return true
	return bool(c.get_meta("night", false)) or Car.night
