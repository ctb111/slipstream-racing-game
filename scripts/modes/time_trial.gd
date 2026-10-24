class_name TimeTrial
extends RaceMode
## Solo laps against the clock and a ghost of your best lap. Every lap is
## recorded (GhostCar, ~30 Hz); a new personal best replaces the ghost and is
## saved per track + car in user:// together with its split times at 1/3 and
## 2/3 of the lap, which the overlay compares against while you drive.
##
## Debug (after `--`, race scene): --mode=timetrial [--laps=N] [--tt_skill=0.85]
## (with --allbots: the AI's pace, so the ghost and the car drift apart).

const UNLIMITED := 99 ## "laps" of an endless session
const SPLITS := [1.0 / 3.0, 2.0 / 3.0]
const SPLIT_SHOW := 3.0

var _best := {} ## {lap: float, splits: Array[float], samples: PackedFloat32Array}
var _rec := PackedFloat32Array()
var _rec_lap := -1
var _next_sample := 0.0
var _splits: Array[float] = []
var _ghost: GhostCar
var _overlay: SplitOverlay
var _key := ""


static func file_for(track_id: String, car_id: String) -> String:
	return "ghost_%s_%s.bin" % [track_id, car_id]


## Saved personal best for this track + car: {lap, splits, samples} or {}.
static func load_best(track_id: String, car_id: String) -> Dictionary:
	var path := ModeStore.dir() + file_for(track_id, car_id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var d = f.get_var() if f else null
	if not (d is Dictionary and d.has("lap") and d.has("samples")):
		return {}
	return d


static func best_lap(track_id: String, car_id: String) -> float:
	return float(load_best(track_id, car_id).get("lap", INF))


func setup_overrides() -> Dictionary:
	var laps := Game.tt_laps if Game.tt_laps > 0 else UNLIMITED
	var a := ModeStore.args()
	if a.has("laps"):
		laps = int(a.laps)
	return {laps = laps, grid = [{peer = 1, name = Game.player_name, bot = false}]}


func attach(_race: Node) -> void:
	super(_race)
	_key = file_for(race.circuit.def.id, race.player.car.model_id)
	_best = load_best(race.circuit.def.id, race.player.car.model_id)
	race.lap_completed.connect(_on_lap)
	if Game.tt_ghost:
		_ghost = GhostCar.new()
		_ghost.name = "Ghost"
		race.add_child(_ghost)
		_ghost.build(race.player.car.model_id, race.player.car.paint_color)
		_ghost.samples = _best.get("samples", PackedFloat32Array())
		_ghost.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var root := HudStyle.make_root(layer)
	_overlay = SplitOverlay.new()
	_overlay.position = Vector2(28, 222) # where the standings tower sits in a race
	_overlay.best = float(_best.get("lap", INF))
	_overlay.ghost = Game.tt_ghost
	root.add_child(_overlay)
	_hide_tower.call_deferred()
	var a := ModeStore.args()
	if a.has("tt_skill") and race.player.ai:
		race.player.ai.skill = float(a.tt_skill)


## One car, no standings: the overlay takes the tower's place.
func _hide_tower() -> void:
	for c in race.get_children():
		if c is RaceHud and c.get("_tower"):
			c._tower.visible = false


func _physics_process(_dt: float) -> void:
	if race == null or race.player == null:
		return
	var p = race.player
	var running: bool = race.state != race.State.COUNTDOWN and p.lap >= 1 and not p.finished
	var t: float = race.race_time - p.lap_start
	if running:
		if p.lap != _rec_lap: # a new lap from the line
			_rec_lap = p.lap
			_rec = PackedFloat32Array()
			_next_sample = 0.0
			_splits = []
		if t >= _next_sample:
			GhostCar.record(_rec, t, p.car.global_transform)
			_next_sample += 1.0 / GhostCar.RATE
		_check_splits(p, t)
	if _ghost:
		_ghost.show_at(t if running else -1.0)


func _check_splits(p, t: float) -> void:
	var length: float = race.circuit.line.length
	var rel: float = p.progress - (p.lap - 1) * length
	var k := _splits.size()
	if k >= SPLITS.size():
		return
	var at: float = SPLITS[k] * length
	if rel >= at and rel < at + length * 0.15:
		_splits.append(t)
		var bs: Array = _best.get("splits", [])
		var delta := t - float(bs[k]) if k < bs.size() else NAN
		_overlay.show_split(k + 1, t, delta)
		if ModeStore.args().has("allbots"):
			print("time trial: split %d  %s  %s" % [k + 1, RaceHud.fmt_time(t), HudStyle.fmt_delta(delta) if not is_nan(delta) else "(no best)"])


func _on_lap(e, lap_time: float) -> void:
	if e != race.player:
		return
	GhostCar.record(_rec, lap_time, e.car.global_transform)
	var valid := _splits.size() == SPLITS.size() # drove the whole lap (no shortcut / reset across the line)
	var prev := float(_best.get("lap", INF))
	_overlay.laps_done += 1
	if valid and lap_time < prev:
		_best = {lap = lap_time, splits = _splits.duplicate(), samples = _rec,
			car = e.car.model_id, track = race.circuit.def.id, date = Time.get_datetime_string_from_system()}
		_save()
		_overlay.best = lap_time
		_overlay.new_best = SPLIT_SHOW
		if _ghost:
			_ghost.samples = _rec
		if ModeStore.args().has("allbots"):
			print("time trial: new personal best %s (%d ghost samples)" % [RaceHud.fmt_time(lap_time), _rec.size() / GhostCar.STRIDE])
	_rec_lap = -1 # next tick starts a fresh recording
	_rec = PackedFloat32Array()


func _save() -> void:
	var f := FileAccess.open(ModeStore.dir() + _key, FileAccess.WRITE)
	if f:
		f.store_var(_best)


func results_subtitle() -> String:
	return "TIME TRIAL  ·  %s  ·  BEST %s" % [str(race.circuit.def.get("name", "")).to_upper(),
		RaceHud.fmt_time(float(_best.get("lap", INF)))]


func results_buttons(parent: Control, make: Callable) -> bool:
	make.call(parent, "Retry", func():
		get_tree().paused = false
		get_tree().reload_current_scene())
	make.call(parent, "Menu", func():
		get_tree().paused = false
		race.quit_to_menu())
	return true


## Left-side panel: personal best, ghost state, and a split card after each sector.
class SplitOverlay:
	extends Control
	var best := INF
	var ghost := true
	var laps_done := 0
	var new_best := 0.0
	var _split := 0
	var _split_t := 0.0
	var _split_delta := NAN
	var _show := 0.0

	func _init() -> void:
		size = Vector2(262, 150)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_split(n: int, t: float, delta: float) -> void:
		_split = n
		_split_t = t
		_split_delta = delta
		_show = SPLIT_SHOW

	func _process(dt: float) -> void:
		_show = maxf(_show - dt, 0.0)
		new_best = maxf(new_best - dt, 0.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		HudStyle.panel(self, Rect2(0, 0, w, 64))
		draw_rect(Rect2(0, 0, 3, 64), HudStyle.AMBER)
		HudStyle.text(self, Vector2(18, 22), "TIME TRIAL", 11, HudStyle.AMBER, 1, 3)
		HudStyle.text(self, Vector2(w - 138, 22), "GHOST ON" if ghost else "GHOST OFF", 11, HudStyle.DIM, 1, 3, 2, 120)
		HudStyle.text(self, Vector2(18, 50), "PB", 11, HudStyle.DIM, 1, 2)
		var col := HudStyle.GREEN if new_best > 0.0 else HudStyle.TEXT
		HudStyle.text(self, Vector2(88, 51), RaceHud.fmt_time(best), 18, col, 1)
		if new_best > 0.0:
			HudStyle.text(self, Vector2(w - 138, 50), "NEW BEST", 11, HudStyle.GREEN, 2, 2, 2, 120)
		if _show <= 0.0:
			return
		var a := clampf(_show / 0.4, 0.0, 1.0)
		var y := 74.0
		HudStyle.panel(self, Rect2(0, y, w, 58), HudStyle.with_alpha(HudStyle.GLASS, a), HudStyle.with_alpha(HudStyle.EDGE, a))
		HudStyle.text(self, Vector2(18, y + 22), "SPLIT %d" % _split, 11, HudStyle.with_alpha(HudStyle.DIM, a), 1, 3)
		HudStyle.text(self, Vector2(18, y + 47), RaceHud.fmt_time(_split_t), 18, HudStyle.with_alpha(HudStyle.TEXT, a), 1)
		if not is_nan(_split_delta):
			var dc := HudStyle.GREEN if _split_delta < 0.0 else HudStyle.RED
			HudStyle.text(self, Vector2(w - 138, y + 47), HudStyle.fmt_delta(_split_delta), 22,
					HudStyle.with_alpha(dc, a), 2, 0, 2, 120)
