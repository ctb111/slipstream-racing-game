class_name TvDirector
extends RefCounted
## Trackside "TV" cameras, like a replay: a fixed spot beside the track ahead
## of the car that pans and zooms to follow it, cutting to the next spot once
## the car has gone by.

const AHEAD_MIN := 55.0
const AHEAD_MAX := 90.0
const PAST := 28.0 ## metres past the camera before cutting
const FRAME := 7.5 ## metres of view kept around the car (sets the zoom)

var position := Vector3.ZERO
var look := Vector3.ZERO
var fov := 40.0
var valid := false
var cut := false ## true on the frame of a cut (snap, don't smooth)
var _offset := 0.0
var _side := 1.0
var _index := -1
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 930


## Returns false if there's no racing line (then use another camera).
func update(line: RacingLine, car: Car, from: Transform3D, space: PhysicsDirectSpaceState3D, dt: float) -> bool:
	if line == null or line.length <= 0.0:
		return false
	cut = false
	_index = line.closest_index(from.origin, _index)
	var car_off := line.offset_of(_index)
	var past := fposmod(car_off - _offset, line.length)
	var went_by := past < line.length * 0.5 and past > PAST
	if not valid or went_by or from.origin.distance_to(position) > 160.0:
		_place(line, car, car_off, space)
		cut = true
	var aim := from.origin + Vector3.UP * 0.55 + car.linear_velocity * 0.12
	look = aim if cut else look.lerp(aim, 1.0 - exp(-dt * 9.0))
	var d := position.distance_to(from.origin)
	var want := clampf(rad_to_deg(2.0 * atan(FRAME * 0.5 / maxf(d, 1.0))), 9.0, 55.0)
	fov = want if cut else lerpf(fov, want, 1.0 - exp(-dt * 3.0))
	return true


func _place(line: RacingLine, car: Car, car_off: float, space: PhysicsDirectSpaceState3D) -> void:
	var road_half := TrackDefs.ROAD_WIDTH * 0.5
	var target := car.global_position + Vector3.UP * 0.8
	for attempt in 6:
		_side = -_side
		var off := car_off + _rng.randf_range(AHEAD_MIN, AHEAD_MAX)
		var lat := _side * (road_half + _rng.randf_range(6.0, 11.0))
		var p := line.transform_at(off, lat, 0.0).origin
		# Stand on whatever is there (terrain, a bank), a person's height or a gantry up.
		var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 40.0, p + Vector3.DOWN * 40.0)
		down.exclude = [car.get_rid()]
		var hit := space.intersect_ray(down)
		if not hit.is_empty():
			p.y = hit.position.y
		p.y += _rng.randf_range(1.7, 4.5)
		# Need a clear view of the stretch the car is about to drive.
		var mid := line.transform_at(off - 25.0, 0.0, 1.0).origin
		var see := PhysicsRayQueryParameters3D.create(p, mid)
		see.exclude = [car.get_rid()]
		if space.intersect_ray(see).is_empty() or attempt == 5:
			position = p
			_offset = fposmod(off, line.length)
			valid = true
			look = target
			return
