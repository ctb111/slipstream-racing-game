extends SceneTree
## Offline baker for the crowd figures. Run headless:
##   godot --headless --path . --script res://assets/people/bake/bake_people.gd
## Loads the rigged source models in assets/people/src (see CREDITS_people.txt),
## poses their skeletons (standing, cheering, clapping, seated, flag, camera),
## skins the vertices on the CPU into one static mesh per pose and LOD (the
## hi/mid/lo source GLBs are decimated in Blender by make_humans.py), packs
## every texture into one atlas and writes the meshes to assets/people/meshes. Per-vertex CUSTOM0 = (region, arm weight, arm side 0/1,
## region mean luminance) drives tinting and motion in shaders/people.gdshader.

const OUT := "res://assets/people/meshes/"
const ATLAS := "res://assets/people/people_atlas.png"
const ATLAS_SIZE := 2048

## Region ids (must match people.gdshader).
const R_KEEP := 0.0
const R_TOP := 1.0
const R_BOTTOM := 2.0
const R_SKIN := 3.0
const R_HAIR := 4.0
const R_SHOES := 5.0
const R_HAT := 6.0
const R_FLAG := 7.0
const R_PROP := 8.0

## Source humans (MakeHuman CC0 via MPFB, see make_humans.py) and their poses.
## "split": how the outfit texture divides into top/bottom tint regions.
const MODELS := {
	"man_jacket": {"poses": ["stand", "cheer", "clap", "camera"], "split": "blue_is_bottom"},
	"man_shirt": {"poses": ["stand", "cheer", "seated"], "split": "belt"},
	"man_overalls": {"poses": ["stand", "flag"], "split": "white_is_keep"},
	"woman_casual": {"poses": ["stand", "cheer", "clap", "seated"], "split": "belt"},
	"woman_skirt": {"poses": ["stand", "clap"], "split": "belt"},
}

var atlas := Image.create(ATLAS_SIZE, ATLAS_SIZE, false, Image.FORMAT_RGBA8)
var report: Array[String] = []


func _init() -> void:
	atlas.fill(Color(0.5, 0.5, 0.5, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := OS.get_cmdline_user_args()
	var m := 0
	for id: String in MODELS:
		if only.is_empty() or only.has(id):
			_bake_model(id, m)
		m += 1
	atlas.save_png(ProjectSettings.globalize_path(ATLAS))
	for line in report:
		print(line)
	quit()


## Atlas tiles of model `m` (0..4): skin and outfit 512 each in a 512x1024
## column (models 0-3 in the top half, 4 bottom-left), small parts in the
## bottom-right area.
func _tile(m: int, kind: String) -> Rect2i:
	var col := Vector2i((m % 4) * 512, (m / 4) * 1024)
	var small := Vector2i(512 + m * 256, 1024)
	match kind:
		"skin": return Rect2i(col, Vector2i(512, 512))
		"outfit": return Rect2i(col + Vector2i(0, 512), Vector2i(512, 512))
		"hair": return Rect2i(small, Vector2i(256, 256))
		"shoes": return Rect2i(small + Vector2i(0, 256), Vector2i(128, 128))
		"brows": return Rect2i(small + Vector2i(128, 256), Vector2i(128, 128))
	return Rect2i(small + Vector2i(0, 384), Vector2i(64, 64)) # eyes


## Which part of the figure a material is ("skin", "outfit", "hair", ...).
func _kind(mat_name: String) -> String:
	var part := mat_name.get_slice(".", 1)
	if part == "body":
		return "skin"
	if part.contains("suit"):
		return "outfit"
	if part.begins_with("shoes"):
		return "shoes"
	if part.begins_with("eyebrow"):
		return "brows"
	if part == "low-poly" or part == "high-poly":
		return "eyes"
	return "hair"


func _bake_model(id: String, m: int) -> void:
	for lod: String in ["hi", "mid", "lo"]:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file("res://assets/people/src/%s_%s.glb" % [id, lod], state)
		assert(err == OK)
		var root: Node3D = doc.generate_scene(state)
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var sk_xf := _to_root(sk, root)
		var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
		var tiles := {}
		for mi: MeshInstance3D in meshes:
			var mat: BaseMaterial3D = mi.mesh.surface_get_material(0)
			var kind := _kind(mat.resource_name)
			var tile := _tile(m, kind)
			tiles[mat.resource_name] = [tile, kind]
			if lod == "hi" and mat.albedo_texture != null:
				var img: Image = mat.albedo_texture.get_image()
				img.decompress()
				img.convert(Image.FORMAT_RGBA8)
				img.resize(tile.size.x, tile.size.y, Image.INTERPOLATE_LANCZOS)
				atlas.blit_rect(img, Rect2i(Vector2i.ZERO, tile.size), tile.position)
		sk.reset_bone_poses()
		var rest := _skin(sk, sk_xf, meshes, tiles, id, null)
		for pose: String in MODELS[id].poses:
			sk.reset_bone_poses()
			_pose(sk, sk_xf, pose)
			var baked := _skin(sk, sk_xf, meshes, tiles, id, rest)
			var extra := {}
			_finish(baked, sk, sk_xf, 1.0, pose, extra)
			if pose == "seated" and lod != "hi":
				_drop_below(baked, -0.15) # shins/feet vanish into the terrace step
			_write(baked, "%s_%s_%s" % [id, pose, lod], extra)
		root.free()


## Transform from skeleton space into the model root's space.
func _to_root(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Bone pose in skeleton space, computed from the local poses (a Skeleton3D
## outside the tree does not refresh its cached global poses).
func _gp(sk: Skeleton3D, b: int) -> Transform3D:
	var xf := Transform3D()
	while b >= 0:
		var local := Transform3D(Basis(sk.get_bone_pose_rotation(b)) * Basis.from_scale(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b))
		xf = local * xf
		b = sk.get_bone_parent(b)
	return xf


func _bone(sk: Skeleton3D, bone_name: String) -> int:
	for pre: String in ["", "mixamorig_", "mixamorig:"]:
		var b := sk.find_bone(pre + bone_name)
		if b >= 0:
			return b
	push_error("no bone " + bone_name)
	return -1


## Rotate `bone` so the direction towards `child` points along `dir` (model space).
func _aim(sk: Skeleton3D, sk_xf: Transform3D, bone_name: String, child_name: String, dir: Vector3) -> void:
	var b := _bone(sk, bone_name)
	var c := _bone(sk, child_name)
	var g := _gp(sk, b)
	var cur := (_gp(sk, c).origin - g.origin).normalized()
	var tgt := (sk_xf.basis.inverse() * dir).normalized()
	var q := Quaternion(cur, tgt)
	var new_basis := Basis(q) * g.basis
	var pg := _gp(sk, sk.get_bone_parent(b))
	var local := (pg.basis.inverse() * new_basis).orthonormalized()
	sk.set_bone_pose_rotation(b, local.get_rotation_quaternion())


func _arm(sk: Skeleton3D, sk_xf: Transform3D, side: String, upper: Vector3, fore: Vector3, hand := Vector3.ZERO) -> void:
	var s := 1.0 if side == "Left" else -1.0
	var mirror := Vector3(s, 1, 1)
	_aim(sk, sk_xf, side + "Arm", side + "ForeArm", upper * mirror)
	_aim(sk, sk_xf, side + "ForeArm", side + "Hand", fore * mirror)
	var h := fore if hand == Vector3.ZERO else hand
	_aim(sk, sk_xf, side + "Hand", side + "HandMiddle1", h * mirror)


## Pose presets. Directions are in model space (+Y up, +Z the way the figure
## faces, +X its left) and are mirrored for the right side.
func _pose(sk: Skeleton3D, sk_xf: Transform3D, pose: String) -> void:
	var stand_up := Vector3(0.14, -1.0, -0.02)
	var stand_fore := Vector3(0.06, -1.0, 0.16)
	match pose:
		"stand":
			_arm(sk, sk_xf, "Left", stand_up, stand_fore)
			_arm(sk, sk_xf, "Right", stand_up + Vector3(0, 0, 0.1), stand_fore + Vector3(0, 0, 0.12))
		"cheer":
			_arm(sk, sk_xf, "Left", Vector3(0.5, 0.86, 0.12), Vector3(0.18, 1.0, 0.12))
			_arm(sk, sk_xf, "Right", Vector3(0.55, 0.8, 0.18), Vector3(0.25, 1.0, 0.1))
		"clap":
			_arm(sk, sk_xf, "Left", Vector3(0.22, -0.8, 0.5), Vector3(-0.62, 0.42, 0.66), Vector3(-0.3, 0.9, 0.3))
			_arm(sk, sk_xf, "Right", Vector3(0.22, -0.8, 0.5), Vector3(-0.62, 0.42, 0.66), Vector3(-0.3, 0.9, 0.3))
		"camera":
			_arm(sk, sk_xf, "Left", Vector3(0.45, -0.55, 0.5), Vector3(-0.35, 0.8, 0.45), Vector3(-0.2, 0.9, 0.4))
			_arm(sk, sk_xf, "Right", Vector3(0.45, -0.55, 0.5), Vector3(-0.35, 0.8, 0.45), Vector3(-0.2, 0.9, 0.4))
		"flag":
			_arm(sk, sk_xf, "Left", stand_up, stand_fore)
			_arm(sk, sk_xf, "Right", Vector3(0.3, 0.95, 0.06), Vector3(0.08, 1.0, 0.0), Vector3(0.0, 1.0, 0.1))
		"seated":
			for s: String in ["Left", "Right"]:
				var x := 0.1 if s == "Left" else -0.1
				_aim(sk, sk_xf, s + "UpLeg", s + "Leg", Vector3(x, -0.08, 1.0))
				_aim(sk, sk_xf, s + "Leg", s + "Foot", Vector3(x * 0.5, -1.0, 0.12))
				_aim(sk, sk_xf, s + "Foot", s + "ToeBase", Vector3(0, -0.35, 1.0))
			_aim(sk, sk_xf, "Spine", "Spine1", Vector3(0, 1.0, 0.06))
			_arm(sk, sk_xf, "Left", Vector3(0.12, -0.9, 0.38), Vector3(-0.12, -0.25, 1.0))
			_arm(sk, sk_xf, "Right", Vector3(0.12, -0.9, 0.38), Vector3(-0.12, -0.25, 1.0))


class Baked:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()


## CPU skinning of every mesh into one vertex list with atlas UVs and region
## data. With `rest` == null the skeleton is in its rest pose and the regions
## are classified; posed bakes reuse the rest bake's regions (same vertex order).
func _skin(sk: Skeleton3D, sk_xf: Transform3D, meshes: Array, tiles: Dictionary, model: String, rest: Baked) -> Baked:
	var out := Baked.new()
	var belt := (sk_xf * _gp(sk, _bone(sk, "Hips")).origin).y + 0.07
	for mi: MeshInstance3D in meshes:
		var mat: BaseMaterial3D = mi.mesh.surface_get_material(0)
		var tile: Rect2i = tiles[mat.resource_name][0]
		var kind: String = tiles[mat.resource_name][1]
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bones.size() / v.size()
		var skin: Skin = mi.skin
		var mats: Array[Transform3D] = []
		var arm_w: PackedFloat32Array = []
		var arm_side: PackedFloat32Array = []
		var legish: PackedFloat32Array = []
		for bi in skin.get_bind_count():
			var b := skin.get_bind_bone(bi)
			if b < 0:
				b = sk.find_bone(skin.get_bind_name(bi))
			mats.append(sk_xf * _gp(sk, b) * skin.get_bind_pose(bi))
			var bn := sk.get_bone_name(b).trim_prefix("mixamorig_").trim_prefix("mixamorig:")
			var w := 0.0
			if bn.ends_with("ForeArm"):
				w = 0.75
			elif bn.ends_with("Arm"):
				w = 0.3
			elif bn.contains("Hand"):
				w = 1.0
			arm_w.append(w)
			arm_side.append(1.0 if bn.begins_with("Left") else 0.0)
			legish.append(1.0 if bn.contains("Leg") or bn.contains("Foot") or bn.contains("Toe") else 0.0)
		var base := out.verts.size()
		for k in v.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			var aw := 0.0
			var side := 0.0
			var leg := 0.0
			for j in per:
				var w := weights[k * per + j]
				if w <= 0.0:
					continue
				var bi := bones[k * per + j]
				p += (mats[bi] * v[k]) * w
				n += (mats[bi].basis * nrm[k]) * w
				aw += arm_w[bi] * w
				side += arm_side[bi] * w
				leg += legish[bi] * w
			var auv := (Vector2(tile.position) + Vector2(clampf(uv[k].x, 0.0, 1.0), clampf(uv[k].y, 0.0, 1.0)) * Vector2(tile.size - Vector2i(1, 1)) + Vector2(0.5, 0.5)) / ATLAS_SIZE
			var texel := atlas.get_pixelv(Vector2i(auv * ATLAS_SIZE).clamp(Vector2i.ZERO, Vector2i(ATLAS_SIZE - 1, ATLAS_SIZE - 1)))
			var vi := out.verts.size()
			var region: float
			if rest != null:
				region = rest.custom[vi * 4]
			else:
				region = _region(model, kind, p, aw, leg, belt, texel)
			out.verts.append(p)
			out.normals.append(n.normalized())
			out.uvs.append(auv)
			out.custom.append_array([region, aw, 1.0 if side > 0.5 else 0.0, texel.get_luminance()])
		for k in idx:
			out.indices.append(base + k)
	return out


func _region(model: String, kind: String, p: Vector3, arm: float, leg: float, belt: float, texel: Color) -> float:
	match kind:
		"skin": return R_SKIN
		"hair", "brows": return R_HAIR
		"shoes": return R_SHOES
		"eyes": return R_KEEP
	match MODELS[model].split:
		"blue_is_bottom":
			return R_BOTTOM if texel.b > texel.r + 0.08 and arm < 0.2 else R_TOP
		"white_is_keep":
			return R_KEEP if texel.s < 0.15 and texel.v > 0.6 else R_TOP
	return R_BOTTOM if (p.y < belt or leg > 0.6) and arm < 0.2 else R_TOP


## Model-space fixes after skinning: turn to face -Z, put the feet (or, seated,
## the underside of the thighs) at y = 0 and add props (the marshal's flag).
func _finish(b: Baked, sk: Skeleton3D, sk_xf: Transform3D, scale: float, pose: String, extra: Dictionary) -> void:
	var turn := Basis(Vector3.UP, PI)
	var min_y := INF
	for k in b.verts.size():
		var p := turn * (b.verts[k] * scale)
		b.verts[k] = p
		b.normals[k] = turn * b.normals[k]
		min_y = minf(min_y, p.y)
	var lift := -min_y
	if pose == "seated":
		# Origin on the seat: under the thighs, at the hips.
		var hip := turn * (sk_xf * _gp(sk, _bone(sk, "LeftUpLeg")).origin * scale)
		var knee := turn * (sk_xf * _gp(sk, _bone(sk, "LeftLeg")).origin * scale)
		lift = -(minf(hip.y, knee.y) - 0.085)
		for k in b.verts.size():
			b.verts[k] += Vector3(0, lift, -hip.z)
		lift = 0.0
	for k in b.verts.size():
		b.verts[k].y += lift
	var shoulder := turn * (sk_xf * _gp(sk, _bone(sk, "RightArm")).origin * scale) + Vector3(0, lift, 0)
	extra["pivot"] = shoulder
	if pose == "flag":
		var hand := turn * (sk_xf * _gp(sk, _bone(sk, "RightHand")).origin * scale) + Vector3(0, lift, 0)
		var grip := hand + Vector3(0, 0.08, 0)
		# Stick: a thin square tube from the grip up 0.95 m.
		_tube(b, grip - Vector3(0, 0.15, 0), grip + Vector3(0, 0.95, 0), 0.014, R_PROP)
		# Cloth: a 12 x 6 grid off the top of the stick, away from the body
		# (+X = the figure's right after the turn). CUSTOM0.z = 0 top .. 1 bottom,
		# CUSTOM0.w = 1 + 0 at the stick .. 1 at the free end (shader cloth motion).
		var top := grip + Vector3(0, 0.93, 0)
		var nx := 12
		var ny := 6
		var base := b.verts.size()
		for j in ny + 1:
			for i in nx + 1:
				var u := float(i) / nx
				var w := float(j) / ny
				b.verts.append(top + Vector3(0.9 * u, -0.6 * w, 0))
				b.normals.append(Vector3.BACK)
				b.uvs.append(Vector2(0.64, 0.51))
				b.custom.append_array([R_FLAG, 1.0, w, 1.0 + u])
		for j in ny:
			for i in nx:
				var a := base + j * (nx + 1) + i
				var c := a + nx + 1
				b.indices.append_array([a, a + 1, c + 1, a, c + 1, c])
	if pose in ["flag"]:
		# Flag-arm weights: only the raised (right) arm follows the wave.
		for k in b.verts.size():
			if b.custom[k * 4] < R_FLAG - 0.5 and b.custom[k * 4 + 2] > 0.5:
				b.custom[k * 4 + 1] = 0.0


## Removes triangles lying entirely below `y`.
func _drop_below(b: Baked, y: float) -> void:
	var keep := PackedInt32Array()
	for t in range(0, b.indices.size(), 3):
		var top := maxf(b.verts[b.indices[t]].y, maxf(b.verts[b.indices[t + 1]].y, b.verts[b.indices[t + 2]].y))
		if top > y:
			keep.append_array([b.indices[t], b.indices[t + 1], b.indices[t + 2]])
	b.indices = keep


func _vtx(b: Baked, p: Vector3, n: Vector3, uv: Vector2, c: Array) -> void:
	b.indices.append(b.verts.size())
	b.verts.append(p)
	b.normals.append(n)
	b.uvs.append(Vector2(0.64, 0.51))
	b.custom.append_array(c)


func _tube(b: Baked, a: Vector3, c: Vector3, r: float, region: float) -> void:
	var sides := [Vector3(r, 0, r), Vector3(-r, 0, r), Vector3(-r, 0, -r), Vector3(r, 0, -r)]
	for s in 4:
		var p0: Vector3 = sides[s]
		var p1: Vector3 = sides[(s + 1) % 4]
		var n := ((p0 + p1) * 0.5).normalized()
		var q := [a + p0, a + p1, c + p1, c + p0]
		for t: int in [0, 2, 1, 0, 3, 2]:
			_vtx(b, q[t], n, Vector2.ZERO, [region, 1.0, 0.0, 0.3])


## Welds, decimates to the two LODs and saves them.
func _write(b: Baked, key: String, extra: Dictionary) -> void:
	# CUSTOM0.w: mean texel luminance of the vertex's region (the shader divides
	# by it to keep only the folds/shading of recoloured clothing).
	var sums := {}
	for k in b.verts.size():
		var r: float = b.custom[k * 4]
		if r >= R_FLAG - 0.5:
			continue
		var s: Vector2 = sums.get(r, Vector2.ZERO)
		sums[r] = s + Vector2(b.custom[k * 4 + 3], 1.0)
	for k in b.verts.size():
		var r: float = b.custom[k * 4]
		if sums.has(r):
			b.custom[k * 4 + 3] = maxf(sums[r].x / sums[r].y, 0.05)
	var fmt := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var mesh := _to_mesh(_compact(b, b.indices), fmt)
	mesh.set_meta("pivot", extra.pivot)
	mesh.resource_name = key
	ResourceSaver.save(mesh, OUT + key + ".res", ResourceSaver.FLAG_COMPRESS)
	report.append("%s: %d tris" % [key, b.indices.size() / 3])


func _compact(b: Baked, idx: PackedInt32Array) -> Baked:
	var remap := {}
	var o := Baked.new()
	for k in idx:
		if not remap.has(k):
			remap[k] = o.verts.size()
			o.verts.append(b.verts[k])
			o.normals.append(b.normals[k])
			o.uvs.append(b.uvs[k])
			o.custom.append_array([b.custom[k * 4], b.custom[k * 4 + 1], b.custom[k * 4 + 2], b.custom[k * 4 + 3]])
		o.indices.append(remap[k])
	return o


func _to_mesh(b: Baked, fmt: int) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.verts
	arrays[Mesh.ARRAY_NORMAL] = b.normals
	arrays[Mesh.ARRAY_TEX_UV] = b.uvs
	arrays[Mesh.ARRAY_CUSTOM0] = b.custom
	arrays[Mesh.ARRAY_INDEX] = b.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	return mesh
