# scripts/car/

Everything about a car: physics, the catalogue of drivable cars, loading their glTF models, the cockpit view,
lamps, effects, dirt build-up and synthesised audio.

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `car.gd` | `Car` (`RigidBody3D`) | Arcade-sim physics: raycast suspension with anti-roll bars, simplified Pacejka tyres, torque curve, 5-speed gearbox (auto/manual), brakes with EBD, turn assist, stability assist, power drifts, aero and slipstream (`draft`). Builds its body (model or procedural fallback), wheels and child effect nodes. Network puppet mode. | Inputs `throttle`, `brake`, `steer_input`, `handbrake`; `model_id`, `paint_color` (set before adding to tree); `reset_to(xf)`, `set_assists(on)`, `set_remote()`, `net_pack()`, `net_push(state)`; statics `weather_road_grip`, `weather_off_grip`, `headlights`, `night`, `lamps_on` |
| `car_catalog.gd` | `CarCatalog` | The six cars (`porsche930` = `DEFAULT`, `bmw_e30_m3`, `datsun_240k`, `toyota_ae86`, `mazda_rx7_fc`, `ferrari_f40`): glb path, real length, material roles (wheels, paint, lamps), credit line, physics preset (keys = `Car` property names), engine sound parameters. | `ids()`, `has(id)`, `get_car(id)`, `physics(id)`, `display_name(id)`, `available_ids()` |
| `car_model.gd` | `CarModel` | Loads a catalogue glb once (cached) and returns what `Car` needs: one merged body mesh with separate paint and brake surfaces, four wheels centred on their hubs, measured wheelbase / track / wheel radius, the merged shadow-proxy mesh, regenerated LODs. | `CarModel.available(id)`, `CarModel.data(id)` |
| `car_body_builder.gd` | `CarBodyBuilder` | Procedural lofted 930-style body and wheels; only used if a model is missing. | `build(visual, paint)`, `build_wheel(...)`, `paint_material(c)` |
| `car_palette.gd` | `CarPalette` | Muted period paint colours. | `COLORS`, `pick(i)` |
| `car_lights.gd` | `CarLights` | Headlamps when they are on (every condition except plain Clear: `Car.headlights`, set in `Circuit.build`): lit lenses, one low-beam SpotLight, at night a beam cone and red tail glow on the road. Only the local player's beam casts shadows (High+). | `CarLights.build(car, mesh, data, front_z, ..., night)`, `enable_shadows()`, `add_road_fill()`, `set_on()`, `set_braking()` |
| `cockpit.gd` | `Cockpit` | In-car view for the local driver: steering wheel that turns (the model's static wheel is cut out of a cockpit-only copy of the body), backlit gauges drawn into textures, a real rear-view mirror (SubViewport, live on High/Ultra), windscreen rain/snow, cabin light, optional hands. | `Cockpit.spec_for(id)`, `set_active(on)`, `eye_transform()`; created by `ChaseCamera` |
| `tire_fx.gd` | `TireFx` | Tyre smoke, dust off the tarmac, skid marks. All cars' skid marks share one MultiMesh ring buffer (one draw call). | added by `Car._ready` |
| `car_fx.gd` | `CarFx` | Backfire flames (in sync with `CarAudio` pops), glowing brake discs, sparks against rails/walls, splashes through standing water (same noise as the road shader's puddles). Idle = hidden. | added by `Car._ready` |
| `car_dirt.gd` | `CarDirt` | Dirt, mud, dust, slush, snow and water building up during a race. A clean car keeps its stock materials; once dirty, body and wheels switch to shader variants composed from `shaders/car_dirt.gdshaderinc`, windows to `shaders/car_glass*.gdshader`. | added by `Car._ready` |
| `car_audio.gd` | `CarAudio` | Engine sound synthesised per engine type (catalogue `engine` block) on a worker thread into short loops at several rpm points, plus turbo, blow-off, overrun pops, tyre, wind and gear sounds. Each car only crossfades and re-pitches players. Adds `CarImpacts` and creates the scene's `AudioSpace`. | `warm_up()`, `request_engine()`, `engine_bank()`, `synth_engine()`; signal `popped` |
| `car_impacts.gd` | `CarImpacts` | Synthesised crunches, thuds and scrape loops from contacts. Only physically simulated (local) cars listen for contacts. | `warm_up()` |

## How it connects

- `race.gd` creates each `Car`, sets `model_id` and `paint_color`, places it, then either adds an `AIDriver`
  (`scripts/race/`), marks it `player_controlled`, or calls `set_remote()` for another player's car.
- `Weather` (`scripts/world/weather.gd`) and `Circuit.build` set the `Car.*` statics (grip, lamps, night).
  Surface grip per wheel comes from the collider the wheel ray hits: static bodies carry `grip` / `drag`
  metadata (`TrackBuilder._add_body`, `Terrain.build_nodes`), read at `car.gd:429`.
- `ChaseCamera` reads speed, g and suspension; the HUD reads `rpm`, `gear`, `speed`, `drifting`,
  `body_slip`.
- Models and their textures live in `assets/cars/` (credits in `assets/cars/CREDITS_cars.txt`).
- `GxParkedCars` and the showroom / ghost reuse `CarModel.data()` to draw cars without physics.

## Gotchas

- **Set `model_id` and `paint_color` before `add_child`**: `_ready` builds the body from them.
- **Catalogue physics keys must match `Car` property names**; `_apply_preset` applies them with `set()`.
- **Car-local space**: -Z is forward, wheel mounts at y = 0, hubs `REST_DROP` (0.225 m) below at rest.
- **Shadows come only from `ShadowProxy`.** The visible body and wheels have `cast_shadow = OFF`. If you add
  a visible part, add it to the proxy (`CarModel._shadow_mesh`) instead of turning its shadow on.
- **Rebuilding a mesh drops its import LODs.** Run new merged meshes through `CarModel._with_lods`.
- **Remote cars are on collision layer 2** and interpolated 0.1 s in the past; local cars get a soft push
  from them in `race.gd`, not a physics collision.
- **Audio is synthesised, never sampled**, and done on worker threads with static caches. Keep new sounds
  in that pattern (no main-thread synthesis during a race).
- New car: add the glb (and textures) under `assets/cars/`, a `CARS` entry with a credit line, the license in
  `assets/cars/CREDITS_cars.txt`, `CREDITS.md` and `assets/CREDITS_INGAME.txt`. Only CC0 / CC BY / CC BY-SA
  (no NC, no ND). No manufacturer logos on the model.

## Debug flags

`--car=<id>`, `--dirt=off|0..1`, `--dirt_kind=...`, `--dirt_lod=...`, `--dirt_log`, `--fxdebug`, `--fxtest`,
`--fxshots=<prefix>`, `--debug-impacts`, cockpit: `--mirror`, `--nomirror`, `--fullmirror`, `--hands`,
`--nohands`, `--probe`, `--noprobe`, `--showcut`, `--nocockpitfx`. Test scenes: `tests/handling_test.tscn`,
`tests/car_preview.tscn`, `tests/cockpit_preview.tscn`, `tests/dirt_preview.tscn`,
`tests/engine_audio_test.tscn`, `tests/impact_test.tscn`.

## Where to start reading

`car.gd`: the exported parameters at the top, then `_physics_process` (lines 171-195) and the functions it
calls in order: `_update_steering`, `_update_gearbox`, `_engine_drive_force`, `_suspension`, `_tires`,
`_stability`, `_arcade_grip`, `_aero`. Then `car_catalog.gd` for one full car entry.
