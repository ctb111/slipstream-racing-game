class_name HudMinimap
extends Control
## Track outline from the circuit's centreline with a dot per car. The map is
## rotated once at build time so the circuit lies in its widest orientation.

const PAD := 16.0

var race: Node ## race.gd

var _outline := PackedVector2Array() ## already in control space
var _xf := Transform2D.IDENTITY ## world XZ -> control space
var _start := Vector2.ZERO
var _start_dir := Vector2.RIGHT


func _init() -> void:
	custom_minimum_size = Vector2(250, 200)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func build() -> void:
	var line: RacingLine = race.circuit.line
	var pts := PackedVector2Array()
	var step := maxi(1, line.centers.size() / 220)
	for i in range(0, line.centers.size(), step):
		pts.append(Vector2(line.centers[i].x, line.centers[i].z))
	# Pick the rotation with the tightest bounding box that is wider than tall.
	var best_a := 0.0
	var best_score := INF
	for deg in range(0, 180, 3):
		var rot := Transform2D(deg_to_rad(deg), Vector2.ZERO)
		var bb := _bounds(rot * pts)
		var score := bb.size.x * bb.size.y * (1.0 if bb.size.x >= bb.size.y else 1.6)
		if score < best_score:
			best_score = score
			best_a = deg_to_rad(deg)
	var rot := Transform2D(best_a, Vector2.ZERO)
	var bb := _bounds(rot * pts)
	# Box height follows the circuit's shape (within limits) so the map fills it.
	var inner_w := size.x - PAD * 2.0
	size.y = clampf(inner_w * bb.size.y / bb.size.x, 90.0, 220.0) + PAD * 2.0
	var avail := size - Vector2(PAD, PAD) * 2.0
	var k := minf(avail.x / bb.size.x, avail.y / bb.size.y)
	var offset := (size - bb.size * k) * 0.5 - bb.position * k
	_xf = Transform2D(0.0, Vector2(k, k), 0.0, offset) * rot
	_outline = _xf * pts
	_outline.append(_outline[0])
	var s_idx := int(race.circuit.start_offset / line.length * line.centers.size()) % line.centers.size()
	var s0 := line.centers[s_idx]
	var s1 := line.centers[(s_idx + 2) % line.centers.size()]
	_start = to_map(s0)
	_start_dir = (to_map(s1) - _start).normalized()
	queue_redraw()


func _bounds(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


func to_map(world: Vector3) -> Vector2:
	return _xf * Vector2(world.x, world.z)


func _process(_dt: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	HudStyle.panel(self, Rect2(Vector2.ZERO, size))
	if _outline.size() < 3:
		return
	draw_polyline(_outline, Color(0, 0, 0, 0.55), 7.0, true)
	draw_polyline(_outline, Color(0.9, 0.9, 0.88, 0.32), 3.0, true)
	# Start / finish: a short bar across the track.
	var n := Vector2(-_start_dir.y, _start_dir.x)
	draw_line(_start - n * 7.0, _start + n * 7.0, Color(0, 0, 0, 0.7), 5.0, true)
	draw_line(_start - n * 6.0, _start + n * 6.0, HudStyle.TEXT, 2.0, true)
	var me = race.player
	for e in race.entries:
		if e == me or e.car == null or not is_instance_valid(e.car):
			continue
		var p := to_map(e.car.global_position)
		draw_circle(p, 5.0, Color(0, 0, 0, 0.6))
		draw_circle(p, 3.6, Color(0.9, 0.9, 0.88, 0.92))
	if me and me.car and is_instance_valid(me.car):
		var p := to_map(me.car.global_position)
		draw_circle(p, 9.0, Color(1.0, 0.72, 0.25, 0.18))
		draw_circle(p, 6.2, Color(0, 0, 0, 0.7))
		draw_circle(p, 4.8, HudStyle.AMBER)
