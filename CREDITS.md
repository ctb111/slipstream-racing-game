# Credits

**Slipstream** is a classic-car LAN racer.

The game's code and its original assets are released under the **MIT License** (see LICENSE). That covers procedural geometry, the
synthesised sounds, the trackside artwork made for the game, and the textures made by our own tools. Third-party
assets keep the licenses listed below. Every one of those licenses allows redistribution and commercial use.

Per-folder credit files hold the technical detail (source files, processing steps):
`assets/CREDITS.txt`, `assets/cars/CREDITS_cars.txt`, `assets/wildlife/CREDITS_wildlife.txt`,
`assets/people/CREDITS_people.txt`, `assets/vegetation/CREDITS_vegetation.txt`,
`assets/materials/CREDITS_materials.txt`, `assets/road/CREDITS_road.txt`, `assets/themes/CREDITS.txt`,
`assets/trackside/CREDITS_trackside.txt`.

License links used below:
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) ·
[CC BY 2.0](https://creativecommons.org/licenses/by/2.0/) ·
[CC BY 2.5](https://creativecommons.org/licenses/by/2.5/) ·
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) ·
[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) ·
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) ·
[SIL OFL 1.1](https://openfontlicense.org) ·
[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)

> **Share-alike note.** The Datsun 240K model and the baked graffiti and billboard atlases
> (`assets/gimmicks/gx_graffiti_walls.png`, `assets/gimmicks/gx_billboard.png`) are adaptations of CC BY-SA works.
> These files are distributed under **CC BY-SA 4.0**, not MIT.

> **Trademarks.** Car makes and model names are trademarks of their respective owners. This is an independent fan
> project, not affiliated with or endorsed by them. All shop, sponsor and team names on signs are invented.

---

## Cars

Licenses were checked against the Sketchfab API (`api.sketchfab.com/v3/models/<uid>`) on 2026-10-24. Each model came from a
public GitHub mirror of the Sketchfab export. Changes made to all of them: Draco/quantization decoded and converted for Godot
with glTF-Transform. Model-specific changes are listed per car.

| Car | Work | Author | License | Modified |
|---|---|---|---|---|
| Porsche 911 Turbo (930) | ["FREE 1975 Porsche 911 (930) Turbo"](https://sketchfab.com/3d-models/free-1975-porsche-911-930-turbo-8568d9d14a994b9cae59499f0dbed21e) | [Lionsharp Studios](https://sketchfab.com/lionsharp) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | decoded |
| BMW M3 (E30) | ["[FREE] BMW M3 E30"](https://sketchfab.com/3d-models/free-bmw-m3-e30-ac3c7013434e403e8faff87948caf422) | Martin Trafas ([TinoD2](https://sketchfab.com/TinoD2), formerly "Bexxie") | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | decoded |
| Datsun 240K GT | ["(FREE) 1972 Datsun 240k GT"](https://sketchfab.com/3d-models/free-1972-datsun-240k-gt-b2303a552b444e5b8637fdf5169b41cb) | [Lionsharp Studios](https://sketchfab.com/lionsharp) (Karol Miklas) | [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) | simplified to ~117k tris, WebP→PNG; the modified model is CC BY-SA 4.0 |
| Toyota Sprinter Trueno (AE86) | ["Japanese Touge Racer - Initial D spec"](https://sketchfab.com/3d-models/japanese-touge-racer-initial-d-spec-59a0eaaa2af144b2956957e7032d0221) | [Daniel Zhabotinsky](https://sketchfab.com/DanielZhabotinsky) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | unmodified |
| Mazda RX-7 (FC) | ["Mazda RX-7 FC"](https://sketchfab.com/3d-models/mazda-rx-7-fc-8ac0df459f514950ab83ac37109a06ab) | [Lexyc16](https://sketchfab.com/Lexyc16) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | packed to .glb |
| Ferrari F40 | ["Ferrari f40"](https://sketchfab.com/3d-models/ferrari-f40-52a66c41cfcd4f999fb1b1c49bf24d70) | [Black Snow](https://sketchfab.com/BlackSnow02) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | packed, welded, simplified to ~140k tris |

Parked cars on the tracks reuse these models. The livery colours and the cockpit interiors and gauges are our own work.

## Vehicles & wildlife

Animal models are from Sketchfab, obtained through the [Objaverse](https://huggingface.co/datasets/allenai/objaverse) dataset.
All of them are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), and each license was checked on Sketchfab.
Modifications for all of them: re-posed, joined, scaled and decimated, with textures shrunk (`assets/wildlife/bake/bake_animals.py`).
The animation is procedural.

| In game | Work | Author |
|---|---|---|
| gull | ["Seagull"](https://sketchfab.com/3d-models/dd79fddb754f47caa3145e7d184e3e58) | Bwinji Shamutete (MangyMedusa) |
| crow | ["Crow"](https://sketchfab.com/3d-models/45a169ef98804f06a9b7a4af1a04d6f9) | zixisun02 (zixisun51) |
| pigeon | ["pigeon - 3dModel - Free"](https://sketchfab.com/3d-models/e3ee02557a7d43a59ac030f5292aa2d3) | velvel |
| birds in flight (recoloured) | ["Bird from Poly by Google"](https://sketchfab.com/3d-models/6ef1e318e5e544bc954f02ba67654b93) | IronEqual (ie-niels), archive of the Google Poly asset "Bird" (Poly assets were CC BY) |
| ginger cat | ["504班-02號-陳泓光-阿嬤養的貓"](https://sketchfab.com/3d-models/b6cb17060a3c445087a96a7b6b2f50bf) | BillyChen |
| red cow | ["Cow"](https://sketchfab.com/3d-models/99d333e3b4e4470a8d7d38436489c001) | Josué Boisvert (JosueBoisvert) |
| Holstein cow | ["cow"](https://sketchfab.com/3d-models/dfa314a5b6bb4ec6b3fdbdc2ab59cbad) | rocket95 |
| sheep | ["Sheep"](https://sketchfab.com/3d-models/67abff7459f34afca11e3effab62c761) | hendrikReyneke |
| horse | ["Low Poly Horse"](https://sketchfab.com/3d-models/c8778532ab804fc18cae6a0e20feffd3) | Nioma van der Steen (fromthestone) |
| deer | ["Walk Deer"](https://sketchfab.com/3d-models/7d988ce63dae499297bc2c46007240f0) | Eseyeyo (painted in-shader) |
| labrador | ["狗狗走路"](https://sketchfab.com/3d-models/7d6d8c6b5a4a4377823ef1b837848177) | HonDaMcd |
| shepherd dog | ["Dog"](https://sketchfab.com/3d-models/10f72adc3c5f4e6db3322963d73e14ee) | Andy Andy (rootrainz4) |

The TV helicopter, camera drone, tractors, forklift, excavator, roller, tents, caravans, balloons and blimp are procedural
geometry made for this game.

## People

All human figures (spectators, crowd, marshals, pit crew) are built from the
[MakeHuman system assets](https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html)
(MakeHuman Community; Data Collection AB, Joel Palmius, Jonas Hauquier), [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
They were posed, decimated and baked into an atlas for this game. See `assets/people/CREDITS_people.txt`.

## Vegetation

All [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Models were rendered into card atlases and packed with our own tools.

- **Poly Haven** ([polyhaven.com/a/&lt;id&gt;](https://polyhaven.com)): grass_medium_01 and grass_medium_02, dandelion_01,
  celandine_01, weed_plant_02, nettle_plant, fern_02, fir_sapling and pine_sapling_small (Rob Tuytel, Rico Cilliers), shrub_03 (Rico Cilliers),
  pine_bark (Dimitrios Savva). Rocks: rock_07 and rock_09 (Jenelle van Heerden), stone_01 (Dario Barresi, Rico Cilliers),
  decimated.
- **ambientCG** ([ambientcg.com](https://ambientcg.com)): LeafSet024, LeafSet016, LeafSet009 (leaf atlases and clumps),
  Bark014, Bark005.
- Tree models were grown with Sapling Tree Gen (see Tools). The meshes it generated are our own output.

## Textures & materials

All [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Poly Haven pages: `https://polyhaven.com/a/<id>`, ambientCG: `https://ambientcg.com/view?id=<id>`.

- **Road & ground** (Poly Haven): asphalt_track (Dimitrios Savva), asphalt_02 (Rob Tuytel), floor_pebbles_01 (Rob Tuytel),
  gravelly_sand (Dario Barresi), gravel_floor (Jenelle van Heerden, Matterfield), grass_ground (Charlotte Baglioni),
  sparse_grass (Amal Kumar).
- **Building materials** (Poly Haven): concrete_wall_008 (Dario Barresi, Charlotte Baglioni), painted_plaster_wall, plastered_wall,
  clay_roof_tiles, clay_roof_tiles_02, farm_soil (Amal Kumar), red_brick_03, roof_slates_03, rusty_metal_02, large_sandstone_blocks,
  coast_sand_01, cobblestone_floor_08 (Rob Tuytel), corrugated_iron_02 (Jenelle van Heerden, Sergej Majboroda),
  weathered_planks (Dario Barresi, Dimitrios Savva), stone_wall (Dario Barresi, Charlotte Baglioni),
  cliff_side (James Ray Cock, Jenelle van Heerden, Dario Barresi).
- **Alpine terrain** (Poly Haven): aerial_rocks_02, rock_08, snow_02 (Rob Tuytel), gray_rocks (Dimitrios Savva).
- **ambientCG**: Metal016, Metal038, Fabric030, Rubber004, ThatchedRoof001A, Facade018A (brick block facade).
  The ARM maps were packed by our tools.
- **Props & models** (Poly Haven, CC0; some decimated, textures at 1k):
  wooden_crate_01, wooden_crate_02, steel_frame_shelves_01, utility_box_01, modular_chainlink_fence, outdoor_table_chair_set_01,
  wooden_lantern_01, wooden_barrels_01, wine_barrel_01, modular_electricity_poles (James Ray Cock; crate_02 with Jurita Burger;
  fence with Amal Kumar), Barrel_01 and Barrel_02 (Jorge Camacho), barrel_03 (Serhii Khromov), hanging_industrial_lamp and
  plastic_monobloc_chair_01 and wicker_basket_01 (Kuutti Siitonen), old_tyre and covered_car (MP), propane_tank (Slinc),
  security_light (Maximilian Schuster), cardboard_box_01 and plastic_bottle_gallon and can_rusted (Rahul Chaudhary),
  cement_bag (PierreB3D), concrete_road_barrier (Amal Kumar), metal_trash_can (GurJas Studios),
  exterior_aircon_unit (Monsta3D), hand_truck (Mutanzom3D), street_lamp_01 (Josh Dean),
  folding_wooden_stool and wooden_picnic_table and plastic_jerrycan (Ulan Cabanilla), stone_fire_pit (Sebastian Platen),
  metal_jerrycan (Sean Buckley), modified_thermos (Alex Weber), modular_wooden_pier (Rico Cilliers), lifebuoy (Hank Kaamura).
- **Original (MIT)**: `assets/textures/car_dirt/dirt_noise.png` (made by `tools/bake_dirt_noise.gd`), `assets/fx/smoke_puff.png`
  (baked smoke sprite), `assets/textures/fx/headlight_pool.png` (baked from the former `_pool_texture()` maths),
  `assets/road/road_noise.png` (FastNoiseLite), the trackside atlases (`tools/make_trackside_atlas.py`) and the birch bark.
  Everything above was made for this game.

## Photos (facades, graffiti, billboards)

Photos were cropped, levelled and weathered. Normal maps and glass masks were derived from them. Brands and text on the posters are invented.

**Facades** (`assets/facades_src` → facade atlas):

- OpenStreetMap wiki [Texture Library](https://wiki.openstreetmap.org/wiki/Texture_Library), public domain:
  DE19B7_AugsburgWallWithWindow0001, MarekCompositeWall00001/00002, DE19F1FreisingDoor00003/00004/00005/00006/00010.
- ["Window with green shutters (52829708373)"](https://commons.wikimedia.org/wiki/File:Window_with_green_shutters_(52829708373).jpg),
  ["Window with green shutters on old house (52829664075)"](https://commons.wikimedia.org/wiki/File:Window_with_green_shutters_on_old_house_(52829664075).jpg),
  ["Rustic old grungy and weathered green wooden window shutters (52829668245)"](https://commons.wikimedia.org/wiki/File:Rustic_old_grungy_and_weathered_green_wooden_window_shutters_(52829668245).jpg)
  by Jernej Furman, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)
- ["This charming door (8643717688)"](https://commons.wikimedia.org/wiki/File:This_charming_door_(8643717688).jpg) by decar66, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)
- ["Closed bakery in Bad Kreuznach"](https://commons.wikimedia.org/wiki/File:Closed_bakery_in_Bad_Kreuznach.jpg) by Spielvogel, [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
- ["Enns, Haus Kirchengasse 2, Tür und Schaufenster"](https://commons.wikimedia.org/wiki/File:Enns,_Haus_Kirchengasse_2,_T%C3%BCr_und_Schaufenster.jpg) by Dguendel, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- ["20110625Cafe Walz Neulussheim2"](https://commons.wikimedia.org/wiki/File:20110625Cafe_Walz_Neulussheim2.jpg) by AnRo0002, [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
- ["DSCF8682"](https://commons.wikimedia.org/wiki/File:DSCF8682.JPG) by Twice25 & Rinina25, [CC BY 2.5](https://creativecommons.org/licenses/by/2.5/)

**Graffiti walls** (`gx_graffiti_walls.png`, CC BY-SA 4.0 as a whole). The artworks belong to their anonymous street artists.

- "Graffiti-hannover 03, 06, 07, 08, 09, 10, 11, 14, 15, 16, 17 hg" by Hannes Grobe, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/):
  [03](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_03_hg.jpg),
  [06](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_06_hg.jpg),
  [07](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_07_hg.jpg),
  [08](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_08_hg.jpg),
  [09](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_09_hg.jpg),
  [10](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_10_hg.jpg),
  [11](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_11_hg.jpg),
  [14](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_14_hg.jpg),
  [15](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_15_hg.jpg),
  [16](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_16_hg.jpg),
  [17](https://commons.wikimedia.org/wiki/File:Graffiti-hannover_17_hg.jpg)
- ["Hallstadt Graffiti -20200417-RM-165317"](https://commons.wikimedia.org/wiki/File:Hallstadt_Graffiti_-20200417-RM-165317.jpg) by Ermell, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- ["M&GN bridge pillar over the Fen Line, graffiti detail"](https://commons.wikimedia.org/wiki/File:M%26GN_bridge_pillar_over_the_Fen_Line,_graffiti_detail.jpg) by Lewis Collard, [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
- ["Ambigram Zen Yes, blue and orange graffiti on concrete wall"](https://commons.wikimedia.org/wiki/File:Ambigram_Zen_Yes,_blue_and_orange_graffiti_on_concrete_wall.jpg) by Basile Morin, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- ["Graffiti Nova Gorica 8"](https://commons.wikimedia.org/wiki/File:Graffiti_Nova_Gorica_8.JPG) by MZaplotnik, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)
- Graffiti tags: ambientCG ["Graffiti Set 001"](https://ambientcg.com/view?id=GraffitiSet001), [CC0](https://creativecommons.org/publicdomain/zero/1.0/)

**Billboards** (`gx_billboard.png`, CC BY-SA 4.0 as a whole; the brands are invented):

- ["Close-up of espresso machine with two brown coffee cups"](https://commons.wikimedia.org/wiki/File:Close-up_of_espresso_machine_with_two_brown_coffee_cups.jpg) by Chevanon Photography, [CC0](https://creativecommons.org/publicdomain/zero/1.0/)
- ["Beer glass microbrewery Heimatliebe in Duderstadt, Lower Saxony, Germany"](https://commons.wikimedia.org/wiki/File:Beer_glass_microbrewery_Heimatliebe_in_Duderstadt,_Lower_Saxony,_Germany.jpg) by Nemracc, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- ["Eielson Alpine Trail View"](https://commons.wikimedia.org/wiki/File:Eielson_Alpine_Trail_View_(416fd47c-ab20-4c43-b2e3-3470c9db0f80).JPG) by NPS Photo / Emily Mesner, public domain (U.S. National Park Service)
- ["Datsun SPL311 (1965)"](https://commons.wikimedia.org/wiki/File:Datsun_SPL311_(1965).jpg) by SG2012, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/)
- ["Binkada Quartz Wristwatch with Blue Sunburst Dial and Faceted Crystal 01"](https://commons.wikimedia.org/wiki/File:Binkada_Quartz_Wristwatch_with_Blue_Sunburst_Dial_and_Faceted_Crystal_01.jpg) by A S M Jobaer, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- "Bergweg tussen Andiast, Ladinas en Breil-Brigels (actm)" [18](https://commons.wikimedia.org/wiki/File:Bergweg_tussen_Andiast,_Ladinas_en_Breil-Brigels_(actm)_18.jpg) and [19](https://commons.wikimedia.org/wiki/File:Bergweg_tussen_Andiast,_Ladinas_en_Breil-Brigels_(actm)_19.jpg) by Agnes Monkelbaan, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)
- ["Glocknerstraße 2026 04"](https://commons.wikimedia.org/wiki/File:Glocknerstra%C3%9Fe_2026_04.jpg) by StVeit Maps, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)

## Sounds

There are no recorded samples. The engines, turbos, tyres, wind, impacts, crowd, PA, birds, weather and menu clicks are all
synthesised in code at load time (`scripts/car/car_audio.gd`, `car_impacts.gd`, `scripts/world/ambience.gd`, `weather.gd`,
`scripts/ui/ui_sounds.gd`). They are original work under MIT.

## Fonts

- **Barlow Semi Condensed** by Jeremy Tribby (The Barlow Project Authors), [SIL OFL 1.1](https://openfontlicense.org): game UI font, `assets/fonts/OFL.txt`.

The fonts below are used only to bake the trackside and road-paint atlases (`assets/trackside/src/fonts`, license texts next to them):

- **Bungee** by David Jonathan Ross, [SIL OFL 1.1](https://openfontlicense.org)
- **Sedgwick Ave Display** by Kevin Burke and Pedro Vergani, [SIL OFL 1.1](https://openfontlicense.org)
- **Permanent Marker** by Font Diner, [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- **Rock Salt** by Font Diner (Sideshow), [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)

## HDRIs / sky

[Poly Haven](https://polyhaven.com) HDRIs, [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/):

- [Kloofendal 48d Partly Cloudy (Pure Sky)](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky): Greg Zaal, Jarod Guest
- [Kloofendal Overcast (Pure Sky)](https://polyhaven.com/a/kloofendal_overcast_puresky): Greg Zaal
- [Qwantani Sunset (Pure Sky)](https://polyhaven.com/a/qwantani_sunset_puresky): Greg Zaal, Jarod Guest
- [Qwantani Dawn (Pure Sky)](https://polyhaven.com/a/qwantani_dawn_puresky): Greg Zaal, Jarod Guest
- [Kloppenheim 02 (Pure Sky)](https://polyhaven.com/a/kloppenheim_02_puresky): Greg Zaal, Jarod Guest
- [Kloppenheim 07 (Pure Sky)](https://polyhaven.com/a/kloppenheim_07_puresky): Greg Zaal, Jarod Guest
- [Snow Field (Pure Sky)](https://polyhaven.com/a/snow_field_puresky): Jarod Guest, Sergej Majboroda

## Tools

- [Godot Engine](https://godotengine.org) 4.7, MIT. The engine runtime is included in exported builds under its own
  [MIT license](https://godotengine.org/license).

The tools below are used only to build assets and are not shipped. Their output is our own work, or follows the asset
licenses above.

- [Blender](https://www.blender.org) 5.2, GPL
- [Sapling Tree Gen](https://extensions.blender.org/add-ons/sapling-tree-gen/) by Andrew Hale and Aaron Buchler, GPL-2.0-or-later
- [MPFB 2](https://extensions.blender.org/add-ons/mpfb/) (MakeHuman plugin for Blender) by Joel Palmius et al., GPL-3.0-or-later
- [glTF-Transform](https://gltf-transform.dev) by Don McCurdy, MIT
- Python with [Pillow](https://python-pillow.org) (MIT-CMU) and [NumPy](https://numpy.org) (BSD)
- [Objaverse](https://huggingface.co/datasets/allenai/objaverse) (Allen Institute for AI), used as the download source for the animal models
