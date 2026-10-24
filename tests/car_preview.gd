extends Node3D
## Visual check of every CarCatalog model: builds body + wheels from
## CarModel.data(id) (paint recoloured from the catalog), screenshots a 3/4
## front view and a side view, prints wheel-centring stats, then quits.
## Run non-headless:  godot res://tests/car_preview.tscn [-- car=<id>] [-- out=<dir>]

var out_dir := "user://car_preview"
var ids: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("car="):
			ids = [a.substr(4)]
		elif a.begins_with("out="):
			out_dir = a.substr(4)
	if ids.is_empty():
		ids = CarCatalog.available_ids()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_env()
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	for id in ids:
		var t0 := Time.get_ticks_msec()
		var car := _build(id)
		print("%s built in %d ms" % [id, Time.get_ticks_msec() - t0])
		for view in ["front", "side", "rear"]:
			match view:
				"front": cam.position = Vector3(-4.2, 1.6, -5.2)
				"side": cam.position = Vector3(-8.5, 0.9, 0.0)
				"rear": cam.position = Vector3(3.8, 1.8, 5.4)
			cam.look_at(Vector3(0, 0.55, 0))
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/car_%s_%s.png" % [out_dir, id, view])
		car.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _build(id: String) -> Node3D:
	var d := CarModel.data(id)
	var spec := CarCatalog.get_car(id)
	var car := Node3D.new()
	add_child(car)
	var hub_y := 0.0
	for w in d.wheels:
		hub_y += w.centre.y / d.wheels.size()
	var ground: float = hub_y - d.wheel_radius
	car.position.y = -ground
	var mi := MeshInstance3D.new()
	mi.mesh = d.body
	for i in d.surface_mats.size():
		var m: Material = d.surface_mats[i]
		if i == d.paint_surface and m is BaseMaterial3D:
			var p: BaseMaterial3D = m.duplicate()
			p.albedo_color = spec.get("paint_color", Color.RED)
			p.albedo_texture = null
			p.metallic = 0.3
			p.roughness = 0.32
			p.clearcoat_enabled = true
			m = p
		elif i == d.brake_surface and m is BaseMaterial3D:
			var l: BaseMaterial3D = m.duplicate()
			l.emission_enabled = true
			l.emission = Color(1, 0.05, 0.03)
			l.emission_energy_multiplier = 2.0
			m = l
		mi.set_surface_override_material(i, m)
	car.add_child(mi)
	print("  %s: surfaces %d paint=%d brake=%d lights=%d radius=%.3f width=%.3f body=%s" % [id, d.surface_mats.size(),
		d.paint_surface, d.brake_surface, d.lights_surface, d.wheel_radius, d.wheel_width, d.body_aabb])
	for w in d.wheels:
		var wm := MeshInstance3D.new()
		wm.mesh = w.mesh
		for k in w.mats.size():
			wm.set_surface_override_material(k, w.mats[k])
		wm.position = w.centre
		# Spin each wheel a bit: a badly centred wheel shows up as offset from its arch.
		wm.rotation.x = 0.7
		car.add_child(wm)
		var a: AABB = w.mesh.get_aabb()
		print("    wheel %s%s centre %s  aabb-centre y/z %.3f %.3f  size %s" % ["F" if w.front else "R", "L" if w.left else "R",
			w.centre.snapped(Vector3.ONE * 0.001), a.get_center().y, a.get_center().z, a.size.snapped(Vector3.ONE * 0.001)])
	return car


func _env() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_4k.hdr")
	sky.sky_material = pano
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.25, 0.26)
	gm.roughness = 0.9
	g.material_override = gm
	add_child(g)
