# scripts/autoload/

The two singletons registered in `project.godot` (`[autoload]`). They exist before any scene and survive
scene changes, so they carry everything the menu hands to the race and the network state.

| File | Autoload name | What it is | Main entry points |
|---|---|---|---|
| `game.gd` | `Game` | Session and player settings. Loads `user://settings.cfg` in `_ready`, picks a first-run quality (Medium on Apple GPUs, else High), applies volumes / window, registers input actions. Holds the current race setup (`mode`, `session`, `track_id`, `laps`, `bots`, `difficulty`, `grid`, `weather_override`, `weather_timeline`, `car_id`, `paint_index`) and the per-quality render helpers. | `save_settings()`, `apply_viewport_quality(vp)`, `render_scale_now()`, `scaling_mode(s)`, `grass_density()`, `bot_skill(rng)`, `apply_volumes()`, `apply_window()`, `speed_units()`, `distance_text()`; constants `QUALITY_NAMES`, `BOT_NAMES`, `RENDER_SCALES`, `BUSES` |
| `net.gd` | `Net` | LAN multiplayer: ENet server/client on UDP 27015, a JSON UDP beacon broadcast every second on 27016 for discovery, the lobby (players, host's race settings), and the RPCs that start a race and return to the lobby. | `host()`, `join(ip)`, `leave()`, `start_scan()` / `stop_scan()`, `set_lobby(dict)`, `start_race()`, `back_to_lobby()`, `update_paint()`, `update_car()`; signals `servers_changed`, `lobby_changed`, `disconnected(reason)` |

## How it connects

- `ui/menu.gd` writes `Game.*` from the menu screens, calls `Net` for host / join / lobby, and switches to
  `scenes/race.tscn`.
- `race/race.gd` reads `Game.*` in `_ready`, may temporarily override some via a `RaceMode`, and calls
  `Game.apply_viewport_quality()`.
- `Net._begin_race` (RPC, `call_local`) copies the host's lobby into `Game` on every machine and changes
  scene, so a client's race setup always comes from the host.
- Many builders read `Game.quality` directly to scale their cost (see the quality table in
  `docs/ARCHITECTURE.md`).
- `ui/settings_panel.gd` edits `Game` settings and calls `Game.save_settings()` on every change.

## Gotchas

- **Debug runs never save.** If `OS.get_cmdline_user_args()` is non-empty, `save_settings()` returns early,
  audio is muted (unless `--write-movie`), and the window is left alone. Do not "fix" this; it protects the
  player's settings from test runs.
- **Weather values are conditions, not kinds.** `Game.weather_override` is a `Weather` condition 0-10 (or -1 =
  track default). Use `Weather.cond_kind()` / `cond_night()` / `cond_changeable()`.
- **`Game.grid`** is `[{peer, name, bot, paint?, car?}]`, index = grid slot. Empty or single-player: `race.gd`
  builds its own grid.
- **RPC paths.** `Net`'s RPCs are on `/root/Net` on every peer. The protocol string `slipstream-1` must be
  bumped when the RPC signatures or the meaning of lobby fields change, or old clients will misbehave.
- Settings keys live in two places (`_ready` and `save_settings`). Add a new setting to both.

## Where to start reading

`game.gd` top to bottom (it is short), then `net.gd` from `host()` to `_begin_race()`.
