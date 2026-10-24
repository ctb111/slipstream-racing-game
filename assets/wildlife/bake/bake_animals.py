"""Normalises the source animal models (Objaverse / Sketchfab, see
assets/wildlife/CREDITS_wildlife.txt) for the Wildlife kit: applies the pose,
joins the parts, turns the head to Blender +Y (Godot -Z), scales to real size,
puts the feet at the origin, decimates to a near (hi) and a far (lo) mesh and
shrinks the textures. Run headless:
  Blender -b --python assets/wildlife/bake/bake_animals.py -- <src glb dir> <out dir> [preview dir] [names...]
"""
import bpy, bmesh, sys, os, math, mathutils

# name: (source glb, measure ('len' horizontal length | 'h' height | 'span' max extent), metres,
#        yaw degrees (head to +Y), hi tris, lo tris, frame)
ASSETS = {
	"gull": ("bird_109", "len", 0.56, 0, 900, 220, 0),
	"bird_fly": ("fly_27", "span", 1.0, 0, 400, 400, 0),
	"crow": ("bird_19", "len", 0.46, 0, 800, 200, 0),
	"pigeon": ("bird_57", "len", 0.32, 0, 700, 180, 0),
	"cat_ginger": ("cat_27", "h", 0.31, 0, 1400, 300, 0),
	"cow_red": ("cow_52", "h", 1.38, 0, 2400, 500, 0),
	"cow_holstein": ("cow_80", "h", 1.5, 0, 2400, 500, 0),
	"sheep": ("sheep_2", "h", 0.95, 0, 1800, 400, 0),
	"horse": ("horse_27", "h", 2.1, 0, 2000, 450, 0),
	"deer": ("deer_48", "len", 1.9, 0, 2600, 500, 0),
	"dog_lab": ("dog_59", "h", 0.72, 0, 2200, 450, 0),
	"dog_shepherd": ("dog_105", "h", 0.85, 0, 2200, 450, 0),
}
YAW_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "yaw.txt")

argv = sys.argv[sys.argv.index("--") + 1:]
src, out = argv[0], argv[1]
prev = argv[2] if len(argv) > 2 else ""
names = argv[3:] or list(ASSETS)
yaws = {}
if os.path.exists(YAW_FILE):
	for line in open(YAW_FILE):
		p = line.split()
		if len(p) == 2:
			yaws[p[0]] = float(p[1])


def tris_of(o):
	return sum(len(p.vertices) - 2 for p in o.data.polygons)


for name in names:
	f, measure, metres, yaw, hi, lo, frame = ASSETS[name]
	yaw = yaws.get(name, yaw)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=os.path.join(src, f + ".glb"))
	sc = bpy.context.scene
	sc.frame_set(frame)
	dg = bpy.context.evaluated_depsgraph_get()
	# Bake every mesh (posed, modifiers applied) into one new object.
	bm = bmesh.new()
	mats = []
	# Helper geometry some sources ship (display stand, light probe sphere).
	skip = ("Cube", "Icosphere") if name == "horse" else ()
	for o in [o for o in sc.objects if o.type == "MESH" and o.name not in skip]:
		e = o.evaluated_get(dg)
		me = bpy.data.meshes.new_from_object(e, preserve_all_data_layers=True, depsgraph=dg)
		me.transform(o.matrix_world)
		# Material indices into the joined list.
		remap = []
		for m in me.materials:
			if m not in mats:
				mats.append(m)
			remap.append(mats.index(m))
		for p in me.polygons:
			p.material_index = remap[p.material_index] if remap else 0
		bm.from_mesh(me)
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	for m in mats:
		me.materials.append(m)
	for o in list(sc.objects):
		bpy.data.objects.remove(o)
	ob = bpy.data.objects.new(name, me)
	sc.collection.objects.link(ob)
	if name == "bird_fly": # modelled upright: wings along Z, body along X
		me.transform(mathutils.Matrix(((0, 0, 1, 0), (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 0, 1))))
	# Yaw (head to +Y), then size, then feet on the origin.
	me.transform(mathutils.Matrix.Rotation(math.radians(yaw), 4, "Z"))
	vs = [v.co for v in me.vertices]
	mn = mathutils.Vector([min(v[i] for v in vs) for i in range(3)])
	mx = mathutils.Vector([max(v[i] for v in vs) for i in range(3)])
	s = mx - mn
	ref = {"len": s.y, "h": s.z, "span": max(s)}[measure]
	k = metres / ref
	c = (mn + mx) / 2
	me.transform(mathutils.Matrix.Scale(k, 4) @ mathutils.Matrix.Translation((-c.x, -c.y, -mn.z)))
	s = s * k
	print("BAKE %s size x %.2f y %.2f z %.2f, %d tris, %d materials" % (name, s.x, s.y, s.z, tris_of(ob), len(mats)))
	# Textures: max 512 px.
	for m in mats:
		if m and m.use_nodes:
			for n in m.node_tree.nodes:
				if n.type == "TEX_IMAGE" and n.image and max(n.image.size) > 512:
					w, h = n.image.size
					f2 = 512 / max(w, h)
					n.image.scale(max(1, int(w * f2)), max(1, int(h * f2)))
	bpy.context.view_layer.objects.active = ob
	ob.select_set(True)
	for lod, target in (("hi", hi), ("lo", lo)):
		cp = ob.copy()
		cp.data = ob.data.copy()
		cp.name = name + "_" + lod
		sc.collection.objects.link(cp)
		t = tris_of(cp)
		if t > target:
			mod = cp.modifiers.new("dec", "DECIMATE")
			mod.ratio = target / t
			mod.use_collapse_triangulate = True
		bpy.ops.object.select_all(action="DESELECT")
		cp.select_set(True)
		bpy.context.view_layer.objects.active = cp
		if cp.modifiers:
			bpy.ops.object.modifier_apply(modifier="dec")
		print("  %s: %d tris" % (lod, tris_of(cp)))
		bpy.ops.export_scene.gltf(filepath=os.path.join(out, "%s_%s.glb" % (name, lod)), use_selection=True,
			export_format="GLB", export_yup=True, export_apply=True, export_animations=False,
			export_image_format="JPEG", export_jpeg_quality=88)
		if lod == "hi" and prev:
			camd = bpy.data.cameras.new("c")
			cam = bpy.data.objects.new("c", camd)
			sc.collection.objects.link(cam)
			sc.camera = cam
			r = max(s) * 1.4
			cam.location = (r * 1.3, 0, s.z * 0.5) if name != "bird_fly" else (0.01, 0, r * 1.5)
			cam.rotation_euler = (mathutils.Vector((0, 0, s.z * 0.5)) - cam.location).to_track_quat("-Z", "Y").to_euler()
			l = bpy.data.objects.new("l", bpy.data.lights.new("l", "SUN"))
			l.rotation_euler = (0.7, 0.3, 1.2)
			sc.collection.objects.link(l)
			w = bpy.data.worlds.new("w")
			sc.world = w
			w.use_nodes = True
			w.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.47, 0.5, 1)
			sc.render.resolution_x, sc.render.resolution_y = 400, 300
			sc.render.filepath = os.path.join(prev, name + ".png")
			ob.hide_render = True
			bpy.ops.render.render(write_still=True)
			ob.hide_render = False
			cp.hide_render = True
