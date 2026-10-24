# scenes/

Only two scenes, and each is just a root node with a script. There are no editor-built levels, prefabs or UI
scenes: everything is created in code at run time.

| Scene | Root node | Script | What it is |
|---|---|---|---|
| `menu.tscn` | `Menu` (`Control`, full rect) | `scripts/ui/menu.gd` | Main scene (`project.godot` `run/main_scene`). Main menu, showroom, settings, lobby, credits, mode screens. |
| `race.tscn` | `Race` (`Node3D`) | `scripts/race/race.gd` | One race. Builds the loading screen, circuit, cars, camera and HUD in `_ready` from the `Game` autoload. |

## How it connects

- `menu.tscn` -> `race.tscn`: `get_tree().change_scene_to_file("res://scenes/race.tscn")` from `menu.gd`,
  `menu_modes.gd`, or `Net._begin_race` (online, every peer).
- `race.tscn` -> `menu.tscn`: `race.quit_to_menu()`, `Net._to_lobby()` / `Net._fail()`.
- Test scenes live in `tests/` (handling rig, previews, audio tests), not here.

## Gotchas

- **Do not rename the `Race` node.** Race RPCs are addressed by node path (`/root/Race`) and must match on
  every peer.
- Do not move logic into these files or add child nodes in the editor; add it to the scripts so the whole
  game stays readable as code.
- `race.tscn` can be run directly with debug args, e.g.
  `godot --path . res://scenes/race.tscn -- --track=hochwald --bots=5`, or via `tools/bgrun.sh` /
  `tools/hrun.sh` (see `docs/ARCHITECTURE.md#10-debug-command-line-flags`).

## Where to start reading

`scripts/race/race.gd` `_ready()` and `scripts/ui/menu.gd` `_ready()`.
