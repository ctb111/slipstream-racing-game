# AGENTS.md: guide for AI coding assistants

This file is for AI coding assistants (Claude Code, Codex, Cursor, Copilot agents, and so on)
working on Slipstream. It is self-contained; humans should read
[CONTRIBUTING.md](CONTRIBUTING.md), which covers the same rules in more detail. Architecture:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Task guides: `docs/HOWTO-*.md`.

## Project facts

- **Engine:** Godot 4.7.x (developed on 4.7.2), GDScript only, **Jolt** physics at 120 Hz with
  physics interpolation, **Forward+** renderer. Autoloads: `Game` (settings, session state) and
  `Net` (LAN lobby). Scenes: `scenes/menu.tscn` (main), `scenes/race.tscn`.
- **Almost everything is built from code at load time**: tracks from control points
  (`scripts/track/track_defs.gd`) through `Circuit.build()` (`scripts/track/circuit.gd`), cars
  from glTF models described in `scripts/car/car_catalog.gd`. There are very few hand-made scenes.
- **12 tracks** (ids): `kiefernring hochwald valle_club brackenmoor schneekopf kuestenstrasse
  altstadt valtellina capo_rosso herbstwald alpenpass hafenstadt`.
- **6 cars** (ids): `porsche930 bmw_e30_m3 datsun_240k toyota_ae86 mazda_rx7_fc ferrari_f40`.
- **Weather conditions** (`--weather=N`, `Weather.NAMES`): 0 Clear, 1 Storm, 2 Snow, 3 Golden
  hour, 4 Night, 5 Night rain, 6 Night snow, 7 Changeable, 8 Changeable night, 9 Dawn, 10 Fog.
- **Target hardware:** fanless M1 MacBook Air. The dev machine is shared: assume other processes
  (and possibly the user playing the game) are running.
- Licence: MIT for code and original assets; third-party assets keep their own licences.

## Running the game: always through the wrappers

Never launch Godot directly for tests. Use:

```sh
tools/hrun.sh <godot args>                              # headless (logic, no GPU)
tools/bgrun.sh <scene> [godot args] -- [game args]      # windowed, in the background
```

Why:

- **Never steal focus.** The user may be working or playing. `bgrun.sh` starts Godot with
  macOS `open -g` so the window opens behind everything and never takes keyboard focus. Any run
  with game arguments also skips the saved window settings and keeps to the background.
- **Silent.** Test runs use `--audio-driver Dummy`, and the game mutes itself whenever it has
  game arguments (except `--write-movie`, which records audio into the file).
- **One queue.** Both wrappers source `tools/lock.sh`, a fair first-come-first-served queue:
  the `gpu` lane (windowed, two slots: two screenshot runs may run side by side) and the `cpu`
  lane (headless, one slot). `perfcheck.sh` takes both gpu slots at once for clean numbers. The
  gpu lane also waits while a real game window is open (the user playing).
- **Watchdog.** Runs are killed after `LIMIT` seconds (default 300). Set `LIMIT=` for long runs.
- **Class cache.** The wrappers re-import when any script is newer than the class cache, so new
  `class_name` files resolve.
- `bgrun.sh` forwards the env vars `VEG_OFF NO_THEMES VEG_DEBUG FOREST_OFF GRASS_OFF TERRAIN_FLAT BELT_OFF FILL_OFF NO_DRESS NO_SHAPER` to the game (headless runs inherit the whole environment).
- Save files: runs with game arguments use `user://test/`, never the player's real progress.

Prefer headless checks for logic. Use windowed runs only for screenshots and fps.

### Run budget and queue etiquette

- Build first, test at milestones. Batch: **one** parse check after a group of edits, **one**
  screenshot run that captures several views (`--dress_shots`, `--gx_test`/`--gx_shots`,
  `--fxshots`, `--pop-shots`), **one** perfcheck at the end.
- Never poll-loop runs, never re-run the same test without a code change in between. Aim for no
  more than about six windowed runs per hour.
- Always run perfcheck on a **subset**: `TRACKS="<only your tracks>" tools/perfcheck.sh`. The full
  run takes about 15 minutes and blocks every windowed run.
- Queue your screenshot runs before your perfcheck; never run several perfchecks at once.
- Read run output from the wrapper; do not open extra Godot instances to "check".

## Never leave a file broken

A parse error in **any** script breaks every run of the game (Godot compiles all scripts that are
loaded, and builders are loaded dynamically). After each group of edits:

```sh
LIMIT=60 tools/hrun.sh res://scenes/race.tscn --quit-after 60 -- --bots=0 --track=kiefernring 2>&1 \
  | grep -E "SCRIPT ERROR|Parse"
```

No output = clean. If you touched a track-specific file, use that `--track=`.

Common GDScript traps:

- `:=` cannot infer from untyped expressions (Dictionary/Array elements, `get()`, `load()`).
  Write `var v: Vector3 = d.pos`, not `var v := d.pos`.
- Typed arrays do not accept untyped ones: `var a: Array[Vector3] = []` then `append`.
- `class_name` collisions: grep for the name before adding a new class.
- Other contributors may edit the same files: re-read a file right before editing it, keep edits
  to shared files (track defs, catalogs, `race.gd`, `themes.gd`) small.
- Do not commit, push or create branches unless the user asks.

## Code map (short)

| Area | Files |
|---|---|
| Race flow, args, network sync, screenshots | `scripts/race/race.gd` |
| Bots | `scripts/race/ai_driver.gd`, `racing_line.gd` |
| Car physics / model / audio / cockpit | `scripts/car/car.gd`, `car_model.gd`, `car_catalog.gd`, `car_audio.gd`, `cockpit.gd` |
| Track build pipeline | `scripts/track/circuit.gd` (calls everything below) |
| Track list | `scripts/track/track_defs.gd` |
| Road, kerbs, gravel, barriers | `scripts/track/track_builder.gd` |
| Themed scenery | `scripts/track/themes.gd` + `theme_*.gd`, terrain shapers `*_terrain.gd` |
| Gimmicks (set pieces) | `scripts/track/gimmicks/` (`gx.gd`, `gx_*.gd`, `dress_<track>.gd`, `fill_landscape.gd`) |
| Terrain, forest, grass | `scripts/world/terrain.gd`, `world_builder.gd`, `vegetation.gd`, `grass.gd` |
| Weather | `scripts/world/weather.gd`, `weather_cycle.gd` |
| LAN | `scripts/autoload/net.gd` |
| UI | `scripts/ui/` |
| Modes | `scripts/modes/` (time trial with ghosts, championship) |

## Gx kit (gimmicks and per-track dressing)

`scripts/track/gimmicks/gx.gd` (read its header). Frames: **+z points away from the road**, y up,
x along the track; a piece built around its origin with its front facing -z faces the road.

| Call | Use |
|---|---|
| `Gx.frame(c, along, side, lateral)` | Transform beside the road, `lateral` m beyond the road **edge** on `Gx.LEFT`/`Gx.RIGHT`, on the ground, -z facing the road |
| `Gx.road_frame(c, along)` | Centred on the road, x along, z to the right: arches, bridges, gantries |
| `Gx.frame_x(c, xf)` | Driving direction at a frame |
| `Gx.centre(c, along)`, `Gx.tangent(c, along)`, `Gx.ground(c, p)` | Centreline point, direction, terrain height |
| `Gx.clear_of_road(c, p, margin)` | Is `p` at least `margin` m outside the road edge (any part of the lap) |
| `Gx.reserve(c, p, radius)` | Keep trees and clutter out of a circle (forest is built after dressing) |
| `Gx.corners(c, min_strength)` | `[{along, turn, strength}]`, sharpest first (`turn` +1 right / -1 left) |
| `Gx.straights(c, min_len)` | `[{from, to}]` |
| `Gx.rng(c, purpose)` | Seeded RNG per track + purpose (same on every machine) |
| `Gx.add_mesh(c, st, mat, name, vis_end, shadows)` | Add a SurfaceTool mesh with a correct, fading visibility range |
| `GxSpot.find(c, alongs, laterals, hx, z0, z1, max_rise)` | First free, flat footprint beside the road, or null |
| `GxGeo.new(xf)` | Merged-mesh builder: `box`, `extrude`, `tube`, `lathe`, `beam`, `sign`, `paint`, `collide`, then `commit(c, name, vis_end)` |
| `GxProps.scatter(c, id, xfs, vis_end)` | Poly Haven CC0 models as one MultiMesh |
| `Mats.mat(type, tint)` | Shared photo PBR materials (`concrete`, `brick`, `plaster`, `stone`, `steel`, ...) |

Pieces: `gx_<piece>.gd` with `class_name Gx<Piece>` and
`static func place(c: Node3D, xf: Transform3D, opts := {}) -> void`.
Per-track dressing: `dress_<track_id>.gd` with `static func dress(c: Node3D) -> void`, called
automatically by `gimmicks.gd`, followed by `fill_landscape.gd` and `GxFans.flush()`.
Debug: `--gx_test=<piece>:<kind>,... --gx_shots=<dir>` places and photographs pieces on any track.
Full guide: [docs/HOWTO-add-a-gimmick.md](docs/HOWTO-add-a-gimmick.md).

## Design taste (the project's own rules)

- **Realistic, photographic, grounded.** Reference level: WRC games, NFS Porsche Unleashed,
  Burnout Paradise. Never "Minecraft-like", cartoony, low-poly-stylised or boxy.
- **Prefer real assets** (permissively licensed photo textures and models) over procedural
  imitations. Good sources: Poly Haven models/textures/HDRIs (CC0,
  `https://api.polyhaven.com/assets?t=models`), ambientCG PBR materials (CC0), Smithsonian 3D
  Open Access (CC0), Wikimedia Commons photographs (check each file). Kenney/Quaternius only if
  the asset is not stylised (usually it is: avoid). Download with `curl`; raw sources go in a
  `src/` folder with a `.gdignore`.
- **No procedurally generated surface detail that pretends to be real** (shader-drawn windows,
  fake signage). Use photo textures or models for windows, facades, signs.
- When geometry must be procedural: real proportions, bevels/insets, trim, photo PBR materials,
  grime/AO, variation. Never plain untextured boxes.
- **Tracks feel enclosed and busy** ("we want to be there, for the race"): forest walls, banks,
  buildings, crowds, no vast empty fields or open vistas. Trees must look full.
- **Gimmicks are welcome**: graffiti, bridges, drive-through warehouses, tunnels, crowds,
  wildlife. More features over fewer.
- **Handling is arcade-leaning** (Burnout Paradise feel) with strong, stable brakes. Bots should
  be hard.
- Out of scope by the choice of the original author: car damage, rally stages, car setup/tuning screens.
- Look at your own screenshots critically, from driver height (chase cam) and close up. If it
  looks cheap, fix it before moving on.
- Anything over the road: at least 5.5 m clear height, never inside the road footprint + 1.5 m.
  Solid parts off the road get collision (`StaticBody3D`, low friction).
- No real logos or trademarks; invented sponsor and shop names only.

## Performance rules

- Hard requirement: **60 fps on Medium with 8 cars** on a fanless M1 MacBook Air.
  Gate: `tools/perfcheck.sh` (avg >= 60, 1%-low >= 45), always with `TRACKS=` subsets.
- **Nothing may appear out of nowhere.** Never fix fps by shortening visibility ranges. Use cheap
  far LODs, impostors, HLOD (merged far meshes per cell) and MultiMesh that stay visible; fades
  must be invisible (LOD cross-fade, distance haze), never pops.
- Merge static geometry (SurfaceTool / GxGeo), MultiMesh for repeats, no shadows on small
  things, few real lights.
- Visibility ranges are measured to the **AABB centre**: extend ranges by the half-diagonal
  (`Gx.add_mesh` does). Short ranges use `VISIBILITY_RANGE_FADE_SELF` with a 20-40 m margin;
  Godot also measures the fade to the AABB centre, so merged cells dissolve smoothly.
- Verify with `--pop-audit` (inventory of short ranges + APPEAR list of hard switch-ons ahead)
  and `--pop-shots=<prefix>,<start s>` (12-frame drive-ahead sequence).
- Find costs with `--perf-ab=<features>` (`tools/perf_ab.gd`) inside one run, not by comparing
  two noisy runs.

## Licensing rules

- Only assets whose licence allows **redistribution and commercial use**: CC0, public domain,
  CC BY, CC BY-SA, SIL OFL, Apache 2.0, MIT/BSD.
- Never NC, ND, editorial-only, personal-use-only or unknown licences. If you cannot verify the
  licence, do not add the asset.
- Credit every asset in the per-folder `assets/<folder>/CREDITS*.txt`, the root `CREDITS.md`, and
  `assets/CREDITS_INGAME.txt` (shown in the in-game Credits screen): title, author, URL, licence,
  changes.

## Checklist before you report a task done

1. Parse check clean.
2. Headless bot race on the affected tracks finishes (`--allbots --fixed-fps 120`).
3. Off-track tests pass where you changed the roadside (`--offtrack_test`, `=gravel`, `=kerb`).
4. `--pop-audit` shows no new large hard switch-ons.
5. One batched screenshot run; you looked at the images.
6. `TRACKS="..." tools/perfcheck.sh` passes.
7. New assets credited in all three places.
