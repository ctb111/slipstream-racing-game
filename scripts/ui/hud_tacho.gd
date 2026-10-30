class_name HudTacho
extends Control
## Analogue rev counter with gear, digital speed, shift lights and assist
## indicators. Everything is drawn in _draw; no nodes are created at runtime.

const SWEEP_START := deg_to_rad(135.0) ## 0 rpm at about seven o'clock
const SWEEP := deg_to_rad(270.0)
const RADIUS := 124.0
const RED_FROM := 6500.0

var car: Car

var _rpm := 0.0 ## smoothed needle rpm
var _abs_t := 0.0 ## >0 while ABS is working (with a short hold so it doesn't flicker)
var _tc_t := 0.0
var _blink := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(290, 322)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_rpm = lerpf(_rpm, car.rpm, 1.0 - exp(-dt * 16.0))
	_blink += dt
	var moving := absf(car.speed) > 3.0
	var slip := 0.0
	var drive_slip := 0.0
	for w in car.wheels:
		slip = maxf(slip, w.slip)
		if w.driven:
			drive_slip = maxf(drive_slip, w.slip)
	_abs_t = 0.25 if car.assist_abs and moving and car.brake > 0.55 and slip > 0.02 else maxf(_abs_t - dt, 0.0)
	_tc_t = 0.25 if car.assist_tc and car.throttle > 0.5 and drive_slip > 0.05 and not car.drifting \
			else maxf(_tc_t - dt, 0.0)
	if is_visible_in_tree():
		queue_redraw()


func _max_rpm() -> float:
	return ceilf(car.redline_rpm / 1000.0 + 0.99) * 1000.0


func _angle(r: float, top: float) -> float:
	return SWEEP_START + SWEEP * clampf(r / top, 0.0, 1.0)


func _draw() -> void:
	if car == null or not is_instance_valid(car):
		return
	var c := Vector2(size.x * 0.5, RADIUS + 6.0)
	var top := _max_rpm()
	var red_from := minf(RED_FROM, car.redline_rpm - 500.0)
	var R := RADIUS

	# Dial body: dark glass disc, hairline bezel, soft inner ring.
	draw_circle(c, R + 4.0, Color(0, 0, 0, 0.28))
	draw_circle(c, R, Color(0.02, 0.022, 0.027, 0.78))
	draw_arc(c, R, 0.0, TAU, 128, Color(1, 1, 1, 0.12), 1.5, true)
	draw_arc(c, R - 6.0, 0.0, TAU, 128, Color(1, 1, 1, 0.035), 1.0, true)

	# Rev track, live fill, red zone.
	var a0 := SWEEP_START
	var track_r := R - 12.0
	draw_arc(c, track_r, a0, a0 + SWEEP, 96, Color(1, 1, 1, 0.06), 5.0, true)
	var ar := _angle(_rpm, top)
	var fill := HudStyle.RED if _rpm >= red_from else HudStyle.AMBER
	if ar > a0 + 0.01:
		draw_arc(c, track_r, a0, ar, 64, HudStyle.with_alpha(fill, 0.55), 5.0, true)
	draw_arc(c, track_r, _angle(red_from, top), a0 + SWEEP, 24, Color(0.85, 0.12, 0.08, 0.85), 5.0, true)

	# Ticks every 250 rpm, numerals every 1000.
	var steps := int(top / 250.0)
	for i in steps + 1:
		var r := i * 250.0
		var a := _angle(r, top)
		var dir := Vector2(cos(a), sin(a))
		var major := i % 4 == 0
		var half := i % 2 == 0
		var tl := 13.0 if major else (8.0 if half else 4.0)
		var col := Color(0.95, 0.3, 0.24) if r >= red_from else HudStyle.TEXT
		col.a = 0.9 if major else (0.55 if half else 0.3)
		var outer := R - 18.0
		draw_line(c + dir * outer, c + dir * (outer - tl), col, 2.2 if major else 1.2, true)
		if major:
			var p := c + dir * (R - 44.0)
			HudStyle.text(self, p + Vector2(-16, 7), str(int(r / 1000.0)), 19, col, 1, 0, 1, 32)


	# Shift lights: five small LEDs filling from 86 % of the redline, flashing near it.
	var shift := clampf((_rpm / car.redline_rpm - 0.86) / 0.11, 0.0, 1.0)
	var flash := _rpm > car.redline_rpm * 0.97
	var on_blink := fmod(_blink, 0.16) < 0.08
	for k in 5:
		var p := c + Vector2((k - 2) * 12.0, -42.0)
		var lit := shift * 5.0 > k + 0.001
		var col := Color(1, 1, 1, 0.07)
		if flash:
			col = HudStyle.RED if on_blink else Color(0.4, 0.06, 0.04, 0.8)
		elif lit:
			col = HudStyle.AMBER if k < 3 else HudStyle.RED
		draw_circle(p, 3.2, col)
		if lit or (flash and on_blink):
			draw_circle(p, 6.0, HudStyle.with_alpha(col, 0.18))

	# Gear.
	var g := "R" if car.gear < 0 else ("N" if car.gear == 0 else str(car.gear))
	var gear_col := HudStyle.AMBER if flash and not car.automatic else HudStyle.TEXT
	HudStyle.text(self, c + Vector2(-50, 26), g, 78, gear_col, 2, 0, 1, 100)

	# Needle: a blade on the outer ring, keeping the centre clear for the gear.
	var dir_n := Vector2(cos(ar), sin(ar))
	var n0 := c + dir_n * (R * 0.5)
	var n1 := c + dir_n * (R - 9.0)
	draw_line(n0, n1, Color(1.0, 0.72, 0.25, 0.16), 8.0, true)
	draw_line(n0, n1, Color(1.0, 0.86, 0.6), 3.0, true)
	draw_circle(n0, 2.5, Color(1.0, 0.86, 0.6))

	# Digital speed in the gap at the bottom of the dial.
	var spd := roundi(Game.speed_units(car.speed))
	HudStyle.text(self, c + Vector2(-60, R * 0.72), "%d" % spd, 40, HudStyle.TEXT, 1, 0, 1, 120)
	HudStyle.text(self, c + Vector2(-40, R * 0.72 + 16), Game.speed_label(), 11, HudStyle.DIM, 1, 2, 1, 80)

	# Indicator chips under the dial: ABS, TC, gearbox.
	var y := c.y + R + 16.0
	var chips := [
		["ABS", 2 if _abs_t > 0.0 else (1 if car.assist_abs else 0)],
		["TC", 2 if _tc_t > 0.0 else (1 if car.assist_tc else 0)],
		["AUTO" if car.automatic else "MANUAL", 1],
	]
	var widths := [44.0, 36.0, 64.0]
	var total := 0.0
	for w in widths:
		total += w
	total += 6.0 * (widths.size() - 1)
	var x := c.x - total * 0.5
	for k in chips.size():
		var state: int = chips[k][1]
		var r := Rect2(x, y, widths[k], 18)
		var tc := HudStyle.FAINT
		if state == 2:
			HudStyle.panel(self, r, Color(1, 0.72, 0.25, 0.9), Color(1, 0.72, 0.25, 1), 3)
			tc = Color(0.05, 0.05, 0.05)
		else:
			HudStyle.panel(self, r, Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.1 if state == 1 else 0.04), 3)
			tc = HudStyle.DIM if state == 1 else HudStyle.FAINT
		HudStyle.text(self, Vector2(x, y + 13.5), chips[k][0], 11, tc, 1, 1, 1, widths[k])
		x += widths[k] + 6.0
