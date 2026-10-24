class_name AlpineTerrain
extends RefCounted
## Landforms for the Alpenpass circuit (def.terrain_shaper), applied after the
## road is carved and before anything is placed on the ground:
##  - mountain-road cross-section everywhere: the ground stays at road level out
##    to just behind the guardrail, then goes straight to the natural mountain:
##    up as a near-vertical rock cutting on the uphill side, down as a steep
##    drop on the valley side (the theme puts stone parapets on those);
##  - the gorge: a narrow, steep-walled river channel along def.river (reuses
##    AutumnTerrain.river_samples) that the road crosses on a stone bridge.

const STEP := 4.0 ## metres between lap samples
const REACH := 70.0 ## metres from the centreline the shaping works to
const K_UP := 1.9 ## cutting wall steepness (rise per metre)
const K_DOWN := 1.3 ## valley drop steepness
const BACK := 2.2 ## metres of level ground behind the guardrail line
const GRADE := 0.1 ## steepest road gradient (allowance along the road)
const GORGE_BED := 4.0
const GORGE_WALL := 2.4


static func shape(terrain: Terrain, curve: Curve3D, def: Dictionary) -> void:
	if OS.has_environment("NO_SHAPER"): # debug bisecting
		return
	_cross_section(terrain, curve)
	_gorge(terrain, def)


## Flat width (from the centreline) per lap sample and side, as the guardrail
## distance TrackBuilder uses (gravel traps on corner outsides) plus BACK.
static func flat_widths(centers: Array[Vector3]) -> Array:
	var corner := TrackBuilder._corner_factors(centers)
	var out := []
	var half := TrackDefs.ROAD_WIDTH * 0.5
	for i in centers.size():
		var w := {}
		for side: float in [1.0, -1.0]:
			var outside := corner[i] * side > 0.0
			var depth := TrackBuilder.GRAVEL_MAX * absf(corner[i]) if outside else 0.0
			w[side] = half + TrackBuilder.CURB_WIDTH + maxf(TrackBuilder.RAIL_GAP, depth + 3.0) + BACK
		out.append(w)
	return out


static func _cross_section(terrain: Terrain, curve: Curve3D) -> void:
	var length := curve.get_baked_length()
	var n := int(length / 2.0)
	var centers: Array[Vector3] = []
	for i in n:
		centers.append(curve.sample_baked(i * length / n))
	var widths := flat_widths(centers) # per 2 m sample (TrackBuilder's corner window)
	var N := Terrain.N
	var r := int(ceil(REACH / terrain.cell))
	var upper := {} # cell -> lowest allowed top (min over samples)
	var lower := {} # cell -> highest allowed bottom (max over samples)
	var stride := int(STEP / 2.0)
	for i in range(0, n, stride):
		var s := centers[i]
		var tn := centers[(i + 1) % n] - centers[(i - 1 + n) % n]
		var rt := Vector3(tn.x, 0, tn.z).normalized().cross(Vector3.UP)
		var cx := int(round((s.x - terrain.origin.x) / terrain.cell))
		var cz := int(round((s.z - terrain.origin.y) / terrain.cell))
		var wr: float = widths[i][1.0]
		var wl: float = widths[i][-1.0]
		for zi in range(maxi(cz - r, 0), mini(cz + r + 1, N)):
			var dz := terrain.origin.y + zi * terrain.cell - s.z
			for xi in range(maxi(cx - r, 0), mini(cx + r + 1, N)):
				var dx := terrain.origin.x + xi * terrain.cell - s.x
				var d2 := dx * dx + dz * dz
				if d2 > REACH * REACH:
					continue
				var d := sqrt(d2)
				var lat := dx * rt.x + dz * rt.z
				var f := wr if lat > 0.0 else wl
				var e := maxf(d - f, 0.0)
				# Ahead / behind this sample the road itself climbs or falls: allow
				# for the grade so a slope never digs a ditch beside the road.
				var along := absf(dx * rt.z - dz * rt.x) * GRADE
				var k := zi * N + xi
				var up := s.y - 0.15 + e * K_UP + along
				var lo := s.y - 0.3 - e * K_DOWN - along
				if not upper.has(k) or up < upper[k]:
					upper[k] = up
				if not lower.has(k) or lo > lower[k]:
					lower[k] = lo
	var h := terrain.heights
	for k: int in upper:
		var x := terrain.origin.x + (k % N) * terrain.cell
		var z := terrain.origin.y + (k / N) * terrain.cell
		var natural := terrain.land(x, z)
		# The road always wins: never above any road's allowance.
		h[k] = minf(maxf(natural, lower[k]), upper[k])
	terrain.heights = h


static func _gorge(terrain: Terrain, def: Dictionary) -> void:
	var samples := AutumnTerrain.river_samples(def)
	var N := Terrain.N
	var reach := 55.0
	var r := int(ceil(reach / terrain.cell))
	var h := terrain.heights
	for s in samples:
		var cx := int(round((s.x - terrain.origin.x) / terrain.cell))
		var cz := int(round((s.z - terrain.origin.y) / terrain.cell))
		for zi in range(maxi(cz - r, 0), mini(cz + r + 1, N)):
			var dz := terrain.origin.y + zi * terrain.cell - s.z
			for xi in range(maxi(cx - r, 0), mini(cx + r + 1, N)):
				var dx := terrain.origin.x + xi * terrain.cell - s.x
				var d := sqrt(dx * dx + dz * dz)
				if d > reach:
					continue
				var target: float
				if d < GORGE_BED:
					target = s.y - 1.6
				else:
					target = s.y - 1.6 + 2.0 * smoothstep(GORGE_BED, GORGE_BED + 2.0, d) + maxf(d - GORGE_BED - 1.0, 0.0) * GORGE_WALL
				var k := zi * N + xi
				if target < h[k]:
					h[k] = target
	terrain.heights = h
