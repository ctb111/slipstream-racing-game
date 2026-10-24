class_name HudLights
extends Control
## Start lights: five red lamps in a gantry housing, then lights out and a "GO" flash.

const LAMP_R := 21.0
const PITCH := 64.0
const HOUSING := Vector2(360, 78)

var lit := 0 ## 0..5, or -1 once the lights have gone out
var _go_t := -1.0 ## seconds since lights out


func _init() -> void:
	size = Vector2(HOUSING.x, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_lit(count: int) -> void:
	lit = count
	if count < 0:
		_go_t = 0.0
	queue_redraw()


func _process(dt: float) -> void:
	if _go_t < 0.0:
		return
	_go_t += dt
	modulate.a = clampf(1.0 - (_go_t - 1.1) / 0.5, 0.0, 1.0)
	if modulate.a <= 0.0:
		visible = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	var hr := Rect2(Vector2((size.x - HOUSING.x) * 0.5, 0), HOUSING)
	HudStyle.panel(self, hr.grow(3), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 10)
	HudStyle.panel(self, hr, Color(0.035, 0.037, 0.042, 0.92), Color(1, 1, 1, 0.1), 8)
	# Mounting rail across the top.
	draw_rect(Rect2(hr.position + Vector2(10, 6), Vector2(hr.size.x - 20, 2)), Color(1, 1, 1, 0.05))
	var cy := hr.position.y + hr.size.y * 0.5 + 3.0
	var x0 := size.x * 0.5 - PITCH * 2.0
	for i in 5:
		var p := Vector2(x0 + i * PITCH, cy)
		var on := lit > i
		# Recessed pod with a hood shadow.
		draw_circle(p, LAMP_R + 5.0, Color(0, 0, 0, 0.7))
		draw_arc(p, LAMP_R + 5.0, PI + 0.3, TAU - 0.3, 24, Color(1, 1, 1, 0.07), 1.5, true)
		if on:
			draw_circle(p, LAMP_R + 12.0, Color(1.0, 0.1, 0.05, 0.1))
			draw_circle(p, LAMP_R, Color(0.9, 0.06, 0.03))
			draw_circle(p, LAMP_R * 0.72, Color(1.0, 0.22, 0.12))
			draw_circle(p + Vector2(-5, -6), LAMP_R * 0.28, Color(1.0, 0.7, 0.6, 0.55))
		else:
			draw_circle(p, LAMP_R, Color(0.13, 0.03, 0.03))
			draw_circle(p + Vector2(-5, -6), LAMP_R * 0.25, Color(1, 1, 1, 0.05))
	if _go_t >= 0.0:
		var a := clampf(1.0 - _go_t / 1.4, 0.0, 1.0)
		var pulse := 1.0 + 0.08 * exp(-_go_t * 6.0)
		var fs := int(64 * pulse)
		HudStyle.text(self, Vector2(0, HOUSING.y + 70), "GO", fs, Color(0.95, 0.96, 0.92, 0.3 + 0.7 * a), 2, 6, 1, size.x)
		draw_rect(Rect2(size.x * 0.5 - 60, HOUSING.y + 84, 120, 2), Color(0.46, 0.86, 0.52, 0.8 * a))
