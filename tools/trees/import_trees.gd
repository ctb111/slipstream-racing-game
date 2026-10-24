extends SceneTree
## Dev tool: turns the tree bakes of tools/trees/gen_trees.py (<name>.bin, two
## LODs each) into ArrayMesh resources for Vegetation.model():
##   res://assets/vegetation/trees/models/<name>_near.res (indexed, tangents)
##   res://assets/vegetation/trees/models/<name>_far.res  (unindexed: the forest
##   merges far meshes per cell with packed-array appends)
##   tools/hrun.sh -s res://tools/trees/import_trees.gd -- --src=<dir with .bin>

const OUT := "res://assets/vegetation/trees/models/"


func _initialize() -> void:
	var src := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(src):
		if not f.ends_with(".bin"):
			continue
		var fa := FileAccess.open(src.path_join(f), FileAccess.READ)
		var name := f.get_basename()
		for lod in ["near", "far"]:
			var n := fa.get_32()
			var ni := fa.get_32()
			var pos := fa.get_buffer(n * 12).to_float32_array()
			var nrm := fa.get_buffer(n * 12).to_float32_array()
			var uv := fa.get_buffer(n * 8).to_float32_array()
			var uv2 := fa.get_buffer(n * 8).to_float32_array()
			var col := fa.get_buffer(n * 16).to_float32_array()
			var idx := fa.get_buffer(ni * 4).to_int32_array()
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			var pv := PackedVector3Array()
			var nv := PackedVector3Array()
			var uvv := PackedVector2Array()
			var uv2v := PackedVector2Array()
			var cv := PackedColorArray()
			pv.resize(n); nv.resize(n); uvv.resize(n); uv2v.resize(n); cv.resize(n)
			for i in n:
				pv[i] = Vector3(pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2])
				nv[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]).normalized()
				uvv[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
				uv2v[i] = Vector2(uv2[i * 2], uv2[i * 2 + 1])
				cv[i] = Color(col[i * 4], col[i * 4 + 1], col[i * 4 + 2], col[i * 4 + 3])
			arr[Mesh.ARRAY_VERTEX] = pv
			arr[Mesh.ARRAY_NORMAL] = nv
			arr[Mesh.ARRAY_TEX_UV] = uvv
			arr[Mesh.ARRAY_TEX_UV2] = uv2v
			arr[Mesh.ARRAY_COLOR] = cv
			arr[Mesh.ARRAY_INDEX] = idx
			var st := SurfaceTool.new()
			st.create_from_arrays(arr)
			st.generate_tangents()
			if lod == "far":
				st.deindex()
			var mesh := st.commit()
			var err := ResourceSaver.save(mesh, OUT + "%s_%s.res" % [name, lod], ResourceSaver.FLAG_COMPRESS)
			print("%s %s: %d verts, %d tris, err %d" % [name, lod, mesh.surface_get_array_len(0), (ni / 3), err])
	quit()
