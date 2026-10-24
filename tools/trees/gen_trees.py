"""Bakes the game's tree models with Blender's Sapling Tree Gen (Weber-Penn
skeletons) into game meshes with wind weights. Dev tool, not used at runtime.

  ~/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
      --python tools/trees/gen_trees.py -- <dir containing sapling_tree_gen/> <out dir> [only=name,...]

Sapling (GPL add-on, https://extensions.blender.org/add-ons/sapling-tree-gen/)
grows the branch curves and leaf quads; this script turns them into one game
surface per LOD: bark tubes (UVs for the tiling bark, root flare, buried base)
plus alpha-tested photo spray cards from the existing atlases (leaf_atlas /
conifer_atlas). Vertex layout = scripts/world/vegetation.gd / veg_tree.gdshader:
  COLOR.r flutter, COLOR.g AO, COLOR.b 0 foliage / 0.5 bark col 0 / 1 bark col 1,
  COLOR.a branch weight (0 trunk .. 1 tip), UV2.x branch phase, UV2.y tree height.
Output per variant: <name>.bin = two LODs (near, far), each
  int32 nverts, int32 nidx, float32 pos[3n] nrm[3n] uv[2n] uv2[2n] col[4n], int32 idx[nidx]
tools/trees/import_trees.gd turns them into ArrayMesh .res files.
"""
import bpy, sys, ast, math, random, struct, os
from mathutils import Vector, Matrix, kdtree, geometry

argv = sys.argv[sys.argv.index('--') + 1:]
SAP, OUT = argv[0], argv[1]
ONLY = None
for a in argv[2:]:
	if a.startswith('only='):
		ONLY = set(a[5:].split(','))
sys.path.insert(0, SAP)
import sapling_tree_gen
sapling_tree_gen.register()

# Atlas cells: leaf_clumps 4x4 (0-1 beech, 2-3 birch, 4-5 oak, 6-7 dense bush; +8 = twig sprays),
# conifer_clumps 4x4 (0-2 fir top, 3-5 pine top, 6-11 fir side, 12-15 pine side).
def cell_rect(i, cols, rows):
	return ((i % cols) / cols, (i // cols) / rows, 1.0 / cols, 1.0 / rows)


BASE = dict(prune=False, showLeaves=True, leafShape='rect', useArm=False, makeMesh=False,
	bevel=True, bevelRes=0, resU=2, handleType='0', rMode='rotate', autoTaper=True,
	leafDist='6', leafangle=0.0, horzLeaves=False, leafScaleT=0.0, leafScaleV=0.0,
	splitByLen=True, useParentAngle=True, useOldDownAngle=False, closeTip=False,
	attractOut=(0.0, 0.0, 0.0, 0.0), curveBack=(0.0, 0.0, 0.0, 0.0), radiusTweak=(1.0, 1.0, 1.0, 1.0),
	taper=(1.0, 1.0, 1.0, 1.0), splitBias=0.0, splitHeight=0.2, scale0=1.0, scaleV0=0.1, scaleV=0.0,
	nrings=0, wind=1.0, gust=1.0, gustF=0.075, af1=1.0, af2=1.0, af3=4.0, leafRotate=137.5,
	leafRotateV=30.0, leafDownAngle=45.0, leafDownAngleV=20.0, taperCrown=0.0, baseSize_s=0.25,
	ratioPower=1.2, minRadius=0.002, customShape=(0.5, 1.0, 0.3, 0.5), shapeS='4',
	branchDist=1.0, armLevels=2, boneStep=(1, 1, 1, 1), frameRate=1.0, loopFrames=0,
	previewArm=False, armAnim=False, leafAnim=False, pruneRatio=1.0, pruneWidth=0.4,
	pruneWidthPeak=0.6, prunePowerLow=0.001, prunePowerHigh=0.5, pruneBase=0.3, leafScaleX=1.0)

# Species. 'kind': broad (sapling leaf quads as spray cards) or conifer (frond
# strips along the last-level branches). 'cells': atlas cells. 'bark': column.
SPECIES = {
	'beech': dict(kind='broad', bark=0.5, cells=[0, 1], atlas='leaf', card=1.75,
		p=dict(levels=3, shape='1', baseSize=0.28, baseSplits=0, branches=(0, 34, 10, 0),
			length=(1.0, 0.42, 0.5, 0.0), lengthV=(0.0, 0.08, 0.15, 0.0),
			downAngle=(90.0, 62.0, 45.0, 45.0), downAngleV=(0.0, -30.0, 15.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 15.0, 30.0, 0.0),
			curve=(0.0, -25.0, -15.0, 0.0), curveV=(20.0, 40.0, 60.0, 0.0), curveRes=(8, 5, 3, 1),
			segSplits=(0.0, 0.12, 0.1, 0.0), splitAngle=(0.0, 20.0, 20.0, 0.0), splitAngleV=(0.0, 5.0, 5.0, 0.0),
			attractUp=(0.0, 0.25, 0.3, 0.0), ratio=0.022, rootFlare=1.25, leaves=10, leafScale=1.0)),
	'oak': dict(kind='broad', bark=0.5, cells=[4, 5], atlas='leaf', card=1.84,
		p=dict(levels=3, shape='2', baseSize=0.22, baseSplits=0, branches=(0, 22, 9, 0),
			length=(1.0, 0.62, 0.45, 0.0), lengthV=(0.0, 0.12, 0.15, 0.0),
			downAngle=(90.0, 70.0, 45.0, 45.0), downAngleV=(0.0, -25.0, 20.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 25.0, 30.0, 0.0),
			curve=(0.0, -10.0, -10.0, 0.0), curveV=(40.0, 90.0, 90.0, 0.0), curveRes=(8, 6, 3, 1),
			segSplits=(0.1, 0.35, 0.2, 0.0), splitAngle=(8.0, 28.0, 25.0, 0.0), splitAngleV=(0.0, 8.0, 8.0, 0.0),
			attractUp=(0.0, 0.1, 0.3, 0.0), ratio=0.03, rootFlare=1.45, leaves=10, leafScale=1.0)),
	'birch': dict(kind='broad', bark=1.0, cells=[2, 3], atlas='leaf', card=1.20,
		p=dict(levels=3, shape='7', baseSize=0.3, baseSplits=0, branches=(0, 38, 10, 0),
			length=(1.0, 0.3, 0.55, 0.0), lengthV=(0.0, 0.08, 0.15, 0.0),
			downAngle=(90.0, 45.0, 55.0, 45.0), downAngleV=(0.0, -25.0, 15.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 15.0, 30.0, 0.0),
			curve=(0.0, 30.0, 50.0, 0.0), curveV=(10.0, 30.0, 40.0, 0.0), curveRes=(8, 5, 4, 1),
			segSplits=(0.0, 0.0, 0.0, 0.0), splitAngle=(0.0, 0.0, 0.0, 0.0), splitAngleV=(0.0, 0.0, 0.0, 0.0),
			attractUp=(0.0, 0.2, -0.6, 0.0), ratio=0.014, rootFlare=1.1, leaves=10, leafScale=0.85)),
	'maple': dict(kind='broad', bark=0.5, cells=[6, 7, 0], atlas='leaf', card=1.75,
		p=dict(levels=3, shape='3', baseSize=0.25, baseSplits=0, branches=(0, 30, 10, 0),
			length=(1.0, 0.45, 0.5, 0.0), lengthV=(0.0, 0.1, 0.15, 0.0),
			downAngle=(90.0, 55.0, 45.0, 45.0), downAngleV=(0.0, -30.0, 15.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 15.0, 30.0, 0.0),
			curve=(0.0, -20.0, -10.0, 0.0), curveV=(20.0, 50.0, 60.0, 0.0), curveRes=(8, 5, 3, 1),
			segSplits=(0.0, 0.2, 0.1, 0.0), splitAngle=(0.0, 25.0, 20.0, 0.0), splitAngleV=(0.0, 5.0, 5.0, 0.0),
			attractUp=(0.0, 0.3, 0.3, 0.0), ratio=0.022, rootFlare=1.25, leaves=10, leafScale=1.0)),
	'olive': dict(kind='broad', bark=0.5, cells=[4, 5, 2], atlas='leaf', card=1.10, olive=True,
		p=dict(levels=3, shape='2', baseSize=0.12, baseSplits=2, branches=(0, 16, 9, 0),
			length=(1.0, 0.7, 0.45, 0.0), lengthV=(0.0, 0.15, 0.15, 0.0),
			downAngle=(90.0, 55.0, 45.0, 45.0), downAngleV=(0.0, -20.0, 20.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 30.0, 30.0, 0.0),
			curve=(0.0, -20.0, -15.0, 0.0), curveV=(90.0, 110.0, 90.0, 0.0), curveRes=(8, 6, 3, 1),
			segSplits=(0.2, 0.4, 0.2, 0.0), splitAngle=(25.0, 30.0, 25.0, 0.0), splitAngleV=(5.0, 8.0, 8.0, 0.0),
			attractUp=(0.0, 0.0, 0.2, 0.0), ratio=0.05, rootFlare=1.6, leaves=10, leafScale=0.8)),
	'poplar': dict(kind='broad', bark=0.5, cells=[2, 3, 6], atlas='leaf', card=1.20,
		p=dict(levels=3, shape='5', baseSize=0.06, baseSplits=0, branches=(0, 46, 8, 0),
			length=(1.0, 0.3, 0.4, 0.0), lengthV=(0.0, 0.06, 0.1, 0.0),
			downAngle=(90.0, 18.0, 30.0, 45.0), downAngleV=(0.0, -5.0, 10.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 15.0, 30.0, 0.0),
			curve=(0.0, -8.0, 0.0, 0.0), curveV=(5.0, 15.0, 30.0, 0.0), curveRes=(10, 4, 2, 1),
			segSplits=(0.0, 0.0, 0.0, 0.0), splitAngle=(0.0, 0.0, 0.0, 0.0), splitAngleV=(0.0, 0.0, 0.0, 0.0),
			attractUp=(0.0, 0.6, 0.4, 0.0), ratio=0.018, rootFlare=1.2, leaves=8, leafScale=1.0)),
	'spruce': dict(kind='broad', bark=0.5, cells=[0, 1, 2], atlas='conifer', card=2.3, fir=True,
		p=dict(levels=3, shape='0', baseSize=0.08, baseSplits=0, branches=(0, 56, 8, 0),
			length=(1.0, 0.3, 0.38, 0.0), lengthV=(0.0, 0.05, 0.1, 0.0),
			downAngle=(90.0, 100.0, 50.0, 45.0), downAngleV=(0.0, -40.0, 10.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 25.0, 40.0, 0.0),
			curve=(0.0, 20.0, -20.0, 0.0), curveV=(10.0, 20.0, 30.0, 0.0), curveRes=(10, 5, 2, 1),
			segSplits=(0.0, 0.0, 0.0, 0.0), splitAngle=(0.0, 0.0, 0.0, 0.0), splitAngleV=(0.0, 0.0, 0.0, 0.0),
			attractUp=(0.0, 0.0, -0.3, 0.0), ratio=0.017, rootFlare=1.35, leaves=4, leafScale=1.0)),
	'spruce_fronds': dict(kind='conifer', bark=0.5, cells=[0, 1, 2], side=[6, 7, 8, 9, 10, 11], atlas='conifer', frond=0.8,
		p=dict(levels=2, shape='0', baseSize=0.08, baseSplits=0, branches=(0, 64, 0, 0),
			length=(1.0, 0.3, 0.0, 0.0), lengthV=(0.0, 0.05, 0.0, 0.0),
			downAngle=(90.0, 105.0, 45.0, 45.0), downAngleV=(0.0, -40.0, 0.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 25.0, 0.0, 0.0),
			curve=(0.0, 22.0, 0.0, 0.0), curveV=(10.0, 20.0, 0.0, 0.0), curveRes=(10, 5, 1, 1),
			segSplits=(0.0, 0.0, 0.0, 0.0), splitAngle=(0.0, 0.0, 0.0, 0.0), splitAngleV=(0.0, 0.0, 0.0, 0.0),
			attractUp=(0.0, 0.0, 0.0, 0.0), ratio=0.017, rootFlare=1.35, leaves=0, leafScale=0.2)),
	'pine': dict(kind='broad', bark=1.0, cells=[3, 4, 5], atlas='conifer', card=1.15, pine=True,
		p=dict(levels=3, shape='4', baseSize=0.5, baseSplits=0, branches=(0, 30, 8, 0),
			length=(1.0, 0.38, 0.45, 0.0), lengthV=(0.0, 0.12, 0.2, 0.0),
			downAngle=(90.0, 75.0, 40.0, 45.0), downAngleV=(0.0, -20.0, 20.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 30.0, 40.0, 0.0),
			curve=(0.0, 20.0, 10.0, 0.0), curveV=(25.0, 60.0, 50.0, 0.0), curveRes=(10, 5, 3, 1),
			segSplits=(0.0, 0.15, 0.1, 0.0), splitAngle=(0.0, 20.0, 20.0, 0.0), splitAngleV=(0.0, 5.0, 5.0, 0.0),
			attractUp=(0.0, 0.35, 0.5, 0.0), ratio=0.02, rootFlare=1.25, leaves=10, leafScale=1.0)),
	'stonepine': dict(kind='broad', bark=1.0, cells=[3, 4, 5], atlas='conifer', card=1.7, pine=True,
		p=dict(levels=3, shape='2', baseSize=0.55, baseSplits=1, branches=(0, 16, 9, 0),
			length=(1.0, 0.75, 0.4, 0.0), lengthV=(0.0, 0.1, 0.15, 0.0),
			downAngle=(90.0, 35.0, 30.0, 45.0), downAngleV=(0.0, -10.0, 15.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 25.0, 40.0, 0.0),
			curve=(0.0, 25.0, 0.0, 0.0), curveV=(25.0, 40.0, 40.0, 0.0), curveRes=(10, 6, 3, 1),
			segSplits=(0.1, 0.4, 0.15, 0.0), splitAngle=(15.0, 25.0, 20.0, 0.0), splitAngleV=(0.0, 5.0, 5.0, 0.0),
			attractUp=(0.0, 0.0, 0.9, 0.0), ratio=0.026, rootFlare=1.3, leaves=5, leafScale=1.0)),
	'cypress': dict(kind='broad', bark=0.5, cells=[6, 7, 8, 9, 10, 11], atlas='conifer', card=1.3, cypress=True,
		p=dict(levels=3, shape='5', baseSize=0.04, baseSplits=0, branches=(0, 55, 6, 0),
			length=(1.0, 0.16, 0.5, 0.0), lengthV=(0.0, 0.04, 0.1, 0.0),
			downAngle=(90.0, 22.0, 30.0, 45.0), downAngleV=(0.0, -5.0, 10.0, 0.0),
			rotate=(99.5, 137.5, 137.5, 137.5), rotateV=(15.0, 15.0, 30.0, 0.0),
			curve=(0.0, 0.0, 0.0, 0.0), curveV=(5.0, 10.0, 20.0, 0.0), curveRes=(10, 3, 2, 1),
			segSplits=(0.0, 0.0, 0.0, 0.0), splitAngle=(0.0, 0.0, 0.0, 0.0), splitAngleV=(0.0, 0.0, 0.0, 0.0),
			attractUp=(0.0, 0.5, 0.5, 0.0), ratio=0.02, rootFlare=1.15, leaves=4, leafScale=1.0)),
}

# Variants: (name, species, height m, seed). Heights match world_builder TREE_AGES.
VARIANTS = []
for sp, hs in [('spruce', [4.5, 8.0, 13.5, 19.0, 24.5]), ('pine', [5.0, 9.0, 14.5, 19.5, 24.0]),
		('beech', [5.5, 10.5, 16.0, 22.0]), ('oak', [5.0, 10.0, 15.0, 20.0]), ('birch', [6.0, 11.5, 17.0]),
		('maple', [6.0, 11.0, 16.0]), ('olive', [4.5, 6.5]), ('stonepine', [9.0, 14.0]), ('cypress', [8.0, 13.0]), ('poplar', [17.0, 20.0])]:
	for i, h in enumerate(hs):
		VARIANTS.append(('%s_%d' % (sp, i), sp, h, 11 + i * 7 + len(sp)))


FAR_CARDS = int(os.environ.get('FAR_CARDS', '2'))  # far LOD: outward card + one crossed per clump
KEEP = int(os.environ.get('KEEP', '3'))


def clear():
	for o in list(bpy.data.objects):
		bpy.data.objects.remove(o, do_unlink=True)
	for c in list(bpy.data.curves):
		bpy.data.curves.remove(c)
	for m in list(bpy.data.meshes):
		bpy.data.meshes.remove(m)


def smooth(a, b, x):
	t = min(1.0, max(0.0, (x - a) / (b - a)))
	return t * t * (3 - 2 * t)


class Lod:
	def __init__(self):
		self.p = []; self.n = []; self.uv = []; self.uv2 = []; self.c = []; self.idx = []

	def v(self, p, n, uv, uv2, c):
		self.p.append(p); self.n.append(n); self.uv.append(uv); self.uv2.append(uv2); self.c.append(c)
		return len(self.p) - 1

	def tris(self):
		return len(self.idx) // 3


def sample_spline(sp, steps):
	"""Bezier spline -> list of (pos, radius)."""
	bp = sp.bezier_points
	out = []
	for i in range(len(bp) - 1):
		a, b = bp[i], bp[i + 1]
		pts = geometry.interpolate_bezier(a.co, a.handle_right, b.handle_left, b.co, steps + 1)
		for k in range(steps + (1 if i == len(bp) - 2 else 0)):
			t = k / steps
			out.append((pts[k].copy(), a.radius * (1 - t) + b.radius * t))
	return out


def pick_n(n, m):
	"""m indices spread evenly over range(n), first and last included."""
	if n <= m:
		return list(range(n))
	return sorted(set(int(round(i * (n - 1) / (m - 1))) for i in range(m)))


def tube(lod, pts, sides, ws, phase, H, barkcol, ao_f, close_tip=True):
	"""Tube along pts [(pos, r)], ws = branch weight per point."""
	if len(pts) < 2:
		return
	# Arc length for bark v.
	s = [0.0]
	for i in range(1, len(pts)):
		s.append(s[-1] + (pts[i][0] - pts[i - 1][0]).length)
	t0 = (pts[1][0] - pts[0][0]).normalized()
	ref = Vector((0, 0, 1)) if abs(t0.z) < 0.9 else Vector((1, 0, 0))
	nrm = t0.cross(ref).normalized()
	rings = []
	prev_t = t0
	r0 = pts[0][1]
	reps = max(1, round(2 * math.pi * r0 / 0.7))
	for i, (p, r) in enumerate(pts):
		if i < len(pts) - 1:
			t = (pts[i + 1][0] - p).normalized()
		else:
			t = prev_t
		if i > 0:
			# parallel transport
			ax = prev_t.cross(t)
			if ax.length > 1e-6:
				ang = prev_t.angle(t)
				nrm = Matrix.Rotation(ang, 3, ax.normalized()) @ nrm
		prev_t = t
		bnm = t.cross(nrm).normalized()
		ring = []
		for k in range(sides + 1):
			a = 2 * math.pi * k / sides
			d = nrm * math.cos(a) + bnm * math.sin(a)
			pos = p + d * r
			ao = ao_f(pos)
			ring.append(lod.v(pos, d, (k / sides * reps, s[i] / 1.4), (phase, H), (0.0, ao, barkcol, ws[i])))
		rings.append(ring)
	for i in range(len(rings) - 1):
		A, B = rings[i], rings[i + 1]
		for k in range(sides):
			lod.idx += [A[k], B[k], B[k + 1], A[k], B[k + 1], A[k + 1]]


def card(lod, corners, uvs, normals, uv2s, cols):
	i = [lod.v(corners[k], normals[k], uvs[k], uv2s[k], cols[k]) for k in range(4)]
	lod.idx += [i[0], i[1], i[2], i[0], i[2], i[3]]


def build(name, spn, H, seed):
	spec = SPECIES[spn]
	clear()
	props = dict(BASE)
	props.update(spec['p'])
	props['seed'] = seed
	props['scale'] = H
	rnd = random.Random(seed)
	bpy.ops.curve.tree_add(**props)
	tree = bpy.data.objects.get('tree')
	leaves_o = bpy.data.objects.get('leaves')
	splines = list(tree.data.splines)
	# Measure, then normalise to height H.
	allz = [bp.co.z for sp in splines for bp in sp.bezier_points]
	if leaves_o:
		allz += [v.co.z for v in leaves_o.data.vertices]
	k = H / max(allz)
	conifer = spec['kind'] == 'conifer'
	near, far = Lod(), Lod()

	# Spline samples, parents, weights, phases.
	samp = []  # per spline list of (pos, r)
	for sp in splines:
		if len(sp.bezier_points) < 2:
			samp.append([])
			continue
		# trunk and thick limbs smooth, twigs coarse
		steps = 2 if (len(samp) == 0 or sp.bezier_points[0].radius * k > 0.07) else 1
		pts = [(p * k, r * k) for p, r in sample_spline(sp, steps)]
		samp.append(pts)
	n_all = sum(len(s) for s in samp)
	kd = kdtree.KDTree(max(1, n_all))
	owner = []
	for si, pts in enumerate(samp):
		for pi, (p, r) in enumerate(pts):
			kd.insert(p, len(owner))
			owner.append((si, pi))
	kd.balance()
	W = []  # weights per spline per point
	PH = []
	LV = []
	for si, pts in enumerate(samp):
		if not pts:
			W.append([]); PH.append(0.0); LV.append(0)
			continue
		if si == 0 or pts[0][0].length < 0.05 * H and pts[0][0].z < 0.1 * H:
			W.append([0.0] * len(pts)); PH.append(rnd.random()); LV.append(0)
			continue
		parent = None
		for (co, idx, dist) in kd.find_n(pts[0][0], 24):
			psi, ppi = owner[idx]
			if psi < si and samp[psi]:
				parent = (psi, ppi)
				break
		if parent is None:
			W.append([0.0] * len(pts)); PH.append(rnd.random()); LV.append(0)
			continue
		psi, ppi = parent
		w0 = W[psi][ppi]
		lv = LV[psi] + 1
		L = sum((pts[i][0] - pts[i - 1][0]).length for i in range(1, len(pts))) or 1.0
		acc = 0.0
		ws = []
		for i in range(len(pts)):
			if i:
				acc += (pts[i][0] - pts[i - 1][0]).length
			f = acc / L
			ws.append(min(1.0, w0 + (1.0 - w0) * f * (0.75 if lv == 1 else 1.0)))
		W.append(ws)
		PH.append((PH[psi] + (rnd.random() if lv == 1 else rnd.random() * 0.2)) % 1.0)
		LV.append(lv)

	# Crown envelope from the outer branch points.
	crown_pts = [p for si, pts in enumerate(samp) if LV[si] >= 1 for (p, r) in pts]
	if not crown_pts:
		crown_pts = [Vector((0, 0, H * 0.6))]
	zs = sorted(p.z for p in crown_pts)
	cz0, cz1 = zs[int(len(zs) * 0.03)], H
	cc = Vector((0, 0, (cz0 + cz1) * 0.5))
	crh = max(0.5, sorted(Vector((p.x, p.y)).length for p in crown_pts)[int(len(crown_pts) * 0.9)])
	crv = max(0.5, (cz1 - cz0) * 0.5)

	def ell(p):  # 0 at crown centre .. 1 at the envelope
		d = p - cc
		return math.sqrt((d.x / crh) ** 2 + (d.y / crh) ** 2 + (d.z / crv) ** 2)

	def ao_leaf(p):
		e = ell(p)
		return 0.4 + 0.6 * smooth(0.2, 1.0, e) * (0.75 + 0.25 * smooth(cz0, cz1, p.z))

	def ao_bark(p):
		if p.z < cz0:
			return 0.85 - 0.25 * smooth(cz0 * 0.5, cz0, p.z)
		return 0.35 + 0.5 * smooth(0.3, 1.1, ell(p))

	def crown_n(p, fn):
		d = p - cc
		o = Vector((d.x / crh, d.y / crh, d.z / crv * 0.8 + 0.25))
		if o.length < 1e-4:
			o = Vector((0, 0, 1))
		o.normalize()
		if fn.dot(o) < 0:
			fn = -fn
		return (o * 0.8 + fn * 0.2).normalized()

	barkcol = spec['bark']
	# Bark.
	for si, pts in enumerate(samp):
		if len(pts) < 2:
			continue
		lv = LV[si]
		r0 = pts[0][1]
		ws = W[si]
		ph = PH[si]
		if lv == 0:
			# Bury the base: trees stand on slopes.
			base = pts[0]
			pts2 = [(base[0] + Vector((0, 0, -0.9)), base[1] * 1.05)] + pts
			ws2 = [0.0] + ws
			sides_n = 9 if r0 > 0.2 else 7
			tube(near, pts2, sides_n, ws2, ph, H, barkcol, ao_bark)
			sel = pick_n(len(pts2), 6)
			tube(far, [pts2[i] for i in sel], 5, [ws2[i] for i in sel], ph, H, barkcol, ao_bark)
			continue
		if conifer or spec.get('fir'):
			rmin_n, rmin_f = 0.014, 0.06
		else:
			rmin_n, rmin_f = 0.011 if lv <= 1 else 0.026, 0.08
		if r0 >= rmin_n:
			sides_n = 6 if r0 > 0.12 else (4 if r0 > 0.035 else 3)
			# Trim the thin end of branches (hidden by the foliage).
			cut = [q for q in pts if q[1] > rmin_n * 0.5]
			if conifer or spec.get('fir'):
				cut = cut[:max(2, int(len(cut) * 0.75))]
			if len(cut) >= 2:
				tube(near, cut, sides_n, ws[:len(cut)], ph, H, barkcol, ao_bark)
		if r0 >= rmin_f and lv <= 1:
			ncut = len([q for q in pts if q[1] > rmin_f * 0.4])
			if ncut >= 2:
				sel = pick_n(ncut, 3)
				tube(far, [pts[i] for i in sel], 3, [ws[i] for i in sel], ph, H, barkcol, ao_bark)

	atlas_cols, atlas_rows = 4, 4  # leaf_clumps: rows 0-1 clumps, 2-3 twig sprays; conifer_clumps 4x4
	spray_off = 8 if spec['atlas'] == 'leaf' else 0

	def emit_card(lod, base, axis_u, axis_v, w, h, cell, wt, ph, scale=1.0, uvq=None):
		"""Card from base point: axis_v along the spray (base -> tip), axis_u across."""
		cu, cv, cw, ch = cell_rect(cell, atlas_cols, atlas_rows)
		w *= scale; h *= scale
		c0 = base - axis_u * (w * 0.5)
		c1 = base + axis_u * (w * 0.5)
		c2 = c1 + axis_v * h
		c3 = c0 + axis_v * h
		fn = axis_u.cross(axis_v).normalized()
		corners = [c0, c1, c2, c3]
		# small inset so neighbouring cells never bleed
		e = 0.004
		if uvq is None:
			uvq = [(0, 0), (1, 0), (1, 1), (0, 1)]
		uvs = [(cu + e + (cw - 2 * e) * a, cv + e + (ch - 2 * e) * (1 - b)) for a, b in uvq]
		ns = [crown_n(c, fn) for c in corners]
		uv2s = [(ph, H)] * 4
		cols = []
		for ci, c in enumerate(corners):
			fl = 0.35 if ci < 2 else 1.0
			cols.append((fl, ao_leaf(c), 0.0, min(1.0, wt + (0.0 if ci < 2 else 0.12))))
		card(lod, corners, uvs, ns, uv2s, cols)

	def clump_shell(pts):
		"""Fills the crown with leaf MASSES: the foliage points are binned into
		clumps (grid ~ a third of the crown radius); every clump gets a few big
		cards with the dense clump textures, facing out of the crown, with
		crossed partners so it reads from any side. The far LOD is exactly this
		shell (same cards, same colours): the near/far swap is invisible."""
		g = max(spec.get('clump_min', 0.8), min(crh, crv) * spec.get('clump', 0.42))
		bins = {}
		for p, wt, ph in pts:
			key = (int(math.floor(p.x / g)), int(math.floor(p.y / g)), int(math.floor(p.z / g)))
			bins.setdefault(key, []).append((p, wt, ph))
		cells = spec.get('clump_cells', spec['cells'])
		up = Vector((0, 0, 1))
		for key in sorted(bins):
			b = bins[key]
			if len(b) < spec.get('clump_minpts', 3):
				continue
			c = Vector((0, 0, 0))
			for p, _, _ in b:
				c += p
			c /= len(b)
			e = ell(c)
			deep = e < 0.42  # buried in the crown: nobody sees it
			# extent of the clump
			ext = max(g * 0.6, max((p - c).length for p, _, _ in b) * 1.15)
			sz = min(g * 1.9, ext * 1.25 + g * 0.55) * rnd.uniform(0.9, 1.12) * spec.get('clump_scale', 1.0)
			d = c - cc
			o = Vector((d.x / crh, d.y / crh, d.z / crv * 0.6))
			if o.length < 1e-3:
				o = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0.2))
			o.normalize()
			if spec.get('fir'):
				# spruce: the masses hang off the whorls, flat-ish and sagging
				o = (Vector((o.x, o.y, 0)).normalized() * 0.8 + Vector((0, 0, 0.6))).normalized() if Vector((o.x, o.y, 0)).length > 1e-3 else up
			wt = sum(w for _, w, _ in b) / len(b)
			ph = b[0][2]
			# card facing o (its normal), 'up' of the card mostly world-up
			av = up - o * o.dot(up)
			av = av.normalized() if av.length > 1e-3 else Vector((1, 0, 0))
			av = Matrix.Rotation(rnd.uniform(-0.45, 0.45), 3, o) @ av
			au = av.cross(o).normalized()
			ctr = c + o * sz * 0.12
			n_cards = 1 if deep else spec.get('clump_cards', 3)
			for k in range(n_cards):
				if k == 0:
					u, v = au, av
				else:
					# crossed partners: rotated about the card's up axis
					ang = (math.pi / 3.0) * (1 if k == 1 else -1) + rnd.uniform(-0.25, 0.25)
					u = Matrix.Rotation(ang, 3, av) @ au
					v = av
				cell = cells[rnd.randrange(len(cells))]
				base = ctr - v * sz * 0.5
				emit_card(near, base, u, v, sz, sz, cell, wt, ph)
				if (not deep and k < FAR_CARDS) or k == 0:
					emit_card(far, base, u, v, sz, sz, cell, wt, ph)

	leafpts = []  # (pos, weight, phase) of every foliage card: the clump shell grows from them
	if not conifer and leaves_o:
		me = leaves_o.data
		uvl = me.uv_layers.active.data if me.uv_layers.active else None
		polys = list(me.polygons)
		rnd.shuffle(polys)
		cells = spec['cells']
		keep = spec.get('keep', KEEP)  # detail cards kept (1 in keep): the clump shell does the filling
		for li, poly in enumerate(polys):
			vs = [me.vertices[i].co * k for i in poly.vertices]
			if uvl is not None:
				uv = [uvl[l].uv for l in poly.loop_indices]
			else:
				uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
			# base edge = verts with uv.y==0
			b = [vs[i] for i in range(4) if uv[i][1] < 0.5]
			t = [vs[i] for i in range(4) if uv[i][1] >= 0.5]
			if len(b) != 2 or len(t) != 2:
				continue
			base = (b[0] + b[1]) * 0.5
			tip = (t[0] + t[1]) * 0.5
			av = tip - base
			if av.length < 1e-4:
				continue
			av.normalize()
			au = (b[1] - b[0]).normalized()
			if spec.get('fir'):
				# Fir sprays seen from above (radial needle masses), centred on the
				# twig, lying roughly flat and sagging outwards like spruce foliage.
				out = Vector((base.x, base.y, 0.0))
				out = out.normalized() if out.length > 1e-3 else Vector((1, 0, 0))
				out = Matrix.Rotation(rnd.uniform(-0.5, 0.5), 3, Vector((0, 0, 1))) @ out
				av = (out + Vector((0, 0, -rnd.uniform(0.2, 0.6)))).normalized()
				au = Vector((0, 0, 1)).cross(out).normalized()
				au = Matrix.Rotation(rnd.uniform(-0.35, 0.35), 3, av) @ au
				sz = spec['card'] * (H / 18.0) ** 0.3 * rnd.uniform(0.8, 1.2)
				cell = cells[rnd.randrange(len(cells))]
				ctr = base - av * sz * 0.5
				co = kd.find(base)
				si, pi = owner[co[1]]
				wt = W[si][pi] if W[si] else 0.6
				leafpts.append((base, wt, PH[si]))
				if li % keep == 0:
					emit_card(near, ctr, au, av, sz, sz, cell, wt, PH[si])
				continue
			if spec.get('pine') or spec.get('cypress'):
				# needle tufts / scale sprays point outwards and upwards
				out = Vector((base.x, base.y, 0.0))
				out = out.normalized() if out.length > 1e-3 else Vector((1, 0, 0))
				av = (av * 0.4 + out * 0.4 + Vector((0, 0, 0.5 if spec.get('cypress') else 0.25))).normalized()
				au = av.cross(Vector((0, 0, 1)))
				au = au.normalized() if au.length > 1e-3 else Vector((1, 0, 0))
				# tilt the card around its axis for variety
				au = Matrix.Rotation(rnd.uniform(-1.1, 1.1), 3, av) @ au
			# The spray's stem sits at the bottom of its cell: start a bit inside.
			sz = spec['card'] * (H / 18.0) ** 0.35 * rnd.uniform(0.8, 1.15)
			cell = cells[rnd.randrange(len(cells))] + spray_off
			ins = base - av * sz * 0.12
			co = kd.find(base)
			si, pi = owner[co[1]]
			wt = W[si][pi] if W[si] else 0.6
			ph = PH[si]
			leafpts.append((base + av * sz * 0.4, wt, ph))
			if li % keep:
				continue
			emit_card(near, ins, au, av, sz * 0.9, sz, cell, wt, ph)
			if spec.get('pine'):
				# crossed second card: tufts read from every side
				au2 = Matrix.Rotation(math.pi * 0.5, 3, av) @ au
				emit_card(near, ins, au2, av, sz * 0.9, sz, cells[rnd.randrange(len(cells))] + spray_off, wt, ph)
	if leafpts:
		clump_shell(leafpts)
	if conifer:
		# Fronds: each branch gets a folded card strip (fir top-view sprays cut
		# as wedges, centre of the spray at the trunk) plus a hanging curtain.
		cells = spec['cells']
		side = spec['side']
		for si, pts in enumerate(samp):
			if LV[si] != 1 or len(pts) < 2:
				continue
			p0 = pts[0][0]
			p1 = pts[-1][0]
			L = (p1 - p0).length
			if L < 0.15:
				continue
			hf = p0.z / H
			ws = W[si]
			ph = PH[si]
			d = (p1 - p0).normalized()
			flat = Vector((d.x, d.y, 0.0))
			flat = flat.normalized() if flat.length > 1e-3 else Vector((1, 0, 0))
			acr = Vector((0, 0, 1)).cross(flat).normalized()
			width = max(0.35, L * spec['frond']) * rnd.uniform(0.85, 1.15)
			cell = cells[rnd.randrange(len(cells))]
			cu, cv, cw, ch = cell_rect(cell, atlas_cols, atlas_rows)
			# Folded strip in 2 halves (a roof over the branch), 2-3 segments.
			nseg = 3 if L > 2.5 else 2
			idxs = [int(round(i * (len(pts) - 1) / nseg)) for i in range(nseg + 1)]
			# Two layers: the flat frond and a narrower, steeper skirt under it.
			layers = [(0.22, 1.0, cell)] + ([(0.62, 0.7, cells[rnd.randrange(len(cells))])] if L > 1.0 else [])
			for droop, wsc, lcell in layers:
				cu, cv, cw, ch = cell_rect(lcell, atlas_cols, atlas_rows)
				for half in (-1, 1):
					prev = None
					for j, ii in enumerate(idxs):
						p = pts[ii][0]
						f = j / nseg
						wdt = wsc * width * (0.55 + 0.45 * math.sin(math.pi * min(1.0, f * 1.2 + 0.15)))
						edge = p + acr * half * wdt * 0.5 + Vector((0, 0, -wdt * droop))
						# wedge UVs: centre of spray (0.5,0.5) at the trunk, edge of the cell at the tip
						ang = math.atan2(flat.y, flat.x) * 0 + rnd.uniform(-0.05, 0.05)
						cur = (p, edge, f, ws[ii])
						if prev is not None:
							(pa, ea, fa, wa), (pb, eb, fb, wb) = prev, cur
							# uv: along -> radius 0..0.5 to the right of centre; across -> +-0.25
							def uvp(fr, side_off):
								return (cu + cw * (0.5 + 0.1 + 0.38 * fr), cv + ch * (0.5 + side_off * 0.26 * (0.5 + 0.5 * fr)))
							corners = [pa, pb, eb, ea]
							uvs = [uvp(fa, 0), uvp(fb, 0), uvp(fb, half), uvp(fa, half)]
							fn = (pb - pa).cross(ea - pa).normalized()
							ns = [crown_n(c, fn) for c in corners]
							cols = [(0.3 + 0.7 * fa, ao_leaf(pa), 0.0, wa), (0.3 + 0.7 * fb, ao_leaf(pb), 0.0, wb),
								(0.8, ao_leaf(eb), 0.0, min(1.0, wb + 0.1)), (0.8, ao_leaf(ea), 0.0, min(1.0, wa + 0.1))]
							card(near, corners, uvs, ns, [(ph, H)] * 4, cols)
						prev = cur
			# Hanging curtain under the outer half (side-view sprays, upside-down tip).
			if L > 0.8 and rnd.random() < 0.8:
				ii = len(pts) // 2
				pm = pts[ii][0]
				sc = cell_rect(side[rnd.randrange(len(side))], atlas_cols, atlas_rows)
				hh = min(1.6, 0.25 + L * 0.35)
				ww = L * 0.6
				a = pm - flat * ww * 0.5 + Vector((0, 0, 0.05))
				b = pm + flat * ww * 0.5 + Vector((0, 0, -0.05))
				corners = [a, b, b + Vector((0, 0, -hh)), a + Vector((0, 0, -hh))]
				e = 0.004
				uvs = [(sc[0] + e, sc[1] + sc[3] * 0.05), (sc[0] + sc[2] - e, sc[1] + sc[3] * 0.05),
					(sc[0] + sc[2] - e, sc[1] + sc[3] * 0.75), (sc[0] + e, sc[1] + sc[3] * 0.75)]
				fn = acr
				ns = [crown_n(c, fn) for c in corners]
				w_m = ws[ii]
				cols = [(0.6, ao_leaf(c) * 0.9, 0.0, min(1.0, w_m + 0.1)) for c in corners]
				card(near, corners, uvs, ns, [(ph, H)] * 4, cols)
			# Far LOD: one flat card per branch, every 2nd branch, wider.
			if si % 2 == 0:
				pe = p0 + (p1 - p0) * 1.05
				w2 = width * 1.6
				corners = [p0 - acr * w2 * 0.3, p0 + acr * w2 * 0.3, pe + acr * w2 * 0.5 + Vector((0, 0, -w2 * 0.3)), pe - acr * w2 * 0.5 + Vector((0, 0, -w2 * 0.3))]
				uvs = [(cu + cw * 0.5, cv + ch * 0.35), (cu + cw * 0.5, cv + ch * 0.65), (cu + cw * 0.98, cv + ch * 0.98), (cu + cw * 0.98, cv + ch * 0.02)]
				fn = Vector((0, 0, 1))
				ns = [crown_n(c, fn) for c in corners]
				cols = [(0.3, ao_leaf(corners[0]), 0.0, ws[0]), (0.3, ao_leaf(corners[1]), 0.0, ws[0]),
					(0.9, ao_leaf(corners[2]), 0.0, ws[-1]), (0.9, ao_leaf(corners[3]), 0.0, ws[-1])]
				card(far, corners, uvs, ns, [(ph, H)] * 4, cols)
		# Leader: a few upright sprays around the top metre or two.
		top = samp[0][-1][0]
		for j in range(3):
			a = j * 2.1 + rnd.random()
			au = Vector((math.cos(a), math.sin(a), 0))
			hh = min(2.2, H * 0.12)
			base = top - Vector((0, 0, hh * 0.85))
			sc = side[rnd.randrange(len(side))]
			emit_card(near, base, au, Vector((0, 0, 1)), hh * 0.8, hh, sc, 0.5, PH[0])
			if j == 0:
				emit_card(far, base, au, Vector((0, 0, 1)), hh * 0.8, hh, sc, 0.5, PH[0])
	return near, far


def write(path, lods):
	with open(path, 'wb') as f:
		for lod in lods:
			n = len(lod.p)
			f.write(struct.pack('<ii', n, len(lod.idx)))
			f.write(struct.pack('<%df' % (3 * n), *[c for p in lod.p for c in (p.x, p.z, -p.y)]))  # z-up -> y-up
			f.write(struct.pack('<%df' % (3 * n), *[c for v in lod.n for c in (v.x, v.z, -v.y)]))
			# Foliage UVs are shifted by +2 in u: veg_tree.gdshader then samples the
			# dense clump atlases (clump_tex) instead of the sparse leaf/conifer atlas.
			f.write(struct.pack('<%df' % (2 * n), *[c for v, col in zip(lod.uv, lod.c) for c in ((v[0] + 2.0) if col[2] < 0.25 else v[0], v[1])]))
			f.write(struct.pack('<%df' % (2 * n), *[c for v in lod.uv2 for c in v]))
			f.write(struct.pack('<%df' % (4 * n), *[c for v in lod.c for c in v]))
			f.write(struct.pack('<%di' % len(lod.idx), *lod.idx))


os.makedirs(OUT, exist_ok=True)
for name, sp, h, seed in VARIANTS:
	if ONLY and name not in ONLY and sp not in ONLY:
		continue
	near, far = build(name, sp, h, seed)
	write(os.path.join(OUT, name + '.bin'), [near, far])
	print('TREE %s h=%.1f near=%d far=%d tris' % (name, h, near.tris(), far.tris()))


# ---------------------------------------------------------------- preview
# preview=<png> [lod=far] : renders the built variants in a row (Cycles, CPU).
PREVIEW = next((a[8:] for a in argv[2:] if a.startswith('preview=')), None)
if PREVIEW:
	USE_FAR = 'lod=far' in argv
	TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../assets/vegetation/trees/')
	clear()
	built = []
	for name, sp, h, seed in VARIANTS:
		if ONLY and name not in ONLY and sp not in ONLY:
			continue
		near, far = build(name, sp, h, seed)
		built.append((name, sp, h, far if USE_FAR else near))
	clear()
	def mat(name, img, alpha):
		m = bpy.data.materials.new(name)
		m.use_nodes = True
		nt = m.node_tree
		bsdf = nt.nodes['Principled BSDF']
		tex = nt.nodes.new('ShaderNodeTexImage')
		tex.image = bpy.data.images.load(img)
		uvn = nt.nodes.new('ShaderNodeUVMap'); uvn.uv_map = 'uv'
		nt.links.new(uvn.outputs[0], tex.inputs[0])
		att = nt.nodes.new('ShaderNodeAttribute'); att.attribute_name = 'col'
		sep = nt.nodes.new('ShaderNodeSeparateColor')
		nt.links.new(att.outputs['Color'], sep.inputs[0])
		mul = nt.nodes.new('ShaderNodeMix'); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'
		mul.inputs[0].default_value = 1.0
		nt.links.new(tex.outputs['Color'], mul.inputs[6])
		nt.links.new(sep.outputs[1], mul.inputs[7])
		nt.links.new(mul.outputs[2], bsdf.inputs['Base Color'])
		if alpha:
			mt = nt.nodes.new('ShaderNodeMath'); mt.operation = 'GREATER_THAN'; mt.inputs[1].default_value = 0.45
			nt.links.new(tex.outputs['Alpha'], mt.inputs[0])
			nt.links.new(mt.outputs[0], bsdf.inputs['Alpha'])
			bsdf.inputs['Subsurface Weight'].default_value = 0.0
			bsdf.inputs['Transmission Weight'].default_value = 0.0
		bsdf.inputs['Roughness'].default_value = 0.85
		return m
	x = 0.0
	for name, sp, h, lod in built:
		spec = SPECIES[sp]
		me = bpy.data.meshes.new(name)
		verts = [(p.x, p.y, p.z) for p in lod.p]
		faces = [lod.idx[i:i + 3] for i in range(0, len(lod.idx), 3)]
		me.from_pydata(verts, [], faces)
		uvl = me.uv_layers.new(name='uv')
		ca = me.color_attributes.new('col', 'FLOAT_COLOR', 'POINT')
		for i, c in enumerate(lod.c):
			ca.data[i].color = (c[0], c[1], c[2], c[3])
		for poly in me.polygons:
			for li in poly.loop_indices:
				vi = me.loops[li].vertex_index
				u, v = lod.uv[vi]
				uvl.data[li].uv = (u, 1.0 - v)
		atlas = TEX + ('leaf_clumps.png' if spec['atlas'] == 'leaf' else 'conifer_clumps.png')
		barkimg = TEX + ('bark_conifer.jpg' if spec['atlas'] == 'conifer' else 'bark_broadleaf.jpg')
		me.materials.append(mat(name + 'L', atlas, True))
		me.materials.append(mat(name + 'B', barkimg, False))
		for poly in me.polygons:
			b = lod.c[poly.vertices[0]][2]
			poly.material_index = 1 if b > 0.25 else 0
			poly.use_smooth = True
		ob = bpy.data.objects.new(name, me)
		bpy.context.scene.collection.objects.link(ob)
		r = max(2.0, h * 0.32)
		x += r
		ob.location = (x, 0, 0)
		x += r + 0.5
	# ground, sun, camera
	bpy.ops.mesh.primitive_plane_add(size=400, location=(x * 0.5, 0, 0))
	gm = bpy.data.materials.new('g'); gm.use_nodes = True
	gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.12, 0.1, 0.06, 1)
	bpy.context.object.data.materials.append(gm)
	sun = bpy.data.lights.new('sun', 'SUN'); sun.energy = 4.0; sun.angle = 0.05
	so = bpy.data.objects.new('sun', sun); so.rotation_euler = (math.radians(50), 0, math.radians(-35))
	bpy.context.scene.collection.objects.link(so)
	w = bpy.data.worlds.new('w'); w.use_nodes = True
	w.node_tree.nodes['Background'].inputs[0].default_value = (0.45, 0.6, 0.85, 1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.8
	bpy.context.scene.world = w
	cam = bpy.data.cameras.new('c'); cam.lens = 35
	co = bpy.data.objects.new('c', cam)
	bpy.context.scene.collection.objects.link(co)
	hmax = max(b[2] for b in built)
	dist = max(x * 0.75, hmax * 1.6)
	co.location = (x * 0.5, -dist, hmax * 0.35)
	co.rotation_euler = (math.radians(88), 0, 0)
	if 'close' in argv:
		ob0 = bpy.data.objects[built[0][0]]
		h0 = built[0][2]
		co.location = (ob0.location.x - 3, -(h0 * 0.55 + 4), 1.6)
		dirv = Vector((ob0.location.x, 0, h0 * 0.42)) - co.location
		co.rotation_euler = dirv.to_track_quat('-Z', 'Y').to_euler()
	sc = bpy.context.scene
	sc.camera = co
	sc.render.engine = 'CYCLES'
	sc.cycles.device = 'CPU'
	sc.cycles.samples = 24
	sc.cycles.use_denoising = True
	sc.render.resolution_x = int(argv_w) if (argv_w := next((a[2:] for a in argv if a.startswith('w=')), None)) else 1600
	sc.render.resolution_y = int(sc.render.resolution_x * 0.5)
	sc.render.filepath = PREVIEW
	sc.view_settings.view_transform = 'AgX'
	bpy.ops.render.render(write_still=True)
