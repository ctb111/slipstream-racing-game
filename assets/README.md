# assets/

Every model, texture, HDRI, font and atlas the game loads. Code finds them by `res://assets/...` path (there
are no `.tscn` prefabs referencing them), so moving a file means updating the script that loads it.

## Licensing rule (read this first)

**Every third-party asset must be credited and must carry a license that allows redistribution and
commercial use.** Accepted: CC0 / public domain, CC BY, CC BY-SA, SIL OFL, Apache 2.0, MIT-style.
**Not accepted: anything NonCommercial (NC) or NoDerivatives (ND)**, "personal use only", "editorial use",
or assets without a clear license. No real manufacturer logos or real brand names on signs (car make and
model names are kept, with the trademark notice in `CREDITS.md`).

When you add an asset you must update **all three** credit places:

1. The per-folder credit file (technical detail: source URL, author, license, what you changed), e.g.
   `assets/cars/CREDITS_cars.txt`, or `assets/CREDITS.txt` for folders without their own file.
2. `CREDITS.md` at the repository root (the public, human-readable list).
3. `assets/CREDITS_INGAME.txt` (shown on the in-game Credits screen by `scripts/ui/menu_credits.gd`;
   `# ` lines are section headers, blank lines separate entries; it is included in exports via
   `export_presets.cfg`).

CC BY-SA assets and anything derived from them (for example the baked graffiti and billboard atlases and the
Datsun 240K) stay CC BY-SA, not MIT; note that in `CREDITS.md`.

## Credit files

| File | Covers |
|---|---|
| `CREDITS.txt` | General / everything not covered below (HDRIs, Poly Haven models, facades, gimmick sources, ...). |
| `CREDITS_INGAME.txt` | The text the in-game Credits screen shows. |
| `cars/CREDITS_cars.txt` | Car models (Sketchfab, CC BY / CC BY-SA). Per-model `license.txt` files sit in `cars/src/`. |
| `materials/CREDITS_materials.txt` | PBR material sets (ambientCG / Poly Haven, CC0). |
| `people/CREDITS_people.txt` | Crowd figure models. |
| `road/CREDITS_road.txt` | Road, gravel and pebble textures. |
| `themes/CREDITS.txt` | Theme textures (roofs, walls, cliffs, sand, cobbles, farm soil). |
| `trackside/CREDITS_trackside.txt` | Trackside atlases (and the fonts used to paint them, licenses in `trackside/src/fonts/`). |
| `vegetation/CREDITS_vegetation.txt` | Tree, grass, flower and rock scans. |
| `wildlife/CREDITS_wildlife.txt` | Animal and bird models. |
| `fonts/OFL.txt` | SIL Open Font License for Barlow Semi Condensed. |

## Folder layout

| Folder | Contents | Loaded by |
|---|---|---|
| `cars/` | One `.glb` per drivable car plus its textures. | `scripts/car/car_catalog.gd` (`path`), `car_model.gd` |
| `cars/src/` | Raw downloads before conversion (`.gdignore`, git-ignored). | not loaded |
| `hdri/` | Poly Haven pure-sky HDRIs for the weather presets (day and night variants). | `scripts/world/weather.gd` `PRESETS.hdri` |
| `textures/` | Core photo sets: `asphalt_track`, `gravel_floor`, `grass_ground`, `sparse_grass`, `car_dirt`, `facades` (FacadeKit atlas `facade_{alb,nor,mask}.png`), `fx`. | `WorldBuilder.tex(id, kind)`, `facade_kit.gd`, `car_dirt.gd` |
| `road/` | Extra road-side photo sets (`asphalt_02`, `floor_pebbles_01`, `gravelly_sand`) and `road_noise.png`. | `track_builder.gd`, road shaders |
| `materials/` | CC0 PBR sets for procedural buildings and props (brick, concrete, corrugated, steel, plaster, roof tiles, slate, stone, wood, ...). | `scripts/world/materials.gd` (`Mats.mat`) |
| `themes/` | Theme-specific photo sets (`alpine`, clay roof tiles, cliff side, coast sand, cobblestones, farm soil, plastered and stone walls), `<id>_<map>_1k.jpg`. | `scripts/track/themes.gd` (`TEX`) and `theme_*.gd` |
| `trackside/` | `trackside_paint.png`, `trackside_signs.png` atlases (regions in `scripts/track/trackside_uv.gd`). | `trackside_kit.gd`, `track_props.gd`, `gx_geo.gd` |
| `trackside/src/` | Atlas sources (git-ignored except `fonts/` with their licenses). | `tools/make_trackside_atlas.py` |
| `gimmicks/` | Gx atlases (`gx_billboard.png`, `gx_graffiti_walls.png`, `gx_graffiti_tags.png`, `gx_road_text.png`), Poly Haven models for the dressing (`dress/`, `electricity_poles/`, `street_lamp_01/`). | `scripts/track/gimmicks/gx_*.gd` |
| `gimmicks/src/` | Atlas sources (`.gdignore`, git-ignored). | `tools/make_gx_*.py` |
| `industrial/` | Poly Haven CC0 props as `.glb` + textures (barrels, crates, ...), `hay/`. | `gimmicks/gx_props.gd` (`GxProps.scatter`) |
| `industrial/src/` | Raw downloads (`.gdignore`, git-ignored). | not loaded |
| `camp/` | Poly Haven CC0 camping props (chairs, tables, jerrycans, fire pit, ...). | `gimmicks/gx_camp.gd` |
| `people/` | Baked posed crowd meshes (`meshes/`), `people_atlas.png`; `bake/` holds the baking scripts. | `scripts/world/people.gd` |
| `people/src/` | Source character models (`.gdignore`, git-ignored). | `people/bake/bake_people.gd` |
| `vegetation/` | Tree models (`trees/`), grass atlas (`grass/`), rocks; `_bake/` holds bake / atlas scripts and a tree gallery scene. | `scripts/world/vegetation.gd`, `grass.gd`, `world_builder.gd` |
| `wildlife/` | Normalised animal / bird models (`models/`); `bake/bake_animals.py` normalises them. | `scripts/world/wildlife.gd` |
| `facades_src/` | Facade photo sources for the FacadeKit atlas (`.gdignore`, git-ignored). | `tools/build_facade_atlas.gd` |
| `fonts/` | Barlow Semi Condensed (SIL OFL), the UI font (`project.godot` `gui/theme/custom_font`). | `ui_theme.gd`, `hud_style.gd` |
| `fx/` | `smoke_puff.png` sprite. | `scripts/car/tire_fx.gd` |

## Raw sources and `.gdignore`

Folders with a `.gdignore` file are invisible to Godot (never imported, never exported):
`cars/src/`, `facades_src/`, `gimmicks/src/`, `industrial/src/`, `people/src/`, `trackside/src/`.
They hold original downloads and atlas inputs used only by the tools in `tools/` and the bake scripts. They
are also listed in `.gitignore`, so they are not in the repository; fetch them again from the sources in
the credit files if you need to rebuild an atlas or re-convert a model.

Put any new raw download in a `src/` folder with a `.gdignore` so its `.blend`/`.fbx`/huge textures are not
imported into the game.

## Gotchas

- **Photographic, not cartoony.** The game aims for a grounded, real-world look: prefer real scans and
  photo PBR sets (Poly Haven, ambientCG, Wikimedia Commons with a compatible license). Avoid stylised /
  low-poly asset packs.
- **Size and import settings matter on an M1.** Use 1k-2k textures unless an asset is seen up close;
  VRAM compression (ETC2/ASTC) is on project-wide.
- **Generated files**: the trackside and Gx atlases (and `scripts/track/trackside_uv.gd`,
  `scripts/track/gimmicks/gx_road_glyphs.gd`) are produced by `tools/make_*.py`; edit the sources and
  regenerate instead of painting over the output.
- Models are post-processed in code (`CarModel` merges, re-centres and re-LODs cars), so a new car needs a
  `CarCatalog` entry describing its materials, not a hand-edited glb.

## Where to start

`CREDITS.md` (root) for what is here and under which license, then the folder for the asset type you are
touching and its credit file.
