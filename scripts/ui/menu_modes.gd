class_name MenuModes
extends RefCounted
## Menu screens for the single-player modes: Time Trial setup, Championship
## setup, the standings hub between rounds and the final podium. Built with the
## menu's own layout helpers (menu.gd) and MenuWidgets, so they look the same.

var m: Control ## menu.gd


func _init(menu: Control) -> void:
	m = menu


# ---------------------------------------------------------------- shared

## Circuit cards along the bottom; `on_choose(card)` when one is focused / clicked.
## Non-interactive when `on_choose` is invalid (championship calendar).
func _track_strip(scr: Control, tracks: Array, on_choose: Callable, activate: Callable) -> Array[MenuWidgets.TrackCard]:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scroll.offset_left = m.MARGIN
	scroll.offset_right = -m.MARGIN
	scroll.offset_top = -100 - 176
	scroll.offset_bottom = -100
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	scr.add_child(scroll)
	var strip := HBoxContainer.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	strip.add_theme_constant_override("separation", 12)
	scroll.add_child(strip)
	var cards: Array[MenuWidgets.TrackCard] = []
	for t in tracks:
		var card := MenuWidgets.TrackCard.new(t)
		strip.add_child(card)
		cards.append(card)
		if on_choose.is_valid():
			card.chosen.connect(func():
				for c in cards:
					c.selected = c == card
				on_choose.call(card))
			if activate.is_valid():
				card.activated.connect(activate)
		else:
			card.focus_mode = Control.FOCUS_NONE
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cards


## Right-aligned info block, top right: eyebrow, big name, meta line, blurb.
func _info(scr: Control, eyebrow: String) -> Array[Label]:
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -m.MARGIN - 560
	info.offset_right = -m.MARGIN
	info.offset_top = 76
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.add_theme_constant_override("separation", 2)
	scr.add_child(info)
	var labels: Array[Label] = [
		UiTheme.caption(info, eyebrow, 13, UiTheme.AMBER, 2, 6),
		UiTheme.caption(info, "", 40, Color.WHITE, 2, 5),
		UiTheme.caption(info, "", 15, UiTheme.TEXT, 1, 3),
	]
	m._gap(info, 8)
	var blurb := UiTheme.caption(info, "", 17, UiTheme.DIM, 0, 0)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	labels.append(blurb)
	for l in labels:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return labels


func _launch(session: int) -> void:
	Game.save_settings()
	Game.mode = Game.Mode.SINGLE
	Game.session = session
	Game.grid = []
	m._fade_out(func(): m.get_tree().change_scene_to_file("res://scenes/race.tscn"))


# ---------------------------------------------------------------- time trial

func show_time_trial() -> void:
	var scr: Control = m._begin("timetrial")
	var box: VBoxContainer = m._column(scr, 540)
	m._header(box, "Time Trial", "Just you, the clock and the ghost of your best lap.")
	var lap_opts := [0, 3, 5, 10]
	var lap_names := ["Unlimited", "3 laps", "5 laps", "10 laps"]
	var r_laps := MenuWidgets.Choice.new("Laps", lap_names, maxi(lap_opts.find(Game.tt_laps), 0))
	r_laps.changed.connect(func(i): Game.tt_laps = lap_opts[i])
	box.add_child(r_laps)
	var wx := ["Track default"]
	wx.append_array(Weather.NAMES)
	var r_wx := MenuWidgets.Choice.new("Weather", wx, Game.weather_override + 1, true)
	r_wx.changed.connect(func(i): Game.weather_override = i - 1)
	box.add_child(r_wx)
	var r_ghost := MenuWidgets.Choice.new("Ghost car", ["Off", "On"], int(Game.tt_ghost), true)
	r_ghost.changed.connect(func(i): Game.tt_ghost = i == 1)
	box.add_child(r_ghost)
	var r_assist := MenuWidgets.Choice.new("Driving assists", ["Off", "On"], int(Game.assists), true)
	r_assist.changed.connect(func(i): Game.assists = i == 1)
	box.add_child(r_assist)
	var r_car: Control = m._car_choice()
	box.add_child(r_car)
	var r_paint := MenuWidgets.Paint.new(Game.paint_index)
	r_paint.changed.connect(m._set_paint)
	box.add_child(r_paint)
	m._gap(box, 22)
	var row: HBoxContainer = m._buttons(box)
	var go := MenuWidgets.button("Start Session", true, 260)
	go.pressed.connect(_launch.bind(Game.Session.TIME_TRIAL))
	row.add_child(go)
	var back := MenuWidgets.button("Back", false, 140)
	back.pressed.connect(m._show_home)
	row.add_child(back)

	var info := _info(scr, "CIRCUIT")
	var pb := UiTheme.caption(info[0].get_parent(), "", 22, UiTheme.AMBER, 2, 3)
	pb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var refresh := func():
		var t := TrackDefs.get_track(Game.track_id)
		var best := TimeTrial.best_lap(Game.track_id, Game.car_id)
		info[1].text = str(t.name).to_upper()
		info[2].text = "%s   ·   %s" % [str(Weather.NAMES[t.get("weather", 0)]).to_upper(), CarCatalog.display_name(Game.car_id).to_upper()]
		info[3].text = t.get("blurb", "")
		pb.text = "PERSONAL BEST   %s" % RaceHud.fmt_time(best) if best < INF else "NO TIME SET YET"
	r_car.changed.connect(func(_i): refresh.call())
	var choose := func(card: MenuWidgets.TrackCard):
		Game.track_id = card.track.id
		refresh.call()
	var cards := _track_strip(scr, TrackDefs.TRACKS, choose, go.emit_signal.bind("pressed"))
	var selected: MenuWidgets.TrackCard = cards[0]
	for c in cards:
		if c.track.id == Game.track_id:
			selected = c
	selected.chosen.emit()
	m._present(scr, m.FRAME_SETUP, r_laps)
	await m.get_tree().process_frame
	if is_instance_valid(go):
		_wire_focus(go, back, cards, selected, r_laps)


## Rows ↕, buttons ↓ into the cards, cards ↑ back to the start button.
func _wire_focus(go: Control, back: Control, cards: Array, selected: Control, first_row: Control) -> void:
	for b in [go, back]:
		b.focus_neighbor_bottom = b.get_path_to(selected)
	for c in cards:
		c.focus_neighbor_top = c.get_path_to(go)
		c.focus_neighbor_bottom = c.get_path()
	go.focus_neighbor_right = go.get_path_to(back)
	back.focus_neighbor_left = back.get_path_to(go)
	first_row.focus_neighbor_top = first_row.get_path_to(selected)


# ---------------------------------------------------------------- championship

## Home entry: continue a running championship, its podium, or set one up.
func show_championship() -> void:
	if Championship.complete():
		show_podium()
	elif Championship.active():
		show_hub()
	else:
		show_champ_setup()


func show_champ_setup() -> void:
	var scr: Control = m._begin("champ_setup")
	var box: VBoxContainer = m._column(scr, 540)
	m._header(box, "Championship", "A season against the same field. Points decide the title.")
	var names := []
	for s in Championship.SERIES:
		names.append(s.name)
	var pick := {series = 0, difficulty = Game.difficulty, laps = clampi(Game.laps, 1, 10), opponents = 7}
	var r_series := MenuWidgets.Choice.new("Series", names, 0, true)
	box.add_child(r_series)
	var r_diff := MenuWidgets.Choice.new("Difficulty", Game.DIFFICULTY_NAMES, pick.difficulty)
	r_diff.changed.connect(func(i): pick.difficulty = i)
	box.add_child(r_diff)
	var laps := []
	for i in range(1, 11):
		laps.append("%d lap%s" % [i, "" if i == 1 else "s"])
	var r_laps := MenuWidgets.Choice.new("Race length", laps, pick.laps - 1)
	r_laps.changed.connect(func(i): pick.laps = i + 1)
	box.add_child(r_laps)
	var opp := []
	for i in range(3, 8):
		opp.append(str(i))
	var r_opp := MenuWidgets.Choice.new("Opponents", opp, pick.opponents - 3)
	r_opp.changed.connect(func(i): pick.opponents = i + 3)
	box.add_child(r_opp)
	var r_assist := MenuWidgets.Choice.new("Driving assists", ["Off", "On"], int(Game.assists), true)
	r_assist.changed.connect(func(i): Game.assists = i == 1)
	box.add_child(r_assist)
	box.add_child(m._car_choice())
	var r_paint := MenuWidgets.Paint.new(Game.paint_index)
	r_paint.changed.connect(m._set_paint)
	box.add_child(r_paint)
	m._gap(box, 22)
	var row: HBoxContainer = m._buttons(box)
	var go := MenuWidgets.button("Start Championship", true, 300)
	go.pressed.connect(func():
		Championship.start(Championship.SERIES[pick.series].id, pick.difficulty, pick.laps, pick.opponents)
		m._set_message("")
		show_hub())
	row.add_child(go)
	var back := MenuWidgets.button("Back", false, 140)
	back.pressed.connect(func(): m._set_message(""); m._show_home())
	row.add_child(back)

	var info := _info(scr, "SERIES")
	var cal := VBoxContainer.new()
	cal.add_theme_constant_override("separation", 0)
	info[0].get_parent().add_child(cal)
	var strip_holder := Control.new()
	strip_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(strip_holder)
	var show_series := func(i: int):
		pick.series = i
		var s: Dictionary = Championship.SERIES[i]
		info[1].text = str(s.name).to_upper()
		info[2].text = "%d ROUNDS" % s.rounds.size()
		info[3].text = s.blurb
		for c in cal.get_children():
			c.queue_free()
		m._gap(cal, 10)
		var tracks := []
		for k in s.rounds.size():
			var r: Dictionary = s.rounds[k]
			var t := TrackDefs.get_track(r.track)
			tracks.append(t)
			var l := UiTheme.caption(cal, "R%d   %s   ·   %s" % [k + 1, str(t.name).to_upper(),
				str(Weather.NAMES[Championship.round_weather(r)]).to_upper()], 14, UiTheme.TEXT, 1, 2)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for c in strip_holder.get_children():
			c.queue_free()
		_track_strip(strip_holder, tracks.slice(0, 8), Callable(), Callable())
	r_series.changed.connect(show_series)
	show_series.call(0)
	if Championship.active():
		m._set_message("Starting a new championship replaces your saved one.")
	m._present(scr, m.FRAME_SETUP, r_series)


## Between rounds: the drivers' table, the next round, race / abandon.
func show_hub() -> void:
	var scr: Control = m._begin("championship")
	var st := Championship.state()
	var s := Championship.series(st.series)
	var rn := Championship.round_index()
	var box: VBoxContainer = m._column(scr, 660)
	m._header(box, s.name, "Round %d of %d   ·   %s   ·   %d laps" % [rn + 1, s.rounds.size(),
		Game.DIFFICULTY_NAMES[int(st.difficulty)], int(st.laps)])
	UiTheme.caption(box, "DRIVERS' STANDINGS", 13, UiTheme.DIM, 2, 4)
	m._gap(box, 8)
	box.add_child(StandingsTable.new())
	m._gap(box, 26)
	var row: HBoxContainer = m._buttons(box)
	var go := MenuWidgets.button("Race round %d" % (rn + 1), true, 260)
	go.pressed.connect(_launch.bind(Game.Session.CHAMPIONSHIP))
	row.add_child(go)
	var quit := MenuWidgets.button("Abandon", false, 160)
	quit.pressed.connect(func():
		if quit.text != "CONFIRM":
			quit.text = "CONFIRM"
			m._set_message("Press again to abandon this championship.")
			return
		Championship.abandon()
		m._set_message("")
		show_champ_setup())
	row.add_child(quit)
	var back := MenuWidgets.button("Back", false, 140)
	back.pressed.connect(m._show_home)
	row.add_child(back)

	var r := Championship.current_round()
	var t := TrackDefs.get_track(r.track)
	var info := _info(scr, "NEXT ROUND")
	info[1].text = str(t.name).to_upper()
	var km := TrackBuilder.make_curve(t.points).get_baked_length() / 1000.0
	info[2].text = "%s   ·   %s   ·   %d LAPS" % [Game.distance_text(km), str(Weather.NAMES[Championship.round_weather(r)]).to_upper(), int(st.laps)]
	info[3].text = t.get("blurb", "")
	var last: Array = st.get("last", [])
	if not last.is_empty():
		var d: Array = st.drivers
		var mine := 0
		for x in last:
			if int(x.driver) == 0:
				mine = int(x.pos)
		var l := UiTheme.caption(info[0].get_parent(), "LAST ROUND: %s WON  ·  YOU FINISHED P%d" % [
			str(d[int(last[0].driver)].name).to_upper(), mine], 14, UiTheme.AMBER, 1, 2)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Calendar: done rounds dimmed, the next one in amber.
	m._gap(info[0].get_parent(), 14)
	for k in s.rounds.size():
		var x: Dictionary = s.rounds[k]
		var cl := UiTheme.caption(info[0].get_parent(), "R%d   %s   ·   %s" % [k + 1, str(TrackDefs.get_track(x.track).name).to_upper(),
			str(Weather.NAMES[Championship.round_weather(x)]).to_upper()], 14,
			UiTheme.AMBER if k == rn else (UiTheme.FAINT if k < rn else UiTheme.TEXT), 1, 2)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	m._present(scr, m.FRAME_PANEL, go)


## Season over: the champion, a podium, the final table.
func show_podium() -> void:
	var scr: Control = m._begin("podium")
	var st := Championship.state()
	var s := Championship.series(st.series)
	var order := Championship.order()
	var champ: Dictionary = st.drivers[order[0]]
	var box: VBoxContainer = m._column(scr, 660)
	m._header(box, "Champion", "%s   ·   %s   ·   final standings" % [s.name, Game.DIFFICULTY_NAMES[int(st.difficulty)]])
	var you := order.find(0)
	var line := "You are the %s champion!" % s.name if you == 0 else "You finished the season P%d." % (you + 1)
	UiTheme.caption(box, str(champ.name).to_upper(), 34, UiTheme.AMBER, 2, 4)
	UiTheme.caption(box, line, 17, UiTheme.TEXT, 0, 0)
	m._gap(box, 18)
	box.add_child(Podium.new())
	m._gap(box, 14)
	box.add_child(StandingsTable.new())
	m._gap(box, 22)
	var row: HBoxContainer = m._buttons(box)
	var again := MenuWidgets.button("New Championship", true, 300)
	again.pressed.connect(func():
		Championship.abandon()
		show_champ_setup())
	row.add_child(again)
	var back := MenuWidgets.button("Home", false, 140)
	back.pressed.connect(m._show_home)
	row.add_child(back)
	m._present(scr, m.FRAME_PANEL, again)


## Drivers' table: position, driver + car, each round's finish, wins, points.
class StandingsTable:
	extends Control
	const ROW_H := 40.0
	const HEAD_H := 26.0
	const X_ROUNDS := 272.0
	const RW := 28.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(660, HEAD_H + Championship.state().drivers.size() * ROW_H)

	func _draw() -> void:
		var st := Championship.state()
		var d: Array = st.drivers
		var n_rounds := Championship.rounds().size()
		var w := size.x
		var f := UiTheme.font(1, 2)
		var fb := UiTheme.font(2, 1)
		draw_string(f, Vector2(12, 16), "POS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.DIM)
		draw_string(f, Vector2(62, 16), "DRIVER", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.DIM)
		for k in n_rounds:
			draw_string(f, Vector2(X_ROUNDS + k * RW, 16), "R%d" % (k + 1), HORIZONTAL_ALIGNMENT_CENTER, RW, 11, UiTheme.DIM)
		draw_string(f, Vector2(w - 150, 16), "WINS", HORIZONTAL_ALIGNMENT_RIGHT, 60, 11, UiTheme.DIM)
		draw_string(f, Vector2(w - 76, 16), "PTS", HORIZONTAL_ALIGNMENT_RIGHT, 60, 11, UiTheme.DIM)
		draw_rect(Rect2(0, HEAD_H - 4, w, 1), Color(1, 1, 1, 0.1))
		var order := Championship.order()
		for i in order.size():
			var drv: Dictionary = d[order[i]]
			var me: bool = order[i] == 0
			var y := HEAD_H + i * ROW_H
			if me:
				draw_rect(Rect2(0, y + 2, w, ROW_H - 4), Color(1, 0.72, 0.25, 0.12))
				draw_rect(Rect2(0, y + 2, 3, ROW_H - 4), UiTheme.AMBER)
			elif i % 2 == 1:
				draw_rect(Rect2(0, y + 2, w, ROW_H - 4), Color(1, 1, 1, 0.03))
			draw_string(fb, Vector2(12, y + 28), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
				UiTheme.AMBER if i == 0 or me else UiTheme.TEXT)
			draw_rect(Rect2(50, y + 10, 3, ROW_H - 20), CarPalette.pick(int(drv.paint)).lightened(0.2))
			draw_string(fb, Vector2(62, y + 21), str(drv.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200, 17,
				UiTheme.AMBER if me else UiTheme.TEXT)
			draw_string(UiTheme.font(0, 1), Vector2(62, y + 35), CarCatalog.display_name(drv.car), HORIZONTAL_ALIGNMENT_LEFT, 200, 11, UiTheme.DIM)
			var res: Array = drv.results
			for k in n_rounds:
				var txt := str(int(res[k])) if k < res.size() else "·"
				var col := UiTheme.FAINT
				if k < res.size():
					col = UiTheme.AMBER if int(res[k]) == 1 else UiTheme.TEXT
				draw_string(f, Vector2(X_ROUNDS + k * RW, y + 26), txt, HORIZONTAL_ALIGNMENT_CENTER, RW, 15, col)
			draw_string(f, Vector2(w - 150, y + 26), str(int(drv.wins)), HORIZONTAL_ALIGNMENT_RIGHT, 60, 15, UiTheme.TEXT)
			draw_string(fb, Vector2(w - 76, y + 27), str(int(drv.points)), HORIZONTAL_ALIGNMENT_RIGHT, 60, 20,
				UiTheme.AMBER if me else Color.WHITE)


## Three steps: 2nd, 1st, 3rd, with names and points.
class Podium:
	extends Control

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(660, 170)

	func _draw() -> void:
		var st := Championship.state()
		var order := Championship.order()
		var bw := 180.0
		var gap := 14.0
		var x0 := (size.x - bw * 3 - gap * 2) * 0.5
		var heights := [110.0, 80.0, 58.0] # P1, P2, P3
		var slots := [1, 0, 2] # left to right: P2, P1, P3
		for k in 3:
			var p: int = slots[k]
			if p >= order.size():
				continue
			var drv: Dictionary = st.drivers[order[p]]
			var h: float = heights[p]
			var x := x0 + k * (bw + gap)
			var top := size.y - h
			draw_rect(Rect2(x, top, bw, h), Color(UiTheme.AMBER, 0.22) if p == 0 else Color(1, 1, 1, 0.1 if p == 1 else 0.07))
			draw_rect(Rect2(x, top, bw, 2), UiTheme.AMBER if p == 0 else Color(1, 1, 1, 0.35))
			draw_string(UiTheme.font(2, 2), Vector2(x, top + h * 0.5 + 16), str(p + 1), HORIZONTAL_ALIGNMENT_CENTER, bw, 40,
				UiTheme.AMBER if p == 0 else UiTheme.TEXT)
			draw_rect(Rect2(x + bw * 0.5 - 20, top - 50, 40, 3), CarPalette.pick(int(drv.paint)).lightened(0.2))
			draw_string(UiTheme.font(2, 1), Vector2(x, top - 24), str(drv.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, bw, 17,
				Color.WHITE if order[p] != 0 else UiTheme.AMBER)
			draw_string(UiTheme.font(1, 2), Vector2(x, top - 7), "%d PTS" % int(drv.points), HORIZONTAL_ALIGNMENT_CENTER, bw, 12, UiTheme.DIM)
