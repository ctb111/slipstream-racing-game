# Slipstream architecture

This is the map of how the game fits together: what runs when, which script owns what, and the rules the
code follows to hold 60 fps. Every folder under `scripts/` also has its own `README.md` with a file table;
this document is the big picture that ties them together.

- Engine: **Godot 4.7**, GDScript only, **Forward+** renderer, **Jolt** physics at **120 ticks/s** with
  physics interpolation (`project.godot`).
- No editor-built levels. There are only two scenes (`scenes/menu.tscn`, `scenes/race.tscn`) and each is a
  single root node with a script. **Everything else (tracks, cars, HUD, sky) is built in code at run time.**
- Hard target: **60 fps average, 45 fps 1%-low, 8 cars, Medium quality, on a fanless M1 MacBook Air**
  (`tools/perfcheck.sh`). Most design decisions below follow from that.

Contents

1. [Boot flow](#1-boot-flow)
2. [The race scene](#2-the-race-scene)
3. [How a track is built](#3-how-a-track-is-built)
4. [The car](#4-the-car)
5. [AI](#5-ai)
6. [Networking](#6-networking)
7. [Weather and lighting](#7-weather-and-lighting)
8. [Rendering and performance](#8-rendering-and-performance)
9. [Settings persistence](#9-settings-persistence)
10. [Debug command-line flags](#10-debug-command-line-flags)

---

## 1. Boot flow

```
project.godot
  run/main_scene = res://scenes/menu.tscn
  [autoload]  Game = scripts/autoload/game.gd     (settings, session, quality helpers)
              Net  = scripts/autoload/net.gd      (ENet host/client, LAN beacon, lobby RPCs)
        |
        v
scenes/menu.tscn  (Control + scripts/ui/menu.gd)
  - Showroom (3D turntable car), MenuWidgets, SettingsPanel, MenuModes, MenuCredits
  - fills Game.* (track_id, laps, bots, difficulty, weather_override, car_id, session ...)
  - online: Net.host() / Net.join(); host presses Start -> Net.start_race()
        |  get_tree().change_scene_to_file("res://scenes/race.tscn")
        |  (single player: menu.gd:519 / menu_modes.gd:81;  online: Net._begin_race RPC, net.gd:234)
        v
scenes/race.tscn  (Node3D "Race" + scripts/race/race.gd)
  _ready():  parse args -> quality -> DynamicRes -> game mode overrides
             -> LoadingScreen + AssetPreload.start()
             -> Circuit.build(track_def)        (awaited; yields frames so the bar animates)
             -> spawn cars (grid) -> ChaseCamera -> Hud + RaceHud -> 3 warm-up frames
             -> LoadingScreen.finish()  -> countdown
        |
        v  race over: RaceHud results -> race.quit_to_menu() / Net.back_to_lobby()
scenes/menu.tscn again (Game.menu_screen / Game.pending_message pick the screen / message)
```

Autoload order matters only in that both are plain `Node`s available everywhere:

| Autoload | File | Owns |
|---|---|---|
| `Game` | `scripts/autoload/game.gd` | Player settings (loaded in `_ready`, saved by `save_settings()`), the current session (`mode`, `session`, `track_id`, `laps`, `bots`, `difficulty`, `grid`, `weather_override`, `weather_timeline`, `car_id`, `paint_index`), quality helpers (`apply_viewport_quality`, `render_scale_now`, `scaling_mode`, `grass_density`), bot skill (`bot_skill`), units, window mode, bus volumes. Also calls `InputSetup.ensure_actions()` so input actions exist before any scene. |
| `Net` | `scripts/autoload/net.gd` | LAN multiplayer: hosting, joining, the UDP discovery beacon, the lobby, and the RPCs that move everyone between menu and race. |

`InputSetup` (`scripts/input_setup.gd`) registers every input action in code (keyboard + gamepad defaults,
two key slots and one pad slot each) and applies the player's rebinds from `Game.bindings`. Nothing is
stored in `project.godot`'s input map.

When the game is started with **any user args after `--`** (tests, screenshots), `Game` mutes audio, does not
touch the window, and `save_settings()` is a no-op, so debug runs never overwrite the player's settings
(`game.gd:100-108`, `game.gd:136-138`). Game-mode progress uses `user://test/` in that case
(`scripts/modes/mode_store.gd:9`).

---

## 2. The race scene

`race.gd` is the race manager. Everything below is created in code under the `Race` root:

```
Race (Node3D, race.gd)                     state: COUNTDOWN -> RACING -> FINISHED
├── DynamicRes                             (unless --nodynres) adaptive 3D resolution
├── LoadingScreen (CanvasLayer)            freed by finish()
├── Circuit (Node3D, circuit.gd)           the whole world, see section 3
│   ├── Weather (Node3D) ── Cycle (WeatherCycle, changeable weather only)
│   ├── WorldEnvironment, Sun (DirectionalLight3D), rain/snow GPUParticles3D
│   ├── terrain chunks, road, kerbs, gravel, rails, props, themes, crowds, forest ...
│   └── NightLights, Atmosphere, Ambience, RoadLeaves, Wildlife ... (EXTRA_BUILDERS)
├── Car0 .. CarN (RigidBody3D, car.gd)     one per grid slot
│   ├── Body/Model + Body/ShadowProxy, wheel pivots
│   ├── TireFx, CarDirt, CarAudio (+ CarImpacts), CarFx, CarLights (when lamps on)
│   └── AIDriver                           bots (and the player with --allbots / after the flag)
├── Mode (RaceMode)                        Championship or TimeTrial controller, single player only
├── ChaseCamera (Camera3D)                 all camera modes; owns CameraPost, Cockpit, TvDirector
│   └── CameraPost (CanvasLayer -1)        full-screen lens / grade pass, under the HUD
├── Hud (CanvasLayer)                      tacho, gear, speed, drift readout, control hints
└── RaceHud (CanvasLayer)                  timing, standings tower, minimap, lights, banners,
                                           pause menu (SettingsPanel), results
```

Key facts (all in `scripts/race/race.gd`):

| Topic | Where | Notes |
|---|---|---|
| Entries | `class Entry` (`race.gd:17`) | name, car, ai, peer, bot, `local` (simulated here), lap, progress, position, timing. |
| Grid | `_single_player_grid` (`race.gd:242`), `Net.start_race` (`net.gd:70`) | Bots first, player(s) at the back. Slot 0 is pole; `Circuit.grid_transform(slot)` places two staggered columns. |
| Who simulates a car | `_spawn` (`race.gd:252`) | `e.local = is_me or (e.bot and _is_authority())`. Non-local cars become puppets (`Car.set_remote()`). |
| Countdown | `_run_countdown` (`race.gd:333`) | Authority only; 5 lights at 0.9 s, random hold 0.4-1.3 s. Mirrored on the start gantry lamps (`_on_gantry_lights`). |
| Lap counting | `_update_progress` / `_on_line_crossed` (`race.gd:403`, `464`) | Uses `RacingLine` indices; a lap only counts if the car was "armed" by passing 40-60 % of the lap. Authority keeps official laps and times. |
| Ranking | `_rank` | Sort by `progress` (metres since the start line; finishers get a large constant minus finish time). |
| Slipstream | `_slipstream` (`race.gd:429`) | A car 3-25 m directly behind another gets `car.draft` 0.6-1.0 (less drag). |
| Finish | `_on_line_crossed` | Player gets an autopilot `AIDriver` (skill 0.6) after the flag; results after everyone finishes or 30 s (`RESULTS_GRACE`). |
| Reset | `_reset_to_track` | `reset_car` action, or `AIDriver.stuck` signal for bots. |
| Game modes | `_make_mode` (`race.gd:222`) | `RaceMode.setup_overrides()` may replace track, laps, grid and temporarily set `Game` properties during setup. |

---

## 3. How a track is built

A track is **data** (`TrackDefs.TRACKS`) turned into a world by a fixed pipeline in `Circuit.build()`
(`scripts/track/circuit.gd:59`). Every step is `await _step(label)` so the loading screen can redraw and
`--loadprof` can time it.

```
TrackDefs.get_track(id)          scripts/track/track_defs.gd   control points, start, hills, weather,
   |                                                           theme, terrain_shaper, street, fixed_heights ...
   v
Circuit.build(def)               scripts/track/circuit.gd
   1 Sky and weather   Weather.create(...)                     scripts/world/weather.gd
   2 Ground            WorldBuilder.build_ground               scripts/world/world_builder.gd
   3 Terrain           Terrain.new + configure(def)            scripts/world/terrain.gd  (STYLE per track)
                       elevate(points) | set_base(...)         road heights from the land (or fixed profile)
                       TrackBuilder.make_curve(points)         Catmull-like Curve3D through the points
                       terrain.carve(curve)                    banks, cuttings, embankments meet the tarmac
                       def.terrain_shaper.shape(...)           optional: autumn / alpine / harbour landforms
                       terrain.build_nodes                     HeightMapShape3D collision + chunked meshes
   4 Tarmac/barriers   TrackBuilder.build                      road ribbon, kerbs, verge, gravel, rails/walls
   5 Trackside         TrackProps.build                        start gantry, grid, pits, grandstand, signs ...
   6 Scenery           Scenery.build                           villages, spectators, windmill, lake ...
   7 EXTRA_BUILDERS    (each: static func build(parent, lap_curve, road_width, weather_preset))
        set_dressing.gd      paddock, pit-lane life, skyline landmarks
        themes.gd            def.theme -> coast / town / autodromo / autumn / harbour / alpine / mediterranean
        ambience.gd          crowd, PA, birds, wind, rain sound
        road_decals.gd       tyre marks, drains, manholes (one mesh)
        night_lights.gd      floodlights / lanterns / sodium lamps (night presets only)
        atmosphere.gd        valley mist, haze, dust motes, gust debris, dust devils, windsocks
        road_leaves.gd       fallen leaves on the tarmac
        gimmicks/gimmicks.gd dress_<id>.gd (Gx pieces) -> fill_landscape.gd -> GxFans.flush
        wildlife_builder.gd  animals, birds, pets (last: needs the crowds)
   8 Grass             Grass.build                             MultiMesh verge grass chunks
   9 Hills             WorldBuilder.build_hills                distant ring of hills
  10 Forest            WorldBuilder.build_forest               photo-card trees, near/far HLOD
  11 Racing line       RacingLine.new(curve, ..., grip)        bots' line and speed plan
```

Things to know:

- **Two curves.** `circuit.curve` is the raw spline; `_rotated_curve()` resamples it so **offset 0 is the
  start/finish line** and offsets run in the driving direction. Every builder after step 4 receives that lap
  curve. `Gx.centre(c, along)` uses `c.curve` plus `c.start_offset`, so "metres round the lap from the
  start line" means the same thing everywhere.
- **`no_trees` meta.** Builders reserve circles with `c.set_meta("no_trees", [[pos, radius], ...])`
  (`Gx.reserve`). The forest is built last and avoids all of them; this is also how pieces avoid each other.
- **Optional builders.** Every `EXTRA_BUILDERS` file and `track_props.gd` is loaded only if it exists
  (`ResourceLoader.exists`), so a missing feature never breaks a track.
- **Determinism.** Placement uses seeded RNGs (`hash(def.id)`, `Gx.rng(c, purpose)`), so every machine in an
  online race builds the same world without sending it.

### Track definitions (`scripts/track/track_defs.gd`)

| id | Theme | Default weather | Special keys |
|---|---|---|---|
| `kiefernring` | (forest) | Clear | |
| `hochwald` | (forest) | Clear | |
| `valle_club` | (hills) | Clear | |
| `brackenmoor` | (moor) | Storm | |
| `schneekopf` | (mountain) | Snow | |
| `kuestenstrasse` | `coast` | Golden hour | |
| `altstadt` | `town` | Clear | |
| `valtellina` | `autodromo` | Golden hour | |
| `capo_rosso` | `mediterranean` | Golden hour | theme anchors |
| `herbstwald` | `autumn` | Golden hour | `terrain_shaper = autumn_terrain.gd`, `fixed_heights` |
| `alpenpass` | `alpine` | Clear | `terrain_shaper = alpine_terrain.gd`, `fixed_heights` |
| `hafenstadt` | `harbour` | 4 (clear night) | `street`, `terrain_shaper = harbour_terrain.gd`, `fixed_heights` |

Common keys: `id`, `name`, `blurb`, `points` (closed loop, metres, XZ; Y used only with `fixed_heights`),
`start`, `hills` (noise amplitude), `weather` (a Weather condition), optional `theme`, `terrain` (overrides
`Terrain.STYLE`), `peaks`, `street` (concrete barriers, no gravel; `TrackBuilder.configure`), `river`,
`cut`, etc. read by the theme / shaper. `ROAD_WIDTH` is 12 m for every track.

### Layers of scenery, from generic to specific

| Layer | Files | Applies to |
|---|---|---|
| Road and run-off | `track_builder.gd` | every track |
| Generic trackside | `track_props.gd`, `scenery.gd`, `set_dressing.gd` | every track |
| Themes | `themes.gd` (coast / town / autodromo, plus batching helpers) dispatching to `theme_autumn.gd`, `theme_harbour.gd`, `theme_alpine.gd`, `theme_mediterranean.gd` (extends `TrackThemes`) | tracks with `def.theme` |
| Terrain shapers | `autumn_terrain.gd`, `alpine_terrain.gd`, `harbour_terrain.gd` | tracks with `def.terrain_shaper` |
| Gimmick kit (Gx) | `gimmicks/gx.gd` helpers, `gimmicks/gx_<piece>.gd` pieces, `gimmicks/dress_<track_id>.gd` per-track placement, `gimmicks/lm_*.gd` track landmarks | tracks with a `dress_<id>.gd` |
| Landscape filler | `gimmicks/fill_landscape.gd` | every track, 20-300 m from the road |
| Shared kits | `trackside_kit.gd` (fans, flares, flags, camps, merged per 80 m cell), `world/people.gd` (PeopleKit crowds), `facade_kit.gd` (photo facades), `world/materials.gd` (Mats PBR library) | used by all of the above |
| Night | `night_lights.gd` | night presets |
| Life | `world/wildlife_builder.gd` + `world/wildlife.gd`, `world/ambience.gd` | every track |

The Gx contract (from `gimmicks/gx.gd`):

- Piece: `class_name Gx<Piece>`, `static func place(c: Node3D, xf: Transform3D, opts := {}) -> void`.
- Dressing: `dress_<track_id>.gd` with `static func dress(c: Node3D) -> void`, auto-called by `gimmicks.gd`.
- Frames: `Gx.frame(c, along, side, lateral)` gives a transform beside the road, standing on the terrain,
  +z pointing away from the road (so a piece's front faces -z). `Gx.road_frame(c, along)` is centred on the
  road for things that span it. Bases are never mirrored on the left side.
- Anything over the road needs at least **5.5 m clearance** and must stay out of the road footprint plus
  1.5 m; solid parts off the road get a `StaticBody3D` (see `tools/AGENT_RULES.md`).

---

## 4. The car

| Piece | File | Role |
|---|---|---|
| Physics | `scripts/car/car.gd` (`class_name Car`, `RigidBody3D`) | Raycast suspension, simplified Pacejka tyres, torque curve + gearbox, brakes with EBD, turn assist, drift logic, aero/draft. Inputs are plain fields (`throttle`, `brake`, `steer_input`, `handbrake`) written by the player (`_read_local_input`), an `AIDriver` or the network. |
| Catalogue | `scripts/car/car_catalog.gd` (`CarCatalog`) | Six cars (`porsche930` default, `bmw_e30_m3`, `datsun_240k`, `toyota_ae86`, `mazda_rx7_fc`, `ferrari_f40`): glb path, how to read the model (material names for wheels, paint, lamps), credit, physics preset (keys match `Car` property names), engine sound parameters. |
| Model loading | `scripts/car/car_model.gd` (`CarModel`) | Loads the glb once (cached), merges the body into one mesh with paint and brake-lamp surfaces, splits the 4 wheels by quadrant, measures wheelbase/track/radius, builds a merged **shadow proxy** (body + wheels, the car's only shadow caster) and regenerates **LODs** (`_with_lods`, meshoptimizer). |
| Fallback body | `scripts/car/car_body_builder.gd` | Procedural 930-ish body, only if a model is missing. |
| Paint | `scripts/car/car_palette.gd` | Period colours; `CarPalette.pick(i)`. |
| Lamps | `scripts/car/car_lights.gd` | Lit lenses, one low-beam SpotLight per car, at night a beam cone and tail glow. Only the local player's beam casts shadows (High+). |
| Cockpit | `scripts/car/cockpit.gd` | In-car view for the local car: animated steering wheel, live gauges, rear-view mirror (live on High/Ultra), windscreen rain. |
| Effects | `tire_fx.gd` (smoke, dust, skid marks in one shared MultiMesh ring), `car_fx.gd` (backfire flames, brake glow, sparks, splashes), `car_dirt.gd` (dirt/mud/snow/water build-up via `car_dirt.gdshaderinc` and `car_glass*.gdshader`) | |
| Audio | `car_audio.gd` (engine synthesised per engine type on a worker thread, turbo, tyres, wind), `car_impacts.gd` (crunches, scrapes) | All synthesised, no samples. Audio buses: `Engine`, `Effects`, `Ambience`. |

Global weather/lighting state the car reads is held in **static vars on `Car`**: `weather_road_grip`,
`weather_off_grip`, `headlights`, `night`, `lamps_on` (`car.gd:75-79`). `Circuit.build` and `Weather` set them.

Car-local space: -Z forward, wheel mounts at y = 0, wheel centres `REST_DROP` (0.225 m) below at rest.

---

## 5. AI

| Piece | File | Role |
|---|---|---|
| Racing line | `scripts/race/racing_line.gd` (`RacingLine`) | Built once per circuit (`Circuit.build`, last step). Samples every 2 m, minimum-curvature lateral offset, crest handling, a speed plan from `AI_LAT_G` (1.45 g) and `AI_BRAKE` (12.5 m/s²) scaled by the weather's road grip. Also the cheap "where am I on the lap" lookups (`closest_index`, `offset_of`, `transform_at`) used for lap counting, positions, resets and grid slots. |
| Driver | `scripts/race/ai_driver.gd` (`AIDriver`) | Child of a `Car`. Pure-pursuit steering on a look-ahead point (6 m + 0.36 s), speed from the plan times `skill`, racecraft (follow, overtake lanes), small human wobble, stuck detection (`stuck` signal). Uses the same controls and assists as the player. |
| Difficulty | `Game.bot_skill(rng)` (`game.gd:187`) | Easy / Medium / Hard = base skill 0.82 / 0.99 / 1.14 with a small random spread, clamped 0.7-1.25. Skill is the fraction of the planned speed the bot aims for. |

When the weather changes mid-race, bots rescale to the live `Car.weather_road_grip` against
`line.built_grip`.

---

## 6. Networking

LAN play over ENet, peer-to-peer star with the host as server. Constants in `scripts/autoload/net.gd`:
game port **UDP 27015**, discovery **UDP 27016**, protocol string `slipstream-1`, max 8 players.

```
 Host (Net.host)                                    Client (Net.join(ip))
 ENet server :27015                                 ENet client
 beacon: JSON {proto,name,track,players,max,state}  start_scan(): listen :27016,
   -> broadcast 255.255.255.255:27016 every 1 s      list servers (expire after 3.5 s)
                       <---- _register(name, proto, paint, car)   (rpc_id 1)
 _sync_lobby(players, lobby)  ---->  (reliable, call_local)
 start_race(): grid = bots + players in join order,
   rolls WeatherCycle timeline if changeable
 _begin_race(grid, lobby) ---->  everyone: Game.* = lobby, change to race.tscn
 ...race...
 back_to_lobby(): _to_lobby() ---->  everyone back to menu.tscn
```

In the race (`scripts/race/race.gd:531-628`):

| Data | RPC | Mode | Rate | Who sends |
|---|---|---|---|---|
| Car states (`Car.net_pack()`: 25 floats: position, rotation, velocities, steer, rpm, throttle, brake, gear, speed, suspension, skid, drift) | `_net_cars` | `any_peer`, `unreliable_ordered` | 30 Hz | Each machine, for the cars it simulates (its own driver; the host also sends bots). Receivers accept a slot only from its owner (`e.peer == sender`, or the host for bots). |
| Race clock, lap counts, lap times, finished flags | `_net_race` | `authority`, `unreliable_ordered` | 5 Hz | Host |
| Start lights | `_net_lights` | `authority`, `reliable` | on change | Host |
| Race finished | `_net_finished` | `authority`, `reliable` | once | Host |

Authority rules:

- **Host is authority** for the countdown, lap counting, lap times, finishing order and the race clock
  (`_is_authority()`; single player is its own authority).
- **Each machine simulates its own car physically**; the host simulates all bots. Other cars are
  **puppets**: `Car.set_remote()` freezes them kinematic, puts them on collision layer 2, and
  `_remote_step` interpolates the received states 0.1 s in the past (`NET_DELAY`). Local cars get a soft
  push from puppets (`_soft_contact`) instead of hard collisions.
- **The world is not sent.** Every client builds the same circuit from the track id and seeded RNGs.
  Changeable weather is a timeline dictionary rolled by the host and sent in the lobby; the weather state
  is a pure function of that timeline and the race clock (which the host syncs), so every sky matches.
- RPC methods live on `/root/Race` (race.gd) and `/root/Net`; node paths must match on all peers, so do not
  rename the `Race` root node.

Automated two-instance tests: `-- --nethost --wait=N` and `-- --netjoin=<ip>` on the menu scene
(`scripts/ui/menu.gd:93`).

---

## 7. Weather and lighting

`scripts/world/weather.gd` (`class_name Weather`) owns sky, sun, fog, ambient, precipitation, lightning and
the grip each surface loses. Everything that varies with the weather is in one table, `Weather.PRESETS`
(per `Kind`) plus `Weather.NIGHT` overrides.

**Kinds** (`enum Kind`): `CLEAR, STORM, SNOW, GOLDEN, DAWN, FOG`.

**Conditions** (the integer the menu, track defs, `--weather=N` and `Game.weather_override` use):

| N | Name | Kind | Night |
|---|---|---|---|
| 0 | Clear | CLEAR | no |
| 1 | Storm | STORM | no |
| 2 | Snow | SNOW | no |
| 3 | Golden hour | GOLDEN | no |
| 4 | Night | CLEAR | yes |
| 5 | Night rain | STORM | yes |
| 6 | Night snow | SNOW | yes |
| 7 | Changeable | (scenario) | no |
| 8 | Changeable night | (scenario) | yes |
| 9 | Dawn | DAWN | no |
| 10 | Fog | FOG | no |

`-1` in `Game.weather_override` means "the track's own default". Helpers: `cond_kind`, `cond_night`,
`cond_changeable`, `condition`.

`Weather.create(parent, condition, is_night, timeline)` builds:

- **Sky**: `shaders/sky.gdshader` over an HDRI panorama (`assets/hdri/`), animated clouds at quarter
  resolution, distant ridges; `Sky.PROCESS_MODE_INCREMENTAL`, radiance 512 on High+, 256 below.
- **Environment**: AgX tonemap, sky ambient mixed down (so cast shadows read), fog + aerial perspective,
  glow, SSAO (Medium+), SSR (storms, High+), SSIL (Ultra), saturation/contrast adjustment.
- **Sun** (`DirectionalLight3D` named `"Sun"`; at night it is the moon). Shadow distance and splits per
  quality; no sun shadows under closed storm/fog overcast; moon shadows only clear-night High+.
- **Precipitation**: rain / snow `GPUParticles3D` following the camera, lightning flash light + synthesised
  thunder, rain hiss and wind loops on the `Ambience` bus.
- **Shader globals** `wx_wet`, `wx_wet_line`, `wx_snow`, `wx_rain`, `wx_wind` (declared in
  `project.godot [shader_globals]`, read through `shaders/weather.gdshaderinc`). Materials take
  `max(own uniform, global)`, so fixed presets and live weather both work without touching materials.
- **Grip**: `Car.weather_road_grip` / `weather_off_grip` from the preset.

**Night** (conditions 4-6, 8): the `NIGHT` overrides darken the sky and add moonlight; `Car.night` turns on
full beams and tail lamps; `NightLights` (`scripts/track/night_lights.gd`) adds shadowless trackside
SpotLights that fade out and cull at short distance so only the dozen nearest are lit; `CameraPost`
switches to a night grade.

**Changeable weather** (`scripts/world/weather_cycle.gd`, `WeatherCycle`): a timeline of keyframes (cloud
gloom, rain, snowfall, wind) between a `base` and a `heavy` preset. `Weather` builds everything the
scenario might need up front (both HDRIs, rain and/or snow emitters, lightning) so nothing compiles
mid-race. `race.gd` sets `weather.clock` from the race time each physics tick; wetness and snow cover are
integrated in fixed 0.25 s steps so every machine computes the same values. Debug: `--weather_script`,
`--weather_seed`, `--weather_speed`, `--weather_at`, `--weather_log`.

Related visual layers: `Atmosphere` (valley mist, haze, dust motes, gust debris, dust devils),
`CameraPost` (per-weather colour grade, rain on the lens), `CarDirt` (cars pick up mud, slush, water),
`RoadLeaves`, `FallingLeaves`.

---

## 8. Rendering and performance

### The target and why

The game must hold **60 fps average and 45 fps 1%-low with 8 cars on Medium** on the developer's
**fanless M1 MacBook Air**, which throttles when hot. That machine is the gate (`tools/perfcheck.sh`: every
track, `--allbots --bots=7 --quality=1`, vsync off, adaptive resolution on). At the same time the tracks
must feel enclosed and busy, and **nothing may visibly pop in** ahead of the player. So the budget is won by
batching and LODs, never by deleting scenery or shortening view distances.

### Quality levels (`Game.quality`, 0 Low .. 3 Ultra)

First run picks Medium on Apple GPUs, High elsewhere (`game.gd:94-96`).

| Setting | Low (0) | Medium (1) | High (2) | Ultra (3) | Where |
|---|---|---|---|---|---|
| MSAA 3D | off | off | 2x | 4x | `Game.apply_viewport_quality` |
| Screen-space AA | FXAA | FXAA | FXAA | off (MSAA 4x) | same |
| Soft shadow filter | very low | low | medium | high | same |
| SSAO | off | on (low) | on (medium) | on (high) | `weather.gd` + `game.gd` |
| SSIL | off | off | off | on | `weather.gd` |
| SSR (wet storm) | off | off | on | on | `weather.gd`, `weather_cycle.gd` |
| Sky radiance | 256 | 256 | 512 | 512 | `weather.gd` |
| Sun shadow distance / splits | 90 m / 2 | 120 m / 2 (split at 20 %) | 160 m / 4 | 250 m / 4 | `weather.gd` |
| Moon shadows, player headlight shadows | off | off | on | on | `weather.gd`, `race.gd:131` |
| Adaptive resolution (`DynamicRes`) | yes (Auto) | yes (Auto) | no | no | `dynamic_res.gd` |
| Default render scale (Auto) | 0.85 | 1.0 | 1.0 | 1.0 | `Game.render_scale_now` |
| Full-detail trees out to | 160 m | 200 m | 300 m | 340 m | `world_builder.gd:367`, `fill_landscape.gd` |
| Grass density | 0.4 | 0.5 | 1.0 | 1.3 | `Game.grass_density` |
| Rain / snow particles | 5k / 7k | 9k / 12k | 16k / 18k | 20k / 22k | `weather.gd` |
| Lens pass: blur taps / sun shafts / grain | 0 / off / off | 6 / off / on | 8 / 10 / on | 10 / 14 / on | `camera_post.gd` |
| Cockpit mirror | static | static | live | live | `cockpit.gd` |
| Dust motes / gust debris / dust devils | off | on | on | on | `atmosphere.gd` |

### Techniques used everywhere

- **Merged static geometry.** Procedural buildings and props are written into `SurfaceTool`s and committed
  as one mesh per material per spatial cell (`TrackThemes` uses 320 m cells, `TracksideKit` 80 m cells,
  `GxGeo` per piece). Printed faces share texture atlases (`TracksideUV`, `gx_*` atlases). Cells exist so
  merged meshes still frustum-cull.
- **MultiMesh for repeats.** Trees, grass, crowds (`PeopleKit`), parked cars, Poly Haven props
  (`GxProps.scatter`), wildlife, skid marks, smoke puffs, flags, glows.
- **Crowds.** `PeopleKit` figures are MultiMesh instances in ~10 m cells with near / mid / far mesh tiers
  chosen per cell with hysteresis, and one decimated shadow-only MultiMesh within 60 m. All animation is in
  `shaders/people.gdshader`.
- **HLOD with `visibility_parent`.** The forest (`world_builder.gd:371`), theme trees (`themes.gd:426`) and
  landscape filler (`fill_landscape.gd:1159`) build: near MultiMeshes -> merged far mesh of a 100 m cell ->
  merged far mesh of a 300 m super cell. A child is drawn only while its parent is hidden, so the swap
  happens in one frame with no gap and no double draw.
- **Shadow proxies.** Cars cast shadows from one merged `ShadowProxy` mesh (`car.gd:733`); the forest
  casts from its far-LOD cell mesh; crowds from a decimated MultiMesh. Visible meshes have shadows off.
- **Few real lights.** No lights on small things; night lamps are shadowless, short-range, fading
  SpotLights; flares and campfires are additive shader glows, not lights.
- **Car LODs.** `CarModel._with_lods` regenerates LODs after merging (the importer's are lost on rebuild).
- **Upscaling.** `Game.render_scale` 0 = Auto, else 50/59/67/77/85/100 %; upscaler FSR 1 (default),
  FSR 2 (temporal, disables FXAA) or bilinear (`Game.scaling_mode`).
- **DynamicRes** (`scripts/race/dynamic_res.gd`): only on Auto resolution at Low/Medium. Once per second it
  steps the 3D scale down 5 % when below 62 fps, back up after a hold that doubles if a raise had to be
  undone. Floor 0.7 (lower on big screens, but never under ~1.6 MP). At the floor and still slow for 3 s it
  turns SSAO off and drops the four finest glow levels; back on after 5 s of clear headroom. Frozen during
  loading, the countdown and the first 6 s of racing (shader compilation would mislead it).
- **Asset preloading.** `AssetPreload` decodes big textures, people meshes and grid car models on worker
  threads while the loading screen is up; three warm-up frames compile pipelines before the lights.

### Visibility range rules (read before touching any `visibility_range_*`)

- Godot measures visibility range **to the centre of the instance AABB**, not to its nearest point. A
  200 m merged cell with `visibility_range_end = 300` disappears when its centre is 300 m away, i.e. its
  near edge is only ~200 m away. Extend ranges by the AABB half-diagonal; `Gx.add_mesh` does this
  (`gimmicks/gx.gd:158`).
- Short ranges must not pop. Use `visibility_range_fade_mode = VISIBILITY_RANGE_FADE_SELF` with a margin
  (20-40 m, `Gx.add_mesh` uses 10 % of the range). The fade alpha is also measured to the AABB centre.
- `FADE_SELF` renders the object through the **transparent pipeline** while it fades (alpha blending, no
  depth prepass, sorting). It is fine for a soft far edge, but do not use it for LOD swaps; use
  `visibility_parent` HLOD for those (see the forest comment at `world_builder.gd:371-379`).
- **Never fix frame rate by shortening view ranges.** Add a cheap far LOD or impostor that stays visible.
- Check with `--pop-audit` (`tools/pop_audit.gd`): it lists short ranges and every hard switch-on ahead of
  the camera, ranked by on-screen size.

### Measuring

- `tools/perfcheck.sh` (the gate; `TRACKS="id ..."` for a subset), `--screenshot=... --shot_at=N` prints
  `perf avg_fps / low1_fps / worst_ms` and a GPU / render CPU / process / physics split for the 6 s before
  the shot (`race.gd:894`).
- `--perf=<flags>` switches individual features off in one run; `--perf-ab[=feat,...]` alternates
  features on/off inside one run and prints the cost of each (`tools/perf_ab.gd`).
- Environment variables for bisecting: `VEG_OFF`, `FOREST_OFF`, `GRASS_OFF`, `BELT_OFF`, `NO_THEMES`,
  `NO_DRESS`, `NO_SHAPER`, `FILL_OFF`, `TERRAIN_FLAT`, `VEG_DEBUG`, `FILL_TRIS`.

---

## 9. Settings persistence

`user://settings.cfg` (a `ConfigFile`), read in `Game._ready()` and written by `Game.save_settings()`
(`scripts/autoload/game.gd:66`, `136`). The settings UI (`SettingsPanel`) saves on every change.

| Section | Keys |
|---|---|
| `player` | `name`, `assists`, `paint`, `car`, `units`, `control_hints`, `cockpit_mirror` |
| `race` | `track`, `laps`, `bots`, `difficulty` |
| `video` | `quality`, `window_mode`, `vsync`, `render_scale`, `upscaler` |
| `audio` | `volumes` (dictionary per bus: Master, Engine, Effects, Ambience, Music) |
| `controls` | `bindings` (action -> `{keys = [k0, k1], pad = {...}}`, see `InputSetup`) |

Other files in `user://`: championship state and time-trial ghosts (`ModeStore`, under `user://test/` for
debug runs), and the loading screen's learnt step timings (`user://load_profile.cfg`, `LoadingScreen`). Runs with user args never write
`settings.cfg`.

---

## 10. Debug command-line flags

Godot passes everything after a bare `--` to the game (`OS.get_cmdline_user_args()`). Example:

```sh
tools/bgrun.sh res://scenes/race.tscn -- --track=altstadt --bots=7 --allbots --weather=5 \
    --screenshot=/tmp/a.png --shot_at=20
tools/hrun.sh res://scenes/race.tscn --quit-after 2000 -- --allbots --track=hochwald
```

`race.gd` parses `--key=value` and `--flag` into `_args` (`race.gd:632`); other scripts read the raw args
themselves. Any user arg also makes the run silent and keeps settings untouched (see section 1).

### Race setup (`scripts/race/race.gd`)

| Flag | Meaning |
|---|---|
| `--track=<id>` | Track id from `TrackDefs` (default: last chosen). |
| `--laps=N` | Number of laps. |
| `--bots=N` | Bot count in single player. |
| `--allbots` | The player's car is driven by the AI too; prints per-lap times and final standings with AI stats, then quits. |
| `--car=<id>` | `CarCatalog` id for the player's car. |
| `--weather=N` | Weather condition 0-10 (section 7). |
| `--difficulty=0..2` | Easy / Medium / Hard. |
| `--quality=0..3` | Graphics quality for this run. |
| `--mode=race\|championship\|timetrial` | Single-player game mode. |
| `--champ_new=<series id>` | Start a new championship series (`Championship.start`); `--bots` sets the number of opponents (default 7). |
| `--skill=X` | Every AI car at this skill. |
| `--mixdiff` | Debug field: a reference AI car on pole (skill `--refskill`, default 1.3), Hard/Medium/Easy behind, all on the player's model; prints contact stats. |
| `--spawn=<m>` | Spawn the player this many metres round the lap. |
| `--nodynres` | Do not add `DynamicRes`. |
| `--nohud` | Hide both HUD layers (clean frames). |
| `--cam=chase\|cockpit\|far\|bumper\|bonnet\|roof\|tv` | Start in this camera. |
| `--shotcam=x,y,z` | Camera at this offset from the player's car (FOV 40). |
| `--worldcam=x,y,z,lx,ly,lz` | Camera at a fixed world position looking at a point (FOV 50). |
| `--screenshot=<png>` | Save a screenshot and quit; prints avg / 1%-low fps, the frame-time split, draw calls. |
| `--shot_at=<s>` | When to take it (default 3 s after loading). |
| `--sun_info` | With `--screenshot`: print sun and shadow-pass statistics. |
| `--probe_meshes` | With `--screenshot`: list visible meshes whose AABB contains the player. |
| `--hold_loading[=0..1]` | Keep the loading screen up at this progress (screenshots). |
| `--loadprof` | Print load timings per build step and per car spawn. |
| `--telemetry` | Print every car's index, lap, speed, position every 2 s (also logs weather). |
| `--steer_log` | Print the front-wheel angle per tick for the first three cars between 8 and 10 s. |
| `--offtrack_test[=gravel\|kerb\|kerb_out]` | Drop the player off the road and report whether it gets back on. |
| `--shadow_probe` | Place a plane and two boxes ahead of the player to inspect shadows. |
| `--weather_at=<s>`, `--weather_speed=<x>` | Changeable weather: start later in the timeline / fast-forward. |
| `--perf=a,b,...` | Switch features off: `nomsaa msaa2 taa fsr2 fsr75 fsr80 bil75 half nossao nossr noglow noshadow nosun nofog noenv nopost noambient nobeamshadow nolamps nocarlights noprecip nocars nocarshadow nofade nofar nomm sky256 skyq tick60`, plus `hide:<name>`, `noproc:<script>`, `envset:<prop>=<v>`, `sunset:<prop>=<v>`. |
| `--pop-audit[=shots]` | Load `tools/pop_audit.gd` (visibility-range / LOD pop audit). |
| `--pop-shots=<prefix>[,start,step,count,burst,scale]` | With `--pop-audit`: capture a drive-ahead image sequence. |
| `--perf-ab[=feat,...\|hitch]` | Load `tools/perf_ab.gd` (in-run on/off cost of features; `hitch` logs long frames). |

### Camera, lens and HUD

| Flag | File | Meaning |
|---|---|---|
| `--cam=<mode>` | `camera/chase_camera.gd` | Also read here (same values as above). |
| `--nopost` | `camera/chase_camera.gd` | No lens/grade pass. |
| `--camstats` | `camera/chase_camera.gd` | Print camera mode, GPU ms, fps, rumble. |
| `--cam_look=sun\|x,y,z` | `camera/chase_camera.gd` | Look past the sun from above the car, or at a point. |
| `--postq=0..3` | `camera/camera_post.gd` | Lens pass quality only. |
| `--shafts=<x>` | `camera/camera_post.gd` | Multiply the sun-shaft strength. |
| `--hud_force=results\|lap\|final\|wrong\|pause\|pause_settings\|pause_controls` | `ui/race_hud.gd` | Show that HUD element one second before `--shot_at`. |

### Car

| Flag | File | Meaning |
|---|---|---|
| `--mirror`, `--nomirror`, `--fullmirror` | `car/cockpit.gd` | Force the cheap live / no / full live rear-view mirror. |
| `--hands`, `--nohands` | `car/cockpit.gd` | Driver's hands on the wheel. |
| `--probe`, `--noprobe`, `--showcut`, `--nocockpitfx` | `car/cockpit.gd` | Cockpit A/B and debug views. |
| `--dirt=off\|0..1`, `--dirt_kind=dust\|mud\|snow\|wet\|only_<layer>`, `--dirt_lod=light\|...`, `--dirt_log` | `car/car_dirt.gd` | Force or log car dirt. |
| `--fxdebug`, `--fxtest`, `--fxshots=<prefix>` | `car/car_fx.gd` | Car effects debugging and screenshots. |
| `--debug-impacts` | `car/car_impacts.gd` | Log contact sounds. |
| `--nopreload` | `race/asset_preload.gd` | Disable background asset preloading. |
| `--dynres_nofreeze` | `race/dynamic_res.gd` | Let DynamicRes act during the countdown (A/B). |

### World and track building

| Flag | File | Meaning |
|---|---|---|
| `--weather_script=<scenario>`, `--weather_seed=<n>` | `world/weather_cycle.gd` | Pick the changeable-weather scenario / seed. |
| `--weather_log`, `--weather_keep_shadows` | `world/weather_cycle.gd` | Log the timeline; keep sun shadows while overcast (A/B). |
| `--nomist`, `--nomotes`, `--nodebris`, `--nodevil`, `--devil`, `--gust=<x>` | `world/atmosphere.gd` | Atmosphere parts off / forced. |
| `--noleaves`, `--debug-leaves` | `world/road_leaves.gd` | Road leaves off / log. |
| `--no-people`, `--people-old`, `--debug-people`, `--debug-people-time` | `world/people.gd` (+ themes, track_props) | Crowds off / old path / logging. |
| `--no-wildlife`, `--debug-wildlife`, `--wildlife-test=<kind>` | `world/wildlife_builder.gd`, `world/wildlife.gd` | Wildlife off / log / line-up of one kind. |
| `--trees_old` | `world/vegetation.gd`, `world/world_builder.gd` | Use the old procedural trees and no edge belt. |
| `--spacedebug` | `world/audio_space.gd` | Print reverb ray readings. |
| `--debug-audio` | `world/ambience.gd` | Log ambience. |
| `--debug-scenery`, `--debug-themes`, `--debug-dressing` | `track/scenery.gd`, `track/themes.gd`, `track/set_dressing.gd`, `track/night_lights.gd` | Build logs. |
| `--debug-dress`, `--no-dress` | `track/gimmicks/dress_*.gd`, `lm_*.gd` | Dressing logs / skip dressing (kiefernring, valtellina). |
| `--fill_off`, `--fill_views`, `--fill_close` | `track/gimmicks/fill_landscape.gd` | Landscape filler off / debug views. |
| `--gx_test=<piece>:<kind>,...`, `--gx_shots=<dir>`, `--gx_at=<m,...>` | `track/gimmicks/gx_test.gd` | Place Gx pieces on any track and photograph them. |
| `--dress_shots=<prefix>`, `--dress_at=...`, `--dress_cam=...`, `--dress_side=...`, `--dress_t0=<s>` | `track/gimmicks/dress_shots.gd` | Many screenshots from one run for track dressers. |
| `--gx_ab`, `--gxdump`, `--no-heli-sound` | `gx_camp.gd`/`gx_geo.gd`, `gx_skilift.gd`, `gx_heli.gd` | Piece-specific debugging. |

### Menu and global

| Flag | File | Meaning |
|---|---|---|
| `--uishot=<png>`, `--uishot_at=<s>` | `autoload/game.gd` | Screenshot whatever scene shows after 1.5 s (or the given time), then quit. |
| `--menu_screen=setup\|host\|join\|settings\|credits\|lobby\|timetrial\|championship\|champ_setup` | `ui/menu.gd` | Open a menu screen directly. |
| `--settings_tab=N` | `ui/menu.gd` | Settings tab to open. |
| `--nethost [--wait=N] [--weather=N]`, `--netjoin=<ip>`, `--name=<s>` | `ui/menu.gd` | Automated LAN host / join for two-instance tests (host: valle_club, 1 lap, 2 bots). |
| `--credits_file=<path>` | `ui/menu_credits.gd` | Read another credits file. |
| `--tt_skill=X` | `modes/time_trial.gd` | Time trial with `--allbots`: the AI's pace. |
| `--write-movie` (Godot's own) | `autoload/game.gd` | Keeps audio when recording a movie. |

Test scenes in `tests/` and tools in `tools/` take their own flags; see the READMEs there.
