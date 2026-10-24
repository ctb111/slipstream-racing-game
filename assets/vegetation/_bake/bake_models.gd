extends SceneTree
## Offline card baker (dev tool, not used by the game). Renders every node of the
## given glTF plant models from the side (orthographic, transparent background)
## into albedo + view-space-normal PNGs, one pair per node and view angle.
##   tools/bgrun.sh "" -s res://assets/vegetation/_bake/bake_models.gd -- \
##       --src=<dir with <id>/<id>_2k.gltf> --out=<dir> --ids=grass_medium_01,fern_02 --px=512 --yaws=0,90

const NORMAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 n = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);
	ALBEDO = n * 0.5 + 0.5;
}
"""

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_run.call_deferred()


func _run() -> void:
	var src: String = _args.get("src", "")
	var out: String = _args.get("out", "")
	var px := int(_args.get("px", "512"))
	var pitch := deg_to_rad(float(_args.get("pitch", "0")))
	var yaws: Array = Array(String(_args.get("yaws", "0")).split(",")).map(func(s: String) -> float: return float(s))
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var nmat := ShaderMaterial.new()
	nmat.shader = Shader.new()
	nmat.shader.code = NORMAL_SHADER
	var info := {}

	for id: String in String(_args.get("ids", "")).split(","):
		var path := "%s/%s/%s_2k.gltf" % [src, id, id]
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			push_error("cannot load " + path)
			continue
		var scene: Node3D = doc.generate_scene(state)
		var meshes: Array[MeshInstance3D] = []
		_collect(scene, meshes)
		for mi in meshes:
			mi.get_parent().remove_child(mi)
		for mi in meshes:
			var holder := Node3D.new()
			vp.add_child(holder)
			holder.add_child(mi)
			mi.transform = Transform3D.IDENTITY
			var aabb := mi.get_aabb()
			# Stand the plant on its base, centred on the origin.
			mi.position = -Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
			var albedo_mats: Array[Material] = []
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				var um: BaseMaterial3D = m.duplicate() if m is BaseMaterial3D else StandardMaterial3D.new()
				um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				um.cull_mode = BaseMaterial3D.CULL_DISABLED
				um.vertex_color_use_as_albedo = false
				albedo_mats.append(um)
			for yaw: float in yaws:
				holder.rotation = Vector3(pitch, deg_to_rad(yaw), 0)
				# Frame the rotated bounds: width across the view, full height.
				var xf := holder.transform * mi.transform
				var b := xf * aabb
				var w := maxf(b.size.x, b.size.y) * 1.02
				cam.size = w
				var cy := b.get_center().y if pitch != 0.0 else b.position.y + w * 0.5 - 0.001
				cam.position = Vector3(b.get_center().x, cy, 50.0)
				cam.rotation = Vector3.ZERO
				var name := "%s__%s__y%d_p%d" % [id, mi.name, int(yaw), int(rad_to_deg(pitch))]
				for pass_i in 2:
					for s in mi.mesh.get_surface_count():
						mi.set_surface_override_material(s, albedo_mats[s] if pass_i == 0 else nmat)
					await process_frame
					await process_frame
					await RenderingServer.frame_post_draw
					var img := vp.get_texture().get_image()
					img.save_png("%s/%s_%s.png" % [out, name, "albedo" if pass_i == 0 else "normal"])
				info[name] = {"width_m": w, "size_m": [b.size.x, b.size.y, b.size.z]}
			holder.queue_free()
		scene.queue_free()
	var f := FileAccess.open(out + "/info.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, "\t"))
	f.close()
	print("baked ", info.size())
	quit()


func _collect(n: Node, into: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		into.append(n)
	for c in n.get_children():
		_collect(c, into)
