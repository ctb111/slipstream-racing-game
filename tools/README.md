# tools/

Developer tools: run wrappers, the performance gate, debug overlays loaded by the race, and
offline bakers that generate textures and tree meshes. None of this ships in an exported game
except `perf_ab.gd` and `pop_audit.gd`, which `race.gd` loads only when their flags are given.

The shell scripts are **zsh** and use `perl` for timeouts (both ship with macOS). `bgrun.sh` is
macOS-only. See [CONTRIBUTING.md](../CONTRIBUTING.md#4-testing-workflow) for the workflow and
[AGENTS.md](../AGENTS.md) for the etiquette when several agents share one machine.

## Run wrappers

### `hrun.sh`: headless run

Runs `godot --headless --path <repo> <args>` through the `cpu` lane of the run queue, killed after
`LIMIT` seconds (default 300). Refreshes the global class cache first if any script changed.
Use for logic checks: parse checks, bot races, off-track tests, pop audits, test scenes, bakers.

```sh
# parse check (no output = clean)
LIMIT=60 tools/hrun.sh res://scenes/race.tscn --quit-after 60 -- --bots=0 --track=kiefernring 2>&1 | grep -E "SCRIPT ERROR|Parse"
# full bot race, fast (fixed 120 fps simulation)
LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --track=altstadt
# run a SceneTree script
tools/hrun.sh -s res://tools/frame_diff.gd -- /tmp/pops pa
```

### `bgrun.sh`: silent background windowed run

`tools/bgrun.sh <scene> [godot args] -- [game args]`. Starts `/Applications/Godot.app` with
`open -g` (the window opens behind everything and never takes focus), `--audio-driver Dummy`,
waits for it to exit and prints its output. Pass `""` as the scene for the main menu. Uses the
`gpu` lane (two slots). Watchdog: `LIMIT` seconds (default 300). Forwards the environment
variables `VEG_OFF NO_THEMES VEG_DEBUG FOREST_OFF GRASS_OFF TERRAIN_FLAT BELT_OFF FILL_OFF NO_DRESS NO_SHAPER` to the game.
Use for screenshots, video and fps.

```sh
tools/bgrun.sh res://scenes/race.tscn -- --track=hafenstadt --weather=4 --bots=7 --screenshot=/tmp/h.png --shot_at=12
tools/bgrun.sh "" -- --menu_screen=credits --uishot=/tmp/credits.png
```

### `lock.sh`: the run queue

Sourced by `hrun.sh`, `bgrun.sh` and `perfcheck.sh`; not run directly. A fair
first-come-first-served queue in `/tmp/slipstream_<lane>.queue`:

- `gpu` lane: windowed runs, two slots (`/tmp/slipstream_bgrun.lock`, `/tmp/slipstream_bgrun2.lock`),
  so two screenshot runs can run side by side. `LOCK_EXCLUSIVE=1` (perfcheck) waits until it is
  first in line and both slots are free, then takes both. The gpu lane also waits while a real
  game window is open (someone playing).
- `cpu` lane: headless runs, one slot.

Dead owners are cleaned up automatically. `BGRUN_LOCKED=1` tells a nested wrapper that the caller
already holds the lock (perfcheck calling bgrun).

## Performance

### `perfcheck.sh`: the 60 fps gate

Runs each track windowed with 8 cars (`--allbots --bots=7`), Medium quality (`--quality=1`),
V-Sync off, adaptive resolution on, and reads the frame statistics printed by `--screenshot` at
24 s (6 s window). Prints `avg`, `low1%`, worst frame, 3D scale and PASS/FAIL per track
(PASS = avg >= 60 and 1%-low >= 45, no script errors). Saves the screenshots to
`$TMPDIR/perfcheck.<pid>/`. Only meaningful on a quiet machine (it prints the load average; below
about 6). Holds both gpu slots for the whole check.

```sh
TRACKS="alpenpass hafenstadt" tools/perfcheck.sh     # subset (preferred)
tools/perfcheck.sh                                     # all 12 tracks (~15 min)
tools/perfcheck.sh --weather=5                         # extra game args go to every case
```

### `perf_ab.gd`: what does a feature cost?

Loaded by `race.gd` with `--perf-ab[=feat1,feat2,...]`. Within one run it alternates each feature
OFF/ON in 1.6 s segments (5 repetitions, first 0.4 s of each discarded) and prints the mean frame
time, draw calls and physics time with the feature on and off, then quits. Machine load and
run-to-run noise cancel out. Features: `ssao glow shadow fog sky post forest grass people themes
props cars particles half`. `--perf-ab=hitch` instead logs every frame over 28 ms for 45 s.

```sh
tools/bgrun.sh res://scenes/race.tscn --disable-vsync -- --allbots --bots=7 --quality=1 --track=herbstwald --perf-ab=forest,grass,themes
```

### `pop_audit.gd`: nothing may pop in

Loaded by `race.gd` with `--pop-audit`. Works headless. Every 0.25 s it checks what visibility
ranges and crowd LODs hide or double-draw near the camera; prints an INVENTORY of every
`GeometryInstance3D` whose range ends early (ranked by size x count) and an APPEAR list of
instances that switch on within 600 m ahead of the camera (ranked by on-screen size; fading ones
are listed as `soft`, LOD swaps are ignored).

`--pop-shots=<prefix>[,<start s>,<step s>,<count>,<burst>,<scale>]` saves a drive-ahead sequence
(default 12 captures 0.5 s apart from 20 s); `burst` > 1 captures consecutive frames for flicker.
`--pop-audit=shots` skips the audit and only captures (windowed).

```sh
tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=alpenpass --pop-audit
tools/bgrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=alpenpass --pop-audit=shots --pop-shots=/tmp/pops/pa,20,0.5,12,3
```

### `frame_diff.gd`: flicker finder

Headless `SceneTree` script. Reads `<prefix>_<capture>_<frame>.png` from `--pop-shots` bursts and
prints, per capture, how many pixels change between consecutive frames and how many **flicker**
(change from frame k to k+1 and back at k+2), plus the 8x6 screen cells with most flicker. No
ImageMagick needed.

```sh
tools/hrun.sh -s res://tools/frame_diff.gd -- /tmp/pops pa
```

## Bakers (offline asset generation)

Run these only when you change their inputs; their outputs are committed. Source images they read
from `src/` folders are git-ignored (too big / raw downloads), so you need to download the
sources listed in the matching `CREDITS*.txt` first.

| Tool | What it makes | Run |
|---|---|---|
| `bake_dirt_noise.gd` | `assets/textures/car_dirt/dirt_noise.png`: tileable RGBA noise for `shaders/car_dirt*` (blotches, Worley drops, grain) | `godot --headless --path . --script res://tools/bake_dirt_noise.gd` |
| `build_facade_atlas.gd` | photo facade atlas (albedo, normal, mask) in `assets/textures/facades/` from `assets/facades_src/` (git-ignored); prints the `SIZES` table for `scripts/track/facade_kit.gd` | `tools/hrun.sh --script res://tools/build_facade_atlas.gd` |
| `make_trackside_atlas.py` | `assets/trackside/trackside_paint.png`, `trackside_signs.png` (banners, arches, warning signs, fan messages) and the generated `scripts/track/trackside_uv.gd` | `python tools/make_trackside_atlas.py` (Pillow + numpy) |
| `make_gx_billboard.py` | `assets/gimmicks/gx_billboard.png`: weathered posters for invented brands (from CC photos in `assets/gimmicks/src`) and road signs, for `gx_billboard.gd` | `python tools/make_gx_billboard.py` |
| `make_gx_graffiti.py` | `assets/gimmicks/gx_graffiti_walls.png` (real photographed graffiti walls) and `gx_graffiti_tags.png` (ambientCG tags) for `gx_graffiti.gd` | `python tools/make_gx_graffiti.py` |
| `make_gx_road_text.py` | `assets/gimmicks/gx_road_text.png` (fan road paint glyphs and symbols) and the generated `scripts/track/gimmicks/gx_road_glyphs.gd` | `python tools/make_gx_road_text.py` |

Python setup: `python3 -m venv /tmp/v && /tmp/v/bin/pip install pillow numpy`, then run with
`/tmp/v/bin/python`.

### `trees/`: the tree models

The forest, tree lines and themed trees use baked meshes in `assets/vegetation/trees/models/`.

| Tool | What | Run |
|---|---|---|
| `trees/build_clumps.py` | dense foliage atlases `leaf_clumps.png` / `conifer_clumps.png` (+ normals) from ambientCG CC0 leaf scans (LeafSet024, 016, 009) | `python tools/trees/build_clumps.py <dir with unzipped ambientCG sets>` |
| `trees/gen_trees.py` | grows the trees with Blender's Sapling Tree Gen (GPL add-on, used as a tool only) and writes `<name>.bin` (near + far LOD, wind weights in vertex colours). `FAR_CARDS` env var (default 2) sets far-LOD cards per clump | `Blender -b --factory-startup --python tools/trees/gen_trees.py -- <dir with sapling_tree_gen/> <out dir> [only=name,...]` |
| `trees/import_trees.gd` | turns the `.bin` files into `ArrayMesh` resources `<name>_near.res` / `<name>_far.res` | `tools/hrun.sh -s res://tools/trees/import_trees.gd -- --src=<dir with .bin>` |

## Other files

- `AGENT_RULES.md`: pointer to [AGENTS.md](../AGENTS.md).
