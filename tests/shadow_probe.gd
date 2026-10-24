extends Node3D
## Minimal shadow check: a box on a plane under a sun. --q=N applies Game quality.
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--q="):
			Game.quality = int(a.substr(4))
			Game.apply_viewport_quality(get_viewport())
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	plane.mesh = pm
	add_child(plane)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	box.position = Vector3(0, 1, 0)
	add_child(box)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.basis = Basis.looking_at(Vector3(0.375, -0.743, -0.554), Vector3.UP)
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 8)
	add_child(cam)
	cam.look_at(Vector3(0, 0.5, -1))
	await get_tree().create_timer(1.5).timeout
	for a in args:
		if a.begins_with("--out="):
			get_viewport().get_texture().get_image().save_png(a.substr(6))
	get_tree().quit()
