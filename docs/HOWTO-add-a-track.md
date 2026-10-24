# How to add a track

A track is data plus optional builder code. The minimum is one entry in
`scripts/track/track_defs.gd`; everything else (terrain style, themed scenery, set pieces,
wildlife) is layered on by files keyed on the track's `id` or `theme`. Read
[ARCHITECTURE.md](ARCHITECTURE.md) for the overall build pipeline first.

## How a track is built

`Circuit.build(def)` in `scripts/track/circuit.gd` runs these steps in order:

1. **Sky and weather**: `Weather.create()` from `def.weather` (or `--weather` / the menu).
2. **Terrain**: `Terrain.new(bounds, 460, def.hills, hash(def.id))`, `terrain.configure(def)`
   (style from `Terrain.STYLE[id]` merged with `def.terrain`), then either
   - `fixed_heights = true`: the point heights are the real profile and the land follows them
     (`terrain.set_base(def.points, def.land_bumps)`), or
   - default: the points are laid onto generated hills (`terrain.elevate`), which also adds a
     designed profile (crests, climbs) if `style.design > 0`.

   Then the road is carved into the land and `load(def.terrain_shaper).shape(terrain, curve, def)`
   runs if the def names one.
3. **Tarmac and barriers**: `TrackBuilder.build()` (road, kerbs, gravel traps, guardrails;
   `street = true` gives concrete barriers and no gravel).
4. **Trackside**: `track_props.gd` (marshal posts, hay bales, fences, start gantry).
5. **Scenery**: `Scenery.build()`.
6. **EXTRA_BUILDERS** (each optional): `set_dressing.gd`, `themes.gd` (runs the def's `theme`),
   `ambience.gd`, `road_decals.gd`, `night_lights.gd`, `atmosphere.gd`, `road_leaves.gd`,
   `gimmicks/gimmicks.gd` (runs `dress_<id>.gd`, then `fill_landscape.gd`), `wildlife_builder.gd`.
7. **Grass**, **Hills** (far ring), **Forest** (keeps out of every `no_trees` circle reserved so
   far), then the **racing line** for the bots.

The menu lists every entry of `TrackDefs.TRACKS` automatically.

## Step 1: the track definition

Add a Dictionary to `TRACKS` in `scripts/track/track_defs.gd`. Minimal example:

```gdscript
	{
		id = "seewald",                     # lowercase, unique; used in file names and --track=
		name = "Seewald",                   # shown in the menu
		hills = 18.0,                       # amplitude (m) of the generated hills
		weather = Weather.Kind.CLEAR,       # default condition (0..10, see Weather.NAMES)
		blurb = "2.2 km around a forest lake. Fast sweepers, one tight hairpin.",
		start = Vector3(0, 0, 80),          # a point on the main straight: start/finish line
		points = [                          # closed loop, metres, XZ plane, in driving order
			Vector3(0, 0, 220), Vector3(0, 0, -200), Vector3(60, 0, -300), Vector3(180, 0, -310),
			Vector3(260, 0, -220), Vector3(240, 0, -80), Vector3(320, 0, 40), Vector3(300, 0, 180),
			Vector3(180, 0, 260), Vector3(60, 0, 280),
		],
	},
```

Rules for the points:

- The loop closes itself (do not repeat the first point). Points are smoothed into a spline by
  `TrackBuilder.make_curve`. Space them 50-150 m apart on sweepers; for tight corners use 3-4
  points around the apex (see the hairpins in `alpenpass` and the 90-degree street corners in
  `hafenstadt`, which use extra points at about 9 m spacing to get a clean radius).
- The road is `TrackDefs.ROAD_WIDTH` (12 m) wide. Keep separate parts of the lap at least 40 m
  apart (centre to centre) unless one crosses over the other on a bridge.
- `start` should lie on a straight of at least 150 m: the grid forms behind it.
- With `fixed_heights = true` the `y` of each point is the road height. Keep gradients under
  about 10 % and smooth crests; the car can take off over a sharp crest at speed.

Optional keys (look at the existing entries for working values):

| Key | Used by | Meaning |
|---|---|---|
| `theme` | `themes.gd` | `"coast"`, `"town"`, `"autodromo"`, `"autumn"`, `"alpine"`, `"harbour"`, `"mediterranean"`: themed scenery, also selects the forest mix |
| `street` | `TrackBuilder.configure`, forest belt, fill | walled street circuit: concrete barriers, no gravel, no forest belt, no landscape fill |
| `fixed_heights` | `circuit.gd` | point heights are the real profile |
| `terrain` | `Terrain.configure` | `{bank = [min, max], bowl, relief, design, start_bank}` overrides (see the comment above `Terrain.STYLE` in `scripts/world/terrain.gd`) |
| `terrain_shaper` | `circuit.gd` | path of a script with `static func shape(terrain, curve, def)` |
| `peaks` | `Terrain` | `[[Vector3(x, height, z), radius], ...]` big landforms |
| `land_bumps` | `Terrain.set_base` | `[Vector4(x, z, radius, +/-height), ...]` (fixed_heights tracks) |
| `river`, `river_levels` | `autumn_terrain.gd`, `theme_autumn.gd`, `alpine_terrain.gd` | XZ polyline (upstream first) and water level at source/mouth, for a gorge/river under a bridge |
| `cut`, `tunnel`, `gallery` | autumn/alpine shapers and themes | rock cut, tunnel, avalanche gallery between two nearest lap points |
| `village`, `arch_at`, `market_at`, `harbour_at`, `beach_at`, `headland_at`, `sea` | `theme_mediterranean.gd`, `set_dressing.gd` | anchors for themed set pieces |
| `quay_z` | `harbour_terrain.gd` | the quay edge for the harbour |

## Step 2: terrain character

For a track without `fixed_heights`, add a line to `Terrain.STYLE` in `scripts/world/terrain.gd`
(or put a `terrain = {...}` override in the def):

```gdscript
	"seewald": {bank = [2.5, 9.0], bowl = 36.0, relief = 7.0, design = 1.0},
```

`bank` is the height of the grass banks behind the barriers, `bowl` how much the land rises
50-280 m out (this is what keeps the horizon close and the track enclosed), `relief` mid-scale
hills, `design` the strength of the generated elevation profile. Unknown ids get `DEFAULT_STYLE`.

For special landforms (river valley, rock walls, flat city), write a terrain shaper. Examples:

- `scripts/track/autumn_terrain.gd` (Herbstwald): river channel, rock cut.
- `scripts/track/alpine_terrain.gd` (Alpenpass): mountain cross-section, cuttings and drops,
  gorge. Honour `NO_SHAPER` for debugging, as it does.
- `scripts/track/harbour_terrain.gd` (Hafenstadt): everything flat except near the road, sea
  floor south of `quay_z`.

```gdscript
class_name SeewaldTerrain
extends RefCounted
## Landforms for Seewald (def.terrain_shaper): the lake basin north of the lap.

static func shape(terrain: Terrain, curve: Curve3D, def: Dictionary) -> void:
	var N := Terrain.N
	for zi in N:
		for xi in N:
			var x := terrain.origin.x + xi * terrain.cell
			var z := terrain.origin.y + zi * terrain.cell
			# ... lower terrain.heights[zi * N + xi] inside the basin, never near the road
```

Never move ground within the carved road band (the road mesh is already built from the curve);
read `harbour_terrain.gd` for how to keep a band around the road untouched.

## Step 3: forest, landmarks, wildlife, fill (per-id tables)

These tables are keyed on the track id (some fall back to the theme or a default). Add entries
so the new track is dressed like the others:

| File | Table | Purpose |
|---|---|---|
| `scripts/world/world_builder.gd` | `FOREST_MIX` | `[spruce, pine, beech, oak, birch]` weights (by id, then theme, then `DEFAULT_MIX`) |
| `scripts/track/set_dressing.gd` | `LANDMARKS` | distant landmarks (`sign`, `mast`, `castle`, `viaduct`, `quarry`); unknown ids get Kiefernring's |
| `scripts/world/wildlife_builder.gd` | `FOREST`, `FARM` | which animal sets appear |
| `scripts/track/gimmicks/fill_landscape.gd` | `PROFILES` | field boundaries, tree lines, barns, crowds, infrastructure 20-300 m out. **A track without a profile gets no landscape fill**, so add one (street circuits are skipped) |
| `scripts/modes/championship.gd` | `SERIES` | optionally add the track to a championship |

## Step 4: themed scenery (optional)

Reuse an existing `theme` if it fits. A new theme means:

1. A file `scripts/track/theme_<name>.gd` with `static func build(themes: TrackThemes) -> void`.
   It gets the `TrackThemes` instance, whose helpers do the batching: lap samples
   (`centers`, `rights`, `tangents`, `corner`), `_fits()` / `_mark()` for building footprints,
   `_st(key, at)` for per-material, per-320 m-cell SurfaceTools, `_mm_set()` / `_mm_add()` for
   MultiMeshes, `_house()`, `_tree_set()`. See `theme_alpine.gd` (Alpenpass) and
   `theme_harbour.gd` (Hafenstadt) for complete examples, including how they keep `skip`
   ranges free for set pieces and add `no_trees` circles.
2. A branch in `TrackThemes._run()` (`scripts/track/themes.gd`):
   ```gdscript
   		"lake":
   			load("res://scripts/track/theme_lake.gd").build(self)
   ```
3. Optionally a `FOREST_MIX` entry for the theme name.

## Step 5: set pieces (dress file)

Create `scripts/track/gimmicks/dress_<id>.gd`; `gimmicks.gd` calls it automatically. Start from
`scripts/track/gimmicks/dress_example.gd.txt` and see
[HOWTO-add-a-gimmick.md](HOWTO-add-a-gimmick.md). Real examples: `dress_alpenpass.gd` (fans on
hairpins, chairlift, beer garden, helicopter) and `dress_hafenstadt.gd` (drive-through warehouse,
tunnel, flyovers, gantries, graffiti, night city lighting).

## Step 6: checks

Run these in order (details in [CONTRIBUTING.md](../CONTRIBUTING.md#4-testing-workflow)):

```sh
# 1. parse + build
LIMIT=120 tools/hrun.sh res://scenes/race.tscn --quit-after 120 -- --bots=0 --track=seewald 2>&1 | grep -E "SCRIPT ERROR|Parse|ERROR"
# 2. build time per step
tools/hrun.sh res://tests/load_profile.tscn -- --track=seewald
# 3. bots race: everyone finishes, few stuck resets
LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --track=seewald
# 4. off-track recovery
for t in "" =gravel =kerb =kerb_out; do tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=seewald --offtrack_test$t; done
# 5. pop audit: nothing large switches on ahead
tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=seewald --pop-audit
# 6. screenshots round the lap (one windowed run)
tools/bgrun.sh res://scenes/race.tscn -- --track=seewald --bots=0 --dress_shots=/tmp/seewald --dress_at=100,500,900,1400,1800
# 7. fps gate
TRACKS="seewald" tools/perfcheck.sh
```

`--dress_shots` needs `DressShots.attach(c)` in your dress file (see `dress_alpenpass.gd`). Look
at the screenshots for: empty plains or open vistas (fill them), cheap-looking geometry, trees
inside the run-off, objects inside the road footprint, the horizon showing the edge of the world.

Also drive it yourself in each weather (`--weather=0..10`) and check that the default weather in
the menu card is right.
