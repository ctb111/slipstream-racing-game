extends Control
## Main menu over a live 3D showroom: home, quick race / host setup, join a
## LAN race, lobby and settings. Screens fade between each other; the car on
## the turntable wears the player's chosen paint.

const BASE_SIZE := Vector2i(1600, 900)
const MARGIN := 80.0
## Camera lens offset per screen: moves the car to the free side of the UI.
const FRAME_HOME := Vector2(-1.3, 0.1)
const FRAME_SETUP := Vector2(-1.75, -0.3)
const FRAME_PANEL := Vector2(-1.9, 0.0)

var _showroom: Showroom
var _layer: Control
var _screen: Control
var _fade: ColorRect
var _message: Label
var _car_line: Label
var _car_name: Label
var _server_box: VBoxContainer
var _server_sig := ""
var _server_ips: Array[String] = []
var _lobby_players: VBoxContainer
var _lobby_info: Label
var _lobby_track: Label
var _current := ""
var _leaving := false
var _prev_scale := []
var _modes: MenuModes ## championship / time trial screens
var _credits: MenuCredits
var _settings_tab := 0 ## last settings tab, reopened next time


func _ready() -> void:
	theme = UiTheme.get_theme()
	# Mechanical click / hover sounds on every button, including ones added later.
	get_tree().node_added.connect(func(n: Node) -> void:
		if n is BaseButton and is_ancestor_of(n):
			UiSounds.wire.call_deferred(n.get_parent()))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Lay the menu out for 1600x900 and scale it to the window (3D stays native).
	var win := get_window()
	_prev_scale = [win.content_scale_mode, win.content_scale_aspect, win.content_scale_size]
	win.content_scale_size = BASE_SIZE
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	Game.apply_viewport_quality(get_viewport())

	_modes = MenuModes.new(self)
	_credits = MenuCredits.new(self)
	_showroom = Showroom.new()
	add_child(_showroom)
	_build_shade()
	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_build_footer()
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.9).set_delay(0.15).set_trans(Tween.TRANS_SINE)

	Net.lobby_changed.connect(_refresh_lobby)
	Net.servers_changed.connect(_refresh_servers)
	Net.disconnected.connect(func(reason: String): _set_message(reason); _show_home())
	if Game.pending_message != "":
		_set_message(Game.pending_message)
		Game.pending_message = ""
	# Coming back from an online race: straight to the lobby.
	if Game.mode != Game.Mode.SINGLE and multiplayer.has_multiplayer_peer():
		_show_lobby()
	elif Game.menu_screen == "championship": # back from a championship round
		_modes.show_championship()
	else:
		_show_home()
	Game.menu_screen = ""
	_debug_screen()
	_debug_autostart()


func _exit_tree() -> void:
	var win := get_window()
	if win and _prev_scale.size() == 3:
		win.content_scale_mode = _prev_scale[0]
		win.content_scale_aspect = _prev_scale[1]
		win.content_scale_size = _prev_scale[2]


## Debug: `-- --nethost --wait=N` hosts and starts once N players joined;
## `-- --netjoin=<ip>` joins. Used for automated two-instance network tests.
func _debug_autostart() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--name="):
			Game.player_name = arg.trim_prefix("--name=")
	for arg in args:
		if arg == "--nethost":
			var wait := 2
			for a in args:
				if a.begins_with("--wait="):
					wait = a.trim_prefix("--wait=").to_int()
			Game.bots = 2
			Game.laps = 1
			Game.track_id = "valle_club"
			for a in args:
				if a.begins_with("--weather="): # e.g. 7 = changeable, sent to the client via the lobby
					Game.weather_override = a.trim_prefix("--weather=").to_int()
			_start_host()
			while Net.players.size() < wait:
				await get_tree().create_timer(0.2).timeout
			print("host: %d players, starting" % Net.players.size())
			Net.start_race()
		elif arg.begins_with("--netjoin="):
			_join(arg.trim_prefix("--netjoin="))


## Debug: `-- --menu_screen=setup|host|join|settings|credits|lobby|timetrial|championship|champ_setup`
## opens a screen directly (screenshots).
func _debug_screen() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings_tab="):
			_settings_tab = arg.trim_prefix("--settings_tab=").to_int()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu_screen="):
			match arg.trim_prefix("--menu_screen="):
				"setup": _show_setup(false)
				"host": _show_setup(true)
				"join": _show_join()
				"settings": _show_settings()
				"credits": _credits.show_credits()
				"lobby": _start_host()
				"timetrial": _modes.show_time_trial()
				"championship": _modes.show_championship()
				"champ_setup": _modes.show_champ_setup()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and not _leaving:
		accept_event()
		if _current == "lobby":
			Net.leave()
			_show_home()
		elif _current != "home":
			_update_car_line() # units may have changed in settings
			_show_home()


# ---------------------------------------------------------------- frame

## Dark wash on the left third and along the bottom so text reads over the car.
func _build_shade() -> void:
	var left := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.22, 0.5, 0.72])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.78), Color(0, 0, 0, 0.3), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	left.texture = gt
	left.stretch_mode = TextureRect.STRETCH_SCALE
	left.set_anchors_preset(Control.PRESET_FULL_RECT)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	var bottom := TextureRect.new()
	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g2.colors = PackedColorArray([Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), Color(0, 0, 0, 0.75)])
	var gt2 := GradientTexture2D.new()
	gt2.gradient = g2
	gt2.width = 4
	gt2.height = 256
	gt2.fill_to = Vector2(0, 1)
	bottom.texture = gt2
	bottom.stretch_mode = TextureRect.STRETCH_SCALE
	bottom.set_anchors_preset(Control.PRESET_FULL_RECT)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)


## Key hints bottom-left, status message, the car's name bottom-right.
func _build_footer() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = MARGIN
	row.offset_right = -MARGIN
	row.offset_top = -62
	row.offset_bottom = -30
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	for pair in [["ARROWS", "NAVIGATE"], ["ENTER", "SELECT"], ["ESC", "BACK"]]:
		var key := UiTheme.caption(row, pair[0], 12, UiTheme.TEXT, 2, 2)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(1, 1, 1, 0.3)
		sb.set_border_width_all(1)
		sb.content_margin_left = 7
		sb.content_margin_right = 7
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		key.add_theme_stylebox_override("normal", sb)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var act := UiTheme.caption(row, pair[1], 12, UiTheme.DIM, 1, 3)
		act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_message = UiTheme.caption(row, "", 15, UiTheme.AMBER, 1, 1)
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var car := VBoxContainer.new()
	car.add_theme_constant_override("separation", 0)
	car.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(car)
	_car_name = UiTheme.caption(car, "", 17, UiTheme.TEXT, 2, 4)
	_car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_car_line = UiTheme.caption(car, "", 12, UiTheme.DIM, 1, 3)
	_car_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_update_car_line()


func _update_car_line() -> void:
	var spec := CarCatalog.get_car(Game.car_id)
	_car_name.text = str(spec.get("name", "")).to_upper()
	var top: int = spec.get("physics", {}).get("top_speed_kmh", 0)
	_car_line.text = "%d  ·  %d %s  ·  %s" % [spec.get("year", 0), roundi(Game.speed_units(top / 3.6)), Game.speed_label(),
		str(MenuWidgets.PAINT_NAMES[Game.paint_index % MenuWidgets.PAINT_NAMES.size()]).to_upper()]


## "Car" selector row: every car in the catalog whose model is present.
func _car_choice() -> Control:
	var ids: Array = CarCatalog.available_ids()
	var names := []
	for id in ids:
		names.append(CarCatalog.display_name(id))
	var row := MenuWidgets.Choice.new("Car", names, maxi(ids.find(Game.car_id), 0), true)
	row.changed.connect(func(i): _set_car(ids[i]))
	return row


func _set_car(id: String) -> void:
	Game.car_id = id
	Net.update_car(id)
	_showroom.set_car(id)
	_showroom.set_paint(CarPalette.pick(Game.paint_index))
	_update_car_line()
	Game.save_settings()


func _set_message(text: String) -> void:
	_message.text = text
	if text != "":
		_message.modulate.a = 0.0
		create_tween().tween_property(_message, "modulate:a", 1.0, 0.3)


func _set_paint(i: int) -> void:
	Game.paint_index = i
	Net.update_paint(i)
	_showroom.set_paint(CarPalette.pick(i))
	_update_car_line()
	Game.save_settings()


# ---------------------------------------------------------------- screens

## Starts a new screen: stops LAN scanning and forgets the old screen's lists.
func _begin(id: String) -> Control:
	Net.stop_scan()
	_server_box = null
	_server_sig = ""
	_lobby_players = null
	_current = id
	var scr := Control.new()
	scr.set_anchors_preset(Control.PRESET_FULL_RECT)
	scr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return scr


## Cross-fades to `scr` and moves the camera framing.
func _present(scr: Control, framing: Vector2, focus: Control) -> void:
	_showroom.set_framing(framing, _screen == null)
	if _screen:
		var old := _screen
		_disable(old)
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.14)
		tw.tween_callback(old.queue_free)
	_screen = scr
	scr.modulate.a = 0.0
	scr.position.x = -16.0
	_layer.add_child(scr)
	var tw := scr.create_tween().set_parallel()
	tw.tween_property(scr, "modulate:a", 1.0, 0.32).set_delay(0.1)
	tw.tween_property(scr, "position:x", 0.0, 0.45).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if focus:
		_focus_later.call_deferred(focus)


func _focus_later(c: Control) -> void:
	if is_instance_valid(c) and c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
		c.grab_focus()


func _disable(n: Node) -> void:
	if n is Control:
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.focus_mode = Control.FOCUS_NONE
	for c in n.get_children():
		_disable(c)


## Left column of a screen.
func _column(scr: Control, width: float, top := 72.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.anchor_bottom = 1.0
	box.offset_left = MARGIN
	box.offset_top = top
	box.offset_right = MARGIN + width
	box.offset_bottom = -100
	box.add_theme_constant_override("separation", 0)
	scr.add_child(box)
	return box


## Eyebrow + big title + one line of explanation.
func _header(box: Control, title: String, sub: String) -> void:
	UiTheme.caption(box, "SLIPSTREAM", 13, UiTheme.AMBER, 2, 6)
	_gap(box, 4)
	UiTheme.caption(box, title.to_upper(), 46, Color.WHITE, 2, 5)
	if sub != "":
		UiTheme.caption(box, sub, 17, UiTheme.DIM, 0, 0)
	_gap(box, 26)


func _gap(box: Control, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)
	return c


func _buttons(box: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	return row


# ---------------------------------------------------------------- home

func _show_home() -> void:
	var scr := _begin("home")
	var box := _column(scr, 520, 0)
	box.offset_bottom = -110
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	UiTheme.caption(box, "SLIPSTREAM", 96, Color.WHITE, 2, 14)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	box.add_child(line)
	var bar := ColorRect.new()
	bar.color = UiTheme.AMBER
	bar.custom_minimum_size = Vector2(46, 2)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(bar)
	UiTheme.caption(line, "CLASSIC SPORTS CAR RACING", 15, UiTheme.TEXT, 1, 6)
	_gap(box, 58)
	var hint := UiTheme.caption(box, "", 15, UiTheme.DIM, 0, 1)
	var items := [
		["Quick Race", "Race the clock and the field on any circuit.", _show_setup.bind(false)],
		["Championship", "A season of rounds against the same field. Points win titles.", _modes.show_championship],
		["Time Trial", "Solo laps against your best, chased by its ghost.", _modes.show_time_trial],
		["Host LAN Race", "Open a lobby friends on your network can join.", _show_setup.bind(true)],
		["Join LAN Race", "Find a race on your local network.", _show_join],
		["Settings", "Display, sound, controls and driver name.", _show_settings],
		["Credits", "The people and assets behind the game.", _credits.show_credits],
		["Quit", "Back to the desktop.", func(): _fade_out(func(): get_tree().quit())],
	]
	var first: Control
	for it in items:
		var n := MenuWidgets.NavItem.new(it[0], it[1])
		n.pressed.connect(it[2])
		n.focus_entered.connect(func(): hint.text = n.hint)
		box.add_child(n)
		if first == null:
			first = n
	box.move_child(hint, box.get_child_count() - 1)
	_gap(box, 18)
	box.move_child(hint, box.get_child_count() - 1)
	# Quiet signature, top right.
	var sig := UiTheme.caption(scr, "ORIGINALLY BUILT BY CATALIN", 12, UiTheme.TEXT, 1, 4)
	sig.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sig.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sig.offset_right = -MARGIN
	sig.offset_top = 44
	sig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sig.modulate.a = 0.6
	_present(scr, FRAME_HOME, first)


# ---------------------------------------------------------------- race setup

func _show_setup(hosting: bool) -> void:
	var scr := _begin("host" if hosting else "setup")
	var box := _column(scr, 540)
	_header(box, "Host LAN Race" if hosting else "Quick Race",
		"Set up the lobby, then friends join from their machines." if hosting else "Pick a circuit, set up the field, go.")
	var laps := []
	for i in range(1, 21):
		laps.append("%d lap%s" % [i, "" if i == 1 else "s"])
	var r_laps := MenuWidgets.Choice.new("Laps", laps, Game.laps - 1)
	r_laps.changed.connect(func(i): Game.laps = i + 1)
	box.add_child(r_laps)
	var bots := []
	for i in 8:
		bots.append("None" if i == 0 else str(i))
	var r_bots := MenuWidgets.Choice.new("Bots" if hosting else "Opponents", bots, Game.bots)
	r_bots.changed.connect(func(i): Game.bots = i)
	box.add_child(r_bots)
	var r_diff := MenuWidgets.Choice.new("Difficulty", Game.DIFFICULTY_NAMES, Game.difficulty)
	r_diff.changed.connect(func(i): Game.difficulty = i)
	box.add_child(r_diff)
	var wx := ["Track default"]
	wx.append_array(Weather.NAMES)
	var r_wx := MenuWidgets.Choice.new("Weather", wx, Game.weather_override + 1, true)
	r_wx.changed.connect(func(i): Game.weather_override = i - 1)
	box.add_child(r_wx)
	var r_assist := MenuWidgets.Choice.new("Driving assists", ["Off", "On"], int(Game.assists), true)
	r_assist.changed.connect(func(i): Game.assists = i == 1)
	box.add_child(r_assist)
	box.add_child(_car_choice())
	var r_paint := MenuWidgets.Paint.new(Game.paint_index)
	r_paint.changed.connect(_set_paint)
	box.add_child(r_paint)
	_gap(box, 22)
	var row := _buttons(box)
	var go := MenuWidgets.button("Create Lobby" if hosting else "Start Race", true, 260)
	go.pressed.connect(_start_host if hosting else _start_single)
	row.add_child(go)
	var back := MenuWidgets.button("Back", false, 140)
	back.pressed.connect(_show_home)
	row.add_child(back)

	# Selected circuit, top right.
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -MARGIN - 560
	info.offset_right = -MARGIN
	info.offset_top = 76
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.add_theme_constant_override("separation", 2)
	scr.add_child(info)
	var i_eyebrow := UiTheme.caption(info, "CIRCUIT", 13, UiTheme.AMBER, 2, 6)
	var i_name := UiTheme.caption(info, "", 40, Color.WHITE, 2, 5)
	var i_meta := UiTheme.caption(info, "", 15, UiTheme.TEXT, 1, 3)
	_gap(info, 8)
	var i_blurb := UiTheme.caption(info, "", 17, UiTheme.DIM, 0, 0)
	i_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [i_eyebrow, i_name, i_meta, i_blurb]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Circuit cards along the bottom.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scroll.offset_left = MARGIN
	scroll.offset_right = -MARGIN
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
	var selected: MenuWidgets.TrackCard
	for t in TrackDefs.TRACKS:
		var card := MenuWidgets.TrackCard.new(t)
		strip.add_child(card)
		cards.append(card)
		card.activated.connect(go.emit_signal.bind("pressed"))
		card.chosen.connect(func():
			Game.track_id = card.track.id
			for c in cards:
				c.selected = c == card
			var wk: int = card.track.get("weather", 0)
			i_name.text = str(card.track.name).to_upper()
			i_meta.text = "%s   ·   %s" % [Game.distance_text(card.length_km), str(Weather.NAMES[wk]).to_upper()]
			i_blurb.text = card.track.blurb)
		if selected == null or t.id == Game.track_id:
			selected = card
	selected.chosen.emit()
	_present(scr, FRAME_SETUP, r_laps)
	# Focus: rows ↕, buttons ↓ into the cards, cards ↑ back to the start button.
	await get_tree().process_frame
	if not is_instance_valid(go):
		return
	for b in [go, back]:
		b.focus_neighbor_bottom = b.get_path_to(selected)
	for c in cards:
		c.focus_neighbor_top = c.get_path_to(go)
		c.focus_neighbor_bottom = c.get_path()
	go.focus_neighbor_right = go.get_path_to(back)
	back.focus_neighbor_left = back.get_path_to(go)
	r_laps.focus_neighbor_top = r_laps.get_path_to(selected)


func _start_single() -> void:
	Game.save_settings()
	Game.mode = Game.Mode.SINGLE
	Game.session = Game.Session.RACE
	Game.grid = []
	_fade_out(func(): get_tree().change_scene_to_file("res://scenes/race.tscn"))


func _fade_out(then: Callable) -> void:
	if _leaving:
		return
	_leaving = true
	_disable(_layer)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(then)


func _start_host() -> void:
	Game.save_settings()
	var err := Net.host()
	if err != OK:
		_set_message("Could not host on port %d: %s" % [Net.PORT, error_string(err)])
		return
	_set_message("")
	_show_lobby()


# ---------------------------------------------------------------- join

func _show_join() -> void:
	var scr := _begin("join")
	var box := _column(scr, 640)
	_header(box, "Join LAN Race", "Races hosted on your local network show up here automatically.")
	var status := UiTheme.caption(box, "SCANNING LOCAL NETWORK", 13, UiTheme.AMBER, 2, 4)
	var pulse := status.create_tween().set_loops()
	pulse.tween_property(status, "modulate:a", 0.35, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(status, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	_gap(box, 10)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_server_box = VBoxContainer.new()
	_server_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_server_box)
	_gap(box, 22)
	UiTheme.caption(box, "DIRECT CONNECT", 13, UiTheme.DIM, 2, 4)
	_gap(box, 8)
	var row := _buttons(box)
	var ip := LineEdit.new()
	ip.placeholder_text = "Host IP address, e.g. 192.168.1.20"
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.custom_minimum_size.y = 52
	ip.add_theme_font_size_override("font_size", 19)
	ip.text_submitted.connect(_join)
	row.add_child(ip)
	var direct := MenuWidgets.button("Connect", false, 150)
	direct.pressed.connect(func(): _join(ip.text))
	row.add_child(direct)
	_gap(box, 26)
	var back := MenuWidgets.button("Back", false, 140)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_show_home)
	box.add_child(back)
	Net.start_scan()
	_refresh_servers()
	_present(scr, FRAME_PANEL, ip)


func _refresh_servers() -> void:
	if _server_box == null:
		return
	# Beacons arrive every second; only rebuild when what we show changes (keeps focus).
	var rows := []
	for ip in Net.servers:
		var s: Dictionary = Net.servers[ip]
		rows.append([ip, "%s's race" % s.name, "%s   ·   %d / %d drivers   ·   %s" % [TrackDefs.get_track(s.track).name, s.players, s.max, ip],
			str(s.state).to_upper()])
	var sig := str(rows)
	if sig == _server_sig:
		return
	_server_sig = sig
	var had_focus := _server_box.get_viewport().gui_get_focus_owner() if _server_box.is_inside_tree() else null
	var focus_ip := ""
	if had_focus and had_focus.get_parent() == _server_box:
		focus_ip = had_focus.get_meta("ip", "")
	for c in _server_box.get_children():
		c.queue_free()
	_server_ips.clear()
	for r in rows:
		var row := MenuWidgets.ListRow.new(r[1], r[2], "JOIN  ·  " + r[3] if r[3] == "LOBBY" else r[3])
		row.set_meta("ip", r[0])
		row.pressed.connect(_join.bind(r[0]))
		_server_box.add_child(row)
		_server_ips.append(r[0])
		if r[0] == focus_ip:
			_focus_later.call_deferred(row)
	if _server_ips.is_empty():
		var empty := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.025)
		sb.content_margin_left = 20
		sb.content_margin_top = 18
		sb.content_margin_bottom = 18
		empty.add_theme_stylebox_override("panel", sb)
		_server_box.add_child(empty)
		var l := UiTheme.caption(empty, "No races found yet. The host needs to be on the same network, with Host LAN Race open.", 16, UiTheme.DIM, 0, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _join(ip: String) -> void:
	ip = ip.strip_edges()
	if ip == "":
		return
	var err := Net.join(ip)
	if err != OK:
		_set_message("Could not connect: %s" % error_string(err))
		return
	_set_message("Connecting to %s..." % ip)
	_show_lobby()


# ---------------------------------------------------------------- lobby

func _show_lobby() -> void:
	var scr := _begin("lobby")
	var box := _column(scr, 620)
	var hosting := Game.mode == Game.Mode.HOST
	_header(box, "Lobby", "Your race is open on the local network." if hosting else "Connected. The host starts the race.")
	UiTheme.caption(box, "CIRCUIT", 13, UiTheme.AMBER, 2, 6)
	_lobby_track = UiTheme.caption(box, "", 30, Color.WHITE, 2, 4)
	_lobby_info = UiTheme.caption(box, "", 15, UiTheme.TEXT, 1, 2)
	_gap(box, 22)
	UiTheme.caption(box, "DRIVERS", 13, UiTheme.DIM, 2, 4)
	_gap(box, 8)
	_lobby_players = VBoxContainer.new()
	_lobby_players.add_theme_constant_override("separation", 2)
	box.add_child(_lobby_players)
	_gap(box, 26)
	UiTheme.caption(box, "YOUR CAR", 13, UiTheme.DIM, 2, 4)
	_gap(box, 4)
	box.add_child(_car_choice())
	var paint := MenuWidgets.Paint.new(Game.paint_index)
	paint.changed.connect(_set_paint)
	box.add_child(paint)
	_gap(box, 20)
	var row := _buttons(box)
	var focus: Control
	if hosting:
		var start := MenuWidgets.button("Start Race", true, 260)
		start.pressed.connect(Net.start_race)
		row.add_child(start)
		focus = start
		Net.set_lobby({track = Game.track_id, laps = Game.laps, bots = Game.bots, difficulty = Game.difficulty, weather = Game.weather_override})
	var leave := MenuWidgets.button("Leave", false, 140)
	leave.pressed.connect(func(): Net.leave(); _show_home())
	row.add_child(leave)
	if focus == null:
		focus = leave
	_refresh_lobby()
	_present(scr, FRAME_PANEL, focus)


func _refresh_lobby() -> void:
	if _lobby_players == null:
		return
	var l: Dictionary = Net.lobby
	var track := TrackDefs.get_track(l.track)
	var wk: int = l.get("weather", -1)
	var wname: String = Weather.NAMES[wk] if wk >= 0 else Weather.NAMES[track.get("weather", 0)]
	_lobby_track.text = str(track.name).to_upper()
	_lobby_info.text = ("%s   ·   %d LAPS   ·   %d BOTS (%s)" % [wname, l.laps, l.bots, Game.DIFFICULTY_NAMES[l.difficulty]]).to_upper()
	for c in _lobby_players.get_children():
		c.queue_free()
	if Net.players.is_empty():
		UiTheme.caption(_lobby_players, "Connecting...", 18, UiTheme.DIM, 0, 0)
	var n := 1
	for id in Net.players:
		_lobby_players.add_child(MenuWidgets.PlayerRow.new(n, Net.players[id].name, id == multiplayer.get_unique_id(), id == 1))
		n += 1
	_gap(_lobby_players, 10)
	if Game.mode == Game.Mode.HOST:
		UiTheme.caption(_lobby_players, "Friends on your network can now find this race under Join LAN Race.", 15, UiTheme.DIM, 0, 0)
	elif not Net.players.is_empty():
		_set_message("")
		UiTheme.caption(_lobby_players, "Waiting for the host to start...", 15, UiTheme.DIM, 0, 0)


# ---------------------------------------------------------------- settings

func _show_settings() -> void:
	var scr := _begin("settings")
	var box := _column(scr, 640)
	box.offset_bottom = -90
	_header(box, "Settings", "Saved automatically.")
	var panel := SettingsPanel.new(false, _settings_tab)
	panel.closed.connect(func(): _update_car_line(); _show_home())
	panel.tab_changed.connect(func(t): _settings_tab = t)
	box.add_child(panel)
	_present(scr, FRAME_PANEL, null)
	_focus_later.call_deferred(panel.first_focus())
