class_name Championship
extends RaceMode
## A series of rounds against a fixed field of bots. Points 10-8-6-5-4-3-2-1,
## grid in reverse championship order (the leader starts at the back; round one:
## the player at the back). Progress is saved after every round, so the player
## can quit and continue later.
##
## Static functions own the saved state; an instance is the race-side
## controller for one round (records the result when the race finishes).
##
## Debug (after `--`, race scene): --mode=championship [--champ_new=<series id>]
## runs the next round; with --allbots it prints the standings before quitting.

const FILE := "championship.json"
const POINTS := [10, 8, 6, 5, 4, 3, 2, 1]
const SERIES: Array[Dictionary] = [
	{
		id = "classic_cup", name = "Classic Cup",
		blurb = "Four rounds on the classic circuits. The place to start.",
		rounds = [
			{track = "kiefernring"}, {track = "valle_club"},
			{track = "hochwald"}, {track = "kuestenstrasse"},
		],
	},
	{
		id = "weather_masters", name = "Weather Masters",
		blurb = "Storm, snow and low sun. Five rounds where the sky fights back.",
		rounds = [
			{track = "brackenmoor", weather = Weather.Kind.STORM},
			{track = "valtellina", weather = Weather.Kind.GOLDEN},
			{track = "schneekopf", weather = Weather.Kind.SNOW},
			{track = "hochwald", weather = Weather.Kind.STORM},
			{track = "kuestenstrasse", weather = Weather.Kind.GOLDEN},
		],
	},
	{
		id = "grand_tour", name = "Grand Tour",
		blurb = "Every circuit in the game, back to back. The full season.",
		rounds = [
			{track = "kiefernring"}, {track = "hochwald"}, {track = "valle_club"},
			{track = "brackenmoor"}, {track = "schneekopf"}, {track = "kuestenstrasse"},
			{track = "altstadt"}, {track = "valtellina"},
		],
	},
]

## Saved state (JSON-friendly), or {} when no championship is running.
static var _state := {}
static var _loaded := false


# ---------------------------------------------------------------- state

static func series(id: String) -> Dictionary:
	for s in SERIES:
		if s.id == id:
			return s
	return SERIES[0]


## The running championship's state (loads it on first use). {} if none.
static func state() -> Dictionary:
	if not _loaded:
		_loaded = true
		var d = ModeStore.load_json(FILE)
		_state = d if d is Dictionary and d.has("series") else {}
	return _state


static func active() -> bool:
	return not state().is_empty()


static func complete() -> bool:
	return active() and bool(_state.get("complete", false))


## Starts a new championship (replacing any saved one) with a fixed field.
static func start(series_id: String, difficulty: int, laps: int, opponents: int) -> void:
	var drivers := [{name = Game.player_name, bot = false, car = Game.car_id, paint = Game.paint_index,
		points = 0, wins = 0, results = []}]
	var names := Game.BOT_NAMES.duplicate()
	names.shuffle()
	var ids: Array = CarCatalog.available_ids()
	for i in opponents:
		var paint := i + int(i >= Game.paint_index) # never the player's colour
		drivers.append({name = names[i % names.size()], bot = true,
			car = ids[(i + 1) % ids.size()] if not ids.is_empty() else CarCatalog.DEFAULT,
			paint = paint % CarPalette.COLORS.size(), points = 0, wins = 0, results = []})
	_state = {series = series_id, difficulty = difficulty, laps = laps, round = 0,
		complete = false, drivers = drivers, last = []}
	_loaded = true
	save()


static func save() -> void:
	ModeStore.save_json(FILE, _state)


static func abandon() -> void:
	_state = {}
	_loaded = true
	ModeStore.remove(FILE)


static func rounds() -> Array:
	return series(str(state().get("series", ""))).rounds


static func round_index() -> int:
	return int(state().get("round", 0))


## The round to race next (or the last one once complete).
static func current_round() -> Dictionary:
	var r := rounds()
	return r[clampi(round_index(), 0, r.size() - 1)]


## Weather of a round: its own, else the track's.
static func round_weather(r: Dictionary) -> int:
	return int(r.get("weather", TrackDefs.get_track(r.track).get("weather", 0)))


## Driver indices sorted by points (then wins, then best finishes), leader first.
static func order() -> Array:
	var d: Array = state().get("drivers", [])
	var idx := range(d.size())
	idx.sort_custom(func(a: int, b: int) -> bool:
		if int(d[a].points) != int(d[b].points):
			return int(d[a].points) > int(d[b].points)
		if int(d[a].wins) != int(d[b].wins):
			return int(d[a].wins) > int(d[b].wins)
		return _best_finish(d[a]) < _best_finish(d[b]) if _best_finish(d[a]) != _best_finish(d[b]) else a < b)
	return idx


static func _best_finish(drv: Dictionary) -> int:
	var best := 99
	for p in drv.results:
		best = mini(best, int(p))
	return best


## Grid for the next round: reverse championship order, leader at the back.
## Round one (all level): the player starts last.
static func grid() -> Array:
	var d: Array = state().drivers
	var slots: Array = []
	if round_index() == 0:
		for i in range(1, d.size()):
			slots.append(i)
		slots.append(0)
	else:
		slots = order()
		slots.reverse()
	var out := []
	for i in slots:
		var drv: Dictionary = d[i]
		out.append({peer = 1, name = drv.name, bot = drv.bot, car = drv.car, paint = int(drv.paint), driver = i})
	return out


## Applies a finished round: `finish` = driver indices in finishing order.
static func record(finish: Array) -> void:
	var d: Array = state().drivers
	var last := []
	for pos in finish.size():
		var drv: Dictionary = d[finish[pos]]
		var pts: int = POINTS[pos] if pos < POINTS.size() else 0
		drv.points = int(drv.points) + pts
		if pos == 0:
			drv.wins = int(drv.wins) + 1
		drv.results.append(pos + 1)
		last.append({driver = finish[pos], pos = pos + 1, pts = pts})
	_state.last = last
	_state.round = round_index() + 1
	if _state.round >= rounds().size():
		_state.complete = true
	save()


# ---------------------------------------------------------------- race controller

var _slot_driver: Array = [] ## grid slot -> driver index
var _points := {} ## entry -> points scored this round
var _recorded := false


func setup_overrides() -> Dictionary:
	var st := state()
	var r := current_round()
	var drv: Dictionary = st.drivers[0]
	var g := grid()
	for info in g:
		_slot_driver.append(info.driver)
	return {
		track = r.track,
		laps = int(st.laps),
		grid = g,
		game = {difficulty = int(st.difficulty), car_id = drv.car, paint_index = int(drv.paint),
			weather_override = int(r.get("weather", -1))},
	}


func attach(_race: Node) -> void:
	super(_race)
	race.race_finished.connect(_on_finished)


func _on_finished() -> void:
	if _recorded or complete():
		return
	_recorded = true
	var finish := []
	for e in race.standings():
		var slot: int = race.entries.find(e)
		if slot >= 0 and slot < _slot_driver.size():
			finish.append(_slot_driver[slot])
	for pos in race.standings().size():
		_points[race.standings()[pos]] = POINTS[pos] if pos < POINTS.size() else 0
	record(finish)
	if ModeStore.args().has("allbots"):
		print_standings()


static func print_standings() -> void:
	var st := state()
	print("CHAMPIONSHIP %s  round %d/%d%s" % [series(st.series).name, round_index(), rounds().size(),
		"  COMPLETE" if complete() else ""])
	var n := 1
	for i in order():
		var drv: Dictionary = st.drivers[i]
		print("  %d. %-14s %3d pts  wins %d  %s" % [n, drv.name, int(drv.points), int(drv.wins), str(drv.results.map(func(x): return int(x)))])
		n += 1


func results_subtitle() -> String:
	var r: int = round_index() if not _recorded else round_index() - 1
	return "%s  ·  ROUND %d OF %d  ·  %s" % [str(series(state().series).name).to_upper(), r + 1,
		rounds().size(), str(race.circuit.def.get("name", "")).to_upper()]


func results_buttons(parent: Control, make: Callable) -> bool:
	if complete():
		make.call(parent, "Final standings", _to_menu)
	else:
		make.call(parent, "Next race", _next_race)
		make.call(parent, "Standings", _to_menu)
	return true


func points_for(entry) -> int:
	return _points.get(entry, 0) if _recorded else -1


func _next_race() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	Game.menu_screen = "championship"
	race.quit_to_menu()
