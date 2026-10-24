class_name RacingLine
extends RefCounted
## Precomputed line and target speeds for AI drivers, plus cheap "where am I
## along the lap" lookups used for positions and lap counting.

const STEP := 2.0
const GRAVITY := 9.81
## What the bots plan with on a dry road at skill 1.0: cornering force in g
## (the arcade tyres + turn assist hold ~1.5-1.9 g) and braking in m/s² (the
## car stops at ~15 m/s²). Skill scales the speeds from there.
const AI_LAT_G := 1.45
const AI_BRAKE := 12.5
const EDGE_MARGIN := 1.5 ## racing line keeps the car's centre this far inside the road edge
const CREST_LOAD := 0.75 ## over a crest, at most this much of the car's weight may "float"

var curve: Curve3D
var length := 0.0
var centers := PackedVector3Array()
var rights := PackedVector3Array()
var points := PackedVector3Array() ## the racing line itself
var lateral := PackedFloat32Array() ## racing line offset from the centreline, metres (+ = right)
var half_width := 4.2 ## how far from the centreline a car may aim
var speeds := PackedFloat32Array() ## max sensible speed (m/s) at each sample, braking included
var built_grip := 1.0 ## tarmac grip multiplier the speeds were planned for


func _init(track_curve: Curve3D, road_width: float, grip := 1.0, braking := 7.5) -> void:
	curve = track_curve
	length = curve.get_baked_length()
	var n := int(length / STEP)
	for i in n:
		var off := i * length / n
		var p := curve.sample_baked(off)
		var ahead := curve.sample_baked(fmod(off + 1.0, length))
		var behind := curve.sample_baked(fmod(off - 1.0 + length, length))
		centers.append(p)
		rights.append((ahead - behind).normalized().cross(Vector3.UP).normalized())

	# Racing line: the minimum-curvature path inside the road (out-in-out,
	# straightened chicanes), relaxed on a coarse grid, then smoothed.
	var half := road_width * 0.5 - EDGE_MARGIN
	half_width = road_width * 0.5 - 1.8
	lateral = _min_curvature_line(half)
	for i in n:
		points.append(centers[i] + rights[i] * lateral[i])

	# Corner speed from the line's own curvature (lateral grip), plus crests:
	# over a sharp brow the car goes light, so don't arrive faster than the
	# tyres stay loaded.
	var kl := _curvature(points)
	var crest := _crest_curvature()
	speeds.resize(n)
	for i in n:
		var r := 1.0 / maxf(absf(kl[i]), 0.0005)
		var v := minf(sqrt(grip * GRAVITY * r), 85.0)
		if crest[i] > 0.0005:
			v = minf(v, sqrt(CREST_LOAD * GRAVITY / crest[i]))
		speeds[i] = v
	# Backwards pass for braking: the tyres' grip is shared between braking and
	# cornering (friction circle), so trail-brake into the turn, no harder.
	var ds := length / n
	for _sweep in 2:
		for i in range(n - 1, -1, -1):
			var nxt := speeds[(i + 1) % n]
			var lat_use := nxt * nxt * absf(kl[i]) / (grip * GRAVITY)
			var dec := braking * sqrt(maxf(1.0 - lat_use * lat_use, 0.25))
			speeds[i] = minf(speeds[i], sqrt(nxt * nxt + 2.0 * dec * ds))


## Lateral offsets of the minimum-curvature line: Gauss-Seidel relaxation of
## each point towards the midpoint of its neighbours, clamped to the road, from
## a coarse stencil (whole corners) down to a fine one.
func _min_curvature_line(half: float) -> PackedFloat32Array:
	var n := centers.size()
	var step := 4 # coarse grid: 8 m
	var m := n / step
	var c := PackedVector3Array()
	var r := PackedVector3Array()
	var lat := PackedFloat32Array()
	c.resize(m)
	r.resize(m)
	lat.resize(m)
	for j in m:
		c[j] = centers[j * step]
		r[j] = rights[j * step]
	for k: int in [6, 3, 2, 1]:
		for _it in 30:
			for j in m:
				var a: int = (j - k + m) % m
				var b: int = (j + k) % m
				var mid := (c[a] + r[a] * lat[a] + c[b] + r[b] * lat[b]) * 0.5
				lat[j] = clampf((mid - c[j]).dot(r[j]), -half, half)
	# Back to the full-resolution samples, smoothed.
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var f := float(i) / step
		var j0 := int(f) % m
		out[i] = lerpf(lat[j0], lat[(j0 + 1) % m], f - floorf(f))
	out = _smooth(out, 3)
	for i in n:
		out[i] = clampf(out[i], -half, half)
	return out


## Downward-bending (crest) vertical curvature of the centreline, 1/m, >= 0.
func _crest_curvature() -> PackedFloat32Array:
	var n := centers.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var d := 4
	var h := d * length / n
	for i in n:
		var y0 := centers[(i - d + n) % n].y
		var y1 := centers[i].y
		var y2 := centers[(i + d) % n].y
		out[i] = maxf(-(y0 - 2.0 * y1 + y2) / (h * h), 0.0)
	return _smooth(out, 2)


func _curvature(pts: PackedVector3Array) -> PackedFloat32Array:
	var n := pts.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var a := pts[(i - 3 + n) % n]
		var b := pts[i]
		var c := pts[(i + 3) % n]
		var angle := (b - a).signed_angle_to(c - b, Vector3.UP)
		out[i] = angle / maxf((a.distance_to(b) + b.distance_to(c)) * 0.5, 0.01)
	return out


func _smooth(v: PackedFloat32Array, k: int) -> PackedFloat32Array:
	var n := v.size()
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var acc := 0.0
		for j in range(-k, k + 1):
			acc += v[(i + j + n) % n]
		out[i] = acc / (2 * k + 1)
	return out


func count() -> int:
	return centers.size()


func offset_of(index: int) -> float:
	return index * length / count()


## Nearest centreline sample to `pos`. Pass the previous result as `hint` to
## search only nearby samples (cheap enough to call every physics tick).
func closest_index(pos: Vector3, hint := -1) -> int:
	var n := count()
	var best := 0
	var best_d := INF
	if hint < 0:
		for i in n:
			var d := centers[i].distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = i
		return best
	for j in range(-8, 30):
		var i := (hint + j + n) % n
		var d := centers[i].distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = i
	if best_d > 60.0 * 60.0: # lost (reset / teleport): full search
		return closest_index(pos, -1)
	return best


func point_ahead(index: int, metres: float) -> Vector3:
	var n := count()
	var f := metres / (length / n)
	var i0 := int(floor(f))
	var t := f - i0
	return points[(index + i0) % n].lerp(points[(index + i0 + 1) % n], t)


## Point `metres` ahead on the centreline, shifted `lat` metres to the right.
func lane_point(index: int, metres: float, lat: float) -> Vector3:
	var n := count()
	var i := (index + int(metres / (length / n))) % n
	return centers[i] + rights[i] * clampf(lat, -half_width, half_width)


func lateral_of(pos: Vector3, index: int) -> float:
	return (pos - centers[index]).dot(rights[index])


func speed_ahead(index: int, metres: float) -> float:
	var n := count()
	return speeds[(index + int(metres / (length / n))) % n]


## Transform on the centreline at a lap offset, facing the direction of travel.
func transform_at(offset: float, lateral := 0.0, height := 0.7) -> Transform3D:
	var off := fposmod(offset, length)
	var p := curve.sample_baked(off)
	var ahead := curve.sample_baked(fposmod(off + 3.0, length))
	var basis := Basis.looking_at((ahead - p).normalized(), Vector3.UP)
	return Transform3D(basis, p + basis.x * lateral + Vector3.UP * height)
