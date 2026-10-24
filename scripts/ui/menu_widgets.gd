class_name MenuWidgets
extends RefCounted
## Custom-drawn menu controls: nav items, option rows, track cards, list rows,
## buttons. All are keyboard / gamepad focusable; hovering with the mouse moves
## focus, so there's only ever one highlighted thing on screen.

## Generic names on purpose (public release): no manufacturer paint names. Order matches CarPalette.COLORS.
const PAINT_NAMES := ["Signal Red", "Pearl White", "Black", "Silver Metallic", "Forest Green Metallic",
	"Midnight Blue", "Mustard Yellow", "Copper Brown Metallic", "Burnt Orange", "Slate Grey"]


## Base: focus follows the mouse, `glow` eases 0..1 with focus for drawing.
class Focusable:
	extends Control
	var glow := 0.0:
		set(v):
			glow = v
			queue_redraw()
	var _tw: Tween
	## Mouse hover moves keyboard focus here. Off for items where focus also
	## selects (track cards): hovering then only highlights, a click selects.
	var hover_focus := true

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			if not hover_focus:
				if not has_focus():
					_ease(0.6)
			elif focus_mode != Control.FOCUS_NONE and not has_focus():
				grab_focus())
		mouse_exited.connect(func(): if not hover_focus and not has_focus(): _ease(0.0))
		focus_entered.connect(_ease.bind(1.0))
		focus_exited.connect(_ease.bind(0.0))

	func _ease(to: float) -> void:
		if _tw:
			_tw.kill()
		_tw = create_tween()
		_tw.tween_property(self, "glow", to, 0.18 if to > 0.5 else 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _font(weight := 1, spacing := 0) -> Font:
		return UiTheme.font(weight, spacing)

	## Amber bar on the left edge, grows with focus.
	func _accent(h: float) -> void:
		if glow <= 0.01:
			return
		var bh := h * (0.35 + 0.65 * glow)
		draw_rect(Rect2(0, (size.y - bh) * 0.5, 3, bh), Color(UiTheme.AMBER, glow))


## Big text item for the main menu. Emits `pressed`.
class NavItem:
	extends Focusable
	signal pressed
	var text := ""
	var hint := ""

	func _init(t: String, h := "") -> void:
		super()
		text = t.to_upper()
		hint = h
		custom_minimum_size = Vector2(380, 58)

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		_accent(30)
		var f := _font(1, 4)
		var col := UiTheme.DIM.lerp(Color.WHITE, glow)
		draw_string(f, Vector2(22 + 14 * glow, size.y * 0.5 + 11), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)


## A settings row: caption on the left, value on the right, ←/→ (or click the
## arrows) to change it. Subclasses draw the value.
class Row:
	extends Focusable
	signal changed(index: int)
	var caption := ""
	var index := 0
	var count := 1
	var wrap := false

	func _init(cap: String) -> void:
		super()
		caption = cap.to_upper()
		custom_minimum_size = Vector2(0, 52)

	func set_index(i: int, emit := true) -> void:
		i = wrapi(i, 0, count) if wrap else clampi(i, 0, count - 1)
		if i == index:
			return
		index = i
		queue_redraw()
		if emit:
			changed.emit(index)

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_left", true):
			set_index(index - 1)
			accept_event()
		elif e.is_action_pressed("ui_right", true):
			set_index(index + 1)
			accept_event()
		elif e.is_action_pressed("ui_accept"):
			set_index(wrapi(index + 1, 0, count))
			accept_event()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_click(e.position)
			accept_event()

	func _click(p: Vector2) -> void:
		var x0 := _value_left()
		if p.x < x0 + 30:
			set_index(index - 1)
		elif p.x > size.x - 40:
			set_index(index + 1)
		else:
			set_index(wrapi(index + 1, 0, count))

	func _value_left() -> float:
		return size.x * 0.44

	func _draw() -> void:
		if glow > 0.01:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.045 * glow))
		_accent(size.y)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), Color(1, 1, 1, 0.06), 1.0)
		var mid := size.y * 0.5
		draw_string(_font(1, 3), Vector2(20, mid + 6), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			UiTheme.DIM.lerp(UiTheme.TEXT, glow))
		var x0 := _value_left()
		var arrow := Color(1, 1, 1, 0.18 + 0.6 * glow)
		var can_l := wrap or index > 0
		var can_r := wrap or index < count - 1
		_chevron(Vector2(x0 + 10, mid), -1, arrow if can_l else Color(1, 1, 1, 0.06))
		_chevron(Vector2(size.x - 20, mid), 1, arrow if can_r else Color(1, 1, 1, 0.06))
		_draw_value(Rect2(x0 + 30, 0, size.x - x0 - 60, size.y))

	func _chevron(c: Vector2, dir: int, col: Color) -> void:
		draw_polyline(PackedVector2Array([c + Vector2(-4 * dir, -7), c + Vector2(4 * dir, 0), c + Vector2(-4 * dir, 7)]), col, 2.0, true)

	func _draw_value(_r: Rect2) -> void:
		pass


## Row choosing one of a list of strings.
class Choice:
	extends Row
	var options: Array = []

	func _init(cap: String, opts: Array, current: int, wraps := false) -> void:
		super(cap)
		options = opts
		count = opts.size()
		index = clampi(current, 0, count - 1)
		wrap = wraps

	func _draw_value(r: Rect2) -> void:
		draw_string(_font(1, 1), Vector2(r.position.x, r.size.y * 0.5 + 8), str(options[index]).to_upper(),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 21, Color.WHITE.lerp(UiTheme.TEXT, 1.0 - glow))


## Row with a 0..steps bar (volume).
class Level:
	extends Row

	func _init(cap: String, steps: int, current: int) -> void:
		super(cap)
		count = steps + 1
		index = clampi(current, 0, steps)

	func _draw_value(r: Rect2) -> void:
		var y := r.size.y * 0.5
		var w := r.size.x - 56
		var x := r.position.x + 4
		draw_rect(Rect2(x, y - 1.5, w, 3), Color(1, 1, 1, 0.12))
		var k := float(index) / (count - 1)
		draw_rect(Rect2(x, y - 1.5, w * k, 3), UiTheme.AMBER.lerp(UiTheme.TEXT, 0.25 * (1.0 - glow)))
		draw_rect(Rect2(x + w * k - 2, y - 8, 4, 16), Color.WHITE)
		draw_string(_font(1), Vector2(x + w + 10, y + 7), "%d%%" % roundi(k * 100), HORIZONTAL_ALIGNMENT_RIGHT, 42, 18, UiTheme.TEXT)


## Row of paint swatches.
class Paint:
	extends Row

	func _init(current: int) -> void:
		super("Paint")
		count = CarPalette.COLORS.size()
		index = clampi(current, 0, count - 1)
		wrap = true
		custom_minimum_size.y = 72

	func _value_left() -> float:
		return size.x * 0.24

	func _slot(i: int, r: Rect2) -> Rect2:
		var s := minf(24.0, (r.size.x - 8 * (count - 1)) / count)
		var total := s * count + 8 * (count - 1)
		return Rect2(r.position.x + (r.size.x - total) * 0.5 + i * (s + 8), 14, s, s)

	func _click(p: Vector2) -> void:
		var x0 := _value_left()
		var r := Rect2(x0 + 30, 0, size.x - x0 - 60, size.y)
		for i in count:
			if _slot(i, r).grow(4).has_point(p):
				set_index(i)
				return
		super(p)

	func _draw_value(r: Rect2) -> void:
		for i in count:
			var s := _slot(i, r)
			if i == index:
				draw_rect(s.grow(4), Color(UiTheme.AMBER, 0.55 + 0.45 * glow), false, 1.5)
			draw_rect(s, _display(CarPalette.COLORS[i]))
			draw_rect(s, Color(1, 1, 1, 0.14), false, 1.0)
		draw_string(_font(0, 2), Vector2(r.position.x, 62), PAINT_NAMES[index].to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 13, UiTheme.DIM.lerp(UiTheme.TEXT, glow))

	## Paint colours are linear-ish and dark; lift them a touch for a flat swatch.
	func _display(c: Color) -> Color:
		return Color(sqrt(c.r), sqrt(c.g), sqrt(c.b)) * 0.92


## Circuit card: outline map, name, length and weather. Emits `chosen` on focus
## (so moving the highlight selects) and `activated` on Enter / double click.
class TrackCard:
	extends Focusable
	signal chosen
	signal activated
	var track: Dictionary
	var selected := false:
		set(v):
			selected = v
			queue_redraw()
	var length_km := 0.0
	var _poly := PackedVector2Array()
	var _start := 0

	func _init(t: Dictionary) -> void:
		super()
		hover_focus = false
		track = t
		custom_minimum_size = Vector2(150, 176)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var curve := TrackBuilder.make_curve(t.points)
		length_km = curve.get_baked_length() / 1000.0
		var pts := curve.tessellate_even_length(5, 6.0)
		for p in pts:
			_poly.append(Vector2(p.x, p.z))
		var best := INF
		for i in _poly.size():
			var d := _poly[i].distance_squared_to(Vector2(t.start.x, t.start.z))
			if d < best:
				best = d
				_start = i
		focus_entered.connect(func(): chosen.emit())

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_accept"):
			accept_event()
			activated.emit()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			grab_focus()
			chosen.emit()
			if e.double_click:
				activated.emit()

	func _draw() -> void:
		var hot := maxf(glow, 1.0 if selected else 0.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.022, 0.026, 0.72 + 0.1 * hot))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03 + 0.04 * glow))
		var edge := Color(UiTheme.AMBER, 0.9) if selected else Color(1, 1, 1, 0.08 + 0.25 * glow)
		draw_rect(Rect2(Vector2.ONE * 0.5, size - Vector2.ONE), edge, false, 1.0)
		if selected:
			draw_rect(Rect2(0, size.y - 3, size.x, 3), UiTheme.AMBER)
		_draw_map(Rect2(20, 16, size.x - 40, size.y - 92), hot)
		var f := _font(2, 2)
		var title := str(track.name).to_upper()
		var fs := 19
		while fs > 10 and f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > size.x - 32:
			fs -= 1
		draw_string(f, Vector2(16, size.y - 46), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color.WHITE if selected else UiTheme.TEXT.lerp(Color.WHITE, glow))
		var info := Game.distance_text(length_km)
		draw_string(_font(1, 2), Vector2(16, size.y - 20), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.DIM)
		var wk: int = track.get("weather", 0)
		var wname := str(Weather.NAMES[wk]).to_upper()
		var wf := _font(1, 2)
		var ww := wf.get_string_size(wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(wf, Vector2(size.x - 16 - ww, size.y - 20), wname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.DIM)
		MenuWidgets.weather_icon(self, Vector2(size.x - 28 - ww, size.y - 25), wk, UiTheme.DIM)

	func _draw_map(r: Rect2, hot: float) -> void:
		if _poly.is_empty():
			return
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in _poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var span := hi - lo
		var s := minf(r.size.x / span.x, r.size.y / span.y)
		var off := r.position + (r.size - span * s) * 0.5
		var pts := PackedVector2Array()
		for p in _poly:
			pts.append((p - lo) * s + off)
		pts.append(pts[0])
		var line := UiTheme.TEXT.lerp(Color.WHITE, hot)
		draw_polyline(pts, Color(UiTheme.AMBER, 0.08 + 0.12 * hot) if hot > 0.5 else Color(1, 1, 1, 0.05), 9.0, true)
		draw_polyline(pts, Color(line, 0.55 + 0.45 * hot), 2.0, true)
		# Start / finish: a short tick across the track plus a dot.
		var a := pts[_start]
		var b := pts[(_start + 1) % (pts.size() - 1)]
		var n := (b - a).normalized().orthogonal() * 7.0
		draw_line(a - n, a + n, UiTheme.AMBER, 2.5, true)
		draw_circle(a, 3.0, UiTheme.AMBER)


## Thin line weather glyph (sun, cloud + bolt, snowflake) centred on `c`.
## `kind` is a condition (Weather.NAMES index).
static func weather_icon(ci: CanvasItem, c: Vector2, kind: int, col: Color) -> void:
	if kind == Weather.FOG: # banks of fog
		for i in 3:
			var y := c.y - 4.0 + i * 4.0
			var x0 := c.x - 7.0 + (i % 2) * 2.0
			ci.draw_line(Vector2(x0, y), Vector2(x0 + 12.0, y), col, 1.4, true)
		return
	if kind == Weather.DAWN: # half sun rising over the horizon
		ci.draw_arc(c + Vector2(0, 3), 3.6, PI, TAU, 10, col, 1.4, true)
		ci.draw_line(c + Vector2(-8, 3), c + Vector2(8, 3), col, 1.4, true)
		for i in 5:
			var d := Vector2.from_angle(PI + (i + 0.5) * PI / 5.0)
			ci.draw_line(c + Vector2(0, 3) + d * 5.4, c + Vector2(0, 3) + d * 7.4, col, 1.4, true)
		return
	if Weather.cond_night(kind): # crescent moon; storm / snow glyph beside it
		var base := Weather.cond_kind(kind)
		var m := c if base == Weather.Kind.CLEAR else c + Vector2(6, -5)
		var r := 5.0 if base == Weather.Kind.CLEAR else 3.4
		ci.draw_arc(m, r, PI * 0.35, PI * 1.65, 14, col, 1.4, true)
		ci.draw_arc(m + Vector2(r * 0.55, -r * 0.1), r * 0.8, PI * 0.55, PI * 1.45, 10, col, 1.4, true)
		if base != Weather.Kind.CLEAR:
			weather_icon(ci, c + Vector2(-2, 1), base, col)
		return
	match kind:
		Weather.Kind.STORM:
			ci.draw_arc(c + Vector2(-2, 0), 4.0, PI * 0.9, PI * 2.0, 10, col, 1.4, true)
			ci.draw_arc(c + Vector2(3, 1), 3.0, PI * 1.4, PI * 2.4, 8, col, 1.4, true)
			ci.draw_line(c + Vector2(-6, 4), c + Vector2(6, 4), col, 1.4, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(1, 5), c + Vector2(-1, 8), c + Vector2(1.5, 8), c + Vector2(-0.5, 11)]), col, 1.4, true)
		Weather.Kind.SNOW:
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0) * 6.0
				ci.draw_line(c - d, c + d, col, 1.4, true)
		_:
			ci.draw_arc(c, 3.2, 0, TAU, 16, col, 1.4, true)
			for i in 8:
				var d := Vector2.from_angle(i * PI / 4.0)
				ci.draw_line(c + d * 5.0, c + d * 7.0, col, 1.4, true)


## Clickable list row (servers). Emits `pressed`.
class ListRow:
	extends Focusable
	signal pressed
	var title := ""
	var detail := ""
	var right := ""

	func _init(t: String, d: String, r := "") -> void:
		super()
		title = t
		detail = d
		right = r
		custom_minimum_size = Vector2(0, 64)

	func _gui_input(e: InputEvent) -> void:
		if e.is_action_pressed("ui_accept") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
			accept_event()
			pressed.emit()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.025 + 0.05 * glow))
		_accent(size.y)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), Color(1, 1, 1, 0.06), 1.0)
		draw_string(_font(2, 1), Vector2(20, 28), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 180, 21,
			UiTheme.TEXT.lerp(Color.WHITE, glow))
		draw_string(_font(0, 1), Vector2(20, 50), detail, HORIZONTAL_ALIGNMENT_LEFT, size.x - 180, 15, UiTheme.DIM)
		draw_string(_font(1, 2), Vector2(size.x - 170, 38), right, HORIZONTAL_ALIGNMENT_RIGHT, 150, 15,
			UiTheme.AMBER if glow > 0.5 else UiTheme.DIM)


## Plain (non-focusable) row for the lobby grid.
class PlayerRow:
	extends Control
	var num := 0
	var who := ""
	var is_you := false
	var is_host := false

	func _init(n: int, name: String, you: bool, host: bool) -> void:
		num = n
		who = name
		is_you = you
		is_host = host
		custom_minimum_size = Vector2(0, 48)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.03))
		if is_you:
			draw_rect(Rect2(0, 0, 3, size.y), UiTheme.AMBER)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), Color(1, 1, 1, 0.06), 1.0)
		var f := UiTheme.font(2, 1)
		draw_string(UiTheme.font(1), Vector2(20, 31), "%02d" % num, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.FAINT)
		draw_string(f, Vector2(62, 32), who, HORIZONTAL_ALIGNMENT_LEFT, size.x - 240, 21, Color.WHITE if is_you else UiTheme.TEXT)
		var x := size.x - 16
		for tag in (["HOST"] if is_host else []) + (["YOU"] if is_you else []):
			var tf := UiTheme.font(2, 2)
			var w := tf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 16
			x -= w
			var r := Rect2(x, 14, w, 21)
			if tag == "HOST":
				draw_rect(r, UiTheme.AMBER)
				draw_string(tf, Vector2(x + 8, 29), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.05, 0.05))
			else:
				draw_rect(r, Color(1, 1, 1, 0.5), false, 1.0)
				draw_string(tf, Vector2(x + 8, 29), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT)
			x -= 8


## Rectangular action button. `primary` = solid amber, else outline.
static func button(text: String, primary := false, min_w := 220.0) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(min_w, 52)
	b.add_theme_font_override("font", UiTheme.font(2, 4))
	b.add_theme_font_size_override("font_size", 18)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base := Color(1.0, 0.72, 0.25, 0.92) if primary else Color(0, 0, 0, 0.35)
	var line := UiTheme.AMBER if primary else Color(1, 1, 1, 0.25)
	b.add_theme_stylebox_override("normal", _flat(base, line))
	b.add_theme_stylebox_override("hover", _flat(base.lightened(0.12) if primary else Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.9) if primary else UiTheme.AMBER))
	b.add_theme_stylebox_override("focus", _flat(Color(0, 0, 0, 0), Color.WHITE if primary else UiTheme.AMBER, 2))
	b.add_theme_stylebox_override("pressed", _flat(base.darkened(0.15), UiTheme.AMBER))
	var ink := Color(0.06, 0.05, 0.03) if primary else UiTheme.TEXT
	for s in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(s, ink if primary else (Color.WHITE if s != "font_color" else ink))
	b.mouse_entered.connect(func(): if b.focus_mode != Control.FOCUS_NONE and not b.has_focus(): b.grab_focus())
	return b


static func _flat(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	return sb
