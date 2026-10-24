class_name LoadingScreen
extends CanvasLayer
## Between the menu and a race while the circuit builds: the track's name,
## blurb and outline (drawn in amber as loading progresses), conditions, a
## rotating driving tip and a progress bar. Same look as the menu.
##
## race.gd creates it first thing, feeds it progress, then calls finish().

const TIP_EVERY := 5.5
const FADE_IN := 0.35
const FADE_OUT := 0.5

var track: Dictionary
var condition := 0 ## Weather condition index (Weather.NAMES)
var laps := 3
var eyebrow := "QUICK RACE"

var _root: Control
var _map: MapView
var _bar: ColorRect
var _bar_back: ColorRect
var _step: Label
var _pct: Label
var _tip: Label
var _tips: Array[String] = []
var _tip_i := 0
var _tip_t := 0.0
var _shown := 0.0 ## displayed progress (eases towards _target)
var _target := 0.0
var _fade: ColorRect
var _clock := 0.0
var _done := false
# Time-based progress: the bar follows how long each step usually takes on
# this track (learnt from the last load, saved in user://), so it glides even
# though the window only redraws between build steps.
const PROFILE := "user://load_profile.cfg"
const DEFAULT_SECS := {"Sky and weather": 0.25, "Ground": 0.2, "Terrain": 0.8, "Tarmac and barriers": 0.45,
	"Trackside": 0.6, "Scenery": 1.1, "Set Dressing": 0.35, "Themes": 1.2, "Grass": 0.25, "Hills": 0.1,
	"Forest": 0.35, "Cars": 1.8, "Warming up": 0.5}
var _expect := {} ## label -> expected seconds
var _order: Array[String] = [] ## labels seen so far, in order
var _done_secs := 0.0 ## expected seconds of finished steps
var _cur := ""
var _cur_t0 := 0.0
var _actual := {} ## label -> measured seconds (saved for next time)


func _init(t: Dictionary, cond: int, lap_count: int, title: String) -> void:
	track = t
	condition = cond
	laps = lap_count
	eyebrow = title
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_root = HudStyle.make_root(self)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # nothing behind is clickable while loading
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	_vignette()

	# Track outline, right half.
	_map = MapView.new(track)
	_map.anchor_left = 0.46
	_map.anchor_right = 1.0
	_map.anchor_bottom = 1.0
	_map.offset_left = 0
	_map.offset_right = -80
	_map.offset_top = 90
	_map.offset_bottom = -170
	_root.add_child(_map)

	# Name, conditions and blurb, left.
	var box := VBoxContainer.new()
	box.anchor_bottom = 1.0
	box.offset_left = 80
	box.offset_right = 80 + 600
	box.offset_top = 0
	box.offset_bottom = -170
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	_root.add_child(box)
	UiTheme.caption(box, eyebrow, 13, UiTheme.AMBER, 2, 6)
	_gap(box, 6)
	var name_l := UiTheme.caption(box, str(track.get("name", "")).to_upper(), 78, Color.WHITE, 2, 10)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	box.add_child(line)
	var bar := ColorRect.new()
	bar.color = UiTheme.AMBER
	bar.custom_minimum_size = Vector2(46, 2)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(bar)
	var km := TrackBuilder.make_curve(track.points).get_baked_length() / 1000.0
	var lap_txt := "" if laps <= 0 or laps >= 999 else "   ·   %d LAP%s" % [laps, "" if laps == 1 else "S"]
	UiTheme.caption(line, "%s%s" % [Game.distance_text(km), lap_txt], 16, UiTheme.TEXT, 1, 5)
	_gap(box, 26)
	var blurb := UiTheme.caption(box, str(track.get("blurb", "")), 21, UiTheme.DIM, 0, 0)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_gap(box, 34)
	var wx := WeatherChip.new(condition)
	box.add_child(wx)

	# Bottom band: tip, progress.
	var foot := Control.new()
	foot.anchor_top = 1.0
	foot.anchor_right = 1.0
	foot.anchor_bottom = 1.0
	foot.offset_left = 80
	foot.offset_right = -80
	foot.offset_top = -150
	foot.offset_bottom = -40
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(foot)
	var tip_cap := UiTheme.caption(foot, "TIP", 12, UiTheme.AMBER, 2, 5)
	tip_cap.position = Vector2(0, 0)
	_tip = UiTheme.caption(foot, "", 19, UiTheme.TEXT, 0, 0)
	_tip.position = Vector2(0, 20)
	_tip.size = Vector2(1100, 30)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(1, 1, 1, 0.08)
	_bar_back.anchor_right = 1.0
	_bar_back.offset_top = 92
	_bar_back.offset_bottom = 94
	foot.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = UiTheme.AMBER
	_bar.offset_top = 92
	_bar.offset_bottom = 94
	foot.add_child(_bar)
	_step = UiTheme.caption(foot, "LOADING", 12, UiTheme.DIM, 1, 4)
	_step.position = Vector2(0, 64)
	_pct = UiTheme.caption(foot, "0%", 12, UiTheme.TEXT, 1, 3)
	_pct.anchor_left = 1.0
	_pct.anchor_right = 1.0
	_pct.offset_left = -80
	_pct.offset_top = 64
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_tips = tips(condition)
	_tips.shuffle()
	_tip.text = _tips[0]

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, FADE_IN).set_trans(Tween.TRANS_SINE)


func _gap(box: Control, h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(c)


func _vignette() -> void:
	var tr := TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 0.72, 0.25, 0.05), Color(0, 0, 0, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.72, 0.45)
	gt.fill_to = Vector2(1.25, 1.1)
	gt.width = 256
	gt.height = 256
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tr)


## 0..1 overall, with the step being worked on ("Terrain"). A new label starts
## a new step; `f` only acts as a floor.
func set_progress(f: float, label: String) -> void:
	_target = maxf(_target, clampf(f, 0.0, 1.0) * 0.5)
	if label != "" and label != _cur:
		_begin(label)
		_step.text = ("BUILDING  " + label).to_upper()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _begin(label: String) -> void:
	if _expect.is_empty():
		_load_profile()
	var t := _now()
	if _cur != "":
		_actual[_cur] = float(_actual.get(_cur, 0.0)) + (t - _cur_t0)
		_done_secs += _secs(_cur)
	_cur = label
	_cur_t0 = t
	if not _order.has(label):
		_order.append(label)


func _secs(label: String) -> float:
	return float(_expect.get(label, DEFAULT_SECS.get(label, 0.25)))


## Total expected time: every step this track ran last time (or the defaults).
func _total() -> float:
	var tot := 0.0
	var seen := {}
	for l: String in _expect:
		tot += _secs(l)
		seen[l] = true
	for l: String in _order:
		if not seen.has(l):
			tot += _secs(l)
	return maxf(tot, 0.5)


func _time_progress() -> float:
	if _cur == "":
		return 0.0
	# Within a step, approach (never reach) its end: no stall, no overshoot.
	var e := _secs(_cur)
	var k := 1.0 - exp(-(_now() - _cur_t0) / maxf(e, 0.05) * 1.6)
	return clampf((_done_secs + e * k * 0.97) / _total(), 0.0, 0.995)


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE) == OK and cfg.has_section(str(track.get("id", ""))):
		for l in cfg.get_section_keys(str(track.get("id", ""))):
			_expect[l] = float(cfg.get_value(str(track.get("id", "")), l))
	if _expect.is_empty():
		_expect = DEFAULT_SECS.duplicate()
		if not track.has("theme"):
			_expect.erase("Themes")


func _save_profile() -> void:
	if _cur != "":
		_actual[_cur] = float(_actual.get(_cur, 0.0)) + (_now() - _cur_t0)
	var cfg := ConfigFile.new()
	cfg.load(PROFILE)
	var id := str(track.get("id", ""))
	if cfg.has_section(id):
		cfg.erase_section(id)
	for l: String in _actual:
		cfg.set_value(id, l, snappedf(float(_actual[l]), 0.01))
	cfg.save(PROFILE)


## Debug: show a fixed progress (screenshots).
func hold(f: float, label: String) -> void:
	_target = f
	_shown = f
	_step.text = ("BUILDING  " + label).to_upper()


func _process(dt: float) -> void:
	_clock += dt
	# Follow the time-based estimate; ease so redraws after a long step glide.
	if not _done:
		_target = maxf(_target, _time_progress())
	_shown = lerpf(_shown, _target, 1.0 - exp(-dt * 9.0))
	var w := _bar_back.size.x
	_bar.offset_right = w * _shown
	_pct.text = "%d%%" % roundi(_shown * 100.0)
	_map.progress = _shown
	_map.clock = _clock
	_map.queue_redraw()
	_tip_t += dt
	if _tip_t > TIP_EVERY and _tips.size() > 1:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % _tips.size()
		var tw := _tip.create_tween()
		tw.tween_property(_tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func(): _tip.text = _tips[_tip_i])
		tw.tween_property(_tip, "modulate:a", 1.0, 0.35)


## Loading done: fill the bar, fade to the race and go away.
func finish() -> void:
	if _done:
		return
	_save_profile()
	_done = true
	_target = 1.0
	_step.text = "READY"
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(_fade, "color:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		for c in _root.get_children():
			if c != _fade:
				c.visible = false)
	tw.tween_property(_fade, "color:a", 0.0, FADE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


## Driving tips, with the player's real keys.
static func tips(cond: int) -> Array[String]:
	var k := func(a: String) -> String:
		var t := InputSetup.keys_text(a)
		return t if t != "" else "(unbound)"
	var out: Array[String] = [
		"Tuck in behind another car: within 25 m the tow cuts your drag and you gain on them.",
		"Tap %s to pull the handbrake and swing the tail into a hairpin, then feed the throttle back in." % k.call("handbrake"),
		"%s cycles the cameras: chase, far chase, roof and cockpit." % k.call("camera"),
		"Off the track? %s puts you back on the racing line." % k.call("reset_car"),
		"%s switches between the automatic and a manual gearbox (%s / %s to shift)." % [k.call("toggle_gearbox"), k.call("shift_up"), k.call("shift_down")],
		"%s toggles the driving assists: ABS, traction control and steering help." % k.call("toggle_assists"),
		"Gravel traps and grass slow you right down and cost grip. Kerbs are fine.",
		"Brake in a straight line, then turn in. Trail the brake only as far as the tyres let you.",
		"The crowd notices. Pass someone in front of a grandstand and they will let you hear it.",
		"All keys and gamepad buttons can be changed under Settings  ·  Controls.",
		"Big or ultra-wide screen? Settings  ·  Display  ·  Render resolution with FSR buys a lot of frame rate.",
	]
	match Weather.cond_kind(cond):
		Weather.Kind.STORM:
			out.append("Wet track: grip is down everywhere, most of all on painted lines and kerbs. Brake earlier.")
			out.append("Standing water hides the apex. Keep a little in reserve on the first lap.")
		Weather.Kind.SNOW:
			out.append("Snow: be smooth. Sudden steering or throttle breaks traction and the car won't come back.")
			out.append("On snow the gravel traps are deep. Stay on the tarmac, even if it means lifting.")
	if Weather.cond_night(cond):
		out.append("At night, brake markers and kerbs are your reference points. Learn them on the first lap.")
	return out


## Track outline: faint full loop, the loaded part in amber, a light running round.
class MapView:
	extends Control
	var progress := 0.0
	var clock := 0.0
	var _poly := PackedVector2Array()
	var _start := 0

	func _init(t: Dictionary) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var curve := TrackBuilder.make_curve(t.points)
		var pts := curve.tessellate_even_length(6, 4.0)
		for p in pts:
			_poly.append(Vector2(p.x, p.z))
		var best := INF
		for i in _poly.size():
			var d := _poly[i].distance_squared_to(Vector2(t.start.x, t.start.z))
			if d < best:
				best = d
				_start = i
		# Start the loop at the start line so progress runs from there.
		var rot := PackedVector2Array()
		for i in _poly.size():
			rot.append(_poly[(i + _start) % _poly.size()])
		_poly = rot

	func _draw() -> void:
		if _poly.size() < 3:
			return
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in _poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var span := hi - lo
		var s := minf(size.x / maxf(span.x, 1.0), size.y / maxf(span.y, 1.0))
		var off := (size - span * s) * 0.5
		var pts := PackedVector2Array()
		for p in _poly:
			pts.append((p - lo) * s + off)
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.035), 22.0, true)
		draw_polyline(pts, Color(1, 1, 1, 0.16), 3.0, true)
		var n := int((pts.size() - 1) * clampf(progress, 0.0, 1.0))
		if n >= 2:
			var done := pts.slice(0, n + 1)
			draw_polyline(done, Color(UiTheme.AMBER, 0.12), 14.0, true)
			draw_polyline(done, UiTheme.AMBER, 3.0, true)
			var head := done[done.size() - 1]
			var pulse := 0.5 + 0.5 * sin(clock * 6.0)
			draw_circle(head, 9.0 + 3.0 * pulse, Color(UiTheme.AMBER, 0.18))
			draw_circle(head, 4.5, Color(1.0, 0.9, 0.7))
		# Start / finish tick.
		var a := pts[0]
		var b := pts[1]
		var nrm := (b - a).normalized().orthogonal() * 12.0
		draw_line(a - nrm, a + nrm, Color.WHITE, 3.0, true)


## Weather line: icon, condition name, a word on what it means.
class WeatherChip:
	extends Control
	var cond := 0

	func _init(c: int) -> void:
		cond = c
		custom_minimum_size = Vector2(560, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var kind := Weather.cond_kind(cond)
		MenuWidgets.weather_icon(self, Vector2(14, 20), cond, UiTheme.TEXT)
		var name := str(Weather.NAMES[clampi(cond, 0, Weather.NAMES.size() - 1)]).to_upper()
		var f := UiTheme.font(2, 4)
		draw_string(f, Vector2(38, 27), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiTheme.TEXT)
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var note := ""
		match kind:
			Weather.Kind.STORM: note = "WET TRACK  ·  LOW GRIP"
			Weather.Kind.SNOW: note = "SNOW  ·  VERY LOW GRIP"
			Weather.Kind.GOLDEN: note = "LOW SUN  ·  DRY"
			Weather.Kind.DAWN: note = "EARLY LIGHT  ·  VALLEY MIST  ·  DRY"
			Weather.Kind.FOG: note = "LOW VISIBILITY  ·  DAMP"
			_: note = "DRY TRACK"
		if Weather.cond_changeable(cond):
			note = "CONDITIONS WILL CHANGE"
		elif Weather.cond_night(cond):
			note += "  ·  NIGHT"
		draw_string(UiTheme.font(1, 3), Vector2(38 + w + 18, 27), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.DIM)
