# Contributing to Slipstream

Thanks for wanting to help. Slipstream is a Godot 4.7 circuit racer (GDScript, Jolt physics,
Forward+ renderer) with classic 70s/80s cars, realistic-looking tracks, changing weather and LAN
multiplayer. This guide covers setup, code style, the test and performance workflow, the look and
licensing rules, and how to send changes.

- How the code fits together: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Step-by-step guides: `docs/HOWTO-*.md` (tracks, cars, gimmicks, weather, multiplayer, media)
- Known issues and feature ideas: [docs/ROADMAP.md](docs/ROADMAP.md)
- Tools and tests: [tools/README.md](tools/README.md), [tests/README.md](tests/README.md)
- AI coding assistants: read [AGENTS.md](AGENTS.md)

## 1. Setup

1. Install **Godot 4.7.x** (standard build, not .NET) from <https://godotengine.org/download>.
   The project is developed on 4.7.2. Older 4.x versions will not open it cleanly.
2. Clone the repository.
3. First import: open the editor once (`godot -e --path .`) or run a headless import:
   ```sh
   godot --headless --path . --import
   ```
   The first import converts all models, textures and HDRIs into `.godot/` and takes several
   minutes. `.godot/` is git-ignored; never commit it.
4. Optional, for the helper scripts in `tools/`: `zsh` and `perl` (both ship with macOS).
   `tools/bgrun.sh` is macOS-only (it uses `open -g` and `/Applications/Godot.app`).
   On Linux/Windows run Godot directly with the same arguments.
5. Optional, for regenerating texture atlases: Python 3 with Pillow and numpy; for re-baking trees:
   Blender with the Sapling Tree Gen add-on. See [tools/README.md](tools/README.md).

## 2. Running from source

```sh
godot --path .                                   # the game (main menu)
godot -e --path .                                # the editor
godot --path . res://scenes/race.tscn -- --track=alpenpass --weather=3 --bots=7
```

Everything after `--` is a game argument read by `scripts/race/race.gd` and friends. The useful
ones:

| Argument | Meaning |
|---|---|
| `--track=<id>` | track id from `scripts/track/track_defs.gd` |
| `--car=<id>` | player car id from `scripts/car/car_catalog.gd` |
| `--bots=N` | number of bots (0..7) |
| `--allbots` | the player's car is driven by the AI too; prints lap times and results, quits at the finish |
| `--laps=N`, `--difficulty=0..2` | race length, bot level |
| `--weather=N` | condition index, see `Weather.NAMES` in `scripts/world/weather.gd` (0 Clear, 1 Storm, 2 Snow, 3 Golden hour, 4 Night, 5 Night rain, 6 Night snow, 7 Changeable, 8 Changeable night, 9 Dawn, 10 Fog) |
| `--quality=0..3` | Low, Medium, High, Ultra |
| `--nodynres` | disable adaptive render resolution |
| `--cam=chase\|cockpit\|far\|bumper\|bonnet\|roof\|tv` | camera mode |
| `--screenshot=<png> --shot_at=<s>` | save a frame after `s` seconds, print fps stats, quit |
| `--mode=timetrial\|championship` | game modes (see `scripts/modes/`) |

Any run with game arguments is silent and stays in a background window, and saves progress under
`user://test/` instead of the player's real save files.

Headless smoke tests:

```sh
godot --headless --path . res://tests/handling_test.tscn
godot --headless --fixed-fps 120 --path . res://scenes/race.tscn -- --allbots --laps=2 --track=valle_club
```

## 3. Code style

Follow the code around you. The conventions used throughout:

- **Tabs** for indentation, in GDScript and shaders.
- **Static typing everywhere.** Typed function parameters and return types (`-> void` included),
  typed member variables, typed arrays where practical (`Array[Vector3]`).
- Use `:=` only when the type can be inferred. GDScript cannot infer from untyped expressions
  (Dictionary/Array elements, `get()`, `load()`, ternaries mixing types). Write the type
  explicitly in those cases:
  ```gdscript
  var p: Vector3 = def.points[0]      # not: var p := def.points[0]  (parse error)
  var w: float = float(opts.get("width", 4.0))
  ```
- `class_name` for reusable classes; `static func` builders that take the circuit node
  (`c: Node3D`) for anything that builds scenery. Most builders are `RefCounted` with static
  functions, not scenes.
- **Doc comments with `##`** at the top of every file (what it is, how to call it, debug flags) and
  on public functions/consts. Plain `#` comments explain *why*, not *what*. Match the density of
  the file you are in: short, specific, real-world units (metres, km/h, seconds).
- Units: metres, seconds, kilograms, radians in code (degrees only where a comment says so).
  Road coordinates: `along` = metres round the lap from the start line.
- Deterministic randomness: seed from the track (`Gx.rng(c, "purpose")`, `hash(def.id)`), never
  `randomize()` in world building. Every machine in an online race must build the same track.
- Debug switches are game arguments (`--something`) or environment variables, documented in the
  file's header comment. They must do nothing when absent.
- Keep a missing optional file harmless: builders are loaded through `ResourceLoader.exists()`
  checks so the game still runs without them.
- No new autoloads or plugins without discussing it first.

## 4. Testing workflow

Godot reports a parse error in **any** script as a broken game. Run a parse check after every
group of edits:

```sh
LIMIT=60 tools/hrun.sh res://scenes/race.tscn --quit-after 60 -- --bots=0 --track=kiefernring 2>&1 \
  | grep -E "SCRIPT ERROR|Parse"
```

No output means clean. The run wrappers:

- **`tools/hrun.sh <godot args>`**: headless run (no window, no GPU), killed after `LIMIT`
  seconds (default 300). Use it for logic: parse checks, bot races, off-track tests, pop audits.
- **`tools/bgrun.sh <scene> [godot args] -- [game args]`**: windowed run that stays in the
  background (macOS `open -g`), silent (`--audio-driver Dummy`), never steals keyboard focus,
  output printed when it exits. Use it for screenshots and fps. Pass `""` as the scene for the
  main menu.
- **`tools/lock.sh`** (sourced by both): a fair first-come-first-served queue so several runs on
  one machine never overlap. Windowed runs use the `gpu` lane (two slots, so two screenshot runs
  can run side by side); headless runs use the `cpu` lane (one slot). The gpu lane also waits
  while a real game window is open. Both wrappers refresh Godot's class cache when a script
  changed, so new `class_name` files are picked up.

Checks to run, in order of cost:

1. **Parse check** (above).
2. **Bots race headless**: `LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --track=<id>`.
   Every car must finish; watch for `stuck reset:` lines and the `crashes` / `stuck` / `off`
   columns in the final standings.
3. **Off-track tests** (cars must get back onto the road from grass, gravel and kerbs):
   ```sh
   tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=<id> --offtrack_test
   tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=<id> --offtrack_test=gravel
   tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=<id> --offtrack_test=kerb
   tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=<id> --offtrack_test=kerb_out
   ```
   Expect `BACK ON TRACK` / `REACHED ROAD`, not `STUCK` / `BLOCKED`.
4. **Pop audit** (nothing may appear out of nowhere):
   `tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=<id> --pop-audit`.
   It prints an inventory of short visibility ranges and an APPEAR list of hard switch-ons ahead
   of the camera, ranked by on-screen size. `soft` entries fade and are fine.
5. **Screenshots** (`tools/bgrun.sh`, see [docs/HOWTO-capture-media.md](docs/HOWTO-capture-media.md)).
   Look at them critically from driver height and close up.
6. **Performance gate** (below).

Batch your checks: one parse check after a group of edits, one screenshot run that captures
several views, one perfcheck at the end. Do not re-run the same test without a code change in
between.

## 5. Performance rules

The target is a **fanless M1 MacBook Air at Medium quality with 8 cars on track: average 60 fps
or more, 1%-low 45 fps or more**, on every track. A feature is done when it passes this gate.

```sh
TRACKS="hafenstadt alpenpass" tools/perfcheck.sh     # the tracks you touched
tools/perfcheck.sh                                     # all 12 tracks (about 15 minutes)
tools/perfcheck.sh --weather=5                         # extra game args go to every case
```

`perfcheck.sh` runs each track windowed with `--allbots --bots=7 --quality=1 --disable-vsync`,
adaptive resolution on, and prints `avg`, `low1%`, worst frame and the 3D scale. Numbers only mean
something on a quiet machine (load average below about 6; it prints it).

To find what a feature costs, measure ON/OFF inside one run with `tools/perf_ab.gd`:

```sh
tools/bgrun.sh res://scenes/race.tscn --disable-vsync -- --allbots --bots=7 --quality=1 --track=<id> \
  --perf-ab=forest,grass,themes
```

Other A/B switches: `--perf=nossao,noshadow,nofog,...` (see `_apply_perf_flags` in `race.gd`),
`--fill_off`, and the environment variables `VEG_OFF`, `FOREST_OFF`, `GRASS_OFF`, `NO_THEMES`,
`TERRAIN_FLAT`, `BELT_OFF`, `FILL_OFF`, `NO_DRESS`, `NO_SHAPER` (both wrappers pass them to the game).

How to stay fast:

- **Never fix fps by shortening view distances.** Nothing may pop into view ahead of the driver.
  Use cheap far LODs, HLOD (merged far meshes per cell), impostor cards and MultiMesh instead,
  so things stay visible at a lower cost.
- Merge static geometry per material and per spatial cell (`SurfaceTool`, `GxGeo`,
  `TrackThemes._st`); use `MultiMeshInstance3D` for repeats.
- No shadows on small things; few real lights (night lamps are mostly emissive + fake pools).
- Godot measures visibility ranges to the **AABB centre**: extend `visibility_range_end` by the
  half-diagonal of the mesh (`Gx.add_mesh` does this for you).
- Ranges that end within view must fade: `visibility_range_fade_mode = FADE_SELF` with a 20-40 m
  margin. Check with `--pop-audit`.
- Collision only where a car can reach it, as simple boxes on a `StaticBody3D`.
- Everything is built at load time; nothing is rebuilt while racing. Weather changes go through
  uniforms and global shader parameters, never shader recompiles.

## 6. Look rules

Slipstream aims for a grounded, photographic look (think NFS Porsche Unleashed, WRC, Burnout
Paradise), not a stylised one.

- **Nothing cartoony, boxy or low-poly-stylised.** No plain untextured boxes, no flat colours.
- **No procedurally faked surface detail** pretending to be real (for example shader-drawn
  building windows or generated signs). Use real photo textures and real models: Poly Haven,
  ambientCG, Wikimedia Commons photographs, Smithsonian Open Access scans.
- When geometry must be procedural, give it real proportions, bevels and insets, trim, PBR photo
  materials (`Mats.mat("brick")`, `GxGeo` material types), grime/AO in the vertex colour, and
  variation.
- Tracks are **enclosed and busy**: forest walls, banks, buildings, crowds. No vast empty plains,
  no empty vistas. Trees must look full.
- Anything over the road needs at least 5.5 m clearance and must stay outside the road footprint
  plus 1.5 m. Solid things beside the road get collision.
- No real brand logos or trademarks on cars, billboards or signs. Car make/model names are kept;
  all sponsor and shop names are invented.

## 7. Asset licensing

Every third-party file must allow **redistribution and commercial use**.

Allowed: **CC0**, **public domain**, **CC BY**, **CC BY-SA**, **SIL OFL** (fonts), **Apache 2.0**,
MIT/BSD-style.

Never: **NC** (non-commercial), **ND** (no derivatives), editorial-only, "free for personal use",
unclear or unknown licences, ripped game assets, anything with a visible real logo.

For every asset you add, credit it in **all three** places:

1. The per-folder credits file next to it (`assets/<folder>/CREDITS*.txt`, for example
   `assets/cars/CREDITS_cars.txt`, `assets/materials/CREDITS_materials.txt`): title, author,
   source URL, licence (with link), and the changes you made.
2. The root [CREDITS.md](CREDITS.md).
3. `assets/CREDITS_INGAME.txt`, which the in-game Credits screen reads
   (`scripts/ui/menu_credits.gd`).

Raw source files (full-resolution downloads, PSDs) go in a `src/` folder with a `.gdignore` and
are git-ignored; only what the game loads is committed.

## 8. Submitting changes

1. Fork, branch from `main`, keep each pull request to one feature or fix.
2. Before opening the PR:
   - the game loads with **zero script errors** (parse check, plus a normal windowed start);
   - bots finish a headless race on every track you touched;
   - off-track tests pass on those tracks;
   - `TRACKS="<your tracks>" tools/perfcheck.sh` passes (avg >= 60, 1%-low >= 45) on the target
     machine, or say clearly in the PR that you could not measure on it;
   - new assets are credited in all three places with an allowed licence.
3. In the PR description: what changed, why, the tracks/cars affected, before/after screenshots
   for anything visual, and the perfcheck table.
4. Keep diffs to shared files (track defs, catalogs, `race.gd`) small and focused. Do not
   reformat code you did not change.

By contributing you agree that your code is released under the project's MIT licence
([LICENSE](LICENSE)) and that any assets you add are under the licence you state for them.
