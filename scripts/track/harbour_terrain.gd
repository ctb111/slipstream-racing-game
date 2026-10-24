class_name HarbourTerrain
extends RefCounted
## Landforms for the Hafenstadt street circuit (def.terrain_shaper):
##  - the city is flat (y = 0) everywhere more than ROAD_BAND metres from the
##    road, so where the road profile climbs (the elevated motorway) it stands
##    above the streets on retaining walls (theme_harbour.gd builds the walls);
##  - south of the waterfront quay (def.quay_z) the land drops to the harbour
##    floor, under the sea plane.

const SEA_FLOOR := -7.0
const ROAD_BAND := 13.0 ## metres from the centreline kept at road level (pavement)


static func shape(terrain: Terrain, curve: Curve3D, def: Dictionary) -> void:
	var qz := float(def.get("quay_z", 1e9))
	var N := Terrain.N
	var h := terrain.heights
	var near := PackedByteArray()
	near.resize(N * N)
	var r := int(ceil(ROAD_BAND / terrain.cell))
	var length := curve.get_baked_length()
	for i in int(length / 2.0):
		var s := curve.sample_baked(i * 2.0)
		var cx := int(round((s.x - terrain.origin.x) / terrain.cell))
		var cz := int(round((s.z - terrain.origin.y) / terrain.cell))
		for zi in range(maxi(cz - r, 0), mini(cz + r + 1, N)):
			var dz := terrain.origin.y + zi * terrain.cell - s.z
			for xi in range(maxi(cx - r, 0), mini(cx + r + 1, N)):
				var dx := terrain.origin.x + xi * terrain.cell - s.x
				if dx * dx + dz * dz <= ROAD_BAND * ROAD_BAND:
					near[zi * N + xi] = 1
	for zi in N:
		var z := terrain.origin.y + zi * terrain.cell
		var sea := z > qz - 1.0
		for xi in N:
			var k := zi * N + xi
			if sea:
				h[k] = SEA_FLOOR
			elif near[k] == 0:
				h[k] = minf(h[k], 0.0) if h[k] < 0.0 and h[k] > -0.3 else 0.0
	terrain.heights = h
