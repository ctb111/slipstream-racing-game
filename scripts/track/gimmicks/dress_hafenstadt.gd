extends RefCounted
## Hafenstadt dressing (the city, port, waterfront and rail crossing come from
## theme_harbour.gd; its SITES are kept free of buildings for these pieces):
##   - a brick warehouse the road drives straight through (warehouse district),
##   - the tunnel into downtown,
##   - a road flyover and a railway bridge over the downtown streets,
##   - a steel footbridge over the waterfront straight,
##   - motorway sign gantries on the elevated section,
##   - graffiti on the warehouse-district walls and under the bridges,
##   - billboards, fan banks behind the barriers, painted road messages.

const P := "res://scripts/track/gimmicks/"


static func _has(piece: String) -> bool:
	return ResourceLoader.exists(P + piece + ".gd")


## Lap distance (from the start line) of the track point nearest a world XZ.
static func _at(c: Node3D, x: float, z: float) -> float:
	var cv := Gx.curve(c)
	var off := cv.get_closest_offset(Vector3(x, cv.sample_baked(0.0).y, z))
	# Height matters little here (flat-ish city); refine with the 3D nearest.
	var best := off
	var bd := INF
	for k in 9:
		var o := fposmod(off + (k - 4) * 6.0, cv.get_baked_length())
		var p := cv.sample_baked(o)
		var d := Vector2(p.x - x, p.z - z).length()
		if d < bd:
			bd = d
			best = o
	return fposmod(best - float(c.get("start_offset")), Gx.length(c))


## The merged city meshes (theme_harbour.gd) cast no shadows at night (only
## the moon; costly with a whole city in the shadow pass); by day only the
## building blocks do.
static func _shadows(c: Node3D) -> void:
	var w = c.get("weather")
	var night := w != null and float(w.preset.get("night", 0.0)) > 0.0
	for ch in c.get_children():
		if ch is GeometryInstance3D and str(ch.name).begins_with("Theme"):
			if night or not str(ch.name).begins_with("Theme_city"):
				(ch as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## City night: sodium sky glow over the horizon, warm bounce ambient and a
## warm-grey haze, so streets and building bases read between the lamps.
static func _night_city(c: Node3D) -> void:
	var w = c.get("weather")
	if w == null or float(w.preset.get("night", 0.0)) <= 0.0:
		return
	var env: Environment = w.env
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.5, 0.4)
	env.ambient_light_energy = 0.32
	env.fog_light_color = Color(0.2, 0.16, 0.13)
	env.fog_density = maxf(env.fog_density, 0.0016)
	# Sky glow: a huge open cylinder far beyond the skyline, orange-grey at
	# the horizon fading out upwards (unshaded, no fog, drawn behind everything).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ctr: Vector3 = Gx.centre(c, 0.0)
	var r := 2600.0
	var segs := 48
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := ctr + Vector3(cos(a0) * r, -60.0, sin(a0) * r)
		var p1 := ctr + Vector3(cos(a1) * r, -60.0, sin(a1) * r)
		var q0 := p0 + Vector3.UP * 900.0
		var q1 := p1 + Vector3.UP * 900.0
		for v: Array in [[p0, 0.0], [p1, 0.0], [q1, 1.0], [p0, 0.0], [q1, 1.0], [q0, 1.0]]:
			st.set_uv(Vector2(0.0, v[1]))
			st.add_vertex(v[0])
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, fog_disabled, blend_add, depth_draw_never, cull_disabled, shadows_disabled;\nvoid fragment() {\n\tfloat h = UV.y;\n\tALBEDO = vec3(0.32, 0.17, 0.08) * pow(1.0 - h, 3.0) + vec3(0.03, 0.025, 0.03) * (1.0 - h);\n}\n"
	m.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "HafenSkyGlow"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3000.0
	c.add_child(mi)


static func dress(c: Node3D) -> void:
	if ResourceLoader.exists(P + "dress_shots.gd"):
		load(P + "dress_shots.gd").attach(c)
	var rng := Gx.rng(c, "dress")
	_shadows(c)
	_night_city(c)
	var used: Array = []
	# Drive-through brick warehouse (theme site at 350, 190).
	if _has("gx_warehouse"):
		var a := _at(c, 350, 190)
		GxWarehouse.place(c, Gx.road_frame(c, a), {kind = "warehouse", length = 54.0, brick = true, sodium = true})
		Gx.reserve(c, Gx.centre(c, a), 40.0)
		used.append(a)
		var tn := _at(c, -420, -150)
		GxWarehouse.place(c, Gx.road_frame(c, tn), {kind = "tunnel", length = 90.0, name = "HAFENTUNNEL", sodium = true})
		used.append(tn)
	if _has("gx_overpass"):
		var a := _at(c, -370, 120)
		GxOverpass.place(c, Gx.road_frame(c, a), {kind = "road", banner = "b_nordlicht", ramps = false})
		used.append(a)
		var r := _at(c, -260, 30)
		GxOverpass.place(c, Gx.road_frame(c, r), {kind = "rail", ramps = false})
		used.append(r)
		var f := _at(c, -300, 300)
		GxOverpass.place(c, Gx.road_frame(c, f), {kind = "footbridge", banner = "b_marzelli", graffiti = false})
		used.append(f)
	if _has("gx_sign_gantry"):
		for x: float in [230.0, -60.0]:
			var a := _at(c, x, -280)
			GxSignGantry.place(c, Gx.road_frame(c, a), {boards = [4, 2]})
			used.append(a)
	if _has("gx_graffiti"):
		# Warehouse district walls (left side of BC is the inside: brick yard walls)
		for k: Array in [[350, 120, Gx.LEFT], [350, 250, Gx.RIGHT], [620, 0, Gx.LEFT], [-420, -90, Gx.RIGHT], [-260, 80, Gx.LEFT]]:
			GxGraffiti.place(c, Gx.frame(c, _at(c, k[0], k[1]), k[2], 4.6), {kind = "retaining", length = 20.0, height = 3.2})
	if _has("gx_billboard"):
		var brands := ["NORDLICHT", "HELIOS BENZIN", "OSTRA FILM", "AUREL WATCHES", "VALTER OIL", "MARZELLI"]
		var spots := [[100, -280, Gx.LEFT], [380, -270, Gx.RIGHT], [-250, -280, Gx.RIGHT], [500, 80, Gx.LEFT], [620, -130, Gx.RIGHT], [-480, 200, Gx.LEFT]]
		for k in spots.size():
			var s: Array = spots[k]
			GxBillboard.place(c, Gx.frame(c, _at(c, s[0], s[1]), s[2], 5.4), {brand = brands[k % brands.size()]})
		for s: Array in [[340, 290, Gx.LEFT], [-410, -60, Gx.LEFT], [-275, 120, Gx.LEFT]]:
			GxBillboard.place(c, Gx.frame(c, _at(c, s[0], s[1]), s[2], 2.2), {kind = "sign", sign = "chevron", count = 3})
	if _has("gx_fans"):
		# Behind the barriers at the big braking zones and along the waterfront.
		for s: Array in [[330, 300, Gx.LEFT, 14], [350, 95, Gx.RIGHT, 10], [-405, -60, Gx.LEFT, 12], [-260, 105, Gx.RIGHT, 10],
				[-470, 120, Gx.RIGHT, 12], [-480, 285, Gx.LEFT, 12], [200, 300, Gx.RIGHT, 16], [-40, 300, Gx.RIGHT, 18], [600, 80, Gx.RIGHT, 10]]:
			GxFans.place(c, Gx.frame(c, _at(c, s[0], s[1]), s[2], 1.6), {count = s[3], flags = 2, flares = 1 if rng.randf() < 0.4 else 0, banner = rng.randf() < 0.5, depth = 2.2})
		GxFans.place(c, Gx.frame(c, _at(c, 120, 300), Gx.LEFT, 1.0), {kind = "banners", length = 60.0})
		GxFans.place(c, Gx.frame(c, _at(c, -200, 300), Gx.RIGHT, 1.0), {kind = "banners", length = 50.0, keys = ["b_nordlicht", "b_helios", "b_valter"]})
		GxFans.place(c, Gx.frame(c, _at(c, -420, -40), Gx.LEFT, 1.0), {kind = "photographers"})
	if _has("gx_parked_cars"):
		# Residents' cars parked along the pavements, outside the barriers.
		for s: Array in [[-340, -60, Gx.RIGHT], [-260, 60, Gx.LEFT], [-400, 120, Gx.LEFT], [350, 140, Gx.RIGHT], [-480, 220, Gx.RIGHT], [-250, 300, Gx.LEFT]]:
			GxParkedCars.place(c, Gx.frame(c, _at(c, s[0], s[1]), s[2], 4.0), {count = 5, layout = "parallel", people = false, dirt = 0.15, seed = rng.randi()})
	if _has("gx_fans"):
		# Fans packed behind the catch fence all round the lap.
		var l := Gx.length(c)
		var a := 60.0
		var k := 0
		while a < l - 60.0:
			var near := false
			for u: float in used:
				if absf(a - u) < 60.0:
					near = true
			var p := Gx.centre(c, a)
			if not near and not (p.x > 385.0 and p.x < 645.0 and p.z > -170.0 and p.z < 130.0):
				GxFans.place(c, Gx.frame(c, a, Gx.LEFT if k % 2 == 0 else Gx.RIGHT, 1.4), {count = rng.randi_range(6, 11), flags = 1, banner = rng.randf() < 0.3, depth = 2.0, tape = false})
				k += 1
			a += 190.0
	if _has("gx_road_text"):
		GxRoadText.place(c, Gx.road_frame(c, _at(c, 0, -280)), {kind = "mixed"})
		GxRoadText.place(c, Gx.road_frame(c, _at(c, 350, 230)), {kind = "arrows"})
		GxRoadText.place(c, Gx.road_frame(c, _at(c, -260, 0)), {kind = "name", color = "yellow"})
		GxRoadText.place(c, Gx.road_frame(c, _at(c, 150, 300)), {kind = "player"})
	if _has("gx_heli"):
		GxHeli.place(c, Transform3D.IDENTITY, {alt_min = 110.0})
