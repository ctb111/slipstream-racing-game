class_name HudInfo
extends Control
## Top-left timing block: position, lap, current / last / best lap with delta.

var position_now := 0
var drivers := 0
var lap := 1
var laps := 1
var current := 0.0
var last := 0.0
var best := INF
var last_delta := NAN ## last lap vs the previous best (NAN = nothing to compare)


func _init() -> void:
	size = Vector2(262, 178)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	HudStyle.panel(self, Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(0, 0, 3, 72), HudStyle.AMBER)
	# Position and lap.
	HudStyle.text(self, Vector2(18, 24), "POSITION", 11, HudStyle.DIM, 1, 3)
	var ps := str(position_now)
	HudStyle.text(self, Vector2(16, 68), ps, 50, HudStyle.TEXT, 2)
	var pw := HudStyle.text_width(ps, 50, 2)
	HudStyle.text(self, Vector2(20 + pw, 68), "/%d" % drivers, 22, HudStyle.DIM, 1)
	HudStyle.text(self, Vector2(w - 118, 24), "LAP", 11, HudStyle.DIM, 1, 3, 2, 100)
	var ls := "/%d" % laps if laps > 0 else "" # 0 = endless (time trial)
	var lw := HudStyle.text_width(ls, 22, 1)
	HudStyle.text(self, Vector2(w - 18 - lw, 68), ls, 22, HudStyle.DIM, 1)
	HudStyle.text(self, Vector2(w - 122 - lw, 68), str(lap), 50, HudStyle.TEXT, 2, 0, 2, 100)
	draw_rect(Rect2(16, 84, w - 32, 1), Color(1, 1, 1, 0.08))
	# Times.
	var rows := [["CURRENT", current], ["LAST", last], ["BEST", best]]
	for i in rows.size():
		var y := 110.0 + i * 24.0
		HudStyle.text(self, Vector2(18, y), rows[i][0], 11, HudStyle.DIM, 1, 2)
		var t: float = rows[i][1]
		var col := HudStyle.TEXT if i == 0 else Color(0.9, 0.9, 0.88, 0.8)
		if i == 2 and t != INF:
			col = HudStyle.AMBER
		HudStyle.text(self, Vector2(88, y + 1), RaceHud.fmt_time(t), 18, col, 1)
		if i == 1 and not is_nan(last_delta):
			var dc := HudStyle.GREEN if last_delta < 0.0 else HudStyle.RED
			HudStyle.text(self, Vector2(w - 98, y), HudStyle.fmt_delta(last_delta), 14,
					HudStyle.with_alpha(dc, 0.9), 1, 0, 2, 80)
