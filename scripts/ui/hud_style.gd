class_name HudStyle
extends RefCounted
## Shared palette, fonts and draw helpers for the in-race HUD (built on UiTheme).

const TEXT := UiTheme.TEXT
const DIM := Color(0.9, 0.9, 0.88, 0.55)
const FAINT := Color(0.9, 0.9, 0.88, 0.22)
const AMBER := UiTheme.AMBER
const RED := Color(0.94, 0.27, 0.2)
const GREEN := Color(0.46, 0.86, 0.52)
const GLASS := Color(0.025, 0.028, 0.033, 0.66)
const EDGE := Color(1, 1, 1, 0.08)
const REF_SIZE := Vector2(1600, 900) ## layouts are authored at this size, then scaled

static var _boxes := {}


static func font(weight := 0, spacing := 0) -> Font:
	return UiTheme.font(weight, spacing)


## A full-window Control under `layer` that scales the whole HUD with the window
## (authored at REF_SIZE) while children still anchor to its edges.
static func make_root(layer: CanvasLayer) -> Control:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	layer.add_child(root)
	var vp := layer.get_viewport()
	var fit := func() -> void:
		var s := vp.get_visible_rect().size
		var k := clampf(minf(s.x / REF_SIZE.x, s.y / REF_SIZE.y), 0.5, 4.0)
		layer.scale = Vector2(k, k)
		root.position = Vector2.ZERO
		root.size = s / k
	fit.call()
	vp.size_changed.connect(fit)
	# The viewport outlives the HUD: drop the handler when the HUD goes.
	root.tree_exiting.connect(func() -> void: vp.size_changed.disconnect(fit))
	return root


## Glass panel with a hairline edge; `tint` replaces the fill colour.
static func panel(ci: CanvasItem, r: Rect2, tint := GLASS, edge := EDGE, radius := 4) -> void:
	var key := [tint, edge, radius]
	var sb: StyleBoxFlat = _boxes.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = tint
		sb.border_color = edge
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		_boxes[key] = sb
	ci.draw_style_box(sb, r)


## draw_string with the baseline at `pos.y`; `align` 0 left / 1 centre / 2 right within `width`.
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color, weight := 0,
		spacing := 0, align := 0, width := -1.0) -> void:
	var h: HorizontalAlignment = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT][align]
	ci.draw_string(font(weight, spacing), pos, s, h, width, size, color)


static func text_width(s: String, size: int, weight := 0, spacing := 0) -> float:
	return font(weight, spacing).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * a)


## "+0.532" / "-1.204" for lap deltas.
static func fmt_delta(d: float) -> String:
	return ("+" if d >= 0.0 else "-") + "%.3f" % absf(d)
