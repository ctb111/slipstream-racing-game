# scripts/camera/

The in-race camera and everything it carries: seven view modes, grounded camera motion, the driver's head in
the cockpit, trackside TV shots, and the full-screen lens / colour-grade pass.

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `chase_camera.gd` | `ChaseCamera` (`Camera3D`) | The one race camera. Modes `CHASE, COCKPIT, FAR, BUMPER, BONNET, ROOF, TV` (`MODE_NAMES`), cycled with the `camera` action; look back/left/right. Adds road rumble, impact jolts, lateral-g roll, surge pull-back and FOV kick. Creates and feeds `CameraPost`, creates the `Cockpit` for the cockpit view, and uses `TvDirector` for the TV view. | `target` (the Car), `mode`, `debug_offset` / `debug_world` (set by `race.gd` for `--shotcam` / `--worldcam`) |
| `camera_shake.gd` | `CameraShake` | Motion read off the car: suspension rumble, sprung jolt on impacts and landings, smoothed lateral g. Sampled in physics, applied per frame. | `sample(car, dt)`, `offsets()` |
| `cockpit_head.gd` | `CockpitHead` | The driver's head for the cockpit view: locked to the car, but pushed by g, keeps the horizon steadier than the shell, glances towards the apex, turns with the look keys. | `place(...)` |
| `tv_director.gd` | `TvDirector` | Trackside "TV" cameras: picks a spot beside the track ahead of the car, pans and zooms to follow, cuts to the next spot after the car passes. Needs a racing line. | `update(...)` (returns false without a line) |
| `camera_post.gd` | `CameraPost` (`CanvasLayer`, layer -1) | One full-screen `canvas_item` pass under the HUD (`shaders/post_process.gdshader`): per-weather colour grade (night grade at night), vignette, radial speed blur, edge aberration, grain, sun glare and shafts, rain drops on the lens. Quality-scaled. | `update_fx(...)` (called by `ChaseCamera` every frame) |

## How it connects

- Created by `race.gd` after the cars spawn (`_camera.target = player.car`, `make_current()`).
- Reads the car (`scripts/car/car.gd`): speed, g, suspension, `Car.night`, `Car.weather_*_grip`.
- Cockpit mode instantiates `Cockpit` (`scripts/car/cockpit.gd`) on the player's car; the windscreen rain
  and the mirror live there, not here.
- `CameraPost` finds the sun by the node name `"Sun"` and the `Weather` node next to it to pick the grade
  and sun glare (`scripts/world/weather.gd`).
- `TvDirector` uses the circuit's `RacingLine`.

## Gotchas

- **Physics interpolation is off for this camera** (`physics_interpolation_mode = OFF`): it follows the
  interpolated car itself; letting the engine interpolate it too makes everything judder.
- **The lens pass is a CanvasLayer under the HUD** (layer -1): HUD elements must be on higher layers or they
  get blurred and graded.
- Keep `CameraPost` cheap: it runs on every pixel every frame. New effects need a quality gate
  (`[Low, Medium, High, Ultra]` arrays like `blur_taps`) and must be off on Low.
- The sun must stay named `"Sun"` (also at night, when it is the moon) or glare and grading fall back to
  guessing from grip.

## Debug flags

`--cam=chase|cockpit|far|bumper|bonnet|roof|tv`, `--nopost`, `--camstats`, `--cam_look=sun|x,y,z`,
`--postq=0..3`, `--shafts=<x>`. From `race.gd`: `--shotcam=x,y,z`, `--worldcam=x,y,z,lx,ly,lz`.

## Where to start reading

`chase_camera.gd` `_ready` and `_process`, then `camera_post.gd` `_ready` (what the grade depends on).
