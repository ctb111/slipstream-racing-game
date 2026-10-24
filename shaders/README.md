# shaders/

Every custom shader in the game. Materials are created in code (`ShaderMaterial.new()` +
`load("res://shaders/<name>.gdshader")`), so the "Used by" column is where to look for the uniforms a
shader is fed. `.gdshaderinc` files are includes shared by several shaders.

## The weather include

`weather.gdshaderinc` declares the **global shader uniforms** `wx_wet`, `wx_wet_line`, `wx_snow`, `wx_rain`,
`wx_wind` (registered in `project.godot` under `[shader_globals]`, pushed by `Weather._push_globals()`), and
`wx_gust(xz, t)`, travelling gust fronts along `WX_DIR` (mirrored on the CPU by `Atmosphere.gust()`).
Materials keep their own build-time uniforms (`wetness`, `snow`, ...) and use `max(uniform, global)`, so a
fixed weather preset and changeable weather both work without touching any material. Any surface that
should get wet, snowy or sway in the wind includes it.

## Files

### Road and ground

| Shader | Used by | What it does |
|---|---|---|
| `road.gdshader` | `track/circuit.gd` | Circuit tarmac: photo asphalt, rubbered racing line, braking / traction zone marks (per-vertex data from `TrackBuilder`), painted lines, puddles, wet sheen, snow. |
| `road_kerb.gdshader` | `track/track_builder.gd` | FIA-style painted kerbs. |
| `road_shoulder.gdshader` | `track/track_builder.gd` | Dirt / grit verge between tarmac and grass. |
| `road_gravel.gdshader` | `track/track_builder.gd` | Gravel traps with tyre grooves. |
| `road_decal.gdshader` | `track/road_decals.gd` | Tyre marks, drain grates, manhole covers in one mesh. |
| `road_leaves.gdshader` | `world/road_leaves.gd` | Fallen leaves on the road kicked up by up to 8 cars. |
| `road_debris.gdshader` | `world/atmosphere.gd` | Leaves and paper blown across the road in gusts. |
| `terrain.gdshader` | `world/world_builder.gd` | Ground: two photo grass sets blended by noise, sampled at two rotated scales. |
| `theme_coast_ground.gdshader` | `track/themes.gd` | Coastal copy of the terrain shader with beach sand and triplanar cliff rock. |
| `alpine_terrain.gdshader` | `track/theme_alpine.gd` | Alpenpass ground: grass plus rock and scree. |

### Sky, water, atmosphere, light

| Shader | Used by | What it does |
|---|---|---|
| `sky.gdshader` | `world/weather.gd` | HDRI panorama + animated clouds (quarter-resolution pass), distant ridges, night sky, crossfade to a second panorama for changeable weather. |
| `theme_sea.gdshader` | `track/themes.gd` | Open sea: ripples, swell, depth colour, shore foam. |
| `water.gdshader` | `track/scenery.gd`, `track/theme_autumn.gd` | Lakes and rivers. |
| `mist.gdshader` | `world/atmosphere.gd` | Valley mist layer, thicker where the land falls away (depth based). |
| `dust_motes.gdshader` | `world/atmosphere.gd` | Specks lit up when looking into a low sun. |
| `dust_devil.gdshader` | `world/atmosphere.gd` | Whirling dust column. |
| `windsock.gdshader` | `world/atmosphere.gd` | Windsock bending with wind and gusts. |
| `lamp_halo.gdshader` | `track/night_lights.gd` | Camera-facing glare around street lamps and floodlights. |
| `set_lamp.gdshader` | `track/night_lights.gd`, `track/set_dressing.gd` | Emissive lamp heads and blinking beacons. |
| `beam_cone.gdshader` | `car/car_lights.gd` | Fake headlight shaft at night, soft where it meets geometry. |

### Vegetation, people, animals

| Shader | Used by | What it does |
|---|---|---|
| `veg_tree.gdshader` | `world/vegetation.gd` | Photo-atlas trees and bushes (alpha-cut foliage + bark), wind, snow, merged far-LOD mode. |
| `foliage.gdshader` | `world/world_builder.gd` | Vertex-coloured swaying trees and bushes. |
| `grass.gdshader` | `world/grass.gd` | Verge grass cards with wind and gusts. |
| `people.gdshader` | `world/people.gd` | Crowd figures: clothing colours, skin, hair from an identity hash; cheering, clapping, flag waving. |
| `wildlife.gdshader` | `world/wildlife.gd` | All animal and bird motion (grazing, gaits, wing beats, flights). |

### Buildings, props, prints

| Shader / include | Used by | What it does |
|---|---|---|
| `pbr_common.gdshaderinc` | `pbr_triplanar*.gdshader` | Photographic PBR sets on UV-less procedural geometry (triplanar), grime, weather. |
| `pbr_triplanar.gdshader` / `pbr_triplanar_2s.gdshader` | `world/materials.gd` (`Mats.mat`) | Single- / double-sided versions of the above. |
| `pbr_props.gdshader` | `world/materials.gd` (`Mats.props`) | Photographic replacement for `set_props.gdshader` with the same mesh interface (COLOR = paint, UV2.x = printed face, UV2.y = gloss). |
| `set_props.gdshader` | (not loaded by current code) | Original vertex-coloured merged-prop shader; kept as the reference for `pbr_props`' mesh interface. |
| `theme_facade.gdshader` | `track/themes.gd`, `track/facade_kit.gd` | Walls with photo windows / doors / shopfronts placed per bay and storey from the FacadeKit atlas; lit windows at night. |
| `facade_unit.gdshader` | `track/facade_kit.gd` | One photo facade unit on a quad. |
| `gx_print.gdshaderinc` | `gx_print*.gdshader` | Printed / painted surfaces (graffiti, posters, signs, road paint): albedo atlas + tiling relief on UV2. |
| `gx_print.gdshader` / `gx_print_alpha.gdshader` | `gimmicks/gx_graffiti.gd`, `gx_billboard.gd`, `gx_road_text.gd` | Opaque / alpha-cut versions. |
| `flag.gdshader` | `track/track_props.gd` | Cloth-like flag motion on merged flag meshes. |
| `trackside_flag.gdshader` | `track/trackside_kit.gd` | Fans' flags (MultiMesh, atlas rect per instance). |
| `trackside_smoke.gdshader` | `track/trackside_kit.gd` | Looping flare and campfire smoke puffs. |
| `trackside_glow.gdshader` | `track/trackside_kit.gd` | Additive flare / campfire flicker and camera flashes. |

### Cars and camera

| Shader / include | Used by | What it does |
|---|---|---|
| `car_dirt.gdshaderinc` | `car/car_dirt.gd` (composes shader variants in code) | Car body / wheel material with dirt, mud, dust, slush, snow and water; variants for double-sided, clearcoat, normal map, AO. |
| `car_glass.gdshaderinc` | `car_glass.gdshader`, `car_glass_cull.gdshader` | Window glass with rain, water film, dust, mud specks, snow. |
| `car_glass.gdshader` / `car_glass_cull.gdshader` | `car/car_dirt.gd` | Double-sided / back-face-culled glass. |
| `exhaust_flame.gdshader` | `car/car_fx.gd` | Backfire flame billboard. |
| `windscreen.gdshader` | `car/cockpit.gd` | Rain drops and snow on the inside view of the windscreen. |
| `post_process.gdshader` | `camera/camera_post.gd` | Full-screen lens pass (`canvas_item`): lens rain, speed blur, aberration, glare and shafts, grade, vignette, grain. |

## How it connects

- Uniforms are set where the material is created (see "Used by"). Live weather arrives through the
  globals, not through per-material updates.
- Textures come from `assets/` (photo sets, atlases generated by `tools/`).

## Gotchas

- **Every shader compiles a pipeline the first time it is drawn.** `race.gd` renders three warm-up frames
  behind the loading screen; changeable weather builds all its materials up front. Do not create new
  materials mid-race.
- **Transparency is expensive and changes sorting.** Prefer alpha scissor / `depth_draw_opaque` for cards
  (grass, trees, prints). Blended shaders (`blend_mix` / `blend_add`) should be `depth_draw_never` and cheap.
  Remember that a `VISIBILITY_RANGE_FADE_SELF` fade also forces the object through the transparent pipeline
  while it fades.
- **Shadows**: most decorative shaders are `shadows_disabled`; shadow casting is done by proxy meshes.
  Keep it that way for anything small.
- **Weather**: include `weather.gdshaderinc` and combine with `max()` rather than adding new per-material
  update code.
- **No procedural fakes of real things.** Windows, facades, signs and graffiti are photo textures; shaders
  place and weather them, they do not draw them.

## Where to start reading

`weather.gdshaderinc`, then `road.gdshader` (shows the per-vertex data contract with `TrackBuilder`), then
`post_process.gdshader`.
