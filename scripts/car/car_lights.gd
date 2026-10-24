class_name CarLights
extends Node3D
## A car's lamps when they are on (storms, snow, night): lit headlamp lenses,
## one SpotLight aimed a few degrees down (a low beam; the car ahead and the
## road ahead light up), and at night a faint beam cone that shows in rain, snow and
## haze plus a red glow on the tarmac behind from the tail lamps.
## Only the local player's beam casts shadows (enable_shadows()).

const BEAM_COLOR := Color(1.0, 0.94, 0.82) # halogen
const TAIL_COLOR := Color(1.0, 0.06, 0.02)

static var _cone_mat: ShaderMaterial
static var _cone_mesh: ArrayMesh

var beam: SpotLight3D
var tail: OmniLight3D
var _night := false
var _lens: BaseMaterial3D


## Adds lights to `car` for a body mesh instance `mi` built from CarModel data
## `d` (or {} for the procedural body). `front_z` is the nose, `y` lamp height.
static func build(car: Node3D, mi: MeshInstance3D, d: Dictionary, front_z: float, rear_z: float, y: float, night: bool) -> CarLights:
	var l := CarLights.new()
	l.name = "Lights"
	l._night = night
	car.add_child(l)
	var heads: Array = [Vector3(-0.55, y, front_z), Vector3(0.55, y, front_z)]
	var tails: Array = [Vector3(0, y, rear_z)]
	if mi and d.has("body"):
		var lamps: int = d.get("lights_surface", -1)
		if lamps >= 0 and d.surface_mats[lamps] is BaseMaterial3D:
			var lit: BaseMaterial3D = d.surface_mats[lamps].duplicate()
			lit.emission_enabled = true
			lit.emission = Color(1.0, 0.95, 0.82)
			lit.emission_energy_multiplier = 5.0 if night else 2.5
			mi.set_surface_override_material(lamps, lit)
			l._lens = lit
			var hp := _lamp_centres(d, lamps, true)
			if not hp.is_empty():
				heads = hp.map(func(p: Vector3) -> Vector3: return mi.transform * p)
		var brake: int = d.get("brake_surface", -1)
		if brake >= 0:
			var tp := _lamp_centres(d, brake, false)
			if not tp.is_empty():
				tails = [mi.transform * ((tp[0] + tp[-1]) * 0.5)]
	var mid: Vector3 = (heads[0] + heads[-1]) * 0.5
	l.beam = SpotLight3D.new()
	l.beam.name = "HeadBeam"
	l.beam.position = mid + Vector3(0, 0, -0.1)
	l.beam.light_color = BEAM_COLOR
	l.beam.shadow_enabled = false
	if night:
		# Aimed a few degrees down so the brightest part lands 15-40 m ahead and
		# little light goes up into the trees (a projector pattern would give a
		# sharp cut-off, but Metal renders projected spots black here).
		l.beam.rotation_degrees.x = -4.5
		# Just ahead of the nose: from inside the lamp the driver's shadowed beam
		# would be blocked by its own lens and bumper.
		l.beam.position.z = minf(mid.z - 0.35, front_z - 0.1)
		l.beam.spot_range = 70.0 # past this the beam is too dim to see; saves light overdraw
		l.beam.distance_fade_enabled = true # cars far ahead / behind the camera drop out
		l.beam.distance_fade_begin = 110.0
		l.beam.distance_fade_length = 30.0
		l.beam.spot_angle = 38.0
		l.beam.spot_attenuation = 0.85
		l.beam.spot_angle_attenuation = 1.4
		l.beam.light_energy = 55.0
		l.beam.light_specular = 0.7
		l.beam.shadow_bias = 0.06
		l.beam.shadow_normal_bias = 1.5
	else:
		l.beam.position = Vector3(0, mid.y, mid.z - 0.1)
		l.beam.rotation_degrees.x = -6.0
		l.beam.spot_range = 45.0
		l.beam.spot_angle = 32.0
		l.beam.light_energy = 4.0
	l.add_child(l.beam)
	# Beam shafts read the depth buffer (a copy per frame) and only really show
	# in rain and snow, so they're a High+ extra.
	var shafts := night and Game.quality >= 2 and (Car.weather_road_grip < 0.9 or Car.weather_off_grip < 0.6)
	if shafts:
		for h: Vector3 in heads:
			var cone := MeshInstance3D.new()
			cone.mesh = _cone()
			cone.material_override = _cone_material()
			cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cone.position = h + Vector3(0, 0, -0.05)
			cone.rotation_degrees.x = -1.5
			l.add_child(cone)
	if night:
		l.tail = OmniLight3D.new()
		l.tail.position = tails[0] + Vector3(0, -0.05, 0.35)
		l.tail.light_color = TAIL_COLOR
		l.tail.omni_range = 3.2
		l.tail.omni_attenuation = 1.4
		l.tail.light_energy = 0.25
		l.tail.light_specular = 0.2
		l.tail.shadow_enabled = false
		l.add_child(l.tail)
	return l


## Beam shadows (the local driver only: the car in front throws a shadow up the road).
func enable_shadows() -> void:
	if beam and _night:
		beam.shadow_enabled = true


## Lamps switched on/off during the race (changeable weather: Car.lamps_on).
func set_on(on: bool) -> void:
	visible = on
	if _lens: # energy, not emission_enabled: toggling that would compile a new shader
		if not _lens.has_meta("on_energy"):
			_lens.set_meta("on_energy", _lens.emission_energy_multiplier)
		_lens.emission_energy_multiplier = float(_lens.get_meta("on_energy")) if on else 0.0


## The local driver's road pool. A lamp 0.7 m up meets the tarmac at a few
## degrees, so a real light puts almost nothing on the road (only things that
## stand in the beam light up). So the pool is faked: an emissive decal laid
## on the road ahead of the nose, widening and fading down the road like a low
## beam (brightest a few metres out, a soft kick on the verge side). One decal
## for the whole field; decals are clustered like lights and cheap.
func add_road_fill() -> void:
	if not _night or beam == null:
		return
	var d := Decal.new()
	d.name = "RoadPool"
	var length := 34.0
	d.size = Vector3(13.0, 3.0, length)
	d.position = Vector3(0.0, beam.position.y - 1.0, beam.position.z - length * 0.5 + 0.8)
	# An imported texture: runtime ImageTextures never reach the decal atlas on Metal
	# (projected / decal textures render black). Made by the old _pool_texture() maths.
	d.texture_emission = load("res://assets/textures/fx/headlight_pool.png")
	d.emission_energy = 0.5
	d.modulate = BEAM_COLOR
	d.albedo_mix = 0.0
	d.normal_fade = 0.5 # road and verges, not the walls and cars standing in it
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	add_child(d)


func set_braking(on: bool) -> void:
	if tail:
		tail.light_energy = 0.9 if on else 0.25


## Centres of the left and right lamps of a body surface (front or rear half),
## in body-mesh space. Cached in the model data.
static func _lamp_centres(d: Dictionary, surface: int, front: bool) -> Array:
	var key := "lamp_centres_%d" % surface
	if d.has(key):
		return d[key]
	var verts: PackedVector3Array = (d.body as ArrayMesh).surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	var sums := [Vector3.ZERO, Vector3.ZERO]
	var counts := [0, 0]
	var zc: float = (d.body_aabb as AABB).get_center().z
	for v in verts:
		if (v.z < zc) != front:
			continue
		var side := 0 if v.x < 0.0 else 1
		sums[side] += v
		counts[side] += 1
	var out := []
	for s in 2:
		if counts[s] > 0:
			out.append(sums[s] / counts[s])
	d[key] = out
	return out


static func _cone() -> ArrayMesh:
	if _cone_mesh:
		return _cone_mesh
	var c := CylinderMesh.new()
	c.top_radius = 0.12
	c.bottom_radius = 4.2
	c.height = 24.0
	c.radial_segments = 16
	c.rings = 4
	c.cap_top = false
	c.cap_bottom = false
	var arr := c.get_mesh_arrays()
	# Lay it along -Z with the narrow end at the origin, a little flattened.
	var xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 0.55, 1.0)), Vector3(0, 0, -12.0))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv := PackedVector2Array()
	uv.resize(v.size())
	for i in v.size():
		uv[i] = Vector2(0.0, (v[i].y + 12.0) / 24.0) # 1 at the lamp .. 0 at the far end
		v[i] = xf * v[i]
		nr[i] = (xf.basis * nr[i]).normalized()
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nr
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TANGENT] = null
	_cone_mesh = ArrayMesh.new()
	_cone_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return _cone_mesh


## Shared additive cone material; strength follows the weather (rain and
## snow scatter far more than a clear night).
static func _cone_material() -> ShaderMaterial:
	if _cone_mat == null:
		_cone_mat = ShaderMaterial.new()
		_cone_mat.shader = load("res://shaders/beam_cone.gdshader")
	var s := 0.03
	if Car.weather_off_grip < 0.6:
		s = 0.09 # snow
	elif Car.weather_road_grip < 0.9:
		s = 0.07 # rain
	_cone_mat.set_shader_parameter("strength", s)
	_cone_mat.set_shader_parameter("color", Vector3(BEAM_COLOR.r, BEAM_COLOR.g, BEAM_COLOR.b))
	return _cone_mat
