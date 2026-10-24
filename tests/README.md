# tests/

Test rigs and visual previews. There is no unit-test framework: each test is a small scene
(`.tscn`) with a script that sets something up, measures or photographs it, prints the results
and quits. Headless tests run on the `cpu` lane with `tools/hrun.sh`; visual previews need a
window and run in the background with `tools/bgrun.sh`. On Linux/Windows call `godot --path .`
with the same arguments.

Arguments after `--` are read by the test script. Note that the preview scenes take plain
`key=value` arguments (no leading `--`), the headless tests use `--key=value`.

Many more checks are built into the race scene itself (bot races, off-track tests, pop audit,
perf A/B, screenshots); see [CONTRIBUTING.md](../CONTRIBUTING.md#4-testing-workflow) and
[tools/README.md](../tools/README.md).

## Headless tests

| Scene | What it checks | Run |
|---|---|---|
| `handling_test.tscn` | Drives cars on a flat asphalt pad with keyboard-style (digital) inputs through scenarios (launch, 100-0 braking, full lock at 80/140 km/h, part-throttle turns, handbrake...) and prints stability and response metrics (slip angle, spins, yaw response, lateral g). Use it to compare handling changes and new cars. | `tools/hrun.sh res://tests/handling_test.tscn [-- --car=<id>]` |
| `reverse_test.tscn` | Auto-reverse: (A) hit a wall at 40 km/h and hold the brake, the car must back out; (B) stop from 60 km/h with the brake held, it must stay put; (C) creep into the wall on throttle, then brake. | `tools/hrun.sh res://tests/reverse_test.tscn` |
| `impact_test.tscn` | Fires a car at a guardrail at a shallow angle, then another car into it; prints what `CarImpacts` heard (impacts, scrape levels). | `tools/hrun.sh res://tests/impact_test.tscn -- --debug-impacts` |
| `engine_audio_test.tscn` | Every car's synthesised engine: synthesis time (limit 400 ms), level, clipping, NaN, loop-seam continuity, firing-frequency spectral check, the background (WorkerThreadPool) path, and that limiter, pops, blow-off and turbo whistle fire. `--dump=<dir>` writes every loop and a rev sweep as `.wav`. | `tools/hrun.sh res://tests/engine_audio_test.tscn [-- --dump=/tmp/engines]` |
| `ambience_test.tscn` | Synthesised ambience per weather: timing, level, clipping, loop seams. `--dump=<dir>` writes `.wav` files. | `tools/hrun.sh res://tests/ambience_test.tscn [-- --dump=/tmp/amb]` |
| `load_profile.tscn` | Builds every circuit (or one) and prints per-step build times (terrain, themes, forest...). Run after adding content to a track. | `tools/hrun.sh res://tests/load_profile.tscn [-- --track=<id>]` |

Read the output: the tests print their measurements and any failed expectation; there is no
global pass/fail exit code for every test, so compare against a run before your change.

## Visual previews (windowed, background)

| Scene | What it shows | Run |
|---|---|---|
| `car_preview.tscn` | Every car (or one) built from `CarModel.data()` with catalog paint: front three-quarter, side and rear screenshots, plus wheel-centring stats and surface counts printed per car. | `tools/bgrun.sh res://tests/car_preview.tscn -- car=<id> out=/tmp/carprev` |
| `cockpit_preview.tscn` | In-car views of a real, frozen `Car` on a plain ground under a sun: `top` = orthographic cut-away from inside the cabin (layout), `eye` = camera at a car-local point looking forward, `side`. Options `eye=x,y,z`, `look=`, `fov=`, `steer=`, `topy=`. | `tools/bgrun.sh res://tests/cockpit_preview.tscn -- car=<id> views=top,eye out=/tmp/cockpit` |
| `dirt_preview.tscn` | Close-ups of `CarDirt` on real cars: forced dirt `kind` (dust, mud, snow, wet, none) and `amount`, the weather's sky and grip, views rear, side, front, wheel, glass. | `tools/bgrun.sh res://tests/dirt_preview.tscn -- car=porsche930 kind=mud amount=1 weather=storm views=rear,side out=/tmp/dirt` |
| `drift_shot.tscn` | The race scene with a scripted player: after lights out it accelerates to about 75 km/h, flicks into a handbrake drift and holds it. Takes the normal race arguments. | `tools/bgrun.sh res://tests/drift_shot.tscn -- --track=valle_club --bots=0 --screenshot=/tmp/drift.png --shot_at=9` |
| `shadow_probe.tscn` | Minimal shadow check: a box on a plane under a sun, at a given quality. | `tools/bgrun.sh res://tests/shadow_probe.tscn -- --q=1 --out=/tmp/shadow.png` |

Write output to an absolute path (`out=/tmp/...`); the default for some previews is under
`user://`.

## Notes

- Add a new test as `tests/<name>.tscn` + `tests/<name>.gd`, document its purpose and run line in
  a `##` header like the existing ones, make it print measurable results and `get_tree().quit()`
  when done, and add a row here.
