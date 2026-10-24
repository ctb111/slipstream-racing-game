"""Builds the DENSE foliage atlases used by the baked tree models (dev tool).

  <venv with pillow+numpy>/python tools/trees/build_clumps.py <acg dir>

<acg dir> holds the ambientCG CC0 leaf scans LeafSet024 (beech), LeafSet016
(oak), LeafSet009 (birch), each unzipped into <acg dir>/<id>/ (the 2K-JPG
download from https://ambientcg.com/view?id=<id>).

Outputs (same cell layout as the sparse atlases, so the generator's cell
indices keep their meaning):
  assets/vegetation/trees/leaf_clumps.png (+_normal)     4x2 cells of 1024 px:
      0-1 beech, 2-3 birch, 4-5 oak, 6-7 dense bush. Each cell is a full leaf
      MASS (hundreds of overlapping photo leaves radiating from the centre,
      self-shadowed inside, lit rim) instead of one thin spray.
  assets/vegetation/trees/conifer_clumps.png (+_normal)  4x4 cells of 1024 px:
      conifer_atlas cells re-stamped several times over themselves (rotated
      copies for the top views, offset copies for the side views, back copies
      darker) so needle masses read solid.
Normals are packed with a rounded 'clump' bias so a single card lights like a
volume.
"""
import math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../..'))
OUT = ROOT + '/assets/vegetation/trees/'
ACG = sys.argv[1] if len(sys.argv) > 1 else '.'


def dilate(img):
	"""Push-pull fill of the colour under transparent pixels (no mip fringes)."""
	a = np.asarray(img).astype(np.float32) / 255.0
	rgb, al = a[..., :3], a[..., 3:4]
	w = (al > 0.02).astype(np.float32)
	levels = [(rgb * w, w)]
	while levels[-1][1].shape[0] > 1 and levels[-1][1].shape[1] > 1:
		c, ww = levels[-1]
		h2, w2 = c.shape[0] // 2, c.shape[1] // 2
		c = c[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, 3).sum((1, 3))
		ww = ww[:h2 * 2, :w2 * 2].reshape(h2, 2, w2, 2, 1).sum((1, 3))
		levels.append((c, ww))
	fill = levels[-1][0] / np.maximum(levels[-1][1], 1e-6)
	for c, ww in reversed(levels[:-1]):
		up = np.repeat(np.repeat(fill, 2, 0), 2, 1)
		up = np.pad(up, ((0, c.shape[0] - up.shape[0]), (0, c.shape[1] - up.shape[1]), (0, 0)), mode='edge')
		own = c / np.maximum(ww, 1e-6)
		k = np.clip(ww, 0, 1)
		fill = own * k + up * (1 - k)
	out = np.concatenate([fill, al], -1)
	return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), 'RGBA')


def leaf_sprites(asset):
	"""Single leaves (stem down) cut out of an ambientCG leaf set."""
	d = f'{ACG}/{asset}/{asset}_2K-JPG_'
	col = Image.open(d + 'Color.jpg').convert('RGB')
	op = Image.open(d + 'Opacity.jpg').convert('L')
	mask = np.asarray(op) > 128
	small = mask[::4, ::4]
	lab = np.zeros(small.shape, np.int32)
	boxes = []
	cur = 0
	from collections import deque
	for y in range(small.shape[0]):
		for x in range(small.shape[1]):
			if small[y, x] and not lab[y, x]:
				cur += 1
				q = deque([(y, x)])
				lab[y, x] = cur
				y0 = y1 = y; x0 = x1 = x; n = 0
				while q:
					cy, cx = q.popleft(); n += 1
					y0, y1, x0, x1 = min(y0, cy), max(y1, cy), min(x0, cx), max(x1, cx)
					for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
						ny, nx = cy + dy, cx + dx
						if 0 <= ny < small.shape[0] and 0 <= nx < small.shape[1] and small[ny, nx] and not lab[ny, nx]:
							lab[ny, nx] = cur
							q.append((ny, nx))
				if n > 200:
					boxes.append((x0 * 4, y0 * 4, x1 * 4 + 4, y1 * 4 + 4))
	rgba = col.copy()
	rgba.putalpha(op)
	return [rgba.crop(b) for b in boxes]


def cloud_mask(px, rng, lobes, fill=0.92):
	"""Irregular cumulus-like clump outline (float mask 0..1) and its centre."""
	m = Image.new('L', (px, px), 0)
	dr = ImageDraw.Draw(m)
	cx, cy = px * 0.5, px * 0.52
	r0 = px * 0.22 * fill
	dr.ellipse([cx - r0, cy - r0, cx + r0, cy + r0], fill=255)
	for k in range(lobes):
		a = rng.uniform(0, math.tau)
		d = rng.uniform(0.14, 0.33) * px * fill
		r = rng.uniform(0.08, 0.16) * px * fill
		x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.85
		dr.ellipse([x - r, y - r, x + r, y + r], fill=255)
		# small satellites: ragged, broken outline
		for j in range(2):
			a2 = a + rng.uniform(-0.8, 0.8)
			d2 = r * rng.uniform(0.9, 1.3)
			r2 = r * rng.uniform(0.3, 0.55)
			x2, y2 = x + math.cos(a2) * d2, y + math.sin(a2) * d2
			dr.ellipse([x2 - r2, y2 - r2, x2 + r2, y2 + r2], fill=255)
	m = m.filter(ImageFilter.GaussianBlur(px * 0.012))
	return np.asarray(m).astype(np.float32) / 255.0, (cx, cy)


def leaf_clump(sprites, px, rng, tint, leaf_px, count, lobes=7, twig=(72, 58, 42)):
	alb = Image.new('RGBA', (px, px), (0, 0, 0, 0))
	nor = Image.new('RGBA', (px, px), (128, 128, 255, 0))
	mask, (cx, cy) = cloud_mask(px, rng, lobes)
	# A few twigs radiating from the attachment point (bottom centre) show in gaps.
	dr = ImageDraw.Draw(alb)
	for k in range(9):
		a = -math.pi / 2 + rng.uniform(-0.7, 0.7)
		x, y = px * 0.5 + rng.uniform(-20, 20), px * 0.96
		L = rng.uniform(0.2, 0.34) * px
		for s in range(8):
			a += rng.uniform(-0.15, 0.15)
			nx, ny = x + math.cos(a) * L / 8, y + math.sin(a) * L / 8
			dr.line([(x, y), (nx, ny)], fill=twig + (255,), width=max(2, int(7 * (1 - s / 8) * px / 1024)))
			x, y = nx, ny
	# Leaf positions: rejection-sample the clump mask.
	ys, xs = np.nonzero(mask > 0.35)
	ry, rx = np.nonzero((mask > 0.02) & (mask <= 0.35)) # ragged rim: leaves poking out
	leaves = []
	while len(leaves) < count:
		if rng.random() < 0.1:
			i = rng.randrange(len(rx))
			x, y = rx[i] + rng.uniform(-1, 1), ry[i] + rng.uniform(-1, 1)
		else:
			i = rng.randrange(len(xs))
			x, y = xs[i] + rng.uniform(-1, 1), ys[i] + rng.uniform(-1, 1)
			if rng.random() > mask[ys[i], xs[i]]:
				continue
		dx, dy = (x - cx) / (px * 0.5), (y - cy) / (px * 0.5)
		rr = math.sqrt(dx * dx + dy * dy)
		# depth: leaves near the rim sit on the outer shell (front), the middle
		# is a mix of front leaves and the dark interior.
		z = rng.random() ** (0.7 if rr > 0.5 else 1.3)
		leaves.append((x, y, z, dx, dy, rr))
	leaves.sort(key=lambda l: l[2])
	for x, y, z, dx, dy, rr in leaves:
		sp = sprites[rng.randrange(len(sprites))]
		s = leaf_px * rng.uniform(0.75, 1.2) / max(sp.size)
		sp = sp.resize((max(3, int(sp.size[0] * s)), max(3, int(sp.size[1] * s))), Image.LANCZOS)
		# tip points away from the clump centre, loosely
		out = math.degrees(math.atan2(dx, -dy)) if rr > 0.05 else rng.uniform(0, 360)
		sp = sp.rotate(-out + rng.uniform(-55, 55), expand=True, resample=Image.BICUBIC)
		top = 1.0 - (y / px)
		shade = (0.26 + 0.74 * z ** 0.8) * (0.86 + 0.24 * top)
		warm = rng.uniform(0.92, 1.08)
		arr = np.asarray(sp).astype(np.float32)
		arr[..., 0] *= tint[0] * shade * warm
		arr[..., 1] *= tint[1] * shade
		arr[..., 2] *= tint[2] * shade / warm
		sp = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA')
		pos = (int(x - sp.size[0] / 2), int(y - sp.size[1] / 2))
		alb.alpha_composite(sp, pos)
		# normal: outward (rounded clump) + per-leaf tilt
		tx = dx * 0.75 + rng.uniform(-0.35, 0.35)
		ty = -dy * 0.75 + rng.uniform(-0.35, 0.35)
		l = math.sqrt(tx * tx + ty * ty)
		if l > 0.85:
			tx, ty = tx / l * 0.85, ty / l * 0.85
		nz = math.sqrt(max(0.05, 1 - tx * tx - ty * ty))
		tile = Image.new('RGBA', sp.size, (int((tx * 0.5 + 0.5) * 255), int((ty * 0.5 + 0.5) * 255), int((nz * 0.5 + 0.5) * 255), 255))
		tile.putalpha(sp.getchannel('A'))
		nor.alpha_composite(tile, pos)
	return alb, nor


def broadleaf():
	rng = random.Random(23)
	beech = leaf_sprites('LeafSet024')
	oak = leaf_sprites('LeafSet016')
	birch = leaf_sprites('LeafSet009')
	print('sprites', len(beech), len(oak), len(birch))
	cols, rows, px = 4, 4, 1024  # rows 0-1 clumps, rows 2-3 twig sprays (detail cards)
	alb = Image.new('RGBA', (cols * px, rows * px), (0, 0, 0, 0))
	nor = Image.new('RGBA', (cols * px, rows * px), (128, 128, 255, 255))
	# (sprites, tint, leaf px, count, lobes)
	specs = [(beech, (0.86, 0.96, 0.8), 50, 1500, 9), (beech, (0.82, 0.94, 0.76), 48, 1550, 10),
			(birch, (0.95, 1.04, 0.74), 36, 2000, 11), (birch, (0.92, 1.0, 0.7), 35, 2100, 10),
			(oak, (0.74, 0.88, 0.64), 54, 1400, 9), (oak, (0.76, 0.88, 0.62), 52, 1450, 10),
			(beech, (0.72, 0.86, 0.66), 46, 1800, 11), (birch, (0.78, 0.92, 0.64), 40, 2000, 11)]
	for i, (sp, tint, lp, cnt, lobes) in enumerate(specs):
		a, n = leaf_clump(sp, px, rng, tint, lp, cnt, lobes)
		pos = ((i % cols) * px, (i // cols) * px)
		alb.paste(a, pos)
		bg = Image.new('RGBA', (px, px), (128, 128, 255, 255))
		bg.alpha_composite(n)
		nor.paste(bg, pos)
		cov = (np.asarray(a)[..., 3] > 115).mean()
		print('leaf cell', i, 'coverage %.2f' % cov)
	# Twig sprays (as in leaf_atlas, at twice the resolution) for the near detail cards.
	sys.path.insert(0, ROOT + '/assets/vegetation/_bake')
	from build_atlases import leaf_cluster
	sprays = [(beech, (0.85, 0.95, 0.8), 88, 180), (beech, (0.8, 0.92, 0.75), 80, 200),
			(birch, (0.95, 1.05, 0.75), 60, 230), (birch, (0.92, 1.0, 0.7), 56, 250),
			(oak, (0.7, 0.85, 0.62), 92, 170), (oak, (0.72, 0.86, 0.6), 84, 190),
			(beech, (0.7, 0.85, 0.65), 96, 260), (birch, (0.75, 0.9, 0.62), 80, 290)]
	for i, (sp, tint, lp, cnt) in enumerate(sprays):
		a, n = leaf_cluster(sp, px, rng, tint, lp, cnt)
		pos = ((i % cols) * px, (i // cols + 2) * px)
		alb.paste(a, pos)
		bg = Image.new('RGBA', (px, px), (128, 128, 255, 255))
		bg.alpha_composite(n)
		nor.paste(bg, pos)
	dilate(alb).save(OUT + 'leaf_clumps.png')
	nor.convert('RGB').save(OUT + 'leaf_clumps_normal.png')


def rot_normal(nimg, angle_deg):
	"""Rotates a normal-map image AND its xy vectors (PIL rotate is CCW)."""
	r = nimg.rotate(angle_deg, expand=False, resample=Image.BICUBIC)
	a = np.asarray(r).astype(np.float32)
	x = a[..., 0] / 127.5 - 1.0
	y = a[..., 1] / 127.5 - 1.0
	t = math.radians(angle_deg)
	# image y points down, normal-map y up: CCW on screen = CCW in (x, y-up)
	c, s = math.cos(t), math.sin(t)
	x2, y2 = x * c - y * s, x * s + y * c
	a[..., 0] = (x2 + 1.0) * 127.5
	a[..., 1] = (y2 + 1.0) * 127.5
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), r.mode)


def shade_img(img, k):
	a = np.asarray(img).astype(np.float32)
	a[..., :3] *= k
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')


def conifer():
	rng = random.Random(5)
	src = Image.open(OUT + 'conifer_atlas.png').convert('RGBA')
	srcn = Image.open(OUT + 'conifer_atlas_normal.png').convert('RGBA')
	px = src.size[0] // 4
	alb = Image.new('RGBA', src.size, (0, 0, 0, 0))
	nor = Image.new('RGBA', src.size, (128, 128, 255, 255))
	for i in range(16):
		box = ((i % 4) * px, (i // 4) * px, (i % 4 + 1) * px, (i // 4 + 1) * px)
		cell = src.crop(box)
		celln = srcn.crop(box)
		celln.putalpha(cell.getchannel('A'))
		out = Image.new('RGBA', (px, px), (0, 0, 0, 0))
		outn = Image.new('RGBA', (px, px), (128, 128, 255, 0))
		top = i < 6
		# sibling cells of the same kind to mix in
		group = list(range(0, 3)) if i < 3 else (list(range(3, 6)) if i < 6 else (list(range(6, 12)) if i < 12 else list(range(12, 16))))
		stamps = 7 if top else 4
		for k in range(stamps):
			j = i if k == stamps - 1 else rng.choice(group)
			b2 = ((j % 4) * px, (j // 4) * px, (j % 4 + 1) * px, (j // 4 + 1) * px)
			c = src.crop(b2)
			cn = srcn.crop(b2)
			cn.putalpha(c.getchannel('A'))
			depth = k / (stamps - 1)
			if top:
				ang = rng.uniform(0, 360) if k < stamps - 1 else 0.0
				s = rng.uniform(0.72, 0.95) if k < stamps - 1 else 1.0
				c = c.rotate(ang, resample=Image.BICUBIC)
				cn = rot_normal(cn, ang)
				off = (rng.uniform(-0.05, 0.05) * px, rng.uniform(-0.05, 0.05) * px)
				anchor = (0.5, 0.5)
			else:
				s = rng.uniform(0.85, 1.0) if k < stamps - 1 else 1.0
				ang = rng.uniform(-6, 6) if k < stamps - 1 else 0.0
				c = c.rotate(ang, resample=Image.BICUBIC, center=(px * 0.5, px * 0.98))
				cn = rot_normal(cn, ang)
				off = (rng.uniform(-0.025, 0.025) * px, rng.uniform(-0.05, 0.0) * px)
				anchor = (0.5, 0.98)
				if rng.random() < 0.5:
					c = c.transpose(Image.FLIP_LEFT_RIGHT)
					a = np.asarray(cn).astype(np.float32)
					a = a[:, ::-1].copy()
					a[..., 0] = 255.0 - a[..., 0]
					cn = Image.fromarray(a.astype(np.uint8), 'RGBA')
			if s != 1.0:
				n = int(px * s)
				c = c.resize((n, n), Image.LANCZOS)
				cn = cn.resize((n, n), Image.LANCZOS)
			pos = (int(px * anchor[0] - c.size[0] * anchor[0] + off[0]), int(px * anchor[1] - c.size[1] * anchor[1] + off[1]))
			c = shade_img(c, 0.55 + 0.45 * depth)
			out.alpha_composite(c, pos)
			outn.alpha_composite(cn, pos)
		alb.paste(out, box[:2])
		bg = Image.new('RGBA', (px, px), (128, 128, 255, 255))
		bg.alpha_composite(outn)
		nor.paste(bg, box[:2])
		print('conifer cell', i, 'coverage %.2f -> %.2f' % ((np.asarray(cell)[..., 3] > 115).mean(), (np.asarray(out)[..., 3] > 115).mean()))
	dilate(alb).save(OUT + 'conifer_clumps.png')
	nor.convert('RGB').save(OUT + 'conifer_clumps_normal.png')


if __name__ == '__main__':
	what = sys.argv[2] if len(sys.argv) > 2 else 'all'
	if what in ('all', 'leaf'):
		broadleaf()
	if what in ('all', 'conifer'):
		conifer()
