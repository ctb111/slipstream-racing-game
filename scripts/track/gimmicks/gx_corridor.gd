class_name GxCorridor
extends RefCounted
## Near-road corridor: frames the view close to the road on both sides of
## every circuit (classic 70s-90s circuits, NFS / Ridge Racer corridors), so a
## glance sideways shows something near instead of open fields and sky.
##
## Per 60 m segment and side, from the track's PROFILES row:
##   - a dense tree wall 6-36 m behind the guardrail (always, where the land
##     allows): not built here but stamped into a 10 m grid
##     (meta "corridor_trees") that WorldBuilder._edge_belt reads, so the trees
##     ride the forest's near/far LOD chain (never pop) and keep out of every
##     Gx.reserve / no_trees footprint;
##   - in front of it, sometimes: tall chain-link catch fencing, a run of
##     sponsor hoardings (fictional brands from the trackside sign atlas) or a
##     graffiti wall.
## Man-made parts merge into the shared TracksideKit cells (one draw call per
## material per 80 m cell); the fence mesh is merged per 160 m cell. Called by
## gimmicks.gd after dress_<track>.gd (so set pieces are reserved already) and
## before fill_landscape.gd (which skips fields the wall hides).
## --corridor_off skips it (perf A/B).

const SEG := 30 ## samples (2 m each) per segment
const GRID := 10.0 ## metres per tree-wall grid cell
const FENCE_CELL := 160.0
const FENCE_H := 3.6
const BANNERS := ["b_helios", "b_valter", "b_kronen", "b_nordlicht", "b_aurel", "b_rallye", "b_falke", "b_marzelli"]

## trees: tree-wall strength (0 = none: towns keep their buildings); fence /
## hoard / graffiti: chance per segment and side of that front layer.
const PROFILES := {
	kiefernring = {trees = 1.0, fence = 0.18, hoard = 0.22, graffiti = 0.04},
	hochwald = {trees = 1.0, fence = 0.15, hoard = 0.22, graffiti = 0.04},
	herbstwald = {trees = 0.75, fence = 0.12, hoard = 0.2, graffiti = 0.04},
	schneekopf = {trees = 1.0, fence = 0.12, hoard = 0.15, graffiti = 0.0},
	alpenpass = {trees = 0.9, fence = 0.1, hoard = 0.15, graffiti = 0.0},
	brackenmoor = {trees = 0.6, fence = 0.15, hoard = 0.2, graffiti = 0.04},
	valtellina = {trees = 0.85, fence = 0.3, hoard = 0.3, graffiti = 0.03},
	valle_club = {trees = 0.6, fence = 0.12, hoard = 0.28, graffiti = 0.04},
	kuestenstrasse = {trees = 0.6, fence = 0.12, hoard = 0.22, graffiti = 0.04},
	capo_rosso = {trees = 0.7, fence = 0.12, hoard = 0.22, graffiti = 0.03},
	altstadt = {trees = 0.0, fence = 0.0, hoard = 0.25, graffiti = 0.0}, # least fps margin: hoardings only
}


static func build(c: Node3D) -> void:
	var def = c.get("def")
	if not def is Dictionary or def.get("street", false) or OS.get_cmdline_user_args().has("--corridor_off"):
		return
	var prof: Dictionary = PROFILES.get(def.get("id", ""), {})
	if prof.is_empty():
		return
	var kit := TracksideKit.shared(c)
	var rng := Gx.rng(c, "corridor")
	var vary := FastNoiseLite.new() # slow change of wall strength along the lap
	vary.seed = 4242
	vary.frequency = 0.004
	var grid := {}
	var fences := {} # cell -> SurfaceTool
	var counts := {trees = 0, fence = 0, hoard = 0, graffiti = 0}
	var tw: float = prof.trees
	for s in range(0, kit.n, SEG):
		for side: float in [-1.0, 1.0]:
			var x := rng.randf()
			if x < float(prof.fence):
				counts.fence += int(_fence(kit, s, s + SEG, side, fences))
			elif x < float(prof.fence) + float(prof.hoard):
				counts.hoard += int(_hoardings(kit, s, s + SEG, side, rng))
			elif x < float(prof.fence) + float(prof.hoard) + float(prof.graffiti):
				kit.graffiti_wall(s + SEG / 2, side, 24.0)
				counts.graffiti += 1
			if tw <= 0.0:
				continue
			var cen := kit.centers[kit._i(s)]
			var strength := tw * lerpf(0.65, 1.0, vary.get_noise_2d(cen.x, cen.z) * 0.5 + 0.5)
			for i in range(s, s + SEG, 2):
				var rail := kit.rail_dist(i, side)
				var road_y := kit.centers[kit._i(i)].y
				for lat: float in [rail + 6.0, rail + 13.0, rail + 20.0, rail + 28.0, rail + 36.0]:
					var p := kit.at(i, side * lat)
					if not kit.road_clear(p, 4.0) or not kit.in_terrain(p, 20.0):
						continue # another stretch of road / edge of the map
					if p.y < road_y - 5.0:
						break # falls away (embankment, cliff, sea): leave the view open
					var key := Vector2i(floori(p.x / GRID), floori(p.z / GRID))
					grid[key] = maxf(float(grid.get(key, 0.0)), strength)
			counts.trees += 1
	c.set_meta("corridor_trees", grid)
	var mat := _fence_material()
	for k: Vector2i in fences:
		Gx.add_mesh(c, fences[k], mat, "CorridorFence", 320.0)
	print("corridor %s: %s, %d wall cells" % [def.get("id", ""), counts, grid.size()])


## Tree-wall strength (0..1) at world point `p` (0 where there is no wall).
static func boost_at(c: Node3D, p: Vector3) -> float:
	var g: Dictionary = c.get_meta("corridor_trees", {})
	return float(g.get(Vector2i(floori(p.x / GRID), floori(p.z / GRID)), 0.0))


## Tall chain-link catch fence 1.6 m behind the rail from sample i0 to i1:
## galvanised posts every 4 m, top and bottom tubes, mesh panels. Gaps where
## the ground is taken (set pieces, the corner fences of TrackProps).
static func _fence(kit: TracksideKit, i0: int, i1: int, side: float, fences: Dictionary) -> bool:
	var steel := Color(0.62, 0.63, 0.64)
	var prev := Vector3.INF
	var u := 0.0
	var any := false
	for i in range(i0, i1 + 1, 2):
		var p := kit.at(i, side * (kit.rail_dist(i, side) + 1.6))
		if not kit.site_ok(p, 0.5, 1.0):
			prev = Vector3.INF
			continue
		kit.cyl("steel", "small", Transform3D(Basis(), p), Vector3(0, FENCE_H * 0.5, 0), 0.045, FENCE_H, steel, 6)
		if prev != Vector3.INF and prev.distance_to(p) < 6.0:
			for y: float in [0.15, FENCE_H - 0.05]:
				kit.strut("steel", "small", prev + Vector3(0, y, 0), p + Vector3(0, y, 0), 0.05, steel)
			var key := Vector2i(floori(p.x / FENCE_CELL), floori(p.z / FENCE_CELL))
			if not fences.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				fences[key] = st
			var seg := prev.distance_to(p)
			var nrm := (p - prev).cross(Vector3.UP).normalized()
			var q := [[prev, u, 0.0], [p, u + seg, 0.0], [p + Vector3.UP * FENCE_H, u + seg, FENCE_H], [prev + Vector3.UP * FENCE_H, u, FENCE_H]]
			for k: int in [0, 1, 2, 0, 2, 3]:
				fences[key].set_normal(nrm)
				fences[key].set_uv(Vector2(q[k][1], q[k][2]) * 4.0)
				fences[key].add_vertex(q[k][0])
			u += seg
			any = true
		prev = p
	return any


## A run of sponsor hoardings (8 x 1.1 m printed boards on steel legs) just
## behind the rail, facing the road, brands changing every few boards.
static func _hoardings(kit: TracksideKit, i0: int, i1: int, side: float, rng: RandomNumberGenerator) -> bool:
	var brand := rng.randi() % BANNERS.size()
	var any := false
	var n := 0
	for i in range(i0, i1 - 3, 4):
		var a := kit.at(i, side * (kit.rail_dist(i, side) + 1.2))
		var e := kit.at(i + 4, side * (kit.rail_dist(i + 4, side) + 1.2))
		var mid := (a + e) * 0.5
		var along := e - a
		along.y = 0.0
		var w := along.length()
		if w < 6.0 or w > 10.0 or not kit.site_ok(mid, 2.0, 0.8):
			continue
		var face := -along.normalized().cross(Vector3.UP) * side # towards the road
		var m := kit.frame_facing(mid, face)
		var h := 1.1
		var y := 0.55 + h * 0.5
		kit.box("props", "mid", m, Vector3(0, y, 0.04), Vector3(w + 0.02, h + 0.06, 0.06), TracksideKit.DARK)
		kit.quad("props", "mid", m, Vector3(0, y, 0.0), Vector3(0, 0, -1), w, h, BANNERS[brand % BANNERS.size()])
		for sx: float in [-0.42, 0.0, 0.42]:
			kit.box("steel", "small", m, Vector3(sx * w, (y - h * 0.5) * 0.5, 0.1), Vector3(0.06, y - h * 0.5 + 0.1, 0.06), Color(0.6, 0.6, 0.62))
		n += 1
		if n % 3 == 0:
			brand += 1
		any = true
	return any


## Galvanised chain-link: a wire-diamond alpha mask (a mesh pattern, not
## printed detail), alpha-scissored, metallic.
static func _fence_material() -> StandardMaterial3D:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for t in s:
		for w in 2:
			img.set_pixel((t + w) % s, t, Color(1, 1, 1, 1))
			img.set_pixel((s - 1 - t + w) % s, t, Color(1, 1, 1, 1))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.57, 0.57)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = 0.7
	m.roughness = 0.5
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
