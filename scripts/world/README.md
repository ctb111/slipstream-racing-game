# scripts/world/

The world around the track: weather, sky and light, terrain, forest and grass, crowds, wildlife, ambient
sound and acoustics, atmosphere effects, and the shared photographic PBR material library.

## Files

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `weather.gd` | `Weather` (`Node3D`) | Weather for a race: `PRESETS` per `Kind` (`CLEAR, STORM, SNOW, GOLDEN, DAWN, FOG`) + `NIGHT` overrides; conditions 0-10 (`NAMES`); builds sky (`sky.gdshader` on an HDRI), environment (AgX, fog, SSAO/SSR/SSIL by quality), sun/moon, rain / snow particles around the camera, lightning and thunder; sets `Car` grip statics and the `wx_*` shader globals. | `Weather.create(parent, condition, night, timeline)`, `Weather.current()`, `preset_for(kind, night)`, `cond_kind/cond_night/cond_changeable/condition`, `set_precipitation()`, fields `kind`, `night`, `preset`, `env`, `sun`, `clock`, `cycle` |
| `weather_cycle.gd` | `WeatherCycle` (`Node`) | Changeable weather: a timeline dictionary of targets (gloom, rain, snow, wind) between a `base` and a `heavy` preset. State is a pure function of the timeline and `Weather.clock`; wetness and snow cover are integrated in fixed 0.25 s steps so all machines agree. | `WeatherCycle.roll()`, `make_timeline(seed, force)`, `setup(weather, timeline)`, `apply(dt)`, `describe()` |
| `world_builder.gd` | `WorldBuilder` | Ground plane, terrain material, distant hills, and the forest: photo-card trees from `Vegetation` as MultiMeshes with a near / far / super-cell HLOD chain (`visibility_parent`) and merged shadow meshes; the forest-edge belt. | `tex(id, kind)`, `terrain_material(noise)`, `build_ground`, `build_hills`, `foliage_material`, `build_forest(...)` |
| `terrain.gd` | `Terrain` | Heightmap (513x513) of layered noise around the circuit. Gives the road its heights (`elevate`, smoothed), then shapes the land to meet it (`carve`: banks, cuttings, embankments, bowl of hills). Per-track character in `STYLE` (overridable by `def.terrain`). One heightmap is both the Jolt `HeightMapShape3D` and, at half resolution in chunks, the render mesh. | `Terrain.new(bounds, margin, amp, seed)`, `configure(def)`, `elevate(points)`, `set_base(...)`, `carve(curve, width)`, `height_at(x, z)`, `road_distance(x, z)`, `build_nodes(...)` |
| `vegetation.gd` | `Vegetation` | Procedural trees and bushes (spruce, pine, beech, oak, birch, bushes) dressed with photo atlases; each emits a detailed near mesh and a cheap far mesh with the same silhouette. Loads baked models from `assets/vegetation/trees/` when present. | `forest_model(...)`, `spruce/pine/broadleaf/bush(...)`, `set_weather(...)`, `set_material_wind(...)` |
| `grass.gd` | `Grass` | Wind-blown verge grass: crossed alpha cards from a photo atlas, grouped in ~3 m patches, MultiMesh chunks of ~40 m that draw only near the camera. Density from `Game.grass_density()`. | `Grass.build(parent, curve, terrain, width, preset, noise)` |
| `materials.gd` | `Mats` | Shared library of CC0 photographic PBR materials (`assets/materials/`) for procedural buildings and props via `pbr_triplanar*.gdshader`; binds ground grime and weather once per track. | `Mats.mat(name, tint, double_sided)`, `Mats.bind_world(terrain, preset)`, `props()`, `tex()`, `noise()` |
| `people.gd` | `PeopleKit` | Crowd figures from baked posed meshes (`assets/people/`) as MultiMesh instances drawn with `people.gdshader` (colours and animation in the shader). Crowds sort figures into ~10 m cells with near / mid / far tiers and one decimated shadow MultiMesh within 60 m. | `PeopleKit.crowd(name, role, xforms, colours, custom)`, `figure()`, `pick()`, `set_wind()`; enums `Pose`, `Role` |
| `wildlife.gd` | `Wildlife` (`Node3D`) | Animals, birds and pets (`assets/wildlife/`) as MultiMeshes with all motion in `wildlife.gdshader`: grazing, gaits, flights, soaring, reactions to cars. | `Wildlife.make(...)`, `add()`, `perch()`, `add_reactive()`, `chase_dog()`, `soar()`, `flock()`, `finish()` |
| `wildlife_builder.gd` | `WildlifeBuilder` | Places wildlife on every track by biome (forest deer and buzzards, farmland livestock and dogs, coast gulls, town pigeons and cats, dogs with spectators). Last `EXTRA_BUILDERS` entry. | `build(...)` |
| `ambience.gd` | `Ambience` (`Node3D`) | Trackside sound: crowds that cheer as cars pass, PA announcer, birds and wind, storm gusts, rain on the roof. Synthesised once on a worker thread and cached. | `build(...)` (`EXTRA_BUILDERS`), `synthesise()`, `cached()` |
| `crowd_react.gd` | `CrowdReact` (`Node`) | The crowd reacts to the race: pushes 7 vec4 shader globals (`shaders/crowd_react.gdshaderinc`) for hotspots (leader, player, battles < 1 s), yellow sectors (car stopped / crawling / spun / reset) and the chequered flag; `people`, `trackside_glow` and `trackside_smoke` shaders react by distance, so no MultiMesh is rewritten. Places the finish-line marshal. Debug `--debug-crowd`, `--crowd_force=hot,yellow,chequer`. | `build(...)` (`EXTRA_BUILDERS`) |
| `audio_space.gd` | `AudioSpace` (`Node`) | Listener acoustics: rays from the camera a few times a second; nearby walls / roofs / tunnels set a reverb on the Engine and Effects buses (bypassed in the open). | `AudioSpace.ensure(...)` (called by `CarAudio`) |
| `atmosphere.gd` | `Atmosphere` (`Node3D`) | Valley mist and low height fog, warm haze, dust motes in low sun, gust fronts with road debris, dust devils, windsocks. Tuned from the preset's `mist` / `haze`; quality-scaled. | `build(...)` (`EXTRA_BUILDERS`), `Atmosphere.gust(...)` |
| `road_leaves.gd` | `RoadLeaves` (`Node3D`) | Fallen leaves on the tarmac near forest, kicked up by passing cars (`road_leaves.gdshader`). One mesh. None on snow. | `build(...)` (`EXTRA_BUILDERS`) |
| `falling_leaves.gd` | `FallingLeaves` (`GPUParticles3D`) | Autumn leaves tumbling around the active camera (Herbstwald, attached by `theme_autumn.gd`). | `FallingLeaves.attach(parent, snowing)` |
| `spinner.gd` | `Spinner` (`Node3D`) | Turns about local Z (windmill sails) or drifts in a circle with a bob (balloon). | properties |

## How it connects

- `Circuit.build()` (`scripts/track/circuit.gd`) calls `Weather.create`, `WorldBuilder.*`, `Terrain`,
  `Grass.build`, and the `EXTRA_BUILDERS` here (`ambience.gd`, `atmosphere.gd`, `road_leaves.gd`,
  `wildlife_builder.gd`).
- `race.gd` drives `Weather.clock` for changeable weather; `Net` carries the timeline.
- `Weather` writes `Car.weather_road_grip`, `Car.weather_off_grip`, `Car.lamps_on` and the `wx_*` shader
  globals that every weather-aware shader reads through `shaders/weather.gdshaderinc`.
- `CameraPost`, `CarDirt`, `CarFx`, `TireFx`, `Cockpit`, `RaceHud`, `Atmosphere` and `DynamicRes` find the
  live weather with `Weather.current()` (`CameraPost` also looks for the `"Sun"` node).
- `PeopleKit` and `Mats` are used by almost every track builder and Gx piece.

## Gotchas

- **Weather has two numbers.** A *condition* (0-10, menu / def / `--weather`) is not a `Kind` (0-5). Dawn is
  condition 9 but `Kind.DAWN` = 4 ("Night" in `NAMES`). Always convert with the static helpers.
- **Changeable weather must build everything up front.** If you add a weather feature that the cycle can
  turn on mid-race, create it idle in `_build_environment` so nothing compiles during the race.
- **Shader globals are max-combined.** Materials keep their build-time uniforms; `weather.gdshaderinc` takes
  `max(uniform, global)`. Add new weather inputs as globals in `project.godot [shader_globals]` and push them
  in `Weather._push_globals`.
- **Forest LOD is HLOD, not fades.** Near MultiMeshes -> 100 m cell far mesh -> 300 m super cell, chained
  with `visibility_parent` so swaps are one-frame, no gap, no double draw (`world_builder.gd:371`). A
  `FADE_SELF` fade would be alpha blending (transparent pipeline). Visibility ranges are measured to the
  AABB centre.
- **Shadows come from proxies**: forest from its far mesh, crowds from a decimated MultiMesh. Keep visible
  instances shadowless.
- **Audio is synthesised on worker threads** and cached statically; never synthesise on the main thread
  during a race.
- `Terrain.N` must stay `2^k + 1` (Jolt height field).
- Do not shorten tree or crowd ranges to win frame time; add cheaper far tiers.

## Debug flags and env vars

`--nomist`, `--nomotes`, `--nodebris`, `--nodevil`, `--devil`, `--gust=<x>`, `--noleaves`, `--debug-leaves`,
`--no-people`, `--people-old`, `--debug-people`, `--debug-people-time`, `--no-wildlife`, `--debug-wildlife`,
`--wildlife-test=<kind>`, `--trees_old`, `--spacedebug`, `--debug-audio`, `--weather_script`,
`--weather_seed`, `--weather_log`, `--weather_keep_shadows`; env `VEG_OFF`, `FOREST_OFF`, `GRASS_OFF`,
`BELT_OFF`, `VEG_DEBUG`, `TERRAIN_FLAT`.

## Where to start reading

`weather.gd` (`PRESETS`, `create`, `_build_environment`), then `terrain.gd` (`STYLE`, `elevate`, `carve`),
then `world_builder.gd` `build_forest`.
