"""Generates the source humans for the crowd with Blender + MPFB 2 and the CC0
MakeHuman system assets, exporting one rigged (Mixamo skeleton) GLB each into
assets/people/src. Run headless (see assets/people/CREDITS_people.txt for setup):

  BLENDER_USER_RESOURCES=<profile with MPFB + makehuman_system_assets> \
    Blender -b --python assets/people/bake/make_humans.py -- <out dir>
"""
import os
import sys

import addon_utils
import bpy

addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

OUT = sys.argv[sys.argv.index("--") + 1]
DATA = LocationService.get_user_data()
print("MPFB data", DATA)

# id: macro sliders, skin, parts (asset dir/name relative to MPFB user data).
HUMANS = {
    "man_jacket": ({"gender": 1.0, "age": 0.62, "muscle": 0.5, "weight": 0.55, "height": 0.55, "proportions": 0.6,
                    "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}},
                   "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat",
                   ["clothes/male_casualsuit05/male_casualsuit05.mhclo", "clothes/shoes02/shoes02.mhclo",
                    "hair/short02/short02.mhclo", "eyebrows/eyebrow001/eyebrow001.mhclo", "eyes/low-poly/low-poly.mhclo"]),
    "man_shirt": ({"gender": 1.0, "age": 0.5, "muscle": 0.55, "weight": 0.5, "height": 0.6, "proportions": 0.6,
                   "race": {"caucasian": 0.85, "african": 0.05, "asian": 0.1}},
                  "skins/young_caucasian_male/young_caucasian_male.mhmat",
                  ["clothes/male_casualsuit01/male_casualsuit01.mhclo", "clothes/shoes01/shoes01.mhclo",
                   "hair/short04/short04.mhclo", "eyebrows/eyebrow002/eyebrow002.mhclo", "eyes/low-poly/low-poly.mhclo"]),
    "man_overalls": ({"gender": 1.0, "age": 0.55, "muscle": 0.6, "weight": 0.52, "height": 0.55, "proportions": 0.6,
                      "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}},
                     "skins/young_caucasian_male2/young_caucasian_male2.mhmat",
                     ["clothes/male_worksuit01/male_worksuit01.mhclo", "clothes/shoes06/shoes06.mhclo",
                      "hair/short01/short01.mhclo", "eyebrows/eyebrow001/eyebrow001.mhclo", "eyes/low-poly/low-poly.mhclo"]),
    "woman_casual": ({"gender": 0.0, "age": 0.5, "muscle": 0.45, "weight": 0.5, "height": 0.5, "proportions": 0.6,
                      "cupsize": 0.5, "firmness": 0.5, "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}},
                     "skins/young_caucasian_female/young_caucasian_female.mhmat",
                     ["clothes/female_casualsuit01/female_casualsuit01.mhclo", "clothes/shoes03/shoes03.mhclo",
                      "hair/ponytail01/ponytail01.mhclo", "eyebrows/eyebrow010/eyebrow010.mhclo", "eyes/low-poly/low-poly.mhclo"]),
    "woman_skirt": ({"gender": 0.0, "age": 0.6, "muscle": 0.45, "weight": 0.55, "height": 0.45, "proportions": 0.6,
                     "cupsize": 0.5, "firmness": 0.5, "race": {"caucasian": 0.9, "african": 0.05, "asian": 0.05}},
                    "skins/middleage_caucasian_female/middleage_caucasian_female.mhmat",
                    ["clothes/female_elegantsuit01/female_elegantsuit01.mhclo", "clothes/shoes05/shoes05.mhclo",
                     "hair/bob02/bob02.mhclo", "eyebrows/eyebrow010/eyebrow010.mhclo", "eyes/low-poly/low-poly.mhclo"]),
}

## (lod, decimate ratio): ~3.7k, ~1.1k and ~320 triangles from ~30k.
LODS = [("hi", 0.13), ("mid", 0.038), ("lo", 0.011)]

ASSET_TYPES = {"clothes": "Clothes", "hair": "Hair", "eyebrows": "Eyebrows", "eyes": "Eyes"}

only = sys.argv[sys.argv.index("--") + 2:] if len(sys.argv) > sys.argv.index("--") + 2 else list(HUMANS)
for key in only:
    macro, skin, parts = HUMANS[key]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    info = TargetService.get_default_macro_info_dict()
    for k, v in macro.items():
        info[k] = v
    basemesh = HumanService.create_human(macro_detail_dict=info)
    basemesh.name = key
    HumanService.add_builtin_rig(basemesh, "mixamo")
    for part in parts:
        HumanService.add_mhclo_asset(os.path.join(DATA, part), basemesh, asset_type=ASSET_TYPES[part.split("/")[0]],
                                     subdiv_levels=0, material_type="GAMEENGINE")
    HumanService.set_character_skin(os.path.join(DATA, skin), basemesh, skin_type="GAMEENGINE")
    # No subdivision on export.
    for obj in bpy.data.objects:
        for mod in list(obj.modifiers):
            if mod.type == "SUBSURF":
                obj.modifiers.remove(mod)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # Three LODs, decimated per object (so small parts such as the head keep
    # their share of triangles); eyes and brows are dropped from the far LOD.
    for lod, ratio in LODS:
        for obj in meshes:
            for mod in list(obj.modifiers):
                if mod.type == "DECIMATE":
                    obj.modifiers.remove(mod)
            part = obj.name.split(".")[-1]
            obj.hide_set(False)
            obj.hide_render = False
            if lod == "lo" and (part.startswith("eyebrow") or part in ("low-poly", "high-poly")):
                obj.hide_set(True)
                obj.hide_render = True
                continue
            if ratio < 1.0:
                dec = obj.modifiers.new("lod", "DECIMATE")
                dec.decimate_type = "COLLAPSE"
                dec.ratio = ratio
                dec.use_collapse_triangulate = True
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "%s_%s.glb" % (key, lod)), export_format="GLB",
                                  export_apply=True, export_skins=True, export_animations=False, export_yup=True,
                                  export_morph=False, use_visible=True, export_jpeg_quality=85,
                                  # Only the full LOD carries the textures (the baker
                                  # builds its atlas from it).
                                  export_image_format="JPEG" if lod == "hi" else "NONE")
    print("EXPORTED", key)
