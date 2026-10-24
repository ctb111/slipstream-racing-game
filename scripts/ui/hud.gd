class_name Hud
extends CanvasLayer
## Driver instruments: rev counter / gear / speed (bottom right), drift readout,
## and a short controls hint for the first seconds of the race.

const HINT_TIME := 8.0 ## seconds of racing the controls hint stays up

const HINTS := [
	[["accelerate", "brake"], "THROTTLE · BRAKE"], [["steer_left", "steer_right"], "STEER"],
	[["handbrake"], "HANDBRAKE"], [["shift_down", "shift_up"], "SHIFT"], [["camera"], "CAMERA"],
	[["look_back"], "LOOK BACK"], [["reset_car"], "RESET"], [["pause"], "PAUSE"],
]

var car: Car

var _root: Control
var _tacho: HudTacho
var _drift: HudDrift
var _hint: Label


func _ready() -> void:
	_root = HudStyle.make_root(self)
	_tacho = HudTacho.new()
	_tacho.car = car
	_pin(_tacho, 1.0, 1.0, Vector2(-_tacho.size.x - 24, -_tacho.size.y - 18))

	_drift = HudDrift.new()
	_drift.car = car
	_pin(_drift, 0.5, 1.0, Vector2(-_drift.size.x * 0.5, -_drift.size.y - 150))

	if not Game.control_hints:
		return
	_hint = UiTheme.caption(_root, hint_text(not Input.get_connected_joypads().is_empty()),
			12, Color(0.9, 0.9, 0.88, 0.6), 1, 2)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -40
	_hint.offset_bottom = -20
	_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_hint.add_theme_constant_override("shadow_offset_y", 1)


## The controls strip from the player's real bindings (gamepad names when one is connected).
static func hint_text(pad: bool) -> String:
	var parts := []
	for h in HINTS:
		var names := []
		for a in h[0]:
			if not InputMap.has_action(a):
				continue
			var n := InputSetup.pad_name(InputSetup.binding(a).pad) if pad else InputSetup.keys_text(a)
			if n != "" and not names.has(n):
				names.append(n)
		if names.size() == h[0].size() or (names.size() > 0 and h[0].size() == 1):
			parts.append("%s  %s" % ["/".join(names), h[1]])
	return "     ".join(parts)


func _pin(c: Control, ax: float, ay: float, offset: Vector2) -> void:
	var s := c.size
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + s.x
	c.offset_bottom = offset.y + s.y
	_root.add_child(c)


func _process(_dt: float) -> void:
	_tacho.visible = not ChaseCamera.cockpit_view # the dashboard has its own dials
	if _hint == null:
		return
	# The race (our parent) knows how long we've been racing; fade the hint after HINT_TIME.
	var race := get_parent()
	var t: float = race.get("race_time") if race and race.get("race_time") != null else 0.0
	var counting: bool = race != null and race.get("state") == 0
	var a := 1.0 if counting else clampf(HINT_TIME - t, 0.0, 1.0)
	_hint.modulate.a = a
	if a <= 0.0:
		_hint.queue_free()
		_hint = null
