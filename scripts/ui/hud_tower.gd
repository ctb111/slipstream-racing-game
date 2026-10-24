class_name HudTower
extends Control
## Live standings: compact rows (position, paint stripe, name, gap to the leader).
## Rows glide to their new slot when positions change.

const ROW_H := 25.0
const ROW_GAP := 2.0
const WIDTH := 262.0

var race: Node ## race.gd

const SETTLE := 0.3 ## s a new order must hold before rows move (no flicker between near-equal cars)

var _y := {} ## Entry -> displayed row y (animated)
var _shown: Array = [] ## order being displayed
var _pending: Array = [] ## newer order waiting to settle
var _pending_t := 0.0


func _init() -> void:
	size = Vector2(WIDTH, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The order to draw: race standings, debounced so two cars trading places
## every frame (side by side, or on the grid) don't leave rows stuck mid-slide
## on top of each other with a hole where one of them should be.
func _order(dt: float) -> Array:
	var live: Array = race.standings()
	if _shown.size() != live.size() or not _shown.all(func(e): return e in live):
		_shown = live # someone joined / left: take it as is
		_pending = []
	elif live != _shown:
		if live != _pending:
			_pending = live
			_pending_t = 0.0
		_pending_t += dt
		if _pending_t >= SETTLE:
			_shown = live
			_pending = []
	else:
		_pending = []
	return _shown


func _process(dt: float) -> void:
	var order := _order(dt)
	var t := 1.0 - exp(-dt * 14.0)
	var step := ROW_H + ROW_GAP
	for i in order.size():
		var target := i * step
		var y: float = lerpf(_y.get(order[i], target), target, t)
		_y[order[i]] = target if absf(y - target) < 0.5 else y
	size.y = order.size() * step
	queue_redraw()


func _gap(e, leader, i: int) -> String:
	if i == 0:
		return "LAP %d" % clampi(e.lap, 1, race.laps) if not e.finished else "FINISH"
	if e.finished and leader.finished:
		return "+%.1f" % (e.finish_time - leader.finish_time)
	var metres: float = leader.progress - e.progress
	var lapped := int(metres / race.circuit.line.length)
	if lapped >= 1:
		return "+%d LAP" % lapped
	var spd: float = absf(leader.car.speed) if leader.car and is_instance_valid(leader.car) else 25.0
	return "+%.1f" % (metres / maxf(spd, 25.0))


func _draw() -> void:
	var order: Array = _shown if not _shown.is_empty() else race.standings()
	if order.is_empty():
		return
	var leader = order[0]
	# Draw the player's row last so it sits above rows sliding past it.
	var seq: Array = order.duplicate()
	var me = race.player
	if me in seq:
		seq.erase(me)
		seq.append(me)
	for e in seq:
		var i := order.find(e)
		var y: float = _y.get(e, i * (ROW_H + ROW_GAP))
		var is_me: bool = e == me
		var row := Rect2(0, y, WIDTH, ROW_H)
		HudStyle.panel(self, row, Color(0.13, 0.1, 0.05, 0.8) if is_me else HudStyle.GLASS,
				Color(1, 0.72, 0.25, 0.55) if is_me else Color(1, 1, 1, 0.05), 3)
		# Position box.
		var pbox := Rect2(0, y, 28, ROW_H)
		if is_me:
			HudStyle.panel(self, pbox, HudStyle.AMBER, HudStyle.AMBER, 3)
		else:
			HudStyle.panel(self, pbox, Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 3)
		HudStyle.text(self, Vector2(0, y + 18), str(i + 1), 15, # slot number: matches the (debounced) row order
				Color(0.05, 0.05, 0.05) if is_me else HudStyle.TEXT, 2, 0, 1, 28)
		# Paint stripe.
		var paint := Color(0.5, 0.5, 0.5)
		if e.car and is_instance_valid(e.car):
			paint = e.car.paint_color.lightened(0.15)
		draw_rect(Rect2(34, y + 6, 3, ROW_H - 12), paint)
		HudStyle.text(self, Vector2(44, y + 17.5), e.name.to_upper(), 14,
				HudStyle.AMBER if is_me else HudStyle.TEXT, 1, 1, 0, 150)
		var gap := _gap(e, leader, i)
		HudStyle.text(self, Vector2(WIDTH - 108, y + 17.5), gap, 13,
				HudStyle.DIM if not is_me else Color(1, 0.8, 0.45, 0.9), 0, 0, 2, 96)
		if e.finished:
			_flag(Vector2(WIDTH - 9, y + 8))


## Tiny chequered flag for finished drivers.
func _flag(p: Vector2) -> void:
	for gx in 2:
		for gy in 3:
			var c := HudStyle.TEXT if (gx + gy) % 2 == 0 else Color(0.1, 0.1, 0.1)
			draw_rect(Rect2(p + Vector2(gx * 3, gy * 3), Vector2(3, 3)), c)
