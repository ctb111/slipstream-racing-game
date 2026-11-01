class_name StartBoard
extends Node3D
## Amber LED boards on the start/finish gantry beam, either side of the start
## lights: left "LAP 2/5" (FINISH once the leader is home), right the race
## clock alternating with the leader's name. Two Label3Ds, text updated at 2 Hz
## by a Timer; no per-frame work.
##   StartBoard.add(parent, xf, half_w)   xf: board centre plane, -z facing approaching cars

const AMBER := Color(2.4, 1.2, 0.22) # HDR: glows like the lamps
const FONT := "res://assets/fonts/BarlowSemiCondensed-Bold.ttf"

var _left: Label3D
var _right: Label3D
var _race: Node
var _chars := 10
var _tick := 0


## `left` / `right`: board centres; `basis` with +z facing approaching cars; `w` board width.
static func add(parent: Node3D, left: Vector3, right: Vector3, basis: Basis, w: float) -> StartBoard:
	var b := StartBoard.new()
	b.name = "StartBoard"
	parent.add_child(b)
	b._left = b._label(Transform3D(basis, left))
	b._right = b._label(Transform3D(basis, right))
	b._chars = maxi(int(w / 0.25), 5)
	b._left.text = "LAPS"
	b._right.text = "0:00"
	GxLive.every(b, 0.5, b._update)
	return b


func _label(xf: Transform3D) -> Label3D:
	var l := Label3D.new()
	l.font = load(FONT)
	l.font_size = 96
	l.pixel_size = 0.0052
	l.outline_size = 0
	l.modulate = AMBER
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.visibility_range_end = 700.0
	l.transform = xf
	add_child(l)
	return l


func _update() -> void:
	if _race == null:
		_race = GxLive.race(self)
		if _race == null:
			return
	_tick += 1
	var laps := int(_race.laps)
	var lead = GxLive.leader(_race)
	var t := float(_race.race_time)
	var clock := "%d:%02d" % [int(t) / 60, int(t) % 60]
	if lead and lead.finished:
		_put(_left, "FINISH")
		_put(_right, str(lead.name).to_upper().left(_chars) if (_tick / 6) % 2 == 0 else "%d:%02d" % [int(lead.finish_time) / 60, int(lead.finish_time) % 60])
	elif int(_race.state) == 0: # countdown on the grid
		_put(_left, "LAPS %d" % laps)
		_put(_right, "0:00")
	else:
		_put(_left, "LAP %d/%d" % [clampi(int(lead.lap) if lead else 1, 1, laps), laps])
		_put(_right, clock if (_tick / 8) % 2 == 0 or lead == null else "P1 " + str(lead.name).to_upper().left(_chars - 3))


static func _put(l: Label3D, s: String) -> void:
	if l.text != s: # Label3D rebuilds its mesh on change only
		l.text = s
