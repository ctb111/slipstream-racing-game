class_name CarDirt
extends Node
## Dirt, mud, dust, slush, snow and water building up on its parent Car
## during a race. Bots, the player and remote puppets all get one.
##
## Materials: once the car has picked up something, its opaque exterior
## surfaces and wheels switch to shaders/car_dirt.gdshaderinc (a variant per
## material: double sided, clearcoat, normal map, AO) and its windows to
## shaders/car_glass*.gdshader. A clean car keeps its stock materials and
## costs nothing. Both mirror the StandardMaterial3D they replace, so the
## switch doesn't show, and they place the dirt in mesh space (masks from
## the car's shape plus a baked tileable noise), so every model gets it the
## same way whatever its UVs. Converted materials are shared by every car of
## a model. Paint is the exception because each car has its own colour. The
## per-car amounts go in as instance uniforms: 3 x vec4 per mesh, pushed at
## most 10x a second and only when they change.
##
## Accumulation (simulated from what the car is doing, the same way on every
## machine, so nothing extra goes over the network):
##   off track (grass / gravel), faster when sliding or spinning the wheels:
##     dry -> dust, wet -> mud, snow -> packed slush
##   on the road: a slow dust film (dry), spray grime (wet), slush (snow)
##   close behind another car in the wet: its spray adds grime to the nose
##   rain wets the car, slowly washes dust off and leaves it in streaks
##   snow on the roof / bonnet from standing in snowfall blows off at speed
## Debug: `--dirt=<0..1>` forces a fixed amount (kind from the weather, or
## `--dirt_kind=dust|mud|snow|wet`); `--dirt=off` keeps the stock materials;
## `--dirt_lod=light|detail` pins the material variant.

const BODY_INCLUDE := "res://shaders/car_dirt.gdshaderinc"
const GLASS_SHADER := preload("res://shaders/car_glass.gdshader")
const GLASS_SHADER_CULL := preload("res://shaders/car_glass_cull.gdshader")
const NOISE := preload("res://assets/textures/car_dirt/dirt_noise.png")
const TICK := 0.1
const ACTIVATE := 0.03 ## switch to the dirt materials once any amount passes this

## Materials that are not windows by name but are (model id -> material names).
const GLASS_EXTRA := {"mazda_rx7_fc": ["Material.002"]}
## Surfaces inside the car: never dirtied (the cockpit view sees them).
const INTERIOR_WORDS := ["interior", "cockpit", "seat", "dash", "pedal", "gauge", "display", "strelki",
	"tappetini", "skin", "carpet", "steer", "doorshut", "mechanics", "sheft"]

static var _all: Array[CarDirt] = []
static var _mat_cache := {} ## "<model>|<surface key>|<mode>" -> ShaderMaterial
static var _shaders := {} ## variant flags -> Shader (see _body_shader)
static var _glass_bounds := {} ## model id -> {surface index -> [glass AABB, windscreen AABB]}
static var _forced := -2.0 ## < -1: args not read yet; < 0: not forced
static var _forced_kind := ""
static var _off := false ## `--dirt=off`: keep the stock materials (A/B perf checks)
static var _no_glass := false ## debug (tests): leave the windows' stock materials
static var _log := false ## `--dirt_log`: print every car's amounts every 5 s

var car: Car
## Current amounts, 0..1.
var dust := 0.0
var mud := 0.0
var slush := 0.0
var wet := 0.0
var snow_top := 0.0
var grime := 0.0
var wash := 0.0

var _seed := 0.0
var _meshes: Array[GeometryInstance3D] = []
var _swaps: Array = [] ## [MeshInstance3D, surface, dirt material, stock material]: see _apply_lod()
var _active := false ## picked up enough dirt to need the dirt materials
var _lod := 0 ## materials in use: 0 stock, 1 light (smooth films), 2 detailed
static var _force_lod := 0 ## `--dirt_lod=light|detail`: always that variant (tests)
var _t := 0.0
var _sent := PackedFloat32Array()
var _log_t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	car = get_parent() as Car
	_read_args()
	if _off:
		set_physics_process(false)
		return
	_seed = fmod(float(car.get_instance_id() % 9973) * 0.6180339, 1.0)
	_t = _seed * TICK # stagger the cars' ticks
	_convert_materials()
	var w := _weather()
	# Cars sat on the grid in the weather before the start.
	wet = w.rain * 0.8
	snow_top = w.snowing * 0.85
	dust = 0.02 if w.wet < 0.3 else 0.0
	_ray.collision_mask = 1
	_ray.exclude = [car.get_rid()]
	_all.append(self)
	_push(true)


func _exit_tree() -> void:
	_all.erase(self)


# ---------------------------------------------------------------- materials

func _convert_materials() -> void:
	if not CarModel.available(car.model_id):
		return
	var d := CarModel.data(car.model_id)
	var body := car.get_node_or_null("Body/Model") as MeshInstance3D
	if body:
		for i in body.mesh.get_surface_count():
			var src := body.get_surface_override_material(i)
			var key: String = d.surface_keys[i]
			var m := _convert(src, key, i, d)
			if m:
				_swaps.append([body, i, m, src])
		_meshes.append(body)
	var spec := CarCatalog.get_car(car.model_id)
	for w in car.wheels:
		for mi in w.spinner.get_children():
			if not mi is MeshInstance3D:
				continue
			for k in (mi as MeshInstance3D).mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(k)
				if not src is BaseMaterial3D:
					continue
				var tyre: bool = src.resource_name == spec.tire_mat
				var ck := "%s|W%s|%d" % [car.model_id, src.resource_name, 1 if tyre else 2]
				if not _mat_cache.has(ck):
					var sm := _from_standard(src, _body_shader(src))
					sm.set_shader_parameter("dirt_mode", 1 if tyre else 2)
					sm.set_shader_parameter("wheel_r", d.wheel_radius)
					_mat_cache[ck] = _add_light(sm, src)
				_swaps.append([mi, k, _mat_cache[ck], src])
			_meshes.append(mi)


## The dirt version of one body surface, or null to leave it as it is.
func _convert(src: Material, key: String, index: int, d: Dictionary) -> Material:
	if not src is BaseMaterial3D:
		return null
	var m := src as BaseMaterial3D
	if index == d.brake_surface or index == d.get("lights_surface", -1) or m.emission_enabled:
		return null
	var lname := key.to_lower()
	for word in INTERIOR_WORDS:
		if word in lname:
			return null
	var is_glass := _is_glass_key(car.model_id, key)
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return _glass(m, key, index, d) if is_glass and not _no_glass else null
	if is_glass:
		return null # opaque "glass" (tinted strips, mirrors): leave alone
	var paint: bool = index == d.paint_surface
	var ck := "%s|%s|0" % [car.model_id, key]
	if not paint and _mat_cache.has(ck):
		return _mat_cache[ck]
	var sm := _from_standard(m, _body_shader(m))
	_set_shape(sm, d)
	_add_light(sm, m)
	if not paint:
		_mat_cache[ck] = sm
	return sm


func _glass(m: BaseMaterial3D, key: String, index: int, d: Dictionary) -> Material:
	var ck := "%s|%s|glass" % [car.model_id, key]
	if _mat_cache.has(ck):
		return _mat_cache[ck]
	var sm := ShaderMaterial.new()
	sm.shader = GLASS_SHADER if m.cull_mode == BaseMaterial3D.CULL_DISABLED else GLASS_SHADER_CULL
	sm.render_priority = m.render_priority
	sm.set_shader_parameter("albedo", m.albedo_color)
	sm.set_shader_parameter("texture_albedo", m.albedo_texture)
	sm.set_shader_parameter("metallic", m.metallic)
	sm.set_shader_parameter("roughness", m.roughness)
	_set_channel_tex(sm, m)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.set_shader_parameter("specular", m.metallic_specular)
	_set_shape(sm, d)
	var b := _glass_box(index, d)
	sm.set_shader_parameter("glass_min", b[0].position)
	sm.set_shader_parameter("glass_max", b[0].end)
	sm.set_shader_parameter("ws_min", b[1].position)
	sm.set_shader_parameter("ws_max", b[1].end)
	_mat_cache[ck] = sm
	return sm


## A shader variant per kind of material (double sided, clearcoat, normal map,
## AO), so each only pays for what its StandardMaterial3D used: a normal map
## costs tangent varyings, clearcoat a second specular lobe.
static func _body_shader(m: BaseMaterial3D, light := false) -> Shader:
	var flags := PackedStringArray()
	if light:
		flags.append("DIRT_LIGHT")
	if m.clearcoat_enabled:
		flags.append("DIRT_CLEARCOAT")
	if m.normal_enabled and m.normal_texture:
		flags.append("DIRT_NORMALMAP")
	if m.ao_enabled and m.ao_texture:
		flags.append("DIRT_AO")
	var cull := "cull_disabled" if m.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_back"
	var key := cull + "|" + ",".join(flags)
	if not _shaders.has(key):
		var code := "shader_type spatial;\nrender_mode blend_mix, depth_draw_opaque, %s, diffuse_burley, specular_schlick_ggx;\n" % cull
		for f in flags:
			code += "#define %s\n" % f
		code += "#include \"%s\"\n" % BODY_INCLUDE
		var sh := Shader.new()
		sh.code = code
		_shaders[key] = sh
	return _shaders[key]


## Once dirty, a car stays on the dirt materials for the rest of the race.
func _activate() -> void:
	_active = true
	_update_lod()


## Detailed materials near the camera, light ones further away (with some
## hysteresis so a car on the edge doesn't flip every tick).
func _update_lod() -> void:
	if not _active or _force_lod > 2: # 3: hold (tests set the variant themselves)
		return
	var want := 1
	if _force_lod > 0:
		want = _force_lod
	else:
		var cam := car.get_viewport().get_camera_3d()
		if cam:
			var d := cam.global_position.distance_to(car.global_position)
			want = 2 if d < (18.0 if _lod == 2 else 14.0) else 1
	if want != _lod:
		_apply_lod(want)


## 0: the stock materials, 1: light dirt, 2: detailed dirt.
func _apply_lod(lod: int) -> void:
	_lod = lod
	for s in _swaps:
		if is_instance_valid(s[0]):
			var m: Material = s[3] if lod == 0 else (s[2].get_meta("light", s[2]) if lod == 1 else s[2])
			(s[0] as MeshInstance3D).set_surface_override_material(s[1], m)


func _from_standard(m: BaseMaterial3D, shader: Shader) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = shader
	sm.render_priority = m.render_priority
	sm.set_shader_parameter("albedo", m.albedo_color)
	sm.set_shader_parameter("texture_albedo", m.albedo_texture)
	sm.set_shader_parameter("use_albedo_tex", m.albedo_texture != null)
	sm.set_shader_parameter("metallic", m.metallic)
	sm.set_shader_parameter("roughness", m.roughness)
	_set_channel_tex(sm, m)
	if m.normal_enabled and m.normal_texture:
		sm.set_shader_parameter("normal_enabled", true)
		sm.set_shader_parameter("texture_normal", m.normal_texture)
		sm.set_shader_parameter("normal_scale", m.normal_scale)
	if m.ao_enabled and m.ao_texture:
		sm.set_shader_parameter("ao_enabled", true)
		sm.set_shader_parameter("texture_ao", m.ao_texture)
		sm.set_shader_parameter("ao_channel", _channel(m.ao_texture_channel))
		sm.set_shader_parameter("ao_light_affect", m.ao_light_affect)
	if m.clearcoat_enabled:
		sm.set_shader_parameter("clearcoat", m.clearcoat)
		sm.set_shader_parameter("clearcoat_roughness", m.clearcoat_roughness)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.set_shader_parameter("specular", m.metallic_specular)
	sm.set_shader_parameter("dirt_noise", NOISE)
	return sm


## The light variant of a detailed body material (same parameters), kept as its meta.
static func _add_light(sm: ShaderMaterial, m: BaseMaterial3D) -> ShaderMaterial:
	var lm := sm.duplicate() as ShaderMaterial
	lm.shader = _body_shader(m, true)
	sm.set_meta("light", lm)
	return sm


static func _set_channel_tex(sm: ShaderMaterial, m: BaseMaterial3D) -> void:
	if m.metallic_texture:
		sm.set_shader_parameter("texture_metallic", m.metallic_texture)
		sm.set_shader_parameter("metallic_channel", _channel(m.metallic_texture_channel))
		sm.set_shader_parameter("use_metallic_tex", true)
	if m.roughness_texture:
		sm.set_shader_parameter("texture_roughness", m.roughness_texture)
		sm.set_shader_parameter("roughness_channel", _channel(m.roughness_texture_channel))
		sm.set_shader_parameter("use_roughness_tex", true)
	sm.set_shader_parameter("dirt_noise", NOISE)


static func _channel(c: int) -> Vector4:
	var v := Vector4.ZERO
	v[clampi(c, 0, 3)] = 1.0 # BaseMaterial3D.TEXTURE_CHANNEL_RED.. ALPHA (GRAYSCALE reads red)
	return v


## Body shape in mesh space: ground, bounds, hubs (the shader's masks hang off these).
static func _set_shape(sm: ShaderMaterial, d: Dictionary) -> void:
	var fz := 0.0
	var fy := 0.0
	var rz := 0.0
	var ry := 0.0
	var nf := 0
	var nr := 0
	for w in d.wheels:
		if w.front:
			fz += w.centre.z
			fy += w.centre.y
			nf += 1
		else:
			rz += w.centre.z
			ry += w.centre.y
			nr += 1
	var box: AABB = d.body_aabb
	var hub_f := Vector2(fz / maxi(nf, 1), fy / maxi(nf, 1))
	var hub_r := Vector2(rz / maxi(nr, 1), ry / maxi(nr, 1))
	if nf == 0:
		hub_f = Vector2(box.position.z + box.size.z * 0.2, box.position.y + 0.3)
	if nr == 0:
		hub_r = Vector2(box.end.z - box.size.z * 0.2, box.position.y + 0.3)
	var r: float = d.wheel_radius if d.wheel_radius > 0.05 else 0.31
	sm.set_shader_parameter("car_ground", (hub_f.y + hub_r.y) * 0.5 - r)
	sm.set_shader_parameter("car_min", box.position)
	sm.set_shader_parameter("car_max", box.end)
	sm.set_shader_parameter("hub_front", hub_f)
	sm.set_shader_parameter("hub_rear", hub_r)
	sm.set_shader_parameter("wheel_r", r)
	var cab := _cabin(d)
	sm.set_shader_parameter("cabin_min", cab.position)
	sm.set_shader_parameter("cabin_max", cab.end)


static func _is_glass_key(model_id: String, key: String) -> bool:
	var lname := key.to_lower()
	return key in GLASS_EXTRA.get(model_id, []) or \
		(("glass" in lname or "window" in lname) and not ("orange" in lname or "light" in lname))


static var _cabins := {} ## model id -> AABB of the window glass (the cabin), mesh space

## The cabin: the box spanned by the windows (lamp covers low on the body are
## left out). Anything inside it below the roof is interior and stays clean.
static func _cabin(d: Dictionary) -> AABB:
	var id: String = d.model_id
	if _cabins.has(id):
		return _cabins[id]
	var body_box: AABB = d.body_aabb
	var mid_y := body_box.position.y + body_box.size.y * 0.5
	var cab := AABB()
	var have := false
	for i in d.surface_mats.size():
		var m = d.surface_mats[i]
		if not (m is BaseMaterial3D and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			continue
		if not _is_glass_key(id, d.surface_keys[i]):
			continue
		var b: AABB = _glass_box(i, d)[0]
		if b.get_center().y < mid_y:
			continue
		cab = b if not have else cab.merge(b)
		have = true
	if not have:
		cab = AABB(Vector3(0, 1e4, 0), Vector3.ZERO) # no cabin found: nothing counts as interior
	_cabins[id] = cab
	return cab


## [bounds of this glass surface, bounds of its forward-facing part (windscreen)].
static func _glass_box(index: int, d: Dictionary) -> Array:
	var id: String = d.model_id
	if not _glass_bounds.has(id):
		_glass_bounds[id] = {}
	var cache: Dictionary = _glass_bounds[id]
	if cache.has(index):
		return cache[index]
	var arr: Array = (d.body as ArrayMesh).surface_get_arrays(index)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var all := AABB(verts[0], Vector3.ZERO)
	var ws := AABB()
	var have_ws := false
	for k in verts.size():
		all = all.expand(verts[k])
		if norms.size() > k and norms[k].z < -0.4 and norms[k].y > 0.1:
			if not have_ws:
				ws = AABB(verts[k], Vector3.ZERO)
				have_ws = true
			ws = ws.expand(verts[k])
	if not have_ws:
		ws = AABB(all.position - Vector3(0, 0, 10), Vector3.ONE * 0.01) # no windscreen here: no wiper arcs
	cache[index] = [all, ws]
	return cache[index]


# ---------------------------------------------------------------- simulation

## Current conditions, 0..1: wet (water on the track), rain / snowing (falling
## now), snow (lying on the ground). Live from Weather.current(), which changes
## mid-race; without a Weather (tests) guessed from the grip multipliers.
static func _weather() -> Dictionary:
	var wx := Weather.current()
	if wx:
		return {wet = wx.wetness, rain = wx.rain, snowing = wx.snowfall, snow = wx.snow_cover}
	var snowy := Car.weather_off_grip < 0.6
	var wet_road := Car.weather_road_grip < 0.95
	return {wet = 1.0 if wet_road else 0.0, rain = 1.0 if wet_road and not snowy else 0.0,
		snowing = 1.0 if snowy else 0.0, snow = 1.0 if snowy else 0.0}


func _physics_process(dt: float) -> void:
	_t += dt
	if _t < TICK:
		return
	var step := _t
	_t = 0.0
	_update_lod()
	if _forced >= 0.0:
		_apply_forced()
	else:
		_simulate(step)
	_push(false)
	if _log:
		_log_t += step
		if _log_t >= 5.0:
			_log_t = 0.0
			var w := _weather()
			print("dirt %s %s: dust %.2f mud %.2f slush %.2f wet %.2f snow %.2f grime %.2f wash %.2f | rain %.2f snowing %.2f road %.2f lod %d" % [
				car.name, car.model_id, dust, mud, slush, wet, snow_top, grime, wash, w.rain, w.snowing, w.wet, _lod])


func _simulate(dt: float) -> void:
	var w := _weather()
	var spd := absf(car.speed)
	var sf := clampf(spd / 25.0, 0.0, 1.3) # how hard the tyres throw things up
	# How much of the car is off the road, and how violently.
	var off := 0.0
	var slide := 0.0
	if car.remote:
		off = _remote_offroad()
		slide = 0.6 if car.drifting else 0.0
	else:
		for wh in car.wheels:
			if wh.grounded:
				if wh.surface_grip < 0.9:
					off += 1.0
				slide = maxf(slide, wh.slip)
		off = off / 4.0
	var churn := off * sf * (1.0 + clampf(slide, 0.0, 1.0) * 1.5)
	var road := (1.0 - off) * sf

	var snowy: float = maxf(w.snow, w.snowing)
	var wet_road: float = maxf(w.wet, w.rain)
	var dry := clampf(1.0 - wet_road - snowy, 0.0, 1.0)
	# Off-track: what the ground is made of today.
	var new_dust := (churn * 0.09 + road * 0.0012) * dry * dt
	wash = maxf(0.0, wash - new_dust * 1.5) # fresh dust covers the old rain streaks
	dust += churn * 0.09 * dry * dt
	mud += churn * (0.11 * wet_road * (1.0 - snowy) + 0.03 * snowy) * dt
	slush += churn * 0.10 * snowy * dt
	# On the road: a slow film.
	dust += road * 0.0012 * dry * dt
	grime += road * 0.0025 * wet_road * dt
	slush += road * 0.0025 * snowy * dt
	grime += _spray_from_ahead() * wet_road * 0.03 * dt

	# Water: rain soaks the car quickly, it dries slowly (faster in the wind).
	var rain: float = w.rain
	var target := maxf(rain, w.wet * 0.35)
	if target > wet:
		wet = move_toward(wet, target, dt / 12.0)
	else:
		wet = move_toward(wet, target, dt * (1.0 + sf) / 150.0)
	# Rain washes dust into streaks (and a little mud / slush away).
	dust -= rain * 0.004 * dt
	mud -= rain * 0.0015 * dt
	slush -= rain * 0.002 * dt
	wash = move_toward(wash, 1.0 if rain > 0.1 else wash, rain * 0.02 * dt)
	# Snow lying on top: builds while standing in snowfall, blows off at speed.
	snow_top += w.snowing * 0.015 * clampf(1.0 - spd / 12.0, 0.0, 1.0) * dt
	snow_top -= clampf((spd - 12.0) / 30.0, 0.0, 1.0) * 0.035 * dt
	snow_top -= rain * 0.01 * dt

	dust = clampf(dust, 0.0, 1.0)
	mud = clampf(mud, 0.0, 1.0)
	slush = clampf(slush, 0.0, 1.0)
	grime = clampf(grime, 0.0, 1.0)
	snow_top = clampf(snow_top, 0.0, 1.0)


## Puppets have no suspension rays of their own: one ray under the rear axle.
func _remote_offroad() -> float:
	if absf(car.speed) < 1.0:
		return 0.0
	var space := car.get_world_3d().direct_space_state
	var from := car.global_transform * Vector3(0, 0.3, car.axle_rear_z)
	_ray.from = from
	_ray.to = from + Vector3.DOWN * 2.0
	var hit := space.intersect_ray(_ray)
	if hit.is_empty() or hit.collider == null:
		return 0.0
	return 1.0 if float(hit.collider.get_meta("grip", 1.0)) < 0.9 else 0.0


## 0..1: how much spray this car is driving through (cars close ahead, going fast).
func _spray_from_ahead() -> float:
	var s := 0.0
	var fwd := -car.global_basis.z
	var right := car.global_basis.x
	for o in _all:
		if o == self or not is_instance_valid(o.car):
			continue
		var rel := o.car.global_position - car.global_position
		var ahead := rel.dot(fwd)
		if ahead < 2.0 or ahead > 30.0 or absf(rel.dot(right)) > 2.5:
			continue
		s = maxf(s, (1.0 - ahead / 30.0) * clampf(absf(o.car.speed) / 30.0, 0.0, 1.0))
	return s


# ---------------------------------------------------------------- output

func _push(force: bool) -> void:
	var w := _weather()
	var v := PackedFloat32Array([dust, mud, slush, wet, snow_top, grime, wash,
		clampf(absf(car.speed) / 50.0, 0.0, 1.0), w.rain, w.snowing])
	if not force and _sent.size() == v.size():
		var changed := false
		for i in v.size():
			if absf(v[i] - _sent[i]) > 0.004:
				changed = true
				break
		if not changed:
			return
	_sent = v
	if not _active and maxf(maxf(maxf(dust, mud), maxf(slush, wet)), maxf(maxf(snow_top, grime), maxf(w.rain, w.snowing))) > ACTIVATE:
		_activate()
	var a := Vector4(dust, mud, slush, wet)
	var b := Vector4(snow_top, grime, wash, _seed)
	var c := Vector4(v[7], w.rain, w.snowing, _seed * 50.0)
	for m in _meshes:
		if is_instance_valid(m):
			m.set_instance_shader_parameter("dirt_a", a)
			m.set_instance_shader_parameter("dirt_b", b)
			m.set_instance_shader_parameter("dirt_c", c)


# ---------------------------------------------------------------- debug

static func _read_args() -> void:
	if _forced > -1.5:
		return
	_forced = -1.0
	for arg in OS.get_cmdline_user_args():
		if arg == "--dirt=off":
			_off = true
		elif arg.begins_with("--dirt_lod="):
			_force_lod = 1 if arg.ends_with("light") else 2
		elif arg == "--dirt_log":
			_log = true
		elif arg.begins_with("--dirt="):
			_forced = clampf(arg.substr(7).to_float(), 0.0, 1.0)
		elif arg.begins_with("--dirt_kind="):
			_forced_kind = arg.substr(12)


func _apply_forced() -> void:
	var w := _weather()
	var k := _forced_kind
	if k == "":
		k = "snow" if maxf(w.snow, w.snowing) > 0.5 else ("mud" if w.wet > 0.5 else "dust")
	var x := _forced
	if k.begins_with("only_"): # debug: a single layer, for profiling
		dust = 0.0; mud = 0.0; slush = 0.0; grime = 0.0; wash = 0.0; snow_top = 0.0; wet = 0.0
		set(k.substr(5), x)
		return
	match k:
		"dust":
			dust = x; mud = x * 0.3; slush = 0.0; grime = 0.0; wash = 0.0; snow_top = 0.0
		"mud":
			dust = x * 0.35; mud = x; grime = x * 0.8; wash = 0.7; slush = 0.0; snow_top = 0.0
		"snow":
			slush = x; snow_top = x * 0.7; grime = x * 0.5; dust = x * 0.2; mud = x * 0.15; wash = 0.0
		"wet":
			dust = x * 0.5; mud = 0.0; grime = x * 0.3; wash = 1.0; slush = 0.0; snow_top = 0.0
	wet = 1.0 if (w.rain > 0.5 or k == "wet") else (0.3 if k == "snow" else 0.0)
