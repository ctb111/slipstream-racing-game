class_name Gx
extends RefCounted
## Gimmick kit core: where things go along the circuit. Every gimmick piece and
## every per-track dressing uses these helpers, so pieces sit on the ground,
## face the road, keep off the tarmac and keep trees away.
##
## Frames: +z points AWAY from the road, y is up, x runs along the track
## (with the driving direction on the right side, against it on the left, so
## the basis is never mirrored; Gx.frame_x() gives the driving direction). A piece built around its
## origin with its "front" facing -z therefore faces the road.
##
##   var xf := Gx.frame(c, 640.0, Gx.RIGHT, 6.0)   # 640 m round the lap, right side, 6 m off the edge
##   GxFans.place(c, xf, {count = 40})
##   var over := Gx.road_frame(c, 1200.0)           # centred on the road, x along, for things spanning it
##   Gx.reserve(c, xf.origin, 12.0)                 # keep trees/clutter out of a 12 m radius
##
## Piece files live next to this one as gx_<piece>.gd (class_name Gx<Piece>)
## with `static func place(c: Node3D, xf: Transform3D, opts := {}) -> void`.
## Per-track dressing lives in dress_<track_id>.gd with
## `static func dress(c: Node3D) -> void`; gimmicks.gd calls it.

const LEFT := -1.0
const RIGHT := 1.0


## The lap curve (offsets measured from the start line) and its length.
static func curve(c: Node3D) -> Curve3D:
	return c.get("curve")


static func length(c: Node3D) -> float:
	return curve(c).get_baked_length()


static func half_width() -> float:
	return TrackDefs.ROAD_WIDTH * 0.5


## Point on the centreline `along` metres round the lap from the start line.
static func centre(c: Node3D, along: float) -> Vector3:
	var cv := curve(c)
	var l := cv.get_baked_length()
	return cv.sample_baked(fposmod(along + float(c.get("start_offset")), l))


static func tangent(c: Node3D, along: float) -> Vector3:
	var t := centre(c, along + 1.5) - centre(c, along - 1.5)
	t.y = 0.0
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


static func ground(c: Node3D, p: Vector3) -> float:
	var t = c.get("terrain")
	return (t as Terrain).height_at(p.x, p.z) if t is Terrain else p.y


## Frame beside the road: `lateral` metres beyond the road EDGE on `side`
## (Gx.LEFT / Gx.RIGHT), standing on the terrain, -z facing the road.
static func frame(c: Node3D, along: float, side: float, lateral: float) -> Transform3D:
	var p := centre(c, along)
	var t := tangent(c, along)
	var r := t.cross(Vector3.UP).normalized() # right of the driving direction
	var out := r * side
	var pos := p + out * (half_width() + lateral)
	pos.y = ground(c, pos)
	# Keep the basis right-handed on both sides (a mirrored basis turns meshes
	# inside-out and text back to front): on the left, +x runs against the
	# driving direction. Use `frame_x(xf)` for the driving direction.
	return Transform3D(Basis(t * side, Vector3.UP, out), pos)


## Driving direction (unit, horizontal) at a frame from `frame()` (or any point).
static func frame_x(c: Node3D, xf: Transform3D) -> Vector3:
	var cv := curve(c)
	var off := cv.get_closest_offset(xf.origin)
	var t := cv.sample_baked(fposmod(off + 1.5, cv.get_baked_length())) - cv.sample_baked(fposmod(off - 1.5, cv.get_baked_length()))
	t.y = 0.0
	return t.normalized()


## Frame centred on the road surface, x along the track, z to the right:
## for things that span the road (arches, bridges, gantries, buildings).
static func road_frame(c: Node3D, along: float) -> Transform3D:
	var p := centre(c, along)
	var t := tangent(c, along)
	var r := t.cross(Vector3.UP).normalized()
	return Transform3D(Basis(t, Vector3.UP, r), p)


## True when `p` is at least `margin` metres outside the road edge (2D).
static func clear_of_road(c: Node3D, p: Vector3, margin := 1.5) -> bool:
	var q := curve(c).get_closest_point(p)
	return Vector2(p.x - q.x, p.z - q.z).length() > half_width() + margin


## Keep trees and scatter out of a circle (the forest is built after dressing).
static func reserve(c: Node3D, p: Vector3, radius: float) -> void:
	var nt: Array = c.get_meta("no_trees", [])
	nt.append([p, radius])
	c.set_meta("no_trees", nt)


## Corners of the lap: [{along, turn (+right / -left), strength 0..1}], sharpest
## first. Straights: [{from, to}] longer than `min_len` metres.
static func corners(c: Node3D, min_strength := 0.25) -> Array:
	var out := []
	var l := length(c)
	var step := 4.0
	var prev_t := tangent(c, 0.0)
	var best := {}
	for i in int(l / step):
		var along := i * step
		var t := tangent(c, along + step)
		var turn := prev_t.signed_angle_to(t, Vector3.UP) / step * 25.0 # ~1 at a hairpin
		prev_t = t
		var s := clampf(absf(turn), 0.0, 1.0)
		if s >= min_strength:
			var key := int(along / 60.0) # one entry per 60 m stretch
			if not best.has(key) or s > best[key].strength:
				best[key] = {along = along, turn = -signf(turn), strength = s}
	for k in best:
		out.append(best[k])
	out.sort_custom(func(a, b): return a.strength > b.strength)
	return out


static func straights(c: Node3D, min_len := 120.0) -> Array:
	var out := []
	var l := length(c)
	var step := 4.0
	var start := -1.0
	var prev_t := tangent(c, 0.0)
	for i in int(l / step) + 1:
		var along := i * step
		var t := tangent(c, along + step)
		var straight := absf(prev_t.signed_angle_to(t, Vector3.UP)) / step * 25.0 < 0.08
		prev_t = t
		if straight and start < 0.0:
			start = along
		elif not straight and start >= 0.0:
			if along - start >= min_len:
				out.append({from = start, to = along})
			start = -1.0
	return out


## Seeded RNG per circuit and purpose, so dressing is the same every load and
## on every machine in an online race.
static func rng(c: Node3D, purpose: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var def = c.get("def")
	r.seed = hash(str(def.get("id", "")) + purpose) if def is Dictionary else hash(purpose)
	return r


## Merge-friendly helper: add a finished SurfaceTool as one MeshInstance3D with
## a material, no shadow by default, visible up to `vis_end` metres (0 = always).
static func add_mesh(c: Node3D, st: SurfaceTool, mat: Material, node_name: String, vis_end := 600.0, shadows := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_end > 0.0:
		var aabb := mi.mesh.get_aabb()
		mi.visibility_range_end = vis_end + aabb.size.length() * 0.5 # Godot measures to the AABB centre
		mi.visibility_range_end_margin = vis_end * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF # dissolve over the margin, no pop
	c.add_child(mi)
	return mi
