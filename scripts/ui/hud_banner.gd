class_name HudBanner
extends Control
## Centre-screen messages: lap time card (with delta vs best), "FINAL LAP" /
## finish banners and the wrong-way warning. Drawn, never rebuilt.

const LAP_SHOW := 3.2
const BANNER_SHOW := 2.8

var wrong_way := false

var _lap_title := ""
var _lap_time := ""
var _lap_delta := NAN
var _lap_best := false
var _lap_t := 0.0
var _banner := ""
var _banner_sub := ""
var _banner_t := 0.0
var _ww_a := 0.0
var _clock := 0.0


func _init() -> void:
	size = Vector2(640, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_lap(title: String, time: String, delta: float, best: bool) -> void:
	_lap_title = title
	_lap_time = time
	_lap_delta = delta
	_lap_best = best
	_lap_t = LAP_SHOW


func show_banner(text: String, sub := "") -> void:
	_banner = text
	_banner_sub = sub
	_banner_t = BANNER_SHOW


func _process(dt: float) -> void:
	_clock += dt
	_lap_t = maxf(_lap_t - dt, 0.0)
	_banner_t = maxf(_banner_t - dt, 0.0)
	_ww_a = move_toward(_ww_a, 1.0 if wrong_way else 0.0, dt * 4.0)
	queue_redraw()


## 0..1 envelope: quick fade in, hold, fade out over the last 0.6 s.
func _env(t: float, total: float) -> float:
	return clampf(minf((total - t) / 0.18, t / 0.6), 0.0, 1.0)


func _draw() -> void:
	var cx := size.x * 0.5
	if _lap_t > 0.0:
		var a := _env(_lap_t, LAP_SHOW)
		var w := 340.0
		var r := Rect2(cx - w * 0.5, 0, w, 86)
		HudStyle.panel(self, r, HudStyle.with_alpha(HudStyle.GLASS, a), Color(1, 1, 1, 0.08 * a), 4)
		draw_rect(Rect2(r.position, Vector2(w, 2)), HudStyle.with_alpha(HudStyle.AMBER, a))
		var cap := _lap_title + ("   ·   BEST LAP" if _lap_best else "")
		HudStyle.text(self, Vector2(r.position.x, 26), cap, 13,
				HudStyle.with_alpha(HudStyle.AMBER if _lap_best else HudStyle.DIM, a), 1, 3, 1, w)
		var has_delta := not is_nan(_lap_delta)
		var tw := HudStyle.text_width(_lap_time, 38, 1)
		var dw := HudStyle.text_width(HudStyle.fmt_delta(_lap_delta), 18, 1) + 14.0 if has_delta else 0.0
		var x := cx - (tw + dw) * 0.5
		HudStyle.text(self, Vector2(x, 70), _lap_time, 38, HudStyle.with_alpha(HudStyle.TEXT, a), 1)
		if has_delta:
			var col := HudStyle.GREEN if _lap_delta < 0.0 else HudStyle.RED
			HudStyle.text(self, Vector2(x + tw + 14.0, 68), HudStyle.fmt_delta(_lap_delta), 18,
					HudStyle.with_alpha(col, a), 1)
	if _banner_t > 0.0:
		var a := _env(_banner_t, BANNER_SHOW)
		var y := 128.0
		var tw := HudStyle.text_width(_banner, 30, 2, 8)
		HudStyle.text(self, Vector2(0, y), _banner, 30, HudStyle.with_alpha(HudStyle.TEXT, a), 2, 8, 1, size.x)
		var gap := tw * 0.5 + 22.0
		var ln := 90.0 * clampf((BANNER_SHOW - _banner_t) / 0.35, 0.0, 1.0)
		draw_rect(Rect2(cx - gap - ln, y - 11, ln, 2), HudStyle.with_alpha(HudStyle.AMBER, a))
		draw_rect(Rect2(cx + gap, y - 11, ln, 2), HudStyle.with_alpha(HudStyle.AMBER, a))
		if _banner_sub != "":
			HudStyle.text(self, Vector2(0, y + 26), _banner_sub, 15, HudStyle.with_alpha(HudStyle.DIM, a), 1, 3, 1, size.x)
	if _ww_a > 0.0:
		var pulse := 0.75 + 0.25 * sin(_clock * 7.0)
		var a := _ww_a
		var w := 300.0
		var r := Rect2(cx - w * 0.5, 190, w, 62)
		HudStyle.panel(self, r, Color(0.22, 0.03, 0.02, 0.72 * a), Color(0.94, 0.27, 0.2, 0.7 * a * pulse), 4)
		HudStyle.text(self, Vector2(r.position.x, r.position.y + 40), "WRONG WAY", 28,
				Color(1, 0.9, 0.86, a), 2, 6, 1, w)
		# Chevrons pointing back: "turn around".
		for s in [-1.0, 1.0]:
			var bx: float = cx + s * (w * 0.5 - 26.0)
			var col := Color(0.94, 0.27, 0.2, a * pulse)
			for k in 2:
				var ox: float = bx + s * k * -9.0
				draw_polyline(PackedVector2Array([
					Vector2(ox + s * 5, r.position.y + 21), Vector2(ox - s * 5, r.position.y + 31),
					Vector2(ox + s * 5, r.position.y + 41)]), col, 3.0, true)
