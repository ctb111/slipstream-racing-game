# How to capture screenshots and video

All capture is driven by command-line arguments, so it can be scripted and run in the background
with `tools/bgrun.sh` (silent, never steals focus). Rendering needs a window: screenshots and
video do not work with `--headless`. On Linux/Windows run `godot --path . <same args>` instead of
`bgrun.sh`.

Remember the argument split: Godot's own options go **before** `--`, game options **after** it.

```sh
tools/bgrun.sh res://scenes/race.tscn [godot options] -- [game options]
```

## Screenshots

### Race frames

`--screenshot=<file.png>` saves one frame after `--shot_at` seconds (default 3; the clock starts
when the race scene is ready, the countdown takes a few seconds), prints frame statistics
(average fps, 1%-low, worst frame, draw calls) and quits.

```sh
# chase cam, 12 s in, field of 8 with the player driven by the AI
tools/bgrun.sh res://scenes/race.tscn -- --track=alpenpass --weather=3 --allbots --bots=7 \
  --screenshot=/tmp/alpenpass_golden.png --shot_at=12
```

Framing options:

| Option | Effect |
|---|---|
| `--cam=chase\|cockpit\|far\|bumper\|bonnet\|roof\|tv` | camera mode (`ChaseCamera.MODE_NAMES`); `tv` = trackside TV cameras that pan with the car and cut (`tv_director.gd`) |
| `--shotcam=x,y,z` | camera at a car-local offset (x right, y up, -z forward), looking at the car, fov 40. `--shotcam=3.5,1.2,-5` is a front three-quarter beauty shot |
| `--worldcam=x,y,z,lx,ly,lz` | fixed world camera at x,y,z looking at lx,ly,lz, fov 50 (overviews, set pieces) |
| `--cam_look=sun` or `--cam_look=x,y,z` | look past the sun / along a direction from above the car (glare checks) |
| `--nohud` | hide both HUD layers: clean frames |
| `--car=<id>` | the player's car |
| `--weather=N` | condition (0 Clear .. 10 Fog, see `Weather.NAMES`) |
| `--quality=0..3`, `--nodynres` | render quality, keep full resolution (recommended for stills) |
| `--spawn=<m>` | start the player `m` metres round the racing line instead of on the grid |
| `--bots=N`, `--allbots` | field size; `--allbots` lets the AI drive the player car |

The window size comes from `project.godot` (1600x900). For larger stills pass a Godot window
option before `--`, for example `--resolution 2560x1440`.

### Many shots from one run

One windowed run that saves many images is much cheaper than many runs:

- **Driver-height and roadside views round a lap** (tracks whose dress file calls
  `DressShots.attach`):
  ```sh
  tools/bgrun.sh res://scenes/race.tscn -- --track=hafenstadt --bots=0 --dress_shots=/tmp/hafen \
    --dress_at=120,640,1300,2100 --dress_side=300,-900 --dress_cam="0,40,300,0,0,0;-400,30,-100,-260,0,0"
  ```
  `--dress_at` = 1.3 m above the road `along` m round the lap looking 70 m ahead;
  `--dress_side` = close-ups of the right (+) / left (-) roadside; `--dress_cam` = free views
  `x,y,z,lookx,looky,lookz` separated by `;`; `--dress_t0` = seconds before the first shot.
- **Gimmick pieces** on any track, four views each:
  `--gx_test=overpass:road,warehouse --gx_shots=/tmp/gx` (see `gx_test.gd`).
- **Car effects** (launch smoke, hard acceleration, off-track dirt): `--fxshots=<prefix>`
  (`car_fx.gd`).
- **Drive-ahead sequence** for pop-in and flicker hunts:
  `--pop-shots=<prefix>,<start s>[,<step s>,<count>,<burst>,<scale>]` (12 captures 0.5 s apart by
  default; a burst of consecutive frames per capture shows flicker), analysed with
  `tools/frame_diff.gd`.
- **Cars, cockpits, dirt** on a neutral stage: `tests/car_preview.tscn`,
  `tests/cockpit_preview.tscn`, `tests/dirt_preview.tscn` (see [tests/README.md](../tests/README.md)).

### Menus and loading screen

- `--uishot=<file.png> [--uishot_at=<s>]` captures whatever scene is showing (default after 1.5 s).
- `--menu_screen=setup|host|join|settings|credits|lobby|timetrial|championship|champ_setup` opens
  a menu screen directly; `--settings_tab=N` picks a settings tab.
- `--hold_loading[=<s>]` keeps the race loading screen up for a shot.

```sh
tools/bgrun.sh "" -- --menu_screen=credits --uishot=/tmp/menu_credits.png
tools/bgrun.sh res://scenes/race.tscn -- --track=herbstwald --hold_loading --uishot=/tmp/loading.png --uishot_at=4
```

## Video

Godot's Movie Maker mode renders every frame at a fixed rate, independent of how fast the machine
is, and writes an AVI (MJPEG + PCM audio) or a PNG sequence:

```sh
LIMIT=1800 tools/bgrun.sh res://scenes/race.tscn \
  --write-movie /tmp/slipstream_alpenpass.avi --fixed-fps 60 --quit-after 5400 \
  -- --track=alpenpass --weather=3 --cam=tv --nohud --allbots --bots=7 --nodynres --quality=2
```

- `--write-movie <path>`: use an **absolute path** (the background launcher's working directory is
  not the project). `.avi` gives MJPEG video with audio; `.png` gives numbered frames plus a WAV.
- `--fixed-fps 60`: 60 frames per second of game time, rendered as slowly as needed.
- `--quit-after N`: stop after N frames (60 fps x 90 s = 5400). Loading frames are recorded too;
  trim them afterwards.
- `LIMIT=`: the wrapper's watchdog (default 300 s of wall time). Movie rendering is slower than
  real time, so raise it.
- Audio: the game normally mutes itself in runs with game arguments; with `--write-movie` it keeps
  the mix and records it into the file.
- `--allbots` makes the player car drive itself; `--cam=tv` gives broadcast-style trackside
  cameras, `--cam=chase` / `cockpit` / `bumper` onboard shots. Changeable weather:
  `--weather=7 --weather_script=clear_to_storm --weather_seed=4 --weather_speed=6` compresses a
  weather change into a short clip.

Convert and trim with ffmpeg:

```sh
# skip the first 8 s (loading + countdown), H.264 for sharing
ffmpeg -ss 8 -i /tmp/slipstream_alpenpass.avi -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p \
  -c:a aac -b:a 192k /tmp/slipstream_alpenpass.mp4
# a short GIF-like loop for the README
ffmpeg -ss 20 -t 6 -i /tmp/slipstream_alpenpass.avi -vf "fps=30,scale=960:-2" -c:v libx264 -crf 22 \
  -pix_fmt yuv420p -an /tmp/clip.mp4
```

## Tips for good-looking media

- Golden hour (`--weather=3`), dawn (9), storm (1) and heavy snow (2) show the game at its best;
  night (4) on Hafenstadt for neon and street lamps.
- Use `--quality=2` or `3` and `--nodynres` for stills and video; the performance target applies
  to gameplay, not to capture.
- Avoid the first seconds after load (shader warm-up) and lap 1 turn 1 (bots bunch up).
- Media in the repository (README screenshots) must show only content we may redistribute; do not
  include real logos.
