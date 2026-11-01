# scripts/ui/

The main menu (over a live 3D showroom), settings, credits, single-player mode screens, the loading screen,
and both in-race HUD layers. Everything is built in code from `Control`s and custom `_draw()` calls; there
are no `.tscn` UI scenes.

## Files

### Menu

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `menu.gd` | (none; root of `scenes/menu.tscn`) | Main menu screens: home, quick race / host setup, join (LAN list or IP), lobby, settings. Screens fade into each other; the showroom car wears the chosen paint. Starts races (`change_scene_to_file("res://scenes/race.tscn")`). Debug autostart for network tests. | `_ready`, `_show_setup`, `_start_host`, `_join`, `_show_settings`; `--menu_screen`, `--nethost`, `--netjoin` |
| `menu_modes.gd` | `MenuModes` | Time Trial setup, Championship setup, standings hub between rounds, final podium; built with `menu.gd`'s layout helpers. | `show_time_trial()`, `show_championship()`, `show_champ_setup()`, `show_hub()`, `show_podium()` |
| `menu_credits.gd` | `MenuCredits` | Credits screen: who built the game, its license, then third-party credits read at run time from `assets/CREDITS_INGAME.txt` (`# ` lines = section headers, blank lines separate entries). | `show_credits()`, `parse(text)`; `--credits_file=<path>` |
| `menu_widgets.gd` | `MenuWidgets` | Custom-drawn, keyboard / gamepad focusable controls: nav items, option rows (`Choice`), track cards, list rows, buttons. Mouse hover moves focus, so only one thing is ever highlighted. | inner classes, `weather_icon()`, `button()` |
| `settings_panel.gd` | `SettingsPanel` (`VBoxContainer`) | Settings pages shared by the main menu and the pause menu: Display / Audio / Controls / Game tabs. Applies and saves on every change. Controls page rebinds KEY / ALT KEY / PAD per action. | `SettingsPanel.new(in_race, tab)`, `first_focus()` |
| `showroom.gd` | `Showroom` (`Node3D`) | Menu backdrop: the selected car on a turning platform in a dark studio (SSR floor, key / rim / softbox lights, haze, AgX). Display-only car from `CarModel`. | `set_car(id)`, `set_paint(color)`, `set_framing(...)` |
| `ui_theme.gd` | `UiTheme` | Shared look: dark glass, off-white type, one amber accent; fonts from `assets/fonts/`. | `get_theme()`, `font()`, `label()`, `caption()` |
| `ui_sounds.gd` | `UiSounds` | Synthesised soft switch clicks for menus (not wired up yet). | `UiSounds.wire(root)`, `UiSounds.play(from, name)` |

### Loading

| File | class_name | What it is | Main entry points |
|---|---|---|---|
| `loading_screen.gd` | `LoadingScreen` (`CanvasLayer`) | Shown by `race.gd` while the circuit builds: track name, blurb and outline (drawn in amber as it loads), conditions, a tip, and a faked progress bar: it glides towards 99 % on its own clock (frame time clamped, so build freezes never make it jump), waits there until the race is ready, then fills and fades. `--loadhitch` prints each frozen frame. | `LoadingScreen.new(def, cond, laps, title)`, `set_progress(f, label)`, `hold(...)`, `finish()` |

### HUD

| File | class_name | What it is |
|---|---|---|
| `hud.gd` | `Hud` (`CanvasLayer`) | Driver instruments: tacho, gear, speed, drift readout, the control-hint strip at the start. `hud.car = player car`. |
| `race_hud.gd` | `RaceHud` (`CanvasLayer`) | Race overlay: timing block, standings tower, minimap, start lights, lap / final lap / wrong-way banners, pause menu (with `SettingsPanel`) and the results screen. `race_hud.race = race`. `RaceHud.fmt_time()` is used elsewhere. `--hud_force=...` for screenshots. |
| `hud_style.gd` | `HudStyle` | Shared HUD palette, fonts and draw helpers; `make_root()` gives a full-window Control that scales the HUD from its authored `REF_SIZE`. |
| `hud_tacho.gd` | `HudTacho` | Analogue rev counter with gear, digital speed, shift lights, assist indicators; all in `_draw`. |
| `hud_drift.gd` | `HudDrift` | Slide angle and a running drift score. |
| `hud_info.gd` | `HudInfo` | Top-left timing: position, lap, current / last / best with delta. |
| `hud_tower.gd` | `HudTower` | Live standings rows that glide to new positions (debounced). |
| `hud_minimap.gd` | `HudMinimap` | Track outline from the centreline with a dot per car, rotated to its widest orientation. |
| `hud_lights.gd` | `HudLights` | Five red start lights, then "GO". |
| `hud_banner.gd` | `HudBanner` | Centre messages: lap card with delta, FINAL LAP / finish, wrong way. |
| `hud_results.gd` | `HudResults` | Results table, fastest lap marked, championship points column. |

## How it connects

- `menu.gd` reads and writes `Game` (autoload) and calls `Net` for hosting, joining and the lobby; it switches
  to `scenes/race.tscn`. `Game.menu_screen` and `Game.pending_message` tell it what to show on return.
- `race.gd` creates `LoadingScreen`, `Hud` and `RaceHud`. `RaceHud` reads `race.entries`, `race.state`,
  `race.race_time`, listens to `lights_changed`, `lap_completed`, `race_finished`, and asks the
  `RaceMode` (if any) for results buttons and points.
- The HUD layers sit above `CameraPost` (CanvasLayer -1), so they are never blurred or graded.

## Gotchas

- **Everything must work with keyboard and gamepad only.** Use `MenuWidgets` controls (focusable, focus
  follows mouse) rather than plain `Button`s, and set a sensible first focus.
- **Draw, don't rebuild.** HUD widgets draw in `_draw()` and `queue_redraw()`; they do not create nodes per
  frame.
- **Scale from `HudStyle.REF_SIZE`.** Lay HUD elements out at the reference size under `HudStyle.make_root()`
  so they scale with the window.
- **Settings save immediately** through `Game.save_settings()`, which is a no-op in debug runs (any user
  args). Do not add a separate "Apply" path.
- **While the pause menu listens for a key**, `SettingsPanel` sets a flag so the race's pause toggle ignores
  that press; keep it when changing input handling.
- Credits text shown in game comes from `assets/CREDITS_INGAME.txt`, which the export presets include
  (`export_presets.cfg` `include_filter`). Update it whenever a credited asset is added.
- Fonts are SIL OFL (`assets/fonts/OFL.txt`).

## Where to start reading

`menu.gd` `_ready` and one screen function (`_show_setup`), `settings_panel.gd`, then `race_hud.gd` `_ready`.
