extends Node3D
## Dev preview of the baked poses: `tools/bgrun.sh res://assets/people/bake/preview.tscn -- --out=/path.png [--dist=6] [--lod=hi]`

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.4, 0.22)
	ground.material_override = gm
	add_child(ground)
	var lod: String = args.get("lod", "hi")
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	var cus: Array[Color] = []
	var x := -7.5
	var tops := [Color(0.62, 0.1, 0.08), Color(0.15, 0.22, 0.42), Color(0.78, 0.62, 0.12), Color(0.12, 0.3, 0.16), Color(0.7, 0.68, 0.62)]
	var k := 0
	for model in ([] if args.has("nolineup") else PeopleKit.MODELS.keys()):
		for pose in [0, 1, 2, 3, 4, 5]:
			if not PeopleKit.MODELS[model].has(pose):
				continue
			var mi := MultiMeshInstance3D.new()
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = PeopleKit.mesh(model, pose, lod)
			mm.instance_count = 1
			mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, PI + float(args.get("turn", "0"))), Vector3(x, 0.5 if pose == 3 else 0.0, 0)))
			mm.set_instance_color(0, tops[k % tops.size()])
			mm.set_instance_custom_data(0, Color(0.1 + k * 0.137, 0.8, 1.0, 0))
			mi.multimesh = mm
			mi.material_override = PeopleKit.material(model, pose, PeopleKit.Role.MARSHAL if pose == 4 else PeopleKit.Role.SPECTATOR)
			add_child(mi)
			if pose == 3:
				var seat := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.5, 0.45)
				seat.mesh = bm
				seat.position = Vector3(x, 0.25, 0.1)
				add_child(seat)
			x += 1.0
			k += 1
	if args.has("stand"):
		# Replica of TrackProps' grandstand terraces: track towards +X (r),
		# tiers step up towards -X, 20 m long along Z.
		var r := Vector3.RIGHT
		var t := Vector3.FORWARD
		var face := Basis.looking_at(r, Vector3.UP)
		var sx: Array[Transform3D] = []
		var sc: Array[Color] = []
		var su: Array[Color] = []
		var rng := RandomNumberGenerator.new()
		var rows := 9 if str(args.stand) == "full" else 6
		var glen := 110.0 if str(args.stand) == "full" else 20.0
		for row in rows:
			var c := -r * (row * 1.0 + 0.5)
			var tier := MeshInstance3D.new()
			var tb := BoxMesh.new()
			tb.size = Vector3(1.0, row * 1.1 + 0.6, glen)
			tier.mesh = tb
			tier.position = c + Vector3.UP * (row * 0.55 + 0.3)
			add_child(tier)
			var seat := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.45, 0.16, glen - 0.4)
			seat.mesh = sb
			seat.position = c + Vector3.UP * (row * 1.1 + 0.68) + r * 0.25
			add_child(seat)
			var per := int(glen / 0.62)
			for q in per:
				if rng.randf() < 0.25:
					continue
				var along := (q + 0.5) / per - 0.5
				var s := rng.randf_range(0.93, 1.07)
				sx.append(Transform3D(face.scaled(Vector3(s, s, s)), c + t * along * glen + Vector3.UP * (row * 1.1 + 0.76) + r * 0.1))
				sc.append(tops[rng.randi() % tops.size()])
				su.append(Color(rng.randf(), rng.randf(), 0, 0))
		add_child(PeopleKit.crowd("Grandstand", PeopleKit.Role.SEATED, sx, sc, su, false))
	if args.has("crowd"):
		var cx: Array[Transform3D] = []
		var cc: Array[Color] = []
		var cu: Array[Color] = []
		var rng := RandomNumberGenerator.new()
		for i in int(args.crowd):
			cx.append(Transform3D(Basis(Vector3.UP, PI + rng.randf_range(-0.4, 0.4)), Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-4, -12))))
			cc.append(tops[i % tops.size()])
			cu.append(Color(rng.randf(), rng.randf_range(0.3, 1.0) if rng.randf() < 0.75 else 0.0, 0, 0))
		add_child(PeopleKit.crowd("Crowd", PeopleKit.Role.SPECTATOR, cx, cc, cu))
	var cam := Camera3D.new()
	var d := float(args.get("dist", "6"))
	cam.position = Vector3(0, 1.3, d)
	cam.fov = 50
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0))
	if args.has("cam"):
		var cv: PackedFloat64Array = str(args.cam).split_floats(",")
		cam.position = Vector3(cv[0], cv[1], cv[2])
		cam.look_at(Vector3(cv[3], cv[4], cv[5]))
	_out = args.get("out", "/tmp/preview.png")
	_wait = float(args.get("wait", "1.0"))


var _out := ""
var _wait := 1.0


func _process(delta: float) -> void:
	if _out == "":
		return
	_wait -= delta
	if _wait < 0.0:
		print("draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			" primitives=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		for c in get_children():
			if c is PeopleKit.Crowd:
				print(c.name, " ", c.stats())
		get_viewport().get_texture().get_image().save_png(_out)
		get_tree().quit()
