class_name UiTheme
extends RefCounted
## Shared look for menus and HUD: dark glass, off-white type, one amber accent.

const TEXT := Color(0.9, 0.9, 0.88)
const DIM := Color(0.9, 0.9, 0.88, 0.5)
const FAINT := Color(0.9, 0.9, 0.88, 0.22)
const AMBER := Color(1.0, 0.72, 0.25)
const BG := Color(0.035, 0.038, 0.042)
const FONT := "res://assets/fonts/BarlowSemiCondensed-Medium.ttf"
const FONT_SEMI := "res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf"
const FONT_BOLD := "res://assets/fonts/BarlowSemiCondensed-Bold.ttf"

static var _theme: Theme
static var _fonts := {}


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = load(FONT)
	t.default_font_size = 18
	for c in ["Label", "Button", "LineEdit", "CheckBox", "OptionButton", "SpinBox", "ItemList"]:
		t.set_color("font_color", c, TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_font("font", "Button", font(1, 2))

	var normal := _box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1))
	var hover := _box(Color(1, 1, 1, 0.09), Color(1, 1, 1, 0.22))
	var focus := _box(Color(1, 0.72, 0.25, 0.12), AMBER)
	var pressed := _box(Color(1, 0.72, 0.25, 0.22), AMBER)
	for c in ["Button", "OptionButton"]:
		t.set_stylebox("normal", c, normal)
		t.set_stylebox("hover", c, hover)
		t.set_stylebox("focus", c, focus)
		t.set_stylebox("pressed", c, pressed)
		t.set_stylebox("disabled", c, _box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.04)))
	var edit := _box(Color(0, 0, 0, 0.35), Color(1, 1, 1, 0.14))
	var edit_focus := _box(Color(0, 0, 0, 0.45), AMBER)
	t.set_stylebox("normal", "LineEdit", edit)
	t.set_stylebox("focus", "LineEdit", edit_focus)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(1, 0.72, 0.25, 0.3))
	t.set_color("font_placeholder_color", "LineEdit", FAINT)
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.03, 0.033, 0.037, 0.86), Color(1, 1, 1, 0.07), 26))
	t.set_stylebox("panel", "ItemList", _box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.08)))
	t.set_color("font_selected_color", "ItemList", AMBER)
	t.set_stylebox("selected", "ItemList", _box(Color(1, 0.72, 0.25, 0.12), Color(0, 0, 0, 0)))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(1, 0.72, 0.25, 0.18), AMBER))
	t.set_stylebox("cursor", "ItemList", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("cursor_unfocused", "ItemList", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	_theme = t
	return t


## Barlow at weight 0 Medium / 1 SemiBold / 2 Bold, with extra letter spacing (px).
static func font(weight := 0, spacing := 0) -> Font:
	var key := weight * 100 + spacing
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	f.base_font = load([FONT, FONT_SEMI, FONT_BOLD][clampi(weight, 0, 2)])
	f.spacing_glyph = spacing
	_fonts[key] = f
	return f


static func _box(bg: Color, border: Color, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.content_margin_left = margin + 6
	sb.content_margin_right = margin + 6
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


static func label(parent: Node, text: String, size := 18, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", load(FONT_BOLD))
	parent.add_child(l)
	return l


## Label with a specific weight and letter spacing (menu headings, captions).
static func caption(parent: Node, text: String, size := 14, color := DIM, weight := 1, spacing := 3) -> Label:
	var l := label(parent, text, size, color)
	l.add_theme_font_override("font", font(weight, spacing))
	return l
