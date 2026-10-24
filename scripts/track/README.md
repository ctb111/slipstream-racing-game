# scripts/track/

Turns a track definition (a closed loop of control points plus a few keys) into a complete circuit: the
spline, the road with kerbs, verges, gravel and barriers, all trackside props, per-theme scenery, terrain
landforms, night lighting, and the shared kits those builders use. The Gx set-piece kit and per-track
dressing live in [`gimmicks/`](gimmicks/README.md).

The full build order is in `circuit.gd` `build()` and drawn in
[`docs/ARCHITECTURE.md#3-how-a-track-is-built`](../../docs/ARCHITECTURE.md#3-how-a-track-is-built).

## Files

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `track_defs.gd` | `TrackDefs` | The catalogue: 12 circuits as dictionaries (`id`, `name`, `blurb`, `points`, `start`, `hills`, `weather`, optional `theme`, `terrain`, `terrain_shaper`, `fixed_heights`, `street`, `peaks`, theme anchors). `ROAD_WIDTH = 12.0`. | `TRACKS`, `TrackDefs.get_track(id)` |
| `circuit.gd` | `Circuit` (`Node3D`) | One complete circuit and its build pipeline: weather, ground, terrain, road, props, scenery, `EXTRA_BUILDERS`, grass, hills, forest, racing line. Holds `def`, `curve`, `line`, `start_offset`, `terrain`, `weather`. | `build(def)` (await it), `grid_transform(slot)`, signal `build_progress`, `EXTRA_BUILDERS`, `load_times` |
| `track_builder.gd` | `TrackBuilder` | Spline through the points; road ribbon (UVs and per-vertex data for `road.gdshader`: racing-line wear, braking / traction zones), FIA kerbs on corners, dirt verge, gravel traps scaled by corner sharpness, guardrails (or concrete Jersey barriers on street circuits), and their colliders with `grip` / `drag` metadata. | `configure(def)`, `make_curve(points)`, `build(parent, curve, width, mats, terrain)`; consts `CURB_WIDTH`, `GRAVEL_MAX`; `_corner_factors()` (used widely) |
| `track_props.gd` | `TrackProps` | Generic trackside detail on every track: start/finish line, grid boxes and start gantry with lights, pits and grandstand, bridge, brake boards, chevrons, invented-sponsor advertising, tyre walls, hay bales, catch fences, marshal posts, flags, bushes, rocks. Merged per material with a shared text atlas. | `TrackProps.build(parent, lap_curve, width, noise)` |
| `scenery.gd` | `Scenery` | Life around the circuit: spectator groups with tents and cars, villages, barns, church, windmill, lake, balloon. | `Scenery.build(parent, lap_curve, width, preset)` |
| `set_dressing.gd` | `SetDressing` | 70s/80s race-weekend dressing: paddock with transporters and helicopter, pit-lane life, skyline landmarks, flag marshals, rally clutter on the verges. Vertex-coloured meshes merged per 100 m cell, one material, no collision. | `SetDressing.build(...)` (an `EXTRA_BUILDERS` entry) |
| `themes.gd` | `TrackThemes` | Theme scenery for defs with `theme`: implements `coast`, `town`, `autodromo` itself, dispatches `autumn`, `harbour`, `alpine`, `mediterranean` to their files, and provides the shared batching helpers (geometry merged per material and 320 m cell, MultiMesh sets, occupancy grid, distance-to-track queries). | `TrackThemes.build(...)` (an `EXTRA_BUILDERS` entry); helpers `rail_dist`, `gravel_depth`, `heights_at` |
| `theme_autumn.gd` | `AutumnTheme` | Herbstwald: river and stone arch bridge, rock cut and tunnel, drive-through sawmill, village and church, hunting lodge, camps, fallen leaves. | `AutumnTheme.build(themes)` |
| `theme_alpine.gd` | `AlpineTheme` | Alpenpass: gorge with waterfall and arch bridge, rock faces on cuttings, parapets, avalanche gallery, summit tunnel, village, hotel. | `AlpineTheme.build(themes)` |
| `theme_harbour.gd` | `HarbourTheme` | Hafenstadt night street circuit: continuous city blocks with photo facades, skyline, port, waterfront, rail crossing, elevated motorway walls. | `HarbourTheme.build(themes)` |
| `theme_mediterranean.gd` | (none, `extends TrackThemes`) | Capo Rosso: the coast theme plus a hilltop village with an arch over the road, drive-through fish market, terraces, Mediterranean flora. | loaded by `themes.gd` when `theme == "mediterranean"` |
| `autumn_terrain.gd` | `AutumnTerrain` | Terrain shaper: river channel along `def.river`, rock cut along `def.cut`. | `shape(terrain, curve, def)`, `river_samples(...)` |
| `alpine_terrain.gd` | `AlpineTerrain` | Terrain shaper: mountain-road cross-section (cutting uphill, drop downhill) and the gorge. | `shape(...)`, `flat_widths(...)` |
| `harbour_terrain.gd` | `HarbourTerrain` | Terrain shaper: flat city away from the road, land drops into the harbour south of the quay. | `shape(...)` |
| `night_lights.gd` | `NightLights` | Night presets only: floodlight masts (mostly at corners), town lanterns, coastal sodium lamps, lit start area. Every lamp is one shadowless SpotLight that fades and culls at short range; poles, heads and halos are MultiMeshes. | `NightLights.build(...)` (an `EXTRA_BUILDERS` entry) |
| `road_decals.gd` | `RoadDecals` | Tyre marks into braking zones and out of slow corners, drain grates and manholes on the straight, all one mesh. | `RoadDecals.build(...)` |
| `trackside_kit.gd` | `TracksideKit` | Reusable WRC-weekend life and set pieces: fan banks, flares, flags, banners, tape, camps, photographers, graffiti walls, painted road messages, arches, footbridges, gantries. Merged per 80 m cell with `VIS` tiers; fx are shader-animated MultiMeshes; no real lights. | `TracksideKit.shared(c)`, `flush(c)`, then many piece methods (`spectator_bank`, `inflatable_arch`, ...), `commit()` |
| `facade_kit.gd` | `FacadeKit` | Photo facades: real windows, doors and shopfronts from one atlas, placed per bay and storey by `shaders/theme_facade.gdshader` on plain wall quads (lit at night). | `material(...)`, `add_wall(...)`, `unit_material(...)`, `add_unit(...)`, `cell_size(...)` |
| `trackside_uv.gd` | `TracksideUV` | GENERATED by `tools/make_trackside_atlas.py`: atlas regions of `assets/trackside/*.png`. Do not edit by hand. | `SIGNS`, region dictionaries |

## How it connects

- `race.gd` calls `TrackDefs.get_track(id)` and `await circuit.build(def)`.
- `circuit.gd` calls into `scripts/world/` for weather, ground, terrain, grass, hills and forest, and into
  `scripts/race/racing_line.gd` at the end.
- Every `EXTRA_BUILDERS` entry (`set_dressing.gd`, `themes.gd`, `world/ambience.gd`, `road_decals.gd`,
  `night_lights.gd`, `world/atmosphere.gd`, `world/road_leaves.gd`, `gimmicks/gimmicks.gd`,
  `world/wildlife_builder.gd`) has the same entry point:
  `static func build(parent: Node3D, lap_curve: Curve3D, road_width: float, weather_preset: Dictionary)`.
- Shared kits used from here: `world/people.gd` (crowds), `world/materials.gd` (`Mats` PBR library),
  `world/vegetation.gd` (theme trees), `facade_kit.gd`, `trackside_kit.gd`.
- Textures: `assets/textures/`, `assets/road/`, `assets/themes/`, `assets/trackside/`, `assets/materials/`.

## Adding a track

1. Add a dictionary to `TrackDefs.TRACKS` (closed loop of points in metres, `start` on the main straight).
2. Optionally a `Terrain.STYLE` entry (`scripts/world/terrain.gd`) or a `terrain = {...}` override in the def.
3. Optionally `theme` (reuse an existing one, or add a `theme_<name>.gd` and a branch in `TrackThemes._run`).
4. Optionally `scripts/track/gimmicks/dress_<id>.gd` with Gx pieces.
5. Check it at 60 fps with `TRACKS="<id>" tools/perfcheck.sh` and with `--pop-audit`.

## Gotchas

- **Offset 0 is the start line only on the lap curve.** Builders receive `_rotated_curve()` (offset 0 = the
  start/finish line, driving direction). `circuit.curve` is the raw spline; convert with `start_offset`.
- **Reserve your footprint.** Register big things with `c.set_meta("no_trees", ...)` (`Gx.reserve`) so the
  forest and later builders avoid them; `themes.gd` reads earlier footprints into `foreign`.
- **Keep the road clear.** Nothing solid inside the road plus kerb plus 1.5 m; anything over the road has
  at least 5.5 m clearance (`TracksideKit.CLEARANCE` is 5.6 m). Use the existing `rail_dist(i, side)` helpers
  to stay behind the barrier.
- **Visibility ranges are measured to the AABB centre.** Merged cells must add their half-diagonal to the
  range (`TracksideKit`, `Gx.add_mesh` do). Fades use `VISIBILITY_RANGE_FADE_SELF`, which is drawn through
  the transparent pipeline while fading; HLOD swaps use `visibility_parent` instead (`themes.gd:426`).
- **Never fix fps by cutting view ranges or scenery.** Merge, MultiMesh, add far LODs. Tracks must feel
  enclosed and nothing may pop in.
- **No real brands.** Sponsors, shops and teams on signs are invented (see `TrackProps` and `themes.gd`
  `SHOPS`).
- **Photo textures, not procedural fakes.** Windows, facades and signs use real photos (`FacadeKit`), never
  shader-drawn imitations.
- `TracksideUV` and the trackside atlases are generated; regenerate with `tools/make_trackside_atlas.py`.
- Seeded RNG only (`hash(def.id)`), so online peers build identical worlds.

## Debug flags and env vars

`--track=<id>`, `--loadprof`, `--debug-scenery`, `--debug-themes`, `--debug-dressing`, `--debug-people`;
env `NO_THEMES=1`, `NO_SHAPER=1`, `TERRAIN_FLAT=1`.

## Where to start reading

`track_defs.gd` (one entry), `circuit.gd` `build()`, `track_builder.gd` `build()`, then `themes.gd` `_run()`
and whichever theme your track uses.
