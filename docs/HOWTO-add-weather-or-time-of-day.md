# How to add a weather condition or time of day

Weather and time of day are the same system in Slipstream: a **condition** is a weather *kind*
(sky, sun, fog, grip, precipitation) optionally combined with **night**. Everything lives in
`scripts/world/weather.gd`; changeable weather is a timeline in `scripts/world/weather_cycle.gd`.
There is no free-running day/night clock yet (see [ROADMAP.md](ROADMAP.md)); "golden hour" and
"dawn" are their own kinds with a low sun.

## How it fits together

- `enum Kind { CLEAR, STORM, SNOW, GOLDEN, DAWN, FOG }`: the base looks.
- **Conditions** (what the menu, `--weather=N`, track defs and the LAN lobby use) are indices into
  `Weather.NAMES`:

  | Index | Name | Kind | Night |
  |---|---|---|---|
  | 0 | Clear | CLEAR | no |
  | 1 | Storm | STORM | no |
  | 2 | Snow | SNOW | no |
  | 3 | Golden hour | GOLDEN | no |
  | 4 | Night | CLEAR | yes |
  | 5 | Night rain | STORM | yes |
  | 6 | Night snow | SNOW | yes |
  | 7 | Changeable | timeline | no |
  | 8 | Changeable night | timeline | yes |
  | 9 | Dawn | DAWN | no |
  | 10 | Fog | FOG | no |

  `cond_kind()`, `cond_night()`, `cond_changeable()` and `condition()` convert between the two.
  Note the enum value of `Kind.DAWN` (4) is not its condition index (9): always convert.
- `PRESETS[kind]` holds every value that changes with the weather: HDRI sky, sun direction
  (`sun_u` = position along the HDRI's horizontal axis so the light matches the photographed
  sun, `sun_elev` in degrees), sun energy/colour, sky energy, exposure, fog density/colour,
  **grip** (`road_grip`, `off_grip`), `wet`, `snow`, saturation, cloud layer, `mist`, `haze`.
- `NIGHT[kind]` is merged over the day preset for night variants (`preset_for(kind, true)` also
  sets `night = 1.0`). Grip, wetness and snow stay the day's.
- `Weather.create(circuit, condition, ...)` (called from `Circuit.build`) builds the sky, sun,
  environment, rain/snow particles, lightning and ambience, sets `Car.weather_road_grip` /
  `weather_off_grip`, and pushes the live state into the **global shader parameters** `wx_wet`,
  `wx_wet_line`, `wx_snow`, `wx_rain`, `wx_wind` (declared in `project.godot`, read through
  `shaders/weather.gdshaderinc`). Road, terrain, props and car shaders react to those, so nothing
  rebuilds when the weather changes.
- **Changeable** (7, 8): `WeatherCycle.make_timeline(seed, scenario)` returns a plain Dictionary
  `{name, seed, base, heavy, wet0, snow0, keys = [[t, gloom, rain, snowfall, wind], ...]}`. The
  live weather blends between the `base` and `heavy` presets by `gloom` and follows the race clock.
  The host sends the timeline to every client, so all machines see the same sky.

Other per-kind tables to keep in step:

| File | What |
|---|---|
| `scripts/camera/camera_post.gd` | `GRADES[kind]` colour grade, `NIGHT_GRADE` |
| `scripts/world/weather.gd` `_fixed_state()` | clouds / rain / snowfall / wind per kind (wind is an array indexed by kind) |
| `scripts/world/ambience.gd` | `cond_for(preset)` picks the ambience bed (clear / storm / snow) |
| `scripts/world/atmosphere.gd` | dust motes, mist banks, which kinds they appear in |
| `scripts/ui/menu_widgets.gd` `weather_icon()` | the menu glyph per condition |
| `scripts/ui/loading_screen.gd` | the condition note on the loading screen |
| `scripts/modes/championship.gd` | per-round weather |

## A. Add a new weather kind (example: light rain "Drizzle")

1. **Enum and names** (`weather.gd`): append to `Kind` and give it a condition index **at the end
   of** `NAMES` (never renumber existing conditions: track defs, saved settings, championship
   rounds and the network lobby store the index). Bump `CONDITIONS`, add a constant like
   `const DRIZZLE := 11` and handle it in `cond_kind()` and `condition()` the way `DAWN` and `FOG`
   are handled.

   ```gdscript
   enum Kind { CLEAR, STORM, SNOW, GOLDEN, DAWN, FOG, DRIZZLE }
   const NAMES := [..., "Dawn", "Fog", "Drizzle"]
   const CONDITIONS := 12
   const DRIZZLE := 11
   ```
2. **Preset**: add `PRESETS[Kind.DRIZZLE]`. Start by copying the closest one (STORM for rain) and
   change values; every key used by the others must be present. Use a CC0 HDRI (Poly Haven
   "puresky" HDRIs work well) and credit it. Set grip honestly: wet tarmac around 0.85-0.9.
   Optionally add a `NIGHT[Kind.DRIZZLE]` entry for a night variant.
3. **Live state**: extend the `wind` array in `_fixed_state()` and decide `clouds`/`rain` for the
   new kind (rain 0.3 for drizzle). Rain particles and audio already scale with `rain`.
4. **Grade, ambience, atmosphere, icon, loading note**: add entries to the tables above.
5. **Menu**: nothing to do; the weather choice lists `Weather.NAMES`.
6. **Track default** (optional): `weather = Weather.DRIZZLE` in a track def is a condition index.

## B. Add a new time of day for an existing kind (example: "Dusk")

Two ways, depending on how different it looks:

- **A new kind** (like `GOLDEN` and `DAWN`): copy the GOLDEN preset, pick an HDRI shot at that
  time of day, set `sun_u` so the sun light comes from the sun in the photograph (find it in the
  HDRI, `u` = x / width), `sun_elev` a few degrees, warm/cool `sun_color`, `sky_tint_low` /
  `sky_tint_high` if needed, then follow steps 1-5 of section A.
- **A night-style overlay**: like `NIGHT`, a second table merged over the day preset with a flag
  in the preset (`night = 1.0`); lamps, headlights and night lighting key off `Weather.night` and
  `Car.night` (set in `Circuit.build`). Street lamps are built by `scripts/track/night_lights.gd`
  for night and changeable conditions; per-track night tweaks belong in the dress file (see
  `_night_city()` in `dress_hafenstadt.gd`).

The original author likes golden hour, rain and heavy snow: those looks are references for quality.

## C. Add a changeable-weather scenario

In `weather_cycle.gd`, append a name to `SCENARIOS` and `SCENARIO_NAMES` and add a branch in
`make_timeline()`:

```gdscript
		"evening_drizzle": # golden start, clouds roll in, light rain, stays damp
			b = Weather.Kind.GOLDEN
			h = Weather.Kind.STORM
			k.append([0.0, 0.05, 0.0, 0.0, 0.2])
			t = rng.randf_range(30.0, 60.0); k.append([t, 0.4, 0.0, 0.0, 0.35])
			t += rng.randf_range(40.0, 70.0); k.append([t, 0.7, 0.25, 0.0, 0.5]) # drizzle
			t += rng.randf_range(60.0, 90.0); k.append([t, 0.65, 0.2, 0.0, 0.45])
```

Each key is `[time s, gloom 0..1, rain 0..1, snowfall 0..1, wind 0..1]`. Use only the seeded
`rng` (never `randf()`), so the same seed gives the same timeline on every machine. Only plain
types in the Dictionary: it is sent over the network.

## Checks

```sh
# parse
LIMIT=60 tools/hrun.sh res://scenes/race.tscn --quit-after 60 -- --bots=0 --weather=11 2>&1 | grep -E "SCRIPT ERROR|Parse"
# screenshots on several tracks (chase cam, and a TV shot without HUD)
tools/bgrun.sh res://scenes/race.tscn -- --track=herbstwald --weather=11 --bots=7 --screenshot=/tmp/wx_herbst.png --shot_at=14
tools/bgrun.sh res://scenes/race.tscn -- --track=hafenstadt --weather=11 --allbots --cam=tv --nohud --screenshot=/tmp/wx_hafen.png --shot_at=30
# changeable: force the scenario, fast-forward the clock, log the phases
tools/bgrun.sh res://scenes/race.tscn -- --track=kiefernring --weather=7 --weather_script=evening_drizzle \
  --weather_seed=3 --weather_speed=10 --weather_log --bots=3 --screenshot=/tmp/wx_cycle.png --shot_at=30
# grip: bots must still finish without lots of crashes in the new conditions
LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --weather=11 --track=valle_club
# fps (rain, fog and night lights cost GPU time)
TRACKS="kiefernring hafenstadt" tools/perfcheck.sh --weather=11
```

`--weather_at=<s>` starts a changeable race later in its timeline; `--weather_keep_shadows` and
`--perf=noprecip,nofog,...` help isolate costs. Check every track's look in the new condition,
especially night brightness on street circuits and fog on tracks with long sight lines.
