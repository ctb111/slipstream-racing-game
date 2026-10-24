class_name SettingsPanel
extends VBoxContainer
## The settings pages, shared by the main menu and the pause menu: a tab strip
## (Display / Audio / Controls / Game) over one page of MenuWidgets rows.
## Everything applies and saves the moment it changes.
##
## Controls page: one row per action with KEY, ALT KEY and PAD cells. ←/→ picks
## a cell, Enter (or a click) listens for the new input, Delete clears it; Esc
## cancels listening. An input already used elsewhere moves here.

signal closed ## the Back button on the page
signal tab_changed(tab: int)

const TABS := ["Display", "Audio", "Controls", "Game"]
const LISTEN_TIMEOUT := 6.0

## Set while listening for a key, so the race's pause toggle ignores that press.
static var listening_until := 0

var in_race := false ## pause menu: no driver name (it's already on the grid)
var tab := 0
var width := 640.0

var _tabs: Array[TabItem] = []
var _page: VBoxContainer
var _msg: Label
var _res_note: Label
var _bind_rows: Array[BindRow] = []
var _listen_row: BindRow
var _listen_t := 0.0
var _back: Button


func _init(race := false, start_tab := 0) -> void:
	in_race = race
	tab = start_tab
	add_theme_constant_override("separation", 0)
	custom_minimum_size.x = width
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	add_child(strip)
	for i in TABS.size():
		var t := TabItem.new(TABS[i])
		t.focus_entered.connect(_select_tab.bind(i))
		strip.add_child(t)
		_tabs.append(t)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.1)
	rule.custom_minimum_size.y = 1
	add_child(rule)
	_gap(self, 14)
	_page = VBoxContainer.new()
	_page.add_theme_constant_override("separation", 0)
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_page)
	_gap(self, 10)
	_msg = UiTheme.caption(self, "", 14, UiTheme.AMBER, 1, 1)
	_msg.custom_minimum_size.y = 22
	_gap(self, 10)
	_back = MenuWidgets.button("Back", false, 140)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(func(): closed.emit())
	add_child(_back)
	_build_page()
	_refresh_tabs()


## The control to focus when the panel opens.
func first_focus() -> Control:
	return _tabs[tab]


func _gap(box: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


func _select_tab(i: int) -> void:
	if i == tab and _page.get_child_count() > 0:
		return
	tab = i
	_cancel_listen()
	_build_page()
	_refresh_tabs()
	tab_changed.emit(i)
	UiSounds.play(self, "hover")


func _refresh_tabs() -> void:
	for i in _tabs.size():
		_tabs[i].selected = i == tab


func _say(text: String) -> void:
	_msg.text = text
	_msg.modulate.a = 1.0
	if text != "":
		var tw := _msg.create_tween()
		tw.tween_interval(3.5)
		tw.tween_property(_msg, "modulate:a", 0.0, 0.6)


func _build_page() -> void:
	for c in _page.get_children():
		c.queue_free()
	_bind_rows.clear()
	_res_note = null
	match tab:
		0: _display_page()
		1: _audio_page()
		2: _controls_page()
		3: _game_page()
	_wire_focus.call_deferred()


## Tabs ↓ into the first row, the last row ↓ to Back, Back ↑ to the last row.
func _wire_focus() -> void:
	var rows: Array[Control] = []
	for c in _page.find_children("*", "Control", true, false):
		if c is Control and c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree():
			rows.append(c)
	if rows.is_empty():
		return
	for t in _tabs:
		t.focus_neighbor_bottom = t.get_path_to(rows[0])
	rows[0].focus_neighbor_top = rows[0].get_path_to(_tabs[tab])
	rows[-1].focus_neighbor_bottom = rows[-1].get_path_to(_back)
	_back.focus_neighbor_top = _back.get_path_to(rows[-1])


# ---------------------------------------------------------------- pages

func _display_page() -> void:
	var cur_mode := Game.window_mode
	var wm := MenuWidgets.Choice.new("Window", Game.WINDOW_NAMES, cur_mode)
	wm.changed.connect(func(i):
		Game.window_mode = i
		Game.apply_window()
		Game.save_settings()
		_update_res_note.call_deferred())
	_page.add_child(wm)
	var vs := MenuWidgets.Choice.new("V-Sync", ["Off", "On"], int(Game.vsync), true)
	vs.changed.connect(func(i): Game.vsync = i == 1; Game.apply_window(); Game.save_settings())
	_page.add_child(vs)
	var q := MenuWidgets.Choice.new("Graphics quality", Game.QUALITY_NAMES, Game.quality)
	q.changed.connect(func(i):
		Game.quality = i
		Game.save_settings()
		Game.apply_viewport_quality(get_viewport())
		_update_res_note()
		if in_race:
			_say("Some quality changes (grass, trees) apply from the next race."))
	_page.add_child(q)
	var names := []
	for s in Game.RENDER_SCALES:
		names.append("Auto" if s == 0 else "%d%%" % s)
	var rs := MenuWidgets.Choice.new("Render resolution", names, maxi(Game.RENDER_SCALES.find(Game.render_scale), 0))
	rs.changed.connect(func(i):
		Game.render_scale = Game.RENDER_SCALES[i]
		Game.save_settings()
		Game.apply_viewport_quality(get_viewport())
		_update_res_note())
	_page.add_child(rs)
	var up := MenuWidgets.Choice.new("Upscaler", Game.UPSCALER_NAMES, Game.upscaler, true)
	up.changed.connect(func(i):
		Game.upscaler = i
		Game.save_settings()
		Game.apply_viewport_quality(get_viewport())
		_update_res_note())
	_page.add_child(up)
	_gap(_page, 14)
	_res_note = UiTheme.caption(_page, "", 15, UiTheme.DIM, 0, 0)
	_res_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_res_note.custom_minimum_size.x = width - 40
	_update_res_note()
	var t := get_tree().create_timer(0.4) # window-mode switches finish asynchronously
	t.timeout.connect(func(): if is_instance_valid(self): _update_res_note())


func _update_res_note() -> void:
	if _res_note == null or not is_instance_valid(_res_note):
		return
	var win := DisplayServer.window_get_size()
	var s := Game.render_scale_now()
	var auto := Game.render_scale == 0
	var txt := "Screen %d × %d.  " % [win.x, win.y]
	if auto and Game.quality <= 1:
		txt += "Auto: renders the 3D view at %d%% and lowers it (down to %d%%) whenever the frame rate dips below 60, upscaled with %s. The HUD always stays sharp." % [
			roundi(s * 100), roundi(_auto_floor(win) * 100), Game.UPSCALER_NAMES[Game.upscaler].get_slice(" (", 0)]
	elif s < 0.999:
		txt += "3D view renders at %d × %d, upscaled with %s. The HUD always stays sharp." % [
			roundi(win.x * s), roundi(win.y * s), Game.UPSCALER_NAMES[Game.upscaler].get_slice(" (", 0)]
	else:
		txt += "3D view renders at native resolution."
	if win.x * win.y > 5.0e6 and s > 0.8:
		txt += " On a screen this big, 67–77% with FSR looks nearly native and runs much faster."
	_res_note.text = txt


func _auto_floor(win: Vector2i) -> float:
	return clampf(sqrt(DynamicRes.MIN_PIXELS / maxf(win.x * win.y, 1.0)), 0.5, DynamicRes.MIN_SCALE)


func _audio_page() -> void:
	var labels := {Master = "Master", Engine = "Engines", Effects = "Effects", Ambience = "Ambience", Music = "Music"}
	for bus in Game.BUSES:
		if bus == "Music" and AudioServer.get_bus_index("Music") < 0:
			continue
		if bus == "Music":
			continue # no music in the game yet; the bus is there for when it arrives
		var row := MenuWidgets.Level.new(labels[bus], 20, roundi(float(Game.volumes.get(bus, 1.0)) * 20.0))
		row.changed.connect(func(i):
			Game.volumes[bus] = i / 20.0
			Game.apply_volumes()
			Game.save_settings()
			UiSounds.play(self, "hover", 4.0))
		_page.add_child(row)
	_gap(_page, 14)
	var note := UiTheme.caption(_page, "Engines: every car's engine, turbo and exhaust.   Effects: tyres, impacts, scraping and the menu.   Ambience: crowd, announcer, weather and nature.", 15, UiTheme.DIM, 0, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = width - 40


func _game_page() -> void:
	if not in_race:
		var name_pad := MarginContainer.new()
		name_pad.add_theme_constant_override("margin_left", 20)
		_page.add_child(name_pad)
		var name_row := HBoxContainer.new()
		name_row.custom_minimum_size.y = 60
		name_pad.add_child(name_row)
		var cap := UiTheme.caption(name_row, "DRIVER NAME", 16, UiTheme.DIM, 1, 3)
		cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_edit := LineEdit.new()
		name_edit.text = Game.player_name
		name_edit.max_length = 16
		name_edit.custom_minimum_size = Vector2(320, 46)
		name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_edit.add_theme_font_size_override("font_size", 20)
		name_edit.text_changed.connect(func(t): Game.player_name = t if t.strip_edges() != "" else "Driver"; Game.save_settings())
		name_edit.mouse_entered.connect(func(): if name_edit.focus_mode != Control.FOCUS_NONE and not name_edit.has_focus(): name_edit.grab_focus())
		name_row.add_child(name_edit)
	var u := MenuWidgets.Choice.new("Speed units", ["km/h", "mph"], Game.units, true)
	u.changed.connect(func(i): Game.units = i; Game.save_settings())
	_page.add_child(u)
	var h := MenuWidgets.Choice.new("Control hints", ["Off", "On"], int(Game.control_hints), true)
	h.changed.connect(func(i): Game.control_hints = i == 1; Game.save_settings())
	_page.add_child(h)
	var rm := MenuWidgets.Choice.new("Rear-view mirror", ["Off", "On"], int(Game.cockpit_mirror), true)
	rm.changed.connect(func(i): Game.cockpit_mirror = i == 1; Game.save_settings())
	_page.add_child(rm)


func _controls_page() -> void:
	var head := Control.new()
	head.custom_minimum_size.y = 26
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(head)
	for c in BindRow.columns(width):
		var l := UiTheme.caption(head, c[0], 12, UiTheme.FAINT, 1, 3)
		l.position = Vector2(c[1], 2)
		l.size.x = c[2]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if c[3] else HORIZONTAL_ALIGNMENT_LEFT
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size.y = 300
	_page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	for d in InputSetup.DEFAULTS:
		if not InputMap.has_action(d[0]):
			continue
		var row := BindRow.new(d[0], d[1])
		row.listen.connect(_start_listen.bind(row))
		row.cleared.connect(func(slot: int):
			InputSetup.rebind(row.action, slot, 0 if slot < 2 else {})
			Game.save_settings()
			_refresh_binds()
			UiSounds.play(self, "back"))
		list.add_child(row)
		_bind_rows.append(row)
	_gap(_page, 12)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 18)
	_page.add_child(foot)
	var reset := MenuWidgets.button("Reset to defaults", false, 230)
	reset.pressed.connect(func():
		_cancel_listen()
		InputSetup.reset_defaults()
		Game.save_settings()
		_refresh_binds()
		_say("Controls reset to the defaults."))
	foot.add_child(reset)
	var hint := UiTheme.caption(foot, "ENTER  REBIND     ←/→  KEY · ALT · PAD     DEL  CLEAR", 12, UiTheme.DIM, 1, 2)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_refresh_binds()


func _refresh_binds() -> void:
	for r in _bind_rows:
		r.load_binding()


func _start_listen(slot: int, row: BindRow) -> void:
	_cancel_listen()
	_listen_row = row
	row.listening = slot
	_listen_t = LISTEN_TIMEOUT
	listening_until = Time.get_ticks_msec() + 100000
	_say("Press a %s for %s  ·  Esc cancels" % ["gamepad button or stick" if slot == 2 else "key", row.label])
	UiSounds.play(self, "click")


func _cancel_listen() -> void:
	if _listen_row and is_instance_valid(_listen_row):
		_listen_row.listening = -1
	_listen_row = null
	listening_until = Time.get_ticks_msec() + 250 # the Esc that cancelled mustn't also unpause


func _process(dt: float) -> void:
	if _listen_row:
		_listen_t -= dt
		if _listen_t <= 0.0:
			_cancel_listen()
			_say("")


func _input(e: InputEvent) -> void:
	if _listen_row == null:
		return
	if e is InputEventMouseButton and e.pressed:
		_cancel_listen()
		_say("")
		get_viewport().set_input_as_handled()
		return
	var slot := _listen_row.listening
	var value: Variant = null
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
		if k == KEY_ESCAPE:
			_cancel_listen()
			_say("")
			get_viewport().set_input_as_handled()
			return
		value = k
		if slot == 2:
			slot = 0
	else:
		var pad := InputSetup.pad_from_event(e)
		if not pad.is_empty():
			value = pad
			slot = 2
	if value == null:
		if e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
			get_viewport().set_input_as_handled() # releases / small stick moves: swallow
		return
	get_viewport().set_input_as_handled()
	var row := _listen_row
	var displaced := InputSetup.rebind(row.action, slot, value)
	Game.save_settings()
	_cancel_listen()
	_refresh_binds()
	row.slot = slot
	var name := InputSetup.key_name(int(value)) if slot < 2 else InputSetup.pad_name(value)
	_say("%s  →  %s%s" % [row.label, name, ("   (taken from %s)" % displaced) if displaced != "" else ""])
	UiSounds.play(self, "confirm")
	row.grab_focus()


# ---------------------------------------------------------------- widgets

## Tab header: caption with an amber underline when selected. Focus = select.
class TabItem:
	extends MenuWidgets.Focusable
	var text := ""
	var selected := false:
		set(v):
			selected = v
			queue_redraw()

	func _init(t: String) -> void:
		super()
		text = t.to_upper()
		custom_minimum_size = Vector2(128, 44)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			accept_event()

	func _draw() -> void:
		var f := _font(1, 4)
		var col := UiTheme.DIM.lerp(Color.WHITE, maxf(glow, 1.0 if selected else 0.0))
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var x := (size.x - w) * 0.5
		if glow > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.04 * glow))
		draw_string(f, Vector2(x, size.y * 0.5 + 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		if selected:
			draw_rect(Rect2(x - 4, size.y - 3, w + 8, 3), UiTheme.AMBER)


## One action on the controls page: label + KEY / ALT / PAD cells.
class BindRow:
	extends MenuWidgets.Focusable
	signal listen(slot: int)
	signal cleared(slot: int)
	var action: StringName
	var label := ""
	var slot := 0
	var listening := -1:
		set(v):
			listening = v
			queue_redraw()
	var _cells := ["", "", ""]
	var _defaults := [false, false, false]
	var _blink := 0.0

	## [caption, x, width, centred] for the header and the cells (for a row `w` wide).
	static func columns(w: float) -> Array:
		var cw := (w - 250.0) / 3.0
		return [["ACTION", 20.0, 200.0, false], ["KEY", 250.0, cw, true], ["ALT KEY", 250.0 + cw, cw, true],
			["GAMEPAD", 250.0 + cw * 2.0, cw, true]]

	func _init(a: StringName, l: String) -> void:
		super()
		action = a
		label = l
		custom_minimum_size = Vector2(0, 42)

	func load_binding() -> void:
		var b := InputSetup.binding(action)
		var d := InputSetup.default_of(action)
		_cells = [InputSetup.key_name(int(b.keys[0])), InputSetup.key_name(int(b.keys[1])), InputSetup.pad_name(b.pad)]
		_defaults = [int(b.keys[0]) == int(d[2][0]), int(b.keys[1]) == int(d[2][1]), InputSetup.pad_name(b.pad) == InputSetup.pad_name(d[3])]
		queue_redraw()

	func _process(dt: float) -> void:
		if listening >= 0:
			_blink += dt
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if listening >= 0:
			return
		if e.is_action_pressed("ui_left", true):
			slot = maxi(slot - 1, 0)
			queue_redraw()
			accept_event()
		elif e.is_action_pressed("ui_right", true):
			slot = mini(slot + 1, 2)
			queue_redraw()
			accept_event()
		elif e.is_action_pressed("ui_accept"):
			accept_event()
			listen.emit(slot)
		elif e is InputEventKey and e.pressed and (e.keycode == KEY_DELETE or e.keycode == KEY_BACKSPACE):
			accept_event()
			cleared.emit(slot)
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			var cols := columns(size.x)
			for i in 3:
				if e.position.x >= cols[i + 1][1] and e.position.x < cols[i + 1][1] + cols[i + 1][2]:
					slot = i
					listen.emit(i)
					return
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			var cols := columns(size.x)
			for i in 3:
				if e.position.x >= cols[i + 1][1] and e.position.x < cols[i + 1][1] + cols[i + 1][2]:
					cleared.emit(i)

	func _draw() -> void:
		if glow > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.045 * glow))
		_accent(size.y)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), Color(1, 1, 1, 0.06), 1.0)
		var mid := size.y * 0.5
		draw_string(_font(1, 3), Vector2(20, mid + 6), label.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 220, 15,
			UiTheme.DIM.lerp(UiTheme.TEXT, glow))
		var cols := columns(size.x)
		for i in 3:
			var x: float = cols[i + 1][1]
			var w: float = cols[i + 1][2]
			var r := Rect2(x + 6, 7, w - 12, size.y - 14)
			var hot := glow > 0.5 and i == slot
			if listening == i:
				var a := 0.5 + 0.5 * sin(_blink * 8.0)
				draw_rect(r, Color(UiTheme.AMBER, 0.12 + 0.1 * a))
				draw_rect(r, Color(UiTheme.AMBER, 0.6 + 0.4 * a), false, 1.5)
				draw_string(_font(1, 2), Vector2(x, mid + 5), "PRESS…", HORIZONTAL_ALIGNMENT_CENTER, w, 13, UiTheme.AMBER)
				continue
			if hot:
				draw_rect(r, Color(1, 1, 1, 0.06))
				draw_rect(r, UiTheme.AMBER, false, 1.0)
			elif _cells[i] != "":
				draw_rect(r, Color(1, 1, 1, 0.14 if not _defaults[i] else 0.07), false, 1.0)
			var txt: String = _cells[i] if _cells[i] != "" else "—"
			var col := Color.WHITE if hot else (UiTheme.TEXT if _cells[i] != "" else UiTheme.FAINT)
			if _cells[i] != "" and not _defaults[i] and not hot:
				col = UiTheme.AMBER.lerp(UiTheme.TEXT, 0.35) # changed from the default
			draw_string(_font(1, 1), Vector2(x, mid + 6), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 16, col)
