extends Node3D
## Dev tool (not used by the game): lines up every tree variant on flat ground
## under the race sky and saves screenshots, to judge shapes, LODs and wind.
##   tools/bgrun.sh res://assets/vegetation/_bake/tree_gallery.tscn -- \
##       --out=/tmp/g.png [--wind=0.3] [--snow=0] [--far] [--species=0,1] \
##       [--cam=x,y,z] [--look=x,y,z] [--at=3] [--shots=1] [--dt=0.25]
## Species 0 spruce, 1 pine, 2 beech, 3 oak, 4 birch. --shots=N saves N frames
## `dt` seconds apart (out_0.png, out_1.png...) to see the wind moving.

var _args := {}
var _t := 0.0
var _shot := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_build.call_deferred()


func _vec(s: String, d: Vector3) -> Vector3:
	if s.is_empty():
		return d
	var v := s.split_floats(",")
	return Vector3(v[0], v[1], v[2])


func _build() -> void:
	get_window().size = Vector2i(1600, 900)
	var world := self
	WorldBuilder.build_environment(world)
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	var noise := NoiseTexture2D.new()
	noise.noise = n
	noise.width = 512
	noise.height = 512
	noise.seamless = true
	noise.generate_mipmaps = true
	await noise.changed
	await get_tree().process_frame
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(600, 600)
	ground.mesh = pm
	ground.material_override = WorldBuilder.terrain_material(noise)
	world.add_child(ground)
	var wind := float(_args.get("wind", "0.3"))
	var snow := float(_args.get("snow", "0"))
	var mats := [Vegetation.conifer_material(noise, wind, snow), Vegetation.broadleaf_material(noise, wind * 1.15, snow * 0.7)]
	var far := _args.has("far")
	if far:
		for i in 2:
			mats[i] = mats[i].duplicate()
			mats[i].set_shader_parameter("normal_depth", 0.0)
	var species: Array = Array(String(_args.get("species", "0,1,2,3,4")).split(",")).map(func(s: String) -> int: return int(s))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	var x := 0.0
	var z := 0.0
	for sp: int in species:
		x = 0.0
		# --models: the baked Sapling trees (5 maple, 6 olive, 7 stonepine, 8 cypress too).
		var names := ["spruce", "pine", "beech", "oak", "birch", "maple", "olive", "stonepine", "cypress"]
		var hs: Array = WorldBuilder.TREE_AGES[sp][0] if sp < 5 else [8.0, 8.0, 8.0, 8.0]
		for ai in hs.size():
			var h: float = hs[ai]
			var lods: Array
			if _args.has("models"):
				lods = Vegetation.model("%s_%d" % [names[sp], ai])
				if lods.is_empty():
					break
				h = (lods[0] as Mesh).get_aabb().size.y
			else:
				match sp:
					0: lods = Vegetation.spruce(rng, h)
					1: lods = Vegetation.pine(rng, h)
					_: lods = Vegetation.broadleaf(rng, h, sp)
			var mi := MeshInstance3D.new()
			mi.mesh = lods[1] if far else lods[0]
			mi.material_override = mats[0 if sp in [0, 1, 7, 8] else 1]
			mi.position = Vector3(x, 0, z)
			world.add_child(mi)
			x += h * 0.45 + 6.0
		z -= 22.0
	var cam := Camera3D.new()
	cam.fov = 50.0
	world.add_child(cam)
	cam.global_position = _vec(_args.get("cam", ""), Vector3(35, 6, 38))
	cam.look_at(_vec(_args.get("look", ""), Vector3(35, 9, -20)), Vector3.UP)
	cam.make_current()
	get_tree().process_frame.connect(_tick)


func _tick() -> void:
	if _t == 0.0:
		_t = Time.get_ticks_msec() / 1000.0
	var now := Time.get_ticks_msec() / 1000.0 - _t
	var at := float(_args.get("at", "3"))
	var dt := float(_args.get("dt", "0.25"))
	var shots := int(_args.get("shots", "1"))
	if now > at + _shot * dt:
		var out: String = _args.get("out", "/tmp/gallery.png")
		if shots > 1:
			out = out.get_basename() + "_%d.png" % _shot
		get_viewport().get_texture().get_image().save_png(out)
		_shot += 1
		if _shot >= shots:
			get_tree().quit()

