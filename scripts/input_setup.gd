class_name InputSetup
extends RefCounted
## Registers input actions at startup (keyboard + gamepad) so they live in code
## instead of a huge serialized block in project.godot, and applies the
## player's rebinds (Game.bindings, saved in settings.cfg).
##
## Every action has two keyboard slots and one gamepad slot. A gamepad slot is
## {b = JoyButton} or {a = JoyAxis, v = -1.0 / 1.0}; an empty slot is 0 / {}.

## [action, label, [key, alt key], pad]. Order = order on the controls screen.
const DEFAULTS := [
	["accelerate", "Throttle", [KEY_W, KEY_UP], {a = JOY_AXIS_TRIGGER_RIGHT, v = 1.0}],
	["brake", "Brake / reverse", [KEY_S, KEY_DOWN], {a = JOY_AXIS_TRIGGER_LEFT, v = 1.0}],
	["steer_left", "Steer left", [KEY_A, KEY_LEFT], {a = JOY_AXIS_LEFT_X, v = -1.0}],
	["steer_right", "Steer right", [KEY_D, KEY_RIGHT], {a = JOY_AXIS_LEFT_X, v = 1.0}],
	["handbrake", "Handbrake", [KEY_SPACE, 0], {b = JOY_BUTTON_A}],
	["shift_up", "Shift up", [KEY_E, 0], {b = JOY_BUTTON_RIGHT_SHOULDER}],
	["shift_down", "Shift down", [KEY_Q, 0], {b = JOY_BUTTON_LEFT_SHOULDER}],
	["camera", "Change camera", [KEY_C, 0], {b = JOY_BUTTON_Y}],
	["look_back", "Look back", [KEY_B, 0], {b = JOY_BUTTON_RIGHT_STICK}],
	["look_left", "Look left", [KEY_Z, 0], {}],
	["look_right", "Look right", [KEY_V, 0], {}],
	["toggle_gearbox", "Auto / manual", [KEY_T, 0], {}],
	["reset_car", "Reset to track", [KEY_R, 0], {b = JOY_BUTTON_BACK}],
	["pause", "Pause", [KEY_ESCAPE, 0], {b = JOY_BUTTON_START}],
]

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "VIEW", JOY_BUTTON_GUIDE: "HOME", JOY_BUTTON_START: "MENU",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-PAD ↑", JOY_BUTTON_DPAD_DOWN: "D-PAD ↓",
	JOY_BUTTON_DPAD_LEFT: "D-PAD ←", JOY_BUTTON_DPAD_RIGHT: "D-PAD →",
}


## Creates / refreshes every action from the defaults plus the player's rebinds.
static func ensure_actions() -> void:
	for d in DEFAULTS:
		var action: StringName = d[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.12)
		InputMap.action_erase_events(action)
		var b := binding(action)
		for k in b.keys:
			if int(k) != 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = int(k)
				InputMap.action_add_event(action, ev)
		var pe := pad_event(b.pad)
		if pe:
			InputMap.action_add_event(action, pe)


static func default_of(action: StringName) -> Array:
	for d in DEFAULTS:
		if d[0] == action:
			return d
	return []


static func label_of(action: StringName) -> String:
	var d := default_of(action)
	return d[1] if not d.is_empty() else str(action)


## {keys = [k0, k1], pad = {...}}: the rebind if there is one, else the default.
static func binding(action: StringName) -> Dictionary:
	var d := default_of(action)
	var keys: Array = d[2].duplicate() if not d.is_empty() else [0, 0]
	var pad: Dictionary = d[3].duplicate() if not d.is_empty() else {}
	var over: Dictionary = Game.bindings.get(str(action), {})
	if over.has("keys") and over.keys is Array and over.keys.size() == 2:
		keys = over.keys.duplicate()
	if over.has("pad") and over.pad is Dictionary:
		pad = over.pad.duplicate()
	return {keys = keys, pad = pad}


## Rebind one slot (0, 1 = keys, 2 = pad) and apply at once. A key or pad input
## already used by another action is taken off that one; returns its label
## ("" if nothing was displaced).
static func rebind(action: StringName, slot: int, value: Variant) -> String:
	var displaced := ""
	for d in DEFAULTS:
		if d[0] == action:
			continue
		var other := binding(d[0])
		var changed := false
		if slot < 2 and int(value) != 0:
			for i in 2:
				if int(other.keys[i]) == int(value):
					other.keys[i] = 0
					changed = true
		elif slot == 2 and not (value as Dictionary).is_empty() and _same_pad(other.pad, value):
			other.pad = {}
			changed = true
		if changed:
			Game.bindings[str(d[0])] = other
			displaced = d[1]
	var b := binding(action)
	if slot < 2:
		b.keys[slot] = int(value)
		if int(value) != 0 and int(b.keys[1 - slot]) == int(value):
			b.keys[1 - slot] = 0
	else:
		b.pad = value
	Game.bindings[str(action)] = b
	ensure_actions()
	return displaced


static func reset_defaults() -> void:
	Game.bindings = {}
	ensure_actions()


static func _same_pad(a: Dictionary, b: Dictionary) -> bool:
	if a.has("b") and b.has("b"):
		return int(a.b) == int(b.b)
	if a.has("a") and b.has("a"):
		return int(a.a) == int(b.a) and signf(a.v) == signf(b.v)
	return false


static func pad_event(pad: Dictionary) -> InputEvent:
	if pad.has("b"):
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(pad.b) as JoyButton
		return ev
	if pad.has("a"):
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(pad.a) as JoyAxis
		ev.axis_value = signf(float(pad.v))
		return ev
	return null


## Pad slot for a captured event, or {} if it isn't a usable press.
static func pad_from_event(e: InputEvent) -> Dictionary:
	if e is InputEventJoypadButton and e.pressed:
		return {b = int(e.button_index)}
	if e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
		return {a = int(e.axis), v = signf(e.axis_value)}
	return {}


## Short name of a physical key as printed on the player's keyboard layout.
static func key_name(k: int) -> String:
	if k == 0:
		return ""
	match k:
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
		KEY_ESCAPE: return "ESC"
		KEY_SPACE: return "SPACE"
		KEY_ENTER: return "ENTER"
		KEY_SHIFT: return "SHIFT"
		KEY_CTRL: return "CTRL"
		KEY_ALT: return "ALT"
		KEY_META: return "CMD" if OS.get_name() == "macOS" else "WIN"
		KEY_TAB: return "TAB"
		KEY_BACKSPACE: return "BKSP"
	var logical := KEY_NONE
	if DisplayServer.get_name() != "headless": # the headless server has no keyboard layout
		logical = DisplayServer.keyboard_get_keycode_from_physical(k as Key)
	var s := OS.get_keycode_string(logical if logical != KEY_NONE else k)
	return s.to_upper() if s != "" else "KEY %d" % k


static func pad_name(pad: Dictionary) -> String:
	if pad.has("b"):
		return PAD_BUTTONS.get(int(pad.b), "BTN %d" % int(pad.b))
	if pad.has("a"):
		var neg := float(pad.v) < 0.0
		match int(pad.a):
			JOY_AXIS_LEFT_X: return "LS ←" if neg else "LS →"
			JOY_AXIS_LEFT_Y: return "LS ↑" if neg else "LS ↓"
			JOY_AXIS_RIGHT_X: return "RS ←" if neg else "RS →"
			JOY_AXIS_RIGHT_Y: return "RS ↑" if neg else "RS ↓"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "AXIS %d%s" % [int(pad.a), "-" if neg else "+"]
	return ""


## "W" / "W / ↑" for hints; "" when the action has no key.
static func keys_text(action: StringName, both := false) -> String:
	var b := binding(action)
	var names := []
	for k in b.keys:
		if int(k) != 0:
			names.append(key_name(int(k)))
	if not both and names.size() > 1:
		names.resize(1)
	return " / ".join(names)
