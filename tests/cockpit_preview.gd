extends Node3D
## Visual check of the in-car views: builds each car (a real, frozen Car) on a
## plain ground plane under a sun and screenshots
##   top  - orthographic cutaway from inside the cabin (roof clipped): layout
##   eye  - camera at a given car-local point looking forward
## Run windowed in the background:
##   tools/bgrun.sh res://tests/cockpit_preview.tscn -- car=<id> views=top,eye eye=x,y,z out=<dir>

var out_dir := "/tmp/cockpit_preview"
var ids: Array = []
var views := ["top", "side"]
var eye := Vector3(-0.37, 0.45, 0.1)
var look := Vector3.ZERO
var fov := 70.0
var steer := 0.0
var cockpit_on := false
var top_y := 0.42


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit()) # never hang a background run
	for a in OS.get_cmdline_user_args():
		if a.begins_with("car="):
			ids = a.substr(4).split(",")
		elif a.begins_with("out="):
			out_dir = a.substr(4)
		elif a.begins_with("views="):
			views = Array(a.substr(6).split(","))
		elif a.begins_with("eye="):
			var v := a.substr(4).split_floats(",")
			eye = Vector3(v[0], v[1], v[2])
		elif a.begins_with("look="):
			var v := a.substr(5).split_floats(",")
			look = Vector3(v[0], v[1], v[2])
		elif a.begins_with("topy="):
			top_y = a.substr(5).to_float()
		elif a.begins_with("steer="):
			steer = a.substr(6).to_float()
		elif a == "rain":
			Car.weather_road_grip = 0.8
		elif a == "snow":
			Car.weather_road_grip = 0.62
			Car.weather_off_grip = 0.5
		elif a.begins_with("fov="):
			fov = a.substr(4).to_float()
	if ids.is_empty():
		ids = CarCatalog.available_ids()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_env()
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for id in ids:
		var car := Car.new()
		car.model_id = id
		car.freeze = true
		car.player_controlled = false
		car.position = Vector3(0, 0.54, 0)
		add_child(car)
		await get_tree().process_frame
		car.steer_input = steer
		if "lamp" in OS.get_cmdline_user_args():
			var lamp := OmniLight3D.new()
			lamp.omni_range = 3.0
			lamp.light_energy = 1.5
			lamp.position = Cockpit.spec_for(id).eye + Vector3(0, 0.05, 0.1)
			car.add_child(lamp)
		if "speceye" in OS.get_cmdline_user_args():
			eye = Cockpit.spec_for(id).eye
		var cp: Cockpit
		if "cockpit" in views or "cockpit_wide" in views or "cslice" in views:
			cp = Cockpit.new()
			cp.car = car
			cp.show_cut = "showcut" in OS.get_cmdline_user_args()
			car.add_child(cp)
			cp.set_active(true)
		for view in views:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.near = 0.02
			cam.fov = fov
			match view:
				"top":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 3.0
					cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), car.to_global(Vector3(0, top_y, 0)))
				"side": # cut at the centreline, looking at the left half
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 2.6
					cam.global_transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), car.to_global(Vector3(-0.02, 0.2, 0)))
				"sider":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 2.6
					cam.global_transform = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), car.to_global(Vector3(0.02, 0.2, 0)))
				"slice", "cslice": # driver's side, cut at x = eye.x + 0.25 towards the centre, 0.1 m grid
					var sx := 1.0 if eye.x < 0.0 else -1.0
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 1.2
					cam.global_transform = Transform3D(Basis.looking_at(Vector3(-sx, 0, 0), Vector3.UP), car.to_global(Vector3(eye.x + 0.25 * sx, 0.3, -0.45)))
					_grid(car, eye.x + 0.2 * sx, true)
				"cockpit", "cockpit_wide":
					var e := cp.eye_transform()
					cam.fov = fov if view == "cockpit" else 85.0
					cam.global_transform = car.global_transform * e
					if look != Vector3.ZERO:
						cam.look_at(car.to_global(look), car.global_basis.y)
				"eye":
					cam.global_position = car.to_global(eye)
					var l := look if look != Vector3.ZERO else eye + Vector3(0, -0.05, -3.0)
					cam.look_at(car.to_global(l), Vector3.UP)
			for i in (240 if "rain" in OS.get_cmdline_user_args() else 30):
				await get_tree().process_frame
			if view == "cslice":
				eye = cp.eye
			for a in OS.get_cmdline_user_args():
				if a.begins_with("pick="): # pick=u,v;u,v (pixels at 1600x900): print car-local hits
					for pair in a.substr(5).split(";"):
						var uv := pair.split_floats(",")
						var from := cam.project_ray_origin(Vector2(uv[0], uv[1]))
						var dir := cam.project_ray_normal(Vector2(uv[0], uv[1]))
						print("pick %s -> %s" % [pair, _pick(car, car.to_local(from), car.global_basis.inverse() * dir)])
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out_dir, id, view])
		car.queue_free()
		await get_tree().process_frame
	get_tree().quit()


func _pick(car: Car, from: Vector3, dir: Vector3) -> Vector3:
	var mi := car.get_node("Body/Model") as MeshInstance3D
	var best := INF
	for sidx in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(sidx)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var m = mi.get_surface_override_material(sidx)
		if m is BaseMaterial3D and m.transparency != 0:
			continue
		for t in range(0, idx.size(), 3):
			var a := v[idx[t]] + mi.position
			var hit = Geometry3D.ray_intersects_triangle(from, dir, a, v[idx[t + 1]] + mi.position, v[idx[t + 2]] + mi.position)
			if hit != null:
				best = minf(best, from.distance_to(hit))
	return (from + dir * best).snapped(Vector3.ONE * 0.005) if best < INF else Vector3.INF


var _grid_mi: MeshInstance3D


## 0.1 m grid drawn over everything, in the car's YZ plane at x (red lines every 0.5 m, green = 0).
func _grid(car: Node3D, x: float, yz: bool) -> void:
	if _grid_mi:
		_grid_mi.queue_free()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-10, 16):
		var v := i * 0.1
		var c := Color(0, 1, 0, 0.8) if i == 0 else (Color(1, 0.2, 0.2, 0.7) if i % 5 == 0 else Color(1, 1, 1, 0.25))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x, v, -2.5))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x, v, 1.5))
	for i in range(-25, 16):
		var v := i * 0.1
		var c := Color(0, 1, 0, 0.8) if i == 0 else (Color(1, 0.2, 0.2, 0.7) if i % 5 == 0 else Color(1, 1, 1, 0.25))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x, -1.0, v))
		im.surface_set_color(c)
		im.surface_add_vertex(Vector3(x, 1.5, v))
	im.surface_end()
	_grid_mi = MeshInstance3D.new()
	_grid_mi.mesh = im
	car.add_child(_grid_mi)


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
	pm.size = Vector2(200, 200)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.25, 0.26)
	gm.roughness = 0.9
	g.material_override = gm
	add_child(g)
