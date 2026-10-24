class_name AutumnTerrain
extends RefCounted
## Landforms for the Herbstwald circuit (def.terrain_shaper), applied after the
## road is carved and before anything is placed on the ground:
##  - the river valley: a channel with a gravel bed and steep banks, following
##    def.river (XZ polyline, upstream first) with the water surface falling
##    linearly from def.river_levels[0] to [1]; the road crosses it on a bridge
##    (the road deck keeps its own height, the ground drops away beneath it);
##  - the rock cut: along def.cut the land rises in near-vertical walls just
##    behind the guardrails instead of the usual gentle embankment.

const RIVER_STEP := 4.0
const BED_HALF := 4.5 ## metres of flat river bed either side of the centre
const BANK := 9.0 ## top of the near bank
const VALLEY_SLOPE := 0.42 ## rise per metre beyond the bank
const CUT_FLAT := 14.0 ## metres from the centreline that stay at road level in the cut
const CUT_SLOPE := 2.6 ## wall steepness (rise per metre)


## River centreline every RIVER_STEP metres: Vector3(x, water level, z).
static func river_samples(def: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pts: Array = def.get("river", [])
	if pts.size() < 2:
		return out
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var n := pts.size()
	for i in n:
		var p := Vector3(pts[i].x, 0, pts[i].y)
		var prev: Vector2 = pts[maxi(i - 1, 0)]
		var nxt: Vector2 = pts[mini(i + 1, n - 1)]
		var h := Vector3(nxt.x - prev.x, 0, nxt.y - prev.y) / 6.0
		c.add_point(p, -h, h)
	var length := c.get_baked_length()
	var lv: Array = def.get("river_levels", [5.0, 1.0])
	var count := int(length / RIVER_STEP)
	for i in count + 1:
		var t := float(i) / count
		var p := c.sample_baked(t * length)
		p.y = lerpf(lv[0], lv[1], t)
		out.append(p)
	return out


static func shape(terrain: Terrain, curve: Curve3D, def: Dictionary) -> void:
	_rock_cut(terrain, curve, def)
	_river(terrain, def)


static func _river(terrain: Terrain, def: Dictionary) -> void:
	var samples := river_samples(def)
	var N := Terrain.N
	var reach := 70.0
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
				if d < BED_HALF:
					target = s.y - 1.8
				elif d < BANK:
					target = lerpf(s.y - 1.8, s.y + 0.7, smoothstep(BED_HALF, BANK, d))
				else:
					target = s.y + 0.7 + (d - BANK) * VALLEY_SLOPE
				var k := zi * N + xi
				if target < h[k]:
					h[k] = target
	terrain.heights = h


static func _rock_cut(terrain: Terrain, curve: Curve3D, def: Dictionary) -> void:
	var cut: Array = def.get("cut", [])
	if cut.size() < 2:
		return
	var length := curve.get_baked_length()
	var o0 := curve.get_closest_offset(Vector3(cut[0].x, terrain.height_at(cut[0].x, cut[0].y), cut[0].y))
	var o1 := curve.get_closest_offset(Vector3(cut[1].x, terrain.height_at(cut[1].x, cut[1].y), cut[1].y))
	var span := fposmod(o1 - o0, length)
	var N := Terrain.N
	var reach := 70.0
	var r := int(ceil(reach / terrain.cell))
	var best := {} # cell index -> lowest wall height over the cut's samples
	var steps := int(span / 2.0)
	for i in steps + 1:
		var off := fposmod(o0 + i * 2.0, length)
		var s := curve.sample_baked(off)
		# Walls grow out of the embankment at both ends.
		var ramp := smoothstep(0.0, 45.0, i * 2.0) * smoothstep(span, span - 45.0, i * 2.0)
		var slope := lerpf(0.35, CUT_SLOPE, ramp)
		# Only cells BESIDE this sample: never raise ground ahead of the cut's
		# ends, where the road itself runs.
		var tn := curve.sample_baked(fposmod(off + 1.0, length)) - curve.sample_baked(fposmod(off - 1.0, length))
		var tl := maxf(Vector2(tn.x, tn.z).length(), 0.001)
		var tx := tn.x / tl
		var tz := tn.z / tl
		var cx := int(round((s.x - terrain.origin.x) / terrain.cell))
		var cz := int(round((s.z - terrain.origin.y) / terrain.cell))
		for zi in range(maxi(cz - r, 0), mini(cz + r + 1, N)):
			var dz := terrain.origin.y + zi * terrain.cell - s.z
			for xi in range(maxi(cx - r, 0), mini(cx + r + 1, N)):
				var dx := terrain.origin.x + xi * terrain.cell - s.x
				if absf(dx * tx + dz * tz) > 1.6:
					continue
				var d := sqrt(dx * dx + dz * dz)
				if d > reach:
					continue
				var target := s.y - 0.15 + maxf(d - CUT_FLAT, 0.0) * slope
				var k := zi * N + xi
				if not best.has(k) or target < best[k]:
					best[k] = target
	var h := terrain.heights
	for k: int in best:
		var x := terrain.origin.x + (k % N) * terrain.cell
		var z := terrain.origin.y + (k / N) * terrain.cell
		var natural := terrain.land(x, z)
		h[k] = maxf(h[k], minf(natural, best[k]))
	terrain.heights = h
