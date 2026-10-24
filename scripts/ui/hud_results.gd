class_name HudResults
extends Control
## Results table: position, driver, total time / gap, best lap (fastest lap marked).

const ROW_H := 34.0
const HEAD_H := 30.0
const COLS := [0.0, 64.0, 330.0, 480.0] ## x of POS, DRIVER, TIME, BEST LAP
const WIDTH := 600.0
const PTS_W := 70.0

var race: Node ## race.gd


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Championship round: an extra column with the points each driver scored.
func _points_col() -> bool:
	return race.mode_ctl != null and race.mode_ctl.points_for(race.player) >= 0


func refresh() -> void:
	custom_minimum_size = Vector2(WIDTH + (PTS_W if _points_col() else 0.0), HEAD_H + race.entries.size() * ROW_H)
	queue_redraw()


func _draw() -> void:
	var order: Array = race.standings()
	if order.is_empty():
		return
	var winner = order[0]
	var fastest := INF
	for e in order:
		fastest = minf(fastest, e.best_lap)
	var heads := ["POS", "DRIVER", "TIME", "BEST LAP"]
	for k in heads.size():
		HudStyle.text(self, Vector2(COLS[k] + (0.0 if k != 0 else 10.0), 18), heads[k], 11, HudStyle.DIM, 1, 3)
	var pts := _points_col()
	var width := WIDTH + (PTS_W if pts else 0.0)
	if pts:
		HudStyle.text(self, Vector2(WIDTH, 18), "PTS", 11, HudStyle.DIM, 1, 3, 2, PTS_W - 10)
	draw_rect(Rect2(0, HEAD_H - 4, width, 1), Color(1, 1, 1, 0.1))
	for i in order.size():
		var e = order[i]
		var y := HEAD_H + i * ROW_H
		var is_me: bool = e == race.player
		if is_me:
			HudStyle.panel(self, Rect2(0, y + 2, width, ROW_H - 4), Color(1, 0.72, 0.25, 0.12), Color(1, 0.72, 0.25, 0.45), 3)
		elif i % 2 == 1:
			draw_rect(Rect2(0, y + 2, width, ROW_H - 4), Color(1, 1, 1, 0.025))
		var base := y + 23.0
		var pc := HudStyle.AMBER if i < 3 and not is_me else HudStyle.TEXT
		if is_me:
			pc = HudStyle.AMBER
		HudStyle.text(self, Vector2(COLS[0], base + 1), str(e.position), 22, pc, 2, 0, 1, 44)
		if e.car and is_instance_valid(e.car):
			draw_rect(Rect2(COLS[1] - 12, y + 10, 3, ROW_H - 20), e.car.paint_color.lightened(0.15))
		HudStyle.text(self, Vector2(COLS[1], base), e.name.to_upper(), 17,
				HudStyle.AMBER if is_me else HudStyle.TEXT, 1, 1, 0, 250)
		var t := ""
		var tc := HudStyle.TEXT
		if not e.finished:
			t = "running"
			tc = HudStyle.FAINT
		elif e == winner:
			t = RaceHud.fmt_time(e.finish_time)
		else:
			t = "+%.3f" % (e.finish_time - winner.finish_time)
			tc = Color(0.9, 0.9, 0.88, 0.8)
		HudStyle.text(self, Vector2(COLS[2], base), t, 17, tc, 1)
		var is_fast: bool = e.best_lap != INF and is_equal_approx(e.best_lap, fastest)
		HudStyle.text(self, Vector2(COLS[3], base), RaceHud.fmt_time(e.best_lap), 17,
				HudStyle.AMBER if is_fast else Color(0.9, 0.9, 0.88, 0.8), 1)
		if pts:
			var p: int = race.mode_ctl.points_for(e)
			HudStyle.text(self, Vector2(WIDTH, base), "+%d" % p if p > 0 else "-", 17,
					HudStyle.AMBER if p > 0 else HudStyle.FAINT, 2, 0, 2, PTS_W - 10)
		if is_fast:
			draw_circle(Vector2(COLS[3] - 10, y + ROW_H * 0.5), 3.0, HudStyle.AMBER)
