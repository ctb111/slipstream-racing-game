class_name Atmosphere
extends Node3D
## Air you can see: mist lying in the valleys (dawn, a little at golden hour),
## low height fog under it, a warm sun-scattered dust haze on dry days, and
## dust motes that light up when you look into a low sun. Built after the
## terrain (Circuit.EXTRA_BUILDERS), tuned from the weather preset's `mist`
## and `haze` keys. Costs: mist = 1-2 big depth-tested transparent planes
## (only drawn where land lies below them), motes = one small particle system.
## Wind: leaves and paper skittering across the road near the camera when a
## gust front (wx_gust in weather.gdshaderinc; gust() here) passes, and a few
## windsocks by the corners. Debug: `-- --nomist`, `-- --nomotes`, `-- --nodebris`.

const MOTES := [0, 160, 260, 360] ## per Game.quality
const DEBRIS := [0, 60, 90, 120] ## per Game.quality
const WX_DIR := Vector2(0.9246, 0.3807) ## same as the shaders' WX_DIR

var _motes: GPUParticles3D
var _debris: GPUParticles3D
var _ground_y := 0.0
var _ray_t := 0.0
var _dbg_gust := -1.0
var _devil: MeshInstance3D
var _devil_mat: ShaderMaterial
var _devil_t := -1.0 ## seconds into the current devil (<0 = waiting)
var _devil_wait := 25.0
var _terrain


## CPU twin of wx_gust() (shaders/weather.gdshaderinc): 0 calm .. 1 in a gust front.
static func gust(xz: Vector2, wind: float, t: float) -> float:
	var spd := 4.0 + 10.0 * wind
	var a := xz.dot(WX_DIR) - t * spd
	var b := xz.dot(Vector2(-WX_DIR.y, WX_DIR.x))
	var g1 := sin(a * 0.045 + sin(b * 0.013) * 2.0) * 0.5 + 0.5
	var g2 := sin(a * 0.11 + b * 0.021 + 1.7) * 0.5 + 0.5
	return smoothstep(0.5, 1.0, g1 * 0.7 + g2 * 0.3) * (0.35 + 0.65 * smoothstep(0.1, 0.6, wind))


static func build(parent: Node3D, _curve: Curve3D, road_width: float, preset: Dictionary) -> void:
	var weather = parent.get("weather")
	var terrain = parent.get("terrain")
	if not (weather is Weather) or terrain == null:
		return
	var w: Weather = weather
	var night := float(preset.get("night", 0.0)) > 0.0
	var mist := 0.0 if night else float(preset.get("mist", 0.0))
	var haze := 0.0 if night else float(preset.get("haze", 0.0))
	var args := OS.get_cmdline_user_args()
	if args.has("--nomist"):
		mist = 0.0
	var a := Atmosphere.new()
	a.name = "Atmosphere"
	parent.add_child(a)
	var sun_dir := w.sun.global_basis.z.normalized() if w.sun else Vector3(0, 0.2, -1)
	var sun_col: Color = preset.get("sun_color", Color.WHITE)
	var env := w.env

	# Valley level: a low percentile of the land around the circuit.
	var hs: PackedFloat32Array = terrain.heights
	var sample := PackedFloat32Array()
	for i in range(0, hs.size(), 37):
		sample.append(hs[i])
	sample.sort()
	var lo := sample[int(sample.size() * 0.08)] if sample.size() > 0 else 0.0
	var mid := sample[int(sample.size() * 0.5)] if sample.size() > 0 else 0.0
	var level := lerpf(lo, mid, 0.85) + 2.0

	if mist > 0.0:
		# Height fog: everything low sits in a faint veil, thickest in the hollows.
		env.fog_height = level + 2.0
		env.fog_height_density = 0.02 * mist
		var fc: Color = preset.get("fog_color", Color(0.7, 0.7, 0.75))
		var mist_col := fc.lerp(Color(0.92, 0.9, 0.95), 0.35) * clampf(float(preset.get("sky_energy", 1.0)), 0.3, 1.0)
		var layers := 1 if Game.quality <= 1 else 2 # Low/Medium: one layer
		for k in layers:
			a._mist_plane(terrain, level + k * 4.0, mist * (0.9 if k == 0 else 0.55), mist_col, sun_col, sun_dir, k * 0.37)
	if haze > 0.0 and w.kind != Weather.Kind.STORM and w.kind != Weather.Kind.SNOW:
		# Dry-day haze: the air towards a low sun glows; distance goes warm and soft.
		env.fog_sun_scatter = 0.05 * haze * clampf(1.4 - float(preset.get("sun_elev", 30.0)) / 50.0, 0.3, 1.2)
		env.fog_aerial_perspective = minf(env.fog_aerial_perspective + 0.05 * haze, 0.5) # kept low: a strong veil reads as washed out
	var low_sun := float(preset.get("sun_elev", 45.0)) < 30.0
	if not night and (haze > 0.0 or mist > 0.0) and low_sun and w.kind != Weather.Kind.STORM \
			and w.kind != Weather.Kind.SNOW and w.kind != Weather.Kind.FOG and not args.has("--nomotes") and MOTES[clampi(Game.quality, 0, 3)] > 0:
		a._make_motes(sun_col, sun_dir, maxf(haze, mist * 0.6))
	if w.kind != Weather.Kind.SNOW and not args.has("--nodebris") and DEBRIS[clampi(Game.quality, 0, 3)] > 0:
		a._make_debris()
	for arg in args:
		if arg.begins_with("--gust="): # debug: hold the debris at this gust level
			a._dbg_gust = arg.trim_prefix("--gust=").to_float()
	a._windsocks(parent.get("curve"), road_width, terrain)
	# Dust devils now and then over the fields on dry, sunny days.
	if haze >= 0.5 and (w.kind == Weather.Kind.CLEAR or w.kind == Weather.Kind.GOLDEN) and w.cycle == null \
			and Game.quality >= 1 and not args.has("--nodevil"):
		a._terrain = terrain
		a._make_devil(sun_col)
		if args.has("--devil"): # debug: one right away
			a._devil_wait = 0.5


func _mist_plane(terrain, y: float, strength: float, col: Color, sun_col: Color, sun_dir: Vector3, seed_v: float) -> void:
	var size: float = terrain.cell * (Terrain.N - 1)
	var centre: Vector2 = terrain.origin + Vector2(size, size) * 0.5
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size) * 1.6
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/mist.gdshader")
	m.set_shader_parameter("noise_tex", _noise())
	m.set_shader_parameter("mist_color", col)
	m.set_shader_parameter("sun_color", sun_col)
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("seed", seed_v)
	m.render_priority = -1
	var mi := MeshInstance3D.new()
	mi.name = "Mist"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(centre.x, y, centre.y)
	add_child(mi)


func _make_motes(sun_col: Color, sun_dir: Vector3, amount: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = MOTES[clampi(Game.quality, 0, 3)]
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 20, 60))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 4, 18)
	pm.direction = Vector3(1, 0.1, 0.3)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.35
	pm.gravity = Vector3(0.05, -0.01, 0.02)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var g := Gradient.new() # fade in and out over the life
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.8, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/dust_motes.gdshader")
	m.set_shader_parameter("sun_color", sun_col)
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("strength", clampf(amount, 0.0, 1.0))
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	_motes = p


func _process(dt: float) -> void:
	if _motes == null and _debris == null and _devil == null:
		set_process(false)
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _motes:
		_motes.global_position = cam.global_position - cam.global_basis.z * 12.0
	if _devil:
		_update_devil(cam, dt)
	if _debris:
		# The road surface under the camera (a ray now and then).
		_ray_t -= dt
		if _ray_t <= 0.0:
			_ray_t = 0.25
			var q := PhysicsRayQueryParameters3D.create(cam.global_position + Vector3.UP, cam.global_position + Vector3.DOWN * 30.0)
			q.collision_mask = 1
			var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
			if not hit.is_empty() and not (hit.collider is RigidBody3D):
				_ground_y = (hit.position as Vector3).y
			elif not hit.is_empty():
				_ground_y = (hit.position as Vector3).y - 0.6
		var ahead := -cam.global_basis.z
		ahead.y = 0.0
		var p := cam.global_position + ahead.normalized() * 10.0
		_debris.global_position = Vector3(p.x, _ground_y + 0.3, p.z)
		var wx := Weather.current()
		var wind := wx.wind if wx else 0.3
		var g := gust(Vector2(p.x, p.z), wind, Time.get_ticks_msec() / 1000.0)
		if _dbg_gust >= 0.0:
			g = _dbg_gust
		var dry := 1.0
		if wx:
			dry = (1.0 - smoothstep(0.05, 0.3, wx.rain)) * (1.0 - smoothstep(0.3, 0.7, wx.wetness)) * (1.0 - smoothstep(0.05, 0.3, wx.snowfall))
		var want := clampf(g * clampf(wind * 2.5, 0.0, 1.0) * dry, 0.0, 1.0)
		_debris.amount_ratio = want
		_debris.emitting = want > 0.03
		var pm := _debris.process_material as ParticleProcessMaterial
		var v := 3.0 + 9.0 * wind
		pm.initial_velocity_min = v * 0.6
		pm.initial_velocity_max = v * 1.2


func _make_devil(sun_col: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var u2 := Vector2(float(i) / 30.0, rng.randf())
		for k in [0, 1, 2, 0, 2, 3]:
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][k] as Vector2
			st.set_uv(uv)
			st.set_uv2(u2)
			st.add_vertex(Vector3.ZERO)
	_devil = MeshInstance3D.new()
	_devil.name = "DustDevil"
	_devil.mesh = st.commit()
	_devil.custom_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 22, 16))
	_devil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_devil_mat = ShaderMaterial.new()
	_devil_mat.shader = load("res://shaders/dust_devil.gdshader")
	_devil_mat.set_shader_parameter("sun_color", sun_col)
	_devil.material_override = _devil_mat
	_devil.visible = false
	add_child(_devil)
	_devil_wait = randf_range(20.0, 50.0)


func _update_devil(cam: Camera3D, dt: float) -> void:
	if _devil_t < 0.0:
		_devil_wait -= dt
		if _devil_wait > 0.0:
			return
		# Out in the open, 60-150 m off to one side of where we're looking.
		var ahead := -cam.global_basis.z
		ahead.y = 0.0
		ahead = ahead.normalized().rotated(Vector3.UP, deg_to_rad(randf_range(25.0, 50.0) * (1.0 if randf() < 0.5 else -1.0)))
		var p := cam.global_position + ahead * randf_range(60.0, 150.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 200.0, p + Vector3.DOWN * 300.0)
		var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or not (hit.collider is StaticBody3D):
			_devil_wait = 3.0
			return
		_devil.global_position = hit.position
		_devil_t = 0.0
		_devil.visible = true
	_devil_t += dt
	var dur := 11.0
	var life := smoothstep(0.0, 2.5, _devil_t) * (1.0 - smoothstep(dur - 3.0, dur, _devil_t))
	_devil_mat.set_shader_parameter("life", life)
	_devil.global_position += Vector3(WX_DIR.x, 0, WX_DIR.y) * dt * 2.5
	if _terrain:
		_devil.global_position.y = _terrain.height_at(_devil.global_position.x, _devil.global_position.z)
	if _devil_t > dur:
		_devil_t = -1.0
		_devil.visible = false
		_devil_wait = randf_range(35.0, 80.0)


func _make_debris() -> void:
	var p := GPUParticles3D.new()
	p.name = "RoadDebris"
	p.amount = DEBRIS[clampi(Game.quality, 0, 3)]
	p.lifetime = 3.5
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 15, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.2, 14)
	pm.direction = Vector3(WX_DIR.x, 0.12, WX_DIR.y)
	pm.spread = 18.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -0.45, 0) # light bits: they skip and hover, not fall
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	# Colour (alpha = shape): browns and dry greens are leaves, pale = paper.
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.45, 0.65, 0.85])
	g.colors = PackedColorArray([Color(0.32, 0.14, 0.04, 0.2), Color(0.5, 0.24, 0.05, 0.2), Color(0.5, 0.38, 0.08, 0.2),
		Color(0.28, 0.26, 0.1, 0.2), Color(0.75, 0.74, 0.7, 0.9)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/road_debris.gdshader")
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	_debris = p


## A few windsocks outside the tightest corners (where the line slows most).
func _windsocks(curve, road_width: float, terrain) -> void:
	if not (curve is Curve3D):
		return
	var c: Curve3D = curve
	var length := c.get_baked_length()
	var cand: Array = [] # [tightness, offset, centre, outward]
	var step := 10.0
	var s := 0.0
	while s < length:
		var a := c.sample_baked(fposmod(s - 15.0, length))
		var m := c.sample_baked(s)
		var b := c.sample_baked(fposmod(s + 15.0, length))
		var d1 := Vector2(m.x - a.x, m.z - a.z).normalized()
		var d2 := Vector2(b.x - m.x, b.z - m.z).normalized()
		var turn := d1.angle_to(d2)
		var right := Vector2(-d1.y, d1.x)
		var outward := -right * signf(turn) # outside of the bend
		cand.append([absf(turn), s, m, outward])
		s += step
	cand.sort_custom(func(x, y): return x[0] > y[0])
	var placed: Array[Vector3] = []
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/windsock.gdshader")
	var wx := Weather.current()
	mat.set_shader_parameter("wind", wx.wind if wx else 0.3)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.55, 0.56, 0.57)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.45
	for e in cand:
		if placed.size() >= 3:
			break
		var o: Vector2 = e[3]
		var m: Vector3 = e[2]
		var base := m + Vector3(o.x, 0, o.y) * (road_width * 0.5 + 13.0)
		var far_ok := true
		for q in placed:
			if q.distance_to(base) < 150.0:
				far_ok = false
		if not far_ok:
			continue
		if terrain:
			base.y = terrain.height_at(base.x, base.z)
		placed.append(base)
		var pole := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.04
		cy.bottom_radius = 0.06
		cy.height = 5.5
		cy.radial_segments = 8
		pole.mesh = cy
		pole.material_override = pole_mat
		pole.position = base + Vector3.UP * 2.75
		add_child(pole)
		var sock := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.28
		sm.bottom_radius = 0.1
		sm.height = 1.6
		sm.radial_segments = 12
		sm.rings = 8
		sm.cap_top = false
		sm.cap_bottom = false
		sock.mesh = sm
		sock.material_override = mat
		sock.position = base + Vector3.UP * 5.35
		sock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sock.extra_cull_margin = 2.0
		add_child(sock)


static var _noise_tex: NoiseTexture2D
static func _noise() -> NoiseTexture2D:
	if _noise_tex == null:
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.012
		n.fractal_octaves = 3
		var t := NoiseTexture2D.new()
		t.noise = n
		t.width = 256
		t.height = 256
		t.seamless = true
		t.generate_mipmaps = true
		_noise_tex = t
	return _noise_tex
