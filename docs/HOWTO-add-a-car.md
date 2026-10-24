# How to add a car

Cars are glTF models plus a catalog entry. There is no per-car scene: `CarModel`
(`scripts/car/car_model.gd`) reads the model, finds wheels, paint and lamps by **material name**,
scales it to the real car's length, and `Car` (`scripts/car/car.gd`) applies the physics preset
from the catalog. The cockpit view has its own per-car spec in `scripts/car/cockpit.gd`.

## Step 1: find a model you may ship

- Licence must allow redistribution and commercial use: CC0, CC BY or CC BY-SA (see
  [CONTRIBUTING.md](../CONTRIBUTING.md#7-asset-licensing)). No NC, no ND, no "editorial use".
  Check the licence on the source page and in the file's own metadata (`asset.extras` in the glTF,
  or a bundled `license.txt`).
- Classic road car of the 70s/80s fits the game best. Realistic, not stylised.
- Interior: a modelled dashboard and seats make the cockpit view much better, but a car without
  one works (`dash = true` builds a procedural dashboard).
- **No logos.** Real make/model names are fine; manufacturer badges and logos must be removed
  (delete the badge material via `skip`, or paint over it in the texture).
- Budget: aim for under ~150k triangles. Simplify with glTF-Transform or Blender if needed.

## Step 2: prepare the file

1. Convert to plain `.glb` that Godot can import: decode Draco/meshopt compression and
   quantization, convert WebP textures to PNG (glTF-Transform: `gltf-transform copy`,
   `gltf-transform webp`/`png`, `gltf-transform dedup`).
2. Put it at `assets/cars/<id>.glb` (textures next to it as Godot extracts them). Raw downloads go
   in `assets/cars/src/` (git-ignored, has a `.gdignore`).
3. Open the project once (`godot --headless --path . --import`) so the model is imported.
4. List the material names: open the `.glb` in the Godot editor (Advanced Import Settings), or run
   `tests/car_preview.tscn` after step 3, which prints surfaces per car.

## Step 3: the catalog entry

Add an entry to `CARS` in `scripts/car/car_catalog.gd`. The header of that file documents every
key. Minimal example:

```gdscript
	"lancia_037": {
		name = "Lancia 037 Stradale", year = 1982,
		path = "res://assets/cars/lancia_037.glb",
		credit = "\"Lancia 037\" by Some Author (example.com/author), CC BY 4.0",
		length = 3.915,                     # real overall length in metres; the model is scaled to it
		forward = Vector3(0, 0, 1),         # axis the SOURCE model's nose points along
		skip = ["Ground_Shadow", "Badge"],  # materials to drop: ground planes, contact shadows, logos
		wheel_mats = ["Rim", "Tyre", "Brake_Disc"],  # everything that spins with the wheels
		rim_mat = "Rim",                    # round part used to find each hub centre
		tire_mat = "Tyre",                  # radius (top of tyre) and width
		paint_mats = ["Body_Paint"],        # merged into one recolourable "paint" surface
		lights_mat = "Headlight_Glass",     # headlamps (front half), lit by car_lights.gd
		brake_mats = ["Tail_Light"],        # rear half becomes the "brake" surface
		paint_color = Color(0.55, 0.02, 0.02),
		physics = {
			drivetrain = "RWD", car_mass = 1170.0, com_offset = Vector3(0.0, -0.25, 0.15),
			idle_rpm = 950.0, redline_rpm = 7500.0,
			gear_ratios = PackedFloat32Array([2.86, 1.94, 1.43, 1.12, 0.89]), final_drive = 3.6,
			torque_rpm = [1000.0, 2000.0, 3000.0, 4000.0, 5000.0, 6000.0, 7500.0],
			torque_nm = [250.0, 300.0, 340.0, 370.0, 380.0, 360.0, 300.0],
			drag_coef = 0.36, downforce_coef = 0.3, brake_force = 22000.0, tire_grip = 1.45,
			top_speed_kmh = 220,
		},
		engine = { type = "i4_037", cylinders = 4, ... },   # optional, see below
	},
```

Notes:

- `physics` keys are named exactly like `Car` properties; `Car._apply_preset()` sets each one
  that exists (`top_speed_kmh` is informational). Torque figures in the catalog are real-world
  values **x1.3** for arcade punch, the same as the other cars; keep that convention so cars stay
  balanced against each other.
- Compare your numbers with the closest existing car (power-to-weight, grip, brakes). The handling
  target is arcade-leaning with strong, stable brakes.
- `engine` (optional) overrides `CarAudio.ENGINE_DEFAULTS` (documented in
  `scripts/car/car_audio.gd`): cylinders, firing irregularity, exhaust resonances, harmonics,
  turbo, blow-off, backfire. Cars sharing an engine `type` share one synthesised sound bank, so
  give a new engine its own `type` name. Start from the car with the most similar engine
  (flat-six `porsche930`, inline-four `bmw_e30_m3`, rotary `mazda_rx7_fc`, V8 `ferrari_f40`).
- `CarCatalog.available_ids()` only lists cars whose `.glb` exists, so a missing model never
  breaks the menu. The menu, showroom, bots' grid and the LAN lobby pick the new car up
  automatically.

## Step 4: cockpit spec

Add an entry to `SPECS` in `scripts/car/cockpit.gd` (keys documented above the table). Without it
the default car's spec is used, which puts the eye and steering wheel in the wrong place. Copy
the entry of the most similar existing car and adjust it:

```gdscript
	"lancia_037": {
		eye = Vector3(-0.3, 0.5, 0.15),     # driver's eye, car-local (-Z forward, +X right; RHD cars use +X)
		wheel = Vector3(-0.3, 0.22, -0.25), wheel_r = 0.18, wheel_tilt = 22.0,
		spokes = 3, wheel_style = "sport",  # "porsche", "sport", "wood"
		cut = [0.24, 0.08],                 # [radius, half-depth] of model triangles removed round the hub (the static wheel)
		dash = true, seats = true, binnacle_w = 0.44,
		# gauges in the instrument binnacle: [kind, x offset, y offset, radius]
		cluster = [["speed", -0.09, 0.0, 0.055], ["tach", 0.09, 0.0, 0.058]],
		needle = Color(1.0, 0.45, 0.12),
		glass = "Windscreen",               # windscreen material: rain plane and wipers fit to it
	},
```

Iterate with the cockpit preview (top cut-away + eye view), one background run per change:

```sh
tools/bgrun.sh res://tests/cockpit_preview.tscn -- car=lancia_037 views=top,eye out=/tmp/cockpit
```

`--showcut` (in a race) draws the removed model triangles in magenta.

## Step 5: credits

Add the model to `assets/cars/CREDITS_cars.txt` (title, author, source URL, licence URL, where you
obtained it, changes made), to the root `CREDITS.md`, and to `assets/CREDITS_INGAME.txt`. Fill the
`credit` field in the catalog as well. CC BY-SA models: note that the modified model stays under
CC BY-SA.

## Step 6: checks

```sh
# parse + one race start with the new car
LIMIT=90 tools/hrun.sh res://scenes/race.tscn --quit-after 120 -- --bots=0 --car=lancia_037 2>&1 | grep -E "SCRIPT ERROR|Parse|ERROR"
# wheel centring, surfaces, screenshots (windowed, background)
tools/bgrun.sh res://tests/car_preview.tscn -- car=lancia_037 out=/tmp/carprev
# handling numbers on the flat pad (compare with the other cars)
tools/hrun.sh res://tests/handling_test.tscn -- --car=lancia_037
# engine synthesis: timing, clipping, firing frequency
tools/hrun.sh res://tests/engine_audio_test.tscn -- --dump=/tmp/engines
# dirt and wet looks on the body
tools/bgrun.sh res://tests/dirt_preview.tscn -- car=lancia_037 kind=mud amount=1 views=rear,side out=/tmp/dirt
# on track: chase cam and cockpit
tools/bgrun.sh res://scenes/race.tscn -- --track=kiefernring --car=lancia_037 --bots=3 --screenshot=/tmp/037_chase.png --shot_at=12
tools/bgrun.sh res://scenes/race.tscn -- --track=kiefernring --car=lancia_037 --cam=cockpit --bots=0 --screenshot=/tmp/037_cockpit.png --shot_at=12
# bots in the new car finish a race
LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --car=lancia_037 --track=valle_club
# 8 cars on track still hold 60 fps (the grid mixes models)
TRACKS="kiefernring" tools/perfcheck.sh
```

What to look for: wheels spinning without wobble and sitting in the arches, paint recolouring
cleanly (no logo or decal left in the paint surface), brake lights lighting the right lamps, no
floating or sunken body, sensible top speed and braking distance in `handling_test`.
