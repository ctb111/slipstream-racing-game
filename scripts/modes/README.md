# scripts/modes/

Single-player game modes layered on top of an ordinary race. `race.gd` runs the race exactly as usual; a mode
only adjusts the setup beforehand, records results afterwards, and adds buttons / points to the results
screen. Online races ignore modes.

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `race_mode.gd` | `RaceMode` (`Node`) | Base class; every hook is a no-op. | `setup_overrides() -> Dictionary` (keys `track`, `laps`, `grid`, `game`), `attach(race)`, `results_subtitle()`, `results_buttons()`, `points_for(entry)` |
| `championship.gd` | `Championship` | A series of rounds against a fixed bot field. Points 10-8-6-5-4-3-2-1, reverse-championship grid (leader at the back). Static functions own the saved state; an instance controls one round. | statics `SERIES`, `start(series_id, difficulty, laps, opponents)`, `active()`, `complete()`, `round_index()`, `current_round()`, `grid()`, `record(...)`, `abandon()`; instance hooks from `RaceMode` |
| `time_trial.gd` | `TimeTrial` | Solo laps against the clock and a ghost of the best lap. Records every lap; a new personal best replaces the ghost and is saved per track + car with splits at 1/3 and 2/3. | `file_for(track, car)`, `load_best(...)`, `best_lap(...)`; hooks from `RaceMode` |
| `ghost.gd` | `GhostCar` (`Node3D`) | Translucent, collision-less replay car built from `CarModel` data, and the ~30 Hz recorder (`[t, px, py, pz, qx, qy, qz, qw]` per sample in a `PackedFloat32Array`). | `GhostCar.record(buf, t, xf)`, `GhostCar.duration(buf)`, `build(model_id, paint)`, `show_at(t)` |
| `mode_store.gd` | `ModeStore` | Where mode progress lives (JSON in `user://`, or `user://test/` for debug runs) and a shared user-args parser. | `dir()`, `save_json()`, `load_json()`, `remove()`, `args()` |

## How it connects

- `ui/menu_modes.gd` builds the Time Trial / Championship menu screens, sets `Game.session` and switches to
  the race scene.
- `race.gd` `_make_mode()` creates the controller from `Game.session` (or `--mode=`), applies
  `setup_overrides()` before building the circuit, adds the node as `Mode` and calls `attach(race)` after
  the cars spawn.
- `ui/race_hud.gd` / `ui/hud_results.gd` ask the mode for the results subtitle, buttons and points column.

## Gotchas

- `setup_overrides().game` values are applied to `Game` **only while the race sets itself up**; `race.gd`
  restores the previous values afterwards, so a championship's difficulty never leaks into the player's
  settings.
- Debug runs (any user args) use `user://test/`, never the player's real progress.
- Bump the save format carefully: old JSON files in players' `user://` must still load (use `.get(key,
  default)`).

## Debug flags

`--mode=race|championship|timetrial`, `--champ_new=<series id>`, `--laps=N`, `--tt_skill=X` (with
`--allbots`).

## Where to start reading

`race_mode.gd` (tiny), then `time_trial.gd`, then `championship.gd`.
