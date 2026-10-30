class_name RaceHud
extends CanvasLayer
## Race overlay: timing block, standings tower, minimap, start lights, lap and
## wrong-way messages, pause menu and the results screen.
##
## Debug (after `--`): --hud_force=results|lap|final|wrong shows that element
## one second before --shot_at, for screenshots.

const WRONG_WAY_DELAY := 2.0

var race: Node # race.gd (untyped to avoid a cyclic class reference)

var _root: Control
var _info: HudInfo
var _tower: HudTower
var _map: HudMinimap
var _map_low := false ## minimap moved to the bottom right (cockpit view)
var _lights: HudLights
var _banner: HudBanner
var _results: Control
var _results_table: HudResults
var _pause: Control
var _results_pending := false
var _top_speed := 0.0 ## player's fastest, m/s
var _pause_settings: SettingsPanel
var _settings_tab := 0
var _results_t := 0.0
var _prev_best := INF
var _last_delta := NAN
var _backwards_t := 0.0
var _debug_force := ""
var _debug_at := INF
var _clock := 0.0


static func fmt_time(t: float) -> String:
	if t == INF or t <= 0.0:
		return "--:--.---"
	var m := int(t / 60.0)
	return "%d:%06.3f" % [m, t - m * 60.0]


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = HudStyle.make_root(self)

	_info = HudInfo.new()
	_info.position = Vector2(28, 28)
	_root.add_child(_info)

	_tower = HudTower.new()
	_tower.race = race
	_tower.position = Vector2(28, 222)
	_root.add_child(_tower)

	_map = HudMinimap.new()
	_map.race = race
	_map.build()
	_anchor(_map, 1.0, 0.0, Vector2(-28 - _map.size.x, 28))
	_root.add_child(_map)

	_lights = HudLights.new()
	_anchor(_lights, 0.5, 0.0, Vector2(-_lights.size.x * 0.5, 40))
	_root.add_child(_lights)

	_banner = HudBanner.new()
	_anchor(_banner, 0.5, 0.2, Vector2(-_banner.size.x * 0.5, 0))
	_root.add_child(_banner)

	race.lights_changed.connect(_on_lights)
	race.lap_completed.connect(_on_lap)
	race.race_finished.connect(_on_finished)
	var wx := Weather.current()
	if wx and wx.cycle: # changeable weather: "RAIN STARTING", "TRACK DRYING", ...
		wx.cycle.news.connect(func(t: String, sub: String): _banner.show_banner(t, sub))
	_parse_debug()


## Pin `c` (fixed size) to a point of the root given as anchor fractions + pixel offset.
func _anchor(c: Control, ax: float, ay: float, offset: Vector2) -> void:
	var s := c.size
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + s.x
	c.offset_bottom = offset.y + s.y


func _process(dt: float) -> void:
	_clock += dt
	var p = race.player
	if p == null:
		return
	if ChaseCamera.cockpit_view != _map_low: # cockpit: the rear-view mirror hangs top right / left
		_map_low = ChaseCamera.cockpit_view
		if _map_low: # the rev counter's corner (hidden in the cockpit, the dash has dials)
			_anchor(_map, 1.0, 1.0, Vector2(-28 - _map.size.x, -24 - _map.size.y))
		else:
			_anchor(_map, 1.0, 0.0, Vector2(-28 - _map.size.x, 28))
	_info.position_now = p.position
	_info.drivers = race.entries.size()
	_info.lap = clampi(p.lap, 1, race.laps)
	_info.laps = race.laps if race.laps < TimeTrial.UNLIMITED else 0 # 0: endless session
	var current: float = race.race_time - p.lap_start if race.state != race.State.COUNTDOWN else 0.0
	_info.current = current if not p.finished else p.last_lap
	_info.last = p.last_lap
	_info.best = p.best_lap
	_info.last_delta = _last_delta
	if _info.is_visible_in_tree():
		_info.queue_redraw()
	_update_wrong_way(p, dt)
	if p.car and is_instance_valid(p.car) and not p.finished:
		_top_speed = maxf(_top_speed, absf(p.car.speed))
	if Time.get_ticks_msec() > SettingsPanel.listening_until and (Input.is_action_just_pressed("pause") \
			or (_pause and Input.is_action_just_pressed("ui_cancel"))):
		if _pause_settings:
			_pause_menu() # Esc in the settings: back to the pause list
		else:
			_toggle_pause()
	if _results_table:
		_results_t += dt
		if _results_t > 0.5:
			_results_t = 0.0
			_results_table.refresh()
	if _clock > _debug_at:
		_debug_at = INF
		_run_debug()


## Wrong way: moving against the track direction above 5 m/s for a couple of seconds.
func _update_wrong_way(p, dt: float) -> void:
	var car: Car = p.car
	var backwards := false
	if car and is_instance_valid(car) and race.state == race.State.RACING and not p.finished \
			and absf(car.speed) > 5.0:
		var line: RacingLine = race.circuit.line
		var n := line.centers.size()
		var i: int = clampi(p.index, 0, n - 1)
		var tangent := line.centers[(i + 3) % n] - line.centers[(i - 3 + n) % n]
		backwards = car.velocity().dot(tangent) < 0.0
	_backwards_t = _backwards_t + dt if backwards else 0.0
	if _debug_force != "wrong":
		_banner.wrong_way = _backwards_t > WRONG_WAY_DELAY


func _on_lights(count: int) -> void:
	_lights.set_lit(count)
	if count < 0 and race.laps == 1:
		_banner.show_banner("FINAL LAP")


func _on_lap(e, lap_time: float) -> void:
	if e != race.player:
		return
	# race.gd has already folded this lap into best_lap; compare with the best before it.
	var delta := lap_time - _prev_best if _prev_best != INF else NAN
	var best := lap_time <= _prev_best
	_prev_best = minf(_prev_best, lap_time)
	_last_delta = delta
	_after_lap.call_deferred(lap_time, delta, best)


## Deferred: by now the lap counter and finish flag are updated (local and network paths).
func _after_lap(lap_time: float, delta: float, best: bool) -> void:
	var e = race.player
	var done: int = e.lap - 1
	_banner.show_lap("LAP %d" % done, fmt_time(lap_time), delta, best and done > 1)
	if e.finished:
		_banner.show_banner("FINISHED", "P%d  OF  %d" % [e.position, race.entries.size()])
	elif e.lap == race.laps:
		_banner.show_banner("FINAL LAP")


# ---------------------------------------------------------------- pause / results

func _toggle_pause() -> void:
	if _results:
		return
	if _pause:
		_pause.queue_free()
		_pause = null
		_pause_settings = null
		_show_hud(true)
		if Game.mode == Game.Mode.SINGLE:
			get_tree().paused = false
		return
	if Game.mode == Game.Mode.SINGLE:
		get_tree().paused = true
	UiSounds.play(self, "click")
	_show_hud(false)
	_pause = _shade()
	_pause_menu()


## Hides the race HUD (ours and the instruments) under the pause screens.
func _show_hud(on: bool) -> void:
	for c in [_info, _tower, _map, _lights, _banner]:
		if c:
			c.visible = on
	for n in race.get_children():
		if n is Hud:
			n.visible = on


## Menu-style pause screen: shaded left column with the options, bindings on the right.
func _pause_menu() -> void:
	for c in _pause.get_children():
		c.queue_free()
	_pause_settings = null
	var p = race.player
	var box := _pause_column(520)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	UiTheme.caption(box, "PAUSED" if Game.mode == Game.Mode.SINGLE else "ONLINE  ·  THE RACE CONTINUES", 13, HudStyle.AMBER, 2, 6)
	_gap(box, 4)
	UiTheme.caption(box, str(race.circuit.def.get("name", "")).to_upper(), 46, Color.WHITE, 2, 5)
	var sub := ""
	if p and race.state != race.State.COUNTDOWN:
		var laps_txt: String = "LAP %d / %d" % [clampi(p.lap, 1, race.laps), race.laps] if race.laps < TimeTrial.UNLIMITED else "LAP %d" % maxi(p.lap, 1)
		sub = "%s   ·   P%d OF %d   ·   BEST %s" % [laps_txt, p.position, race.entries.size(), fmt_time(p.best_lap)]
	else:
		sub = "ON THE GRID   ·   %d LAPS" % race.laps if race.laps < TimeTrial.UNLIMITED else "ON THE GRID"
	UiTheme.caption(box, sub, 15, HudStyle.TEXT, 1, 3)
	_gap(box, 44)
	var hint := UiTheme.caption(box, "", 15, UiTheme.DIM, 0, 1)
	var items := [["Resume", "Back to the race.", _toggle_pause]]
	if Game.mode == Game.Mode.SINGLE:
		items.append(["Restart", "Start this race again from the grid.", _restart])
	items.append(["Settings", "Display, sound and controls.", _open_pause_settings])
	items.append(["Quit to menu", "Leave the race." if Game.mode == Game.Mode.SINGLE else "Leave the online race.", _to_menu])
	var first: Control
	for it in items:
		var n := MenuWidgets.NavItem.new(it[0], it[1])
		n.pressed.connect(func():
			UiSounds.play(n, "back" if it[0].begins_with("Quit") else "click")
			it[2].call())
		n.focus_entered.connect(func(): hint.text = n.hint; UiSounds.play(n, "hover"))
		box.add_child(n)
		if first == null:
			first = n
	box.move_child(hint, box.get_child_count() - 1)
	_gap(box, 18)
	box.move_child(hint, box.get_child_count() - 1)
	first.call_deferred("grab_focus")
	# Controls, from the live bindings, bottom right.
	var ctl := VBoxContainer.new()
	ctl.anchor_left = 1.0
	ctl.anchor_right = 1.0
	ctl.anchor_top = 1.0
	ctl.anchor_bottom = 1.0
	ctl.offset_left = -420
	ctl.offset_right = -80
	ctl.offset_bottom = -64
	ctl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctl.add_theme_constant_override("separation", 0)
	_pause.add_child(ctl)
	UiTheme.caption(ctl, "CONTROLS", 13, HudStyle.AMBER, 2, 6).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gap(ctl, 8)
	var pad := not Input.get_connected_joypads().is_empty()
	for d in InputSetup.DEFAULTS:
		var b := InputSetup.binding(d[0])
		var key := InputSetup.pad_name(b.pad) if pad else InputSetup.keys_text(d[0], true)
		if key == "":
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.alignment = BoxContainer.ALIGNMENT_END
		ctl.add_child(row)
		UiTheme.caption(row, str(d[1]).to_upper(), 12, HudStyle.DIM, 1, 2).size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var k := UiTheme.caption(row, key, 14, HudStyle.TEXT, 2, 1)
		k.custom_minimum_size.x = 86
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _open_pause_settings() -> void:
	for c in _pause.get_children():
		c.queue_free()
	var box := _pause_column(640)
	box.offset_top = 72
	box.offset_bottom = -60
	UiTheme.caption(box, "PAUSED", 13, HudStyle.AMBER, 2, 6)
	_gap(box, 4)
	UiTheme.caption(box, "SETTINGS", 46, Color.WHITE, 2, 5)
	_gap(box, 20)
	_pause_settings = SettingsPanel.new(true, _settings_tab)
	_pause_settings.tab_changed.connect(func(t): _settings_tab = t)
	_pause_settings.closed.connect(_pause_menu)
	box.add_child(_pause_settings)
	_pause_settings.first_focus().call_deferred("grab_focus")


## Full-window shade for the pause screens: dark on the left, clear on the right.
func _shade() -> Control:
	var o := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.9), Color(0, 0, 0, 0.8), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.35)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	o.texture = gt
	o.stretch_mode = TextureRect.STRETCH_SCALE
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(o)
	return o


func _pause_column(w: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.anchor_bottom = 1.0
	box.offset_left = 80
	box.offset_right = 80 + w
	box.offset_bottom = -110
	box.add_theme_constant_override("separation", 0)
	_pause.add_child(box)
	return box


func _gap(box: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


## Let the player see themselves cross the line (and the FINISHED banner) first.
func _on_finished() -> void:
	if _results or _results_pending:
		return
	_results_pending = true
	var p = race.player
	if p and p.finished and _debug_force == "":
		await get_tree().create_timer(2.8, true).timeout
	_results_pending = false
	_show_results()


func _show_results() -> void:
	if _results:
		return
	if _pause:
		_toggle_pause()
	_banner.wrong_way = false
	_show_hud(false)
	_results = _overlay()
	var track := str(race.circuit.def.get("name", "")).to_upper()
	var sub: String = race.mode_ctl.results_subtitle() if race.mode_ctl else ""
	if sub == "":
		sub = "%s  ·  %d LAPS" % [track, race.laps] if track != "" else "%d LAPS" % race.laps
	var box := _panel(_results, "RESULTS", sub)
	var p = race.player
	if p:
		var mine := "P%d OF %d" % [p.position, race.entries.size()] if p.finished else "DID NOT FINISH"
		var line := "YOUR RACE   %s   ·   BEST LAP %s   ·   TOP SPEED %d %s" % [mine, fmt_time(p.best_lap),
			roundi(Game.speed_units(_top_speed)), Game.speed_label()]
		UiTheme.caption(box, line, 13, HudStyle.TEXT, 1, 2)
	_results_table = HudResults.new()
	_results_table.race = race
	box.add_child(_results_table)
	_results_table.refresh()
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	if race.mode_ctl and race.mode_ctl.results_buttons(buttons, _button):
		pass # championship: next race / standings; time trial: retry
	elif Game.mode == Game.Mode.SINGLE:
		_button(buttons, "Race again", _restart)
		_button(buttons, "Menu", _to_menu)
	elif Game.mode == Game.Mode.HOST:
		_button(buttons, "Back to lobby", Net.back_to_lobby)
	else:
		var wait := UiTheme.label(buttons, "Waiting for the host...", 16, HudStyle.DIM)
		wait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_button(buttons, "Leave", _to_menu)


## Full-window dimmer that holds a centred panel.
func _overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0, 0, 0, 0.45)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(o)
	return o


func _panel(parent: Control, title: String, sub: String) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.033, 0.038, 0.92)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.border_width_top = 2
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(30)
	sb.content_margin_top = 26
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	p.add_child(box)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	box.add_child(head)
	var accent := ColorRect.new()
	accent.color = HudStyle.AMBER
	accent.custom_minimum_size = Vector2(36, 3)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(accent)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	head.add_child(spacer)
	UiTheme.caption(head, title, 30, HudStyle.TEXT, 2, 6)
	UiTheme.caption(head, sub, 12, HudStyle.DIM, 1, 3)
	return box


## Menu-style button; the first one in a row is the solid (primary) one and takes focus.
func _button(parent: Node, text: String, cb: Callable) -> Button:
	var first := true
	for c in parent.get_children():
		if c is Button:
			first = false
	var b := MenuWidgets.button(text, first, 200)
	b.pressed.connect(cb)
	b.pressed.connect(func(): UiSounds.play(b, "click"))
	b.focus_entered.connect(func(): UiSounds.play(b, "hover"))
	parent.add_child(b)
	if first:
		b.call_deferred("grab_focus")
	return b


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	race.quit_to_menu()


# ---------------------------------------------------------------- debug

func _parse_debug() -> void:
	var shot_at := 3.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hud_force="):
			_debug_force = arg.get_slice("=", 1)
		elif arg.begins_with("--shot_at="):
			shot_at = float(arg.get_slice("=", 1))
	if _debug_force != "":
		_debug_at = maxf(shot_at - 1.0, 0.1)


func _run_debug() -> void:
	match _debug_force:
		"results": _show_results()
		"pause", "pause_settings", "pause_controls":
			_toggle_pause()
			if _debug_force != "pause":
				_settings_tab = 2 if _debug_force == "pause_controls" else 0
				_open_pause_settings()
			# The tree is paused now, so race.gd's screenshot never fires: take it here.
			var path := ""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--screenshot="):
					path = arg.get_slice("=", 1)
			if path != "":
				await get_tree().create_timer(0.4, true).timeout
				get_viewport().get_texture().get_image().save_png(path)
				get_tree().quit()
		"lap":
			_banner.show_lap("LAP 2", fmt_time(83.456), -0.532, true)
			_banner.show_banner("FINAL LAP")
		"wrong": _banner.wrong_way = true
