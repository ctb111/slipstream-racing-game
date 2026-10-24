# How to add a gimmick (Gx piece) and dress a track

"Gimmicks" are the set pieces that make a lap memorable: bridges and flyovers, a warehouse the
road drives through, sign gantries, graffiti walls, fan banks with flares, a TV helicopter, wind
turbines, billboards. They live in `scripts/track/gimmicks/` and share one small kit, **Gx**.

- **Pieces**: `gx_<piece>.gd`, `class_name Gx<Piece>`, one static entry point
  `static func place(c: Node3D, xf: Transform3D, opts := {}) -> void`. A piece knows how to build
  itself at a transform; it does not decide where it goes.
- **Dress files**: `dress_<track_id>.gd` with `static func dress(c: Node3D) -> void`. They decide
  what goes where on one track. `gimmicks.gd` (an EXTRA_BUILDER of `Circuit`) calls the dress
  file, then `fill_landscape.gd` (fields, barns, tree lines 20-300 m out), then `GxFans.flush()`
  (builds every crowd placed so far as one merged batch).
- `c` is always the `Circuit` node. The forest is built **after** dressing and keeps out of every
  circle reserved with `Gx.reserve()`.

## Coordinate frames

From `scripts/track/gimmicks/gx.gd`:

- `Gx.frame(c, along, side, lateral)`: a frame beside the road, `lateral` metres beyond the road
  **edge** on `Gx.LEFT` or `Gx.RIGHT`, standing on the terrain. **+z points away from the road**,
  y is up, x runs along the track. Build your piece around its origin with its front facing **-z**
  and it faces the road on both sides. The basis is never mirrored (on the left side +x runs
  against the driving direction; `Gx.frame_x(c, xf)` gives the driving direction).
- `Gx.road_frame(c, along)`: centred on the road surface, x along the track, z to the right. For
  things that span the road (arches, bridges, gantries, buildings the road goes through).
- `along` is metres round the lap from the start line. `Gx.length(c)` is the lap length.

Helpers: `Gx.corners(c, min_strength)` (sharpest first, `turn` +1 right / -1 left, so
`-turn` is the outside), `Gx.straights(c, min_len)`, `Gx.clear_of_road(c, p, margin)`,
`Gx.ground(c, p)`, `Gx.rng(c, purpose)`, `GxSpot.find(...)` (first flat, free footprint),
`GxSpot.near_start(c)`, `GxSpot.on_straights(c)`.

## Step 1: write the piece

Use `GxGeo` (`gx_geo.gd`) to build merged geometry: it collects triangles per material, then
`commit()` creates one `MeshInstance3D` per material (with a correct, fading visibility range via
`Gx.add_mesh`) plus one `StaticBody3D` of box colliders. Materials are photo PBR types from
`Mats` (`"concrete"`, `"stone"`, `"brick"`, `"steel"`, `"painted_metal"`, `"rusty_metal"`,
`"plaster"`, ...), `"props"` (printed sign atlas) or `"glass"`. The vertex colour (`g.col`)
multiplies the material; use it for grime and AO, not as the main colour.

Minimal example, `scripts/track/gimmicks/gx_footbridge.gd`:

```gdscript
class_name GxFootbridge
extends RefCounted
## Steel lattice footbridge over the road on concrete piers.
##   GxFootbridge.place(c, Gx.road_frame(c, 820.0), {height = 6.5})
## opts:
##   height   underside clearance over the road (default 6.0, never below 5.5)
##   width    deck width (default 3.0)

static func place(c: Node3D, xf: Transform3D, opts := {}) -> void:
	var h: float = maxf(float(opts.get("height", 6.0)), 5.5) # rule: >= 5.5 m clear over the road
	var w: float = float(opts.get("width", 3.0))
	var span := Gx.half_width() * 2.0 + 8.0 # piers 4 m beyond each road edge (>= 1.5 m required)
	var g := GxGeo.new(xf)
	g.col = Color(0.85, 0.84, 0.8)
	for s in [-1.0, 1.0]: # piers, z is across the road in a road_frame
		var pz: float = s * span * 0.5
		g.box("concrete", Vector3(0, h * 0.5, pz), Vector3(w, h, 1.2), 0.05)
		g.collide(Vector3(0, h * 0.5, pz), Vector3(w, h, 1.2))
	g.col = Color(0.55, 0.57, 0.6)
	g.box("painted_metal", Vector3(0, h + 0.3, 0), Vector3(w, 0.6, span + 1.2), 0.03) # deck
	g.tube("steel", [Vector3(-w * 0.5, h + 1.6, -span * 0.5), Vector3(-w * 0.5, h + 1.6, span * 0.5)], 0.04)
	g.tube("steel", [Vector3(w * 0.5, h + 1.6, -span * 0.5), Vector3(w * 0.5, h + 1.6, span * 0.5)], 0.04)
	g.commit(c, "GxFootbridge", 900.0)
	Gx.reserve(c, xf.origin, span * 0.6) # no trees growing through it
```

Rules:

- **Over the road: at least 5.5 m clearance.** Nothing solid inside the road footprint + 1.5 m.
  Check positions with `Gx.clear_of_road(c, p, 1.5)`.
- Solid parts a car can reach get collision (`g.collide(...)`, simple boxes).
- Real proportions, bevels (`box(..., bevel)`), trims, profiles (`extrude`), photo materials, grime.
  Never plain untextured boxes. Prefer real models where they exist: `GxProps.scatter(c, id, xfs)`
  places Poly Haven CC0 models from `assets/industrial/` as one MultiMesh.
- Text and images come from real atlases (`assets/trackside/trackside_signs.png`,
  `assets/gimmicks/*.png`, built by the `tools/make_*.py` scripts), never drawn in a shader.
  Invented brand names only.
- Randomness from `Gx.rng(c, "<piece>")` so every machine builds the same thing.
- Visibility: big landmark shapes always drawn (`vis_end = 0`) or far ranges; small details may
  fade (`Gx.add_mesh` sets `FADE_SELF` and extends the range by the AABB half-diagonal). Nothing
  large may pop in ahead of the driver.
- Document the call and every `opts` key in the `##` header, like the existing pieces.

Register the piece for the test harness: add `footbridge = "res://scripts/track/gimmicks/gx_footbridge.gd"`
to `GxTest.PIECES` in `gx_test.gd`.

## Step 2: try it on any track

`gx_test.gd` places pieces on the longest straights of any track and photographs each from four
views (far, driver, side, close), then quits:

```sh
tools/bgrun.sh res://scenes/race.tscn -- --track=kiefernring --bots=0 \
  --gx_test=footbridge,overpass:road --gx_shots=/tmp/gx
```

Spec syntax: `<piece>[:<kind>][:key=value...]`, comma-separated; `kind` arrives as `opts.kind`,
each `key=value` as `opts[key]` (strings). `--gx_at=300,900` sets the
positions; `at=dip` (as an option) puts a piece at the deepest dip under the road (for bridges).
It also prints build time, draw calls and triangles per piece.

## Step 3: place it in a track's dress file

`scripts/track/gimmicks/dress_<track_id>.gd` is loaded automatically if it exists. Template
(`dress_example.gd.txt`):

```gdscript
extends RefCounted
## Seewald dressing: the footbridge over the lake straight, fans on the hairpins.

const P := "res://scripts/track/gimmicks/%s.gd"


static func _put(c: Node3D, piece: String, xf: Transform3D, opts := {}) -> void:
	if ResourceLoader.exists(P % piece): # a missing piece never breaks the track
		load(P % piece).place(c, xf, opts)


static func dress(c: Node3D) -> void:
	if ResourceLoader.exists(P % "dress_shots"):
		load(P % "dress_shots").attach(c) # enables --dress_shots screenshots
	var rng := Gx.rng(c, "dress")
	_put(c, "gx_footbridge", Gx.road_frame(c, 820.0), {height = 6.5})
	for corner in Gx.corners(c, 0.55).slice(0, 3): # fans on the outside of the 3 sharpest corners
		var side := -float(corner.turn)
		_put(c, "gx_fans", Gx.frame(c, corner.along, side, 9.0), {count = 24 + rng.randi_range(0, 8), flares = 1})
	var xf = GxSpot.find(c, GxSpot.near_start(c), [8.0, 14.0], 16.0, 0.0, 18.0, 2.5)
	if xf != null: # hospitality tents near the start, where there is room
		_put(c, "gx_hospitality", xf)
```

Good examples to copy from:

- `dress_alpenpass.gd`: fan banks on every hairpin with spacing logic, photographers at apexes,
  chevrons, a chairlift crossing the road, beer garden, camps, helicopter.
- `dress_hafenstadt.gd`: placement by world coordinates (`_at(c, x, z)` converts a world XZ to an
  `along`), drive-through warehouse, tunnel, flyovers, gantries, graffiti, night lighting tweaks
  on the environment.
- `dress_kiefernring.gd`, `dress_valtellina.gd`: classic circuit dressing.

Themes (`theme_*.gd`) build the town/village/port itself and may keep `SITES` free for pieces;
coordinate with the theme so you do not place into a building.

## Step 4: checks

```sh
# parse + build the dressed track
LIMIT=120 tools/hrun.sh res://scenes/race.tscn --quit-after 120 -- --bots=0 --track=seewald 2>&1 | grep -E "SCRIPT ERROR|Parse"
# collision sanity: bots must not hit the piece, everyone finishes
LIMIT=600 tools/hrun.sh res://scenes/race.tscn --fixed-fps 120 -- --allbots --bots=7 --laps=2 --track=seewald
# off-track recovery near the piece still works
tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=seewald --offtrack_test=kerb
# nothing pops in ahead
tools/hrun.sh res://scenes/race.tscn -- --allbots --bots=0 --track=seewald --pop-audit
# screenshots: driver-height views and roadside close-ups in one run
tools/bgrun.sh res://scenes/race.tscn -- --track=seewald --bots=0 --dress_shots=/tmp/seewald \
  --dress_at=780,820,860 --dress_side=820,-820
# fps on the dressed track
TRACKS="seewald" tools/perfcheck.sh
```

For bisecting, some dress files have their own switches (`--no-dress` in Kiefernring and
Valtellina, `NO_DRESS=1` in Alpenpass, `--debug-dress` placement logs in Küstenstraße); add the
same to yours if it is large. `--fill_off` skips the landscape filler.
