class_name GxLive
extends RefCounted
## Live race state for trackside pieces (LED boards, lamps, searchlight, finish fx).
## Lookups are cached by the caller; nothing here walks the scene tree per frame.
##   var r := GxLive.race(self)          # the Race node (has entries, state, race_time, laps) or null
##   GxLive.every(self, 0.5, _tick)       # engine Timer, no per-frame script


## The Race node above `n` (or the current scene), or null (menus, gx tests).
static func race(n: Node) -> Node:
	var p := n
	while p:
		if "entries" in p and "race_time" in p:
			return p
		p = p.get_parent()
	var s := n.get_tree().current_scene if n.is_inside_tree() else null
	return s if s and "entries" in s and "race_time" in s else null


## Debug `--live_off`: build none of the live extras (perf A/B against the plain track).
static func off() -> bool:
	return OS.get_cmdline_user_args().has("--live_off")


## Leader entry (position 1) or null.
static func leader(r: Node) -> Object:
	if r == null or not r.has_method("standings"):
		return null
	var st: Array = r.standings()
	return st[0] if not st.is_empty() else null


## Proper dark: night or storm (searchlight).
static func dark() -> bool:
	var w := Weather.current()
	return w != null and (w.night or w.kind == Weather.Kind.STORM)


## Calls `fn` every `period` s while `owner` is in the tree.
static func every(owner: Node, period: float, fn: Callable) -> Timer:
	var t := Timer.new()
	t.wait_time = period
	t.autostart = true
	t.timeout.connect(fn)
	owner.add_child(t)
	return t


## "H:MM:SS" of a race clock.
static func hms(s: float) -> String:
	var i := int(maxf(s, 0.0))
	return "%d:%02d:%02d" % [i / 3600, (i / 60) % 60, i % 60]
