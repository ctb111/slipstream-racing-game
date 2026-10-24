extends Node3D
## Close-up screenshots of CarDirt on real Car nodes: one car per run, a few
## camera angles, forced dirt amount and kind, and the weather's sky + grip.
## Run windowed in the background:
##   tools/bgrun.sh res://tests/dirt_preview.tscn -- car=<id>[,<id>..] kind=dust|mud|snow|wet|none amount=1 \
##       weather=clear|storm|snow views=rear,side,front,wheel,glass out=<dir> [paint=<index>]

var out_dir := "user://dirt_preview"
var car_ids: Array = [CarCatalog.DEFAULT]
var kind := "dust"
var amount := 1.0
var weather := "clear"
var views := ["rear", "side", "front"]
var paint := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"car": car_ids = Array(kv[1].split(","))
			"kind": kind = kv[1]
			"amount": amount = kv[1].to_float()
			"weather": weather = kv[1]
			"views": views = Array(kv[1].split(","))
			"out": out_dir = kv[1]
			"paint": paint = kv[1].to_int()
	DirAccess.make_dir_recursive_absolute(out_dir)
	Car.weather_road_grip = {"clear": 1.0, "storm": 0.8, "snow": 0.62}.get(weather, 1.0)
	Car.weather_off_grip = {"clear": 1.0, "storm": 0.75, "snow": 0.5}.get(weather, 1.0)
	CarDirt._read_args()
	CarDirt._forced = amount if kind != "none" else 0.0
	CarDirt._forced_kind = kind if kind != "none" else "dust"
	CarDirt._off = kind == "stock" # the untouched StandardMaterial3Ds, for A/B timing
	CarDirt._no_glass = "noglass" in OS.get_cmdline_user_args()
	_env()
	for id in car_ids:
		await _shoot(id)
	get_tree().quit()


func _shoot(car_id: String) -> void:
	var car := Car.new()
	car.model_id = car_id
	car.player_controlled = false
	car.paint_color = CarPalette.pick(paint)
	car.position = Vector3(0, 0.9, 0)
	add_child(car)
	car.locked = true
	var cam := Camera3D.new()
	cam.fov = 38.0
	add_child(cam)
	await get_tree().create_timer(1.5).timeout
	for v in views:
		var look := Vector3(0, 0.55, 0)
		match v:
			"rear": cam.position = Vector3(3.6, 1.5, 4.6)
			"side": cam.position = Vector3(-6.2, 0.75, 0.3)
			"front": cam.position = Vector3(-3.6, 1.3, -4.8)
			"wheel":
				cam.position = Vector3(-2.6, 0.55, 2.4)
				look = Vector3(-0.8, 0.35, car.axle_rear_z + 0.1)
			"glass":
				cam.position = Vector3(-0.9, 1.9, -3.2)
				look = Vector3(0, 0.95, -0.6)
			"top": cam.position = Vector3(-2.5, 4.5, -3.5)
			"chase": # the race's chase camera distance
				cam.position = Vector3(0.0, 1.9, 6.2)
				look = Vector3(0, 0.9, 0)
		cam.look_at(look)
		await get_tree().create_timer(0.6).timeout
		if "perf" in OS.get_cmdline_user_args():
			# Frame time with vsync off (run with --disable-vsync), dirt materials
			# vs stock ones alternated in this one process so drift cancels out.
			# (Metal reports 0 for the measured GPU render time.)
			var dirt: CarDirt
			for c in car.get_children():
				if c is CarDirt:
					dirt = c
			var res := [[], [], []]
			CarDirt._force_lod = 3 # hold: _update_lod() leaves the variant alone
			for round in 18:
				var lod := round % 3
				dirt._apply_lod(lod)
				await get_tree().create_timer(0.15).timeout
				var last := Time.get_ticks_usec()
				for f in 70:
					await RenderingServer.frame_post_draw
					var now := Time.get_ticks_usec()
					if f >= 20:
						res[lod].append((now - last) / 1000.0)
					last = now
			for lod in 3:
				var t: Array = res[lod]
				t.sort()
				print("frame %s %s %s %s: median %.3f ms" % [car_id, kind, v, ["stock ", "light ", "detail"][lod], t[t.size() / 2]])
			CarDirt._force_lod = 0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/dirt_%s_%s_%s_%s.png" % [out_dir, car_id, kind, weather, v])
	car.queue_free()
	cam.queue_free()
	await get_tree().process_frame


func _env() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	var hdri: String = {"clear": "kloofendal_48d_partly_cloudy_puresky_4k.hdr", "storm": "kloofendal_overcast_puresky_2k.hdr",
		"snow": "snow_field_puresky_2k.hdr"}.get(weather, "kloofendal_48d_partly_cloudy_puresky_4k.hdr")
	pano.panorama = load("res://assets/hdri/" + hdri)
	sky.sky_material = pano
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = not ("nossao" in OS.get_cmdline_user_args())
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 2.0 if weather == "clear" else 0.5
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.set_meta("grip", 1.0)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	cs.position.y = -0.5
	ground.add_child(cs)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.2, 0.2, 0.21) if weather != "snow" else Color(0.75, 0.77, 0.8)
	gm.roughness = 0.85 if weather == "clear" else 0.3
	g.material_override = gm
	ground.add_child(g)
	add_child(ground)
