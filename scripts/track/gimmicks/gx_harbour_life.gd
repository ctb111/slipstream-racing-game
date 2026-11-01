class_name GxHarbourLife
extends Node3D
## Dynamic harbour life:
##   - Realistic European harbour tugboat cruising the basin with gentle water bob.
##   - Port (red), starboard (green) and masthead (white) emissive navigation lights.
##   - Lit wheelhouse windows at night.
##   - Merged mesh (1 draw call), unshaded emissive materials, no shadows, no Light3D.
##   - Distance culling when camera is > 600 m away.

var _tug: Node3D = null
var _p0 := Vector3(-340, -1.2, 388)
var _p1 := Vector3(260, -1.2, 388)
var _x := -340.0
var _dir := 1.0
var _speed := 4.2 ## ~8.2 knots cruising speed
var _water_y := -1.2
var _time := 0.0
var _turning := 0.0


static func maybe_place(c: Node3D) -> void:
	if c.has_node("GxHarbourLife"):
		return
	var def = c.get("def")
	if not def is Dictionary:
		return
	var tid: String = str(def.get("id", ""))
	var theme: String = str(def.get("theme", ""))
	if tid != "hafenstadt" and tid != "kuestenstrasse" and theme != "harbour" and theme != "coast":
		return

	var life := GxHarbourLife.new()
	life.name = "GxHarbourLife"
	var quay_z: float = float(def.get("quay_z", 346.0))
	if tid == "hafenstadt":
		life._p0 = Vector3(-350.0, -1.2, quay_z + 42.0)
		life._p1 = Vector3(270.0, -1.2, quay_z + 42.0)
		life._water_y = -1.2
	elif tid == "kuestenstrasse":
		# Basin off the harbour back straight
		var kf := Gx.frame(c, 980.0, Gx.LEFT, 45.0)
		life._p0 = kf * Vector3(-90, -1.0, 30)
		life._p1 = kf * Vector3(90, -1.0, 30)
		life._water_y = life._p0.y

	life._setup(c)
	c.add_child(life)


func _setup(c: Node3D) -> void:
	_x = _p0.x
	_tug = Node3D.new()
	_tug.name = "Tugboat"
	_tug.position = _p0
	add_child(_tug)

	var is_night: bool = Car.night
	var w = c.get("weather")
	if w != null and "preset" in w:
		if float(w.preset.get("night", 0.0)) > 0.0:
			is_night = true

	_build_tugboat(_tug, is_night)


func _build_tugboat(holder: Node3D, night: bool) -> void:
	var g := GxGeo.new()
	# Tug proportions: length 22 m, beam 6.4 m, hull depth 3.2 m
	var L := 22.0
	var W := 6.4
	var hw := W * 0.5
	var hl := L * 0.5

	# 1. Hull (dark navy / black steel with red anti-fouling boot-topping)
	g.col = Color(0.12, 0.13, 0.16) # dark hull
	# Main hull body
	g.box("painted_metal", Vector3(0, 0.8, 0), Vector3(L - 4.0, 1.8, W), 0.15)
	# Red bottom hull (anti-fouling)
	g.col = Color(0.62, 0.14, 0.1)
	g.box("painted_metal", Vector3(0, -0.4, 0), Vector3(L - 4.2, 1.0, W - 0.4), 0.12)

	# Flared bow
	g.col = Color(0.12, 0.13, 0.16)
	g.box("painted_metal", Vector3(hl - 1.2, 1.1, 0), Vector3(2.6, 2.2, W - 1.2), 0.3)
	# Heavy rubber bow fender (pusher block)
	g.col = Color(0.06, 0.06, 0.06)
	g.box("rubber", Vector3(hl + 0.2, 1.2, 0), Vector3(0.6, 1.8, 2.4), 0.12)
	# Rounded stern with tow deck
	g.box("rubber", Vector3(-hl + 0.8, 1.0, 0), Vector3(2.0, 1.6, W - 0.8), 0.3)

	# White sheer line / bulwark rail
	g.col = Color(0.88, 0.88, 0.85)
	g.box("painted_metal", Vector3(0, 1.8, hw - 0.08), Vector3(L - 2.0, 0.25, 0.12))
	g.box("painted_metal", Vector3(0, 1.8, -hw + 0.08), Vector3(L - 2.0, 0.25, 0.12))

	# 2. Deckhouse & Raised Wheelhouse
	# Main deckhouse (white/buff)
	g.col = Color(0.85, 0.84, 0.8)
	g.box("painted_metal", Vector3(1.0, 2.3, 0), Vector3(11.0, 1.3, W - 1.6), 0.08)
	# Raised wheelhouse
	g.col = Color(0.88, 0.88, 0.86)
	g.box("painted_metal", Vector3(2.6, 3.8, 0), Vector3(4.8, 1.8, 4.2), 0.08)
	# Wheelhouse sun visor / brow
	g.col = Color(0.35, 0.35, 0.38)
	g.box("painted_metal", Vector3(2.6, 4.75, 0), Vector3(5.2, 0.14, 4.6), 0.03)

	# Windows (day: tinted grey, night: warm emissive)
	var win_mat := "emit_warm" if night else "glass"
	g.col = Color.WHITE
	# Front bridge windows
	g.box(win_mat, Vector3(5.02, 3.9, 0), Vector3(0.04, 0.9, 3.4))
	# Side bridge windows
	for s: float in [-1.0, 1.0]:
		g.box(win_mat, Vector3(2.6, 3.9, s * 2.12), Vector3(3.6, 0.9, 0.04))

	# 3. Funnel stack & exhaust
	g.col = Color(0.12, 0.12, 0.14)
	g.box("painted_metal", Vector3(-2.8, 4.0, 0), Vector3(1.8, 2.6, 1.4), 0.1)
	# Red livery band on funnel
	g.col = Color(0.82, 0.16, 0.12)
	g.box("painted_metal", Vector3(-2.8, 4.2, 0), Vector3(1.84, 0.7, 1.44), 0.08)

	# 4. Mast with radar & navigation lights
	g.col = Color(0.85, 0.85, 0.82)
	g.bar("steel", Vector3(3.2, 4.8, 0), Vector3(3.2, 8.4, 0), 0.06, 6)
	g.bar("steel", Vector3(3.2, 6.6, -1.4), Vector3(3.2, 6.6, 1.4), 0.035, 4) # yardarm

	# Navigation lights:
	# Starboard (right / +z when facing +x): GREEN
	g.col = Color.WHITE
	g.box("emit_green", Vector3(3.2, 6.6, 1.45), Vector3(0.12, 0.16, 0.12))
	# Port (left / -z when facing +x): RED
	g.box("emit_red", Vector3(3.2, 6.6, -1.45), Vector3(0.12, 0.16, 0.12))
	# Masthead light (forward white): WHITE
	g.box("emit_white", Vector3(3.25, 8.2, 0), Vector3(0.14, 0.18, 0.14))
	# Stern light (aft white): WHITE
	g.box("emit_white", Vector3(-hl + 0.4, 2.2, 0), Vector3(0.12, 0.14, 0.12))

	# 5. Work deck fittings (tow winch & bitts)
	g.col = Color(0.2, 0.2, 0.22)
	g.box("steel", Vector3(-5.5, 1.8, 0), Vector3(2.2, 0.9, 2.4), 0.05) # winch drum
	g.tube("steel", [Vector3(-8.2, 1.6, -1.2), Vector3(-8.2, 2.4, -1.2)], 0.14, 8, true) # bitt
	g.tube("steel", [Vector3(-8.2, 1.6, 1.2), Vector3(-8.2, 2.4, 1.2)], 0.14, 8, true)

	var root := g.commit(holder, "TugMesh", 700.0, false)
	_setup_materials(root, night)


func _process(dt: float) -> void:
	# Camera distance culling
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	if cam.global_position.distance_squared_to(_tug.global_position) > 650.0 * 650.0:
		return

	_time += dt

	# Cruising along X
	if _turning > 0.0:
		_turning -= dt
		var target_yaw := 0.0 if _dir > 0.0 else PI
		_tug.rotation.y = lerp_angle(_tug.rotation.y, target_yaw, 3.0 * dt)
	else:
		_x += _dir * _speed * dt
		_tug.position.x = _x
		var t_dist := (_p1.x - _p0.x)
		if (_dir > 0.0 and _x >= _p1.x) or (_dir < 0.0 and _x <= _p0.x):
			_dir = -_dir
			_turning = 2.4

	# Gentle water heave & roll
	_tug.position.y = _water_y + sin(_time * 1.6) * 0.07
	_tug.rotation.z = sin(_time * 1.2) * 0.022
	_tug.rotation.x = sin(_time * 0.9) * 0.012


static func _setup_materials(root: Node, night: bool) -> void:
	for ch in root.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(ch as GeometryInstance3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			var mat_name := str(ch.name)
			if mat_name == "emit_green":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(0.1, 0.95, 0.25)
				em.emission_enabled = true
				em.emission = Color(0.1, 0.95, 0.25)
				em.emission_energy_multiplier = 7.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em
			elif mat_name == "emit_red":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(0.95, 0.12, 0.1)
				em.emission_enabled = true
				em.emission = Color(0.95, 0.12, 0.1)
				em.emission_energy_multiplier = 7.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em
			elif mat_name == "emit_white":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.98, 0.92)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.98, 0.92)
				em.emission_energy_multiplier = 7.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em
			elif mat_name == "emit_warm":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.85, 0.5)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.85, 0.5)
				em.emission_energy_multiplier = 4.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em
