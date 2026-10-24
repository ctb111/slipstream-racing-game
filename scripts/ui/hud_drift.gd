class_name HudDrift
extends Control
## Subtle drift readout: slide angle while drifting, plus a running score for
## the current slide that lingers briefly after it ends.

const HOLD := 1.4 ## seconds the score stays after the slide ends

var car: Car

var _score := 0.0
var _angle := 0.0
var _hold := 0.0
var _alpha := 0.0


func _init() -> void:
	size = Vector2(240, 70)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var deg := absf(rad_to_deg(car.body_slip))
	if car.drifting and deg > 4.0:
		if _hold <= 0.0 and _alpha <= 0.0:
			_score = 0.0
		_score += deg * absf(car.speed) * dt * 0.5
		_angle = lerpf(_angle, deg, 1.0 - exp(-dt * 10.0))
		_hold = HOLD
	else:
		_hold = maxf(_hold - dt, 0.0)
	var target := 1.0 if _hold > 0.0 else 0.0
	var was := _alpha
	_alpha = move_toward(_alpha, target, dt * (6.0 if target > 0.0 else 2.5))
	if _alpha > 0.0 or was > 0.0:
		queue_redraw()


func _draw() -> void:
	if _alpha <= 0.0:
		return
	var a := _alpha
	var active := car != null and car.drifting
	var w := size.x
	HudStyle.text(self, Vector2(0, 16), "DRIFT", 12, HudStyle.with_alpha(HudStyle.AMBER, a), 1, 5, 1, w)
	var s := "%d" % roundi(_score)
	HudStyle.text(self, Vector2(0, 50), s, 32, HudStyle.with_alpha(HudStyle.TEXT, a), 2, 1, 1, w)
	var ang := "%d°" % roundi(_angle) if active else ""
	var sw := HudStyle.text_width(s, 32, 2, 1)
	HudStyle.text(self, Vector2(w * 0.5 + sw * 0.5 + 10, 48), ang, 15, HudStyle.with_alpha(HudStyle.DIM, a), 1)
	# Thin angle bar under the score (full at 45 degrees).
	var bw := 120.0
	var f := clampf(_angle / 45.0, 0.0, 1.0) if active else 0.0
	draw_rect(Rect2(w * 0.5 - bw * 0.5, 60, bw, 2), Color(1, 1, 1, 0.1 * a))
	draw_rect(Rect2(w * 0.5 - bw * 0.5, 60, bw * f, 2), HudStyle.with_alpha(HudStyle.AMBER, 0.9 * a))
