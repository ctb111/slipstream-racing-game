class_name GhostCar
extends Node3D
## Replay of a recorded lap: a translucent, collision-less copy of the car
## built from CarModel data (like the showroom), no physics or audio. Also the
## recorder: samples a car's transform at ~30 Hz into a flat PackedFloat32Array
## of [t, px, py, pz, qx, qy, qz, qw] per sample.

const RATE := 30.0
const STRIDE := 8
const ALPHA := 0.55 ## GeometryInstance3D.transparency (0 = solid)

var samples := PackedFloat32Array()
var _spinners: Array[Node3D] = []
var _wheel_radius := 0.33
var _cursor := 0
var _last_pos := Vector3.ZERO


## Appends one sample to `buf`.
static func record(buf: PackedFloat32Array, t: float, xf: Transform3D) -> void:
	var q := xf.basis.get_rotation_quaternion()
	var p := xf.origin
	buf.append_array(PackedFloat32Array([t, p.x, p.y, p.z, q.x, q.y, q.z, q.w]))


static func duration(buf: PackedFloat32Array) -> float:
	return buf[buf.size() - STRIDE] if buf.size() >= STRIDE else 0.0


## Display body + wheels in the same car space as Car (hubs REST_DROP below the mounts).
func build(model_id: String, paint: Color) -> void:
	top_level = true
	if not CarModel.available(model_id):
		return
	var d := CarModel.data(model_id)
	var hub_y := 0.0
	var fz := 0.0
	var rz := 0.0
	for w in d.wheels:
		hub_y += w.centre.y * 0.25
		if w.front:
			fz += w.centre.z * 0.5
		else:
			rz += w.centre.z * 0.5
	var offset := Vector3(0, -Car.REST_DROP - hub_y, -(fz + rz) * 0.5)
	_wheel_radius = d.wheel_radius
	var body := MeshInstance3D.new()
	body.mesh = d.body
	body.position = offset
	for i in d.surface_mats.size():
		var m: Material = d.surface_mats[i]
		if i == d.paint_surface and m is BaseMaterial3D:
			var p: BaseMaterial3D = m.duplicate()
			p.albedo_color = paint.lightened(0.25)
			p.emission_enabled = true
			p.emission = paint.lightened(0.4)
			p.emission_energy_multiplier = 0.35
			m = p
		body.set_surface_override_material(i, m)
	_ghostly(body)
	add_child(body)
	for w in d.wheels:
		var hub := Node3D.new()
		hub.position = w.centre + offset
		add_child(hub)
		var wm := MeshInstance3D.new()
		wm.mesh = w.mesh
		for k in w.mats.size():
			wm.set_surface_override_material(k, w.mats[k])
		_ghostly(wm)
		hub.add_child(wm)
		_spinners.append(hub)


func _ghostly(mi: MeshInstance3D) -> void:
	mi.transparency = ALPHA
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Places the ghost at lap time `t`; hidden before the first / after the last sample.
func show_at(t: float) -> void:
	var n := samples.size() / STRIDE
	if n < 2 or t < 0.0 or t > samples[(n - 1) * STRIDE]:
		visible = false
		return
	if _cursor >= n - 1 or samples[_cursor * STRIDE] > t:
		_cursor = 0 # new lap: rewind
	while _cursor < n - 2 and samples[(_cursor + 1) * STRIDE] <= t:
		_cursor += 1
	var a := _cursor * STRIDE
	var b := a + STRIDE
	var span := samples[b] - samples[a]
	var f := clampf((t - samples[a]) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var pa := Vector3(samples[a + 1], samples[a + 2], samples[a + 3])
	var pb := Vector3(samples[b + 1], samples[b + 2], samples[b + 3])
	var qa := Quaternion(samples[a + 4], samples[a + 5], samples[a + 6], samples[a + 7]).normalized()
	var qb := Quaternion(samples[b + 4], samples[b + 5], samples[b + 6], samples[b + 7]).normalized()
	var pos := pa.lerp(pb, f)
	var xf := Transform3D(Basis(qa.slerp(qb, f)), pos)
	# Roll the wheels by the distance covered along the car's nose.
	var fwd := (pos - _last_pos).dot(-xf.basis.z)
	if visible and absf(fwd) < 5.0:
		for s in _spinners:
			s.rotate_object_local(Vector3.RIGHT, -fwd / _wheel_radius)
	_last_pos = pos
	global_transform = xf
	visible = true
