# Roadmap

Known issues first, then feature ideas. Sizes are rough: **S** = a day or two, **M** = about a
week, **L** = several weeks. File paths point at where the work would start. Pick something, open
an issue to say you are on it, and see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Known issues

### Performance

- **Several tracks are below the 60 fps target** (avg >= 60, 1%-low >= 45 on an M1 MacBook Air,
  Medium, 8 cars) since the latest content: denser trees, the forest edge belt, terrain banks and
  the landscape filler. Run `tools/perfcheck.sh` for the current numbers. Levers to measure and
  A/B (do **not** shorten view distances):
  - `BELT_OFF=1` (env var): skips the forest edge belt (`WorldBuilder._edge_belt`,
    `scripts/world/world_builder.gd`). `--trees_old` does the same.
  - `FAR_CARDS=1` when re-baking trees (`tools/trees/gen_trees.py`, then
    `tools/trees/import_trees.gd`): one far-LOD card per clump instead of two.
  - `--fill_off` / `FILL_OFF=1`: skips `scripts/track/gimmicks/fill_landscape.gd`.
  - `TERRAIN_FLAT=1`: no banks, ridges or designed profile (`Terrain.configure`).
  - `--perf-ab=forest,grass,themes,props,...` measures each feature inside one run
    (`tools/perf_ab.gd`).
  Likely fixes: cheaper far tree LODs / impostors, merging more of the belt into the far HLOD
  cells, fewer shadow casters at distance. Size: **M**.
- **Visibility fades use the transparent pipeline.** `VISIBILITY_RANGE_FADE_SELF` (used by
  `Gx.add_mesh`, themes, props, wildlife) draws fading instances with alpha blending, which costs
  more and can cause sorting artefacts against other transparent surfaces (glass, particles,
  foliage). A dithered/alpha-hash fade in the shaders would avoid it. Size: **M**.

### Rendering and look

- **Flicker of cars and terrain during the start countdown.** Cause not found yet. Leads:
  adaptive resolution's countdown freeze (`scripts/race/dynamic_res.gd`, A/B with
  `--dynres_nofreeze` or `--nodynres`), shader warm-up, shadow cascades while the cars are locked.
  Capture with `--pop-shots=<prefix>,0,0.25,16,3` and analyse with `tools/frame_diff.gd`.
  Size: **S-M**.
- **Grass dissolve line on the new terrain banks.** The verge grass cards fade out at 40-75 m
  (`scripts/world/grass.gd`); `shaders/terrain.gdshader` hides the hand-off with a far-grass tint
  (`grass_fade`, `grass_far`, `grass_far_tint`), but `shaders/alpine_terrain.gdshader` (swapped in
  by `AlpineTheme._ground_tint()`) has no such tint, so a line shows where the grass ends. Port the
  far-grass block. Size: **S**.
- **House windows look flush** (no depth or sill) and some walls read flat. Facades are photo
  textures on flat walls (`scripts/track/facade_kit.gd`, `shaders/theme_facade.gdshader`,
  `facade_unit.gdshader`). Add real inset geometry or parallax depth, sills and lintels. Size: **M**.
- **Occasional oversized falling leaf on the road** (`scripts/world/falling_leaves.gd`,
  `scripts/world/road_leaves.gd`). Check particle scale ranges and the road-leaf decal sizes.
  Size: **S**.
- **Low-resolution apex hay bales** (`scripts/track/track_props.gd`, hay bales on the inside of
  corners). Replace with a real scanned model or higher-resolution texture. Size: **S**.
- **Some conifer leaf cards look pale when lit from above**, and **roadside bushes read as bright
  blobs**. Foliage normals/ albedo in the clump atlases (`tools/trees/build_clumps.py`,
  `assets/vegetation/trees/`) and `shaders/veg_tree.gdshader` / `foliage.gdshader`. Size: **S-M**.
- **Hafenstadt's night brightness** and **Alpenpass's weather variants** have not been reviewed
  on screen yet. Size: **S** (review + tuning in `dress_hafenstadt.gd` `_night_city()`,
  `weather.gd` presets).

### Driving and AI

- **One Herbstwald crest is near the car's limit**: the light crests after the tunnel
  (`herbstwald` points in `scripts/track/track_defs.gd`, marked "crest 1" / "crest 2") can unsettle
  a car at full speed. Smooth the profile or soften the approach. Size: **S**.
- **Lap-1 / turn-1 contacts between bots.** The field bunches into the first corner
  (`scripts/race/ai_driver.gd`: braking for cars ahead, lateral spacing on lap 1). Size: **M**.

### Multiplayer

- **Not re-tested with the newest tracks** (Herbstwald, Alpenpass, Hafenstadt, Capo Rosso) and the
  changeable weather on them. See [HOWTO-multiplayer.md](HOWTO-multiplayer.md#testing-with-two-instances).
  Size: **S**.

## Feature ideas

### Racing and modes

| Idea | Size | Notes |
|---|---|---|
| Full race replays | L | Ghosts already exist for time trial (`scripts/modes/ghost.gd`, 30 Hz transform samples). Extend recording to every car (plus wheel/steer/brake state from `Car.net_pack()`, which already captures what a puppet needs), store per race, play back with puppet cars (`Car.set_remote()`) and the TV camera (`scripts/camera/tv_director.gd`). |
| Ghost improvements | S | Download/share ghost files, race a friend's ghost, ghost of the track record. `scripts/modes/time_trial.gd`, `mode_store.gd`. |
| Time-trial leaderboards | M | Local per track + car best laps are already saved (`TimeTrial.file_for()`). Online boards need a small server or a service; validate with the ghost samples. |
| Championship progression | M | Championships exist (`scripts/modes/championship.gd`, `SERIES`). Add more series, unlockable cars/tracks, career stats, difficulty ramp. |
| More cars | S each | Same era classics; see [HOWTO-add-a-car.md](HOWTO-add-a-car.md). |
| More tracks | M each | See [HOWTO-add-a-track.md](HOWTO-add-a-track.md). Ideas: Nordic lakes, vineyard hill climb, Belgian forest, night city in rain. |
| Track editor | L | In-game editor for `points`/heights and dress placements, saving a def Dictionary (same keys as `TrackDefs.TRACKS`) to `user://`; needs a loader for custom defs and network transfer of the def for LAN races. |
| Reverse layouts | S | Reverse `points` order and the start direction in `Circuit.build()`; dress files that rely on `along` positions need checking. |
| Race rules | S-M | Flags, track limits, jump-start penalties; host-authoritative (`race.gd`). |

### Multiplayer and platforms

| Idea | Size | Notes |
|---|---|---|
| Online lobby / matchmaking | L | `Net` is LAN + direct IP. Options: a tiny lobby/relay server, WebRTC with a signalling server, or Steam networking (GodotSteam). Keep the host-authoritative model. |
| Split-screen | L | Two `SubViewport`s with their own `ChaseCamera`, per-device input in `scripts/input_setup.gd`, HUD per viewport. Expensive on the target hardware; probably Low quality only. |
| Spectator / late join | M | Join a race in progress as a spectator using the puppet stream. |
| Linux build | S | Add a Linux export preset to `export_presets.cfg`; `tools/bgrun.sh` is macOS-only, write a Linux equivalent (xdotool/no-focus window). |
| Steam Deck | M | Linux build + gamepad UI pass + a performance profile around the Low/Medium boundary; verify text size at 1280x800. |

### Look and world

| Idea | Size | Notes |
|---|---|---|
| Dynamic time of day | L | Interpolate presets over the race (sun direction, HDRI blend, exposure) like `WeatherCycle` does for weather; lamps and headlights already switch with `Car.lamps_on` in changeable night. Shadows and the sky shader must not recompile. |
| More wildlife | S-M | `scripts/world/wildlife.gd`, `wildlife_builder.gd` (`FOREST`, `FARM` lists). Deer at the forest edge, herons by rivers, gulls at the harbour. Real CC0 models only. |
| Photo mode | M | Pause, free camera (`ChaseCamera.debug_world`), depth of field, exposure, hide HUD (`--nohud` path), save PNG (`--screenshot` code in `race.gd`). |
| Rain on the lens / better spray | S-M | `scripts/car/tire_fx.gd`, `car_fx.gd`, `shaders/windscreen.gdshader`. |
| More set pieces | S each | Ski jump, quarry with conveyor, rail viaduct with a moving train. See [HOWTO-add-a-gimmick.md](HOWTO-add-a-gimmick.md). |

### Input and accessibility

| Idea | Size | Notes |
|---|---|---|
| Force feedback / wheel support | L | Godot only exposes simple rumble (`Input.start_joy_vibration`). Wheels with FFB need a GDExtension (SDL haptics or DirectInput) and steering-axis calibration in `scripts/input_setup.gd`; feed it from tyre forces in `car.gd`. |
| Accessibility options | M | Colour-blind friendly HUD colours (`scripts/ui/hud_style.gd`), camera shake toggle (`scripts/camera/camera_shake.gd`), HUD scale, steering/braking assist levels (assists exist: `Car.set_assists`), audio cues for the countdown. |
| Localisation | M | Move UI strings to Godot translation files (`TranslationServer`, `tr()`), starting with `scripts/ui/menu*.gd` and the HUD. Fonts already cover Latin Extended. |

### Deliberately out of scope

The original author chose **not** to have these. Discuss in an issue before starting any of them:

- **Car damage** (visual or mechanical).
- **Rally stages** (point-to-point, co-driver calls). The game is a circuit racer.
- **Car setup / tuning screens** (gearing, suspension, tyre pressures). Handling is tuned per car
  in `scripts/car/car_catalog.gd` and stays arcade-leaning.
