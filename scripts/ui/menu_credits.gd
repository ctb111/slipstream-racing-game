class_name MenuCredits
extends RefCounted
## Credits screen for the main menu: who built the game, its licence, then the
## third-party credits read at runtime from assets/CREDITS_INGAME.txt
## ("# " lines are section headers, blank lines separate entries).
## Debug: `-- --credits_file=<path>` reads another file instead.

const PATH := "res://assets/CREDITS_INGAME.txt"

var m: Control ## menu.gd


func _init(menu: Control) -> void:
	m = menu


func show_credits() -> void:
	var scr: Control = m._begin("credits")
	var box: VBoxContainer = m._column(scr, 720)
	box.offset_bottom = -90
	m._header(box, "Credits", "")
	# Dark glass panel; the scroll area fills it edge to edge (scrollbar on the
	# panel's right edge, focus accent on its left), text inset by a margin.
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb: StyleBoxFlat = UiTheme.get_theme().get_stylebox("panel", "PanelContainer").duplicate()
	sb.content_margin_left = 0
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	box.add_child(panel)
	var scroll := Scroller.new()
	panel.add_child(scroll)
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 28 if side != "right" else 34)
	inset.add_theme_constant_override("margin_top", 26)
	inset.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(inset)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	inset.add_child(content)
	_fill(content)
	m._gap(box, 22)
	var back := MenuWidgets.button("Back", false, 140)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(m._show_home)
	box.add_child(back)
	scroll.next = back
	m._present(scr, m.FRAME_PANEL, scroll)
	back.focus_neighbor_top = back.get_path_to(scroll) # in the tree now
	back.focus_neighbor_bottom = back.get_path()


func _fill(c: VBoxContainer) -> void:
	UiTheme.caption(c, "SLIPSTREAM — ORIGINALLY BUILT BY CATALIN", 26, Color.WHITE, 2, 3)
	_gap(c, 4)
	UiTheme.caption(c, "Code and original assets: MIT License", 16, UiTheme.DIM, 0, 0)
	_gap(c, 22)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.08)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(rule)
	var path := PATH
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--credits_file="):
			path = arg.trim_prefix("--credits_file=")
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		_gap(c, 22)
		UiTheme.caption(c, "Third-party credits are missing from this build.", 16, UiTheme.DIM, 0, 0)
		return
	for block in parse(text):
		if block.has("header"):
			_gap(c, 30)
			UiTheme.caption(c, str(block.header).to_upper(), 13, UiTheme.AMBER, 2, 6)
			_gap(c, 6)
			continue
		_gap(c, 12)
		var lines: PackedStringArray = block.lines
		for i in lines.size():
			var l := UiTheme.caption(c, lines[i], 18 if i == 0 else 15,
				UiTheme.TEXT if i == 0 else UiTheme.DIM, 1 if i == 0 else 0, 0)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gap(c, 18)


## Splits the credits text into [{header}, {lines}, ...].
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cur := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("# "):
			if not cur.is_empty():
				out.append({lines = cur})
				cur = PackedStringArray()
			out.append({header = line.trim_prefix("# ").strip_edges()})
		elif line.strip_edges() == "":
			if not cur.is_empty():
				out.append({lines = cur})
				cur = PackedStringArray()
		else:
			cur.append(line.strip_edges())
	if not cur.is_empty():
		out.append({lines = cur})
	return out


func _gap(c: Control, h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size.y = h
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(g)


## Focusable scroll area that eases to its target: mouse wheel / trackpad,
## ↑/↓ (keys, d-pad, left stick, held = continuous), right stick, Page Up/Down,
## Home/End. ↓ at the end moves focus on to `next` (the Back button).
class Scroller:
	extends ScrollContainer
	const STEP := 90.0
	const SPEED := 900.0 ## px/s while ↑/↓ or a stick is held
	var next: Control
	var _target := 0.0
	var _set := 0.0
	var glow := 0.0:
		set(v):
			glow = v
			queue_redraw()

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		follow_focus = false
		var bar := get_v_scroll_bar()
		bar.add_theme_stylebox_override("scroll", _bar_box(Color(1, 1, 1, 0.06)))
		bar.add_theme_stylebox_override("scroll_focus", _bar_box(Color(1, 1, 1, 0.06)))
		bar.add_theme_stylebox_override("grabber", _bar_box(Color(1, 1, 1, 0.3)))
		bar.add_theme_stylebox_override("grabber_highlight", _bar_box(Color(UiTheme.AMBER, 0.7)))
		bar.add_theme_stylebox_override("grabber_pressed", _bar_box(UiTheme.AMBER))
		focus_entered.connect(_ease.bind(1.0))
		focus_exited.connect(_ease.bind(0.0))
		# Mouse over the panel (wheel, drag) also gives it focus.
		mouse_entered.connect(func(): if focus_mode != Control.FOCUS_NONE and not has_focus(): grab_focus())

	static func _bar_box(col: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.content_margin_left = 1.5
		sb.content_margin_right = 1.5
		return sb

	func _ease(to: float) -> void:
		create_tween().tween_property(self, "glow", to, 0.18 if to > 0.5 else 0.3) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _limit() -> float:
		var bar := get_v_scroll_bar()
		return maxf(bar.max_value - bar.page, 0.0)

	func _nudge(d: float) -> void:
		_target = clampf(_target + d, 0.0, _limit())

	func _gui_input(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		var pan := e as InputEventPanGesture
		if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var k := mb.factor if mb.factor > 0.0 else 1.0 # trackpads report fractions
			_nudge(STEP * k * (1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0))
			accept_event()
		elif pan:
			_nudge(pan.delta.y * 24.0)
			accept_event()
		elif e.is_action_pressed("ui_down", true):
			if not e.is_echo() and _target >= _limit() - 1.0 and next:
				next.grab_focus()
			elif not e.is_echo():
				_nudge(STEP * 0.6)
			accept_event()
		elif e.is_action_pressed("ui_up", true):
			if not e.is_echo():
				_nudge(-STEP * 0.6)
			accept_event()
		elif e.is_action_pressed("ui_page_down", true):
			_nudge(size.y * 0.85)
			accept_event()
		elif e.is_action_pressed("ui_page_up", true):
			_nudge(-size.y * 0.85)
			accept_event()
		elif e.is_action_pressed("ui_end"):
			_target = _limit()
			accept_event()
		elif e.is_action_pressed("ui_home"):
			_target = 0.0
			accept_event()

	func _process(dt: float) -> void:
		var bar := get_v_scroll_bar()
		if absf(bar.value - _set) > 0.5: # dragged by the scrollbar
			_target = bar.value
		if has_focus():
			var ax := Input.get_axis("ui_up", "ui_down")
			var rs := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
			if absf(rs) > 0.2:
				ax += rs
			if absf(ax) > 0.05:
				_nudge(ax * SPEED * dt)
		_target = clampf(_target, 0.0, _limit())
		bar.value = lerpf(bar.value, _target, 1.0 - exp(-dt * 14.0))
		_set = bar.value

	func _draw() -> void:
		if glow > 0.01: # amber edge on the left while focused, like the menu rows
			var h := size.y * (0.35 + 0.65 * glow)
			draw_rect(Rect2(0, (size.y - h) * 0.5, 3, h), Color(UiTheme.AMBER, glow))
