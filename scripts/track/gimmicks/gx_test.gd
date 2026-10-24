class_name GxTest
extends RefCounted
## Debug: place Gx pieces on any track and photograph them, one run, many shots.
##   tools/bgrun.sh res://scenes/race.tscn -- --track=kiefernring --bots=0 \
##       --gx_test=overpass:road,arch:gate,sponsor:inflatable --gx_shots=/tmp/gx [--gx_at=300,900,..]
## Each piece goes on its own straight (or at --gx_at metres), is timed, then the
## camera visits views "far", "driver", "side", "close" for each piece and saves
## <dir>/<n>_<piece>_<view>.png. Quits when done. Off unless --gx_test is given.

const PIECES := {
	overpass = "res://scripts/track/gimmicks/gx_overpass.gd",
	arch = "res://scripts/track/gimmicks/gx_arch.gd",
	sponsor = "res://scripts/track/gimmicks/gx_sponsor_arch.gd",
	signs = "res://scripts/track/gimmicks/gx_sign_gantry.gd",
	power = "res://scripts/track/gimmicks/gx_power.gd",
	turbine = "res://scripts/track/gimmicks/gx_turbine.gd",
	tower = "res://scripts/track/gimmicks/gx_tower.gd",
	camp = "res://scripts/track/gimmicks/gx_camp.gd",
	cars = "res://scripts/track/gimmicks/gx_parked_cars.gd",
	heli = "res://scripts/track/gimmicks/gx_heli.gd",
	sky = "res://scripts/track/gimmicks/gx_sky.gd",
	hosp = "res://scripts/track/gimmicks/gx_hospitality.gd",
	farm = "res://scripts/track/gimmicks/gx_farm.gd",
	fans = "res://scripts/track/gimmicks/gx_fans.gd",
	graffiti = "res://scripts/track/gimmicks/gx_graffiti.gd",
	roadtext = "res://scripts/track/gimmicks/gx_road_text.gd",
	billboard = "res://scripts/track/gimmicks/gx_billboard.gd",
	warehouse = "res://scripts/track/gimmicks/gx_warehouse.gd",
	industrial = "res://scripts/track/gimmicks/gx_industrial.gd",
	roadside = "res://scripts/track/gimmicks/gx_roadside.gd",
	works = "res://scripts/track/gimmicks/gx_works.gd",
}


static func args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gx_"):
			var kv := a.substr(5).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


static func maybe_run(c: Node3D) -> void:
	var a := args()
	if not a.has("test"):
		return
	var specs: Array = Array(a.test.split(","))
	var ats: Array = []
	if a.has("at"):
		for s in a.at.split(","):
			ats.append(float(s))
	else:
		var st := Gx.straights(c, 90.0)
		st.sort_custom(func(p, q): return p.to - p.from > q.to - q.from)
		for s in st:
			ats.append((s.from + s.to) * 0.5)
		if ats.size() < specs.size(): # not enough straights: spread round the lap
			ats.clear()
			for k in specs.size():
				ats.append(Gx.length(c) * (k + 0.5) / specs.size())
	var shots := []
	for n in specs.size():
		var spec: String = specs[n]
		var parts := spec.split(":")
		var piece := parts[0]
		var opts := {}
		if parts.size() > 1:
			opts.kind = parts[1]
		for k in range(2, parts.size()):
			var kv := parts[k].split("=")
			opts[kv[0]] = kv[1] if kv.size() > 1 else true
		if not PIECES.has(piece) or not ResourceLoader.exists(PIECES[piece]):
			push_warning("gx_test: no piece " + piece)
			continue
		var along: float = ats[n % maxi(ats.size(), 1)] if not ats.is_empty() else n * 400.0
		if str(opts.get("at", "")) == "dip": # deepest terrain dip under the road (bridges)
			along = dip(c)
		elif opts.has("at"):
			along = float(opts.at)
		var xf := Gx.road_frame(c, along)
		if opts.has("side"): # side pieces: :side=6 (metres off the right edge), :side=-6 (left)
			var lat := float(opts.side)
			xf = Gx.frame(c, along, signf(lat) if lat != 0.0 else 1.0, absf(lat))
		var t0 := Time.get_ticks_usec()
		load(PIECES[piece]).place(c, xf, opts)
		print("gx_test: %s %s at %.0f m: %.2f ms" % [piece, opts, along, (Time.get_ticks_usec() - t0) / 1000.0])
		if not GxGeo.stats.is_empty():
			print("gx_test:   meshes [draw calls, triangles]: ", GxGeo.stats)
			GxGeo.stats.clear()
		var o := xf.origin
		var x := xf.basis.x
		var z := xf.basis.z
		var up := Vector3.UP
		var behind := Gx.centre(c, along - 70.0) + up * 1.3
		var near := Gx.centre(c, along - 28.0) + up * 1.2
		shots.append(["%d_%s_%s_far" % [n, piece, opts.get("kind", "")], behind, o + up * 4.0])
		shots.append(["%d_%s_%s_driver" % [n, piece, opts.get("kind", "")], near, o + up * 4.5])
		shots.append(["%d_%s_%s_side" % [n, piece, opts.get("kind", "")], o - x * 34.0 + z * 26.0 + up * 6.0, o + up * 4.0])
		shots.append(["%d_%s_%s_close" % [n, piece, opts.get("kind", "")], o - x * 9.0 - z * 4.0 + up * 1.6, o + z * 9.5 + up * 4.0])
		var script = load(PIECES[piece])
		if script.has_method("views"): # extra [name, from, look_at] views from the piece itself
			for v: Array in script.views(c, xf, opts):
				shots.append(["%d_%s_%s_%s" % [n, piece, opts.get("kind", ""), v[0]], v[1], v[2]])
	var shooter := Shooter.new()
	shooter.shots = shots
	shooter.dir = a.get("shots", "/tmp/gx")
	shooter.only = a.get("views", "")
	c.add_child(shooter)


class Shooter:
	extends Node
	var shots: Array = []
	var dir := ""
	var only := ""

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		DirAccess.make_dir_recursive_absolute(dir)
		await get_tree().create_timer(9.0, true).timeout
		for s: Array in shots:
			if only != "" and not str(s[0]).ends_with(only) and not only.split("|").has(str(s[0]).get_slice("_", 3)):
				continue
			var cam := get_viewport().get_camera_3d()
			if cam and "debug_world" in cam:
				cam.debug_world = [s[1], s[2]]
				cam.fov = 55.0
			for i in 25:
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(dir.path_join(str(s[0]) + ".png"))
			print("gx_test: shot ", dir.path_join(str(s[0]) + ".png"))
		get_tree().quit()


## Lap distance where the terrain beside the road is lowest below it.
static func dip(c: Node3D) -> float:
	var best := 0.0
	var best_d := -INF
	var l := Gx.length(c)
	var k := 0.0
	while k < l:
		var f := Gx.road_frame(c, k)
		var d := INF
		for z: float in [-10.0, -16.0, 10.0, 16.0]:
			d = minf(d, f.origin.y - Gx.ground(c, f * Vector3(0, 0, z)))
		if d > best_d:
			best_d = d
			best = k
		k += 10.0
	print("gx_test: dip %.1f m deep at %.0f m" % [best_d, best])
	return best
