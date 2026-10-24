extends Node
## Debug (`--pop-audit`): every 0.25 s checks what the visibility ranges and the
## crowd LOD hide or double-draw near the current camera, the way Godot decides
## it (distance camera -> centre of the instance AABB). Prints a summary each
## second and a total at exit. Needs no rendering, so it runs headless too.
##   wrong_hidden:  instances closer than 0.9 x their range end (or the forest
##                  near range) that their node hides as a whole
##   forest_far:    trees closer than FOREST_FAR_OK m drawn with the far mesh
##   crowd_missing / crowd_double: figures in front of the camera within 150 m
##                  drawn by no LOD tier / by two tiers
##
## Appear audit (same flag): once, an inventory of every GeometryInstance3D whose
## visibility range ends early (end - AABB half-diagonal < 300 m, i.e. where its
## near edge appears) ranked by size x count; then every 0.1 s the instances that
## switch ON (range or `visible`) within APPEAR_D m in front of the camera, ranked
## by on-screen size at the moment they appear. A switch-on matched by a nearby
## switch-off in the same tick is an LOD swap and is not counted. Fading ones
## (fade mode != disabled with a margin) are listed separately as `soft`.

const FOREST_FAR_OK := 100.0

var _t := 0.0
var _print_t := 0.0
var _tot := {}
var _sec := {}
var _worst := {}
var _samples := 0


const APPEAR_D := 600.0
var _on := {} # GeometryInstance3D -> bool drawn last tick
var _app_t := 0.0
var _inv_done := false
var _first := true
var _shot_prefix := ""
var _shot_t := 0.0
var _shot_n := 0
var _appear := {} # key -> [count, max score, min dist, sum score, soft]


func _ready() -> void:
	process_priority = 1000 # after everything that moves cameras or updates LODs
	# `--pop-shots=<prefix>[,<start s>,<step s>,<count>,<burst>,<scale>]`:
	# `count` captures `step` s apart (default 12 x 0.5 s from 20 s, drive-ahead),
	# each a burst of `burst` CONSECUTIVE frames (flicker shows frame to frame),
	# kept in memory at `scale` and written when done: <prefix>_<capture>_<frame>.png.
	# `--pop-audit=shots` skips the (slow) audit and only captures.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pop-shots="):
			var v := a.trim_prefix("--pop-shots=").split(",")
			_shot_prefix = v[0]
			_shot_t = float(v[1]) if v.size() > 1 else 20.0
			_shot_step = float(v[2]) if v.size() > 2 else 0.5
			_shot_count = int(v[3]) if v.size() > 3 else 12
			_shot_burst = int(v[4]) if v.size() > 4 else 1
			_shot_scale = float(v[5]) if v.size() > 5 else 1.0
		if a == "--pop-audit=shots":
			_audit = false


var _shot_step := 0.5
var _shot_count := 12
var _shot_burst := 1
var _shot_scale := 1.0
var _shot_in_burst := 0
var _shot_imgs: Array = []
var _shot_clock := 0.0
var _audit := true


func _shots(delta: float) -> void:
	if _shot_prefix == "" or _shot_n >= _shot_count or DisplayServer.get_name() == "headless":
		return
	_shot_clock += delta
	if _shot_in_burst == 0:
		_shot_t -= delta
		if _shot_t > 0.0:
			return
		_shot_t += _shot_step
	var img := get_viewport().get_texture().get_image()
	if _shot_scale < 1.0:
		img.resize(int(img.get_width() * _shot_scale), int(img.get_height() * _shot_scale), Image.INTERPOLATE_BILINEAR)
	var cam := get_viewport().get_camera_3d()
	var info := "cam=%s scale=%.2f lights=%s" % [cam.global_position.snapped(Vector3.ONE * 0.01) if cam else Vector3.ZERO, get_viewport().scaling_3d_scale, str(get_parent().get("lights"))]
	_shot_imgs.append(["%s_%03d_%d.png" % [_shot_prefix, _shot_n, _shot_in_burst], img, _shot_clock, Engine.get_frames_drawn(), info])
	_shot_in_burst += 1
	if _shot_in_burst >= _shot_burst:
		_shot_in_burst = 0
		_shot_n += 1
		if _shot_n >= _shot_count:
			for r: Array in _shot_imgs:
				(r[1] as Image).save_png(r[0])
				print("pop-shot %s t=%.3f frame=%d %s" % [r[0].get_file(), r[2], r[3], r[4]])
			_shot_imgs.clear()


## Readable group key: parent/name without the auto-numbering.
func _key(g: Node) -> String:
	var n := String(g.name).get_slice("@", 0).rstrip("0123456789_")
	if n == "":
		n = g.get_class()
	var par := g.get_parent()
	var pn := ""
	while par and pn == "":
		pn = String(par.name).get_slice("@", 0).rstrip("0123456789_")
		par = par.get_parent()
	if n == "MeshInstance3D" or n == "MultiMeshInstance3D":
		# Unnamed: say which mesh and range, to grep for the builder.
		var m: Mesh = (g as MultiMeshInstance3D).multimesh.mesh if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh else (g.get("mesh") as Mesh)
		var mn := ""
		if m:
			mn = m.resource_name if m.resource_name != "" else m.resource_path.get_file()
			if mn == "" and m.get_surface_count() > 0:
				var mat: Material = g.material_override if g.material_override else m.surface_get_material(0)
				if mat:
					mn = "mat:" + (mat.resource_name if mat.resource_name != "" else (mat.shader.resource_path.get_file() if mat is ShaderMaterial and mat.shader else mat.get_class()))
		n += "[%s r%d]" % [mn, int(g.visibility_range_end)]
	return pn + "/" + n


## Side area of one instance mesh (m^2) and how many instances.
func _area_count(g: GeometryInstance3D) -> Vector2:
	var b := AABB()
	var n := 1
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return Vector2.ZERO
		b = mm.mesh.get_aabb()
		n = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
		b = (g as MeshInstance3D).mesh.get_aabb()
	else:
		b = g.get_aabb()
	var s := b.size * g.global_basis.get_scale()
	# Capped: a merged mesh spread over the whole track is not one big wall.
	return Vector2(minf(maxf(s.x, s.z) * s.y + s.x * s.z * 0.3, 300.0), n)


## Drawn now, with Godot's hysteresis: a drawn instance hides beyond end +
## margin (below begin - margin); a hidden one shows within end - margin
## (beyond begin + margin).
func _drawn(g: GeometryInstance3D, p: Vector3, was: bool) -> bool:
	if not g.is_visible_in_tree():
		return false
	if g.visibility_range_end <= 0.0 and g.visibility_range_begin <= 0.0:
		return true
	var d := p.distance_to(_box(g).get_center())
	var s := 1.0 if was else -1.0
	if g.visibility_range_end > 0.0 and d > g.visibility_range_end + s * g.visibility_range_end_margin:
		return false
	return not (g.visibility_range_begin > 0.0 and d < g.visibility_range_begin - s * g.visibility_range_begin_margin)


func _soft(g: GeometryInstance3D) -> bool:
	# Shader-side distance fades (grass dissolve, leaves shrink) end before the range.
	var mat := g.material_override
	if mat is ShaderMaterial and (mat as ShaderMaterial).shader and (mat as ShaderMaterial).shader.resource_path.get_file() in ["grass.gdshader", "road_leaves.gdshader"]:
		return true
	return g.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED and g.visibility_range_end_margin >= 8.0


func _inventory() -> void:
	var rows := {}
	for g: GeometryInstance3D in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end <= 0.0 or g.visibility_range_begin > 0.0:
			continue
		var box := _box(g)
		var half := Vector2(box.size.x, box.size.z).length() * 0.5
		var eff := g.visibility_range_end - half # where its near edge switches on
		if eff >= 300.0:
			continue
		var ac := _area_count(g)
		var k := _key(g)
		var r: Array = rows.get(k, [0, 0.0, INF, 0, 0.0])
		r[0] += 1
		r[1] += ac.x * ac.y
		r[2] = minf(r[2], eff)
		r[3] += int(_soft(g))
		r[4] = maxf(r[4], g.visibility_range_end)
		rows[k] = r
	var keys := rows.keys()
	keys.sort_custom(func(a, b): return rows[a][1] > rows[b][1])
	print("pop-audit INVENTORY short ranges (%d groups): key | nodes | area*count m2 | near-edge on at m | range_end | soft" % keys.size())
	for k in keys.slice(0, 60):
		var r: Array = rows[k]
		print("  inv %-48s %4d %9.0f %6.0f %6.0f  %d/%d" % [k, r[0], r[1], r[2], r[4], r[3], r[0]])


func _appear_tick(p: Vector3, f: Vector3) -> void:
	var ons: Array = []
	var offs: Array = []
	for g: GeometryInstance3D in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if String(g.name).begins_with("Forest") or g is GPUParticles3D or g is CPUParticles3D:
			continue
		var par := g.get_parent()
		if par and par.has_method("stats") and par.get("_far") is Dictionary:
			continue # crowd LOD buffers: checked by crowd_missing
		# Nodes added after the first tick count as switched on (spawned).
		var was: bool = _on.get(g, _drawn(g, p, true) if _first else false)
		var now := _drawn(g, p, was)
		_on[g] = now
		if now == was:
			continue
		if now:
			ons.append(g)
		else:
			offs.append(_box(g))
	_first = false
	for g: GeometryInstance3D in ons:
		var box := _box(g)
		var q := p.clamp(box.position, box.end)
		var d := maxf(p.distance_to(q), 1.0)
		var to := box.get_center() - p
		if d > APPEAR_D or to.dot(f) < to.length() * 0.5:
			continue
		var swap := false
		for o: AABB in offs:
			if o.grow(5.0).intersects(box):
				swap = true
				break
		if swap:
			continue
		var ac := _area_count(g)
		if g is MultiMeshInstance3D:
			ac.y = maxf(ac.y * minf(1.0, 4000.0 / maxf(box.size.x * box.size.z, 1.0)), 1.0) # only part of a big cell is ahead
		var score := ac.x * ac.y / (d * d) * 1000.0
		var k := _key(g) + (" (soft)" if _soft(g) else "")
		var r: Array = _appear.get(k, [0, 0.0, INF, 0.0, 0])
		r[4] += int(d < 250.0)
		r[0] += 1
		r[1] = maxf(r[1], score)
		r[2] = minf(r[2], d)
		r[3] += score
		_appear[k] = r


func _appear_report() -> void:
	var keys := _appear.keys()
	keys.sort_custom(func(a, b): return _appear[a][3] > _appear[b][3])
	var tot := 0.0
	var n := 0
	var n250 := 0
	for k in keys:
		if not String(k).ends_with("(soft)"):
			tot += _appear[k][3]
			n += _appear[k][0]
			n250 += _appear[k][4]
	print("pop-audit APPEAR within %d m ahead: %d hard pops (%d within 250 m), score %.0f. key | pops | <250m | max score | closest m | total score" % [APPEAR_D, n, n250, tot])
	for k in keys.slice(0, 50):
		var r: Array = _appear[k]
		print("  pop %-56s %5d %5d %8.1f %6.0f %9.1f" % [k, r[0], r[4], r[1], r[2], r[3]])


func _process(delta: float) -> void:
	_t -= delta
	_print_t += delta
	_app_t -= delta
	_shots(delta)
	if not _audit:
		return
	if _app_t <= 0.0 and get_viewport().get_camera_3d():
		_app_t = 0.1
		var c3 := get_viewport().get_camera_3d()
		if not _inv_done and Time.get_ticks_msec() > 4000:
			_inv_done = true
			_inventory()
		_appear_tick(c3.global_position, -c3.global_basis.z)
	if _t > 0.0:
		return
	_t = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_samples += 1
	var p := cam.global_position
	var f := -cam.global_basis.z
	for g: GeometryInstance3D in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
		if not g.is_visible_in_tree():
			continue
		if String(g.name).begins_with("ForestNear"):
			_check_forest(g as MultiMeshInstance3D, p)
			continue
		if String(g.name).begins_with("Forest"):
			continue
		if g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0:
			_check_range(g, p)
	for c in get_tree().root.find_children("*", "Node3D", true, false):
		if c.has_method("stats") and c.get("_far") is Dictionary:
			_check_crowd(c, p, f)
	if _print_t >= 1.0:
		_print_t = 0.0
		var parts := []
		for k: String in _sec:
			parts.append("%s=%d (closest %.0f m)" % [k, _sec[k], _worst.get(k, 0.0)])
		if not parts.is_empty():
			print("pop-audit t=%.0f cam=(%.0f,%.0f): %s" % [Time.get_ticks_msec() / 1000.0, p.x, p.z, ", ".join(parts)])
		_sec.clear()
		_worst.clear()


func _note(kind: String, n: int, dist: float) -> void:
	if n <= 0:
		return
	_sec[kind] = _sec.get(kind, 0) + n
	_tot[kind] = _tot.get(kind, 0) + n
	_worst[kind] = minf(_worst.get(kind, INF), dist)


var _mm_box := {}


## World AABB the renderer uses. MultiMesh AABBs are computed here from the
## instances: the headless dummy renderer reports them empty.
func _box(g: GeometryInstance3D) -> AABB:
	if g is MultiMeshInstance3D:
		if g.custom_aabb.has_volume():
			return g.global_transform * g.custom_aabb
		if not _mm_box.has(g):
			var mm := (g as MultiMeshInstance3D).multimesh
			var mb := mm.mesh.get_aabb() if mm.mesh else AABB()
			var box := AABB()
			for i in mm.instance_count:
				var b := mm.get_instance_transform(i) * mb
				box = b if i == 0 else box.merge(b)
			_mm_box[g] = box
		return g.global_transform * (_mm_box[g] as AABB)
	return g.global_transform * g.get_aabb()


func _hidden(g: GeometryInstance3D, p: Vector3) -> bool:
	var d := p.distance_to(_box(g).get_center())
	if g.visibility_range_end > 0.0 and d > g.visibility_range_end + g.visibility_range_end_margin:
		return true
	return g.visibility_range_begin > 0.0 and d < g.visibility_range_begin - g.visibility_range_begin_margin


func _check_range(g: GeometryInstance3D, p: Vector3) -> void:
	if not _hidden(g, p):
		return
	var kind := _kind(g)
	# A pop the player can notice: within 75 % of the range end and 200 m.
	var limit := minf(g.visibility_range_end * 0.75, 200.0)
	if g.visibility_range_begin > 0.0:
		# A far LOD: fine as long as its near LOD takes over (checked via forest_far).
		if kind == "forest":
			return
		limit = INF
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		var n := 0
		var closest := INF
		for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
			var d := p.distance_to(g.global_transform * mm.get_instance_transform(i).origin)
			if d < limit:
				n += 1
				closest = minf(closest, d)
		if kind == "forest":
			# Near trees hidden: they are drawn by the far mesh instead.
			var n2 := 0
			for i in mm.instance_count:
				var d := p.distance_to(g.global_transform * mm.get_instance_transform(i).origin)
				if d < FOREST_FAR_OK:
					n2 += 1
					closest = minf(closest, d)
			_note("forest_far", n2, closest)
			return
		_note("wrong_hidden:" + kind, n, closest)
	else:
		var box := _box(g)
		var q := p.clamp(box.position, box.end)
		var d := p.distance_to(q)
		if d < limit:
			_note("wrong_hidden:" + kind, 1, d)


## Forest HLOD chain (world_builder.gd): near -> cell far mesh -> super far
## mesh. Near trees are drawn only while both ancestors are hidden by their
## range begin; count near-mesh trees within FOREST_FAR_OK m that are not.
func _check_forest(g: MultiMeshInstance3D, p: Vector3) -> void:
	var far := g.get_node_or_null(g.visibility_parent) as GeometryInstance3D
	if far == null:
		return
	var sup := far.get_node_or_null(far.visibility_parent) as GeometryInstance3D
	var near_drawn := p.distance_to(_box(far).get_center()) < far.visibility_range_begin
	if sup != null and p.distance_to(_box(sup).get_center()) >= sup.visibility_range_begin:
		near_drawn = false
	if near_drawn:
		return
	var mm := g.multimesh
	var n := 0
	var closest := INF
	for i in mm.instance_count:
		var d := p.distance_to(g.global_transform * mm.get_instance_transform(i).origin)
		if d < FOREST_FAR_OK:
			n += 1
			closest = minf(closest, d)
	_note("forest_far", n, closest)


func _kind(g: Node) -> String:
	var n := String(g.name)
	if g.visibility_range_begin > 0.0 or (g is MultiMeshInstance3D and g.visibility_range_end_margin == 40.0 and g.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF and not n.begins_with("Theme")):
		return "forest"
	if n.begins_with("ThemeMM_"):
		return n
	if n.begins_with("Theme_"):
		return "theme_mesh"
	if g.get_parent() and String(g.get_parent().name).begins_with("SetDressing"):
		return "set_dressing"
	return n.get_slice("@", 0) if not n.begins_with("@") else g.get_class()


var _dup_done := {}
var _crowd_state := {}


func _check_crowd(c: Node3D, p: Vector3, f: Vector3) -> void:
	# Buffer rewrites (LOD set changes) and whether they would be drawn
	# physics-interpolated (blended with the previous buffer for a frame).
	var interp := false
	for mmi in c.get_children():
		if mmi is MultiMeshInstance3D and mmi.is_physics_interpolated_and_enabled():
			interp = true
	var states := ""
	for sets: Dictionary in [c.get("_near"), c.get("_mid"), c.get("_far")]:
		for key: String in sets:
			states += String(sets[key].state) + "|"
	if _crowd_state.get(c, "") != states:
		if _crowd_state.has(c):
			_note("crowd_rewrite:" + String(c.name), 1, 0.0)
			if interp:
				_note("crowd_rewrite_interpolated:" + String(c.name), 1, 0.0)
		_crowd_state[c] = states
	if not _dup_done.has(c):
		_dup_done[c] = true
		print("pop-audit crowd %s: physics interpolated = %s" % [c.name, interp])
		var all := {}
		var dup := 0
		for key: String in c.get("_far"):
			for ch: Array in c.get("_far")[key].chunks:
				var data: PackedFloat32Array = ch[1]
				for k in range(0, data.size(), 20):
					var o := Vector3(data[k + 3], data[k + 7], data[k + 11])
					if all.has(o):
						dup += 1
					all[o] = true
		print("pop-audit crowd %s: %d figures, %d share an origin with another" % [c.get_path(), c.get("total"), dup])
	# What each LOD set draws, from its chunk list and keep mask (the
	# RenderingServer copy of the buffer is not readable headless).
	var seen := {}
	var dbl := 0
	var dbl_d := INF
	for sets: Dictionary in [c.get("_near"), c.get("_mid"), c.get("_far")]:
		for key: String in sets:
			var st: Dictionary = sets[key]
			var mask: PackedByteArray = String(st.state).hex_decode()
			for i in mini(mask.size(), st.chunks.size()):
				if mask[i] != 1:
					continue
				var data: PackedFloat32Array = st.chunks[i][1]
				for k in range(0, data.size(), 20):
					var o := Vector3(data[k + 3], data[k + 7], data[k + 11])
					if seen.has(o):
						dbl += 1
						dbl_d = minf(dbl_d, p.distance_to(c.global_transform * o))
					seen[o] = true
	_note("crowd_double", dbl, dbl_d)
	# Every figure: from the far sets' chunk data (all figures, once each).
	var miss := 0
	var miss_d := INF
	var far: Dictionary = c.get("_far")
	for key: String in far:
		for ch: Array in far[key].chunks:
			var data: PackedFloat32Array = ch[1]
			for k in range(0, data.size(), 20):
				var o := Vector3(data[k + 3], data[k + 7], data[k + 11])
				if seen.has(o):
					continue
				var w := c.global_transform * o
				var to := w - p
				var d := to.length()
				# In front (within a generous 70 deg of the view axis) and not too far.
				if d < 150.0 and to.dot(f) > d * 0.34:
					miss += 1
					miss_d = minf(miss_d, d)
	_note("crowd_missing", miss, miss_d)
	_legacy(c, p, f)


## The pre-fix crowd rule (each LOD grouping decided by its own chunk
## centroids, no hysteresis), evaluated on the same camera for comparison.
func _legacy(c: Node3D, p: Vector3, f: Vector3) -> void:
	var nd: float = c.get("_near_d")
	var md: float = c.get("_mid_d")
	var seen := {}
	var dbl := 0
	var dbl_d := INF
	var pass_i := 0
	for sets: Dictionary in [c.get("_near"), c.get("_mid"), c.get("_far")]:
		for key: String in sets:
			for ch: Array in sets[key].chunks:
				var to: Vector3 = ch[0] - p
				var d := to.length()
				var on := d < nd if pass_i == 0 else (d >= nd and d < md if pass_i == 1 else d >= md and to.dot(f) > -0.35 * d)
				if not on:
					continue
				var data: PackedFloat32Array = ch[1]
				for k in range(0, data.size(), 20):
					var o := Vector3(data[k + 3], data[k + 7], data[k + 11])
					if seen.has(o):
						dbl += 1
						dbl_d = minf(dbl_d, p.distance_to(c.global_transform * o))
					seen[o] = true
		pass_i += 1
	_note("legacy_crowd_double", dbl, dbl_d)
	var miss := 0
	var miss_d := INF
	var far: Dictionary = c.get("_far")
	for key: String in far:
		for ch: Array in far[key].chunks:
			var data: PackedFloat32Array = ch[1]
			for k in range(0, data.size(), 20):
				var o := Vector3(data[k + 3], data[k + 7], data[k + 11])
				if seen.has(o):
					continue
				var to := c.global_transform * o - p
				var d := to.length()
				if d < 150.0 and to.dot(f) > d * 0.34:
					miss += 1
					miss_d = minf(miss_d, d)
	_note("legacy_crowd_missing", miss, miss_d)


func _exit_tree() -> void:
	if not _audit:
		return
	_appear_report()
	var parts := []
	for k: String in _tot:
		parts.append("%s=%d" % [k, _tot[k]])
	print("pop-audit TOTAL over %d samples: %s" % [_samples, ", ".join(parts) if not parts.is_empty() else "clean"])
