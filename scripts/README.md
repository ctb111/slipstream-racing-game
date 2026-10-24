# scripts/

All game code. GDScript only, no C#, no GDExtension. The two scenes in `scenes/` are just a root node with a
script; everything else is built from here at run time. For the big picture read
[`docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) first.

## Folders

| Folder | What lives there | Start with |
|---|---|---|
| [`autoload/`](autoload/README.md) | The two singletons: `Game` (settings, session) and `Net` (LAN multiplayer). | `game.gd` |
| [`race/`](race/README.md) | The race manager, AI driver, racing line, adaptive resolution, asset preloading. | `race.gd` |
| [`track/`](track/README.md) | Track catalogue and everything that turns a list of points into a circuit: road, props, themes, night lights. | `track_defs.gd`, `circuit.gd` |
| [`track/gimmicks/`](track/gimmicks/README.md) | The Gx kit: placement helpers, set pieces (bridges, warehouses, fans, graffiti ...) and per-track dressing. | `gx.gd`, `dress_kiefernring.gd` |
| [`world/`](world/README.md) | Weather, sky, terrain, forest, grass, crowds, wildlife, ambient sound, PBR material library. | `weather.gd`, `terrain.gd`, `world_builder.gd` |
| [`car/`](car/README.md) | Vehicle physics, model loading, catalogue, cockpit, lights, effects, dirt, audio. | `car.gd`, `car_catalog.gd` |
| [`camera/`](camera/README.md) | In-race camera modes, camera shake, cockpit head, TV director, lens post-process. | `chase_camera.gd` |
| [`ui/`](ui/README.md) | Main menu, showroom, settings, credits, loading screen, both HUD layers. | `menu.gd`, `race_hud.gd` |
| [`modes/`](modes/README.md) | Single-player game modes layered on top of a race: championship, time trial (+ ghost). | `race_mode.gd` |

## Files at this level

| File | class_name | What it is |
|---|---|---|
| `input_setup.gd` | `InputSetup` | Registers every input action in code (two keyboard slots + one gamepad slot each) and applies the player's rebinds from `Game.bindings`. Entry: `InputSetup.ensure_actions()` (called by `Game._ready` and `race.gd`). Also used by the controls page (`rebind`, `reset_defaults`, `key_name`, `pad_name`). |

## Conventions

- **Build in code, not in the editor.** Nodes are created with `.new()` and `add_child()`. Large builders are
  `RefCounted` classes with a `static func build(...)` entry point.
- **One `class_name` per file** for anything referenced elsewhere. Files that are only ever `load()`ed by
  path (per-track dressing, optional builders, `theme_mediterranean.gd`) have no `class_name`.
- **Optional features are loaded by path** with `ResourceLoader.exists()` first (see `Circuit.EXTRA_BUILDERS`,
  `gimmicks.gd`), so deleting a feature file never breaks a track.
- **Comments explain why.** Most files start with a `##` header describing purpose, usage and debug flags.
  Read it before editing; keep it current when you change behaviour.
- **Debug flags** are read with `OS.get_cmdline_user_args()`; list of all of them in
  `docs/ARCHITECTURE.md#10-debug-command-line-flags`. Add new ones to that list.

## Gotchas (apply to every folder)

- **Typed inference fails on untyped values.** `var v := arr[i]`, `var d := dict.get("k")`,
  `var x := node.get("prop")` do not compile when the right side is a Variant. Write the type:
  `var v: Vector3 = arr[i]`.
- **New `class_name` files** need Godot's global class cache refreshed (an editor import, or
  `godot --headless --import`). `tools/bgrun.sh` and `tools/hrun.sh` do this automatically when a script is
  newer than the cache.
- **A parse error in any script breaks every run**, because the race scene preloads most classes. Run a
  quick headless check after editing (see `CONTRIBUTING.md` / `tools/README.md`).
- **Performance is a feature.** 60 fps on Medium with 8 cars on a fanless M1 is the gate. Merge geometry,
  MultiMesh repeats, no shadows on small things, few real lights. Never fix frame rate by shortening view
  ranges or deleting scenery. See `docs/ARCHITECTURE.md#8-rendering-and-performance`.
- **Determinism for multiplayer.** Anything placed in the world must come from seeded RNGs (track id based),
  never `randomize()`, or online players will see different worlds.

## Where to start reading

1. `autoload/game.gd` (what a session is), 2. `race/race.gd` (`_ready` is the whole startup sequence),
3. `track/circuit.gd` (`build()` is the whole world pipeline), 4. `car/car.gd` (`_physics_process`).
