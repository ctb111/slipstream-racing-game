class_name FallingLeaves
extends GPUParticles3D
## Autumn leaves tumbling down around the active camera: one small GPU particle
## box that follows the camera (local coords off, so leaves stay in the world
## as you drive through them). ~260 tiny two-sided quads, no lights, no shadows.

const BOX := Vector3(34, 14, 34)


static func attach(parent: Node3D, snowing: bool) -> void:
	if snowing or OS.has_environment("VEG_OFF"):
		return
	var p := FallingLeaves.new()
	p.name = "FallingLeaves"
	parent.add_child(p)


func _ready() -> void:
	amount = [140, 200, 260, 320][clampi(Game.quality, 0, 3)]
	lifetime = 9.0
	preprocess = 9.0
	local_coords = false
	fixed_fps = 30
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(-BOX * 0.5 - Vector3(10, 20, 10), BOX + Vector3(20, 30, 20))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = BOX * 0.5
	pm.direction = Vector3(0.6, -1.0, 0.25)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.5, -0.9, 0.2) # drag-limited fall, drifting downwind
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.2
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.15
	pm.turbulence_influence_max = 0.35
	pm.angular_velocity_min = -220.0
	pm.angular_velocity_max = 220.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.particle_flag_rotate_y = true
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(0.85, 0.45, 0.08), Color(0.7, 0.18, 0.05), Color(0.9, 0.65, 0.12),
		Color(0.5, 0.28, 0.1), Color(0.8, 0.35, 0.06)])
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_initial_ramp = gt
	# Fade in/out at the ends of life so nothing pops.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.9, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.07)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.85
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.3, 0.1)
	q.material = m
	draw_pass_1 = q


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		# Lead the camera a little so leaves are ahead of a moving car.
		var ahead := -cam.global_transform.basis.z
		global_position = cam.global_position + Vector3(ahead.x, 0, ahead.z) * 10.0 + Vector3.UP * 3.0
