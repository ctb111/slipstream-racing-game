class_name PeopleKit
extends RefCounted
## Realistic crowd figures built from baked, posed meshes of rigged models
## (assets/people, see CREDITS_people.txt; baked by assets/people/bake/bake_people.gd).
##
## Every figure is an instance in a MultiMesh drawn with shaders/people.gdshader:
##   instance colour  = top / jacket (overalls for crew, flag colour for marshals), sRGB
##   INSTANCE_CUSTOM  = (phase / identity hash, excitement or flag wave, marshal tint 0 white / 1 orange, -)
## Trousers, skin tone, hair and shoes are picked in the shader from the
## identity hash. A Crowd node sorts its figures into ~10 m chunks and, as the
## camera moves, draws each chunk with the full mesh (~4k tris, < NEAR m), the
## mid mesh (~1.1k, < MID m) or a generic far mesh (~320), skips chunks well
## behind the camera, and casts all shadows within 60 m from one decimated
## shadow-only MultiMesh.
##
## Usage: parent.add_child(PeopleKit.crowd("Spectators", PeopleKit.Role.SPECTATOR, xfs, cols, custom))
## with transforms at the feet facing -Z (Role.SEATED: at the seat surface, the
## hips at the origin, thighs towards -Z).

enum Pose { STAND, CHEER, CLAP, SEATED, FLAG, CAMERA }
enum Role { SPECTATOR, CREW, MARSHAL, SEATED, PHOTOGRAPHER }

## Baked models and the poses each has (see assets/people/bake/bake_people.gd).
const MODELS := {
	"man_jacket": [Pose.STAND, Pose.CHEER, Pose.CLAP, Pose.CAMERA],
	"man_shirt": [Pose.STAND, Pose.CHEER, Pose.SEATED],
	"man_overalls": [Pose.STAND, Pose.FLAG],
	"woman_casual": [Pose.STAND, Pose.CHEER, Pose.CLAP, Pose.SEATED],
	"woman_skirt": [Pose.STAND, Pose.CLAP],
}
const POSE_NAMES: Array[String] = ["stand", "cheer", "clap", "seated", "flag", "camera"]
## Shader `motion` per pose.
const POSE_MOTION: Array[int] = [0, 1, 2, 4, 3, 5]
## Distances (m) up to which chunks use the full / the mid-detail mesh.
const NEAR := 12.0
const MID := 36.0
const CHUNK := 10.0

static var _meshes := {}
static var _materials := {}
static var _wind := 0.35


## `pose` if `model` has it, else the closest one it has.
static func pose_for(model: String, pose: Pose) -> Pose:
	var have: Array = MODELS[model]
	if have.has(pose):
		return pose
	for alt: Pose in [Pose.CLAP, Pose.CHEER, Pose.STAND]:
		if have.has(alt) and pose != Pose.SEATED:
			return alt
	return have[0]


## The baked mesh for `model` in `pose` (or its fallback); `lod` "hi", "mid" or "lo".
static func mesh(model: String, pose: Pose, lod := "hi") -> ArrayMesh:
	var key := "%s_%s_%s" % [model, POSE_NAMES[pose_for(model, pose)], lod]
	if not _meshes.has(key):
		_meshes[key] = load("res://assets/people/meshes/%s.res" % key)
	return _meshes[key]


## Shared material for a pose mesh and role (crew/marshal recolour differently).
static func material(model: String, pose: Pose, role: Role) -> ShaderMaterial:
	pose = pose_for(model, pose)
	var shader_role := 1 if role == Role.CREW else (2 if role == Role.MARSHAL else 0)
	var key := "%s_%d_%d" % [model, pose, shader_role]
	if not _materials.has(key):
		var m := mesh(model, pose)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/people.gdshader")
		mat.set_shader_parameter("atlas", load("res://assets/people/people_atlas.png"))
		mat.set_shader_parameter("motion", POSE_MOTION[pose])
		mat.set_shader_parameter("role", shader_role)
		mat.set_shader_parameter("pivot", m.get_meta("pivot", Vector3(0.2, 1.45, 0)))
		mat.set_shader_parameter("wind", _wind)
		_materials[key] = mat
	return _materials[key]


## Weather wind 0 calm .. 1 storm for the marshals' hand flags (they also fly
## from being waved). Applies to all figure materials, current and future.
static func set_wind(w: float) -> void:
	_wind = w
	for key: String in _materials:
		(_materials[key] as ShaderMaterial).set_shader_parameter("wind", w)


## Picks [model, pose] for one figure of `role`. `custom` is its INSTANCE_CUSTOM.
static func pick(role: Role, custom: Color) -> Array:
	var h := fposmod(sin(custom.r * 12.9898 + 4.1) * 43758.5453, 1.0)
	var h2 := fposmod(sin(custom.r * 78.233 + 1.7) * 24634.6345, 1.0)
	match role:
		Role.CREW:
			return ["man_shirt" if h < 0.12 else "man_overalls", Pose.STAND]
		Role.MARSHAL:
			return ["man_overalls", Pose.FLAG]
		Role.PHOTOGRAPHER:
			return ["man_jacket", Pose.CAMERA]
		Role.SEATED:
			return ["woman_casual" if h < 0.35 else "man_shirt", Pose.SEATED]
	var model := "man_jacket" if h < 0.36 else ("man_shirt" if h < 0.62 else ("woman_casual" if h < 0.83 else "woman_skirt"))
	var ex := custom.g
	var pose := Pose.STAND
	if ex > 0.84:
		pose = Pose.CHEER
	elif ex > 0.01 and h2 < 0.45:
		pose = Pose.CLAP
	if model == "man_shirt" or model == "woman_skirt":
		pose = Pose.STAND # keeps the number of pose meshes (draw calls) down
	return [model, pose_for(model, pose)]


## Builds a crowd from parallel arrays (transform at the feet, facing -Z;
## seated figures: at the seat surface). Returns the node to add to the scene.
static func crowd(node_name: String, role: Role, xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color], cast_shadows := true) -> Crowd:
	var c := Crowd.new()
	c.name = node_name
	if OS.get_cmdline_user_args().has("--no-people"):
		return c # debug: measure the scene without figures
	c.setup(role, xfs, cols, custom, cast_shadows)
	return c


## One figure for set dressing (a 1-instance crowd, so it shares the shader).
static func figure(role: Role, xf: Transform3D, col: Color, custom := Color(0.5, 0.0, 0.0, 0.0)) -> Crowd:
	var xfs: Array[Transform3D] = [xf]
	var cols: Array[Color] = [col]
	var cus: Array[Color] = [custom]
	return crowd("Figure", role, xfs, cols, cus)


## Triangles one figure of each mesh costs (near, far) — for budgets/stats.
static func tris(model: String, pose: Pose, lod := "hi") -> int:
	return mesh(model, pose, lod).surface_get_array_index_len(0) / 3


## The decimated mesh used for `model`/`pose` beyond NEAR: far away only the
## silhouette matters, so the far tier needs just a few meshes (draw calls).
static func far_variant(model: String, pose: Pose) -> Array:
	if model == "man_overalls" or pose == Pose.SEATED or pose == Pose.FLAG:
		return [model, pose]
	if model.begins_with("woman"):
		return ["woman_casual", Pose.CHEER if pose == Pose.CHEER else Pose.STAND]
	return ["man_jacket", Pose.CHEER if pose == Pose.CHEER else Pose.STAND]


class Crowd extends Node3D:
	## Two independent groupings of the same figures into ~10 m chunks:
	## by exact model/pose (drawn by _near with the full mesh within NEAR m and
	## by _mid with the ~1k-triangle mesh within MID m) and by a few generic far
	## variants (_far, decimated, beyond MID unless well behind the camera).
	## Each set = {mmi, chunks: Array, state} with chunk =
	## [centre, data: PackedFloat32Array, count, bounds: AABB, cell: Vector3i]. _shadow casts every figure within SHADOW m with one
	## decimated mesh (shadows only); the visible tiers cast none.
	## The tier is decided once per 10 m cell (shared centre of all its figures,
	## with hysteresis), so the groupings never disagree: every figure is drawn
	## by exactly one tier, never by none or two.
	const SHADOW := 30.0
	const SHADOW_OLD := 60.0 ## --people-old
	const BUCKET := 80.0 ## metres: cells grouped for the far test
	static var _OLD := OS.get_cmdline_user_args().has("--people-old")
	var _buckets: Array = [] ## [centre, radius, cells: Array[Vector3i], whole-bucket tier (-1 = per cell)]
	var _cell_sets := {} ## cell -> sets (Dictionaries) holding a chunk of it
	var _shadow_dirty := true
	const NEAR_CAP := 24 ## figures per Crowd drawn with the full mesh (closest cells first)
	var _cell_n := {} ## cell -> figure count
	## Metres seated figures float above the seat surface they are placed on.
	const SEAT_LIFT := 0.025
	## Metres a cell must cross a tier boundary by before it switches.
	const HYST := 2.5
	## cell -> [centre, radius, tier (-1 unset, 0 near, 1 mid, 2 far, 3 skipped behind), casts shadow]
	var _cells := {}
	var _cam_id := 0
	var _near := {}
	var _mid := {}
	var _far := {}
	var _shadow: MultiMeshInstance3D
	var _shadow_state := ""
	var _last_cam := Vector3(INF, INF, INF)
	var _last_fwd := Vector3.ZERO
	var _timer := 0.0
	var _near_d := PeopleKit.NEAR
	var _mid_d := PeopleKit.MID
	var total := 0

	func setup(role: PeopleKit.Role, xfs: Array[Transform3D], cols: Array[Color], custom: Array[Color], cast_shadows: bool) -> void:
		if role == PeopleKit.Role.SEATED:
			# Packed terraces: hundreds of figures close together, mostly half hidden.
			_near_d = 8.0
			_mid_d = 18.0
		if Game.quality <= 1:
			# Low / Medium: the lighter meshes a little sooner (a few px of difference).
			_near_d *= 0.75
			_mid_d *= 0.8
		var near_g := {}
		var far_g := {}
		for k in xfs.size():
			var mp: Array = PeopleKit.pick(role, custom[k])
			var fv: Array = PeopleKit.far_variant(mp[0], mp[1])
			var b := xfs[k].basis
			var o := xfs[k].origin
			if role == PeopleKit.Role.SEATED:
				# The thigh undersides lie in the seat plane (origin): lift them
				# off it, or they z-fight with the seat and shimmer as the camera
				# shakes (worst on the grid, next to the grandstand).
				o += b.y.normalized() * SEAT_LIFT
			var c := cols[k]
			var u := custom[k]
			var row := PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y,
				b.x.z, b.y.z, b.z.z, o.z, c.r, c.g, c.b, c.a, u.r, u.g, u.b, u.a])
			_add(near_g, mp, o, row)
			_add(far_g, fv, o, row)
			var cell := Vector3i(floori(o.x / PeopleKit.CHUNK), 0, floori(o.z / PeopleKit.CHUNK))
			if not _cells.has(cell):
				_cells[cell] = [Vector3.ZERO, AABB(o, Vector3.ZERO), -1, false, 0]
			var cc: Array = _cells[cell]
			cc[0] += o
			cc[1] = (cc[1] as AABB).expand(o)
			cc[4] += 1
		for cell: Vector3i in _cells:
			var cc: Array = _cells[cell]
			_cell_n[cell] = cc[4]
			cc[0] /= float(cc[4])
			var bb: AABB = cc[1]
			cc[1] = Vector2(bb.size.x, bb.size.z).length() * 0.5 + 1.0 # radius around the centre
			cc.resize(4)
		total = xfs.size()
		# No physics interpolation (the project turns it on): with it, every
		# MultiMesh buffer rewrite below would be drawn blended slot by slot
		# with the previous buffer, i.e. other figures' transforms, until the
		# next physics tick: figures jump and flicker at each LOD refresh.
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# Late in the frame: after the race has moved or switched cameras, so a
		# cut never shows one frame of the old camera's LOD choice.
		process_priority = 900
		_near = _make_sets(near_g, "hi", role)
		_mid = _make_sets(near_g, "mid", role)
		_far = _make_sets(far_g, "lo", role)
		if cast_shadows and total > 0:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = PeopleKit.mesh("man_jacket", PeopleKit.Pose.STAND, "lo")
			_shadow = MultiMeshInstance3D.new()
			_shadow.name = "shadows"
			_shadow.multimesh = mm
			_shadow.material_override = PeopleKit.material("man_jacket", PeopleKit.Pose.STAND, role)
			_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_shadow.visible = false
			add_child(_shadow)
		# Until a camera shows up: everything in the far tier.
		_timer = randf() * 0.1 # crowds refresh on different frames
		if _OLD:
			_refresh_old(Vector3(INF, 0, INF), Vector3.ZERO)
		else:
			_refresh(Vector3(INF, 0, INF), Vector3.ZERO)

	func _add(groups: Dictionary, mp: Array, o: Vector3, row: PackedFloat32Array) -> void:
		var key := "%s|%d" % [mp[0], mp[1]]
		if not groups.has(key):
			groups[key] = {"model": mp[0], "pose": mp[1], "cells": {}}
		var cell := Vector3i(floori(o.x / PeopleKit.CHUNK), 0, floori(o.z / PeopleKit.CHUNK))
		var cells: Dictionary = groups[key].cells
		if not cells.has(cell):
			cells[cell] = [Vector3.ZERO, PackedFloat32Array(), 0, AABB(o, Vector3.ZERO), cell]
		var ch: Array = cells[cell]
		# Packed arrays are values: append to a local and store it back.
		var data: PackedFloat32Array = ch[1]
		data.append_array(row)
		ch[1] = data
		ch[0] += o
		ch[2] += 1
		ch[3] = (ch[3] as AABB).expand(o)

	func _make_sets(groups: Dictionary, lod: String, role: PeopleKit.Role) -> Dictionary:
		var sets := {}
		for key: String in groups:
			var g: Dictionary = groups[key]
			var chunks: Array = []
			for cell: Vector3i in g.cells:
				var ch: Array = g.cells[cell]
				if not g.has("done"):
					ch[0] /= float(ch[2])
					# Room for the figure (and a raised flag) around the feet.
					var box: AABB = (ch[3] as AABB).grow(1.5)
					box.size.y += 2.5
					ch[3] = box
				chunks.append(ch)
			g["done"] = true
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = PeopleKit.mesh(g.model, g.pose, lod)
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "%s_%s_%s" % [g.model, PeopleKit.POSE_NAMES[g.pose], lod]
			mmi.multimesh = mm
			mmi.material_override = PeopleKit.material(g.model, g.pose, role)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visible = false
			add_child(mmi)
			sets[key] = {"mmi": mmi, "chunks": chunks, "state": ""}
		return sets

	## --debug-people-time: CPU cost of all Crowds' _process, printed every 5 s.
	static var _prof_on := OS.get_cmdline_user_args().has("--debug-people-time")
	static var _prof_us := 0
	static var _prof_max := 0
	static var _prof_frames := 0
	static var _prof_last_frame := -1
	static var _prof_t0 := 0
	static var _prof_crowds := 0
	static var _prof_refresh := 0

	func _process(delta: float) -> void:
		if not _prof_on:
			_process_inner(delta)
			return
		var t0 := Time.get_ticks_usec()
		_process_inner(delta)
		var us := Time.get_ticks_usec() - t0
		var f := Engine.get_process_frames()
		if f != _prof_last_frame:
			_prof_last_frame = f
			_prof_frames += 1
			_prof_crowds = 0
		_prof_crowds += 1
		_prof_us += us
		_prof_max = maxi(_prof_max, us)
		var now := Time.get_ticks_msec()
		if _prof_t0 == 0:
			_prof_t0 = now
		elif now - _prof_t0 > 5000:
			print("people-time: %.3f ms/frame over %d crowds, max single %.2f ms, %d refreshes/s" % [
				_prof_us / 1000.0 / maxi(_prof_frames, 1), _prof_crowds, _prof_max / 1000.0, _prof_refresh * 1000 / (now - _prof_t0)])
			_prof_us = 0
			_prof_max = 0
			_prof_frames = 0
			_prof_refresh = 0
			_prof_t0 = now

	func _process_inner(delta: float) -> void:
		if total == 0:
			return
		_timer -= delta
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var p := cam.global_position
		var f := -cam.global_basis.z
		# Camera cuts (TV director, camera change, respawn) and fast pans refresh
		# at once, so nothing in the new view waits for the next tick.
		var cut := cam.get_instance_id() != _cam_id or p.distance_to(_last_cam) > 12.0 or f.dot(_last_fwd) < 0.9
		if not cut:
			if _timer > 0.0:
				return
			if p.distance_to(_last_cam) < (1.0 if _OLD else 3.0) and f.dot(_last_fwd) > 0.985:
				return
		_timer = 0.1
		_cam_id = cam.get_instance_id()
		_prof_refresh += 1
		if _OLD:
			_refresh_old(p, f)
		else:
			_refresh(p, f)
		if OS.get_cmdline_user_args().has("--debug-people"):
			var st := stats()
			print("people %s: %d/%d drawn, %d tris incl. shadow proxies, %d visible multimeshes" % [name, st.x, total, st.y, st.z])

	## Tier for a cell at distance `d` with thresholds shifted by `h`.
	func _tier(d: float, h: float) -> int:
		return 0 if d < _near_d + h else (1 if d < _mid_d + h else 2)

	## Tiers per cell exactly as before, but only the work that can change:
	## cells are grouped into BUCKET-m buckets; a bucket wholly beyond the mid
	## and shadow ranges is decided as a whole (far, or skipped when the whole
	## bucket is behind the camera: a stricter test than per cell, so nothing
	## on screen can differ), and a cell whose tier or shadow flag changes marks
	## only the sets holding it for a rebuild.
	func _refresh(p: Vector3, f: Vector3) -> void:
		_last_cam = p
		_last_fwd = f
		var nowhere := p.x == INF
		if _buckets.is_empty():
			_make_buckets()
		var far_d := maxf(_mid_d, SHADOW) + HYST * 2.0 + 1.0
		for b: Array in _buckets:
			var to_b: Vector3 = b[0] - p
			var db := 1e9 if nowhere else to_b.length()
			var rb: float = b[1]
			if db - rb > far_d:
				var bt := 2
				if not nowhere and to_b.dot(f) + rb < -0.35 * (db + rb):
					bt = 3
				if b[3] == bt:
					continue # whole bucket unchanged
				b[3] = bt
				for cell: Vector3i in b[2]:
					var cc: Array = _cells[cell]
					var t := bt
					if t == 3 and not (to_b.dot(f) + rb < -0.35 * (db + rb)):
						t = 2
					if cc[2] != t or cc[3]:
						cc[2] = t
						cc[3] = false
						_dirty_cell(cell, true)
				continue
			b[3] = -1
			for cell: Vector3i in b[2]:
				var cc: Array = _cells[cell]
				var to: Vector3 = cc[0] - p
				var d := 1e9 if nowhere else to.length()
				var prev: int = mini(cc[2], 2)
				var t: int
				if prev < 0:
					t = _tier(d, 0.0)
				else:
					t = prev
					var farther := _tier(d, HYST)
					var closer := _tier(d, -HYST)
					if farther > prev:
						t = farther
					elif closer < prev:
						t = closer
				var r: float = cc[1]
				if t == 2 and not nowhere and to.dot(f) + r < -0.35 * d:
					t = 3
				var sh: bool = not nowhere and d < (SHADOW + HYST if cc[3] else SHADOW - HYST)
				if t != cc[2] or sh != cc[3]:
					cc[2] = t
					cc[3] = sh
					_dirty_cell(cell, true)
		# The full ~4k-triangle mesh only for the NEAR_CAP closest figures: at a
		# packed hairpin bank the rest use the ~1.1k mesh (no visible difference
		# at race speed, a large GPU saving).
		if not nowhere:
			var near_cells: Array = []
			for b: Array in _buckets:
				if b[3] != -1:
					continue
				for cell: Vector3i in b[2]:
					if _cells[cell][2] == 0:
						near_cells.append([((_cells[cell][0] as Vector3) - p).length_squared(), cell])
			if near_cells.size() > 1:
				near_cells.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
				var n := 0
				for nc: Array in near_cells:
					if n >= NEAR_CAP:
						_cells[nc[1]][2] = 1
						_dirty_cell(nc[1], false)
					n += int(_cell_n.get(nc[1], 1))
		for pass_i in 3:
			var sets: Dictionary = [_near, _mid, _far][pass_i]
			for key: String in sets:
				var s: Dictionary = sets[key]
				if not s.get("dirty", true):
					continue
				s.dirty = false
				var keep := PackedByteArray()
				keep.resize(s.chunks.size())
				var i := 0
				for ch: Array in s.chunks:
					keep[i] = 1 if _cells[ch[4]][2] == pass_i else 0
					i += 1
				var st := keep.hex_encode()
				if st != s.state:
					s.state = st
					_fill(s.mmi, s.chunks, keep)
		if _shadow != null and _shadow_dirty:
			_shadow_dirty = false
			var chunks: Array = []
			var keep := PackedByteArray()
			for key: String in _far:
				for ch: Array in _far[key].chunks:
					chunks.append(ch)
					keep.append(1 if _cells[ch[4]][3] else 0)
			var st := keep.hex_encode()
			if st != _shadow_state:
				_shadow_state = st
				_fill(_shadow, chunks, keep)

	func _dirty_cell(cell: Vector3i, shadow: bool) -> void:
		for s: Dictionary in _cell_sets.get(cell, []):
			s.dirty = true
		if shadow:
			_shadow_dirty = true

	func _make_buckets() -> void:
		var groups := {}
		for cell: Vector3i in _cells:
			var cc: Array = _cells[cell]
			var c: Vector3 = cc[0]
			var k := Vector2i(floori(c.x / BUCKET), floori(c.z / BUCKET))
			if not groups.has(k):
				groups[k] = []
			groups[k].append(cell)
		for k: Vector2i in groups:
			var cells: Array = groups[k]
			var ctr := Vector3.ZERO
			for cell: Vector3i in cells:
				ctr += _cells[cell][0]
			ctr /= float(cells.size())
			var rad := 0.0
			for cell: Vector3i in cells:
				rad = maxf(rad, (_cells[cell][0] as Vector3).distance_to(ctr) + float(_cells[cell][1]))
			_buckets.append([ctr, rad, cells, -1])
		for sets: Dictionary in [_near, _mid, _far]:
			for key: String in sets:
				var s: Dictionary = sets[key]
				s.dirty = true
				for ch: Array in s.chunks:
					var cell: Vector3i = ch[4]
					if not _cell_sets.has(cell):
						_cell_sets[cell] = []
					(_cell_sets[cell] as Array).append(s)

	## The previous refresh (every cell and set, every time), kept for A/B: --people-old.
	func _refresh_old(p: Vector3, f: Vector3) -> void:
		_last_cam = p
		_last_fwd = f
		var nowhere := p.x == INF
		for cell: Vector3i in _cells:
			var cc: Array = _cells[cell]
			var to: Vector3 = cc[0] - p
			var d := 1e9 if nowhere else to.length()
			var prev: int = mini(cc[2], 2)
			var t: int
			if prev < 0:
				t = _tier(d, 0.0)
			else:
				t = prev
				var farther := _tier(d, HYST) # moving out needs HYST past the line
				var closer := _tier(d, -HYST) # moving in likewise
				if farther > prev:
					t = farther
				elif closer < prev:
					t = closer
			# Far cells well behind the camera are skipped: the whole cell (its
			# radius) must be outside a ~110 degree cone around the view axis.
			var r: float = cc[1]
			if t == 2 and not nowhere and to.dot(f) + r < -0.35 * d:
				t = 3
			cc[2] = t
			cc[3] = not nowhere and d < (SHADOW_OLD + HYST if cc[3] else SHADOW_OLD - HYST)
		for pass_i in 3:
			var sets: Dictionary = [_near, _mid, _far][pass_i]
			for key: String in sets:
				var s: Dictionary = sets[key]
				var keep := PackedByteArray()
				keep.resize(s.chunks.size())
				var i := 0
				for ch: Array in s.chunks:
					keep[i] = 1 if _cells[ch[4]][2] == pass_i else 0
					i += 1
				var st := keep.hex_encode()
				if st != s.state:
					s.state = st
					_fill(s.mmi, s.chunks, keep)
		if _shadow != null:
			var chunks: Array = []
			var keep := PackedByteArray()
			for key: String in _far:
				for ch: Array in _far[key].chunks:
					chunks.append(ch)
					keep.append(1 if _cells[ch[4]][3] else 0)
			var st := keep.hex_encode()
			if st != _shadow_state:
				_shadow_state = st
				_fill(_shadow, chunks, keep)

	func _fill(mmi: MultiMeshInstance3D, chunks: Array, keep: PackedByteArray) -> void:
		var data := PackedFloat32Array()
		var n := 0
		var box := AABB()
		for i in chunks.size():
			if keep[i] == 1:
				var ch: Array = chunks[i]
				data.append_array(ch[1])
				box = ch[3] if n == 0 else box.merge(ch[3])
				n += ch[2]
		var mm := mmi.multimesh
		mmi.visible = n > 0
		mm.instance_count = n
		if n > 0:
			mm.buffer = data
			mmi.custom_aabb = box

	## Debug: (figures drawn, triangles submitted incl. shadow casters, visible multimeshes).
	func stats() -> Vector3i:
		var inst := 0
		var tri := 0
		var vis := 0
		for mmi: MultiMeshInstance3D in get_children():
			var mm := mmi.multimesh
			if not mmi.visible:
				continue
			vis += 1
			if mmi != _shadow:
				inst += mm.instance_count
			tri += mm.instance_count * mm.mesh.surface_get_array_index_len(0) / 3
		return Vector3i(inst, tri, vis)
