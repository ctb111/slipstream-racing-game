# scripts/race/

The race itself: building the scene, the grid, start lights, laps, positions, results, network sync, plus the
AI that drives bots and the systems that keep the frame rate up while racing.

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `race.gd` | (none; root of `scenes/race.tscn`) | Race manager. `_ready` is the whole startup: args, quality, `DynamicRes`, game mode overrides, `LoadingScreen`, `AssetPreload`, `Circuit.build()`, car spawns, camera, HUDs, warm-up. Runs the countdown, lap counting, ranking, slipstream, finish, resets, network RPCs and all race-level debug flags. | `_ready`, `_spawn`, `_physics_process`, `_update_progress`, `_on_line_crossed`, `standings()`, `quit_to_menu()`; signals `lights_changed`, `lap_completed`, `race_finished`; RPCs `_net_cars`, `_net_race`, `_net_lights`, `_net_finished` |
| `racing_line.gd` | `RacingLine` | Precomputed racing line (minimum-curvature lateral offset, sampled every 2 m) and target speeds from `AI_LAT_G` / `AI_BRAKE` scaled by grip. Also the fast lap-position lookups used for lap counting, ranking, resets and grid slots. | `RacingLine.new(curve, width, lat_g, brake)`, `closest_index(pos, hint)`, `offset_of(i)`, `point_ahead`, `lane_point`, `speed_ahead`, `transform_at(offset, lateral)` |
| `ai_driver.gd` | `AIDriver` | Child node of a `Car` that drives it with the player's controls: pure-pursuit steering, speed plan x `skill`, following and overtaking, small human wobble, stuck detection. Has debug stats used by `--allbots` / `--mixdiff`. | `line`, `skill`, `enabled`, `others`; signal `stuck(car)` |
| `dynamic_res.gd` | `DynamicRes` | Adaptive 3D render scale for Auto resolution (any preset): steps down 5 % below 62 fps (vsync on: just under the refresh rate; raises only with GPU headroom), creeps back up with a growing hold; at the floor it also turns SSAO off and drops fine glow levels. Frozen during loading, countdown and the first 2 s; starts at the scale the last race on that track settled at (`Game.auto_scales`). | `DynamicRes.wanted()`; added by `race.gd` unless `--nodynres` |
| `asset_preload.gd` | `AssetPreload` | While the loading screen shows, starts `ResourceLoader.load_threaded_request` for big textures, people meshes, vegetation atlases and the grid's car models so the main-thread build finds them cached. | `AssetPreload.start(track_def, car_ids)`, `AssetPreload.finish()`; `--nopreload` disables |

## How it connects

- Reads its setup from `Game` (autoload) and optionally a `RaceMode` (`scripts/modes/`).
- Builds `Circuit` (`scripts/track/circuit.gd`), then spawns `Car`s (`scripts/car/car.gd`) at
  `circuit.grid_transform(slot)`; bots get an `AIDriver` using `circuit.line` (a `RacingLine`).
- Creates `ChaseCamera` (`scripts/camera/`), `Hud` and `RaceHud` (`scripts/ui/`). `RaceHud` reads
  `race.entries`, `race.state`, `race.race_time` and listens to the race signals.
- Online: `Net` (autoload) switches every peer into this scene; the RPCs here then keep cars and timing in
  sync. Authority rules are in `docs/ARCHITECTURE.md#6-networking`.
- Debug tools `tools/pop_audit.gd` and `tools/perf_ab.gd` are loaded from here by `--pop-audit` / `--perf-ab`.

## Gotchas

- **Do not rename the `Race` root node** (in `scenes/race.tscn`): RPCs are routed by node path.
- **`_loaded` gates physics.** Nothing race-related runs until the loading screen is gone; `DynamicRes` also
  reads `_loaded`, `state` and `race_time` from its parent by name.
- **Lap counting is index based.** A crossing only counts after the car was "armed" between 40 % and 60 % of
  the lap, so cutting across the infield or reversing over the line does not add laps. Keep that if you
  change `_update_progress`.
- **The host owns timing.** In online races clients never decide laps or finishing; they only mirror
  `_net_race`. Only the owner of a car may move it (`_net_cars` checks the sender).
- **Bot difficulty is skill, not cheating.** `Game.bot_skill()` scales the planned speed; bots use the same
  physics, grip and assists as the player. Tune `RacingLine.AI_LAT_G` / `AI_BRAKE` and the skill table in
  `game.gd` rather than giving bots extra grip.
- **Strict typing:** `entries` is `Array[Entry]`; lambdas over it need typed parameters
  (`func(x: Entry) -> bool:`), as the existing code shows.

## Where to start reading

`race.gd` `_ready()` (lines 55-194), then `_spawn()`, then `_physics_process()` and the network section.
For the AI: `racing_line.gd` `_init`, then `ai_driver.gd` `_physics_process`.
