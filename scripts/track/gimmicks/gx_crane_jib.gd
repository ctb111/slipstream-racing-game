class_name GxCraneJib
extends Node3D
## Slewing superstructure for tower cranes (GxIndustrial):
## Slowly slews back and forth, red apex obstruction light at night.
## Merged mesh (1 draw call), no shadows, distance culled.

var _base_yaw := 0.0
var _phase := 0.0
var _time := 0.0


static func build(holder: Node3D, xf: Transform3D, top: Vector3, yaw: float, paint: Color, jib_len: float, cj: float, rng: RandomNumberGenerator) -> GxCraneJib:
	var jib_node := GxCraneJib.new()
	jib_node.name = "CraneJib"
	# Position at top of mast in world/holder space
	jib_node.position = top
	jib_node.rotation.y = yaw
	jib_node._base_yaw = yaw
	jib_node._phase = rng.randf() * TAU
	holder.add_child(jib_node)

	# Build jib geometry in local coordinate frame (facing -z in local space)
	var g := GxGeo.new()
	# Slewing unit / ring
	g.col = Color(0.25, 0.25, 0.25)
	g.box("painted_metal", Vector3(0, 0.6, 0), Vector3(2.4, 1.2, 2.4), 0.05)
	# Cab
	g.col = Color(0.9, 0.9, 0.88)
	g.box("painted_metal", Vector3(1.6, 1.4, -1.6), Vector3(1.8, 2.0, 1.6), 0.08)

	# Main triangular lattice jib along -z
	var jt := Vector3(0, 1.4, 0)
	var pts_b1 := [jt + Vector3(-0.7, 0, 0), jt + Vector3(-0.7, 0, -jib_len)]
	var pts_b2 := [jt + Vector3(0.7, 0, 0), jt + Vector3(0.7, 0, -jib_len)]
	var pts_t := [jt + Vector3(0, 1.4, 0), jt + Vector3(0, 0.6, -jib_len)]
	g.col = paint
	g.beam("painted_metal", pts_b1[0], pts_b1[1], 0.14)
	g.beam("painted_metal", pts_b2[0], pts_b2[1], 0.14)
	g.beam("painted_metal", pts_t[0], pts_t[1], 0.12)
	var nj := int(jib_len / 2.5)
	for k in nj:
		var f0 := float(k) / nj
		var f1 := float(k + 1) / nj
		var b1a: Vector3 = pts_b1[0].lerp(pts_b1[1], f0)
		var b2a: Vector3 = pts_b2[0].lerp(pts_b2[1], f0)
		var ta: Vector3 = pts_t[0].lerp(pts_t[1], f0)
		var b1b: Vector3 = pts_b1[0].lerp(pts_b1[1], f1)
		var b2b: Vector3 = pts_b2[0].lerp(pts_b2[1], f1)
		g.beam("painted_metal", b1a, pts_t[0].lerp(pts_t[1], f1), 0.05)
		g.beam("painted_metal", b2a, pts_t[0].lerp(pts_t[1], f1), 0.05)
		g.beam("painted_metal", b1a, b2a, 0.05)
		g.beam("painted_metal", ta, b1b, 0.05)
		g.beam("painted_metal", ta, b2b, 0.05)

	# Counter-jib along +z
	g.beam("painted_metal", jt + Vector3(-0.7, 0, 0), jt + Vector3(-0.7, 0, cj), 0.14)
	g.beam("painted_metal", jt + Vector3(0.7, 0, 0), jt + Vector3(0.7, 0, cj), 0.14)
	for k in int(cj / 2.0):
		g.beam("painted_metal", jt + Vector3(-0.7, 0, k * 2.0), jt + Vector3(0.7, 0, k * 2.0 + 2.0), 0.05)
	# Concrete counterweights
	g.col = Color(0.6, 0.6, 0.58)
	g.box("concrete", jt + Vector3(0, -0.6, cj - 1.8), Vector3(2.2, 2.4, 2.0), 0.05)

	# A-frame & tension pendants
	g.col = paint
	var apex := jt + Vector3(0, 7.0, 0)
	g.beam("painted_metal", jt + Vector3(-0.7, 0, 0), apex, 0.12)
	g.beam("painted_metal", jt + Vector3(0.7, 0, 0), apex, 0.12)
	g.col = Color(0.2, 0.2, 0.2)
	g.bar("steel", apex, jt + Vector3(0, 0.8, -jib_len * 0.7), 0.03, 4)
	g.bar("steel", apex, jt + Vector3(0, 0, cj), 0.03, 4)

	# Trolley & hoist hook
	var frac := rng.randf_range(0.35, 0.75)
	var tp := jt + Vector3(0, 0, -jib_len * frac)
	g.col = Color(0.85, 0.85, 0.85)
	g.box("painted_metal", tp, Vector3(1.2, 0.4, 1.2))
	var hook_drop := rng.randf_range(10.0, 24.0)
	g.bar("steel", tp, tp + Vector3(0, -hook_drop, 0), 0.02, 3)
	g.col = Color(0.9, 0.7, 0.05)
	g.box("painted_metal", tp + Vector3(0, -hook_drop - 0.4, 0), Vector3(0.6, 0.8, 0.4), 0.05)

	# Red obstruction light at the apex
	g.col = Color.WHITE
	g.box("emit_red", apex + Vector3(0, 0.15, 0), Vector3(0.2, 0.3, 0.2))

	var root := g.commit(jib_node, "JibMesh", 900.0, false)
	for ch in root.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(ch as GeometryInstance3D).physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			if str(ch.name) == "emit_red":
				var em := StandardMaterial3D.new()
				em.albedo_color = Color(1.0, 0.1, 0.1)
				em.emission_enabled = true
				em.emission = Color(1.0, 0.1, 0.1)
				em.emission_energy_multiplier = 8.0
				em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				(ch as MeshInstance3D).material_override = em

	return jib_node


func _process(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	if cam.global_position.distance_squared_to(global_position) > 450.0 * 450.0:
		return

	_time += dt
	rotation.y = _base_yaw + sin(_time * 0.038 + _phase) * 0.42
